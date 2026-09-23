# TODO

## Needs you

- [ ] **Try it.** Open `Dispute.xcodeproj`, run it, and take a real argument
      through end to end. Everything below is guesswork until someone uses it.
- [ ] **Apple Developer account** ($99/year) — only for TestFlight and the App
      Store (M12). Running on your own phone does not need one.
- [x] Decide whether the on-device model is good enough at finding cruxes.
      Measured over eleven configurations against the fixtures plus the two real
      sessions that went wrong: the model was not the bottleneck, the prompt and
      the grammar were. Same weights went from 15% of points copied out of a
      position and 7 usable lists in 10 to 0% and 10 in 10. See DECISIONS →
      "Is the model good enough?".
- [ ] **Read a transcript from a session that had none of these faults.** The
      measurement above counts defects, which is not the same as the crux being
      the right question. That still has to be judged by reading, and every
      transcript so far had something countable wrong with it.
- [ ] **Try the by-hand path on a real argument.** Run the app with
      `-forceManualMode` and take a disagreement through it. Writing your own
      points and naming your own crux is more work than tapping a button, and
      whether people will actually do it is the open question of this pass.
- [ ] **Try the downloaded model on an actual old phone.** Everything below the
      protocol is tested on a Mac, where it answers in about 8 seconds. An
      iPhone 12 will be several times slower. The spinner has a floor now — it
      explains itself at 10s and 30s — but those thresholds are guesses until
      someone sees real timings.
      `scripts/test-on-mac.sh ai <model.gguf>` runs the same path in the
      simulator first, but on the CPU — its timings say nothing about a phone.

## Needs no money

Everything works free and on-device: no API key, no server, no subscription,
and now no code path that could take one. The argument never leaves the phone.

## Next up (M5 — the real remaining work)

- [x] Score against `Fixtures/debates.json`. Done for the *downloaded* model:
      Qwen3 1.7B matches the answer key 7 times in 8. See DECISIONS.
- [x] Build a harness so prompt changes can be compared rather than eyeballed.
      It exists and has already earned its keep — two "improvements" to the crux
      prompt were measured as worse and thrown away.
- [x] Score Apple's on-device model the same way. No longer applicable: that
      engine is gone and every phone runs the measured one.
- [x] The `needs_conversation` bug looks fixed on the downloaded model — false on
      all 8 debates, including the plainly factual ones.
- [ ] **Re-score the fixtures at Q5_K_M.** The 7-of-8 figure was measured on the
      4-bit quantisation. The 5-bit one should be the same or better and has not
      been run, so the number in the README is inherited rather than observed.
- [ ] **Nobody has read an assumption the real model produced.** The screen, the
      grammar, the filter and the prompt are all in place and tested, but every
      example anyone has looked at is the seeded one from `-seedAssumptions`.
      Whether the assumptions it finds are the *interesting* ones is exactly the
      kind of question only reading answers — the same open question as the crux.

## The downloaded model — what's untested

- [ ] The download itself has only been exercised by unit tests over its pieces
      (checksum, install, replace, free-space). The background `URLSession` path
      — locking the phone mid-download, resuming, running out of space at 90% —
      needs a real device.
- [x] `handleEventsForBackgroundURLSession` is implemented, and the downloader is
      rebuilt on every launch so a transfer that finished while the app was shut
      is delivered. Both still need a real device to confirm.
- [ ] Memory on a 4 GB phone (iPhone 11, 12 mini). The model is 1.1 GB plus the
      context; `llama_init_from_model` returning null is handled and surfaces as
      "there isn't enough free memory", but it has not been seen happen.
- [ ] Loading the model takes tens of seconds on first use and currently happens
      behind the ordinary spinner. If it's as slow as feared, it needs its own
      screen saying what it's doing.

## Found this pass, not yet done

- [ ] **The write-up splices their words into a clause and it does not always
      fit.** Someone answered "what would change your mind" with "Being fat", and
      the last screen read "Noah would change their mind if being fat." Another
      answered "If I applied and they rejected me personally", which arrives as
      "Henry would change their mind if I applied and they rejected me
      personally" — their "I" reading as the app's. Their words are correct and
      the sentence around them is not. Left alone deliberately: every fix is a
      copy decision, and rewriting what somebody typed is worse than an awkward
      join. Options are to quote it ("Noah would change their mind if: being
      fat"), or to give it its own line under the paragraph rather than inside a
      sentence.
- [ ] **Twelve words is a guess, and probably a generous one.** `Dispute.
      minimumPositionWords` is the point below which the assisted path refuses to
      run. It was set where a five-word position fails and a terse-but-real one
      passes, and then an integration test showed thirteen words getting through
      the gate and failing anyway: "We should move closer to my work. The commute
      is eating my evenings." is long enough to pass and still gives the model
      almost nothing to draw a third-person claim out of, because all of it is
      about the person rather than the subject. Length is a proxy for the thing
      that actually matters. Raising the number would catch that case and start
      turning away real ones, so it is left where it is until somebody has seen it
      in front of two people who wanted to get on with the argument.
- [ ] **A fabricated stance cannot be detected by how much of it is their
      words.** The Starbucks crux said "Starbucks is good because it's a
      well-known brand with a wide range of products", which nobody had said.
      Measured as the share of a stance's meaningful words appearing anywhere in
      the session, it scores 0.40 against a median of 0.43 over 204 stances, with
      93 of the 204 at or below it. No threshold separates them, so there is no
      filter, and invention stays a thing only reading catches.

- [x] The three-way phone messaging is gone. Every iPhone downloads the same
      model, so there is no `builtInButOff` case, no route through iOS Settings,
      and no device table to keep current. See DECISIONS → "One model on every
      phone".

## Known gaps

- [ ] No history UI. One session is saved and resumed; past disputes aren't kept.
      Deliberate for the MVP, but worth revisiting.
- [ ] Application Support is included in device backups. If argument text should
      never leave the phone even via iCloud, set `isExcludedFromBackupKey` on the
      storage directory.
- [ ] No app icon. Needed before TestFlight.
- [ ] VoiceOver labels are in place but have not been tested with the screen
      reader actually running, nor has Dynamic Type at its largest sizes.
- [ ] Xcode's editor shows "No such module 'DisputeCore'" in Swift files — a
      SourceKit indexing quirk with the local package. `xcodebuild` is green.

## Decisions now settled

- Recursion stops at depth 3, plus a per-branch "that's just what I value".
- The steelman gate is uncapped — they keep going until both agree they've been
  understood, with a suggested rewrite offered after three misses.
- Emotional cruxes are framed as "worth talking through rather than settling".
- Storage is one local JSON file, not SwiftData. See ARCHITECTURE.

## Later versions

Voice input; two-device mode; resolution follow-ups; templates by argument type;
export; more than two people. See PROJECT_PLAN → MVP scope → Out.

## On-device performance — the live risk

- [ ] **Everything in DECISIONS → "What the model costs the phone" needs
      measuring on hardware.** Four changes went in off the back of one report
      that the app made the whole phone unusable: the thread count is down from
      five to two on a phone, the loaded model is released on backgrounding and
      on memory pressure, the key/value cache is down from ~470 MB to ~176 MB,
      and every engine call runs at `.utility`. None of it can be checked in a
      simulator, which has a Mac's cores and nothing else competing for them.
      What to look for: whether other apps still stutter *after* a session, what
      Instruments reports as the app's footprint while it sits in the background,
      and how much slower a session got in exchange.
- [ ] **The lean llama.cpp context has never initialised on a real GPU.** Q8_0
      key/value cache plus flash attention is the memory-lean configuration and
      also the one a backend is most likely to refuse. `LlamaRunner.makeContext`
      falls back to plain parameters if it fails, so the failure is soft — but if
      it is silently falling back on every phone, the cache saving above is
      imaginary. Worth a log line on a device before trusting the number.
- [ ] **Claim generation is slow.** One structured generation of eight claim
      objects took minutes and pinned the device hard enough that the simulator
      stopped redrawing. Now split into two calls of three plain strings each,
      which is far lighter — but measure it on real hardware, which is faster
      than the simulator.
- [ ] If it's still slow: cut to two claims per side, or generate the first
      person's list while they're still typing their position.
- [x] The spinner has a floor. `ThinkingView` explains why it's slow at 10s and
      says it hasn't frozen at 30s. Time-based rather than progress-based: the
      model reports no progress, and a fake bar stalling at 80% is worse than
      none. Thresholds unverified against real hardware.

## Found while testing on-device

- [ ] `needs_conversation` was coming back **true on every crux**, including
      plainly factual ones ("is the move cost greater than the raise?"). The
      prompt now says "almost always false" and defines the narrow case. Not yet
      re-measured — check this first when scoring the fixtures.
