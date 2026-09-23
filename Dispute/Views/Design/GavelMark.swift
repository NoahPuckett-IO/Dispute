import SwiftUI

/// The mark. The same gavel as the app icon, drawn rather than shipped as an
/// asset so it scales and follows the palette.
///
/// Drawn rather than taken from SF Symbols because there is no gavel in SF
/// Symbols. `hammer.fill` was standing in, and a claw hammer is a different
/// object saying a different thing — this app is a referee, not a builder.
///
/// Every measurement is a fraction of `size`, so the mark is identical at 54pt
/// in the introduction and 96pt on the splash.
struct GavelMark: View {
    var size: CGFloat = 64
    /// Holds the gavel up, mid-swing. Only ever set true as the *start* of an
    /// animation that immediately sets it false — the default has to be the
    /// struck position, or every static use of the mark renders mid-swing.
    var isRaised = false

    /// Where the hand would be: the free end of the handle.
    ///
    /// This is the whole difference between a gavel and a metronome. Swinging
    /// about the centre of the shape pivots it roughly through the head, so the
    /// head barely travels and the handle waves about behind it — the motion of
    /// a needle, not a blow. Anchored at the grip, the head swings through a real
    /// arc and lands, which is what a gavel does.
    private static let grip = UnitPoint(x: 0.5, y: 0.76)

    /// Struck is the *resting* pose, and it is the icon's pose. So every static
    /// use of the mark is the app icon, and the animation is a departure from it
    /// and a return — rather than the icon being a position the mark only passes
    /// through.
    private static let struckAngle: Double = 34
    private static let raisedAngle: Double = 3

    private var angle: Double { isRaised ? Self.raisedAngle : Self.struckAngle }

    var body: some View {
        ZStack {
            gavel
                .rotationEffect(.degrees(angle), anchor: Self.grip)
                // Recentres the result. Swinging about the grip puts the head
                // up and to the right of it, so the shape as a whole sits high
                // and right in its own frame and would ride the edge of the
                // circle without this.
                .offset(x: -size * 0.17, y: -size * 0.01)
        }
        .frame(width: size, height: size)
        .background {
            Circle().fill(Theme.brand.opacity(0.14))
        }
        .accessibilityHidden(true)
    }

    /// Built upright — head horizontal on top, handle straight down — so the one
    /// angle above is the only thing that decides the pose. The proportions and
    /// the two tones are the icon's.
    private var gavel: some View {
        ZStack {
            // The handle first, so the head laps over the join rather than the
            // other way round. A visible seam at the neck is the thing that most
            // makes a drawn gavel look assembled.
            Capsule()
                .fill(Theme.brand.opacity(0.82))
                .frame(width: size * 0.088, height: size * 0.34)
                .offset(y: size * 0.09)

            // Centred on the handle. Sliding it along its own axis to put more
            // of the head on the striking side made the head hang out roughly
            // twice as far on one end as the other, and at this size that reads
            // as a mistake rather than as a gavel. The band below is what gives
            // the head its direction; the silhouette doesn't need to.
            RoundedRectangle(cornerRadius: size * 0.048, style: .continuous)
                .fill(Theme.brand)
                .frame(width: size * 0.38, height: size * 0.175)
                .offset(y: -size * 0.145)

            // The band across the head, centred on the handle rather than set
            // off toward the striking end. It reads as the collar where the two
            // pieces meet, which is a joint the eye already expects to find
            // there — anywhere else on a head this size and it just looks
            // misplaced, because there is nothing for it to line up with.
            //
            // White rather than a lighter rust: the band sits *on* the head, and
            // the head is already solid rust, so the same hue at lower opacity
            // composites to exactly the head colour and vanishes.
            RoundedRectangle(cornerRadius: size * 0.012, style: .continuous)
                .fill(.white.opacity(0.28))
                .frame(width: size * 0.062, height: size * 0.175)
                .offset(y: -size * 0.145)
        }
        .frame(width: size, height: size)
    }
}

/// The mark, striking over and over, for as long as something is loading.
///
/// One strike says "this app is about to start". A repeated one says "this app
/// is busy" — which is the honest thing to show while a request is out to
/// the model, which takes long enough that a still image reads as a hang.
///
/// The lift and the fall are deliberately not the same speed. A blow is a slow
/// wind-up and a fast landing; matched timings read as a pendulum, which is the
/// thing this stopped being when the pivot moved to the grip.
struct SmashingGavel: View {
    var size: CGFloat = 96
    /// Seconds to wait before the first strike, so the mark can arrive and
    /// settle rather than being mid-swing on the very first frame.
    var startDelay: Double = 0
    /// A tap at the moment of impact.
    ///
    /// On for the splash, which is three or four strikes and then gone. Off
    /// while a request is in flight: that runs as long as the model takes, and a
    /// phone buzzing every second and a half for that long stops reading as
    /// feedback and starts reading as a fault.
    var isTactile = false

    @State private var isRaised = false

    var body: some View {
        GavelMark(size: size, isRaised: isRaised)
            .task {
                // Reduce Motion stops the swing rather than un-animating it, and
                // the difference matters. `Motion.run` with no animation applies
                // the change instantly, which for a two-state loop means a gavel
                // that teleports between raised and struck every 780ms — more
                // jarring than the spring it replaced, not less. There is nothing
                // to soften here, so the loop simply never starts and the mark
                // stays at rest.
                //
                // Nothing is lost by it. The gavel is decoration on the splash
                // and a way of saying "still working" on the thinking screen, and
                // the thinking screen says that in words directly underneath.
                guard !Motion.isReduced else { return }

                if startDelay > 0 {
                    try? await Task.sleep(for: .seconds(startDelay))
                }
                while !Task.isCancelled {
                    // The lift is the warning that a strike is coming, and it
                    // lasts long enough to be a useful one: the engine is awake
                    // by the time the head is up.
                    if isTactile { Haptics.prepare(.heavy) }

                    Motion.run(.easeInOut(duration: 0.42)) { isRaised = true }
                    try? await Task.sleep(for: .milliseconds(420))
                    guard !Task.isCancelled else { return }

                    // Underdamped on purpose: the small rebound at the end is
                    // what sells it as hitting something.
                    Motion.run(.spring(response: 0.2, dampingFraction: 0.4)) { isRaised = false }

                    // The tap belongs at the landing, and this line used to sit
                    // directly under the one above — so it fired as the head was
                    // released rather than when it arrived, and the buzz was in
                    // the air while the gavel was still travelling. A spring of
                    // this response first reaches the struck angle about 90ms
                    // in, so that is where the blow is.
                    //
                    // The remaining 270ms keeps the cycle at the 780ms it has
                    // always been: the rhythm is unchanged, only the tap moved.
                    try? await Task.sleep(for: .milliseconds(90))
                    guard !Task.isCancelled else { return }
                    if isTactile { Haptics.tap(.heavy) }

                    try? await Task.sleep(for: .milliseconds(270))
                }
            }
    }
}

#Preview {
    VStack(spacing: 30) {
        GavelMark(size: 96)
        GavelMark(size: 54)
        GavelMark(size: 96, isRaised: true)
        SmashingGavel(size: 96)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.background)
}
