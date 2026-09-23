import Foundation

/// How a session gets from what two people wrote to the crux underneath it.
///
/// Every phone can run the app. Not every phone can run a model, so the work the
/// model does — turning positions into a list of points, and naming the question
/// under the disagreement — has to be doable by hand as well. Both modes reach
/// the same screens and produce the same `Dispute`; they differ only in who does
/// that middle step.
///
/// Fixed for the life of a session. Someone who starts an argument by hand and
/// flips the toggle halfway through would otherwise land on a checklist built
/// from points nobody wrote.
public enum DisputeMode: String, Codable, Hashable, CaseIterable, Sendable {
    /// The two people write their own points and name their own crux. No model,
    /// no download, works on every phone.
    case manual
    /// A model on this phone does it. Never a server — see `DisputeEngine`.
    case assisted

    /// Whether this mode calls a model at all.
    public var usesEngine: Bool { self == .assisted }

    public var label: String {
        switch self {
        case .manual: "By hand"
        case .assisted: "With AI"
        }
    }
}
