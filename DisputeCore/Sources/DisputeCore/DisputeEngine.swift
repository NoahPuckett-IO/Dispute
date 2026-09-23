import Foundation

/// The reasoning behind a dispute session.
///
/// Everything the app needs an LLM for sits behind this protocol, so the whole
/// UI can be built against `MockDisputeEngine` — no API key, no network, no cost
/// — and nothing above this line depends on any particular model.
public protocol DisputeEngine: Sendable {
    /// Turns both positions into one combined list of checkable claims.
    ///
    /// Claims are deliberately interleaved rather than grouped by author: both
    /// people answer the same list, and knowing whose claim it is biases the
    /// answer.
    func breakDown(
        positionA: String,
        positionB: String,
        disputeTitle: String
    ) async throws -> [Claim]

    /// Names the underlying disagreement, given where the two answers differed.
    ///
    /// One question, or none. The app used to ask for a list and show all of it,
    /// and a screen with three questions on it is the argument they walked in
    /// with — picking the one that would actually move somebody is the job.
    /// `nil` means there is nothing left to disagree about, which is a real
    /// answer and not a failure.
    func findCrux(in dispute: Dispute) async throws -> Crux?

    /// What each position takes for granted without saying so.
    ///
    /// Both at once, in one call. It was one call each until the shared free tier
    /// ran out mid-argument on a day two people were testing: this pass was half
    /// of every session's requests, and it is the half nothing downstream depends
    /// on. One call also means one round trip on a screen that says "Reading what
    /// you both wrote…" rather than two of them end to end.
    ///
    /// The flags come back for both parties, each carrying its own, and the
    /// prompt is what keeps the two readings apart.
    ///
    /// Returning an empty array is a perfectly good answer and must stay cheap —
    /// this runs between the two turns and cannot become another wait.
    ///
    /// There is deliberately no counterpart that writes up the finished argument.
    /// `ArgumentRecap` composes that on the phone out of things that actually
    /// happened, instantly and on every device; handing it to a model to say
    /// again more fluently bought nothing and cost the last screen of the app a
    /// spinner at the exact moment two people had finished and wanted to stop.
    func findAssumptions(
        positionA: String,
        positionB: String,
        disputeTitle: String
    ) async throws -> [AssumptionFlag]

    /// Whether this engine is good enough at that to be allowed to try.
    ///
    /// Kept from the fact-checking version of this feature, where the answer for
    /// the on-device model was no. It is yes here, and the difference is what is
    /// being asked rather than how big the model is: naming what a paragraph
    /// takes for granted is a reading job over text the model has in front of it,
    /// where deciding whether a claim about the world is true is a knowledge job
    /// it has no way to do and no way to know it has failed at.
    var canFlagAssumptions: Bool { get }
}

public extension DisputeEngine {
    /// Opt-in: an engine that can't do this well should not pretend to.
    func findAssumptions(
        positionA: String,
        positionB: String,
        disputeTitle: String
    ) async throws -> [AssumptionFlag] { [] }

    var canFlagAssumptions: Bool { true }
}

/// A canned engine for building and testing the UI offline.
///
/// Deterministic by design: the same input always produces the same output, so
/// screenshots and walkthroughs are reproducible.
public struct MockDisputeEngine: DisputeEngine {
    public var latency: Duration
    public var failure: EngineError?

    public init(latency: Duration = .zero, failure: EngineError? = nil) {
        self.latency = latency
        self.failure = failure
    }

    private func pause() async throws {
        if let failure { throw failure }
        if latency > .zero { try? await Task.sleep(for: latency) }
    }

    public func breakDown(
        positionA: String,
        positionB: String,
        disputeTitle: String
    ) async throws -> [Claim] {
        try await pause()

        return [
            Claim(text: "\(positionA.condensed) is the most important factor here", origin: .a),
            Claim(text: "\(positionB.condensed) outweighs the alternative", origin: .b),
            Claim(text: "We have enough information to decide this now", origin: .a),
            Claim(text: "The cost of getting this wrong falls on both of us equally", origin: .b),
            Claim(text: "There is a version of this we would both accept", origin: .a),
        ]
    }

    public func findAssumptions(
        positionA: String,
        positionB: String,
        disputeTitle: String
    ) async throws -> [AssumptionFlag] {
        try await pause()

        // Deterministic trigger so the flag UI can be exercised offline, and one
        // position carrying it must not put a flag on the other — the screen
        // shows whose is whose.
        return zip(Party.allCases, [positionA, positionB]).compactMap { party, position in
            guard position.lowercased().contains("always") else { return nil }
            return AssumptionFlag(
                party: party,
                quote: "always",
                assumption: "This treats the usual case as the only case, with no exception allowed for."
            )
        }
    }

    public func findCrux(in dispute: Dispute) async throws -> Crux? {
        try await pause()

        guard let claim = dispute.contestedClaims.first else { return nil }

        return Crux(
            // `midSentence`, not `lowercasedFirst`: the claim ends in a full
            // stop, and folding it into a question without dropping that gives
            // "…no physical presence.?" on the one screen people photograph.
            question: "Is it true that \(claim.text.midSentence(keeping: dispute.capitalisedNames))?",
            positions: PartyPair(
                a: claim.agreement.a == true ? "Yes" : "No",
                b: claim.agreement.b == true ? "Yes" : "No"
            ),
            // Long enough and concrete enough to pass `Crux.hasTest`, so the
            // screen that shows it can be looked at offline. A canned engine
            // whose output the app then discards is a canned engine that proves
            // nothing about the screen it was meant to fill.
            test: "Agree on one number that would settle it, go and find that "
                + "number, and compare it against what you each expected."
        )
    }
}

extension String {
    /// First sentence or clause, trimmed — enough to read naturally when
    /// embedded in generated copy.
    var condensed: String {
        let firstSentence = split(separator: ".", maxSplits: 1).first.map(String.init) ?? self
        return firstSentence.trimmed
    }
}
