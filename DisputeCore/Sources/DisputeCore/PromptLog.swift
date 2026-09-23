#if DEBUG
import Foundation

/// Every prompt the app sent a model this session, and what came back verbatim.
///
/// Debug builds only. The whole file is inside `#if DEBUG`, and nothing records
/// anything until `isEnabled` is set, so a release build has neither the code
/// nor a switch that could turn it on.
///
/// It exists because the one part of this app that unit tests cannot cover is
/// whether the model did the thing it was asked to do. Every test can pass, the
/// engine can return a well-formed `Crux`, and the question in it can still be a
/// restatement of the topic rather than the crux. The only way to see that is to
/// read the prompt and the raw answer side by side, which is what this collects.
///
/// It holds the prompts, which contain everything the two people wrote. That is
/// the reason it never ships, and the reason nothing here writes to disk on its
/// own — where a transcript goes is a decision someone makes on the debug screen.
public final class PromptLog: @unchecked Sendable {
    /// One call to a model.
    public struct Call: Sendable {
        /// Which job this was: "claims (person A)", "crux", "recap".
        public let step: String
        public let engine: String
        public let system: String
        public let prompt: String
        /// Exactly what the model produced, before any parsing.
        public let reply: String?
        /// Why it produced nothing usable, if it didn't.
        public let failure: String?
        public let at: Date
        public let seconds: TimeInterval
    }

    /// What the app then did with an answer, which is often where the fault is.
    ///
    /// A model can return a perfectly good crux that the app throws away, and a
    /// log of prompts alone makes that look like the model's mistake.
    public struct Note: Sendable {
        public let text: String
        public let at: Date
    }

    public enum Entry: Sendable {
        case call(Call)
        case note(Note)

        public var at: Date {
            switch self {
            case let .call(call): call.at
            case let .note(note): note.at
            }
        }
    }

    public static let shared = PromptLog()

    private let lock = NSLock()
    private var storage: [Entry] = []
    private var enabled = false

    private init() {}

    /// Off until the app turns it on, which only debug code does.
    public var isEnabled: Bool {
        get { lock.withLock { enabled } }
        set { lock.withLock { enabled = newValue } }
    }

    public var entries: [Entry] {
        lock.withLock { storage }
    }

    public func clear() {
        lock.withLock { storage.removeAll() }
    }

    /// Records one call. `startedAt` rather than a duration so callers only have
    /// to remember `Date()` on the way in.
    public func record(
        step: String,
        engine: String,
        system: String,
        prompt: String,
        reply: String? = nil,
        failure: String? = nil,
        startedAt: Date
    ) {
        lock.withLock {
            guard enabled else { return }
            storage.append(
                .call(
                    Call(
                        step: step,
                        engine: engine,
                        system: system,
                        prompt: prompt,
                        reply: reply,
                        failure: failure,
                        at: startedAt,
                        seconds: Date().timeIntervalSince(startedAt)
                    )
                )
            )
        }
    }

    public func note(_ text: String) {
        lock.withLock {
            guard enabled else { return }
            storage.append(.note(Note(text: text, at: Date())))
        }
    }
}
#endif
