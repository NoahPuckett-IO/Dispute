import XCTest
@testable import DisputeCore

private func assertEngineError(
    _ expected: EngineError,
    _ body: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await body()
        XCTFail("expected \(expected), nothing thrown", file: file, line: line)
    } catch let error as EngineError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("expected EngineError, got \(error)", file: file, line: line)
    }
}

final class MockDisputeEngineTests: XCTestCase {
    func testBreakDownProducesClaimsFromBothSides() async throws {
        let claims = try await MockDisputeEngine().breakDown(
            positionA: "We need nuclear.",
            positionB: "It costs too much.",
            disputeTitle: "Nuclear power"
        )

        XCTAssertFalse(claims.isEmpty)
        XCTAssertTrue(claims.contains { $0.origin == .a })
        XCTAssertTrue(claims.contains { $0.origin == .b })
        XCTAssertTrue(claims.allSatisfy { !$0.isAnsweredByBoth }, "claims start unanswered")
    }

    /// Determinism is what makes screenshots and walkthroughs reproducible.
    func testTheMockIsDeterministic() async throws {
        let engine = MockDisputeEngine()
        let first = try await engine.breakDown(positionA: "A", positionB: "B", disputeTitle: "T")
        let second = try await engine.breakDown(positionA: "A", positionB: "B", disputeTitle: "T")

        XCTAssertEqual(first.map(\.text), second.map(\.text))
    }

    func testTheCruxComesFromAContestedClaim() async throws {
        var dispute = Dispute(title: "Nuclear power")
        dispute.claims = [
            Claim(text: "Agreed point", origin: .a, agreement: PartyPair(a: true, b: true)),
            Claim(text: "Split point", origin: .b, agreement: PartyPair(a: true, b: false)),
        ]

        let crux = try await MockDisputeEngine().findCrux(in: dispute)

        XCTAssertEqual(crux?.question, "Is it true that split point?")
    }

    /// The whole change: one question at the end, never a list of them. An
    /// engine that hands back two has nowhere to put the second.
    func testOnlyOneCruxComesBackEvenWithSeveralContestedPoints() async throws {
        var dispute = Dispute(title: "Nuclear power")
        dispute.claims = (1...4).map {
            Claim(text: "Split \($0)", origin: .a, agreement: PartyPair(a: true, b: false))
        }

        let crux = try await MockDisputeEngine().findCrux(in: dispute)

        XCTAssertNotNil(crux)
        XCTAssertEqual(dispute.contestedClaims.count, 4, "several to choose from")
    }

    func testNoContestedClaimsMeansNoCrux() async throws {
        var dispute = Dispute(title: "T")
        dispute.claims = [
            Claim(text: "Agreed", origin: .a, agreement: PartyPair(a: true, b: true))
        ]

        let crux = try await MockDisputeEngine().findCrux(in: dispute)

        XCTAssertNil(crux)
    }

    func testFailureCanBeInjectedToExerciseErrorStates() async {
        let engine = MockDisputeEngine(failure: .timedOut)

        await assertEngineError(.timedOut) {
            _ = try await engine.breakDown(positionA: "a", positionB: "b", disputeTitle: "t")
        }
    }

    /// The last screen is composed, not generated, so it is never blank and never
    /// waits. No engine gets a say in it — there is no hook for one to implement.
    func testTheWriteUpIsComposedRatherThanAskedFor() {
        var dispute = Dispute(title: "Whether to move", names: PartyPair(a: "Alex", b: "Sam"))
        dispute.claims = [
            Claim(text: "Rent is cheaper there.", origin: .a, agreement: PartyPair(a: true, b: true))
        ]

        let written = ArgumentRecap.compose(from: dispute)

        XCTAssertTrue(written.contains("Whether to move"))
        XCTAssertFalse(written.isEmpty)
    }

    /// An engine that declines to flag assumptions says so, and returns nothing
    /// rather than being asked and failing.
    func testAnEngineThatCannotFlagAssumptionsReturnsNothing() async throws {
        struct Plain: DisputeEngine {
            func breakDown(positionA: String, positionB: String, disputeTitle: String) async throws -> [Claim] { [] }
            func findCrux(in dispute: Dispute) async throws -> Crux? { nil }
            var canFlagAssumptions: Bool { false }
        }

        let flags = try await Plain().findAssumptions(
            positionA: "Anything at all, it is never asked.",
            positionB: "Nor is this.",
            disputeTitle: "t"
        )
        XCTAssertTrue(flags.isEmpty)
    }
}

final class EngineErrorTests: XCTestCase {
    func testRetryabilityIsClassifiedCorrectly() {
        XCTAssertTrue(EngineError.timedOut.isRetryable)
        // Sampled models genuinely do come back usable on a second attempt.
        XCTAssertTrue(EngineError.malformedResponse("bad shape").isRetryable)

        XCTAssertFalse(EngineError.refused(cause: .safety, explanation: nil).isRetryable)
        XCTAssertFalse(EngineError.truncated.isRetryable)
        // A rejected key is the one refusal somebody in the room can fix, and
        // `EngineSource` builds a fresh engine per call, so the corrected key is
        // live the moment it is saved. Without a retry the screen said "check it
        // in Settings" over a single button offering to give up on the AI for the
        // rest of the session.
        XCTAssertTrue(EngineError.refused(cause: .key, explanation: nil).isRetryable)
        // And the app's own credential is not: nobody holding the phone typed it,
        // and there is nothing in Settings for them to correct.
        XCTAssertFalse(EngineError.refused(cause: .app, explanation: nil).isRetryable)
        // Mistral having a bad afternoon is worth a second press, and there is
        // nothing else to offer: no key to check, no wording to change.
        XCTAssertTrue(EngineError.serviceUnavailable(reason: "Mistral had a problem").isRetryable)
        // The one that used to be a retry and should never be one again. By the
        // time it is thrown the app has asked the model twice, and measured over
        // the sessions that hit it the same prompt came back unusable five times
        // in six. A third go is twenty seconds spent arriving back here.
        XCTAssertFalse(EngineError.notEnoughToWorkWith.isRetryable)
    }

    /// Not the inverse of retryable, which is the mistake this guards. A refusal
    /// is neither retryable nor unfixable: rewording clears it. A timeout is
    /// retryable and rewording has nothing to do with it.
    func testTheWayOutIsClassifiedSeparatelyFromRetrying() {
        XCTAssertTrue(EngineError.notEnoughToWorkWith.isFixedByRewriting)
        XCTAssertTrue(EngineError.refused(cause: .safety, explanation: nil).isFixedByRewriting)

        // The context window filled. The only part of that anyone can change is
        // how much they wrote, so this is a reword and never a retry.
        XCTAssertTrue(EngineError.truncated.isFixedByRewriting)

        XCTAssertFalse(EngineError.timedOut.isFixedByRewriting)
        XCTAssertFalse(EngineError.malformedResponse("bad shape").isFixedByRewriting)
    }

    /// Every error the *model* can produce has to leave at least one thing for
    /// somebody to do. One that is neither retryable nor fixed by rewriting is a
    /// screen with no buttons on it, which is the dead end this layer exists to
    /// avoid, and writing that invariant down is what caught `truncated` sitting
    /// on the wrong side of it.
    ///
    /// Nothing is excluded any more. There used to be one exclusion, back when a
    /// model that would not load was a thing that could happen and the answer to
    /// it lived in AI settings rather than on this screen. Every failure left is
    /// one the two of them can either wait out, retry, reword, or walk away from
    /// and finish by hand.
    func testEveryFailureLeavesSomethingToDo() {
        for error: EngineError in EngineError.allFailures {
            XCTAssertTrue(
                error.isRetryable || error.isFixedByRewriting || error.isFixedByCarryingOnByHand,
                "\(error) offers nothing to do"
            )
        }
    }

    /// The model that used to run on the phone is gone, and no message may still
    /// send somebody looking for it.
    ///
    /// This is the second time that copy has been wrong. The switch to Gemini
    /// deleted the on-device engine and left three failure messages telling
    /// people to go and use it, which is advice for a Settings screen that no
    /// longer has that switch on it — a dead end dressed as a way out, in the one
    /// layer of this app whose whole job is never to produce one.
    func testNoFailureSendsThemToAModelOnThePhone() {
        for error in EngineError.allFailures {
            let message = error.errorDescription ?? ""
            for phrase in ["on this phone", "on-device", "on device", "the model on"] {
                XCTAssertFalse(
                    message.localizedCaseInsensitiveContains(phrase),
                    "\"\(message)\" points at a model that isn't there any more"
                )
            }
        }
    }

    /// A refused credential must never be dressed up as something the two of them
    /// wrote wrongly. It is the same HTTP status either way and opposite advice.
    func testARefusedCredentialIsNeverATypingProblem() {
        for cause: RefusalCause in [.key, .app] {
            let error = EngineError.refused(cause: cause, explanation: "nope")
            XCTAssertFalse(error.isFixedByRewriting, "\(cause) sends them off to reword")
            XCTAssertTrue(error.isFixedByCarryingOnByHand)
        }

        // And the safety filter is the mirror image: rewording is the only thing
        // that clears it, and there is no credential to go and check.
        let refusal = EngineError.refused(cause: .safety, explanation: "blocked")
        XCTAssertTrue(refusal.isFixedByRewriting)
        XCTAssertFalse(refusal.isFixedByCarryingOnByHand)
    }

    /// Only the person's own key may be described as the person's own key.
    /// Somebody who never typed one and is told to go and check theirs has been
    /// sent to look for something that does not exist.
    func testOnlyARejectedKeyMentionsAKey() {
        let appRefusal = EngineError.refused(cause: .app, explanation: nil).errorDescription ?? ""
        XCTAssertFalse(appRefusal.localizedCaseInsensitiveContains("key"))

        let keyRefusal = EngineError.refused(cause: .key, explanation: nil).errorDescription ?? ""
        XCTAssertTrue(keyRefusal.localizedCaseInsensitiveContains("key"))
    }
}

private extension EngineError {
    /// Every case, so an invariant over all of them cannot quietly stop covering
    /// one. `EngineError` is not `CaseIterable` — two cases carry values — so
    /// this is written out, and a new case makes the compiler ask nothing at all.
    /// The switch below is what asks: it is exhaustive, so adding a case breaks
    /// the build here until somebody has decided what the new one leaves people
    /// to do.
    static var allFailures: [EngineError] {
        let all: [EngineError] = [
            .timedOut,
            .rateLimited(),
            .offline,
            .refused(cause: .key, explanation: nil),
            .refused(cause: .app, explanation: nil),
            .refused(cause: .safety, explanation: "blocked"),
            .truncated,
            .serviceUnavailable(reason: "Mistral had a problem"),
            .malformedResponse("x"),
            .notEnoughToWorkWith,
        ]
        for error in all {
            switch error {
            case .timedOut, .rateLimited, .offline, .refused, .truncated,
                 .serviceUnavailable, .malformedResponse, .notEnoughToWorkWith:
                continue
            }
        }
        return all
    }
}

final class CruxPromptTests: XCTestCase {
    private func dispute() -> Dispute {
        var dispute = Dispute(title: "Nuclear power", names: PartyPair(a: "Alex", b: "Sam"))
        dispute.positions = PartyPair(a: "We need it", b: "Too costly")
        dispute.claims = [
            Claim(text: "Emissions matter most", origin: .a, agreement: PartyPair(a: true, b: true)),
            Claim(text: "Cost should decide", origin: .b, agreement: PartyPair(a: false, b: true)),
        ]
        return dispute
    }

    private func prompt(for dispute: Dispute) -> String {
        DisputePrompts.findCrux(
            disputeTitle: dispute.title,
            positionA: dispute.positions[.a],
            positionB: dispute.positions[.b],
            agreed: DisputePrompts.list(dispute.sharedClaims),
            contested: DisputePrompts.list(dispute.contestedClaims),
            secondLooks: DisputePrompts.secondLooks(in: dispute)
        )
    }

    /// Common ground is what makes the crux legible — without it the model is
    /// naming a question from half the evidence.
    func testThePromptCarriesBothAgreedAndContestedClaims() {
        let text = prompt(for: dispute())

        XCTAssertTrue(text.contains("Emissions matter most"))
        XCTAssertTrue(text.contains("Cost should decide"))
    }

    /// The instruction that produces one question rather than a list.
    func testThePromptAsksForExactlyOne() {
        let text = prompt(for: dispute())

        XCTAssertTrue(text.contains("Return exactly one"))
        XCTAssertFalse(text.contains("at most two"))
    }

    /// This model copies whatever it is shown. The stance rule carried a worked
    /// example, *not "Person A believes that cost matters most", just "cost
    /// matters most"*, and over the eight tuning debates the example came back
    /// inside the answer on 6 of 16 stances: "Alex says cost matters most: the
    /// pace at which new work is created" reached the last screen.
    ///
    /// So no sample answer goes in this prompt, in any form. The same thing
    /// happened to the two rewrites recorded in docs/DECISIONS.md and to the
    /// claims prompt before it, and each time the fix was to state the rule flat
    /// and enforce it in code — `String.withoutAttribution`, here.
    func testTheCruxPromptShowsTheModelNothingItCanCopy() {
        let text = prompt(for: dispute())

        XCTAssertFalse(text.contains("cost matters most"), "a sample answer is back in the prompt")
        XCTAssertFalse(text.contains("just \""), "a sample answer is back in the prompt")
        // The rule itself has to survive, or the doubled attribution comes back.
        XCTAssertTrue(text.contains("Give the stance by itself"))
    }

    func testSecondLooksReachThePromptWhenThereAreAny() {
        var dispute = self.dispute()
        let contested = dispute.contestedClaims[0]
        dispute.setRethink(
            Rethink(
                claimID: contested.id,
                bestCase: "Cost is the only lever a household controls.",
                changeCondition: "the build came in under budget"
            ),
            for: .a
        )

        let text = prompt(for: dispute)

        XCTAssertTrue(text.contains("Cost is the only lever a household controls."))
        XCTAssertTrue(text.contains("the build came in under budget"))
        XCTAssertTrue(text.contains("What would change Person A's mind"))
    }

    /// A heading with nothing under it is an invitation to invent something.
    func testTheSecondLookSectionIsAbsentWhenNobodyAnsweredOne() {
        let text = prompt(for: dispute())

        XCTAssertFalse(text.contains("said what would change their mind"))
    }

    /// Names never reach the model. It is given "Person A" and "Person B", so
    /// nothing it writes can be steered by who someone is.
    func testRealNamesAreNotSentToTheModel() {
        var dispute = self.dispute()
        dispute.setRethink(
            Rethink(claimID: dispute.claims[0].id, bestCase: "b", changeCondition: "c"),
            for: .b
        )

        let text = prompt(for: dispute)

        XCTAssertFalse(text.contains("Alex"))
        XCTAssertFalse(text.contains("Sam"))
    }
}

/// The prompt behind the one screen where the app says something about a
/// person's own words back to them.
///
/// The feature this replaced flagged facts that looked wrong, and the reason it
/// was replaced is that no wording could stop it reading as the app taking a
/// side. What keeps the new one safe is not tone, it is the question being asked:
/// what a paragraph assumes is a fact about the paragraph. These tests pin the
/// instructions that keep it there.
final class AssumptionPromptTests: XCTestCase {
    private var text: String {
        DisputePrompts.assumptions(
            positionA: "The money is life-changing and offers like this don't come round twice.",
            positionB: "We would be moving the children mid-year for a gamble.",
            disputeTitle: "Whether to take the job"
        )
    }

    /// The line that separates this from the fact check. Naming an assumption is
    /// safe; ruling on it is the thing the app must never do.
    func testTheModelIsForbiddenFromJudgingTheAssumption() {
        XCTAssertTrue(text.contains("Do not say whether it is true"))
        XCTAssertTrue(text.contains("describing the shape of an argument"))
    }

    /// Nothing is ever addressed to the person, because both of them read this
    /// screen and neither is told which card is theirs.
    func testTheModelIsForbiddenFromAddressingThem() {
        XCTAssertTrue(text.contains("do not address them"))
    }

    /// An empty answer has to be reachable and has to be described as normal. The
    /// fact check had no way to say "nothing", which is how it came to flag
    /// something in all eight tuning debates.
    func testFindingNothingIsOfferedAsANormalAnswer() {
        XCTAssertTrue(text.contains("Return an empty list"))
        XCTAssertTrue(text.contains("That is a normal answer"))
    }

    /// Two is the ceiling. This is one card between two turns, not a critique.
    func testAtMostTwoAreAskedFor() {
        XCTAssertTrue(text.contains("at most two"))
    }

    func testThePositionAndTitleAreBothInThePrompt() {
        XCTAssertTrue(text.contains("offers like this don't come round twice"))
        XCTAssertTrue(text.contains("Whether to take the job"))
    }

    /// Names never reach a model anywhere in this app, and this prompt is handed
    /// one position at a time precisely so it has nobody to name.
    func testNothingIdentifiesWhoWroteIt() {
        XCTAssertFalse(text.contains("Person A"))
        XCTAssertFalse(text.contains("Person B"))
    }
}
