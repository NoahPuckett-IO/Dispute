import SwiftUI

/// Whether an animation should play, in one place.
///
/// ## What Reduce Motion actually asks for
///
/// Not silence. Apple's own guidance is that Reduce Motion means replacing
/// *movement* — things that slide, spring, scale or fly in from somewhere — with
/// a cross-fade. A view that fades from nothing to something is not what makes
/// somebody with a vestibular disorder feel ill; a view that travels fourteen
/// points up the screen on an underdamped spring is.
///
/// So this is not a switch that turns the app static. Every call site below was
/// looked at and sorted into one of three kinds:
///
/// - **Movement.** The gavel lifting and striking, the splash settling, the
///   handoff card arriving, the agreement bar filling, `Entrance` lifting each
///   paragraph into place. These are what the setting is for, and they are the
///   ones that stop.
/// - **Cross-fades.** `.transition(.opacity)` on the splash, the thinking
///   screen's reassurances, the phase changes in `SessionShell`. These stay:
///   they are already the thing Reduce Motion asks movement to be replaced
///   *with*, and removing them would make the app flicker rather than settle.
/// - **State that happens to be animated.** The primary button's colour easing
///   between enabled and disabled. No movement, no travel, 150ms. Stays.
///
/// ## Why this reads `UIAccessibility` rather than the environment
///
/// `@Environment(\.accessibilityReduceMotion)` is the idiomatic answer and it is
/// the wrong shape for this app. Most of the animations here are started from
/// inside `.onAppear` and `.task` closures — the gavel loop is in a `while` in a
/// detached task — and an environment value cannot be read from those without
/// threading a property through every view that owns one. Reading the same
/// underlying flag at the moment the animation would start gets the same answer
/// with none of that, and it picks up a change made in Settings mid-session,
/// which the environment would also do.
enum Motion {
    /// Whether the person has asked for less movement.
    static var isReduced: Bool { UIAccessibility.isReduceMotionEnabled }

    /// The animation, or `nil` — which `withAnimation` and `.animation` both
    /// read as "apply the change immediately".
    ///
    /// Returning `nil` rather than `.easeInOut(duration: 0)` on purpose: a
    /// zero-duration animation still schedules a transaction, and the states
    /// this guards are mostly a single `Bool` flipping from false to true. With
    /// `nil` the view simply starts in its settled position, which is exactly
    /// where somebody who asked for no movement wants to find it.
    static func animation(_ animation: Animation?) -> Animation? {
        isReduced ? nil : animation
    }

    /// `withAnimation`, honouring the setting.
    ///
    /// Named `run` rather than shadowing `withAnimation`, because a call that
    /// looks identical to the system one but behaves differently is the kind of
    /// thing that gets "fixed" back by somebody who did not know why it was
    /// there.
    static func run<Result>(
        _ animation: Animation?,
        _ body: () throws -> Result
    ) rethrows -> Result {
        try withAnimation(Self.animation(animation), body)
    }

    /// How far a thing may travel on its way in.
    ///
    /// Zero under Reduce Motion, so `Entrance` becomes the cross-fade the
    /// guidance asks for rather than a lift — same fade, same stagger, no
    /// journey.
    static func offset(_ points: CGFloat) -> CGFloat {
        isReduced ? 0 : points
    }
}
