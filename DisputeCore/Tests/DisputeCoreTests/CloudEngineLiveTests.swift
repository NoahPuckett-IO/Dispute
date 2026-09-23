import XCTest
@testable import DisputeCore

/// The hosted engine, against the real Mistral API.
///
/// Skipped unless `MISTRAL_API_KEY` is set, exactly like the on-device tests
/// skipped without `DISPUTE_TEST_MODEL`. Nothing here can run in CI and nothing
/// here should: it spends somebody's free-tier quota and it fails when Mistral
/// has a bad afternoon.
///
///     MISTRAL_API_KEY=… swift test --filter CloudEngineLive
///
/// This is the test that earns its keep on a provider change. Everything else in
/// this package would pass just as happily against an endpoint that no longer
/// exists — the wire format, the model identifier and the shape of a real reply
/// are only answerable by asking the real thing.
///
/// What it is for is the thing unit tests cannot reach. Every other test in this
/// package checks the app's half of the contract — that a prompt says what it
/// should, that a malformed answer is rejected, that a grammar has the right
/// bounds. None of them can tell you whether the model on the other end returns
/// the shape the app asks for, whether the wire format is right, or whether a
/// wrong key surfaces as something a screen can explain. Those are answerable
/// only by asking the real thing.
final class CloudEngineLiveTests: XCTestCase {
    private var engine: CloudEngine!

    override func setUpWithError() throws {
        guard let key = ProcessInfo.processInfo.environment["MISTRAL_API_KEY"],
              !key.trimmed.isEmpty
        else {
            throw XCTSkip("set MISTRAL_API_KEY to run the live Mistral tests")
        }
        engine = CloudEngine(apiKey: key)
    }

    /// Two real positions, of the kind two people actually type.
    private let positionA = """
        We should take the job. The money is life-changing and offers like this \
        don't come round twice, so waiting costs us the whole thing. I've been in \
        the same role for four years and I'm not learning anything any more.
        """
    private let positionB = """
        We'd be moving the kids mid-year for a company neither of us knows will \
        still exist in two years. The raise looks big until you price a house \
        here against a house there, and I'd be giving up the job I actually like.
        """

    // MARK: - Claims

    func testItBreaksTwoPositionsIntoAListBothCouldAnswer() async throws {
        let claims = try await engine.breakDown(
            positionA: positionA,
            positionB: positionB,
            disputeTitle: "Whether to take the job"
        )

        XCTAssertGreaterThanOrEqual(claims.count, Claim.minimumUsableClaims)
        XCTAssertTrue(claims.contains { $0.origin == .a }, "nothing came from the first position")
        XCTAssertTrue(claims.contains { $0.origin == .b }, "nothing came from the second position")

        for claim in claims {
            XCTAssertFalse(claim.text.isEmpty)
            // Both people tick this list without being told whose point is
            // whose, so a claim written in somebody's voice gives it away.
            XCTAssertFalse(
                Claim.isInSomeonesVoice(claim.text),
                "a point in somebody's own voice reached the blind list: \(claim.text)"
            )
            for position in [positionA, positionB] {
                XCTAssertFalse(
                    Claim.isEcho(claim.text, of: position),
                    "a sentence was handed back: \(claim.text)"
                )
            }
        }

        // The list is shuffled, not grouped, or the first half is obviously one
        // person's and the blind tick is not blind.
        let origins = claims.map(\.origin)
        XCTAssertTrue(
            zip(origins, origins.dropFirst()).contains { $0 != $1 },
            "the list is grouped by author"
        )
    }

    // MARK: - The crux

    /// The whole point of the hosted model: a crux that is a real double crux,
    /// with something at the end of it the two of them can go and do.
    func testItFindsADoubleCruxWithATest() async throws {
        var dispute = Dispute(
            title: "Whether to take the job",
            names: PartyPair(a: "Alex", b: "Sam"),
            positions: PartyPair(a: positionA, b: positionB)
        )
        let claims = [
            Claim(text: "The raise would cover what the move costs.", origin: .a,
                  agreement: PartyPair(a: true, b: false)),
            Claim(text: "A comparable offer is unlikely to come along soon.", origin: .a,
                  agreement: PartyPair(a: true, b: false)),
            Claim(text: "Changing schools mid-year would set the children back.", origin: .b,
                  agreement: PartyPair(a: false, b: true)),
            Claim(text: "Neither of us wants to decide this in a hurry.", origin: .b,
                  agreement: PartyPair(a: true, b: true)),
        ]
        dispute.claims = claims
        dispute.setRethink(
            Rethink(claimID: claims[2].id,
                    bestCase: "A mid-year move does land badly for a child who has just settled.",
                    changeCondition: "If the new school could take them in September instead"),
            for: .a
        )
        dispute.setRethink(
            Rethink(claimID: claims[0].id,
                    bestCase: "The salary difference is real money and it compounds.",
                    changeCondition: "If we wrote down a year of costs and it still came out ahead"),
            for: .b
        )

        let crux = try await engine.findCrux(in: dispute)

        let found = try XCTUnwrap(crux, "no crux came back at all")
        XCTAssertTrue(found.isUsable)
        XCTAssertTrue(found.question.hasSuffix("?"), "a crux is a question: \(found.question)")
        XCTAssertTrue(found.isShared, "the same stance on both sides: \(found.positions.a)")
        XCTAssertTrue(found.hasTest, "no usable test came back: \"\(found.test)\"")

        // Names never reach the model, so nothing it wrote can contain one.
        for text in [found.question, found.positions.a, found.positions.b, found.test] {
            XCTAssertFalse(text.contains("Alex"), "a name reached the model: \(text)")
            XCTAssertFalse(text.contains("Sam"), "a name reached the model: \(text)")
        }

        // The app writes the person's name in front of each stance, so a stance
        // that names somebody itself arrives doubled on the last screen.
        for stance in [found.positions.a, found.positions.b] {
            XCTAssertFalse(stance.lowercased().hasPrefix("person "), "attribution survived: \(stance)")
        }

        print("""

        ── LIVE CRUX ─────────────────────────────────────────
        Q:    \(found.question)
        A:    \(found.positions.a)
        B:    \(found.positions.b)
        Test: \(found.test)
        Needs conversation: \(found.needsConversation)
        ──────────────────────────────────────────────────────

        """)
    }

    // MARK: - Assumptions

    /// Both people in one call now, which is the cheap way and the risky one.
    ///
    /// A model holding both paragraphs can quietly start answering each with the
    /// other: naming what A takes for granted *because B contradicted it*. That
    /// is B's rebuttal handed to A as their own reasoning, on the one screen
    /// where the app says something about somebody's own words back to them, and
    /// no unit test can see it because the shape is correct either way. The
    /// closest thing to a mechanical check is where the quote came from — a flag
    /// on A quoting B's paragraph is the failure, visible.
    func testItNamesAnAssumptionWithoutRulingOnItOrCrossingTheTwo() async throws {
        let flags = try await engine.findAssumptions(
            positionA: positionA,
            positionB: positionB,
            disputeTitle: "Whether to take the job"
        )

        for party in Party.allCases {
            XCTAssertLessThanOrEqual(
                flags.filter { $0.party == party }.count, 2,
                "this is one card between two turns"
            )
        }

        for flag in flags {
            XCTAssertTrue(flag.isUsable)
            // The quote has to be their words, or the card points at something
            // that is not on their screen — and after the merge, "theirs" is the
            // whole question.
            let theirs = flag.party == .a ? positionA : positionB
            let theOthers = flag.party == .a ? positionB : positionA
            XCTAssertTrue(
                theirs.localizedCaseInsensitiveContains(flag.quote.trimmed),
                "the quote is not in what they wrote: \(flag.quote)"
            )
            XCTAssertFalse(
                theOthers.localizedCaseInsensitiveContains(flag.quote.trimmed)
                    && !theirs.localizedCaseInsensitiveContains(flag.quote.trimmed),
                "the flag quotes the other person: \(flag.quote)"
            )
            // The line that separates this from the fact check it replaced.
            let text = flag.assumption.lowercased()
            for verdict in ["is wrong", "incorrect", "is false", "not true", "mistaken", "you should"] {
                XCTAssertFalse(text.contains(verdict), "a verdict came back: \(flag.assumption)")
            }
            // Naming the other person, or their disagreement, is the same fault
            // arriving in prose rather than in a quote. Worth reading rather than
            // asserting on: "the other person" is a phrase a clean answer could
            // conceivably use, and a red test nobody trusts gets deleted.
            for crossed in ["the other person", "disagree", "unlike", "whereas"] {
                if text.contains(crossed) {
                    print("── CHECK BY EYE ── \(flag.party): \(flag.assumption)")
                }
            }
            print("── LIVE ASSUMPTION ── \(flag.party) \"\(flag.quote)\" → \(flag.assumption)")
        }
    }

    // MARK: - Failure

    /// A wrong key has to arrive as something the screen can explain, not as a
    /// generic failure. It is the single most likely thing to go wrong on this
    /// path, because it happens the first time anybody sets it up.
    func testARejectedKeySaysSo() async throws {
        let wrong = CloudEngine(apiKey: "AIzaSyDefinitelyNotARealKey000000000000000")

        do {
            _ = try await wrong.findAssumptions(positionA: positionA, positionB: positionB, disputeTitle: "t")
            XCTFail("a bad key was accepted")
        } catch let error as EngineError {
            guard case let .refused(cause, _) = error else {
                return XCTFail("a bad key surfaced as \(error), which no screen explains")
            }
            XCTAssertEqual(cause, .key)
            // Sending them off to reword a position that was never the problem
            // is the wrong advice, and the screen decides from this.
            XCTAssertFalse(error.isFixedByRewriting)
            XCTAssertTrue(error.isFixedByCarryingOnByHand)
        }
    }
}
