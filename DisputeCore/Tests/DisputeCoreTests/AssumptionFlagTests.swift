import XCTest
@testable import DisputeCore

/// The filter that stands between a small model and the one screen in the app
/// where it says something about a person's own words back to them.
///
/// `isUsable` is the whole of that filter, and everything it catches is something
/// a grammar cannot: a well-formed, correctly-shaped, entirely useless answer.
final class AssumptionFlagTests: XCTestCase {

    private func flag(quote: String, assumption: String) -> AssumptionFlag {
        AssumptionFlag(party: .a, quote: quote, assumption: assumption)
    }

    // MARK: - What gets through

    func testAnOrdinaryAssumptionIsUsable() {
        XCTAssertTrue(
            flag(
                quote: "offers like this don't come round twice",
                assumption: "This treats the current offer as the last one, with no allowance for a similar one later."
            ).isUsable
        )
    }

    // MARK: - What doesn't

    /// The failure this exists for. Asked what a sentence assumes, a small model
    /// will sometimes hand the sentence back — which reads to two people as the
    /// app saying "you assume what you said", and is worse than showing nothing.
    func testTheQuoteHandedBackAsItsOwnAssumptionIsRejected() {
        XCTAssertFalse(
            flag(
                quote: "offers like this don't come round twice",
                assumption: "They assume that offers like this don't come round twice."
            ).isUsable
        )
    }

    /// A fragment is not a thought. Both of these came back well-formed and
    /// grammatical, and neither says anything.
    func testAStubIsRejected() {
        XCTAssertFalse(flag(quote: "the commute", assumption: "Money.").isUsable)
        XCTAssertFalse(flag(quote: "the commute", assumption: "That it matters").isUsable)
    }

    func testAnEmptyAssumptionIsRejected() {
        XCTAssertFalse(flag(quote: "the commute", assumption: "").isUsable)
        XCTAssertFalse(flag(quote: "the commute", assumption: "   ").isUsable)
    }

    /// The echo test only applies to a quote long enough for the overlap to mean
    /// something. A short quote is a phrase like "the money", which a good
    /// assumption will legitimately repeat — "This takes it as given that the
    /// money is the part that matters" is exactly the right answer and contains
    /// the quote verbatim.
    func testAShortQuoteMayAppearInsideItsOwnAssumption() {
        XCTAssertTrue(
            flag(
                quote: "the money",
                assumption: "This takes it as given that the money is the part that decides it."
            ).isUsable
        )
    }

    /// Case and surrounding whitespace are noise from the model, not signal.
    func testTheEchoTestIgnoresCaseAndPadding() {
        XCTAssertFalse(
            flag(
                quote: "  Offers Like This Don't Come Round Twice  ",
                assumption: "The writer assumes offers like this don't come round twice, which is unstated."
            ).isUsable
        )
    }

    // MARK: - Storage

    /// The flags are persisted with the session, so a resumed argument shows the
    /// same cards. A flag that survives a round trip differently is a flag the
    /// app has quietly rewritten.
    func testAFlagSurvivesARoundTrip() throws {
        let original = AssumptionFlag(
            party: .b,
            quote: "moving the kids mid-year",
            assumption: "This takes as given that the move could not wait until the summer.",
            isAcknowledged: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AssumptionFlag.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.id, original.id)
    }

    /// A session saved by a version that fact checked carries `factFlags`, whose
    /// contents were judgements about whether something was true. There is no
    /// honest translation of those into assumptions, so they are dropped — but
    /// the argument around them has to survive, because `DisputeStore` treats a
    /// decode failure as "no saved session" and would throw the whole thing away.
    func testASessionSavedWithOldFactFlagsStillLoads() throws {
        let saved = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Whether to move",
          "createdAt": 0,
          "stage": "positions",
          "names": {"a": "Alex", "b": "Sam"},
          "positions": {"a": "The commute is eating my evenings.", "b": "We cannot afford it."},
          "claims": [],
          "factFlags": [
            {"id": "\(UUID().uuidString)", "party": "a", "quote": "it doubled",
             "issue": "Published figures show a 12% rise.", "isAcknowledged": false}
          ]
        }
        """

        let dispute = try JSONDecoder().decode(Dispute.self, from: Data(saved.utf8))

        XCTAssertEqual(dispute.title, "Whether to move")
        XCTAssertEqual(dispute.name(for: .a), "Alex")
        XCTAssertTrue(dispute.assumptionFlags.isEmpty)
    }

    // MARK: - Acknowledgement

    func testAcknowledgingClearsWhatIsOutstanding() {
        var dispute = Dispute(
            assumptionFlags: [
                flag(quote: "the money", assumption: "This takes the raise as the deciding factor."),
                flag(quote: "the kids", assumption: "This takes the school year as immovable."),
            ]
        )

        XCTAssertEqual(dispute.unacknowledgedFlags.count, 2)
        dispute.acknowledgeAllFlags()
        XCTAssertTrue(dispute.unacknowledgedFlags.isEmpty)
        XCTAssertEqual(dispute.assumptionFlags.count, 2, "acknowledging is not deleting")
    }
}
