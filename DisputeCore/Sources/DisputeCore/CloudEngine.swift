import Foundation

/// `DisputeEngine` backed by a hosted model.
///
/// The same three calls as the on-device engine and the same types back, so
/// nothing above the protocol knows which one it got. What differs is the size of
/// the model: 1.7B parameters against something orders of magnitude larger, on
/// the two jobs in this app that reward reading closely — finding the question
/// underneath two paragraphs of somebody's actual argument, and naming what those
/// paragraphs take for granted. The small model produces something well-formed
/// and shallow, and two people who have just typed out a real disagreement can
/// tell immediately.
///
/// Everything here is about *what to ask and what to accept back*. How the ask
/// travels is a `ModelTransport`, and there are two: through the app's Worker,
/// which is what somebody who has just installed this gets and costs them
/// nothing, or straight to Mistral with a key of their own. Neither changes a
/// prompt, a retry, or what counts as a usable answer, which is the reason the
/// seam is where it is — and it is the reason swapping the provider underneath
/// all of this touched two files rather than twenty.
public struct CloudEngine: DisputeEngine {
    /// Who the request goes to, for the sentences that have to name them.
    ///
    /// Its own constant because the app is legally obliged to say this out loud
    /// — guideline 5.1.2(i) and the consent screen built for it — and the last
    /// provider's name ended up hardcoded in nine places across two targets,
    /// where changing it meant finding all nine. Anything user-facing that names
    /// the company reads it from here.
    public static let providerName = "Mistral"

    /// Everybody who might read what the two of them wrote, for the sentences
    /// that promise where it goes.
    ///
    /// Not the same as `providerName`, and the difference is the whole point.
    /// The proxy answers with a model running on Cloudflare when Mistral will
    /// not, which it has been doing since the day Mistral stopped answering at
    /// all — so "sent to Mistral" stopped being the whole truth, on the one
    /// screen in this app that cannot afford a half-truth.
    ///
    /// Cloudflare was always in the path as the operator of the proxy. What
    /// changed is that it may now run the model too, and a consent screen that
    /// names one recipient while a second reads the same words is the exact
    /// failure this release spent a week undoing.
    ///
    /// `providerName` still names who the app *asks* first, for the sentences
    /// that are about the provider rather than about the data.
    public static let recipients = "Mistral or Cloudflare"

    /// One model rather than a picker: choosing between model identifiers is a
    /// question nobody using this app can answer, and the right answer changes
    /// every few months. The app makes the choice and this is where it is
    /// written down.
    ///
    /// **A dated identifier again, and chosen from the account rather than the
    /// docs this time.**
    ///
    /// The previous one, `mistral-medium-2604`, was not a string this account
    /// could call at all, and the docs disagree with themselves about what
    /// Medium's identifier even is. The authority is Mistral's own Admin →
    /// Limits page, which lists exactly what this workspace may call and at what
    /// rate. This string is copied from there.
    ///
    /// It was briefly `mistral-large-2512`, chosen off Mistral's Admin → Limits
    /// page, which lists Large at twelve times Medium's tokens-per-minute. That
    /// page describes the *organisation's* limits and is not the same list as the
    /// models an API key may actually call: `GET /v1/models` on this account
    /// returns no Large of any kind. Every request 403'd until it went back.
    ///
    /// The lesson is the one this file keeps relearning. `GET /v1/models` on the
    /// key that will make the requests is the only list that means anything —
    /// not the docs, not the limits page. `scripts/check-mistral.sh` asks it.
    ///
    /// **The old note argued for an alias. Read that argument, then this:**
    ///
    /// It was `mistral-medium-2604`, pinned on the reasoning that an alias moving
    /// underneath a shipped build changes what the app does without a release,
    /// and that the fixtures were scored against one specific model. Both of
    /// those are still true. They were the wrong trade anyway.
    ///
    /// What the pin actually bought was this: the dated identifier stopped being
    /// one this account could call, every request began coming back 429, and
    /// because 429 means "rate limited" everywhere else in this file, the app
    /// told people mid-argument that a shared allowance was spent. It was not
    /// spent. Usage for the month was three requests. The app had been unable to
    /// reach a model at all since it shipped, and said the one thing guaranteed
    /// to stop anybody reporting it as a fault — because "wait a few minutes and
    /// try again" is what you say to somebody whose session you expect to work
    /// later.
    ///
    /// A moving alias risks the model changing under a release. A dated
    /// identifier risks the model *disappearing* under a release, silently, with
    /// no error anybody can act on. The second is what happened, and it is worse:
    /// a different model still answers.
    ///
    /// So: the alias. If it moves and the crux gets worse, the fixtures catch it
    /// and the fix is a release. If it moves and this app cannot reach it at all,
    /// that is Mistral discontinuing Medium entirely, which is a thing worth
    /// finding out about rather than being pinned away from.
    ///
    /// `scripts/check-mistral.sh` still confirms this string is served before a
    /// build goes anywhere — and would have caught this in August, had it been
    /// run again after the model was first chosen.
    public static let model = "mistral-medium-latest"

    /// **The company, not the model, and that is now a correctness fix rather
    /// than a style choice.**
    ///
    /// The app cannot honestly name the model it is using. On the hosted path —
    /// which is what almost everybody gets — the Worker sets `model` from its own
    /// environment and ignores whatever the phone asked for. That is deliberate
    /// and it is a security property: it is the line that stops a patched client
    /// spending this account on something expensive. But it means `model` above
    /// is a request, not a fact, and a screen that printed it was stating
    /// something it had no way to check.
    ///
    /// It was wrong in exactly that way: the card read "Mistral Medium 3.5" while
    /// the Worker was asking for an identifier the account could not call, and
    /// then while it was asking for Large. Both times the consent screen — the one
    /// screen in this app that cannot afford to be wrong — described a model
    /// nobody had run.
    ///
    /// "Mistral" is true whatever the Worker is configured with, which is the
    /// only claim of this kind the app is in a position to make.
    ///
    /// "Mistral Medium 3.5" was accurate the day it was written and false by the
    /// time anybody noticed. A version number in user-facing copy is a claim with
    /// an expiry date, and this app has now shipped two of them — "Gemini" on the
    /// product page for a month after the provider moved, and "3.5" on a consent
    /// screen pointed at a model the account could not call.
    ///
    /// The App Store description deliberately goes one step further and names
    /// only the company. In-app copy can afford to be specific because it ships
    /// with the build that makes it true; the listing cannot, because it is
    /// edited by hand in a different system and nothing fails when it drifts.
    public static let modelDisplayName = "Mistral"
    public static let keyURL = URL(string: "https://console.mistral.ai/api-keys")!

    /// Low but not zero: greedy decoding makes a model repeat itself across the
    /// two sides, and both people end up ticking the same sentence twice.
    public static let temperature: Float = 0.3
    /// Enough for the long one, which is the crux call with both positions and
    /// every second look in front of it.
    public static let maximumOutputTokens = 2000
    /// Generous, because the alternative is worse: a timeout means two people
    /// who waited half a minute are told it failed and asked to wait again.
    public static let timeout: TimeInterval = 90

    private let transport: any ModelTransport

    public init(transport: any ModelTransport) {
        self.transport = transport
    }

    /// The direct path, with somebody's own key. Kept as an initialiser of its
    /// own because it is what every test and every caller already says, and
    /// because "a cloud engine built from a key" is still the honest description
    /// of that arrangement.
    public init(apiKey: String, session: URLSession? = nil) {
        self.init(transport: MistralTransport(apiKey: apiKey, session: session))
    }

    public var canFlagAssumptions: Bool { true }

    // MARK: - DisputeEngine

    /// Both sides in one call, unlike the on-device engine.
    ///
    /// That engine splits this in two because one large structured generation
    /// takes minutes on a phone. Here the opposite is true: a model that can hold
    /// both positions at once writes a *better* list, because it can see when the
    /// two of them are making the same claim in two voices and decline to write
    /// it twice. The deduplication afterwards stays, as a net rather than a
    /// crutch.
    ///
    /// Asked twice where the first answer was unusable, then given up on — the
    /// same contract as every other engine, so the screens behave identically.
    public func breakDown(
        positionA: String,
        positionB: String,
        disputeTitle: String
    ) async throws -> [Claim] {
        var lastCount = 0
        for attempt in 1...2 {
            let generated: GeneratedClaimPair = try await respond(
                to: DisputePrompts.claimsForBothSides(
                    positionA: positionA,
                    positionB: positionB,
                    disputeTitle: disputeTitle
                ),
                step: "claims (both sides)",
                // Both positions are already in front of it and the job is to
                // restate them as six things either person could tick.
                thinking: .low
            )
            let combined = Claim.deduplicated(
                Claim.interleave(
                    generated.claims_a.map { Claim(text: $0.cleaned, origin: .a) },
                    generated.claims_b.map { Claim(text: $0.cleaned, origin: .b) }
                ),
                orEchoing: [positionA, positionB]
            )
            #if DEBUG
            PromptLog.shared.note(
                "Attempt \(attempt). Claims kept: \(generated.claims_a.count) from A + "
                    + "\(generated.claims_b.count) from B, \(combined.count) after "
                    + "near-duplicates and played-back sentences were dropped."
            )
            #endif
            if combined.count >= Claim.minimumUsableClaims { return combined }
            lastCount = combined.count
        }
        #if DEBUG
        PromptLog.shared.note(
            "Both attempts left \(lastCount) usable points, under the "
                + "\(Claim.minimumUsableClaims) the checklist needs."
        )
        #endif
        throw EngineError.notEnoughToWorkWith
    }

    public func findCrux(in dispute: Dispute) async throws -> Crux? {
        let generated: GeneratedCloudCrux = try await respond(
            to: DisputePrompts.findCrux(
                disputeTitle: dispute.title,
                positionA: dispute.positions[.a],
                positionB: dispute.positions[.b],
                agreed: DisputePrompts.list(dispute.sharedClaims),
                contested: DisputePrompts.list(dispute.contestedClaims),
                secondLooks: DisputePrompts.secondLooks(in: dispute)
            ),
            step: "crux",
            // The one call worth thinking about. Its prompt asks the model to
            // test its own answer against both people in turn and go deeper if
            // either would not move, which is the work being paid for here.
            thinking: .standard
        )
        let crux = Crux(
            question: generated.question.withoutEmDashes,
            positions: PartyPair(
                a: generated.position_a.withoutEmDashes.withoutAttribution,
                b: generated.position_b.withoutEmDashes.withoutAttribution
            ),
            test: (generated.test ?? "").withoutEmDashes,
            needsConversation: generated.needs_conversation ?? false
        )
        #if DEBUG
        if !crux.isUsable {
            PromptLog.shared.note("The app discarded that crux as unusable.")
        } else if !crux.isShared {
            PromptLog.shared.note(
                "That crux had the same stance on both sides, so it is one person's "
                    + "objection rather than a question both of them would move on."
            )
        } else if !crux.hasTest {
            PromptLog.shared.note(
                "That crux came back with no usable test — empty, too short, or one "
                    + "of the 'communicate more' non-answers the prompt rules out."
            )
        }
        #endif
        return crux.isUsable ? crux : nil
    }

    public func findAssumptions(
        positionA: String,
        positionB: String,
        disputeTitle: String
    ) async throws -> [AssumptionFlag] {
        let generated: GeneratedCloudAssumptions = try await respond(
            to: DisputePrompts.assumptions(
                positionA: positionA,
                positionB: positionB,
                disputeTitle: disputeTitle
            ),
            step: "assumptions (both people)",
            // Two short paragraphs in, at most four quotes and four sentences
            // out, and the prompt already says an empty answer is a normal one.
            thinking: .low
        )
        // Two each rather than two between them. The card between the turns holds
        // one person's flags at a time, and a model that found nothing in the
        // first paragraph must not thereby earn the second person a third.
        return flags(from: generated.assumptions_a, for: .a)
            + flags(from: generated.assumptions_b, for: .b)
    }

    private func flags(
        from generated: [GeneratedCloudAssumption]?,
        for party: Party
    ) -> [AssumptionFlag] {
        (generated ?? [])
            .prefix(2)
            .map {
                AssumptionFlag(
                    party: party,
                    quote: $0.quote,
                    assumption: $0.assumption.withoutEmDashes
                )
            }
            .filter(\.isUsable)
    }

    // MARK: - Request

    private func respond<Output: Decodable>(
        to prompt: String,
        step: String,
        thinking: Thinking
    ) async throws -> Output {
        #if DEBUG
        let startedAt = Date()
        var raw: String?
        #endif
        do {
            let text = try await transport.reply(
                to: prompt,
                system: DisputePrompts.systemPrompt,
                thinking: thinking
            )
            #if DEBUG
            raw = text
            #endif
            let decoded: Output = try Self.decodeJSON(from: text)
            #if DEBUG
            PromptLog.shared.record(
                step: step,
                engine: Self.modelDisplayName,
                system: DisputePrompts.systemPrompt,
                prompt: prompt,
                reply: raw,
                startedAt: startedAt
            )
            #endif
            return decoded
        } catch {
            #if DEBUG
            PromptLog.shared.record(
                step: step,
                engine: Self.modelDisplayName,
                system: DisputePrompts.systemPrompt,
                prompt: prompt,
                reply: raw,
                failure: String(describing: error),
                startedAt: startedAt
            )
            #endif
            throw error
        }
    }

    /// Pulls a JSON object out of whatever the model wrote around it.
    ///
    /// Necessary rather than defensive. The on-device engine has a grammar, so
    /// malformed output is unrepresentable; here the shape is asked for, and
    /// `response_format` is a strong request rather than a guarantee. Models wrap
    /// answers in a ```json fence, open with "Here is the JSON:", or append a
    /// paragraph explaining themselves — all three are a valid answer with rubbish
    /// either side of it.
    ///
    /// So: try the whole string, then try what sits between the first brace and
    /// the last. Nothing cleverer, because anything cleverer starts repairing
    /// genuinely broken JSON and silently changing what the model said.
    static func decodeJSON<Output: Decodable>(from text: String) throws -> Output {
        let decoder = JSONDecoder()
        let trimmed = text.trimmed

        if let data = trimmed.data(using: .utf8),
           let decoded = try? decoder.decode(Output.self, from: data) {
            return decoded
        }

        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start < end
        else {
            throw EngineError.malformedResponse("no JSON object in the reply")
        }

        let slice = String(trimmed[start...end])
        guard let data = slice.data(using: .utf8) else {
            throw EngineError.malformedResponse("the reply was not readable text")
        }
        do {
            return try decoder.decode(Output.self, from: data)
        } catch {
            throw EngineError.malformedResponse(error.localizedDescription)
        }
    }
}

// MARK: - Generated shapes

/// Optional where a grammar-constrained decoder's would not have to be, because
/// nothing is enforcing this shape. A model that omits `test` should produce a crux without a
/// test rather than a decode failure and a screen saying nothing was found.
private struct GeneratedCloudCrux: Decodable {
    let question: String
    let position_a: String
    let position_b: String
    let test: String?
    let needs_conversation: Bool?
}

private struct GeneratedClaimPair: Decodable {
    let claims_a: [String]
    let claims_b: [String]
}

private struct GeneratedCloudAssumption: Decodable {
    let quote: String
    let assumption: String
}

/// Both lists optional: a model that finds nothing in one paragraph tends to omit
/// its key rather than send an empty array, and that is a normal answer rather
/// than a decode failure that costs the other person their flags too.
private struct GeneratedCloudAssumptions: Decodable {
    let assumptions_a: [GeneratedCloudAssumption]?
    let assumptions_b: [GeneratedCloudAssumption]?
}

private extension String {
    var cleaned: String {
        withoutEmDashes.withoutLeadingConjunction.trimmed
    }
}
