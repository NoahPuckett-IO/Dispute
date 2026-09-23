import XCTest
@testable import DisputeCore

/// A crux is only worth naming if both of them would move on it, and only worth
/// showing if there is something to go and do.
///
/// The app used to stop at the question. Two people who walked in stuck walked
/// out stuck, holding a better description of being stuck — which is a diagnosis,
/// not a referee. These are the two properties that make the difference.
final class DoubleCruxTests: XCTestCase {

    private func crux(a: String, b: String, test: String = "") -> Crux {
        Crux(
            question: "Does the raise actually cover what the move costs?",
            positions: PartyPair(a: a, b: b),
            test: test
        )
    }

    // MARK: - Both of them, or it isn't a crux

    func testACruxWithTwoDifferentStancesIsShared() {
        XCTAssertTrue(crux(a: "Yes, with room to spare", b: "No, not once childcare is counted").isShared)
    }

    /// The failure this catches: a model that could not find a real split writes
    /// the same sentence into both slots, and the screen then presents an
    /// invented disagreement as the thing they came for.
    func testTheSameStanceOnBothSidesIsNotShared() {
        XCTAssertFalse(crux(a: "It probably does", b: "It probably does").isShared)
        XCTAssertFalse(crux(a: "It probably does", b: "  it Probably Does  ").isShared)
    }

    /// One side left blank is one person's objection, not a double crux.
    func testAMissingStanceIsNotShared() {
        XCTAssertFalse(crux(a: "Yes", b: "").isShared)
        XCTAssertFalse(crux(a: "", b: "No").isShared)
    }

    // MARK: - Something to actually do

    func testAConcreteTestCounts() {
        XCTAssertTrue(
            crux(
                a: "Yes", b: "No",
                test: "Get three nursery quotes near the new place and compare the total against the raise."
            ).hasTest
        )
    }

    /// The two sentences a model writes when it has nothing, and the reason
    /// `hasTest` exists rather than a plain emptiness check. Both are grammatical,
    /// both are the right length, and both are what these two people have already
    /// been failing to do — which is why they opened the app.
    func testTheNonAnswersAreRejected() {
        for excuse in [
            "The two of you should communicate more about this going forward.",
            "Do more research into the costs before making any final decision.",
            "You should discuss it further when you both have more time.",
            "Gather more information about the situation before deciding.",
        ] {
            XCTAssertFalse(
                crux(a: "Yes", b: "No", test: excuse).hasTest,
                "a non-answer got through: \(excuse)"
            )
        }
    }

    func testAnEmptyOrStubbyTestIsRejected() {
        XCTAssertFalse(crux(a: "Yes", b: "No", test: "").hasTest)
        XCTAssertFalse(crux(a: "Yes", b: "No", test: "Check it.").hasTest)
    }

    // MARK: - The manual draft

    /// Manual mode has no model to write a test, and a blank box on the hardest
    /// field of the hardest screen gets left blank. Both of them have already
    /// answered "what would change my mind", separately and blind, which is the
    /// raw material a test is made of.
    func testTheManualDraftBuildsATestFromBothConditions() {
        let claim = Claim(text: "The raise would cover the move.", origin: .a,
                          agreement: PartyPair(a: true, b: false))
        let draft = Crux.draft(
            from: claim,
            rethinks: PartyPair(
                a: Rethink(claimID: claim.id, bestCase: "b",
                           changeCondition: "If the nursery quotes came back over £1,200 a month"),
                b: Rethink(claimID: claim.id, bestCase: "b",
                           changeCondition: "If a year of costs still came out ahead")
            )
        )

        XCTAssertTrue(draft.test.contains("nursery quotes"))
        XCTAssertTrue(draft.test.contains("came out ahead"))
        XCTAssertTrue(draft.hasTest)
    }

    /// One condition alone is not a double crux, and offering it as one would
    /// teach the wrong thing about what they are looking for.
    func testTheManualDraftLeavesTheTestBlankWhenOnlyOnePersonAnswered() {
        let claim = Claim(text: "The raise would cover the move.", origin: .a)
        let draft = Crux.draft(
            from: claim,
            rethinks: PartyPair(
                a: Rethink(claimID: claim.id, bestCase: "b", changeCondition: "If the quotes came back high"),
                b: nil
            )
        )

        XCTAssertTrue(draft.test.isEmpty)
        XCTAssertFalse(draft.hasTest)
    }

    // MARK: - Storage

    /// A crux saved before `test` existed still loads. `DisputeStore` reads a
    /// decode failure as "no saved session", so getting this wrong costs somebody
    /// the argument they were in the middle of.
    func testACruxSavedWithoutATestStillLoads() throws {
        let saved = """
        {"id": "\(UUID().uuidString)", "question": "Does it cover the costs?",
         "positions": {"a": "Yes", "b": "No"}, "needsConversation": false}
        """

        let crux = try JSONDecoder().decode(Crux.self, from: Data(saved.utf8))

        XCTAssertEqual(crux.question, "Does it cover the costs?")
        XCTAssertEqual(crux.test, "")
        XCTAssertTrue(crux.isUsable)
        XCTAssertFalse(crux.hasTest)
    }

    func testACruxSurvivesARoundTrip() throws {
        let original = crux(a: "Yes", b: "No", test: "Compare a written year of costs against the raise.")
        let data = try JSONEncoder().encode(original)

        XCTAssertEqual(try JSONDecoder().decode(Crux.self, from: data), original)
    }

    // MARK: - The write-up

    /// The test is the only sentence in the write-up that says what happens now,
    /// so it has to reach the last screen and the shared transcript.
    func testTheTestReachesTheWriteUpAndTheTranscript() {
        var dispute = Dispute(title: "Whether to move", names: PartyPair(a: "Alex", b: "Sam"))
        dispute.claims = [
            Claim(text: "The raise covers it.", origin: .a, agreement: PartyPair(a: true, b: false))
        ]
        dispute.crux = crux(
            a: "Yes", b: "No",
            test: "Write down a year of costs and compare the total against the raise."
        )

        XCTAssertTrue(ArgumentRecap.compose(from: dispute).contains("Write down a year of costs"))
        let transcript = ArgumentRecap.transcript(of: dispute)
        XCTAssertTrue(transcript.contains("HOW TO SETTLE IT"))
        XCTAssertTrue(transcript.contains("Write down a year of costs"))
    }

    /// And a non-answer must not, or the last screen tells two people who have
    /// just worked through this that they should talk more.
    func testANonAnswerNeverReachesTheWriteUp() {
        var dispute = Dispute(title: "Whether to move", names: PartyPair(a: "Alex", b: "Sam"))
        dispute.crux = crux(a: "Yes", b: "No", test: "You should communicate more about this.")

        XCTAssertFalse(ArgumentRecap.compose(from: dispute).contains("communicate more"))
        XCTAssertFalse(ArgumentRecap.transcript(of: dispute).contains("HOW TO SETTLE IT"))
    }
}

/// The prompt that asks for both of those.
final class DoubleCruxPromptTests: XCTestCase {
    private var text: String {
        DisputePrompts.findCrux(
            disputeTitle: "Whether to take the job",
            positionA: "The money is life-changing.",
            positionB: "We would be moving the kids mid-year.",
            agreed: "- Something",
            contested: "- Something else",
            secondLooks: ""
        )
    }

    /// The definition that makes it a double crux rather than a disagreement.
    func testTheModelIsToldItMustWorkOnBothOfThem() {
        XCTAssertTrue(text.contains("works on BOTH of them"))
        XCTAssertTrue(text.contains("Test yours twice, once per person"))
    }

    /// A question only one of them is waiting on is that person's objection, and
    /// answering it leaves the argument where it was.
    func testTheModelIsWarnedOffOnePersonsObjection() {
        XCTAssertTrue(text.contains("not the crux"))
    }

    func testATestIsAskedForAndTheNonAnswersAreRuledOut() {
        XCTAssertTrue(text.contains("\"test\""))
        XCTAssertTrue(text.contains("Never \"communicate more\""))
        XCTAssertTrue(text.contains("why they opened this app"))
    }

    /// The two stances have to differ, or the card presents an invented split.
    func testTheStancesAreRequiredToDiffer() {
        XCTAssertTrue(text.contains("must differ from each other"))
    }

    /// Names never reach a model anywhere in this app.
    func testNoRealNamesAreSent() {
        XCTAssertFalse(text.contains("Alex"))
        XCTAssertFalse(text.contains("Sam"))
    }
}
