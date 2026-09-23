import SwiftUI

/// The first thing you see. Brief, and only on a cold start.
///
/// It exists because building the session asks the system what this phone can
/// do, which is not instant — the choice is between a blank screen for that
/// moment or this. The gavel keeps coming down for as long as that takes.
///
/// Repeated rather than a single strike, because how long this screen lasts is
/// not fixed: on a phone that has to read a gigabyte off disk it is there a
/// while, and a mark that struck once and then sat still looked like the app
/// had stopped rather than like it was working.
struct SplashView: View {
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 18) {
                // Starts after the mark has arrived and settled, so the first
                // blow reads as deliberate rather than as a shudder on the way in.
                SmashingGavel(size: 96, startDelay: 0.36, isTactile: true)
                    .scaleEffect(hasAppeared ? 1 : 0.85)
                    .opacity(hasAppeared ? 1 : 0)

                VStack(spacing: 6) {
                    Text("Dispute")
                        .font(.system(.largeTitle, design: .serif, weight: .bold))
                        .foregroundStyle(Theme.ink)

                    Text("Find what you actually disagree on")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink.opacity(0.7))
                }
                .opacity(hasAppeared ? 1 : 0)
            }
        }
        .onAppear {
            Motion.run(.spring(response: 0.6, dampingFraction: 0.7)) {
                hasAppeared = true
            }
        }
    }
}

#Preview("Splash") { SplashView() }
