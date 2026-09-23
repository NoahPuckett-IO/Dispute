import Foundation

/// How a prompt gets to the model and an answer gets back.
///
/// One method, because one method is the whole of what `CloudEngine` needs. It
/// composes the prompts, decides what a usable answer is, retries the call that
/// is worth retrying and throws the errors the screens know how to explain —
/// none of which has anything to do with which pipe the bytes went down.
///
/// There are two pipes, and that is the reason this exists:
///
/// - `ProxyTransport` goes through the app's own Worker, which holds the
///   credential and hands the request on to Mistral. No key on the phone: what
///   the phone carries is an App Check token proving it is a real copy of this
///   app. That is what makes the AI free for somebody who has just installed
///   this and is standing in a kitchen having an argument.
/// - `MistralTransport` opens a connection to Mistral with a key the person
///   pasted in. It is the way for anybody who wants their own quota rather than
///   a share of the app's, and it is the way this gets tested on a real phone
///   before there is a Worker in front of it.
///
/// Both speak the same wire format — Mistral's API is OpenAI-shaped and the
/// Worker passes that shape straight through — so the request and the reply are
/// built in one place and the two transports differ only in where they point and
/// how they prove they are allowed.
///
/// **This protocol was called `GeminiTransport`.** It was renamed with the
/// provider, because a protocol named for a company the app no longer talks to
/// is the kind of thing that is still there three providers later.
///
/// `system` is passed per call rather than held by the transport because both
/// providers want it every time and a transport that stored it would be a second
/// place for it to drift.
public protocol ModelTransport: Sendable {
    /// The model's answer as text, or an `EngineError` explaining why there
    /// isn't one.
    ///
    /// Text rather than a decoded type: what comes back is a JSON object the
    /// model wrote, `CloudEngine.decodeJSON` is the one place that is allowed to
    /// be forgiving about it, and a transport that started parsing would be a
    /// second place for that to drift.
    func reply(to prompt: String, system: String, thinking: Thinking) async throws -> String
}

/// How much thinking a call is worth paying for.
///
/// ## What this means now
///
/// Nothing, on the models this app ships against, and that is worth being
/// precise about rather than quietly deleting.
///
/// Gemini 3 thought before every answer and could be told how hard, which
/// mattered enormously: measured over a day of two people testing, the default
/// spent 24k thinking tokens against 1.5k tokens of actual answer, and thinking
/// was billed as output against the same quota. Asking for less on the two
/// extraction calls was most of what kept the app inside a free tier.
///
/// Mistral Medium 3.5 and Large 3 do not deliberate before answering and take no
/// parameter for it, so both cases currently send the same request. The enum
/// stays because the *distinction* is still true about the three calls — two of
/// them are extraction and one is the thing the app is for — and because the day
/// this app is pointed at a reasoning model (Magistral, or whatever replaces it),
/// the mapping goes in `Requests.body` and nothing above it changes.
///
/// Deleting it would mean rediscovering which calls deserve the budget, and that
/// was measured once already.
public enum Thinking: Sendable, Equatable {
    /// Whatever the model does unasked.
    ///
    /// The crux call. Naming a question that would move *both* people is the
    /// product, and it is the one call the fixtures score.
    case standard

    /// Enough to follow the instructions, not enough to deliberate over them.
    ///
    /// For the calls whose answer is already in front of the model.
    case low
}

// MARK: - Mistral, directly

/// Mistral over HTTP, with a key belonging to whoever typed it in.
///
/// The path for somebody who wants their own quota, and the path this app is
/// developed against: a key in the Keychain and no Worker in the way is the
/// shortest distance between a build on a cable and an answer on a screen.
public struct MistralTransport: ModelTransport {
    static let endpoint = URL(string: "https://api.mistral.ai/v1/chat/completions")!

    private let apiKey: String
    private let session: URLSession

    public init(apiKey: String, session: URLSession? = nil) {
        self.apiKey = apiKey
        self.session = session ?? Requests.defaultSession()
    }

    public func reply(to prompt: String, system: String, thinking: Thinking) async throws -> String {
        try await Requests.send(
            to: Self.endpoint,
            prompt: prompt,
            system: system,
            thinking: thinking,
            // A key somebody pasted in, so a rejected credential is theirs and
            // the screen can say exactly where to fix it.
            authorization: "Bearer \(apiKey)",
            credential: .key,
            session: session
        )
    }
}

// MARK: - Mistral, through the app's Worker

/// Mistral through the app's own proxy, with no key on the phone.
///
/// This is what somebody gets when they install the app and start arguing. There
/// is nothing to sign up for, nothing to paste in, and nothing to pay: a
/// Cloudflare Worker holds the credential, forwards the request to Mistral, and
/// the phone's side of it is an App Check token proving this is a real copy of
/// this app rather than a script somebody pointed at the endpoint.
///
/// The alternative was the thing the app did before, and it worked, and almost
/// nobody did it. Getting a key takes about a minute and it is a minute spent
/// while two people are standing in a kitchen mid-argument, which is the worst
/// moment anybody has ever been asked to go and make an account.
///
/// ## Why the token arrives as a closure
///
/// Because App Check is Firebase's, Firebase is a binary, and `DisputeCore`
/// links none. The whole test suite runs in a second or two because this package
/// builds with the command line tools alone, and pulling the Firebase SDK down
/// here to fetch one string would cost that for nothing. The app target knows
/// how to get a token; this knows what to do with one.
///
/// It is `async` because fetching a token is: App Attest talks to the Secure
/// Enclave and then to Apple, and the first call after a cold launch is not
/// instant.
///
/// ## What it costs
///
/// Nothing, and that is a decision with an edge on it. The no-cost tier is
/// Mistral's free tier, whose quota belongs to the *account* rather than to each
/// phone — so every copy of this app draws on one allowance. It is a far larger
/// allowance than the app had before, and it is still one pool: a busy enough day
/// means somebody's session hits `rateLimited` through no fault of their own.
/// Two things soften that and neither hides it: the by-hand path is a complete
/// way to use the app and the message says so, and anybody who would rather not
/// share the pool can paste in a key of their own, which is what
/// `MistralTransport` is still here for.
public struct ProxyTransport: ModelTransport {
    private let endpoint: URL
    private let token: @Sendable () async throws -> String
    private let session: URLSession

    /// - Parameters:
    ///   - endpoint: The Worker's chat route.
    ///   - session: Injectable so the tests can drive this without a network.
    ///   - token: Produces an App Check token. Throwing from here is the honest
    ///     answer when attestation fails, and it arrives at the screens as
    ///     `refused(cause: .app)` — *this copy of the app* was not vouched for,
    ///     which is nothing the two people in front of the phone can fix and so
    ///     must never send them looking for a key they never typed.
    public init(
        endpoint: URL,
        session: URLSession? = nil,
        token: @escaping @Sendable () async throws -> String
    ) {
        self.endpoint = endpoint
        self.token = token
        self.session = session ?? Requests.defaultSession()
    }

    public func reply(to prompt: String, system: String, thinking: Thinking) async throws -> String {
        let appCheckToken: String
        do {
            appCheckToken = try await token()
        } catch {
            // Attestation failed before a byte left the phone. Not a network
            // failure and not the person's key, so it is neither `offline` nor
            // `.key`.
            //
            // The underlying error is carried rather than dropped, and dropping
            // it was a mistake worth naming: `.app` is the one failure whose two
            // causes are indistinguishable on screen — a token this phone could
            // not obtain, and a token the Worker would not accept — and they are
            // fixed in different places. With `nil` here the debug transcript
            // recorded the same sentence for both. Nothing user-facing shows
            // this; `errorDescription` for `.app` is fixed prose, because the
            // two people holding the phone can act on neither.
            throw EngineError.refused(
                cause: .app,
                explanation: "no App Check token: \(error)"
            )
        }
        return try await Requests.send(
            to: endpoint,
            prompt: prompt,
            system: system,
            thinking: thinking,
            // The Worker reads this header, verifies the token against Firebase's
            // public keys and only then spends the app's quota. The real
            // credential never comes near the phone.
            appCheckToken: appCheckToken,
            credential: .app,
            session: session
        )
    }
}

// MARK: - The request both of them make

/// The one place a chat request is built and a reply is read.
///
/// Both transports hit an OpenAI-shaped endpoint and differ only in where they
/// point and what proves they are allowed, so everything else — the body, the
/// status mapping, the shape of a usable reply — lives here once. The two halves
/// of this were written out separately under the previous provider and drifted
/// within a month, which is how `response_format` ended up on one path and not
/// the other.
enum Requests {
    static func defaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        // Generous, because the alternative is worse. The crux call is the long
        // one, and a timeout means two people who waited half a minute are told
        // it failed and asked to wait again.
        configuration.timeoutIntervalForRequest = CloudEngine.timeout
        configuration.timeoutIntervalForResource = CloudEngine.timeout
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    static func send(
        to endpoint: URL,
        prompt: String,
        system: String,
        thinking: Thinking,
        authorization: String? = nil,
        appCheckToken: String? = nil,
        credential: RefusalCause,
        session: URLSession
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authorization {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        if let appCheckToken {
            request.setValue(appCheckToken, forHTTPHeaderField: "X-Firebase-AppCheck")
        }
        request.httpBody = try JSONSerialization.data(
            withJSONObject: body(prompt: prompt, system: system, thinking: thinking)
        )

        let startedAt = Date()
        for attempt in 1... {
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch let error as URLError where error.code == .timedOut {
                throw EngineError.timedOut
            } catch {
                throw EngineError.offline
            }

            let http = response as? HTTPURLResponse
            if let http, !(200..<300).contains(http.statusCode) {
                let failure = EngineError(
                    status: http.statusCode,
                    detail: APIError.message(in: data),
                    credential: credential
                )
                guard let wait = retryDelay(
                    after: http,
                    attempt: attempt,
                    startedAt: startedAt
                ) else {
                    throw failure
                }
                try? await Task.sleep(for: .seconds(wait))
                continue
            }

            guard let completion = try? JSONDecoder().decode(ChatCompletion.self, from: data),
                  let choice = completion.choices.first
            else {
                throw EngineError.malformedResponse("the reply was not in the expected shape")
            }
            // Mistral says `length` where Gemini's OpenAI-compatible endpoint said
            // `max_tokens`. Both mean the context window filled, and both mean the
            // only part of that anybody can change is how much they wrote.
            if let reason = choice.finish_reason, reason == "length" || reason == "model_length" {
                throw EngineError.truncated
            }
            guard let content = choice.message.content, !content.trimmed.isEmpty else {
                throw EngineError.malformedResponse("the reply came back empty")
            }
            return content
        }
        // Unreachable: the loop either returns, throws, or sleeps, and
        // `retryDelay` stops handing out sleeps long before the budget is gone.
        throw EngineError.serviceUnavailable(reason: "\(CloudEngine.providerName) had a problem")
    }

    /// How long to wait before trying this request again, or `nil` for "don't".
    ///
    /// ## Why this is here at all
    ///
    /// Because a 429 from Mistral is usually not what the word "limit" makes it
    /// sound like. The free tier caps three separate things — requests in flight
    /// at once, tokens per minute, and tokens per month — and the first two belong
    /// to the *workspace*, which is to say to every copy of this app at once. Two
    /// arguments happening simultaneously anywhere in the world is enough to turn
    /// one of them into a 429 that clears a few seconds later.
    ///
    /// Passed straight up, that became `rateLimited`, and `rateLimited` puts a
    /// wall in front of two people saying the shared allowance is spent. It was
    /// not spent. Nobody had used it up and nothing they did caused it, and the
    /// app ended their session over four seconds of somebody else's request.
    ///
    /// So a throttle is waited out rather than reported, up to a point, and the
    /// message survives for the case where the wait does not help.
    ///
    /// ## The budget
    ///
    /// Measured from the start of the *first* attempt rather than from now, which
    /// is what keeps this from compounding with the retry the Worker already does
    /// on its own side. A proxied call that spent twenty-five seconds being
    /// retried upstream arrives here with most of the budget gone and is not
    /// retried a second time — no header, no coordination, just the clock telling
    /// the truth about how long this has taken.
    ///
    /// The ceiling is set under `CloudEngine.timeout` for a reason worth stating:
    /// overrunning it does not produce a longer wait, it produces `timedOut`,
    /// which is a strictly worse error because the screen behind it does not
    /// offer to carry on by hand.
    ///
    /// ## The wait itself
    ///
    /// `Retry-After` when the provider sent one, because a number they chose
    /// beats a number this made up. Otherwise exponential with full jitter. The
    /// jitter matters more than the exponent: every phone that hit the same
    /// throttle is waiting on the same clock, and a fixed backoff walks all of
    /// them into the limit again on the same second.
    static func retryDelay(
        after response: HTTPURLResponse,
        attempt: Int,
        startedAt: Date
    ) -> TimeInterval? {
        // 429 is the whole reason this exists. 5xx is here because Mistral
        // answers with 502 and 503 under load and they clear the same way.
        // Everything else — a rejected key, a refused prompt, a body it would not
        // take — is an answer rather than a hiccup, and asking again only spends
        // somebody's time to print the same sentence twice.
        let status = response.statusCode
        guard status == 429 || (500..<600).contains(status) else { return nil }
        guard attempt < maximumAttempts else { return nil }

        let header = response.value(forHTTPHeaderField: "Retry-After")
        let wait = header.flatMap(retryAfterSeconds)
            ?? Double.random(in: 0...1) * pow(2, Double(attempt - 1))
        guard Date().timeIntervalSince(startedAt) + wait < retryBudget else { return nil }
        return wait
    }

    /// `Retry-After` in either of the two forms the spec allows. Mistral sends
    /// seconds; the HTTP-date form is read as well because it costs three lines
    /// and the alternative is silently falling back to a guess.
    private static func retryAfterSeconds(_ header: String) -> TimeInterval? {
        if let seconds = TimeInterval(header.trimmed), seconds >= 0 { return seconds }
        guard let date = DateFormatter.httpDate.date(from: header.trimmed) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }

    /// Attempts in total, not retries after the first.
    static let maximumAttempts = 3

    /// Wall clock from the first attempt, including the time the attempts
    /// themselves took. Under `CloudEngine.timeout` by enough that the longest
    /// call in the app — the crux, with both positions and every second look in
    /// front of it — still has room to finish after the last wait.
    static let retryBudget: TimeInterval = 45

    static func body(prompt: String, system: String, thinking: Thinking) -> [String: any Sendable] {
        // `thinking` is deliberately unread. See `Thinking` — the models this
        // ships against take no parameter for it, and the switch that would map
        // it belongs here on the day one does.
        _ = thinking
        return [
            "model": CloudEngine.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": prompt],
            ],
            // Low but not zero, for the same reason as any other sampler here:
            // greedy decoding makes a model repeat itself across the two sides.
            "temperature": CloudEngine.temperature,
            "max_tokens": CloudEngine.maximumOutputTokens,
            // Mistral's JSON mode. As with every other provider's, a strong
            // request rather than a guarantee — `CloudEngine.decodeJSON` is still
            // the thing that makes it safe. Mistral additionally requires the
            // word JSON to appear in the messages, which `DisputePrompts` has
            // always done because every other provider wanted it too.
            "response_format": ["type": "json_object"],
        ]
    }

}

extension DateFormatter {
    /// RFC 9110's `IMF-fixdate`, which is the only date form a `Retry-After`
    /// header is allowed to use. Fixed locale and time zone rather than the
    /// device's: this parses a machine's string, and a phone set to Arabic
    /// numerals or a non-Gregorian calendar would otherwise fail to read a
    /// perfectly ordinary header.
    /// Internal rather than private only so `TransportRetryTests` can build a
    /// header in the same form it has to parse.
    static let httpDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}

// MARK: - Wire shapes

private struct ChatCompletion: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
        let finish_reason: String?
    }
    let choices: [Choice]
}

/// Mistral is not consistent about its error envelope: a rejected key comes back
/// as `{"message": ...}`, a rejected body as `{"detail": [{"msg": ...}]}`, and
/// the Worker in front of it sends `{"error": {"message": ...}}` like everything
/// else. All three are read here rather than in three `catch` blocks.
private struct APIError: Decodable {
    struct Nested: Decodable { let message: String? }
    struct Detail: Decodable { let msg: String? }

    let message: String?
    let error: Nested?
    let detail: [Detail]?

    static func message(in data: Data) -> String? {
        guard let decoded = try? JSONDecoder().decode(APIError.self, from: data) else { return nil }
        return decoded.message
            ?? decoded.error?.message
            ?? decoded.detail?.compactMap(\.msg).first
    }
}

// MARK: - Status codes

public extension EngineError {
    /// The failure an HTTP status means.
    ///
    /// Shared by both transports, and it has to be: the Worker is a proxy in
    /// front of the same API, so a spent quota is a 429 either way and a
    /// turned-down request is a 401 or 403 either way.
    ///
    /// What differs is *whose* credential was turned down, which the caller knows
    /// and this cannot: on the direct path it is a key somebody pasted into
    /// Settings, and on the hosted path it is the app itself failing to prove it
    /// is the app. Same status code, opposite advice — so it is a parameter.
    init(status: Int, detail: String?, credential: RefusalCause = .key) {
        switch status {
        // The status travels with the message, and it has to.
        //
        // On the hosted path a 401 has two completely different causes that look
        // identical on screen: the Worker refusing an App Check token, and
        // Mistral refusing the Worker's key. One is fixed on the phone, the other
        // in a Cloudflare secret, and for a week this app said the same fourteen
        // words for both while somebody guessed between them.
        //
        // They are trivially distinguishable in the body — the Worker says "App
        // Check rejected", Mistral says something about a key — so the body is
        // what gets carried up, with the status in front of it.
        // A model this plan may not have is not this copy of the app being
        // turned down, and saying it was sent a week of debugging at App Check.
        //
        // Mistral's support team named the code. 403 `tier_not_allowed` means
        // the model is not on this plan — nothing about the phone, the build, or
        // App Attest, all three of which `refused(.app)` points at when it says
        // "wouldn't take a request from this copy of the app".
        case 403 where (detail ?? "").lowercased().contains("tier_not_allowed"):
            self = .serviceUnavailable(
                reason: "\(CloudEngine.providerName) could not serve the model this app asks for"
            )
        case 401, 403:
            self = .refused(
                cause: credential,
                explanation: detail.map { "HTTP \(status): \($0)" } ?? "HTTP \(status)"
            )
        // Every 429, including the "Service tier capacity exceeded for this
        // model" one that used to be special-cased here.
        //
        // That special case was a guess, and Mistral's support team has since
        // corrected it: a 429 always means the model is allowed and there is no
        // capacity spare. It never means the identifier is unusable — that is
        // the 403 above. So the split was wrong, and `rateLimited` already says
        // the true thing: busy, or the shared free limit is spent.
        //
        // What it carries now is Mistral's own words, because "rate limited" has
        // been the misleading answer twice and the next person to see this
        // should not have to guess.
        case 429:
            self = .rateLimited(detail: detail.map { "HTTP 429: \($0)" })
        // 422 is Mistral's validation failure, and the one that turns up in
        // practice is a prompt its filters would not take.
        case 400 where (detail ?? "").lowercased().contains("safety"), 422, 451:
            self = .refused(cause: .safety, explanation: detail)
        case 500...599:
            self = .serviceUnavailable(reason: "\(CloudEngine.providerName) had a problem")
        default:
            self = .malformedResponse(detail ?? "the request was rejected")
        }
    }
}
