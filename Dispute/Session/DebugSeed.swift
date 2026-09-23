#if DEBUG
import Foundation
import DisputeCore

/// Launches the app straight into a given stage, for development and
/// screenshots. Debug builds only — this never ships.
///
///     xcrun simctl launch <device> com.jamesgpuckett.Dispute -seedStage checklist
enum DebugSeed {
    /// Every default the app persists. Must be kept in step with the
    /// `@AppStorage` keys and `AIAvailability.enabledKey`.
    ///
    /// Listed by hand, which is annoying, because the two ways of avoiding that
    /// both fail here and fail *silently*:
    ///
    /// - `removePersistentDomain(forName:)` is documented as unreliable for an
    ///   app's own bundle identifier, and measurably leaves the values readable;
    /// - `persistentDomain(forName:)` returns nil for the app's own domain, so
    ///   enumerating it to find the keys clears nothing at all.
    ///
    /// Both versions of this shipped and neither reset anything. If you add a
    /// stored default, add it here, and check `-freshInstall` still lands on the
    /// first-run screen.
    private static let storedKeys = [
        "hasSeenIntroduction",
        "aiEnabled",
        // Whether the AI question has been answered. Without this in the list,
        // `-freshInstall` lands on the introduction with the choice already
        // made, which is the one state a fresh install cannot be in.
        "aiChoiceMade",
        "appearance",
        "hapticsEnabled",
        SessionViewModel.assumptionsEnabledKey,
    ]

    /// Puts the app back to how it looks on a phone it has never run on before:
    /// introduction unseen, AI off, saved argument gone.
    ///
    /// What this cannot clear is anything written by `simctl spawn defaults
    /// write`, which lands outside the app's sandbox and takes precedence. That
    /// is why `test-on-mac.sh` deletes those itself before every fresh run.
    static func resetIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-freshInstall") else { return }

        let defaults = UserDefaults.standard
        for key in Self.storedKeys { defaults.removeObject(forKey: key) }

        try? DisputeStore().deleteEverything()
    }

    /// Whether this launch was told to jump straight to a stage.
    ///
    /// The first-run sheet is modal and `interactiveDismissDisabled`, so without
    /// checking this, `-seedStage crux` lands on the introduction and stays
    /// there — the seed silently does nothing, which is worse than not having it.
    static var isSeeded: Bool {
        stageFromLaunchArguments() != nil
    }

    /// Land on the follow-up screen at the end of a checklist turn, rather than
    /// on the list.
    ///
    /// Reaching it by hand means ticking a whole list first, which is six taps
    /// before you can look at the screen you changed. Use with
    /// `-seedStage checklist -seedSkipHandoff`.
    static var startsOnSecondLook: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedSecondLook")
    }

    /// Land on the entry screen as it is on the *second* visit, after the
    /// checklist could not be built from what they wrote.
    ///
    /// Both halves of that flow are otherwise reachable only by getting a real
    /// model to hand both positions back, which is a thing that happens when
    /// nobody is watching and refuses to happen when somebody is. Use with
    /// `-seedStage positions -seedSkipHandoff`, and note that the seeded
    /// positions are the ones `DebugSeed.dispute(at:)` fills in, so Done stays
    /// held until you type into the box.
    static var startsAfterFailedClaims: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedAfterFailedClaims")
    }

    /// Put the list on the checklist screen without a model writing it.
    ///
    /// The checklist seed deliberately stops *before* the list exists, because
    /// that is the state somebody is in when they arrive and the app then goes
    /// and fills it. Correct for using the app, wrong for photographing it: the
    /// App Store screenshot of the one screen this whole app is about needed a
    /// live model, which meant it needed a key, which meant that whenever the
    /// key was missing the shot came out as the failure screen instead — and a
    /// picture of "That API key wasn't accepted" went up on the listing.
    ///
    /// The claims are the same ones every other seeded screen uses, with nobody's
    /// answers on them, which is what the list looks like the moment it appears.
    ///
    ///     -seedStage checklist -seedSkipHandoff -seedClaims
    static var startsWithClaims: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedClaims")
    }

    /// Put the crux on the crux screen without a model finding it.
    ///
    /// Same reason as `-seedClaims`, and the same failure: `-seedStage crux`
    /// stops with the crux still to be found, so photographing that screen meant
    /// a live call or a picture of an error.
    ///
    ///     -seedStage crux -seedSkipHandoff -seedCrux
    static var startsWithCrux: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedCrux")
    }

    /// Lands on the assumptions screen, with two flags already on it.
    ///
    /// Same reasoning as `-forceFailure` below. That screen appears only when a
    /// real model happens to find something in what two people wrote, which is
    /// not a thing that can be arranged: the mock engine only flags a position
    /// containing the word "always", and the real one takes a minute per run in
    /// the simulator and may well come back with nothing. Without this, the one
    /// screen in the app that says something about a person's own words back to
    /// them is the one screen nobody ever looks at.
    ///
    ///     -seedStage positions -seedSkipHandoff -seedAssumptions
    static var startsOnAssumptions: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedAssumptions")
    }

    /// The two flags that screen is seeded with.
    ///
    /// Written to be the awkward case rather than the flattering one: one flag
    /// per person, so the screen has to look even-handed, and both quoting
    /// something the seeded positions actually say.
    static var seededAssumptions: [AssumptionFlag] {
        [
            AssumptionFlag(
                party: .a,
                quote: "people are happier with the flexibility",
                assumption: "This takes it as given that what people prefer is the thing worth optimising for."
            ),
            AssumptionFlag(
                party: .b,
                quote: "mentoring and the accidental conversations happen",
                assumption: "This assumes those conversations cannot happen any other way than in person."
            ),
        ]
    }

    /// Hides the debug chrome — the beetle beside the gear — so a seeded screen
    /// can be photographed as it will actually ship.
    ///
    /// The App Store screenshots can only be taken from a debug build, because
    /// everything that reaches these screens without a live model and a real
    /// argument is `#if DEBUG`. Without this the listing shows a beetle that no
    /// released copy of the app has, on every screen.
    ///
    ///     -seedStage crux -seedSkipHandoff -screenshotMode
    static var isScreenshot: Bool {
        ProcessInfo.processInfo.arguments.contains("-screenshotMode")
    }

    /// Makes the engine fail on demand, so the screens that handle failure can be
    /// looked at without waiting for a model to produce the failure by itself.
    ///
    /// Both of these are states the app is *expected* to reach — a position with
    /// too little in it, and a safety refusal on a heated argument — and both were
    /// previously only ever seen by accident, in a session somebody was in the
    /// middle of and not reading carefully.
    ///
    ///     -seedStage checklist -seedSkipHandoff -forceFailure notEnough
    static var forcedFailure: EngineError? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-forceFailure"),
              let name = arguments[safe: flagIndex + 1]
        else { return nil }

        return switch name {
        case "notEnough": .notEnoughToWorkWith
        case "refused": .refused(cause: .safety, explanation: nil)
        case "timedOut": .timedOut
        case "truncated": .truncated
        case "malformed": .malformedResponse("the answer was not readable text")
        // The three the hosted path made ordinary. `rateLimited` in particular
        // is no longer an edge case worth reaching by accident: the free quota
        // is shared between everybody using the app, so this is the screen most
        // likely to be somebody's first sight of the AI not working.
        case "rateLimited": .rateLimited()
        case "offline": .offline
        case "badKey": .refused(cause: .key, explanation: nil)
        case "appRefused": .refused(cause: .app, explanation: nil)
        default: nil
        }
    }

    static func stageFromLaunchArguments() -> SessionStage? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-seedStage"),
              let raw = arguments[safe: flagIndex + 1],
              let stage = SessionStage(rawValue: raw)
        else { return nil }
        return stage
    }

    /// A dispute wound forward to `stage`, satisfying each gate on the way.
    ///
    /// The mode matters: a manual seed has to carry the points each person would
    /// have written, or the positions gate never opens and the seed lands on a
    /// screen it was told to skip.
    static func dispute(at stage: SessionStage, mode: DisputeMode = .assisted) -> Dispute {
        var dispute = Dispute(
            title: "Remote work vs office work",
            mode: mode,
            names: PartyPair(a: "Alex", b: "Sam")
        )
        if stage == .setup { return dispute }

        try? dispute.advance()
        // Ordinarily this stage is seeded with an empty box, because that is what
        // the screen looks like when anyone reaches it. The one exception is the
        // second visit after a checklist that could not be built, which is
        // *defined* by there already being something in the box to add to.
        if stage == .positions, !startsAfterFailedClaims { return dispute }

        // Deliberately not the nuclear example that used to live in the prompt:
        // the bug being guarded against is the model drifting onto a topic
        // nobody raised.
        dispute.positions = PartyPair(
            a: "Most knowledge work goes fine from home and people are happier with the flexibility.",
            b: "Being in the office is where mentoring and the accidental conversations happen."
        )
        // Filled in, and going no further: the stage asked for is `positions`.
        if stage == .positions { return dispute }

        dispute.setPoints(
            [
                "Most knowledge work needs no physical presence.",
                "Flexibility makes people happier at work.",
            ],
            for: .a
        )
        dispute.setPoints(
            [
                "Mentoring junior people works worse over video.",
                "Culture erodes without regular in-person contact.",
            ],
            for: .b
        )
        try? dispute.advance()
        if stage == .checklist {
            // The follow-up screen needs a list that has been ticked, so the
            // first person's answers go in and the second person's do not —
            // exactly the state someone is in when they reach it.
            if startsOnSecondLook {
                dispute.claims = seededClaims.map { claim in
                    var claim = claim
                    claim.agreement.b = nil
                    return claim
                }
            } else if startsWithClaims {
                // The list as it looks the moment it appears: written, and
                // nobody has answered it yet.
                dispute.claims = seededClaims.map { claim in
                    var claim = claim
                    claim.agreement = PartyPair(a: nil, b: nil)
                    return claim
                }
            }
            return dispute
        }

        dispute.claims = seededClaims
        // Both second looks filled in, because every screen after the checklist
        // now reads from them — a seed without them shows the crux and the
        // write-up in a state only an argument where nobody crossed anything out
        // can produce.
        seedSecondLooks(&dispute)
        try? dispute.advance()
        if stage == .crux {
            if startsWithCrux { dispute.crux = seededCrux }
            return dispute
        }

        dispute.crux = seededCrux
        try? dispute.advance()
        return dispute
    }

    /// The crux every seeded screen past the checklist shows.
    ///
    /// Its own property because two places need it now — the summary seed, which
    /// always had it, and `-seedCrux`, which exists so the crux screen can be
    /// photographed without spending a real call to find one.
    private static var seededCrux: Crux {
        Crux(
            question: "How much does informal contact actually contribute, compared with flexibility?",
            positions: PartyPair(a: "Less than people assume", b: "More than output numbers show"),
            test: "Ask the three most recent joiners what they learned by overhearing, "
                + "and compare that against what the team shipped in the same period."
        )
    }

    private static func seedSecondLooks(_ dispute: inout Dispute) {
        for party in Party.allCases {
            guard let rejected = dispute.rejectedClaims(by: party).first else { continue }
            dispute.setRethink(
                Rethink(
                    claimID: rejected.id,
                    bestCase: party == .a
                        ? "Someone starting out has nobody to overhear, and that is most of how you learn a job."
                        : "Plenty of deep work genuinely does go better without anyone within earshot.",
                    changeCondition: party == .a
                        ? "If the juniors themselves said they were learning less"
                        : "If two years of output showed no difference either way"
                ),
                for: party
            )
        }
    }

    /// Answered by both, with a genuine split, so the crux screen has material.
    private static var seededClaims: [Claim] {
        [
            ("Flexibility makes people happier at work.", Party.a, true, true),
            ("Most knowledge work needs no physical presence.", .a, true, false),
            ("Mentoring junior people works worse over video.", .b, false, true),
            ("Informal conversation drives most good ideas.", .b, false, true),
            ("Output is easy to measure without watching people.", .a, true, false),
            ("Culture erodes without regular in-person contact.", .b, false, true),
        ].map { text, origin, a, b in
            Claim(text: text, origin: origin, agreement: PartyPair(a: a, b: b))
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
