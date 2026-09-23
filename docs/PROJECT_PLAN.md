# Dispute — Project Plan

## What it is

An iOS referee for arguments. Two people who are stuck hand one phone back and
forth, and the app walks them through a structured process:

1. **Say your side** — each person writes what they think.
2. **Tick the list** — the app breaks both positions into one combined list of
   claims, origin hidden, and each person ticks what they agree with.
3. **See the crux** — matching ticks are common ground; differing ticks are the
   argument, and the app names the question underneath them.

The phone changes hands twice. An earlier design had five working stages and
eight handoffs; it was exhausting and people stopped before reaching the crux.

Only one person needs the app installed. No accounts, no invites, no second
device.

## Prior art

This productizes two existing techniques:

- **Double crux** (rationalist tradition) — find the specific belief where, if it
  flipped, each side would change their mind.
- **The Rapoport rule / Ideological Turing Test** — you may not criticise a
  position until you can restate it to the holder's satisfaction.

Naming these is useful both for design decisions and for explaining the app to
users.

## Problem

Most arguments are not disagreements about the thing being argued about. They
are disagreements about an unstated premise two layers down, while both people
shout at the surface. Three failure modes, three countermeasures:

| Failure mode                                   | Countermeasure                        |
| ---------------------------------------------- | ------------------------------------- |
| Arguing past each other about different claims | Recursive assumption excavation       |
| Attacking a strawman                           | Steelman with opponent sign-off       |
| No shared sense of what is actually contested  | Explicit crux identification          |

The side effect of step 2 matters as much as the mechanism: being accurately
understood by the person you are arguing with is de-escalating on its own,
whether or not anything is resolved.

## Audience

General-purpose — anyone having a debate or disagreement. Not scoped to a
specific relationship, setting, or subject matter. The app makes no assumptions
about who the two parties are to each other, and its tone stays neutral and
non-therapeutic throughout.

## MVP scope

**In:**

- Single-device pass-the-phone flow, text input only
- One dispute at a time, one full pass through all four stages
- One shared checklist of 6–8 claims, drawn from both positions, origin hidden
- Explicit agree / don't-agree per claim, so an unanswered item is distinguishable
  from a considered "no"
- Crux screen: 1–3 identified disagreements, each stated as a plain question
- Local-only storage; no account, no sync, no analytics on argument content
- One tone-calibrated system prompt — neutral, never takes a side

**Out (later):**

- Voice input and transcription
- Two-device mode, shared sessions, invites
- Resolution tracking and follow-ups
- Templates by argument type
- Export / share / PDF
- Recursion deeper than 3, or auto-recursion without user control
- Cloud sync, iPad, Watch, widgets
- Subscriptions
- More than two participants

## Open questions

Decisions made so far are marked. The rest are live.

1. **How many handoffs?** *Decided:* two. Recursive excavation and the steelman
   round were cut — they produced eight handoffs and people gave up. The
   checklist does the same job in one pass.
2. **Should claim origin be shown?** *Decided:* no. Told a point came from the
   person you are arguing with, you answer the person rather than the point.
3. **Person B never consented.** The other party is handed a phone mid-argument.
   The first screen they see is the highest-risk UI in the product. Copywriting
   problem more than an engineering one.
4. **Users are dysregulated.** Long text entry and anything condescending gets
   the app closed. Every screen must survive an angry, impatient reader.
5. **Privacy is the trust story.** These transcripts are among the most sensitive
   text a person will type. Local storage, easy wipe, plain disclosure.
6. **API key security.** A key in an iOS binary is extractable. Production needs
   a backend proxy (M10). Local dev may use an on-device key.
7. **No official Anthropic SDK for Swift.** Raw HTTPS over `URLSession`.
8. **Crux detection is the hard AI problem.** Comparing two assumption trees for
   genuine divergence, not wording differences. Prototyped offline in M5.
9. **When the crux is emotional.** Sometimes the true crux is "I don't think you
   respect me." Surfacing that accurately can escalate. Needs defined behaviour.

## Milestones

One at a time, in order. Complexity: S / M / L.

| #   | Goal                                        | Complexity | Status      |
| --- | ------------------------------------------- | ---------- | ----------- |
| M0  | Repo and docs                               | S          | Done        |
| M1  | Xcode project boots                         | S          | Done        |
| M2  | Data model and session state machine        | M          | Done        |
| M3  | Engine protocol and mock                    | S          | Done        |
| M4  | Real Claude client over URLSession          | L          | Done        |
| M5  | Crux-detection prompt, tuned offline        | M          | Partial     |
| M6  | Pass-the-phone shell                        | M          | Done        |
| M7  | Stage 1 — positions and excavation          | L          | Done        |
| M8  | Stage 2 — the steelman gate                 | M          | Done        |
| M9  | Stage 3 — crux and summary                  | M          | Done        |
| M10 | Backend proxy, key removed from binary      | M          | Dropped     |
| M11 | Persistence, polish, accessibility          | M          | Done        |
| M12 | TestFlight and App Store                    | M          | Not started |

**Toolchain:** Xcode 26.6, iOS 26.5 SDK, deployment target iOS 17. Note that
installing Xcode is not sufficient on its own — the iOS platform runtime is a
separate download (`xcodebuild -downloadPlatform iOS`), and without it
`xcodebuild` reports zero eligible destinations even though `simctl` lists
devices.

**M5 is partial.** The prompts have been rewritten for the on-device model —
the excavation prompt now defines what an assumption is, gives worked good/bad
examples, and tells the model to test each candidate; the crux prompt adds the
"would this change someone's mind?" test. What has *not* happened is a scored
run against `Fixtures/debates.json`, comparing the model's crux to the expected
one across all eight debates. That is the remaining work.

**M10 is dropped.** With the on-device engine there is no API key in the binary,
so there is nothing for a backend proxy to hide. It returns only if the app ever
ships with `ClaudeDisputeEngine` as the default.

## How to test each milestone

- **M0** — `git log` shows history; the five docs exist.
- **M1** — builds clean, launches in simulator and on device.
- **M2** — `swift test` passes in `DisputeCore/`.
- **M3** — mock engine returns a fixed assumption tree.
- **M4** — a debug screen runs one hardcoded dispute end to end.
- **M5** — for each fixture, the identified crux matches what you'd say by hand.
- **M6** — tap through a full mock session; whose turn it is is never ambiguous.
- **M7** — both people can complete the checklist; progress is tracked per person.
- **M8** — matching ticks count as common ground, differing ticks as contested.
- **M9** — a full unbroken run from launch to crux on a real argument.
- **M10** — a strings dump of the built app contains no key.
- **M11** — VoiceOver pass; largest Dynamic Type with no clipping; light and dark.
- **M12** — real people run real arguments through TestFlight.
