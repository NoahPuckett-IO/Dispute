import Foundation

/// The stages of a dispute.
///
/// Kept deliberately short. An earlier design had five working stages and eight
/// handoffs; people found it exhausting and stopped before reaching the crux.
/// Two stages are taken in turns, so the phone changes hands exactly twice.
///
/// Stages only move forward. Re-litigating one mid-session is the exact
/// behaviour the app exists to interrupt.
public enum SessionStage: String, Codable, Hashable, CaseIterable, Sendable {
    /// Naming the dispute.
    case setup
    /// Each person says what they think.
    case positions
    /// Both work through the same list of claims, ticking what they agree with.
    case checklist
    /// Where the ticks differ.
    case crux
    /// Wrap-up.
    case summary

    public var order: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    public var next: SessionStage? {
        let index = order + 1
        return index < Self.allCases.count ? Self.allCases[index] : nil
    }

    public var isTerminal: Bool { next == nil }

    /// Whether this stage is taken in turns, one person at a time.
    public var isPerParty: Bool {
        switch self {
        case .positions, .checklist: true
        case .setup, .crux, .summary: false
        }
    }

    /// Short label for the progress indicator.
    public var shortTitle: String {
        switch self {
        case .setup: "Start"
        case .positions: "Sides"
        case .checklist: "Points"
        case .crux: "Crux"
        case .summary: "Done"
        }
    }

    /// Stages a person actually sees a step for, used by the progress indicator.
    public static var visibleSteps: [SessionStage] {
        [.positions, .checklist, .crux]
    }
}

extension SessionStage: Comparable {
    public static func < (lhs: SessionStage, rhs: SessionStage) -> Bool {
        lhs.order < rhs.order
    }
}
