import SwiftUI

/// Shown while the model is working.
///
/// Named steps rather than a bare spinner, because a round trip to the model takes
/// a few seconds and silence reads as a hang. So the screen keeps talking: after
/// ten seconds it asks them not to leave, and after half a minute it says
/// outright that it hasn't frozen.
///
/// Both `.thinking` paths in `SessionViewModel` are gated behind an engine, so
/// this view is on screen if and only if a request is in flight. That is what
/// the copy below is allowed to assume, and it is why the copy has to be careful:
/// whatever it says about where the work is happening is being said at the exact
/// moment two people's argument is on its way off the phone.
///
/// The reassurance is time-based rather than progress-based on purpose. There is
/// no honest progress figure to show — the model doesn't report one — and a fake
/// bar that stalls at 80% is worse than no bar.
struct ThinkingView: View {
    let message: String

    @State private var elapsed = 0

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            // Not tactile: this runs for as long as the request takes, which on
            // a slow connection is a good while. A phone buzzing every second
            // and a half for that long stops reading as feedback and starts
            // reading as a fault.
            SmashingGavel(size: 72)

            VStack(spacing: 8) {
                Text(message)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)

                if let reassurance {
                    Text(reassurance)
                        .font(.caption)
                        .foregroundStyle(Theme.ink.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .transition(.opacity)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.4), value: reassurance)
        .task {
            // Restarts whenever the view is rebuilt for a new stage, which is
            // what we want: each generation gets its own clock.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                elapsed += 1
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// What the wait says for itself once it has gone on long enough to worry
    /// somebody.
    ///
    /// This used to say "This runs on your phone, not a server. That's slower,
    /// but nothing is being uploaded." That was true of the downloaded model and
    /// became false the day the model moved to Gemini — and it was false *here*,
    /// on the one screen that is only ever shown while the upload is happening.
    /// It also contradicted the first screen, the privacy policy and the App
    /// Privacy questionnaire, all three of which say plainly that what the two of
    /// them wrote leaves the phone.
    ///
    /// What is worth saying instead is the thing somebody can act on: stay here.
    /// Leaving cancels the request in flight, and the step has to be done again.
    private var reassurance: String? {
        switch elapsed {
        case ..<10: nil
        case ..<30: "Keep the app open. Closing it now cancels this and you'd have to do the step again."
        default: "Still going, and it hasn't got stuck. Keep the app open a moment longer."
        }
    }
}

#Preview {
    ThinkingView(message: "Reading both sides…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
}
