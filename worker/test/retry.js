// What the proxy does when Mistral says "not right now".
//
// The bug these were written for was live on the App Store: a 429 was forwarded
// to the phone, the phone read it as `rateLimited`, and two people mid-argument
// were told the shared allowance was spent. Usually it was not. The free tier
// caps requests in flight and tokens per minute across the whole workspace, so
// one other person arguing at the same moment was enough — and it cleared in
// seconds.

var results = [];

function check(name, ok) {
  results.push((ok ? "PASS  " : "FAIL  ") + name);
}

// MARK: - Which statuses come back on their own

check("429 is retried", worthRetrying(429) === true);
check("503 is retried", worthRetrying(503) === true);
check("502 is retried", worthRetrying(502) === true);
// An answer rather than a hiccup. Asking again prints the same sentence twice.
check("401 is not retried", worthRetrying(401) === false);
check("422 is not retried", worthRetrying(422) === false);
check("400 is not retried", worthRetrying(400) === false);

// MARK: - How long it waits

check("Retry-After in seconds is obeyed", backoff(1, "7") === 7000);
check("first backoff is under a second", backoff(1, null) <= 1000);
check("third backoff is under four seconds", backoff(3, null) <= 4000);
check("an unreadable Retry-After falls back", backoff(1, "soon") <= 1000);

// The jitter matters more than the exponent. Every phone that hit the same
// throttle is waiting on the same clock, and a fixed backoff walks all of them
// into the limit again on the same second.
var seen = {};
for (var i = 0; i < 40; i++) {
  seen[backoff(2, null)] = true;
}
check("the backoff is jittered", Object.keys(seen).length > 1);

// MARK: - The loop

var env = { MISTRAL_API_KEY: "test" };

calls = 0;
waits = [];
script = [{ status: 429, retryAfter: "0" }, { status: 200 }];

callUpstream({ messages: [] }, env)
  .then(function (response) {
    check("a throttle that clears becomes an answer", response.status === 200);
    check("...having asked twice", calls === 2);

    calls = 0;
    script = [];
    script.fallback = {
      status: 429,
      retryAfter: "0",
      body: '{"message":"Requests rate limit exceeded"}',
    };
    return callUpstream({ messages: [] }, env);
  })
  .then(function (response) {
    // The message has to survive. A throttle that outlasts the budget is one
    // somebody genuinely has to be told about.
    check("a throttle that never clears is still forwarded", response.status === 429);
    check("...stopping at the attempt ceiling", calls === MAX_ATTEMPTS);
    check("...with Retry-After passed on", response.headers["Retry-After"] === "0");

    calls = 0;
    script = [];
    script.fallback = { status: 401, body: '{"message":"bad key"}' };
    return callUpstream({ messages: [] }, env);
  })
  .then(function (response) {
    check("a rejected key is asked once", calls === 1);
    check("...and its body is forwarded unchanged", response.body === '{"message":"bad key"}');

    // Overrunning the client's 90-second timeout does not buy a longer wait, it
    // buys `timedOut` — whose screen does not offer to carry on by hand.
    calls = 0;
    waits = [];
    script = [];
    script.fallback = { status: 429, retryAfter: "600" };
    return callUpstream({ messages: [] }, env);
  })
  .then(function () {
    check("a wait past the budget is declined", calls === 1);
    check("...rather than taken", waits.length === 0);

    // MARK: - What reaches a log line
    //
    // The beta review notes promise Apple this proxy keeps no logs and retains
    // nothing. `classify` is what makes that true while still answering the one
    // question the log exists for, so it is tested rather than trusted.
    check("a rate limit is named", classify('{"message":"Requests rate limit exceeded"}') === "rate-limit");
    check("a spent quota is named", classify('{"message":"quota exceeded"}') === "quota");
    check("a busy provider is named", classify('{"message":"Service tier capacity exceeded"}') === "capacity");
    check("a bad key is named", classify('{"message":"Unauthorized"}') === "auth");
    check("anything else is 'other'", classify('{"message":"???"}') === "other");

    // Mistral's support team named these two, and they mean opposite things:
    // tier_not_allowed is "not on your plan", capacity is "on your plan, none
    // spare". Note that the capacity message contains the word "tier", which is
    // why the match above is on the exact code and not on a bare word.
    check(
      "tier_not_allowed is its own reason",
      classify('{"message":"tier_not_allowed","type":"invalid_request_error"}') === "tier-not-allowed"
    );
    check(
      "'Service tier capacity exceeded' is still capacity",
      classify('{"message":"Service tier capacity exceeded for this model."}') === "capacity"
    );

    // The one that matters. Whatever two people wrote, none of it comes back.
    var argued = '{"detail":[{"msg":"invalid: he never does the washing up and I am sick of it"}]}';
    var line = JSON.stringify({ reason: classify(argued) });
    check("no user content survives classification", line.indexOf("washing up") === -1);
    check("...and it still classifies", classify(argued) === "other");

    // MARK: - The Mistral cooldown
    //
    // "Try Mistral first in case they fixed it" is right, and asking on every
    // single call is how it gets expensive: three calls a session, two attempts
    // each, all to rediscover the same refusal. After one refusal Mistral is
    // left alone for a few minutes and Cloudflare answers directly.
    calls = 0;
    script = [];
    script.fallback = { status: 429, body: '{"message":"Rate limit exceeded"}' };
    return callUpstream({ messages: [] }, { MISTRAL_API_KEY: "x", AI: fakeAI() })
      .then(function () {
        var afterFirst = calls;
        calls = 0;
        return callUpstream({ messages: [] }, { MISTRAL_API_KEY: "x", AI: fakeAI() })
          .then(function (res) {
            // Not asserting that the *first* call reached Mistral: the
            // permanent-throttle test above already tripped the cooldown, and
            // it is module state that outlives a single case. That is the
            // behaviour under test, not a flaw in it.
            check("once refused, Mistral is not asked again", calls === 0);
            check("...and Cloudflare answers instead", res.status === 200);
            check("...having been asked on the earlier call too", afterFirst === 0);
          });
      })
      .then(function () {
        console.log(results.join("\n"));
      });
  });

// A stand-in for the Workers AI binding.
function fakeAI() {
  return {
    run: function () {
      return Promise.resolve({ response: '{"question":"anything"}' });
    },
  };
}

// osascript prints the value of the last expression; this keeps the promise
// chain above out of the output.
undefined;
