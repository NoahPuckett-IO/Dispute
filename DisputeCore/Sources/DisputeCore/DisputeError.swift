import Foundation

/// Every way a dispute session can be driven into an illegal state.
///
/// These are programmer-facing and precise. User-facing copy is the view layer's
/// job — a person mid-argument should never see the word "illegal transition".
public enum DisputeError: Error, Equatable, Sendable {
    case illegalTransition(from: SessionStage, to: SessionStage)
    case notReadyToAdvance(stage: SessionStage, reason: String)
    case alreadyAtFinalStage
    case emptyStatement
}

extension DisputeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .illegalTransition(from, to):
            "Cannot move from \(from.rawValue) to \(to.rawValue)."
        case let .notReadyToAdvance(stage, reason):
            "Cannot leave \(stage.rawValue) yet: \(reason)"
        case .alreadyAtFinalStage:
            "The session is already at its final stage."
        case .emptyStatement:
            "A statement cannot be empty."
        }
    }
}
