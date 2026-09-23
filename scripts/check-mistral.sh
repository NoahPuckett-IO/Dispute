#!/bin/bash
#
# Confirms the Mistral side of the app before anything is built against it.
#
#     MISTRAL_API_KEY=… scripts/check-mistral.sh
#
# Three questions, in the order they can break, each one worth its own answer:
#
#   1. Does the key work at all?
#   2. Is the pinned model identifier still a thing Mistral serves? A dated id
#      is a promise the provider made and can retire, and the failure mode is
#      every request 404ing on a screen two people are waiting at.
#   3. Does a real request come back as JSON in the shape the app decodes?
#
# The third is the one unit tests cannot reach. Everything in DisputeCore would
# pass just as happily against an endpoint that no longer exists.
#
set -uo pipefail

MODEL=$(grep -o 'public static let model = "[^"]*"' \
    DisputeCore/Sources/DisputeCore/CloudEngine.swift | cut -d'"' -f2)

if [ -z "${MISTRAL_API_KEY:-}" ]; then
    echo "Set MISTRAL_API_KEY first. Get one at https://console.mistral.ai/api-keys"
    exit 1
fi

echo "Model pinned in CloudEngine.swift: $MODEL"
echo

# 1 + 2. The catalogue, which answers "is the key good" and "is the id real" in
# one call and without spending any tokens.
echo "--- Models on this key ---"
models=$(curl -sS -w '\n%{http_code}' https://api.mistral.ai/v1/models \
    -H "Authorization: Bearer $MISTRAL_API_KEY")
status=$(echo "$models" | tail -1)
body=$(echo "$models" | sed '$d')

if [ "$status" != "200" ]; then
    echo "The key was refused (HTTP $status):"
    echo "$body"
    exit 1
fi

echo "$body" | python3 -c '
import json, sys
ids = sorted(m["id"] for m in json.load(sys.stdin)["data"])
for i in ids:
    print(" ", i)
' || { echo "Could not read the model list"; exit 1; }

echo
if echo "$body" | grep -q "\"$MODEL\""; then
    echo "OK — $MODEL is served on this key."
else
    echo "PROBLEM — $MODEL is NOT in the list above."
    echo "Pick one that is and change CloudEngine.model AND worker/wrangler.toml."
    exit 1
fi

# 3. One real request, in the shape the app sends, checked for the shape the app
# decodes. Cheap: a few dozen tokens against an allowance of a billion a month.
echo
echo "--- One real request ---"
reply=$(curl -sS https://api.mistral.ai/v1/chat/completions \
    -H "Authorization: Bearer $MISTRAL_API_KEY" \
    -H 'Content-Type: application/json' \
    -d "{
        \"model\": \"$MODEL\",
        \"messages\": [
            {\"role\": \"system\", \"content\": \"Answer only with JSON.\"},
            {\"role\": \"user\", \"content\": \"Return JSON: {\\\"ok\\\": true}\"}
        ],
        \"temperature\": 0.3,
        \"max_tokens\": 100,
        \"response_format\": {\"type\": \"json_object\"}
    }")

echo "$reply" | python3 -c '
import json, sys
try:
    r = json.load(sys.stdin)
except Exception:
    print("The reply was not JSON at all:"); print(sys.stdin.read()); sys.exit(1)

if "error" in r or "message" in r and "choices" not in r:
    print("Refused:", json.dumps(r)[:400]); sys.exit(1)

content = r["choices"][0]["message"]["content"]
finish  = r["choices"][0].get("finish_reason")
usage   = r.get("usage", {})
print("  content     :", content.strip()[:120])
print("  finish      :", finish)
print("  tokens      :", usage.get("prompt_tokens"), "in /", usage.get("completion_tokens"), "out")
json.loads(content)   # the app does this too, and it is the part that matters
print("\nOK — the reply parsed as JSON. The wire format is right.")
' || exit 1
