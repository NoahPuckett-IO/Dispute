# Dispute — Architecture

## Shape

```
┌─────────────────────────────────────────┐
│  Dispute (iOS app target)               │
│  SwiftUI views + view models            │  ← needs Xcode
└──────────────────┬──────────────────────┘
                   │ imports
┌──────────────────▼──────────────────────┐
│  DisputeCore (Swift package)            │
│  Models, state machine, engine protocol │  ← builds with CLT alone
│  CloudEngine → ModelTransport           │
└─────────────────────────────────────────┘
                   │ two transports
        ┌──────────┴───────────┐
   ProxyTransport         MistralTransport
   (DisputeCore)          (DisputeCore)
   the app's Worker,      the person's own key,
   free, no key           their own quota
```

**One package, no binaries.** There used to be a second target, `DisputeLlama`,
holding llama.cpp and the engine that ran a downloaded model on the phone. It is
gone along with its 31 MB xcframework — see docs/DECISIONS.md. Everything runs
through an HTTP client now, so the package has no binary dependency and the
whole thing builds without Xcode.

**Nothing holds an engine.** `SessionViewModel` holds an `EngineSource` — a
closure — rather than an engine. That began as a memory fix, when an engine was
a gigabyte of weights and a stored reference meant the memory never came back.
It stays for a second reason that outlived the first: the AI can be switched off
or a key added mid-session, and a session holding an engine built before that
would go on using it until relaunch.

**One engine, two transports.** `CloudEngine` composes the prompts, decides what
a usable answer is, retries the call worth retrying and throws the errors the
screens explain. How the bytes travel is a `ModelTransport`, and that seam is
what lets the same prompts go through Firebase for everybody and through
somebody's own key when they want their own quota. It is also what made the
engine testable offline: `CloudEngineTests` scripts the transport, which before
the split meant spending real quota to find out what the app does with a fenced
JSON reply.

## Two modes

`DisputeMode` is a property of a `Dispute`, fixed when the session starts. The
engine is `Optional`: `nil` is manual mode, and the compiler makes that a case
you have to handle rather than a null object that silently does nothing.

| Step | `.assisted` | `.manual` |
| --- | --- | --- |
| Positions → points | engine `breakDown` | each person writes their own, same turn |
| Between the turns | `findAssumptions` | skipped |
| Contested → crux | engine `findCrux` | the pair edit a generated draft |
| The write-up | composed on the phone | composed on the phone |

Both paths end in the same `[Claim]` and `[Crux]`, through the same interleave
and deduplicate rules, so nothing from the checklist onwards knows which ran.

**Why the mode is nearly fixed per session.** Someone who starts by hand and
flips the toggle mid-argument would otherwise land on a checklist built from
points nobody was asked for. There is exactly one exception and it runs the other
way: `Dispute.continueByHand()` gives up on the model mid-session, for the
failures nobody in the room can fix — the shared quota is spent, the phone has no
signal, the provider is down. It builds the checklist out of their own sentences, the
same fallback used when two rounds of asking produce nothing usable, and it is
one-way. Assisted needs a list the model wrote, and by the time somebody has
pressed that button they are past the screen that would have built one.

**Why the package split.** Everything that encodes a rule — how deep recursion
may go, when a steelman counts as approved, which stage transitions are legal —
lives in `DisputeCore`, which has no UI dependency. That buys three things:

1. It compiles and tests without Xcode (relevant right now — see PROJECT_PLAN).
2. Business rules are unit-testable without launching a simulator.
3. The rules can't quietly drift into a view file, where they'd be untestable
   and duplicated across screens.

## Layers

| Layer      | Lives in                     | Knows about                    |
| ---------- | ---------------------------- | ------------------------------ |
| Models     | `DisputeCore/Sources`        | Nothing but Foundation         |
| Engine     | `DisputeCore/Sources`        | Models; protocol only          |
| View model | app target                   | Models + engine protocol       |
| Views      | app target                   | View model only                |

Views never call the engine directly and never mutate a model directly. That
keeps the "who is allowed to change what" question answerable.

## Pattern: MVVM

SwiftUI plus MVVM. One `SessionViewModel` owns the live `Dispute` value and is
the only thing that mutates it; views observe and send intent. Chosen over
plain-SwiftUI-state because the session is a state machine with real invariants
(you cannot reach the crux stage before both steelmen resolve), and those
invariants need one owner.

## Pattern: protocol-based engine

```swift
protocol DisputeEngine {
    func breakDown(...) async throws -> [Claim]
    func findCrux(...) async throws -> Crux?
    func findAssumptions(...) async throws -> [AssumptionFlag]
}
```

Two implementations: `CloudEngine` (Mistral over HTTPS) and `MockDisputeEngine`
(canned and deterministic). The entire UI is built and demoed against the mock,
so screens can be developed with no key, no network and no wait.

This protocol has now outlived four conformers — a Claude API client, Apple's
on-device model, a llama.cpp engine running downloaded weights, and before them
a different shape of the same idea. Each removal cost exactly what the split was
supposed to make it cost: no view, no model type and no rule changed.

## Data model

Value types (`struct` / `enum`) throughout, all `Codable`. No reference
semantics in the model layer — a `Dispute` passed to a function cannot be
mutated behind the caller's back.

| Type           | Role                                                        |
| -------------- | ----------------------------------------------------------- |
| `Party`        | Which of the two people. `.a` / `.b`, with `.opponent`       |
| `PartyPair<T>` | One value per party, keyed by `Party`, generic over content  |
| `SessionStage` | The state machine: setup → positions → … → summary           |
| `Assumption`   | A node in the excavation tree; holds its own children        |
| `Steelman`     | One party's attempts to restate the other's view             |
| `Crux`         | An identified point of genuine disagreement                  |
| `Dispute`      | The aggregate root tying all of the above together           |

**`Assumption` is recursive** — it holds `[Assumption]` children. Swift permits
this without the `indirect` keyword because `Array` is itself a reference to
heap storage, so the struct's size stays fixed.

**`PartyPair<T>` instead of `[Party: T]`.** Swift only encodes dictionaries as
JSON objects when the key is `String` or `Int`; a `String`-backed enum key
silently encodes as a flat alternating array instead. `PartyPair` gives clean
JSON, compile-time guarantees that both parties always have a value, and a
`subscript(party:)` that reads the same as dictionary access at call sites.

## Persistence

`DisputeStore` — a single JSON file in Application Support, local device only.
No iCloud sync, no server-side storage, and a wipe-everything control.

**SwiftData was the original plan and was rejected.** `Dispute` is a value type
that is already `Codable`; SwiftData would have meant turning the model layer
into reference types purely to satisfy the framework, for an app that holds one
session at a time and never syncs. The storage story has to be simple enough to
state in one sentence in the privacy disclosure — "it is one file on this
device" clears that bar; an object graph does not.

Dates use `JSONEncoder`'s default strategy rather than ISO 8601. ISO 8601 reads
better but silently drops sub-second precision, so a saved session would not
round-trip exactly — caught by a test.

## Networking

Two ways to the same model, behind `ModelTransport`.

**`ProxyTransport`** is what everybody gets, and it is why the AI is free and
needs no setup. It posts to a **Cloudflare Worker** this project operates, which
holds the Mistral key and forwards the request. The phone proves it is a real copy
of this app with **App Check** (App Attest on device, the debug provider in the
simulator) and the Worker verifies that token against Google's public keys before
spending anything.

It lives in `DisputeCore` despite needing a Firebase token, because it does not
fetch one: it takes an `async` closure that produces a token, and `HostedEngine`
in the app target supplies it. That is what keeps the package linking no binaries
and building with the command line tools alone. The previous arrangement —
`FirebaseTransport`, up in the app target, calling Firebase AI Logic — could not
be tested by the package at all.

**`MistralTransport`** is the path for anybody who pastes in a key of their own.
It posts to Mistral's chat-completions endpoint, which is OpenAI-shaped, and the
Worker forwards that same shape — so both transports share one request builder
and one status-code mapping in `Requests`.

Same prompts, same parsing, same failures either way — only the pipe differs.

- **Model:** `gemini-3.6-flash`, which is what the free tier covers. One model
  rather than a picker — choosing between model identifiers is a question nobody
  using this app can answer, and the right answer changes every few months.
- **`response_format: json_object`**, and the reply is *still* parsed defensively.
  A JSON mode is a strong request rather than a guarantee: models wrap answers in
  a ```json fence, open with "Here is the JSON:", or append a paragraph
  explaining themselves. `CloudEngine.decodeJSON` tries the whole string, then
  what sits between the first brace and the last, and nothing cleverer — anything
  cleverer starts repairing broken JSON and silently changing what the model said.
- **`temperature: 0.3`.** Low but not zero: greedy decoding makes a model repeat
  itself across the two sides, and both people end up ticking the same sentence.
- **Ephemeral session, no URL cache** on the direct path. Nothing about an
  argument belongs on disk in a cache the app did not decide to write.
- **90-second timeout.** Generous, because the alternative is worse: the crux
  call is the long one, and a timeout means two people who waited half a minute
  are told it failed and asked to wait again.

## Secrets

An API key inside a shipped iOS binary is extractable, so there is not one. That
has not changed. What changed is what stands in its place.

**Nobody needs a key.** Requests go through the app's Firebase project, and what
the phone sends instead of a credential is an **App Check** token: a statement
from Apple, signed by the Secure Enclave, that this is an unmodified build of
this app on a real device. `GoogleService-Info.plist` ships in the bundle and is
not a secret — it identifies the project, and App Check is what stops anybody who
reads it out of the binary from spending the day's quota with it.

**The quota is the account's, and it is shared.** The free tier's limits belong to
the Mistral account rather than to each phone, so a busy enough day means
somebody's session hits `rateLimited` through no fault of their own. The Mistral
free tier is 1B tokens/month against roughly 7,000 tokens a session, so that day is
far off — the Gemini tier this replaced was 20 requests, or about six sessions. Two things
answer that, and neither hides it: the failure screen offers to finish the
argument by hand, and Settings still takes a key of somebody's own.

**Free does not mean trained on.** Mistral's free tier uses inputs for training
unless the account opts out, and this one has. That is a setting rather than a
guarantee, which is why it is written down in three places that have to change
together: the AI card, the privacy policy and the beta review notes. Under Gemini
there was no opt-out at all and the card had to say so — this is the clearest
thing the two people in front of the phone gained from the move.

**A key of their own** is still supported and still optional. It buys their own
quota, and requests then go direct rather than through Firebase.

It lives in the **Keychain**, not `UserDefaults`, and the distinction is not
academic: `UserDefaults` is a plist in the app's container that goes into iCloud
and device backups, so a key typed here would end up in a backup of every phone
the person ever restores from.
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` keeps it off backups and off
other devices while still allowing a call while the phone is locked — which
matters, because a session can be running when the screen goes off.

`Settings → Delete everything` removes it. A button with that word on it that
leaves a credential behind is lying about the most important part of itself.

## Error handling

Model-layer failures are typed (`DisputeError`) and thrown. Engine failures are
`EngineError`, and every case maps to a screen with a way forward — never a dead
end, never a raw error string.

The ones worth naming exist because the app is networked. `rateLimited` — the
shared free tier is spent — is now the most likely failure on the path, not an
exotic one, and its answer is neither "retry" nor "reword" but the button that
finishes the session by hand.

`RefusalCause` splits what used to be a `String` compared against `"key"` in four
places. Three causes, three different ways out:

| Cause | What happened | What the screen offers |
| --- | --- | --- |
| `.key` | A key somebody pasted in was rejected | Check it in Settings |
| `.app` | App Check or the project's configuration turned the app away | Carry on by hand; it is nothing they did |
| `.safety` | the provider's classifiers declined | Go back and reword |

The `.app` case is the one the split was written for. It is the same 403 as a bad
key, and telling somebody who never typed a key to go and check theirs sends them
looking for something that does not exist.

## Conventions

- Types `UpperCamelCase`; properties and functions `lowerCamelCase`.
- One primary type per file, named for the type.
- Comments only where they state a constraint the code cannot show. No comments
  narrating what the next line does.
- Small functions. If a view body needs a comment to be followed, extract a
  subview instead.
- Accessibility, Dark Mode, and Dynamic Type are considered per screen as it is
  built, not retrofitted in M11.
