#!/bin/bash
#
# Run Dispute on this Mac, in the iOS Simulator, before it goes near a phone.
#
#   scripts/test-on-mac.sh          the app as this phone sees it
#   scripts/test-on-mac.sh manual   the by-hand path, with the AI off
#
# Every mode starts from a fresh install — introduction unseen, AI setting reset
# — so the first-run screen is what you land on. The AI itself needs nothing
# configured. A key of your own, if you added one, survives this: it is in the
# Keychain rather than in the app's defaults, and re-pasting it every run would
# be tedious.
#
# Set DISPUTE_SIM to choose the device. The only thing it changes is the screen
# size, which is still worth checking:
#
#   DISPUTE_SIM="iPhone 12 mini" scripts/test-on-mac.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${DISPUTE_SIM:-iPhone 17 Pro}"
MODE="${1:-default}"

# Read from the project rather than written down here.
#
# Xcode rewrites `PRODUCT_BUNDLE_IDENTIFIER` on its own — appending a digit when
# it thinks two targets collide, which it does after a signing-team change. A
# hard-coded copy then points at an app that is no longer being built: the
# install succeeds, `defaults delete` clears a domain nobody is using, and the
# launch fails with "No such file or directory" as though the simulator were
# broken. It is not, and erasing it does not help. Hours went into that once.
BUNDLE=$(xcodebuild -project Dispute.xcodeproj -scheme Dispute \
    -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ PRODUCT_BUNDLE_IDENTIFIER = /{print $2; exit}')
[ -n "$BUNDLE" ] || { echo "couldn't read the bundle identifier from the project"; exit 1; }

say() { printf "\033[1m==>\033[0m %s\n" "$1"; }

say "Building for $DEVICE"
xcodebuild -project Dispute.xcodeproj -scheme Dispute \
    -destination "platform=iOS Simulator,name=$DEVICE" \
    -quiet build

APP=$(find ~/Library/Developer/Xcode/DerivedData -name "Dispute.app" \
        -path "*Debug-iphonesimulator*" -not -path "*Index.noindex*" \
        -print -quit)
[ -n "$APP" ] || { echo "couldn't find the built app"; exit 1; }

# Resolve the name to one UDID and use that everywhere below.
#
# `booted` is not safe here. It means "the booted device" and there is usually
# more than one — two, if you are checking a large and a small screen side by
# side, which is the normal way to work on this app.
# simctl then picks one of them, and the install, the container copy and the
# launch can each pick a different one. The failure is silent and looks like the
# app ignoring its own launch arguments.
#
# Duplicate names across runtimes (an iOS 26.4 and an iOS 26.5 "iPhone 17 Pro")
# resolve to the first available one. Set DISPUTE_SIM to a UDID to be exact.
if xcrun simctl list devices | grep -q "^ *$DEVICE ("; then
    UDID=$(xcrun simctl list devices -j | python3 -c "
import json,sys
for devices in json.load(sys.stdin)['devices'].values():
    for d in devices:
        if d.get('isAvailable') and d['name'] == '$DEVICE':
            print(d['udid']); raise SystemExit
")
else
    UDID="$DEVICE"   # already a UDID
fi
[ -n "$UDID" ] || { echo "no simulator called $DEVICE"; exit 1; }

say "Booting $DEVICE ($UDID)"
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator

# `boot` returns before the device is ready to install onto.
until xcrun simctl list devices | grep -q "$UDID.*(Booted)"; do sleep 1; done

# A cold launch is what reads launch arguments. Foregrounding a process that is
# already running silently ignores them.
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
say "Installing"
xcrun simctl install "$UDID" "$APP"

# Clear the app's defaults before anything else runs, so `-freshInstall` starts
# from a genuinely fresh install. The Keychain is untouched, which is why a
# stored Gemini key survives this and the introduction does not.
xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" 2>/dev/null || true

case "$MODE" in
  manual) ARGS=(-freshInstall -forceManualMode) ;;
  *)      ARGS=(-freshInstall) ;;
esac

say "Launching (${ARGS[*]:-no flags})"
xcrun simctl launch --console-pty "$UDID" "$BUNDLE" "${ARGS[@]}"
