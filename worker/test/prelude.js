// The ambient things the Worker runtime provides and JavaScriptCore does not.
//
// `setTimeout` is the interesting one: it does not exist here, so it is stubbed
// to record the wait and fire immediately. That is what a test wants anyway —
// the question is never "did it really sleep four seconds", it is "how long did
// it decide to sleep, and did it decide to sleep at all".

var waits = [];
this.setTimeout = function (fn, ms) {
  waits.push(ms);
  fn();
};

var calls = 0;
var script = [];

// One scripted reply per call, falling back to `script.fallback` once the script
// runs out — which is how "throttled forever" is expressed.
this.fetch = function () {
  calls++;
  var reply = script.shift() || script.fallback;
  return Promise.resolve({
    ok: reply.status >= 200 && reply.status < 300,
    status: reply.status,
    body: null,
    text: function () {
      return Promise.resolve(reply.body || "{}");
    },
    headers: {
      get: function (name) {
        return name === "Retry-After" ? reply.retryAfter || null : null;
      },
    },
  });
};

this.Response = function (body, init) {
  this.body = body;
  this.status = (init || {}).status;
  this.headers = (init || {}).headers;
};

// Present so the module's top level evaluates; App Check is not what these test.
this.crypto = { subtle: {} };
