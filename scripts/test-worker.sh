#!/bin/bash
#
# Runs worker/test/retry.js against worker/src/index.js.
#
#     scripts/test-worker.sh
#
# Under JavaScriptCore rather than node, because node is not a dependency of
# anything else in this project and this is the only JavaScript in it. `osascript
# -l JavaScript` ships with macOS and parses and runs the same language, which is
# enough for pure functions and for a retry loop whose only ambient dependencies
# — `fetch` and `setTimeout` — the test supplies itself.
#
# What this cannot do is run the Worker runtime. `wrangler dev` is still the
# thing that proves App Check verification and the real bindings; this proves the
# part that decides whether somebody mid-argument sees an error screen.
#
set -uo pipefail
cd "$(dirname "$0")/.."

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

# `export default` is a module form JavaScriptCore will not take, and the handler
# is not what these tests drive anyway.
sed 's/^export default {/const _handler = {/' worker/src/index.js > "$scratch/worker.js"
cat worker/test/prelude.js "$scratch/worker.js" worker/test/retry.js > "$scratch/run.js"

output=$(osascript -l JavaScript "$scratch/run.js" 2>&1)
echo "$output"

if echo "$output" | grep -q "FAIL"; then
    echo
    echo "Worker tests failed."
    exit 1
fi
echo
echo "All worker tests passed."
