import Foundation

/// One argument, start to finish.
///
/// The single owner of session state. `stage` is `private(set)` so it can only
/// move through `advance()`, which enforces both the ordering and the per-stage
/// requirements — the rules cannot be bypassed by assigning a stage from a view.
public struct Dispute: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public private(set) var stage: SessionStage
    /// Whether a model does the middle step or the two people do it themselves.
    /// Decided when the session starts — see `DisputeMode`.
    ///
    /// It can change once, in one direction, part of the way through: see
    /// `continueByHand()`. Never the other way. Assisted needs a list the model
    /// wrote, and by the time somebody has given up on it they are past the
    /// screen that would have built one.
    public private(set) var mode: DisputeMode
    /// What the two people are actually called.
    ///
    /// "Person A" and "Person B" made testers feel the app had assigned them a
    /// side. Real names remove the question, and make every later screen read
    /// like it's about them rather than about slots.
    public var names: PartyPair<String>
    public var positions: PartyPair<String>
    /// In manual mode, the points each person drew out of their own view.
    ///
    /// Written on the same turn as the position, so the phone still changes
    /// hands exactly twice. Empty in assisted mode, where the model does this.
    public var ownPoints: PartyPair<[String]>
    /// The combined list both people work through. Drawn from both positions.
    public var claims: [Claim]
    /// What each position takes for granted, shown once between the two stages.
    public var assumptionFlags: [AssumptionFlag]
    /// Whether that screen has already been shown in this session.
    ///
    /// **This is what stops the loop**, and the loop was bad enough to be worth
    /// spelling out. The assumptions screen offers "go back and add to it", which
    /// returns to the positions stage and clears everything derived from it —
    /// including the flags. Both people then rewrite, the positions stage ends,
    /// the assumption pass runs again on the new text, finds assumptions again
    /// (there are always assumptions), and puts them back on the same screen. The
    /// only ways out were to force-quit the app or to notice that the smaller,
    /// quieter button was the way forward.
    ///
    /// So the screen is shown **at most once per argument**. Going back after it
    /// does what it says — lets them add to what they wrote — and then carries on
    /// to the checklist instead of asking again. Deliberately *not* cleared by
    /// `returnToPositions`, which is the whole point: it has to survive the thing
    /// that clears everything else.
    ///
    /// Persisted, so a resumed session does not show it a second time either.
    public var hasShownAssumptions: Bool
    /// How many times building the checklist has failed for lack of material.
    ///
    /// The other loop, and the same shape: `notEnoughToWorkWith` sends them to a
    /// screen asking for more words, which sends them back to the positions
    /// stage, which can fail the same way again. Counted so that the second
    /// failure ends it — see `SessionStage` handling in the view model. Nobody
    /// gets asked a third time.
    public var failedClaimAttempts: Int
    /// Each person's second look at a point they crossed out — see `Rethink`.
    /// Written on the same turn as the ticking, so the phone still changes hands
    /// the same number of times as before.
    public var rethinks: PartyPair<Rethink?>
    /// The one question underneath the argument.
    ///
    /// Singular, and it was not always. The app used to show up to two, and
    /// testers read a screen with two questions on it as the app hedging —
    /// picking one is the entire job, and a list of them is what they already
    /// had before they opened it. `nil` until it has been found or written.
    public var crux: Crux?
    /// The written record of the argument, shown at the end.
    ///
    /// Composed on the phone from everything below, on every phone, with no
    /// model involved. A model used to be given the chance to say the same facts
    /// more fluently; it is not any more, so this is now the only version there
    /// is. See `ArgumentRecap`.
    public var recap: String

    /// How many points one person must write before their turn can end.
    ///
    /// Two each is the floor because four claims is the shortest list a crux can
    /// be found in — see `Claim.minimumUsableClaims`. Three is what the screen
    /// asks for, and what the model is asked for in assisted mode, so both modes
    /// produce a list of the same length.
    public static let requiredPointsEach = 2
    public static let suggestedPointsEach = 3
    public static let maximumPointsEach = 4

    public init(
        id: UUID = UUID(),
        title: String = "",
        createdAt: Date = Date(),
        stage: SessionStage = .setup,
        mode: DisputeMode = .assisted,
        names: PartyPair<String> = PartyPair(both: ""),
        positions: PartyPair<String> = PartyPair(both: ""),
        ownPoints: PartyPair<[String]> = PartyPair(both: []),
        claims: [Claim] = [],
        assumptionFlags: [AssumptionFlag] = [],
        hasShownAssumptions: Bool = false,
        failedClaimAttempts: Int = 0,
        rethinks: PartyPair<Rethink?> = PartyPair(both: nil),
        crux: Crux? = nil,
        recap: String = ""
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.stage = stage
        self.mode = mode
        self.names = names
        self.positions = positions
        self.ownPoints = ownPoints
        self.claims = claims
        self.assumptionFlags = assumptionFlags
        self.hasShownAssumptions = hasShownAssumptions
        self.failedClaimAttempts = failedClaimAttempts
        self.rethinks = rethinks
        self.crux = crux
        self.recap = recap
    }

    /// Decoded by hand so that a session saved before a field existed still
    /// loads. `DisputeStore` treats a decode failure as "no saved session", so a
    /// synthesised initialiser would silently throw away an argument in progress
    /// the first time someone updated the app.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        stage = try container.decode(SessionStage.self, forKey: .stage)
        names = try container.decode(PartyPair<String>.self, forKey: .names)
        positions = try container.decode(PartyPair<String>.self, forKey: .positions)
        claims = try container.decode([Claim].self, forKey: .claims)
        // A session saved by a version that fact checked has `factFlags` and no
        // `assumptionFlags`. Those flags said whether something was *true*, which
        // is a judgement this app no longer makes about anybody, so they are
        // dropped rather than translated: there is no honest way to turn "the
        // record shows a 12% rise" into a sentence about what the argument takes
        // for granted. Decoding to an empty list is what makes the difference
        // between a resumed argument and a lost one — see the note above.
        assumptionFlags = try container.decodeIfPresent(
            [AssumptionFlag].self,
            forKey: .assumptionFlags
        ) ?? []
        // A session saved before the loop was fixed is assumed to have seen the
        // screen already. Guessing "yes" is the safe direction: the worst case is
        // one person not being shown their assumptions on a resumed argument,
        // against a worst case the other way of dropping them straight back into
        // the loop the moment they reopen the app.
        hasShownAssumptions = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasShownAssumptions
        ) ?? !(try container.decodeIfPresent([AssumptionFlag].self, forKey: .assumptionFlags) ?? []).isEmpty
        failedClaimAttempts = try container.decodeIfPresent(Int.self, forKey: .failedClaimAttempts) ?? 0
        mode = try container.decodeIfPresent(DisputeMode.self, forKey: .mode) ?? .assisted
        ownPoints = try container.decodeIfPresent(
            PartyPair<[String]>.self,
            forKey: .ownPoints
        ) ?? PartyPair(both: [])
        rethinks = try container.decodeIfPresent(
            PartyPair<Rethink?>.self,
            forKey: .rethinks
        ) ?? PartyPair(both: nil)
        recap = try container.decodeIfPresent(String.self, forKey: .recap) ?? ""

        // A session saved when the app still showed a list of cruxes keeps its
        // first one, which was always the one it called most important. Read
        // through a second key type rather than an unused case on `CodingKeys`,
        // so the encoder has no way to start writing the old shape again.
        if let crux = try container.decodeIfPresent(Crux.self, forKey: .crux) {
            self.crux = crux
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            self.crux = (try legacy.decodeIfPresent([Crux].self, forKey: .cruxes))?.first
        }
    }

    private enum LegacyKeys: String, CodingKey {
        case cruxes
    }

    // MARK: - Progress

    /// Why the session cannot leave the current stage yet, or `nil` if it can.
    public var blockerForAdvancing: String? {
        switch stage {
        case .setup:
            if title.trimmed.isEmpty {
                "the argument needs a name"
            } else if !names.allSatisfy({ !$0.trimmed.isEmpty }) {
                "both of you need to put your name in"
            } else {
                nil
            }

        case .positions:
            if !positions.allSatisfy({ !$0.trimmed.isEmpty }) {
                "both of you need to say what you think"
            } else if mode == .manual && !Party.allCases.allSatisfy(hasEnoughPoints) {
                "both of you need to write at least \(Self.requiredPointsEach) points"
            } else if mode == .assisted && !Party.allCases.allSatisfy(hasEnoughToWorkWith) {
                "say a bit more about why, so there's something to pull apart"
            } else {
                nil
            }

        case .checklist:
            claims.isEmpty
                ? "no points have been drawn out yet"
                : (claims.allSatisfy(\.isAnsweredByBoth)
                    ? nil
                    : "both of you need to go through the list")

        case .crux:
            // No crux is a legitimate answer here: it means they ticked
            // everything the same way and there is nothing left to disagree
            // about. Requiring one regardless left the button dead with no
            // way forward.
            (crux == nil && !contestedClaims.isEmpty)
                ? (mode == .manual
                    ? "name the question underneath the argument"
                    : "no crux has been found yet")
                : nil

        case .summary:
            nil
        }
    }

    public var canAdvance: Bool {
        !stage.isTerminal && blockerForAdvancing == nil
    }

    /// Moves to the next stage, if the current one's requirements are met.
    public mutating func advance() throws {
        guard let next = stage.next else { throw DisputeError.alreadyAtFinalStage }
        if let blocker = blockerForAdvancing {
            throw DisputeError.notReadyToAdvance(stage: stage, reason: blocker)
        }
        stage = next
    }

    /// What to call someone, falling back to a neutral label so nothing ever
    /// renders blank.
    public func name(for party: Party) -> String {
        let entered = names[party].trimmed
        if !entered.isEmpty { return entered }
        return switch party {
        case .a: "First person"
        case .b: "Second person"
        }
    }

    /// The shortest position the assisted path can do anything with.
    ///
    /// A real session had one side write "I like the smores frappe" and stop.
    /// Asked for three claims that view depends on, the model has two ways to
    /// answer and both are wrong: hand the sentence back, which it did, or make
    /// something up, which it also did. No model fixes this. There are not three
    /// claims in five words, and a bigger one would only invent more fluently.
    ///
    /// Twelve words is deliberately low. It is not a standard for a good
    /// position, it is the point below which the next screen cannot be built,
    /// and someone mid-argument being told to write an essay would close the
    /// app. Manual mode has no such floor: there the points are typed by hand
    /// and a short position is only context.
    public static let minimumPositionWords = 12

    /// Whether this person wrote enough for a model to draw points out of.
    public func hasEnoughToWorkWith(_ party: Party) -> Bool {
        positions[party].split(whereSeparator: \.isWhitespace).count >= Self.minimumPositionWords
    }

    /// Words the two of them write as names, taken from everything they typed.
    ///
    /// The app splices their sentences into its own — "Henry says …", "Is it
    /// true that …?" — which means lowercasing a first letter that was a capital
    /// on purpose. Their own words are the only dictionary worth consulting for
    /// that: whatever they are arguing about is in here, spelled the way they
    /// spell it. See `String.midSentence(keeping:)`.
    public var capitalisedNames: Set<String> {
        var source = [title, positions[.a], positions[.b]]
        source += claims.map(\.text)
        source += ownPoints[.a] + ownPoints[.b]
        return source.joined(separator: "\n").capitalisedNames
    }

    public var unacknowledgedFlags: [AssumptionFlag] {
        assumptionFlags.filter { !$0.isAcknowledged }
    }

    public mutating func acknowledgeAllFlags() {
        for index in assumptionFlags.indices { assumptionFlags[index].isAcknowledged = true }
    }

    /// Steps back so someone can rewrite what they said.
    ///
    /// The only way backwards. Needed because the model's safety filters can
    /// decline a position outright, and before this the only escape was to throw
    /// the whole session away and start again. Downstream work is cleared
    /// because it was derived from text that is about to change.
    public mutating func returnToPositions() {
        stage = .positions
        claims = []
        assumptionFlags = []
        rethinks = PartyPair(both: nil)
        crux = nil
        recap = ""
        // `hasShownAssumptions` and `failedClaimAttempts` deliberately survive.
        // They are the record of what this session has already asked of these two
        // people, and clearing them here is precisely what turned "go back and
        // add to it" into a screen they could not get past. See the fields.
    }

    /// The checklist, built out of the two positions when nothing else worked.
    ///
    /// A last resort, and the thing that guarantees the assisted path cannot
    /// dead-end. `notEnoughToWorkWith` sends someone to a screen asking them to
    /// write more; if the second attempt fails too, asking a third time is the
    /// app blaming them for a model's limitation. Their sentences are not claims
    /// drawn out of their reasoning — they are just what they wrote, split up —
    /// but a list they can tick beats a screen they cannot leave.
    ///
    /// Deduplicated and interleaved by the same rules as every other list, so
    /// nothing downstream can tell this one apart.
    /// Gives up on the model for the rest of this session, and makes a checklist
    /// out of what the two of them already wrote.
    ///
    /// The way out of the failures nobody in the room can do anything about: the
    /// free quota is spent, the phone has no signal, the provider is having an
    /// afternoon. Before this existed those all ended at a screen offering "try
    /// again" against something that was not going to work for hours, which is a
    /// dead end with a button on it.
    ///
    /// One way, and for the rest of the session. Somebody who has just been told
    /// to wait until tomorrow is not looking for a setting to keep an eye on;
    /// they are two people mid-argument who would like to finish it. Reaching the
    /// crux screen and being asked to wait a second time is the failure this is
    /// meant to end, not a state worth preserving the option of.
    ///
    /// The list comes from their own sentences rather than their own points,
    /// because an assisted session never asked them for points — that is the
    /// question the model was there to answer. Same fallback the app already uses
    /// when two rounds of asking produce nothing usable.
    public mutating func continueByHand() {
        mode = .manual
        buildClaimsFromPositions()
    }

    public mutating func buildClaimsFromPositions() {
        guard claims.isEmpty else { return }
        claims = Claim.deduplicated(
            Claim.interleave(
                sentences(in: positions[.a]).map { Claim(text: $0, origin: .a) },
                sentences(in: positions[.b]).map { Claim(text: $0, origin: .b) }
            )
        )
    }

    /// Sentences long enough to be worth ticking, at most three per person.
    ///
    /// Three because that is what both other paths produce, so the checklist is
    /// the same length however it was built. The length floor drops "Yes." and
    /// "I disagree", which are not things the other person can meaningfully
    /// answer.
    private func sentences(in position: String) -> [String] {
        position
            .split(whereSeparator: { ".!?\n".contains($0) })
            .map { String($0).trimmed }
            .filter { $0.split(whereSeparator: \.isWhitespace).count >= 4 }
            .prefix(Self.suggestedPointsEach)
            .map { $0.hasSuffix(".") ? $0 : $0 + "." }
    }

    // MARK: - Points written by hand

    /// The points one person wrote, with blanks dropped.
    public func points(for party: Party) -> [String] {
        ownPoints[party].map(\.trimmed).filter { !$0.isEmpty }
    }

    public func hasEnoughPoints(_ party: Party) -> Bool {
        points(for: party).count >= Self.requiredPointsEach
    }

    public mutating func setPoints(_ points: [String], for party: Party) {
        ownPoints[party] = Array(points.prefix(Self.maximumPointsEach))
    }

    /// Builds the checklist out of what the two of them wrote themselves.
    ///
    /// The same two rules the assisted path uses — alternate the two batches so
    /// the list doesn't read as "their points, then mine", and drop
    /// near-duplicates — so a manual list behaves like a generated one from the
    /// checklist onwards. Nothing downstream can tell which mode built it.
    public mutating func buildClaimsFromOwnPoints() {
        guard claims.isEmpty else { return }
        claims = Claim.deduplicated(
            Claim.interleave(
                points(for: .a).map { Claim(text: $0, origin: .a) },
                points(for: .b).map { Claim(text: $0, origin: .b) }
            )
        )
    }

    // MARK: - Claims

    public func claimsAwaiting(_ party: Party) -> [Claim] {
        claims.filter { !$0.isAnswered(by: party) }
    }

    public func hasFinishedChecklist(_ party: Party) -> Bool {
        !claims.isEmpty && claims.allSatisfy { $0.isAnswered(by: party) }
    }

    /// Where the two disagree. The raw material for a crux.
    public var contestedClaims: [Claim] {
        claims.filter(\.isContested)
    }

    /// What they both signed up to — usually more than either expected.
    public var sharedClaims: [Claim] {
        claims.filter { $0.isShared || $0.isMutuallyRejected }
    }

    // MARK: - Second looks

    /// The points this person crossed out, which are the only ones they can be
    /// asked to argue for.
    ///
    /// Available the moment they finish ticking, so the first person is asked
    /// this on their own turn rather than waiting on the second — the two of
    /// them answer in the same conditions, neither having seen the other.
    public func rejectedClaims(by party: Party) -> [Claim] {
        claims.filter { $0.agreement[party] == false }
    }

    /// Whether this person still owes the follow-up.
    ///
    /// Someone who ticked every row is not asked: there is nothing they
    /// rejected, and inventing a prompt for them would be busywork on the one
    /// screen that has to feel worth the typing.
    public func owesRethink(_ party: Party) -> Bool {
        !rejectedClaims(by: party).isEmpty && rethinks[party]?.isComplete != true
    }

    public mutating func setRethink(_ rethink: Rethink, for party: Party) {
        rethinks[party] = Rethink(
            claimID: rethink.claimID,
            bestCase: rethink.bestCase.trimmed,
            changeCondition: rethink.changeCondition.trimmed
        )
    }

    /// The claim someone's second look was about, looked back up.
    public func claim(withID id: UUID) -> Claim? {
        claims.first { $0.id == id }
    }

    @discardableResult
    public mutating func setAgreement(
        _ agrees: Bool,
        for party: Party,
        claimID: UUID
    ) -> Bool {
        guard let index = claims.firstIndex(where: { $0.id == claimID }) else { return false }
        claims[index].setAgreement(agrees, for: party)
        return true
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public extension String {
    /// Whether this is genuinely different writing from `previous`, rather than
    /// the same words with the whitespace moved.
    ///
    /// The entry screen holds its Done button on this after a checklist that
    /// could not be built: the text already there is long enough to pass every
    /// other gate, so without this the button is live on arrival and pressing it
    /// spends another half minute reaching the same screen.
    ///
    /// A low bar on purpose — any real edit clears it. It is here to stop an
    /// accidental identical re-run, not to judge whether the rewrite was any
    /// good, and it is in this layer rather than in the view because a rule about
    /// what a session will accept is not a detail of how a screen draws itself.
    func isDifferentWriting(from previous: String) -> Bool {
        trimmed != previous.trimmed
    }
}
