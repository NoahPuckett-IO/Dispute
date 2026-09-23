import XCTest
@testable import DisputeCore

/// The hosted engine's half of the contract, without a network.
///
/// These could not be written until the transport became a seam. Before that,
/// `CloudEngine` was a `URLSession` with prompts wrapped round it, so the only
/// way to ask "what does this do when the model writes prose around its JSON"
/// was to spend somebody's quota and hope the model did that today.
/// `CloudEngineLiveTests` still exists and still asks the questions only the real
/// thing can answer. This asks the ones it never could: the app's own behaviour
/// when an answer arrives in a shape it did not ask for.
final class CloudEngineTests: XCTestCase {
    /// A transport that says what it is told to say.
    private struct Scripted: ModelTransport {
        let replies: [String]
        let error: EngineError?
        /// What actually went down the pipe, for the tests that care.
        let seen = Recorder()

        init(_ replies: String..., error: EngineError? = nil) {
            self.replies = replies
            self.error = error
        }

        func reply(to prompt: String, system: String, thinking: Thinking) async throws -> String {
            if let error { throw error }
            let index = seen.record(prompt: prompt, system: system, thinking: thinking)
            return replies[min(index, replies.count - 1)]
        }
    }

    /// `ModelTransport` is `Sendable` and the engine holds it as a `let`, so a
    /// mutable count needs somewhere legitimate to live.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var prompts: [String] = []
        private(set) var systems: [String] = []
        private(set) var thinking: [Thinking] = []

        @discardableResult
        func record(prompt: String, system: String, thinking level: Thinking) -> Int {
            lock.lock()
            defer { lock.unlock() }
            prompts.append(prompt)
            systems.append(system)
            thinking.append(level)
            return prompts.count - 1
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return prompts.count
        }
    }

    private let claimsJSON = """
        {"claims_a": [
            "The pay rise would cover what the move costs.",
            "A comparable offer is unlikely to come along soon.",
            "Four years in one role is long enough to stop learning."
        ],
        "claims_b": [
            "Changing schools mid-year sets a child back.",
            "The company may not exist in two years.",
            "Housing costs cancel out most of the difference."
        ]}
        """

    // MARK: - The system prompt

    /// The rules the whole app depends on — never take a side, never counsel,
    /// never use a dash — are in the system prompt, and a transport that dropped
    /// it would produce answers that still parse and still fit every screen.
    /// Nothing else in the suite would notice.
    func testTheSystemPromptReachesTheModelOnEveryCall() async throws {
        let transport = Scripted(claimsJSON)
        _ = try await CloudEngine(transport: transport).breakDown(
            positionA: "We should take the job, the money is life-changing.",
            positionB: "We would be moving the children mid-year for a gamble.",
            disputeTitle: "Whether to take the job"
        )

        XCTAssertEqual(transport.seen.systems.first, DisputePrompts.systemPrompt)
    }

    // MARK: - Answers with rubbish round them

    /// A JSON mode is a strong request rather than a guarantee, and the three
    /// ways a model breaks it are all "a valid answer with something either side
    /// of it".
    func testItReadsAnAnswerThatCameWrappedInProseOrAFence() async throws {
        for wrapped in [
            "```json\n\(claimsJSON)\n```",
            "Here is the JSON you asked for:\n\(claimsJSON)",
            "\(claimsJSON)\n\nI hope this helps with the disagreement.",
        ] {
            let claims = try await CloudEngine(transport: Scripted(wrapped)).breakDown(
                positionA: "We should take the job, the money is life-changing.",
                positionB: "We would be moving the children mid-year for a gamble.",
                disputeTitle: "Whether to take the job"
            )
            XCTAssertGreaterThanOrEqual(claims.count, Claim.minimumUsableClaims)
        }
    }

    func testAnAnswerWithNoJSONInItIsAMalformedResponse() async {
        let engine = CloudEngine(transport: Scripted("I would rather not do that."))
        do {
            _ = try await engine.findAssumptions(positionA: "Anything.", positionB: "Or anything.", disputeTitle: "t")
            XCTFail("prose was accepted as an answer")
        } catch let error as EngineError {
            guard case .malformedResponse = error else {
                return XCTFail("\(error) is not what a screen expects here")
            }
            // Sampled models genuinely come back usable on a second press.
            XCTAssertTrue(error.isRetryable)
        } catch {
            XCTFail("\(error) is not an EngineError")
        }
    }

    // MARK: - Asking twice

    /// One bad list is bad luck. The engine asks again before it gives up, and
    /// the screen that handles giving up is a different screen — so which one
    /// somebody lands on depends entirely on this count being right.
    func testItAsksASecondTimeWhenTheFirstListIsUnusable() async throws {
        let thin = #"{"claims_a": ["Yes."], "claims_b": ["No."]}"#
        let transport = Scripted(thin, claimsJSON)

        let claims = try await CloudEngine(transport: transport).breakDown(
            positionA: "We should take the job, the money is life-changing.",
            positionB: "We would be moving the children mid-year for a gamble.",
            disputeTitle: "Whether to take the job"
        )

        XCTAssertEqual(transport.seen.count, 2, "the second attempt never happened")
        XCTAssertGreaterThanOrEqual(claims.count, Claim.minimumUsableClaims)
    }

    func testTwoUnusableListsAskThePeopleForMoreRatherThanTheModel() async {
        let thin = #"{"claims_a": ["Yes."], "claims_b": ["No."]}"#
        let transport = Scripted(thin)

        do {
            _ = try await CloudEngine(transport: transport).breakDown(
                positionA: "Yes.",
                positionB: "No.",
                disputeTitle: "t"
            )
            XCTFail("a two-point list was accepted")
        } catch let error as EngineError {
            XCTAssertEqual(error, .notEnoughToWorkWith)
            // The one error whose answer is not "try that again": measured, the
            // same prompt comes back unusable five times in six.
            XCTAssertFalse(error.isRetryable)
            XCTAssertTrue(error.isFixedByRewriting)
        } catch {
            XCTFail("\(error) is not an EngineError")
        }
        XCTAssertEqual(transport.seen.count, 2, "it gave up early, or kept going")
    }

    // MARK: - The crux

    /// An unusable crux is `nil`, not a throw. The screen has something to say
    /// about finding nothing and nothing to say about a crash.
    func testACruxWithNothingInItComesBackAsNothingFound() async throws {
        let engine = CloudEngine(transport: Scripted(
            #"{"question": "", "position_a": "Yes", "position_b": "No", "test": "Go and count them."}"#
        ))
        let crux = try await engine.findCrux(in: Dispute(title: "t", names: PartyPair(a: "A", b: "B")))
        XCTAssertNil(crux)
    }

    /// `test` is optional on the wire and not on the screen. A model that omits
    /// it should produce a crux without one, not a decode failure that the app
    /// reports as "nothing found".
    func testACruxWithNoTestStillArrives() async throws {
        let engine = CloudEngine(transport: Scripted(
            #"{"question": "Does the pay rise cover the move?", "position_a": "Yes", "position_b": "No"}"#
        ))
        let crux = try await engine.findCrux(in: Dispute(title: "t", names: PartyPair(a: "A", b: "B")))

        let found = try XCTUnwrap(crux)
        XCTAssertTrue(found.isUsable)
        XCTAssertFalse(found.hasTest)
    }

    // MARK: - Assumptions

    /// Two is what the card between the turns holds, and it is two *each*.
    ///
    /// The cap has to be applied per person rather than to the pair, or one
    /// verbose paragraph takes both slots and the second person's turn opens on a
    /// card about somebody else. A model handing back six is not a reason to draw
    /// six either way.
    func testNoMoreThanTwoAssumptionsSurviveForEachPerson() async throws {
        let many = (1...6)
            .map { #"{"quote": "always \#($0)", "assumption": "This treats the usual case as the only case, with no exception allowed for \#($0)."}"# }
            .joined(separator: ",")
        let engine = CloudEngine(
            transport: Scripted(#"{"assumptions_a": [\#(many)], "assumptions_b": [\#(many)]}"#)
        )

        let flags = try await engine.findAssumptions(positionA: "a", positionB: "b", disputeTitle: "t")

        XCTAssertEqual(flags.filter { $0.party == .a }.count, 2)
        XCTAssertEqual(flags.filter { $0.party == .b }.count, 2)
    }

    /// One person's paragraph resting on nothing is an ordinary answer, and it
    /// must not cost the other person theirs. Models omit the key rather than
    /// send an empty array, so this is the shape that actually arrives.
    func testNothingFoundForOnePersonLeavesTheOtherAlone() async throws {
        let one = #"{"quote": "always", "assumption": "This treats the usual case as the only case, with nothing allowed outside it."}"#
        let engine = CloudEngine(transport: Scripted(#"{"assumptions_b": [\#(one)]}"#))

        let flags = try await engine.findAssumptions(positionA: "a", positionB: "always", disputeTitle: "t")

        XCTAssertEqual(flags.count, 1)
        XCTAssertEqual(flags.first?.party, .b)
    }

    func testNoAssumptionsAtAllIsAPerfectlyGoodAnswer() async throws {
        let engine = CloudEngine(transport: Scripted(#"{"assumptions_a": [], "assumptions_b": []}"#))
        let flags = try await engine.findAssumptions(positionA: "Anything.", positionB: "Or anything.", disputeTitle: "t")
        XCTAssertTrue(flags.isEmpty)
    }

    // MARK: - What each call is worth thinking about

    /// Thinking is billed as output and drawn from the same shared quota, and
    /// left unasked this model thinks at `medium` on all three calls. Over a day
    /// of two people testing that came to 24k thinking tokens against 1.5k tokens
    /// of answer, and the free tier ran out mid-argument.
    ///
    /// So the two extraction calls ask for less. This is the test that says which
    /// ones: an economy quietly applied to the crux as well would be invisible
    /// here, invisible on screen, and paid for in the one answer the app exists
    /// to produce.
    func testOnlyTheCruxIsWorthTheModelsFullThinking() async throws {
        let claims = Scripted(claimsJSON)
        _ = try await CloudEngine(transport: claims).breakDown(
            positionA: "We should take the job, the money is life-changing.",
            positionB: "We would be moving the children mid-year for a gamble.",
            disputeTitle: "Whether to take the job"
        )
        XCTAssertEqual(claims.seen.thinking, [.low])

        let assumptions = Scripted(#"{"assumptions": []}"#)
        _ = try await CloudEngine(transport: assumptions)
            .findAssumptions(positionA: "Anything.", positionB: "Or anything.", disputeTitle: "t")
        XCTAssertEqual(assumptions.seen.thinking, [.low])

        let crux = Scripted(
            #"{"question": "Does the pay rise cover the move?", "position_a": "Yes", "position_b": "No"}"#
        )
        _ = try await CloudEngine(transport: crux)
            .findCrux(in: Dispute(title: "t", names: PartyPair(a: "A", b: "B")))
        XCTAssertEqual(crux.seen.thinking, [.standard])
    }

    // MARK: - Failures on the way out

    /// Whatever the transport threw has to arrive at the screen unchanged. A
    /// spent quota that gets rewritten into "unexpected response" on the way up
    /// costs somebody the one message that tells them what to do about it.
    func testTheFailureTheTransportThrewIsTheFailureTheScreenGets() async {
        for thrown: EngineError in [
            .rateLimited(),
            .offline,
            .refused(cause: .app, explanation: nil),
            .refused(cause: .key, explanation: "bad key"),
            .timedOut,
            .serviceUnavailable(reason: "Mistral had a problem"),
        ] {
            let engine = CloudEngine(transport: Scripted("", error: thrown))
            do {
                _ = try await engine.findAssumptions(positionA: "x", positionB: "y", disputeTitle: "t")
                XCTFail("\(thrown) vanished")
            } catch let error as EngineError {
                XCTAssertEqual(error, thrown)
            } catch {
                XCTFail("\(thrown) arrived as \(error)")
            }
        }
    }

    // MARK: - Status codes

    /// Both transports read the same status codes into the same failures, so the
    /// mapping is tested once, here.
    func testStatusCodesBecomeFailuresAScreenCanExplain() {
        XCTAssertEqual(EngineError(status: 429, detail: nil), .rateLimited())
        // Mistral's support team settled what its two refusals mean, and the
        // answer was not the one this test used to assert.
        //
        // A 429 always means the model is allowed and there is no capacity
        // spare — including the "Service tier capacity exceeded for this model"
        // wording, which reads like the opposite. `rateLimited` is right for all
        // of them, and it carries Mistral's words now so nobody has to guess
        // which flavour it was.
        XCTAssertEqual(
            EngineError(status: 429, detail: "Service tier capacity exceeded for this model."),
            .rateLimited(detail: "HTTP 429: Service tier capacity exceeded for this model.")
        )
        // The model genuinely not being on this plan is a 403 with its own code,
        // and it is emphatically not the app being turned down — which is what
        // `refused(.app)` says, and which sent a week of debugging at App Check.
        XCTAssertEqual(
            EngineError(status: 403, detail: "tier_not_allowed", credential: .app),
            .serviceUnavailable(reason: "Mistral could not serve the model this app asks for")
        )
        // A real throttle still reads as one, and now carries what Mistral said
        // so a report from somebody's phone names the cause.
        XCTAssertEqual(
            EngineError(status: 429, detail: "Requests rate limit exceeded"),
            .rateLimited(detail: "HTTP 429: Requests rate limit exceeded")
        )
        XCTAssertEqual(
            EngineError(status: 503, detail: nil),
            .serviceUnavailable(reason: "Mistral had a problem")
        )
        XCTAssertEqual(
            EngineError(status: 400, detail: "blocked by the safety filter"),
            .refused(cause: .safety, explanation: "blocked by the safety filter")
        )

        // The same 403, and opposite advice, decided by which credential was
        // turned down. A key the person pasted in is theirs to check; the app
        // failing to prove it is the app is nothing they can act on at all.
        XCTAssertEqual(
            EngineError(status: 403, detail: nil),
            .refused(cause: .key, explanation: "HTTP 403")
        )
        XCTAssertEqual(
            EngineError(status: 403, detail: nil, credential: .app),
            .refused(cause: .app, explanation: "HTTP 403")
        )
    }
}
