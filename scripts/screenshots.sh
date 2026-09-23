#!/bin/bash
# Takes the App Store / TestFlight screenshots, at the exact pixel size Apple
# asks for, from a simulator that is that size natively.
#
#     scripts/screenshots.sh
#
# 6.5-inch is 1242 x 2688, which is an iPhone 11 Pro Max — so the shots come out
# at the right size rather than being resized into it afterwards. That device
# type only exists in older runtimes; iOS 17.2 is what this uses, and the app's
# deployment target is 17.0, so it builds.
#
# Three things this handles that a screenshot taken by hand does not:
#
#   - Every screen after the first needs a seeded session, because reaching the
#     crux for real takes two people, fifteen minutes and a live model.
#   - Seeds are `#if DEBUG`, so these are debug builds, which put a beetle beside
#     the gear on every screen. `-screenshotMode` hides it.
#   - The status bar is overridden to 9:41 with full bars, which is what Apple's
#     own screenshots show and what stops a listing looking like a phone at 14%.
#
# Output: Beta App Review/screenshots/6.5-inch/
set -euo pipefail

cd "$(dirname "$0")/.."

# Size is overridable, because Apple moved the required iPhone screenshot from
# the 6.5-inch slot to the 6.9-inch one and both may be asked for. The defaults
# below are unchanged — running this with no environment set still produces the
# 6.5-inch set exactly as before. For 6.9-inch:
#
#     DISPUTE_SHOT_SIZE=6.9 scripts/screenshots.sh
#
# 6.9-inch is 1320 x 2868, which is an iPhone 16 Pro Max, and it exists in the
# iOS 26.5 runtime — so unlike the 6.5-inch set it needs no old runtime
# downloaded to shoot it natively.
case "${DISPUTE_SHOT_SIZE:-6.5}" in
  6.9)
    DEFAULT_NAME="Dispute 6.9in"
    DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max"
    RUNTIME="${DISPUTE_SHOT_RUNTIME:-com.apple.CoreSimulator.SimRuntime.iOS-26-5}"
    OUT="Beta App Review/screenshots/6.9-inch"
    EXPECT="1320 2868"
    ;;
  6.5)
    DEFAULT_NAME="Dispute 6.5in"
    DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-11-Pro-Max"
    RUNTIME="${DISPUTE_SHOT_RUNTIME:-com.apple.CoreSimulator.SimRuntime.iOS-17-2}"
    OUT="Beta App Review/screenshots/6.5-inch"
    EXPECT="1242 2688"
    ;;
  *)
    echo "DISPUTE_SHOT_SIZE must be 6.5 or 6.9" >&2; exit 1 ;;
esac

DEVICE_NAME="${DISPUTE_SHOT_SIM:-$DEFAULT_NAME}"
BUNDLE_ID="com.jamesgpuckett.Dispute"
DERIVED="${TMPDIR:-/tmp}/dispute-screenshots-dd"

# `|| true` matters: with pipefail set, grep finding nothing fails the whole
# pipeline, and under `set -e` that exits here — silently, before the branch
# below that would have created the device. It only ever looked fine because
# the simulator already existed.
UDID=$(xcrun simctl list devices | grep "$DEVICE_NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)
if [ -z "$UDID" ]; then
  echo "Creating $DEVICE_NAME…"
  UDID=$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$RUNTIME")
fi
echo "Device: $UDID"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

echo "Building…"
xcodebuild -project Dispute.xcodeproj -scheme Dispute -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$DERIVED" build >/dev/null

xcrun simctl install "$UDID" "$DERIVED/Build/Products/Debug-iphonesimulator/Dispute.app"

# 9:41, full signal, full battery. Cleared again at the end, or every later
# launch of this simulator lies about the time.
xcrun simctl status_bar "$UDID" override \
  --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3

mkdir -p "$OUT"

# shoot <name> <seconds to wait> <launch arguments…>
#
# The wait is per screen and it matters. Three seconds covers the entrance
# animations, which stagger in over about a second.
#
# Three seconds was not always enough for the first shot. On a 6.9-inch device
# it photographed the splash — a gavel on an empty screen — and that went onto
# the listing as the first thing anybody saw. The splash hands over on its own
# schedule, so 01 waits long enough to be past it rather than long enough on the
# machine this was written on.
#
# 03 and 06 used to wait thirty-five seconds for a real model call, because their
# seeds stopped just before the thing the screenshot is of. That was the worse
# bug: run without MISTRAL_API_KEY, both shots photographed the failure screen,
# and "That API key wasn't accepted" went up on the App Store as a picture of the
# app's main feature. They are now seeded with -seedClaims and -seedCrux, so
# every shot in this script is deterministic and none of them needs a key.
shoot() {
  local name="$1" wait="$2"; shift 2
  echo "  $name"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  # SIMCTL_CHILD_ is how an environment variable reaches the app rather than
  # simctl itself. Debug builds read DISPUTE_API_KEY and use it directly, which
  # is the only way the two live shots below can reach a model: the hosted path
  # needs App Attest, App Attest does not exist on a simulator, and the Worker
  # correctly refuses the debug token that stands in for it.
  SIMCTL_CHILD_DISPUTE_API_KEY="${MISTRAL_API_KEY:-}" \
    xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@" -screenshotMode >/dev/null
  sleep "$wait"
  # `simctl io screenshot` refuses to overwrite and exits 1, so a second run of
  # this script died on the first shot — under `set -e`, with the error sent to
  # /dev/null, which is a silent failure that leaves the previous set in place
  # and looks from the outside like nothing happened. This script is for
  # *re*-taking screenshots; it has to be able to write over the last lot.
  rm -f "$OUT/$name.png"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null
}

# The order is the order of the listing, which is the order somebody meets these
# screens.
echo "Shooting…"
shoot 01-what-it-does         8 -freshInstall
shoot 02-pass-the-phone       3 -seedStage checklist
shoot 03-tick-the-same-list   4 -seedStage checklist -seedSkipHandoff -seedClaims
shoot 04-take-the-other-side  3 -seedStage checklist -seedSkipHandoff -seedSecondLook
shoot 05-what-youre-assuming  3 -seedStage positions -seedSkipHandoff -seedAssumptions
shoot 06-the-crux             4 -seedStage crux -seedSkipHandoff -seedCrux
shoot 07-written-up           3 -seedStage summary -seedSkipHandoff

xcrun simctl status_bar "$UDID" clear
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true

echo
echo "Written to $OUT:"
for f in "$OUT"/*.png; do
  printf '  %-34s %s\n' "$(basename "$f")" \
    "$(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/ {printf "%s ", $2}')"
done
echo
echo "Apple wants $EXPECT for ${DISPUTE_SHOT_SIZE:-6.5}-inch. Anything else and the upload is rejected."
