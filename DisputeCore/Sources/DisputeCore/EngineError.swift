import Foundation

/// Why a request was turned down, when it was turned down rather than failed.
///
/// Three causes, and they are three because the way out of each is different.
/// This used to be a `String` with `"key"` compared against it in four places,
/// which was survivable while there were two of them and stopped being so the
/// moment the app could be refused for a reason that had nothing to do with a
/// key the person never typed.
public enum RefusalCause: String, Sendable, Equatable, CaseIterable {
    /// A key somebody pasted into Settings was rejected. Theirs to fix, and the
    /// screen can say exactly where.
    case key
    /// This copy of the app was not let through to the shared, no-cost path:
    /// App Check could not vouch for it, or the project's end of it is
    /// misconfigured. Nothing the two people in front of the phone did, and
    /// nothing they can do — so the screen must not send them off to check a
    /// key, because there isn't one.
    case app
    /// The provider's safety classifiers declined. Arguments get heated enough
    /// to trip these, so this is an expected state and the way out is a reword.
    case safety
}

/// Everything that can go wrong reaching the reasoning engine.
///
/// Deliberately small. The view layer maps every case onto a recoverable state
/// with a way forward: a person mid-argument should never hit a dead end, and
/// never see a raw error string.
///
/// `rateLimited` came back when hosted models did. It had been removed on the
/// grounds that an app which never opens a connection cannot be rate limited,
/// which was true right up until the app could be pointed at a provider — and a
/// spent free-tier quota is the single most likely failure on that path, not an
/// exotic one. It got likelier still when the quota stopped being one person's
/// and became the whole app's.
public enum EngineError: Error, Equatable, Sendable {
    /// Generation took too long, or was cancelled for taking too long.
    case timedOut
    /// The provider turned the request away for being one too many.
    ///
    /// Named for a quota, and that name was doing damage. Mistral's free tier
    /// caps three separate things — requests in flight at once, tokens per
    /// minute, tokens per month — and the first two belong to the *workspace*,
    /// which is to say to every copy of this app at once. Two arguments happening
    /// simultaneously anywhere in the world was enough to produce this, and it
    /// cleared a few seconds later. The screen meanwhile told two people the
    /// allowance was spent, which it almost never was.
    ///
    /// So this is now what is left *after* waiting: `Requests.retryDelay` and the
    /// Worker both sit out a throttle before anything reaches here. Getting this
    /// far means the throttle outlasted both, which is worth telling somebody
    /// about — and the message no longer claims to know which of the three caps
    /// it was, because it doesn't.
    ///
    /// Its own case because its answer is unlike every other failure here: not
    /// "try again" straight away, not "reword it", but "wait a little, or carry
    /// on by hand", which is a thing the app can tell them to do and a thing the
    /// app can actually do.
    case rateLimited(detail: String? = nil)
    /// The phone has no usable connection.
    ///
    /// Only reachable on the hosted path. It had been removed on the grounds that
    /// an app which never opens a connection cannot be offline — true right up
    /// until the app could be pointed at a hosted model, and now the most likely
    /// failure of the lot, because the situation this app is for is two people
    /// somewhere having an argument rather than two people at a desk.
    case offline
    /// The request was declined rather than attempted. See `RefusalCause`.
    case refused(cause: RefusalCause, explanation: String?)
    /// The answer was cut off before it finished — the context window filled.
    case truncated
    /// The provider is reachable and is not working. Nothing on the phone is
    /// wrong, and nothing anybody types will change it.
    ///
    /// Named for the on-device model for a long time after the on-device model
    /// was deleted, which meant the screen apologised for the phone when the
    /// fault was five hundred miles away.
    case serviceUnavailable(reason: String)
    /// The model replied with something that did not match the expected shape.
    case malformedResponse(String)
    /// Nothing in the two positions could be turned into points the two of them
    /// could answer.
    ///
    /// Not a malfunction, and deliberately not folded into `malformedResponse`:
    /// the model answered, in the right shape, and every point it produced was
    /// one of their own sentences handed back or written in their own voice. That
    /// happens when there is little in a position to draw a claim out of, and the
    /// only thing that fixes it is more from the people. `breakDown` has already
    /// asked twice by the time this is thrown.
    ///
    /// The one error in here whose answer is not "try that again".
    case notEnoughToWorkWith

    /// Whether offering the user a retry button makes sense.
    ///
    /// A malformed answer is worth retrying because these models are sampled:
    /// the same prompt genuinely can come back usable the second time.
    ///
    /// `notEnoughToWorkWith` is the exception that proves the rule. Measured over
    /// the two sessions that hit it, the same prompt came back unusable five times
    /// in six, so a retry button is a button that mostly wastes twenty seconds and
    /// then says the same thing. What that screen offers instead is the way out
    /// that works: go back and write a bit more.
    public var isRetryable: Bool {
        switch self {
        case .timedOut, .malformedResponse: true
        // Retryable, and more honestly so than when the quota was one person's.
        // A per-minute limit clears in a minute, which is a wait somebody will
        // sit through; a daily one does not, which is why the message says what
        // else to do rather than leaving the button to say it.
        case .rateLimited: true
        // Worth a button: people walk into signal, and the tunnel ends.
        case .offline: true
        // The app is up against something at the provider's end that a second
        // attempt sometimes clears, and there is nothing else to offer.
        case .serviceUnavailable: true
        // A rejected key is the one refusal whose cause is in the room. The
        // message sends them to Settings to fix it and `EngineSource` builds a
        // fresh engine on every call, so the corrected key is live the moment it
        // is saved — but without this there was no button to spend it on, and
        // the screen said "check it in Settings" above a single button offering
        // to give up on the AI for the rest of the session. That is the dead end
        // with a button on it that this whole screen exists to end.
        case let .refused(cause, _): cause == .key
        case .truncated, .notEnoughToWorkWith: false
        }
    }

    /// Whether the answer is to stop waiting on a model and carry on by hand.
    ///
    /// The failures with a genuinely different way out. By hand is a complete way
    /// to use this app — it is what everybody got before there was a model at all
    /// — so a session that cannot reach the model is not a session that has to
    /// end.
    ///
    /// This used to be `isFixedBySwitchingToOnDevice`, back when the fallback was
    /// a model on the phone. That model is gone; the fallback is the two of them.
    public var isFixedByCarryingOnByHand: Bool {
        switch self {
        case .rateLimited, .offline, .serviceUnavailable: true
        case let .refused(cause, _): cause != .safety
        default: false
        }
    }

    /// Whether the way out is for one of them to rewrite what they said.
    ///
    /// Separate from `isRetryable` because they are not opposites: a refusal is
    /// not retryable and is also fixed by rewording, and a timeout is retryable
    /// and is not.
    ///
    /// `truncated` is in here on the merits. It means the prompt and the answer
    /// together overran the context window, and the only part of that anyone can
    /// change is how much they wrote — so shorter positions are the fix, and
    /// running it again unchanged is not.
    public var isFixedByRewriting: Bool {
        switch self {
        // A rejected credential is a `refused` that no amount of rewording
        // touches, and offering "go back and reword" for one sends somebody to
        // rewrite a position that was never the problem.
        case let .refused(cause, _): cause == .safety
        case .notEnoughToWorkWith, .truncated: true
        case .timedOut, .malformedResponse, .serviceUnavailable, .rateLimited, .offline: false
        }
    }
}

extension EngineError {
    /// The technical half of a failure, on its own line, for the failures whose
    /// cause nobody in the room can see.
    ///
    /// This exists because of a week spent guessing. Every network failure in
    /// this app arrives as one of four reassuring sentences, and those sentences
    /// are right for the person holding the phone and useless for the person
    /// trying to fix it — a 401 from the Worker and a 401 from Mistral produce
    /// identical prose and have opposite fixes. The app shipped for six weeks
    /// unable to reach a model at all, saying "wait a few minutes and try again".
    ///
    /// Shown in release builds, not just DEBUG, and that is the point: the builds
    /// that fail in ways worth diagnosing are the ones on other people's phones,
    /// and `PromptLog` does not exist there. It is one short line in smaller
    /// type, after the sentence that tells somebody what to do — they can ignore
    /// it, and it makes every report actionable instead of "it says it didn't
    /// work".
    static func diagnostic(_ detail: String?) -> String {
        guard let detail, !detail.trimmed.isEmpty else { return "" }
        return "\n\n\(detail.prefix(200))"
    }
}

extension EngineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .timedOut:
            "That took too long."
        case let .rateLimited(detail):
            "\(CloudEngine.providerName) is busy, or the shared free limit is "
                + "spent. The app already waited and tried again. Give it a minute "
                + "and press try again, or carry on by hand: you write the points "
                + "yourselves and the app walks you through the rest."
                + Self.diagnostic(detail)
        case .offline:
            "This phone isn't online, and \(CloudEngine.providerName) needs a "
                + "connection. You can carry on by hand until it's back."
        case let .refused(cause, explanation):
            switch cause {
            case .key:
                "That API key wasn't accepted. Open Settings with the gear at the "
                    + "top, fix it or remove it to fall back on the app's own free "
                    + "connection, then try again. Nothing here is lost."
            case .app:
                "\(CloudEngine.providerName) wouldn't take a request from this copy "
                    + "of the app. That's at our end, not yours. Try again in a bit, "
                    + "or carry on by hand."
                    + Self.diagnostic(explanation)
            case .safety:
                explanation ?? "This request could not be processed."
            }
        case .truncated:
            "The answer was cut off before it finished."
        case let .serviceUnavailable(reason):
            "\(reason). Try again in a moment, or carry on by hand."
        case let .malformedResponse(detail):
            "Unexpected response: \(detail)"
        case .notEnoughToWorkWith:
            "There wasn't enough in what you both wrote to build a list from."
        }
    }
}
