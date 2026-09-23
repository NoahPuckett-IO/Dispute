# Getting Dispute onto TestFlight

The membership is paid and active, so the step that used to be blocked is now the
next thing to do. This is the whole route from here, with the parts that are
already done marked as such.

Two things in it changed with the app rather than with the account, and both will
be wrong in the listing if an old version gets pasted in:

1. The app sends what people write to Mistral, once somebody has said it may.
   There is no key to paste any more; there is a question on the first screen,
   and the AI is off until it is answered.
2. It links a third-party SDK, Firebase, which it did not before.

See **Phase 6**, which is the one that needs actual care, and the
`Beta App Review/` folder in the project root for the paste-ready version.

## What the paid membership changed

Team `38Q977Q767` ("James Puckett") owns `com.jamesgpuckett.Dispute`, and
nothing about the identifier moves.

What was failing before was distribution signing:

    No signing certificate "iOS Distribution" found

**That is resolved as of 2026-08-04.** Both now exist:

    Apple Distribution: JAMES GRAHAM PUCKETT (38Q977Q767)   valid to 2027-08-04
    Profile "Paid Team" → 38Q977Q767.com.jamesgpuckett.Dispute
                          get-task-allow=false, beta-reports-active=true

### Do not be fooled by the certificate name

`Apple Development: <account-holder email> (C5V6PN8C95)` looks like it names a
personal team. It does not. That parenthetical is a **certificate ID**. The team
is in the OU field, and it is the paid one:

    OU=38Q977Q767 / O=JAMES GRAHAM PUCKETT

There is no personal team anywhere in this project. Both build configurations
set `DEVELOPMENT_TEAM = 38Q977Q767`. If Signing & Capabilities says "Personal
Team", that is stale Xcode UI state, not the project — and it does not stop a
release, because the command-line route below ignores it.

## Phase 1 — Enrolment — DONE

## Phase 2 — Add the second seat

App Store Connect → **Users and Access** → invite `<developer email>` as
**App Manager**. That covers builds, TestFlight, testers and metadata.

Reserved to the Account Holder: legal agreements, renewals, banking. Worth
knowing that **a pending license agreement freezes uploads and releases until he
accepts it**, which is the one thing that will need him at short notice — and it
appears without warning whenever Apple changes terms.

## Phase 3 — Project configuration — DONE

- `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`. Still correct now the app
  makes network requests: it uses ordinary HTTPS, which is exempt. Declaring it
  here is what stops App Store Connect asking the export-compliance question on
  every single upload.
- `DEVELOPMENT_TEAM = 38Q977Q767`, `CODE_SIGN_STYLE = Automatic`.
- `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 6` (1 through 5 are
  spent; 6 is the one to submit — 4 has no privacy manifest and would be
  rejected for ITMS-91053, and 5 tells people nothing is being uploaded on the
  screen shown while it is).
  **Every upload needs a build number never used before for that marketing
  version.** Bump `CURRENT_PROJECT_VERSION` each time; leave the marketing
  version alone until the app itself changes meaningfully. An upload that reuses
  a build number is rejected after the whole upload has finished, which is a
  slow way to find out.
- The 1024pt marketing icon is present, which is a common submission blocker.
- Release configuration builds clean, verified. All debug scaffolding
  (`DebugSeed`, `-seedStage`, `-seedAssumptions`, `-forceFailure`,
  `-forceMockEngine`, the transcript viewer) is behind `#if DEBUG` and none of
  its strings appear in a Release binary.
- The app was 4.9 MB before Firebase. It links `FirebaseAILogic` and
  `FirebaseAppCheck` now, so expect a few MB more; still nothing like the 31 MB
  llama.cpp xcframework it vendored until the on-device model was removed.
- **App Attest.** `Dispute/Dispute.entitlements` declares
  `com.apple.developer.devicecheck.appattest-environment = production`. Automatic
  signing adds the capability to the App ID on its own; if a distribution build
  complains about provisioning, that is what it wants. Debug builds never touch
  App Attest — they use App Check's debug provider.
- **App Check and the Worker have to be configured or the AI fails for every
  tester.** Console → App Check enabled and the app registered; then the Worker
  deployed and its URL in `HostedEngine.endpointString`. AI Logic is no longer
  needed — the model call does not go through Firebase any more.
  A TestFlight build is a release build, so it uses App Attest rather than a debug
  token, and it needs App Check registered for the app rather than for a
  simulator.

## Phase 4 — Create the app record — DONE

App Store Connect → **My Apps → + → New App**:

- Platform iOS, bundle ID `com.jamesgpuckett.Dispute` (it will be in the list).
- **The app name has to be unique across the entire App Store**, so "Dispute"
  may well be taken. This is a listing decision only — the name under the icon on
  the home screen comes from the bundle and does not have to match.
- SKU is private; anything stable, e.g. `dispute-001`.

## Phase 5 — Archive and upload — 1.0 (6) is the one to submit

**1.0 (5) went up on 2026-08-05** by the command-line route below, which is
still the one that works. It carries `Dispute/PrivacyInfo.xcprivacy`, without
which Apple returns ITMS-91053 for the `UserDefaults` calls and rejects the
submission — and no ITMS mail arrived after it, which is how you know the
manifest was accepted. 1.0 (4), uploaded an hour earlier, is the same app
without that file.

**1.0 (6) went up on 2026-08-05** by the command-line route below, and is the
build to submit. Verified in the archive before it was sent: `CFBundleVersion`
6, `PrivacyInfo.xcprivacy` at the bundle root declaring `CA92.1`,
`appattest-environment` = `production`, team `38Q977Q767`,
`ITSAppUsesNonExemptEncryption` = false. Worth doing every time — it is the only
moment all five are checkable at once, and it costs one `plutil` call.

**It is 1.0 (5) plus an honest loading screen.** `ThinkingView` told people "This runs on your phone, not a server.
That's slower, but nothing is being uploaded." — copy left over from the
downloaded model, on the one screen that is shown *only* while a request is in
flight to Google. It contradicted the first screen, the privacy policy and the
App Privacy questionnaire, and it said so at the exact moment it was least true.
It now asks them to keep the app open instead, which is the thing they can
actually act on.

1. Xcode → destination **Any iOS Device (arm64)**. Not a simulator — a simulator
   archive produces something that cannot be uploaded and the error is unclear.
   This destination is **build-only**: pressing Run against it gives "a build
   only device cannot be used to run this target". That is expected. Switch to a
   simulator to Run, back to Any iOS Device to Archive.
2. **Product → Archive.**
3. In the Organizer: **Distribute App → TestFlight & App Store → Upload.**
4. Leave "Manage Version and Build Number" **off**, or Xcode silently renumbers
   the build and the project no longer matches what was uploaded.

Processing in App Store Connect takes 5–20 minutes, and the build appears under
TestFlight only after it finishes.

### If the Organizer has no team in its dropdown

This happened on 2026-08-04: Xcode → Settings → Accounts listed no teams, and
the Distribute assistant cancelled out with `team(resolved)="(null)"` before
producing any error. Signing itself was fine the whole time. Rather than fight
the UI, upload from the command line — this is what actually shipped 1.0 (1):

    ARCH=$(ls -d ~/Library/Developer/Xcode/Archives/<date>/*.xcarchive)
    xcodebuild -exportArchive \
      -archivePath "$ARCH" \
      -exportOptionsPlist scripts/UploadOptions.plist \
      -exportPath UploadOut \
      -allowProvisioningUpdates

`-allowProvisioningUpdates` is the load-bearing flag. Without it, export fails
with `No profiles for 'com.jamesgpuckett.Dispute' were found` even though the
correct profile is sitting in
`~/Library/Developer/Xcode/UserData/Provisioning Profiles/`. Copying the profile
to the legacy `~/Library/MobileDevice/Provisioning Profiles/` does **not** help;
only the flag does.

`UploadOptions.plist`:

    method                        app-store-connect
    destination                   upload
    teamID                        38Q977Q767
    signingStyle                  automatic
    manageAppVersionAndBuildNumber  false
    uploadSymbols                 true

## Phase 6 — Privacy and review answers ⚠️ CHANGED

This is the part that is different from the last version of this document, and
the part where getting it wrong means a rejection or, worse, a true statement in
the listing that stops being true.

**The app sends what people write to Mistral, once they have agreed to it.** This
is the part that changed most. There is no longer a key to add: the first screen
asks — "Use the AI" or "Do it by hand" — and if the answer is yes, both positions
and the list of points go to Mistral through this project's Worker. If it is no, or
the switch is turned off in Settings later, the app runs entirely by hand and
opens no connections at all.

**That question is there because of guideline 5.1.2(i)**, amended November 2025:
explicit permission is required before personal data goes to a third-party AI.
The app used to have the AI on from first launch behind a Start button, which is
a disclosure rather than a permission. See `Beta App Review/12-risks-and-
rejections.md` for the whole reasoning, which is also the answer if a reviewer
asks.

Two consequences for the listing:

- The **free tier does not train on the content**, because the account opted out.
  That is a setting rather than a guarantee, and it is asserted on the AI card, in
  the privacy policy and in the beta review notes — so all three change together
  if it is ever turned back on.
- **Firebase is a third-party SDK**, which the old answers said there were none
  of. `FirebaseAppCheck` only, since `FirebaseAILogic` was removed with the
  provider change. No Analytics, no Crashlytics,
  no advertising identifier — `IS_ANALYTICS_ENABLED` is false in the plist and
  the Analytics product is not linked.

That means **App Privacy is no longer "Data Not Collected" across the board.**
Declare it honestly:

| Question | Answer |
|---|---|
| Data types collected | **User Content → Other User Content** |
| Used for tracking | **No** |
| Linked to identity | **No** — there is no account and no sign-in |
| Purpose | **App Functionality** |

Everything else stays **Data Not Collected**: no analytics, no advertising, no
third-party SDKs, no contacts, no identifiers. The app stores one JSON file in
Application Support that `Settings → Delete this argument` removes.

It was previously defensible to argue the app "collects" nothing, because the
traffic went from the user's device to the user's own account. That argument is
gone: the traffic now goes through our Worker to our Mistral account. Declare it.
Apple's question is about data leaving the device, the answer costs nothing, and
an under-declaration found later is the kind of thing that gets an app pulled.

**App Check and DeviceCheck.** App Attest produces an attestation about the
device and the app binary. It is not an advertising identifier, is not linked to
the user, and Apple does not ask about it separately — but if a reviewer queries
the DeviceCheck entitlement, that is what it is for: stopping anybody who
extracts `GoogleService-Info.plist` from the binary from spending the shared
quota.

## Phase 7 — Testers

**Internal, up to 100.** Anyone holding an App Store Connect role on the team. No
review, live within minutes. Both of you should be here.

**External, up to 10,000.** Email invite or public link. The first build of each
*marketing version* goes through Beta App Review — normally about 24 hours —
and later builds of the same version usually clear in minutes.

## Phase 8 — Upkeep

- **TestFlight builds expire after 90 days.** Testers lose the app and their
  saved argument. Worth saying in the tester notes so it doesn't read as a bug.
  Nothing needs pasting back in any more, which is one fewer thing to explain.
- **Watch the shared quota.** The no-cost tier's limits belong to the Firebase
  project, so every tester draws on one allowance. A batch of testers all trying
  it the same evening is exactly the shape of usage that hits it. If that starts
  happening, the answer is billing on the Firebase project, not a code change.
- Membership renews annually. A lapsed membership pulls the app from sale and
  stops TestFlight.

---

## Paste-ready

Everything to paste lives outside this document, so there is one copy of that
text rather than two that drift:

- **`Beta App Review/`** in the project root — every field App Store Connect
  asks for before a build can go to external testers, one file per field, in the
  order it asks. Start at `Beta App Review/00-START-HERE.md`. It also holds the
  support site and privacy policy to publish, the screenshots, and a list of what
  would most plausibly be rejected.
- **`docs/APP_STORE_LISTING.txt`** — the product page copy: description,
  subtitle, promotional text, keywords. Not needed for TestFlight; needed before
  the app goes on sale.
