import Foundation
import DisputeCore

/// Where a session gets an engine.
///
/// A closure rather than an engine, which is worth a note now that the reason has
/// changed. It was structural: the engine used to be a gigabyte of weights, and a
/// view model holding one for the life of a session meant `AIAvailability` could
/// drop its own reference and free precisely nothing. Asking per call was the
/// only way the memory ever came back.
///
/// That model is gone and `CloudEngine` is a struct around a URL, so nothing
/// would break if a session held one. This stays because the second reason
/// outlived the first: the key can be replaced or removed mid-session, and a
/// session holding an engine built from the old key goes on using it until the
/// app is relaunched. Asking per call means Settings takes effect immediately.
///
/// The two facts a session needs without touching the engine at all are stored
/// values: `description` is a line in Settings, and `canFlagAssumptions` decides
/// whether a toggle is drawn.
struct EngineSource {
    /// What to call this on the privacy line in Settings.
    let description: String
    /// Whether the toggle for assumption flagging should exist. Answered without
    /// loading, because Settings must open instantly.
    let canFlagAssumptions: Bool
    /// Hands back an engine, loading one if it isn't in memory. May be `nil` if
    /// the load fails — out of memory on an older phone is the realistic way —
    /// and callers must treat that as "this turn runs by hand", never as a crash.
    ///
    /// Main-actor isolated because the thing it asks is: `AIAvailability` owns
    /// whether a load is already running, and that question has exactly one right
    /// answer only if there is one place asking it.
    let provide: @MainActor () async -> (any DisputeEngine)?

    /// The real one, built from whatever key is stored at the moment of the call.
    @MainActor
    static func live(_ ai: AIAvailability) -> EngineSource {
        EngineSource(
            description: ai.engineDescription,
            canFlagAssumptions: true,
            provide: { ai.engine() }
        )
    }

    /// A fixed engine, for previews, seeded launches, and the forced-failure
    /// flags. Holding this one is fine: `MockDisputeEngine` is a few strings.
    static func fixed(_ engine: any DisputeEngine, description: String) -> EngineSource {
        EngineSource(
            description: description,
            canFlagAssumptions: engine.canFlagAssumptions,
            provide: { engine }
        )
    }
}
