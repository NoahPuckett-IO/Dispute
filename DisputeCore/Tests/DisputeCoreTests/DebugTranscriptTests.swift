#if DEBUG
import XCTest
@testable import DisputeCore

/// The debug transcript is read by someone who was not holding the phone, so
/// what it leaves out is the whole cost of having it. These check the parts that
/// a prompting fault hides in: whose points ended up on the list, how each of
/// them answered, the prompt as sent, and the answer before anything parsed it.
final class DebugTranscriptTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PromptLog.shared.clear()
        PromptLog.shared.isEnabled = true
    }

    override func tearDown() {
        PromptLog.shared.clear()
        PromptLog.shared.isEnabled = false
        super.tearDown()
    }

    func testItCarriesTheSessionAndTheModelSideOfIt() {
        PromptLog.shared.record(
            step: "crux",
            engine: "Apple on-device",
            system: "You are the neutral referee",
            prompt: "The argument: whether to take the job",
            reply: #"{"question":"Does the raise cover the move?"}"#,
            startedAt: Date()
        )

        let text = DebugTranscript.text(for: finished(), engine: "On this device", device: "iPhone")

        // The session, as the two of them left it.
        XCTAssertTrue(text.contains("Whether to take the job"))
        XCTAssertTrue(text.contains("The money is life-changing"))
        XCTAssertTrue(text.contains("[SPLIT]"))
        XCTAssertTrue(text.contains("[from A]"))
        XCTAssertTrue(text.contains("What would change their mind: If the new school couldn't take them"))

        // The model's side of it.
        XCTAssertTrue(text.contains("You are the neutral referee"))
        XCTAssertTrue(text.contains("The argument: whether to take the job"))
        XCTAssertTrue(text.contains(#"{"question":"Does the raise cover the move?"}"#))
    }

    /// A prompt that failed is the most interesting one in the file, so it must
    /// not be the one that gets dropped.
    func testAFailedCallIsKeptWithItsPrompt() {
        PromptLog.shared.record(
            step: "claims (person A)",
            engine: "Downloaded model",
            system: "You are the neutral referee",
            prompt: "Write three claims",
            failure: "truncated",
            startedAt: Date()
        )

        let text = DebugTranscript.text(for: finished(), engine: "On this device", device: "iPhone")

        XCTAssertTrue(text.contains("claims (person A)"))
        XCTAssertTrue(text.contains("Write three claims"))
        XCTAssertTrue(text.contains("FAILED: truncated"))
    }

    /// What the app did with an answer belongs next to the answer. A crux the
    /// app threw away looks like a model that found nothing without this.
    func testNotesSitInOrderWithTheCalls() {
        PromptLog.shared.record(
            step: "crux",
            engine: "Apple on-device",
            system: "system",
            prompt: "prompt",
            reply: "answer",
            startedAt: Date()
        )
        PromptLog.shared.note("The app discarded that crux as unusable")

        let text = DebugTranscript.text(for: finished(), engine: "On this device", device: "iPhone")
        let call = try! XCTUnwrap(text.range(of: "CALL 1: crux"))
        let note = try! XCTUnwrap(text.range(of: "NOTE: The app discarded"))
        XCTAssertLessThan(call.lowerBound, note.lowerBound)
    }

    func testASessionThatNeverCalledAModelSaysSoRatherThanLookingEmpty() {
        let text = DebugTranscript.text(for: finished(), engine: "Nothing", device: "iPhone")
        XCTAssertTrue(text.contains("Nothing was recorded"))
    }

    // MARK: - Fixture

    private func finished() -> Dispute {
        let claims = [
            Claim(text: "The raise would cover what the move costs.", origin: .a,
                  agreement: PartyPair(a: true, b: false)),
            Claim(text: "A comparable offer is unlikely to come along soon.", origin: .a,
                  agreement: PartyPair(a: true, b: true)),
            Claim(text: "Changing schools mid-year would set the kids back.", origin: .b,
                  agreement: PartyPair(a: false, b: true)),
            Claim(text: "Neither of us wants to decide this in a hurry.", origin: .b,
                  agreement: PartyPair(a: true, b: true)),
        ]

        return Dispute(
            title: "Whether to take the job",
            stage: .summary,
            names: PartyPair(a: "Alex", b: "Sam"),
            positions: PartyPair(
                a: "The money is life-changing and offers like this don't come round twice.",
                b: "We'd be moving the kids mid-year for a job neither of us knows will last."
            ),
            claims: claims,
            rethinks: PartyPair(
                a: Rethink(
                    claimID: claims[2].id,
                    bestCase: "Kids do notice a move, and this one lands mid-year.",
                    changeCondition: "If the new school couldn't take them until September"
                ),
                b: nil
            ),
            crux: Crux(
                question: "Does the raise actually cover what the move costs?",
                positions: PartyPair(a: "Yes", b: "No, not once childcare is counted")
            )
        )
    }
}
#endif
