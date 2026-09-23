import XCTest
@testable import DisputeCore

/// What the transport does when the provider says "not right now".
///
/// These exist because of a bug that was live on the App Store: a 429 from
/// Mistral's free tier was passed straight up as `rateLimited`, and
/// `rateLimited` puts a wall in front of two people saying the shared allowance
/// is spent. Most of the time it was not spent. The free tier caps requests in
/// flight and tokens per minute across the whole *workspace* — every copy of the
/// app at once — so two arguments happening simultaneously anywhere in the world
/// was enough to end one of them, and it cleared seconds later.
///
/// The fix is that a retryable status is now waited out rather than reported.
/// What has to stay true is the shape of that: it retries the two statuses that
/// clear on their own, it does *not* retry an answer, it obeys `Retry-After`
/// when there is one, and it gives up rather than running past the timeout that
/// would turn a recoverable throttle into `timedOut`.
final class TransportRetryTests: XCTestCase {

    override func tearDown() {
        StubProtocol.reset()
        super.tearDown()
    }

    // MARK: - What gets tried again

    /// The bug, in one test. A throttle followed by an answer is an answer.
    func testAThrottleThatClearsIsWaitedOutRatherThanReported() async throws {
        StubProtocol.queue([
            .throttled(retryAfter: "0"),
            .ok(#"{"question": "Does the pay rise cover the move?"}"#),
        ])

        let reply = try await send()

        XCTAssertTrue(reply.contains("pay rise"))
        XCTAssertEqual(StubProtocol.attempts, 2, "it should have asked twice")
    }

    /// Mistral answers 502 and 503 under load, and those clear the same way a
    /// 429 does.
    func testAProviderHiccupIsWaitedOutToo() async throws {
        StubProtocol.queue([
            .status(503, retryAfter: "0"),
            .ok(#"{"question": "Anything."}"#),
        ])

        _ = try await send()

        XCTAssertEqual(StubProtocol.attempts, 2)
    }

    // MARK: - What does not

    /// A rejected credential is an answer rather than a hiccup. Asking again
    /// spends somebody's time to print the same sentence, and — on the hosted
    /// path — hammers an endpoint that has already said no.
    func testARejectedCredentialIsNotAskedTwice() async {
        StubProtocol.queue([.status(401, body: #"{"message": "bad key"}"#)])

        do {
            _ = try await send()
            XCTFail("a 401 should not have produced a reply")
        } catch let error as EngineError {
            XCTAssertEqual(error, .refused(cause: .key, explanation: "HTTP 401: bad key"))
        } catch {
            XCTFail("arrived as \(error)")
        }
        XCTAssertEqual(StubProtocol.attempts, 1, "a 401 is an answer, not a hiccup")
    }

    /// Same for a prompt the safety filter would not take: the fix is different
    /// words, and no number of attempts produces them.
    func testARefusedPromptIsNotAskedTwice() async {
        StubProtocol.queue([.status(422, body: #"{"message": "no"}"#)])

        _ = try? await send()

        XCTAssertEqual(StubProtocol.attempts, 1)
    }

    // MARK: - Giving up

    /// The message has to survive. A throttle that outlasts the budget is a
    /// throttle somebody genuinely has to be told about, and `rateLimited` is the
    /// one failure whose screen offers to carry on by hand.
    func testAThrottleThatNeverClearsStillArrivesAsRateLimited() async {
        StubProtocol.alwaysThrottled(retryAfter: "0")

        do {
            _ = try await send()
            XCTFail("it should have given up")
        } catch let error as EngineError {
            XCTAssertEqual(error, .rateLimited(detail: "HTTP 429: Requests rate limit exceeded"))
        } catch {
            XCTFail("arrived as \(error)")
        }
        XCTAssertEqual(
            StubProtocol.attempts,
            Requests.maximumAttempts,
            "it should stop at the attempt ceiling rather than spin"
        )
    }

    /// Overrunning `CloudEngine.timeout` does not buy a longer wait, it buys
    /// `timedOut` — whose screen, unlike this one, does not offer a way to carry
    /// on. So a `Retry-After` longer than the budget is not slept on at all.
    func testAWaitLongerThanTheBudgetIsNotTaken() async {
        StubProtocol.alwaysThrottled(retryAfter: "600")

        let startedAt = Date()
        _ = try? await send()

        XCTAssertEqual(StubProtocol.attempts, 1, "ten minutes is past the budget")
        XCTAssertLessThan(
            Date().timeIntervalSince(startedAt),
            5,
            "it should have declined the wait rather than taken it"
        )
    }

    // MARK: - Reading Retry-After

    /// Seconds, which is what Mistral sends.
    func testRetryAfterInSecondsIsObeyed() throws {
        let delay = try XCTUnwrap(
            Requests.retryDelay(after: response(429, retryAfter: "7"), attempt: 1, startedAt: Date())
        )
        XCTAssertEqual(delay, 7, accuracy: 0.001)
    }

    /// The HTTP-date form, which the spec allows and which a proxy in front of
    /// Mistral could produce even though Mistral itself does not.
    func testRetryAfterAsAnHTTPDateIsObeyed() throws {
        let when = Date().addingTimeInterval(30)
        let header = DateFormatter.httpDate.string(from: when)

        let delay = try XCTUnwrap(
            Requests.retryDelay(after: response(429, retryAfter: header), attempt: 1, startedAt: Date())
        )
        XCTAssertEqual(delay, 30, accuracy: 2)
    }

    /// A header nobody can read is not a reason to wait forever or to give up —
    /// it falls back to the app's own backoff.
    func testAnUnreadableRetryAfterFallsBackToBackoff() throws {
        let delay = try XCTUnwrap(
            Requests.retryDelay(
                after: response(429, retryAfter: "soon"),
                attempt: 1,
                startedAt: Date()
            )
        )
        XCTAssertGreaterThanOrEqual(delay, 0)
        XCTAssertLessThanOrEqual(delay, 1, "first backoff is under a second")
    }

    /// The jitter is not decoration. Every phone that hit the same throttle is
    /// waiting on the same clock, and a fixed backoff walks all of them into the
    /// limit again on the same second.
    func testTheBackoffIsJittered() {
        let delays = (0..<40).map { _ in
            Requests.retryDelay(after: response(429), attempt: 2, startedAt: Date())
        }
        XCTAssertGreaterThan(Set(delays.compactMap { $0 }).count, 1, "all identical is not jitter")
    }

    /// Time already spent counts against the budget. This is what stops the
    /// phone retrying a request the Worker has *already* spent twenty-five
    /// seconds retrying on its own side — no header and no coordination, just
    /// the clock telling the truth about how long this has taken.
    func testTimeAlreadySpentCountsAgainstTheBudget() {
        let longAgo = Date().addingTimeInterval(-Requests.retryBudget)
        XCTAssertNil(Requests.retryDelay(after: response(429), attempt: 1, startedAt: longAgo))
    }

    // MARK: - Odds and ends

    private func send() async throws -> String {
        try await MistralTransport(apiKey: "test", session: StubProtocol.session())
            .reply(to: "prompt", system: "system", thinking: .low)
    }

    private func response(_ status: Int, retryAfter: String? = nil) -> HTTPURLResponse {
        HTTPURLResponse(
            url: MistralTransport.endpoint,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: retryAfter.map { ["Retry-After": $0] }
        )!
    }
}

// MARK: - The stub

/// A `URLProtocol` that answers from a script instead of a network.
///
/// Statics rather than an injected handler because `URLProtocol` is instantiated
/// by `URLSession` rather than by the test, so there is nowhere to hand anything
/// in. The lock is what makes that safe under Swift 6 rather than merely quiet.
final class StubProtocol: URLProtocol {
    struct Reply {
        var status: Int
        var body: String
        var retryAfter: String?

        static func ok(_ body: String) -> Reply {
            // Wrapped in the completion shape the transport decodes, so these
            // tests exercise the real read path rather than a shortcut.
            Reply(
                status: 200,
                body: #"{"choices": [{"message": {"content": "\#(body.escapedForJSON)"}}]}"#
            )
        }

        static func throttled(retryAfter: String?) -> Reply {
            .status(429, body: #"{"message": "Requests rate limit exceeded"}"#, retryAfter: retryAfter)
        }

        static func status(_ status: Int, body: String = "{}", retryAfter: String? = nil) -> Reply {
            Reply(status: status, body: body, retryAfter: retryAfter)
        }
    }

    private static let state = State()

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var scripted: [Reply] = []
        private var fallback: Reply?
        private var count = 0

        func queue(_ replies: [Reply], fallback: Reply?) {
            lock.withLock {
                scripted = replies
                self.fallback = fallback
                count = 0
            }
        }

        func next() -> Reply? {
            lock.withLock {
                count += 1
                return scripted.isEmpty ? fallback : scripted.removeFirst()
            }
        }

        var attempts: Int { lock.withLock { count } }

        func reset() {
            lock.withLock {
                scripted = []
                fallback = nil
                count = 0
            }
        }
    }

    static func queue(_ replies: [Reply]) { state.queue(replies, fallback: nil) }

    static func alwaysThrottled(retryAfter: String?) {
        state.queue([], fallback: .throttled(retryAfter: retryAfter))
    }

    static var attempts: Int { state.attempts }

    static func reset() { state.reset() }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let reply = Self.state.next() else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        var headers = ["Content-Type": "application/json"]
        if let retryAfter = reply.retryAfter { headers["Retry-After"] = retryAfter }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension String {
    /// Enough escaping for a test fixture to survive being nested inside the
    /// completion envelope above.
    var escapedForJSON: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
