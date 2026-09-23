# The model proxy

Holds the Mistral key so the phone doesn't have to, and only spends it on
requests carrying a valid Firebase App Check token.

This is what replaced Firebase AI Logic. That did two jobs — held Google's
credential, and made the Gemini call — and Firebase will not proxy to a provider
that isn't Google's. So the second job moved here, and the first job moved to a
Cloudflare secret.

**App Check did not change.** Same token, same Google signing keys, same App
Attest on the device, same entitlement in the app. It is verified here instead of
inside Firebase, which needs only the public half of the key and therefore no
billing plan on either side.

## Deploying it

Free plan throughout: 100,000 requests a day, and this app is three requests per
session.

```sh
npm install -g wrangler     # once
cd worker
wrangler login              # opens a browser
wrangler secret put MISTRAL_API_KEY    # paste the key, it is never written to disk
wrangler deploy
```

`wrangler deploy` prints the URL. Take it, add `/`, and put it in
`HostedEngine.endpointString`:

```swift
private static let endpointString = "https://dispute-ai.<your-subdomain>.workers.dev/"
```

Until that string is filled in, `HostedEngine.isConfigured` is false and the app
behaves exactly as it does in a build with no `GoogleService-Info.plist` — the
by-hand path, offered honestly on the first screen. That is deliberate: a
placeholder URL that resolves to nothing would fail on the third screen of
somebody's argument instead.

## Checking it works

Without a token, which should be refused:

```sh
curl -i -X POST https://dispute-ai.<your-subdomain>.workers.dev/ \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"hello"}]}'
# HTTP/2 401
# {"error":{"message":"missing App Check token"}}
```

A 401 here is the whole point of the thing. If this returns a model's answer,
the token check is not running and the endpoint is an open Mistral proxy — stop
and fix that before shipping.

With a token: run the app on a device. `DEBUG` builds use Firebase's debug
provider, which prints a token on first launch to be registered once in the
Firebase console under App Check. Release builds use App Attest and need no
registration.

## What it enforces

| Check | Why |
|---|---|
| `POST` only | Nothing else has a body worth reading. |
| Valid App Check JWT | Signature against Google's JWKS, plus issuer, audience and expiry. |
| `aud` is `projects/792932176138` | A token minted for somebody else's Firebase project is not this app. |
| Body ≤ 128 KB | Two positions and a system prompt is a few kilobytes. |
| `model` forced to `env.MODEL` | The caller does not get to choose what the account pays for. |
| `max_tokens` clamped | One request cannot eat the day's allowance. |

The last two are the ones that matter if somebody patches the app. App Check
proves the *app* is real; it cannot prove the app is unmodified in every respect,
so anything that costs money is decided here rather than accepted from the wire.

## When Mistral says no

A 429 from the free tier is usually not what the word "limit" makes it sound
like. Three things are capped — requests in flight at once, tokens per minute,
and tokens per month — and the first two belong to the **workspace**, which is to
say to every copy of the app at once. Two people arguing simultaneously anywhere
in the world can turn one of them into a 429 that clears a few seconds later.
Install count has very little to do with it.

Forwarded as-is, that became `rateLimited` on the phone, and `rateLimited` puts a
wall in front of two people telling them the shared allowance is spent. It was
not spent.

So a 429 or a 5xx is now retried here — up to four attempts inside a 25-second
budget, honouring `Retry-After` when Mistral sends one and backing off
exponentially with jitter when it doesn't. The budget is well under the app's
90-second timeout on purpose: overrunning it produces `timedOut`, whose screen
does not offer to carry on by hand. `ModelTransport.retryDelay` does the same
thing on the phone for the own-key path, and measures its budget from the start
of the call, so a request the Worker already spent 25 seconds retrying is not
retried all over again.

**Retrying absorbs a throttle. It does not create capacity.** If the logs below
show 429s that survive all four attempts, the answer is the account rather than
the code — Mistral's free mode is documented as being for evaluation and
prototyping, and enabling pay-as-you-go moves the workspace to Tier 1 with
limits meant for something that ships.

## Watching it

```sh
wrangler tail
```

Every non-2xx from Mistral logs one JSON line: the status, which attempt it was,
how long the call had been running, the `Retry-After` it sent, whether it was
retried, and a one-word `reason` — `rate-limit`, `quota`, `capacity`, `auth` or
`other`. That last field is the point. The app says "the limit is spent" for all
three of the tier's caps and for the provider simply being busy, and those have
different answers: `rate-limit` clears by waiting, `quota` needs pay-as-you-go,
`capacity` is nothing to do with this account at all.

**Mistral's error body is deliberately not logged.** The first version of this
logged 500 bytes of it, which broke a promise the beta review notes make to Apple
in writing — that this proxy retains nothing. A rate-limit body is harmless
prose, but a 422 from the validator can quote the field it rejected, and that
field is two people's argument. `classify()` reads the body, returns one word
from a fixed list, and throws the rest away.

## Rotating the key

```sh
wrangler secret put MISTRAL_API_KEY   # overwrites
```

No app release needed — the phone never had it.
