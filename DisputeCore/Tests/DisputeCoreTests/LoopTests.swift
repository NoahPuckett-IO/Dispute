import XCTest
@testable import DisputeCore

/// The two screens that could not be escaped.
///
/// Both were the same bug wearing different clothes: a screen offering "go back
/// and change what you wrote", where going back re-ran the thing that produced
/// the screen. The user's words for it were that it "keeps sending you back to
/// rewrite", which is exactly what it did — indefinitely, with the only ways out
/// being to force-quit or to notice that the smaller, quieter button was the way
/// forward.
final class LoopTests: XCTestCase {

    // MARK: - The assumptions loop

    /// The state that breaks the cycle has to survive the thing that clears
    /// everything else. `returnToPositions` is called by the button on the
    /// assumptions screen, and it wipes claims, flags, rethinks, the crux and the
    /// recap — all correctly, because all of them were derived from text that is
    /// about to change. The record that the screen has already been shown is not
    /// derived from anything, and clearing it is what made the loop.
    func testGoingBackDoesNotForgetThatAssumptionsWereShown() {
        var dispute = Dispute(title: "T")
        dispute.hasShownAssumptions = true
        dispute.assumptionFlags = [
            AssumptionFlag(party: .a, quote: "q", assumption: "This takes something as given.")
        ]

        dispute.returnToPositions()

        XCTAssertTrue(dispute.hasShownAssumptions, "the loop is back")
        XCTAssertTrue(dispute.assumptionFlags.isEmpty, "the flags were about text that just changed")
    }

    /// And it has to survive a relaunch, or backgrounding the app on that screen
    /// and coming back reopens the cycle.
    func testTheRecordSurvivesBeingSavedAndLoaded() throws {
        var dispute = Dispute(title: "Whether to move")
        dispute.hasShownAssumptions = true
        dispute.failedClaimAttempts = 1

        let data = try JSONEncoder().encode(dispute)
        let decoded = try JSONDecoder().decode(Dispute.self, from: data)

        XCTAssertTrue(decoded.hasShownAssumptions)
        XCTAssertEqual(decoded.failedClaimAttempts, 1)
    }

    /// A session saved by the version with the loop in it has no such field. It
    /// is assumed to have been shown, because the two ways of being wrong are not
    /// symmetric: guessing "shown" costs somebody one look at their assumptions,
    /// and guessing "not shown" drops them straight back into the loop the moment
    /// they reopen the app.
    func testAnOlderSessionWithFlagsIsTreatedAsHavingSeenThem() throws {
        let saved = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Whether to move",
          "createdAt": 0,
          "stage": "positions",
          "names": {"a": "Alex", "b": "Sam"},
          "positions": {"a": "One.", "b": "Two."},
          "claims": [],
          "assumptionFlags": [
            {"id": "\(UUID().uuidString)", "party": "a", "quote": "q",
             "assumption": "This takes something as given.", "isAcknowledged": false}
          ]
        }
        """

        let dispute = try JSONDecoder().decode(Dispute.self, from: Data(saved.utf8))

        XCTAssertTrue(dispute.hasShownAssumptions)
    }

    /// An older session that never got as far as the assumptions screen should
    /// still be shown it once.
    func testAnOlderSessionWithNoFlagsHasNotSeenThem() throws {
        let saved = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Whether to move",
          "createdAt": 0,
          "stage": "setup",
          "names": {"a": "Alex", "b": "Sam"},
          "positions": {"a": "", "b": ""},
          "claims": [],
          "assumptionFlags": []
        }
        """

        let dispute = try JSONDecoder().decode(Dispute.self, from: Data(saved.utf8))

        XCTAssertFalse(dispute.hasShownAssumptions)
    }

    // MARK: - The "write a bit more" loop

    /// The other cycle: the checklist cannot be built, the app asks for more
    /// words, they add some, and it cannot be built again. The escape is that the
    /// second failure stops asking and builds the list out of their own
    /// sentences — duller than drawn-out claims, and infinitely better than a
    /// screen with no way past.
    func testTheCountOfFailedAttemptsSurvivesGoingBack() {
        var dispute = Dispute(title: "T")
        dispute.failedClaimAttempts = 2

        dispute.returnToPositions()

        XCTAssertEqual(dispute.failedClaimAttempts, 2, "the count is the thing that ends the loop")
    }

    func testAChecklistCanAlwaysBeBuiltFromTwoRealPositions() {
        var dispute = Dispute(
            title: "Remote work",
            positions: PartyPair(
                a: "Most knowledge work goes fine from home. People are happier with the flexibility. "
                    + "The commute was dead time anyway.",
                b: "Being in the office is where mentoring happens. Culture erodes without contact. "
                    + "Juniors learn by overhearing people."
            )
        )

        dispute.buildClaimsFromPositions()

        XCTAssertGreaterThanOrEqual(dispute.claims.count, Claim.minimumUsableClaims)
        XCTAssertTrue(dispute.claims.contains { $0.origin == .a })
        XCTAssertTrue(dispute.claims.contains { $0.origin == .b })
    }

    /// Three each at most, so a list built this way is the same length as one the
    /// model wrote and nothing downstream can tell them apart.
    func testTheFallbackListIsTheSameLengthAsARealOne() {
        var dispute = Dispute(
            positions: PartyPair(
                a: "One thing is true here. Two things are true here. Three things are true here. "
                    + "Four things are true here. Five things are true here.",
                b: "Something else entirely is the case. Another thing entirely is the case. "
                    + "A third thing entirely is the case. A fourth thing entirely is the case."
            )
        )

        dispute.buildClaimsFromPositions()

        XCTAssertLessThanOrEqual(dispute.claims.count, 6)
    }

    /// Fragments are not things the other person can meaningfully tick.
    func testTheFallbackDropsScrapsThatCannotBeAnswered() {
        var dispute = Dispute(
            positions: PartyPair(
                a: "Yes. No. Absolutely. The commute is eating my evenings and I want it back.",
                b: "Nope. We genuinely cannot afford the move at this point in the year."
            )
        )

        dispute.buildClaimsFromPositions()

        for claim in dispute.claims {
            XCTAssertGreaterThanOrEqual(
                claim.text.split(whereSeparator: \.isWhitespace).count, 4,
                "a scrap reached the checklist: \(claim.text)"
            )
        }
    }

    /// It must not overwrite a list that was built properly.
    func testTheFallbackNeverReplacesAListThatAlreadyExists() {
        var dispute = Dispute(
            positions: PartyPair(a: "One sentence that is long enough.", b: "Another that is long enough.")
        )
        dispute.claims = [Claim(text: "A real generated claim.", origin: .a)]

        dispute.buildClaimsFromPositions()

        XCTAssertEqual(dispute.claims.count, 1)
        XCTAssertEqual(dispute.claims.first?.text, "A real generated claim.")
    }
}
