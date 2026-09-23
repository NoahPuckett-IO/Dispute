import XCTest
@testable import DisputeCore

final class ManualModeGatingTests: XCTestCase {
    private func started(_ mode: DisputeMode) -> Dispute {
        var dispute = Dispute(
            title: "Whether to move",
            mode: mode,
            names: PartyPair(a: "Alex", b: "Sam")
        )
        try? dispute.advance()
        return dispute
    }

    /// The whole point of manual mode: a position alone is not enough, because
    /// nothing downstream can build the checklist from it.
    func testManualModeNeedsPointsAsWellAsPositions() {
        var dispute = started(.manual)
        dispute.positions = PartyPair(a: "We should move.", b: "We should stay.")

        XCTAssertEqual(
            dispute.blockerForAdvancing,
            "both of you need to write at least 2 points"
        )

        dispute.setPoints(["The commute costs too much.", "Rent is cheaper there."], for: .a)
        XCTAssertFalse(dispute.canAdvance, "one person's points are not enough")

        dispute.setPoints(["The kids would change schools.", "Rent is higher in town."], for: .b)
        XCTAssertTrue(dispute.canAdvance)
    }

    /// Assisted mode must not inherit the points gate — the model writes the
    /// points there, after this stage is over. It has a gate of its own, on the
    /// length of the positions the model has to draw them out of, and no gate on
    /// anything either person has to fill in by hand.
    func testAssistedModeAsksForNoPointsOfItsOwn() {
        var dispute = started(.assisted)
        dispute.positions = PartyPair(
            a: "We should move closer to my work, because the commute is eating every evening.",
            b: "Moving takes the kids out of their school, and the rent in town is higher."
        )

        XCTAssertTrue(dispute.canAdvance)
        XCTAssertTrue(dispute.points(for: .a).isEmpty, "nobody was asked to write points")
    }

    /// And manual mode inherits nothing from the assisted gate. There the two of
    /// them write the points, so the position is only context and a short one
    /// costs nobody anything.
    func testManualModeAcceptsAShortPosition() {
        var dispute = started(.manual)
        dispute.positions = PartyPair(a: "We should move.", b: "We should stay.")
        dispute.setPoints(["The commute costs too much.", "Rent is cheaper there."], for: .a)
        dispute.setPoints(["The kids would change schools.", "Rent is higher in town."], for: .b)

        XCTAssertTrue(dispute.canAdvance)
    }

    func testBlankPointsDoNotCount() {
        var dispute = started(.manual)
        dispute.positions = PartyPair(a: "We should move.", b: "We should stay.")
        dispute.setPoints(["A real point.", "   ", ""], for: .a)
        dispute.setPoints(["One.", "Two."], for: .b)

        XCTAssertFalse(dispute.canAdvance)
        XCTAssertEqual(dispute.points(for: .a), ["A real point."])
    }

    func testMoreThanTheMaximumPointsAreDropped() {
        var dispute = started(.manual)
        dispute.setPoints(["1", "2", "3", "4", "5", "6"], for: .a)

        XCTAssertEqual(dispute.ownPoints[.a].count, Dispute.maximumPointsEach)
    }
}

final class ManualChecklistBuildingTests: XCTestCase {
    private func readyToBuild() -> Dispute {
        var dispute = Dispute(mode: .manual, names: PartyPair(a: "Alex", b: "Sam"))
        dispute.setPoints(["A one.", "A two.", "A three."], for: .a)
        dispute.setPoints(["B one.", "B two.", "B three."], for: .b)
        return dispute
    }

    /// Alternating matters as much here as it does for generated points: a list
    /// that reads "theirs, then mine" gives the hidden origin away on sight.
    func testTheTwoSidesAreInterleaved() {
        var dispute = readyToBuild()
        dispute.buildClaimsFromOwnPoints()

        XCTAssertEqual(dispute.claims.map(\.origin), [.a, .b, .a, .b, .a, .b])
    }

    func testEachPointKeepsItsAuthor() {
        var dispute = readyToBuild()
        dispute.buildClaimsFromOwnPoints()

        let fromA = dispute.claims.filter { $0.origin == .a }.map(\.text)
        XCTAssertEqual(fromA, ["A one.", "A two.", "A three."])
    }

    func testBuildingTwiceDoesNotDuplicateTheList() {
        var dispute = readyToBuild()
        dispute.buildClaimsFromOwnPoints()
        let first = dispute.claims
        dispute.buildClaimsFromOwnPoints()

        XCTAssertEqual(dispute.claims, first)
    }

    /// Two people arguing about the same thing write the same sentence more
    /// often than they expect to.
    func testNearDuplicatePointsAreDropped() {
        var dispute = Dispute(mode: .manual)
        dispute.setPoints(
            ["Moving would cost more in rent.", "The commute is too long.", "We can afford it."],
            for: .a
        )
        dispute.setPoints(
            ["Moving would cost more in rent.", "The kids would change schools.", "It is too far."],
            for: .b
        )
        dispute.buildClaimsFromOwnPoints()

        let texts = dispute.claims.map(\.text)
        XCTAssertEqual(texts.count, Set(texts).count, "a repeated point survived: \(texts)")
    }
}

final class ManualCruxTests: XCTestCase {
    func testADraftTurnsAPointIntoAQuestion() {
        let claim = Claim(
            text: "The raise would cover what the move costs.",
            origin: .a,
            agreement: PartyPair(a: true, b: false)
        )

        let draft = Crux.draft(from: claim)

        XCTAssertEqual(
            draft.question,
            "Is it true that the raise would cover what the move costs?"
        )
        XCTAssertEqual(draft.positions.a, "Yes")
        XCTAssertEqual(draft.positions.b, "No")
    }

    /// Lowercasing blindly would turn "AI will take these jobs" into "aI will…".
    func testADraftLeavesAcronymsAlone() {
        let claim = Claim(text: "AI will take these jobs.", origin: .a)

        XCTAssertEqual(
            Crux.draft(from: claim).question,
            "Is it true that AI will take these jobs?"
        )
    }

    func testAnUnansweredPointLeavesThePositionsBlankToFillIn() {
        let claim = Claim(text: "Rent is higher in town.", origin: .b)

        let draft = Crux.draft(from: claim)

        XCTAssertEqual(draft.positions.a, "")
        XCTAssertEqual(draft.positions.b, "")
    }

    /// Manual mode cannot advance until they've named something.
    func testTheCruxStageWaitsForThemToNameOne() {
        var dispute = Dispute(
            stage: .crux,
            mode: .manual,
            claims: [Claim(text: "One.", origin: .a, agreement: PartyPair(a: true, b: false))]
        )

        XCTAssertEqual(
            dispute.blockerForAdvancing,
            "name the question underneath the argument"
        )

        dispute.crux = Crux(question: "Is it?", positions: PartyPair(both: "Maybe"))
        XCTAssertTrue(dispute.canAdvance)
    }

    /// Where someone has already said what would change their mind about this
    /// exact point, that sentence is a better answer to show them than "No".
    func testADraftUsesWhatTheySaidWouldChangeTheirMind() {
        let claim = Claim(
            text: "The raise would cover what the move costs.",
            origin: .a,
            agreement: PartyPair(a: true, b: false)
        )
        let rethinks = PartyPair<Rethink?>(
            a: nil,
            b: Rethink(
                claimID: claim.id,
                bestCase: "The salary difference is real money.",
                changeCondition: "We wrote down a year of costs and it still came out ahead"
            )
        )

        let draft = Crux.draft(from: claim, rethinks: rethinks)

        XCTAssertEqual(draft.positions.a, "Yes")
        XCTAssertEqual(
            draft.positions.b,
            "No, unless we wrote down a year of costs and it still came out ahead"
        )
    }

    /// A second look about a different point must not be pulled onto this one.
    func testADraftIgnoresASecondLookAboutAnotherPoint() {
        let claim = Claim(text: "Rent is higher in town.", origin: .b,
                          agreement: PartyPair(a: false, b: true))
        let rethinks = PartyPair<Rethink?>(
            a: Rethink(claimID: UUID(), bestCase: "b", changeCondition: "something else entirely"),
            b: nil
        )

        XCTAssertEqual(Crux.draft(from: claim, rethinks: rethinks).positions.a, "No")
    }

    /// Ticking everything the same way is a real outcome, not a dead end. This
    /// gate used to have no exit: the engine is allowed to answer "they agree on
    /// everything" with an empty list, and the Continue button then stayed
    /// disabled forever with nothing on screen to do about it.
    func testAgreeingOnEverythingIsNotADeadEnd() {
        for mode in DisputeMode.allCases {
            let dispute = Dispute(
                stage: .crux,
                mode: mode,
                claims: [Claim(text: "One.", origin: .a, agreement: PartyPair(a: true, b: true))]
            )

            XCTAssertNil(dispute.blockerForAdvancing, "\(mode) is stuck with nothing contested")
            XCTAssertTrue(dispute.canAdvance, "\(mode) cannot leave the crux stage")
        }
    }
}

final class DisputeDecodingTests: XCTestCase {
    /// A session saved before these fields existed has to keep working. The
    /// store treats a decode failure as "no saved session", so getting this
    /// wrong silently throws away an argument in progress.
    func testASessionSavedBeforeManualModeExistedStillLoads() throws {
        let legacy = """
        {
          "id": "6C7C6B4E-3C09-4E51-9F0E-2F3B9E8E1A11",
          "title": "Whether to move",
          "createdAt": 774000000,
          "stage": "positions",
          "names": {"a": "Alex", "b": "Sam"},
          "positions": {"a": "Move.", "b": "Stay."},
          "claims": [],
          "factFlags": [],
          "cruxes": []
        }
        """.data(using: .utf8)!

        let dispute = try JSONDecoder().decode(Dispute.self, from: legacy)

        XCTAssertEqual(dispute.title, "Whether to move")
        XCTAssertEqual(dispute.mode, .assisted, "old sessions predate manual mode")
        XCTAssertEqual(dispute.ownPoints[.a], [])
    }

    func testAManualSessionRoundTrips() throws {
        var original = Dispute(title: "Whether to move", mode: .manual)
        original.setPoints(["One.", "Two."], for: .a)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Dispute.self, from: data)

        XCTAssertEqual(decoded.mode, .manual)
        XCTAssertEqual(decoded.ownPoints[.a], ["One.", "Two."])
    }
}

/// Giving up on the model part of the way through.
///
/// The failure this exists for stopped being exotic when the free quota stopped
/// being one person's: it is shared between everybody using the app, so "wait
/// and try again" can mean waiting until tomorrow while two people stand there
/// mid-argument. Before this, that screen offered a retry against something that
/// was not going to work and nothing else.
final class CarryingOnByHandTests: XCTestCase {
    private func assisted() -> Dispute {
        var dispute = Dispute(
            title: "Whether to move",
            mode: .assisted,
            names: PartyPair(a: "Alex", b: "Sam")
        )
        dispute.positions = PartyPair(
            a: "The commute is eating every evening. We would get an hour a day back. "
                + "Rent is cheaper the further out you go.",
            b: "The children would change schools mid-year. My job is here and it is "
                + "the one I actually like. Moving costs more than a year of commuting."
        )
        return dispute
    }

    func testItSwitchesTheSessionToManualAndBuildsTheListFromWhatTheyWrote() {
        var dispute = assisted()
        XCTAssertTrue(dispute.claims.isEmpty)

        dispute.continueByHand()

        XCTAssertEqual(dispute.mode, .manual)
        XCTAssertFalse(dispute.claims.isEmpty, "there is nothing to tick")
        // Their own sentences, not their own points: an assisted session never
        // asked them for points, because that was the model's job.
        XCTAssertTrue(dispute.claims.contains { $0.origin == .a })
        XCTAssertTrue(dispute.claims.contains { $0.origin == .b })
    }

    /// The button is on a failure screen, and a failure screen can be arrived at
    /// twice. The second press must not throw away a list they have started
    /// answering.
    func testItLeavesAListThatAlreadyExistsAlone() {
        var dispute = assisted()
        let existing = [
            Claim(text: "The commute is the main cost here.", origin: .a),
            Claim(text: "Changing schools mid-year sets a child back.", origin: .b),
        ]
        dispute.claims = existing

        dispute.continueByHand()

        XCTAssertEqual(dispute.claims.map(\.text), existing.map(\.text))
    }

    /// It is written down as one-way, and the type is what has to enforce that:
    /// `mode` is `private(set)`, so this is the only thing that can change it and
    /// there is no counterpart going back the other way.
    func testASessionThatHasGoneByHandStaysThatWay() throws {
        var dispute = assisted()
        dispute.continueByHand()

        let decoded = try JSONDecoder().decode(
            Dispute.self,
            from: try JSONEncoder().encode(dispute)
        )
        XCTAssertEqual(decoded.mode, .manual, "reopening the session put the model back")
    }
}
