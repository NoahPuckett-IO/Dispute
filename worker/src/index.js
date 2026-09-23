/**
 * Dispute's model proxy.
 *
 * One job: hold the Mistral key so the phone doesn't have to, and only spend it
 * for requests that can prove they came from a real copy of the app.
 *
 * This replaced Firebase AI Logic, which did the same two things for Gemini and
 * will not proxy to anybody else. The proof of identity is unchanged — the same
 * Firebase App Check token, signed by the same Google keys, verified here
 * instead of there. Verification needs only the public half, which is why this
 * works on Firebase's free plan and Cloudflare's.
 *
 * What this is *not* is a general-purpose Mistral endpoint. A valid App Check
 * token from a patched client would otherwise buy somebody unlimited inference
 * on the app's account, so the model and the output ceiling are set here rather
 * than accepted from the caller. See `buildUpstreamBody`.
 *
 * It has since taken on a third job, which is waiting out the free tier's
 * throttling instead of forwarding it. See `RETRY_BUDGET_MS` for why a 429 here
 * is usually nothing to do with anybody's allowance being spent, and why the
 * waiting belongs on this side of the wire.
 */

const JWKS_URL = "https://firebaseappcheck.googleapis.com/v1/jwks";
const MISTRAL_URL = "https://api.mistral.ai/v1/chat/completions";

/** Biggest request body worth reading, in bytes. Two positions and a system
 *  prompt is a few kilobytes; anything past this is not this app. */
const MAX_BODY_BYTES = 128 * 1024;

/**
 * How long this is willing to keep trying upstream before giving up.
 *
 * Mistral's free tier enforces three separate limits — concurrent requests,
 * tokens per minute, and tokens per month — and the first two are *shared across
 * the whole workspace*, which is to say across every copy of this app. Two
 * people arguing at the same moment anywhere in the world is enough to make one
 * of them a 429, and that 429 clears in seconds. It is not a spent allowance and
 * it has almost nothing to do with how many people have installed this.
 *
 * Before this existed, that transient 429 was passed straight down to the phone,
 * where the app read it as `rateLimited` and put up a wall telling two people
 * mid-argument that the limit was spent. It was not spent. They were unlucky for
 * about four seconds, and the app ended their session over it.
 *
 * So the wait happens here instead. Here is the right place for two reasons:
 * this is a `wrangler deploy` rather than an App Store release, and the phone is
 * already sitting on a "reading both sides…" screen for twenty seconds — waiting
 * three more inside that is invisible, where waiting three more *after* an error
 * screen is a second thing to sit through.
 *
 * The budget is set against `CloudEngine.timeout`, which is 90 seconds. It stays
 * far under that on purpose: the crux call can itself take 30 seconds, and a
 * proxy that spent the client's whole timeout on retries would turn a recoverable
 * throttle into `timedOut`, which is a worse error because nothing above it
 * offers to carry on by hand.
 */
const RETRY_BUDGET_MS = 25_000;

/** Attempts in total, not retries after the first. Four spaced by the backoff
 *  below is about 14 seconds of trying, which covers every free-tier throttle
 *  seen so far and stops well inside the budget. */
const MAX_ATTEMPTS = 4;

/** Attempts before handing over, when there is a second model to hand over to.
 *  One retry covers a genuine blip; past that, something that will answer beats
 *  something that might. */
const ATTEMPTS_WITH_FALLBACK = 2;

/**
 * The model Workers AI runs when Mistral will not answer.
 *
 * Overridable from the dashboard rather than pinned here, and that is the whole
 * lesson of the week this was written in: a model identifier hard-coded into a
 * shipped artefact is a thing that stops working on somebody else's schedule and
 * cannot be changed without a release. This one is a variable, so trying a
 * different model is a dashboard edit.
 *
 * Verify any replacement against Cloudflare's model list before setting it — an
 * identifier that does not exist fails every request, which is the exact shape
 * of the bug this fallback was built to survive.
 */
const DEFAULT_FALLBACK_MODEL = "@cf/meta/llama-3.3-70b-instruct-fp8-fast";

/** What gets tried again. 429 is the whole reason this exists; the 5xx family is
 *  here because Mistral returns 502 and 503 under load and they clear the same
 *  way. Everything else — a rejected key, a refused prompt, a malformed body —
 *  is an answer rather than a hiccup, and trying it again just spends the
 *  person's time to print the same sentence. */
function worthRetrying(status) {
  return status === 429 || (status >= 500 && status < 600);
}

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return error(405, "method not allowed");
    }

    const token = request.headers.get("X-Firebase-AppCheck");
    if (!token) {
      // 401 rather than 403: the app maps both onto "this copy of the app was
      // turned down", but 401 is the honest code for a missing credential.
      return error(401, "missing App Check token");
    }

    try {
      await verifyAppCheck(token, env);
    } catch (cause) {
      return error(401, `App Check rejected: ${cause.message}`);
    }

    const raw = await request.text();
    if (raw.length > MAX_BODY_BYTES) {
      return error(413, "request too large");
    }

    let incoming;
    try {
      incoming = JSON.parse(raw);
    } catch {
      return error(400, "body was not JSON");
    }

    return callUpstream(buildUpstreamBody(incoming, env), env);
  },
};

/**
 * The upstream call, with the free tier's throttling waited out rather than
 * forwarded.
 *
 * Passed through rather than reshaped, as before: the app already knows how to
 * read a Mistral reply and how to turn a Mistral status code into something a
 * screen can explain, and a proxy that rewrote either would be a second place
 * for that mapping to live. What is new is only *when* it gets passed through —
 * a retryable status is slept on and tried again until the budget is gone, and
 * only the last one is sent down.
 */
/**
 * When Mistral is worth asking again, as a timestamp.
 *
 * Module scope, so it lives as long as the isolate — minutes to hours, never
 * shared between them, and gone on deploy. Deliberately not stored anywhere
 * durable: this is an optimisation, and the worst case of losing it is one
 * wasted call.
 *
 * ## Why
 *
 * Because "try Mistral first, in case they have fixed it" is the right
 * instinct and the expensive implementation. Mistral's free tier refuses
 * everything today, so asking first costs two round trips per call — six a
 * session — every session, to discover the same refusal. Setting
 * PRIMARY=cloudflare avoids that and gives up on ever noticing a fix.
 *
 * This is the middle: when Mistral refuses, stop asking for a few minutes, then
 * ask again. A fix is noticed within `MISTRAL_COOLDOWN_MS` of the next session
 * rather than instantly, which is a distinction nobody can perceive, and in
 * exchange almost every call goes straight to the model that answers.
 */
let mistralQuietUntil = 0;

/** How long to leave Mistral alone after it refuses. Long enough that a busy
 *  evening is not spent rediscovering the same 429, short enough that an
 *  account fixed at lunchtime is serving again by the afternoon. */
const MISTRAL_COOLDOWN_MS = 10 * 60 * 1000;

async function callUpstream(body, env) {
  // Which model gets asked first, as a dashboard variable rather than a decision
  // baked in here.
  //
  // Mistral's support team put the free tier in writing: "a best-effort
  // offering... capacity is prioritized for paying accounts", with no guarantee
  // any given model is reachable. On that tier, asking Mistral first is two
  // wasted round trips per call — six a session — before Cloudflare answers
  // anyway.
  //
  // But the day somebody enables pay-as-you-go, Mistral is the better model and
  // should be first again. Hard-coding either way is exactly the mistake this
  // file keeps making: a choice that is right this week, welded into something
  // that takes a release to change.
  //
  // So: set PRIMARY to "cloudflare" to skip Mistral entirely, unset it to have
  // Mistral tried first. Neither needs a deploy of anything but a variable, and
  // neither needs Apple.
  // Skipped outright, or skipped because it said no a few minutes ago and has
  // not earned another go yet. Either way Cloudflare answers, and either way a
  // failure here falls through to Mistral rather than to an error screen — an
  // unlikely model beats a certain apology.
  const restingMistral = Date.now() < mistralQuietUntil;
  if (env.PRIMARY === "cloudflare" || restingMistral) {
    const direct = await runFallback(body, env, restingMistral ? "cooldown" : "primary");
    if (direct) return direct;
  }

  const payload = JSON.stringify(body);
  const startedAt = Date.now();

  for (let attempt = 1; ; attempt++) {
    const upstream = await fetch(MISTRAL_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${env.MISTRAL_API_KEY}`,
      },
      body: payload,
    });

    if (upstream.ok) {
      // Answering clears the cooldown immediately. Whatever was wrong with the
      // account is over, and nothing should make the next session wait out a
      // timer set before it was fixed.
      mistralQuietUntil = 0;
      return new Response(upstream.body, {
        status: upstream.status,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Read rather than streamed from here down. A failure is a few hundred
    // bytes, and having it as a string is what makes both of the next two
    // things possible: logging what actually went wrong, and sending the body
    // on after the stream would otherwise have been thrown away by a retry.
    const detail = await upstream.text();
    const retryAfter = upstream.headers.get("Retry-After");

    const spent = Date.now() - startedAt;
    const wait = backoff(attempt, retryAfter);

    // How many goes Mistral gets before Cloudflare is asked instead.
    //
    // The long retry existed because there was nothing else to do: wait out the
    // throttle or hand somebody an error screen. There is something else to do
    // now, and Mistral's support team has since put the free tier's behaviour in
    // writing — it is "a best-effort offering... capacity is prioritized for
    // paying accounts", and a 429 means the model is allowed but no quota is
    // available. That is not a blip that clears in four seconds. Spending
    // twenty-five seconds discovering it, three times a session, is over a
    // minute of somebody's argument spent waiting for a refusal we can predict.
    //
    // So with a fallback wired up, Mistral gets one retry — enough for a genuine
    // transient — and then the other model answers. Without one, the old budget
    // stands, because then waiting really is all there is.
    const ceiling = env.AI ? ATTEMPTS_WITH_FALLBACK : MAX_ATTEMPTS;
    const canRetry =
      worthRetrying(upstream.status) &&
      attempt < ceiling &&
      spent + wait < RETRY_BUDGET_MS;

    // The only window onto any of this, and it is deliberately a narrow one.
    //
    // Without something here a 429 on somebody else's phone is unattributable:
    // the app says "the limit is spent" for all three of the tier's caps and
    // for the provider simply being busy, and those have different answers —
    // one is wait, one is upgrade the account.
    //
    // **Mistral's error body is not logged, and must not be.** The first
    // version of this logged 500 bytes of it, which was the obvious thing to do
    // and quietly broke a promise made in writing: the beta review notes tell
    // Apple this proxy keeps "no logs, no retention of any kind", and the app's
    // whole posture is that nothing anybody types is kept anywhere. A rate-limit
    // body is harmless prose, but a 422 from the validator can quote the field
    // it rejected, and the field it rejected is two people's argument. A log
    // line that is *usually* free of user content is not a property worth
    // relying on.
    //
    // So the body is classified and thrown away. `reason` answers the only
    // question the log exists to answer, and cannot contain anything anybody
    // wrote.
    console.log(
      JSON.stringify({
        at: "upstream",
        status: upstream.status,
        attempt,
        spent_ms: spent,
        retry_after: retryAfter,
        retrying: canRetry,
        reason: classify(detail),
      }),
    );

    if (!canRetry) {
      // Out of goes. Stop asking for a while — the next two calls of this
      // session are about to happen, and a refusal now predicts a refusal in
      // four seconds better than anything else available.
      mistralQuietUntil = Date.now() + MISTRAL_COOLDOWN_MS;

      // Before handing two people an error screen, try the model that runs here.
      const fallback = await runFallback(body, env, classify(detail));
      if (fallback) return fallback;

      const headers = { "Content-Type": "application/json" };
      // Forwarded so the phone can wait the length it was actually told to
      // wait rather than a length this guessed.
      if (retryAfter) headers["Retry-After"] = retryAfter;
      return new Response(detail, { status: upstream.status, headers });
    }

    await sleep(wait);
  }
}

/**
 * The second model, running on Cloudflare, for when the first one will not.
 *
 * ## Why this exists
 *
 * Because the app spent six weeks on the App Store unable to reach a model at
 * all, and there was nothing it could do about that from the phone. The account
 * it depends on began refusing every request after a single session, and every
 * copy of the app — including the one already shipped, which cannot be changed
 * without Apple — was dead in the water for the one thing it is for.
 *
 * A proxy is the only part of this system that can be fixed in thirty seconds
 * for everybody at once. So the proxy is where the answer belongs: if the
 * provider will not answer, run something that will, here, and let the session
 * finish. Workers AI needs no key and no card — it is a binding on the account
 * this Worker already runs on.
 *
 * ## What it costs, honestly
 *
 * A smaller model. `CloudEngine` is blunt about what that means: a small model
 * "produces something well-formed and shallow, and two people who have just
 * typed out a real disagreement can tell immediately". The crux is the product,
 * and this will write a worse one.
 *
 * It is still the right trade. A worse crux is a session that finishes. The
 * alternative on offer is a screen apologising, which is what everybody has had
 * since launch.
 *
 * ## What it must never become
 *
 * Silent in the way that matters. The app tells people what leaves their phone
 * and who reads it, on a screen Apple reviews under 5.1.2(i), and Cloudflare is
 * already named there as the operator of this proxy — so content arriving here
 * is disclosed. What must stay true is the sentence about *who runs the model*,
 * which is why `modelDisplayName` names no model and the listing names no
 * provider beyond the company. Anything stronger than that becomes false the
 * moment this function runs.
 *
 * Returns `null` rather than throwing when it cannot help — no binding
 * configured, or the model gave nothing usable — so the caller falls through to
 * the honest error it was already about to send.
 */
async function runFallback(body, env, reason) {
  // No binding means this Worker was deployed without the AI binding attached,
  // which is the state every deployment before this one was in. Not an error:
  // the caller simply carries on and reports what Mistral said.
  if (!env.AI) return null;

  const model = env.FALLBACK_MODEL || DEFAULT_FALLBACK_MODEL;
  try {
    const result = await env.AI.run(model, {
      messages: body.messages,
      max_tokens: body.max_tokens,
      temperature: body.temperature,
      // The app parses the reply as JSON and `CloudEngine.decodeJSON` is
      // forgiving, but asking is free and Workers AI implements the same
      // `response_format` OpenAI does.
      response_format: { type: "json_object" },
    });

    // Workers AI answers `{response}` for most text models and the OpenAI shape
    // for some. Both are read here, because which one you get depends on the
    // model string and that is a dashboard variable.
    const raw = result?.response ?? result?.choices?.[0]?.message?.content;
    const content = typeof raw === "string" ? raw : raw ? JSON.stringify(raw) : null;
    if (!content) {
      console.log(JSON.stringify({ at: "fallback", model, ok: false, why: "empty" }));
      return null;
    }

    console.log(JSON.stringify({ at: "fallback", model, ok: true, after: reason }));

    // Reshaped into the envelope the app already decodes. The app is not told
    // which model answered and has no way to ask, which is exactly why nothing
    // user-facing is allowed to name one.
    return new Response(
      JSON.stringify({
        choices: [{ message: { content }, finish_reason: "stop" }],
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (cause) {
    // A failed fallback must not replace the real error with a worse one. The
    // caller still has Mistral's answer and will send that.
    console.log(
      JSON.stringify({ at: "fallback", model, ok: false, why: String(cause).slice(0, 200) }),
    );
    return null;
  }
}

/**
 * Which kind of "no" this was, as one word from a fixed list.
 *
 * Matched against the body but never quoting it, so nothing a person typed can
 * reach a log line. The list is the set of answers that differ: `rate-limit`
 * clears by waiting and is what the retry above is for; `quota` does not clear
 * by waiting and means the account needs pay-as-you-go; `capacity` is Mistral
 * being busy rather than anything to do with this account; `auth` is the key.
 * Anything else is `other`, which is the signal to go and look at Mistral's
 * dashboard rather than to guess from here.
 */
function classify(body) {
  const text = String(body).toLowerCase();
  if (text.includes("rate limit") || text.includes("too many requests")) {
    return "rate-limit";
  }
  if (text.includes("quota") || text.includes("credit") || text.includes("billing")) {
    return "quota";
  }
  // Order matters here, and getting it wrong twice is how this ended up with
  // tests. Mistral's support team named the two that look alike:
  //
  //   403 tier_not_allowed  — the model is not on this plan at all
  //   429 capacity exceeded — it is on this plan, there is just none spare
  //
  // Opposite meanings, opposite fixes, and the second one's message is "Service
  // tier capacity exceeded for this model" — which contains both "tier" and
  // "model". Matching on either word folded the two together. So the plan
  // problem is matched on its exact code, and everything else falls through to
  // the capacity test below it.
  //
  // There used to be a "model-unavailable" branch here, on the belief that a 429
  // mentioning a model meant the identifier was unusable. Mistral says
  // otherwise: a 429 always means allowed-but-unavailable. The branch was a
  // guess, it was wrong, and `tier-not-allowed` is the real version of it.
  if (text.includes("tier_not_allowed")) {
    return "tier-not-allowed";
  }
  if (text.includes("capacity") || text.includes("overloaded") || text.includes("busy")) {
    return "capacity";
  }
  if (text.includes("unauthorized") || text.includes("api key") || text.includes("invalid key")) {
    return "auth";
  }
  return "other";
}

/**
 * How long to wait before trying again, in milliseconds.
 *
 * `Retry-After` first, because a number the provider chose beats a number this
 * made up — Mistral sends it in seconds, and the HTTP-date form is accepted too
 * because the spec allows it and reading both costs three lines.
 *
 * Failing that, exponential with full jitter: 1s, 2s, 4s, each multiplied by a
 * random fraction. The jitter is not decoration. Every phone that hit the same
 * throttle is waiting on the same clock, and a fixed backoff marches all of them
 * back into the limit together on the same second — which is how a throttle that
 * would have cleared once becomes a throttle that clears, re-trips, and clears
 * again.
 */
function backoff(attempt, retryAfter) {
  if (retryAfter) {
    const seconds = Number(retryAfter);
    if (Number.isFinite(seconds) && seconds >= 0) return seconds * 1000;
    const date = Date.parse(retryAfter);
    if (Number.isFinite(date)) return Math.max(0, date - Date.now());
  }
  return Math.random() * 1000 * 2 ** (attempt - 1);
}

/** Waiting is not CPU time, which is what the free plan meters. */
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * What actually gets sent upstream.
 *
 * The messages are the caller's. Everything that costs money is ours: the model
 * is pinned to what the app was tuned and scored against, and `max_tokens` is
 * clamped so a single request cannot eat the day's allowance.
 */
function buildUpstreamBody(incoming, env) {
  const ceiling = Number(env.MAX_OUTPUT_TOKENS ?? 2000);
  const asked = Number(incoming.max_tokens ?? ceiling);
  return {
    messages: incoming.messages,
    model: env.MODEL,
    temperature: incoming.temperature ?? 0.3,
    max_tokens: Math.min(Number.isFinite(asked) ? asked : ceiling, ceiling),
    response_format: incoming.response_format ?? { type: "json_object" },
  };
}

// MARK: - App Check

/**
 * Verifies a Firebase App Check token.
 *
 * Checks the signature against Google's published keys, then the three claims
 * that make the signature mean anything: that Google issued it, that it was
 * issued for *this* Firebase project, and that it has not expired. A token that
 * passes all four came from a device Apple's App Attest vouched for, running a
 * build signed with this app's identity.
 */
async function verifyAppCheck(token, env) {
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("not a JWT");

  const header = JSON.parse(decodeText(parts[0]));
  const payload = JSON.parse(decodeText(parts[1]));

  if (header.alg !== "RS256") throw new Error(`unexpected alg ${header.alg}`);

  const key = await publicKey(header.kid);
  const signed = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    decodeBytes(parts[2]),
    signed,
  );
  if (!valid) throw new Error("bad signature");

  const project = env.FIREBASE_PROJECT_NUMBER;
  const audiences = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!audiences.includes(`projects/${project}`)) {
    throw new Error("wrong audience");
  }
  if (payload.iss !== `https://firebaseappcheck.googleapis.com/${project}`) {
    throw new Error("wrong issuer");
  }
  if (typeof payload.exp !== "number" || payload.exp * 1000 <= Date.now()) {
    throw new Error("expired");
  }
}

/**
 * Google's signing key for a given `kid`, imported for verification.
 *
 * Cached in module scope, which on Workers means "for the life of this isolate"
 * — long enough that the common request does no extra fetch, short enough that
 * a rotated key is picked up without anybody deploying anything. A miss falls
 * through to a fresh fetch, so rotation costs one slow request rather than an
 * outage.
 */
let jwksCache = null;

async function publicKey(kid) {
  let key = jwksCache?.[kid];
  if (!key) {
    const response = await fetch(JWKS_URL, {
      cf: { cacheTtl: 3600, cacheEverything: true },
    });
    if (!response.ok) throw new Error("could not fetch Google's keys");
    const { keys } = await response.json();
    jwksCache = Object.fromEntries(keys.map((k) => [k.kid, k]));
    key = jwksCache[kid];
  }
  if (!key) throw new Error(`no key for kid ${kid}`);

  return crypto.subtle.importKey(
    "jwk",
    { kty: key.kty, n: key.n, e: key.e, alg: "RS256", ext: true },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );
}

// MARK: - Odds and ends

/** base64url, which is not what atob takes. */
function decodeBytes(segment) {
  const padded = segment.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(padded.padEnd(Math.ceil(padded.length / 4) * 4, "="));
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

function decodeText(segment) {
  return new TextDecoder().decode(decodeBytes(segment));
}

/** The error envelope the app already knows how to read. */
function error(status, message) {
  return new Response(JSON.stringify({ error: { message } }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
