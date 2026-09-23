import Foundation

/// Local, on-device storage for the session in progress.
///
/// A single JSON file rather than SwiftData. `Dispute` is a value type that is
/// already `Codable`, and SwiftData would mean turning the model layer into
/// reference types purely to satisfy the framework — a large change that buys
/// nothing here, since the app holds one session at a time and never syncs.
///
/// Storage is deliberately trivial to reason about, because the privacy claim
/// has to be simple enough to state in one sentence: it is one file on this
/// device, and `deleteEverything()` removes it.
public struct DisputeStore: Sendable {
    private let directory: URL
    private let fileName = "session.json"

    private var fileURL: URL { directory.appendingPathComponent(fileName) }

    /// Defaults to Application Support, which is excluded from iCloud backup
    /// only if configured — see `TODO`. Pass a directory in tests.
    public init(directory: URL? = nil) throws {
        if let directory {
            self.directory = directory
        } else {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.directory = base.appendingPathComponent("Dispute", isDirectory: true)
        }
        try FileManager.default.createDirectory(
            at: self.directory,
            withIntermediateDirectories: true
        )
    }

    /// Uses the default date strategy on purpose. ISO 8601 reads nicer but drops
    /// sub-second precision, so a saved session would not round-trip exactly.
    public func save(_ dispute: Dispute) throws {
        try JSONEncoder().encode(dispute).write(to: fileURL, options: .atomic)
    }

    /// The saved session, or `nil` if there isn't one.
    ///
    /// A file that can't be decoded is treated as absent rather than as an
    /// error: a corrupt session should start a fresh one, not brick the app.
    public func load() -> Dispute? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Dispute.self, from: data)
    }

    public var hasSavedSession: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Removes everything this app has stored. One call, no residue.
    public func deleteEverything() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
