import XCTest
@testable import DisputeCore

final class DisputeStageGatingTests: XCTestCase {
    func testSetupRequiresATitle() {
        var dispute = Dispute()

        XCTAssertEqual(dispute.stage, .setup)
        XCTAssertFalse(dispute.canAdvance)
        XCTAssertEqual(dispute.blockerForAdvancing, "the argument needs a name")
    }

    /// Both names are required before anything starts. Testers handed
    /// "Person A" and "Person B" assumed the app had picked a side for them.
    func testSetupRequiresBothNames() {
        var dispute = Dispute(title: "Nuclear power")

        XCTAssertEqual(dispute.blockerForAdvancing, "both of you need to put your name in")

        dispute.names[.a] = "Alex"
        XCTAssertFalse(dispute.canAdvance, "one name is not enough")

        dispute.names[.b] = "Sam"
        XCTAssertTrue(dispute.canAdvance)
    }

    func testBlankNamesDoNotCount() {
        var dispute = Dispute(title: "Nuclear power", names: PartyPair(a: "Alex", b: "   "))

        XCTAssertFalse(dispute.canAdvance)
    }

    /// Nothing ever renders blank, even before names are entered.
    func testNamesFallBackToNeutralLabels() {
        var dispute = Dispute(title: "T")
        XCTAssertEqual(dispute.name(for: .a), "First person")
        XCTAssertEqual(dispute.name(for: .b), "Second person")

        dispute.names = PartyPair(a: "  Alex  ", b: "Sam")
        XCTAssertEqual(dispute.name(for: .a), "Alex", "names are trimmed")
        XCTAssertEqual(dispute.name(for: .b), "Sam")
    }

    func testPositionsRequiresBothSides() throws {
        var dispute = Dispute(title: "Nuclear power", names: PartyPair(a: "Alex", b: "Sam"))
        try dispute.advance()

        dispute.positions[.a] = "We need nuclear power, because nothing else runs whatever the weather does."
        XCTAssertFalse(dispute.canAdvance)

        dispute.positions[.b] = "It is too slow to build and too costly, and the waste goes nowhere."
        XCTAssertTrue(dispute.canAdvance)
    }

    /// A position with nothing in it to pull apart does not reach the model.
    ///
    /// One real session had a side write "I like the smores frappe" and stop.
    /// There are not three claims in five words, so the model handed the
    /// sentence straight back and invented the rest, and both people spent the
    /// session ticking their own words. See `Dispute.minimumPositionWords`.
    func testAssistedModeNeedsSomethingToWorkWith() throws {
        var dispute = Dispute(
            title: "Is Starbucks good",
            mode: .assisted,
            names: PartyPair(a: "Henry", b: "Noah")
        )
        try dispute.advance()

        dispute.positions = PartyPair(
            a: "I like the smores frappe",
            b: "Their stuff is corporate slop, the queue is full of people who can afford it, and they turned me down for a job."
        )
        XCTAssertFalse(dispute.canAdvance, "five words is not a position")
        XCTAssertEqual(
            dispute.blockerForAdvancing,
            "say a bit more about why, so there's something to pull apart"
        )

        dispute.positions[.a] = "I like the smores frappe, and the coffee is better than anywhere else on that street."
        XCTAssertTrue(dispute.canAdvance)
    }

    func testChecklistRequiresEveryClaimAnsweredByBoth() throws {
        var dispute = try makeDispute(at: .checklist)
        dispute.claims = [
            Claim(text: "One", origin: .a),
            Claim(text: "Two", origin: .b),
        ]

        XCTAssertFalse(dispute.canAdvance)

        for claim in dispute.claims {
            dispute.setAgreement(true, for: .a, claimID: claim.id)
        }
        XCTAssertFalse(dispute.canAdvance, "one person finishing is not enough")

        for claim in dispute.claims {
            dispute.setAgreement(false, for: .b, claimID: claim.id)
        }
        XCTAssertTrue(dispute.canAdvance)
    }

    func testAnEmptyChecklistBlocksWithItsOwnReason() throws {
        let dispute = try makeDispute(at: .checklist)

        XCTAssertEqual(dispute.blockerForAdvancing, "no points have been drawn out yet")
    }

    func testCruxStageRequiresACrux() throws {
        var dispute = try makeDispute(at: .crux)

        XCTAssertFalse(dispute.canAdvance)

        dispute.crux = Crux(
            question: "Does cost outweigh emissions?",
            positions: PartyPair(a: "No", b: "Yes")
        )
        XCTAssertTrue(dispute.canAdvance)
    }

    func testSummaryIsTheEnd() throws {
        var dispute = try makeDispute(at: .summary)

        XCTAssertEqual(dispute.stage, .summary)
        XCTAssertThrowsError(try dispute.advance()) { error in
            XCTAssertEqual(error as? DisputeError, .alreadyAtFinalStage)
        }
    }
}

final class DisputeClaimTests: XCTestCase {
    private func dispute(with answers: [(Bool, Bool)]) -> Dispute {
        var dispute = Dispute(title: "T")
        dispute.claims = answers.enumerated().map { index, answer in
            Claim(
                text: "Claim \(index)",
                origin: index.isMultiple(of: 2) ? .a : .b,
                agreement: PartyPair(a: answer.0, b: answer.1)
            )
        }
        return dispute
    }

    func testContestedAndSharedArePartitioned() {
        let dispute = dispute(with: [(true, true), (true, false), (false, false), (false, true)])

        XCTAssertEqual(dispute.contestedClaims.count, 2)
        XCTAssertEqual(dispute.sharedClaims.count, 2)
    }

    func testProgressIsTrackedPerPerson() {
        var dispute = Dispute(title: "T")
        dispute.claims = [Claim(text: "One", origin: .a), Claim(text: "Two", origin: .b)]

        XCTAssertEqual(dispute.claimsAwaiting(.a).count, 2)
        XCTAssertFalse(dispute.hasFinishedChecklist(.a))

        dispute.setAgreement(true, for: .a, claimID: dispute.claims[0].id)
        XCTAssertEqual(dispute.claimsAwaiting(.a).count, 1)

        dispute.setAgreement(false, for: .a, claimID: dispute.claims[1].id)
        XCTAssertTrue(dispute.hasFinishedChecklist(.a))
        XCTAssertFalse(dispute.hasFinishedChecklist(.b))
    }

    func testAnsweringAnUnknownClaimReportsFailure() {
        var dispute = Dispute(title: "T")

        XCTAssertFalse(dispute.setAgreement(true, for: .a, claimID: UUID()))
    }
}

final class DisputeCodableTests: XCTestCase {
    func testAFullSessionSurvivesARoundTrip() throws {
        var dispute = try makeDispute(at: .crux)
        dispute.crux = Crux(
            question: "Does cost outweigh emissions?",
            positions: PartyPair(a: "No", b: "Yes"),
            needsConversation: true
        )

        let data = try JSONEncoder().encode(dispute)
        let restored = try JSONDecoder().decode(Dispute.self, from: data)

        XCTAssertEqual(restored, dispute)
        XCTAssertEqual(restored.stage, .crux)
        XCTAssertEqual(restored.crux?.needsConversation, true)
    }
}

// MARK: - Helpers

/// Drives a dispute forward to `stage`, satisfying each gate along the way.
private func makeDispute(at stage: SessionStage) throws -> Dispute {
    var dispute = Dispute(
        title: "Nuclear power for climate change",
        names: PartyPair(a: "Alex", b: "Sam")
    )
    if stage == .setup { return dispute }

    try dispute.advance() // positions
    if stage == .positions { return dispute }

    dispute.positions = PartyPair(
        a: "We need nuclear power because it is the only low carbon source that runs whatever the weather does.",
        b: "It is too slow to build and too costly, and the waste has nowhere settled to go."
    )
    try dispute.advance() // checklist
    if stage == .checklist { return dispute }

    dispute.claims = [
        Claim(text: "Emissions matter most", origin: .a, agreement: PartyPair(a: true, b: true)),
        Claim(text: "Cost should decide", origin: .b, agreement: PartyPair(a: false, b: true)),
    ]
    try dispute.advance() // crux
    if stage == .crux { return dispute }

    dispute.crux = Crux(question: "Placeholder?", positions: PartyPair(a: "No", b: "Yes"))
    try dispute.advance() // summary
    return dispute
}

final class DisputeRecoveryTests: XCTestCase {
    /// Before this existed, a safety refusal meant throwing the whole session
    /// away — a tester hit one and had to start from scratch.
    func testReturningToPositionsClearsDerivedWork() throws {
        var dispute = try makeDisputeForRecovery()
        XCTAssertEqual(dispute.stage, .checklist)
        XCTAssertFalse(dispute.claims.isEmpty)

        dispute.returnToPositions()

        XCTAssertEqual(dispute.stage, .positions)
        XCTAssertTrue(dispute.claims.isEmpty, "claims came from text that's about to change")
        XCTAssertNil(dispute.crux)
        XCTAssertTrue(dispute.assumptionFlags.isEmpty)
    }

    /// What people wrote is kept — the point is to edit it, not lose it.
    ///
    /// Both of them, which is what `SayMoreView` promises in as many words: it
    /// says "Add to what you said" and "nothing is lost", and it sends both of
    /// them back through this. One position surviving would make it a lie for
    /// whichever of them went second.
    func testReturningToPositionsKeepsWhatTheyBothWrote() throws {
        var dispute = try makeDisputeForRecovery()
        let before = dispute.positions

        dispute.returnToPositions()

        XCTAssertEqual(dispute.positions[.a], before[.a])
        XCTAssertEqual(dispute.positions[.b], before[.b])
        XCTAssertFalse(dispute.positions[.b].isEmpty, "the fixture stopped carrying a second position")
        XCTAssertEqual(dispute.name(for: .b), "Sam")
        XCTAssertEqual(dispute.title, "Nuclear power for climate change")
    }

    /// And the second look goes, because it points at a claim by id and every
    /// claim was just thrown away. Left behind, `owesRethink` would be satisfied
    /// by a `Rethink` whose `claimID` no longer matches anything on the list.
    func testReturningToPositionsClearsTheSecondLooks() throws {
        var dispute = try makeDisputeForRecovery()
        dispute.setRethink(
            Rethink(claimID: dispute.claims[0].id, bestCase: "Best.", changeCondition: "If x."),
            for: .a
        )
        XCTAssertNotNil(dispute.rethinks[.a])

        dispute.returnToPositions()

        XCTAssertNil(dispute.rethinks[.a])
        XCTAssertNil(dispute.rethinks[.b])
    }

    func testFlagsAreAcknowledgedTogether() {
        var dispute = Dispute(title: "T")
        dispute.assumptionFlags = [
            AssumptionFlag(party: .a, quote: "one", assumption: "x"),
            AssumptionFlag(party: .b, quote: "two", assumption: "y"),
        ]

        XCTAssertEqual(dispute.unacknowledgedFlags.count, 2)
        dispute.acknowledgeAllFlags()
        XCTAssertTrue(dispute.unacknowledgedFlags.isEmpty)
    }
}

private func makeDisputeForRecovery() throws -> Dispute {
    var dispute = Dispute(
        title: "Nuclear power for climate change",
        names: PartyPair(a: "Alex", b: "Sam")
    )
    try dispute.advance()
    dispute.positions = PartyPair(
        a: "We need nuclear power because it is the only low carbon source that runs whatever the weather does.",
        b: "It is too slow to build and too costly, and the waste has nowhere settled to go."
    )
    try dispute.advance()
    dispute.claims = [Claim(text: "A point", origin: .a)]
    dispute.assumptionFlags = [AssumptionFlag(party: .a, quote: "q", assumption: "i")]
    return dispute
}

/// The condition the entry screen holds its Done button on, after a checklist
/// that could not be built from what they wrote.
final class AddingToAPositionTests: XCTestCase {
    private static let failed = "Most knowledge work goes fine from home and people are happier."

    func testAddingSomethingCounts() {
        XCTAssertTrue(
            "\(Self.failed) The commute is two hours a day."
                .isDifferentWriting(from: Self.failed)
        )
        XCTAssertTrue("Something else entirely.".isDifferentWriting(from: Self.failed))
        XCTAssertTrue("".isDifferentWriting(from: Self.failed), "clearing it is a change too")
    }

    /// Pressing Done on the text that just failed is the retry button this whole
    /// change removed. It has to stay held.
    func testTheSameTextDoesNotCount() {
        XCTAssertFalse(Self.failed.isDifferentWriting(from: Self.failed))
    }

    /// Space is not an edit. Somebody who taps into the box, nudges the cursor and
    /// presses Done has changed nothing, and the app must not spend half a minute
    /// proving it.
    func testWhitespaceAloneDoesNotCount() {
        XCTAssertFalse("  \(Self.failed)\n ".isDifferentWriting(from: Self.failed))
        XCTAssertFalse(Self.failed.isDifferentWriting(from: "\n\(Self.failed)  "))
    }

    /// A change inside the text counts, not only one on the end. The screen says
    /// "add", but rewording it entirely is a better answer and must not be refused.
    func testAnEditInTheMiddleCounts() {
        XCTAssertTrue(
            "Most knowledge work goes fine from home and people are much happier."
                .isDifferentWriting(from: Self.failed)
        )
    }
}
