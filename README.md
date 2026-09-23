# Dispute

> Built by Noah Puckett for the 2026 Congressional App Challenge (PA-13).
> Free on the App Store. This repository is the full source of the iOS app and
> the Cloudflare Worker behind it.
>
> **Note for anyone building it:** the App Store paperwork folder (`Beta App
> Review/`) and the Firebase config file are not included here. To run the
> assisted path, add a `Dispute/GoogleService-Info.plist` from your own Firebase
> project with App Check enabled, or paste a Mistral API key into Settings. The
> by-hand path works with no setup at all.

An iOS referee for arguments. Two people who are stuck pass one phone back and
forth, and the app walks them through four steps:

1. **Say your side.** Each person writes what they think, in their own words.
2. **Tick the list.** The app breaks *both* positions into one combined list of
   plain statements. Each person goes through it and ticks what they agree with.
   Whose point is whose is hidden — otherwise you answer the person, not the point.
3. **Take the other side.** Still on your own turn, you pick one point you
   crossed out, make the best case *for* it, and say what would change your mind
   about it. You write it before the phone changes hands, so neither of you is
   performing for the other.
4. **See the crux, and how to settle it.** Where your ticks match is common
   ground, usually more than either of you expected. What's left is **one
   question** — not a list of them — chosen so that *both* of you would change
   your mind depending on the answer, which is what makes it a crux rather than
   one person's objection. Underneath it is the one thing you could go and do
   that would settle it. Then the app writes the whole thing up.

The phone changes hands exactly twice. Step 3 sits inside step 2's turn on
purpose: an earlier design had five working stages and eight handoffs, and
people stopped before they reached the crux.

Step 3 is where the app stopped being a voting machine. Ticking a list says
*where* two people split; it never says why, and a crux named from nothing but
which rows differed is a guess. What someone says would change their mind names
the thing their position is actually resting on — and where the two of them are
waiting on different things, that gap usually *is* the crux.

Only one person needs the app installed. No accounts, no invites, no second
device.

## The AI

Steps 2 and 3 are the ones a model is useful for, and the app uses **Mistral
Medium 3.5** to do them. There is nothing to set up: no account, no key, no card.
A small Cloudflare Worker holds the key and makes the call on the free tier, and
the phone proves it is a real copy of this app with App Check rather than
carrying a credential anybody could read out of the binary.

**It is off until somebody says yes.** The first screen asks — *Use the AI* or
*Do it by hand* — and nothing leaves the phone until that is answered. Apple's
guideline 5.1.2(i) requires explicit permission before personal data reaches a
third-party model, and two people's account of their own argument is exactly
that. The screen it is asked on already named the provider, named the model and
said what the free tier means; what it did not have, until 2026-08-05, was a fork.
An inherited `aiEnabled = true` from before that does not count as consent —
see `AIAvailability.hasChosen`.

There is no on-device option any more. There was: the app downloaded Qwen3 1.7B
and ran it through llama.cpp, which meant no key, no account and no connection.
It is gone, and what it cost is written up in
[docs/DECISIONS.md](docs/DECISIONS.md). The short version is that a 1.7B model
produces something well-formed and shallow on exactly the two jobs this app has,
and everything around it — a 1.26 GB download, 31 MB of vendored framework, a
background transfer that had to survive being killed mid-flight, and a gigabyte
of wired memory that made the whole phone slow until it was released on every
sensible trigger — was infrastructure in service of an answer nobody liked.

**By hand still works, and is one of the two buttons on the first screen.** Turn
the AI off — or never turn it on — and you each
write your own points on the same turn you say what you think, and at the end the
two of you name the crux together from a filled-in draft. Nothing leaves the
phone, nothing is blocked, and the Start button never waits on anything. The same
path is offered mid-session, on the failure screen, when the model cannot be
reached.

**What it costs you.** What you both write is sent to Mistral when the AI is on.
It is not used to train anything — the account has opted out of that — and the app
says so on the card, and asks, before you type anything.
There is no account and no sign-in. The one piece of infrastructure this app has
is the Worker, and it stores nothing: no database, no logs, no retention.

**The free limit is shared** between everybody using Dispute, so on a busy day it
can run out. If that happens the app offers to finish the argument by hand, and
Settings has a slot for a Mistral key of your own if you would rather have your
own limit. Most people will not need it. The free tier is 1B tokens a month
against roughly 7,000 a session, so this is now unlikely rather than routine.

## What it flags, and what it doesn't

Between the two turns the app names **what each side is taking for granted** — the
step somebody's argument depends on but never states.

It used to check facts instead, and that was a mistake worth recording. Asking a
model whether a statement about the world is true needs knowledge it may not
have, produces an answer nobody in the room can check, and hands one side a
weapon when it is wrong. Measured over the eight tuning debates the on-device
model flagged something in all eight, including statements of value it had itself
just called unfalsifiable, and once answered a contested empirical question with
a verdict.

An assumption is a question about the *text*, which is the thing the model can
actually see. It says nothing about whether the assumption holds — the two people
in the room are the only ones who can say — and arguments that go in circles
usually do it because each side is standing on something the other never agreed
to.

Nothing else the model produces is shown as its own writing. The write-up on the
last screen is composed on the phone from what the two of you actually did: it
appears instantly, on every phone, and cannot invent a sentence about who was
closer to right. A model used to be given the chance to rewrite it more fluently,
which bought nothing and cost the final screen a spinner at the one moment two
people have finished and want to put the phone down.

## Running it

```sh
open Dispute.xcodeproj
```

Pick an iPhone simulator and hit run. The assisted path works out of the box,
against the real model, as long as `Dispute/GoogleService-Info.plist` is the one
for a Firebase project with App Check enabled and `HostedEngine.endpointString`
points at a deployed Worker. Without either, paste a Mistral key into Settings.

**App Check in the simulator.** App Attest does not exist there, so debug builds
use App Check's debug provider. It prints a token on first launch:

```
[AppCheckCore][I-GAC004001] App Check debug token: 'XXXXXXXX-...'
```

Register it once per simulator or debug device under **App Check → Apps → Manage
debug tokens** in the Firebase console. Until App Check enforcement is turned on
in the console, an unregistered token logs a warning and requests still go
through.

### Trying it on the Mac first

```sh
scripts/test-on-mac.sh          # as this phone sees it
scripts/test-on-mac.sh manual   # the by-hand path, with no key
```

Builds, boots the simulator, installs, and launches.

**Two simulators show the same thing, which is the point.**

```sh
xcrun simctl launch <17-pro>  com.jamesgpuckett.Dispute -freshInstall
xcrun simctl launch <12-mini> com.jamesgpuckett.Dispute -freshInstall
```

Both land on the same first-run screen. That used to be the bug — a simulated 12
mini reported Apple Intelligence as available, because the simulator answers that
question for the Mac underneath it, so the old-phone half of the app was nearly
impossible to see. There are no halves now, so there is nothing to fake and the
flags that faked it are gone. The two devices differ only in screen size, which
is still worth checking: the offer card is one line of copy away from pushing
content below the fold on a 12 mini.

Pass UDIDs, not `booted` — see below.

### Testing against the real model

```sh
cd DisputeCore
MISTRAL_API_KEY=… swift test --filter CloudEngineLive
```

Skipped without the variable, and everything else still runs. It covers what no
unit test can reach: whether the model returns the shape the app asks for,
whether the crux comes back a genuine double crux with a usable test, whether an
assumption arrives without a verdict in it, whether names leak into anything the
model wrote, and whether a wrong key surfaces as something a screen can explain.
It prints the crux and the assumptions it got, because whether they are any
*good* is a question only reading answers.

From the command line:

```sh
xcodebuild -project Dispute.xcodeproj -scheme Dispute \
  -destination 'id=<simulator-udid>' build

cd DisputeCore && swift test
```

Use `-destination 'id=…'` rather than `name=`: duplicate device names across
runtimes make the name form fail to resolve.

### Jumping to a stage during development

```sh
xcrun simctl launch <device> com.jamesgpuckett.Dispute -seedStage crux -seedSkipHandoff
```

`-forceFailure <notEnough|refused|timedOut|truncated|malformed>` makes the engine
fail on demand, which is the only practical way to look at the screens that
handle failure — a model produces those when nobody is watching and refuses to
when somebody is. `-seedAfterFailedClaims` lands on the entry screen as it is on
the second visit, with Done held until something is added.

`-seedStage` accepts any stage name (`positions`, `checklist`, `crux`,
`summary`). `-seedSkipHandoff` lands directly on the working screen.
`-forceMockEngine` pins the offline mock. Debug builds only.

`-seedSecondLook` lands on the follow-up at the end of a checklist turn, with
the list already ticked. Use it with `-seedStage checklist -seedSkipHandoff`.
Reaching that screen by hand means ticking six points first, which is six taps
before you can look at the thing you changed.

`-seedAssumptions` lands on the assumptions screen with two flags on it. Use it
with `-seedStage positions -seedSkipHandoff`. That screen otherwise appears only
when a real model happens to find something in what two people wrote, which is
not a thing that can be arranged — so without this, the one screen in the app
that says something about a person's own words back to them is the one screen
nobody ever looks at.

`-seedStage` also skips the first-run screen, which is modal — without that it
would land on the introduction and stay there.

- `-forceManualMode` — no model at all, the by-hand path.
- `-freshInstall` — introduction unseen, the AI question unanswered, saved
  argument gone. Leaves a
  downloaded model in place, so trying the first-run screen doesn't cost a
  gigabyte each time.

The flags that pretended to be a different *phone* are gone, because there is no
longer a different phone to pretend to be.

Two things will waste an afternoon if you drive `simctl` by hand:

- **`booted` is not a device.** It means "the booted device", and with more than
  one up simctl picks one — so install, container copy and launch can each land
  somewhere different. Pass a UDID. `DISPUTE_SIM` accepts one, and duplicate
  names across runtimes (an iOS 26.4 and an iOS 26.5 "iPhone 17 Pro") are exactly
  when this bites.
- **Launch arguments are only read on a cold launch.** `simctl launch` on a
  running app foregrounds it and drops them silently, which looks like the flag
  not working. `simctl terminate` first.

### Taking the App Store screenshots

```sh
scripts/screenshots.sh
```

Seven screens at 1242 × 2688, into `Beta App Review/screenshots/6.5-inch/`. It
creates an iPhone 11 Pro Max simulator, which is that size natively, so nothing
is resized into it afterwards.

Every screen but the first needs a seeded session, and the seeds are `#if DEBUG`
— which is why `-screenshotMode` exists. It hides the beetle, so the listing
doesn't show a control no released copy of the app has. The status bar is
overridden to 9:41 and cleared again at the end.

### Reading what the model was actually asked

Debug builds put a beetle beside the gear on every screen. It opens the session
as plain text: both positions, the list with each person's answers and where they
split, both second looks, the crux the app decided to show, and then every prompt
the model was given with its raw answer underneath. Copy it, share it as a file,
or write it into the app's Documents folder and fetch it from a simulator:

```sh
open "$(xcrun simctl get_app_container <device> com.jamesgpuckett.Dispute data)/Documents"
```

This is the part of the app that tests cannot cover. A crux can be well formed,
parse cleanly, satisfy every assertion, and still be a restatement of the topic
rather than the question underneath the argument. Reading the prompt and the raw
answer side by side is the only way to tell.

Notes from the app sit in the same stream as the calls, because the app is as
likely to be at fault as the model. A crux thrown away for being too short reads
as a model that found nothing, unless something says so.

The log is in memory and per launch, so take the transcript before relaunching.
It never reaches a release build: `PromptLog` and `DebugTranscript` are wrapped
in `#if DEBUG`, and none of their strings appear in a Release binary.

## Layout

```
Dispute/            the iOS app
  Session/               the session view model and what this phone can do
  Views/Design/          palette, components, the mark. No screens.
  Views/Onboarding/      splash, first run, how-it-works
  Views/AI/              the offer card and the settings section
  Views/Session/         one file per screen of an argument
DisputeCore/        models, rules, and the engine. No UI, no binaries. Unit-tested.
  Sources/DisputeCore/   rules, both modes, the model client, the Keychain store
Fixtures/           debates.json — the answer key for crux-detection tuning
docs/               plan, architecture, changelog, decisions, todo, release
docs/IDEA.md        the original one-paragraph idea, unchanged
worker/             the Cloudflare Worker that holds the API key. Deployed, not
                    bundled. See worker/README.md
scripts/            test-on-mac.sh, screenshots.sh, check-mistral.sh, and the
                    upload options plist
Beta App Review/    everything App Store Connect asks for before the app can go
                    to external testers, one file per field — plus the support
                    site and privacy policy to publish, and the screenshots
transcripts/        debug transcripts pulled off a device. Never committed; a
                    transcript is somebody's whole argument in plain text.
```

The split matters: every rule — when a claim counts as contested, when a stage
may advance, what counts as common ground — lives in `DisputeCore` with no UI
dependency, so it is testable without a simulator and cannot drift into a view.

## Engines

`DisputeEngine` is a protocol with two implementations:

| Engine | Use |
|---|---|
| `CloudEngine` | Mistral Medium 3.5. The real one, over a `ModelTransport`. |
| `MockDisputeEngine` | Canned and deterministic. No network, no key. Tests and previews. |

`CloudEngine` holds the prompts, the retries and the failures; how the request
travels is a `ModelTransport`, of which there are two — `ProxyTransport`
(everybody, free, no key) and `MistralTransport` (a key of your own, your own
quota). Scripting that transport is how the engine is tested offline.

`AIAvailability` decides whether there is an engine at all — `nil` is manual
mode. Views hold an `EngineSource` rather than an engine, so a change in Settings
takes effect on the next call rather than the next launch.

There were two more. `AppleFoundationEngine` used Apple Intelligence where the
phone had it, and `LocalModelEngine` ran a downloaded Qwen3 1.7B through
llama.cpp. Both are gone; see [docs/DECISIONS.md](docs/DECISIONS.md).

## Docs

- [docs/PROJECT_PLAN.md](docs/PROJECT_PLAN.md) — scope, milestones, open questions
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — layering and why
- [docs/CHANGELOG.md](docs/CHANGELOG.md) — what happened, per milestone
- [docs/DECISIONS.md](docs/DECISIONS.md) — product decisions, in Noah's words
- [docs/TODO.md](docs/TODO.md) — what's next
- [docs/IDEA.md](docs/IDEA.md) — the original idea, verbatim
- [docs/RELEASE.md](docs/RELEASE.md) — the route to TestFlight and the App Store
- [Beta App Review/00-START-HERE.md](Beta%20App%20Review/00-START-HERE.md) — what
  Apple asks for before external testers, in the order it asks
