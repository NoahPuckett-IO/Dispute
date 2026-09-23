import SwiftUI
import DisputeCore

/// Shown once, before the first argument.
///
/// Two people who are already annoyed will not read a screen of prose to find
/// out how an app works. Everything here earns its place or is cut: the mark,
/// the three steps as a picture, the AI offer, and the answer to it. Anything
/// only true in one mode belongs on the screen where that mode is happening.
///
/// **This screen is where the AI is agreed to, which is why it has two buttons
/// rather than one.** It used to have a Start button and the AI already on, and
/// that is the thing Apple's guideline 5.1.2(i) stopped allowing in November
/// 2025: what two people write about their argument leaves the phone, and it may
/// not go there on the strength of a screen they walked past. Both answers are
/// one tap, neither is dressed as the wrong one, and `AIAvailability` sends
/// nothing until one of them is given.
///
/// Neither button is ever blocked or waits on anything.
struct IntroductionView: View {
    @Bindable var ai: AIAvailability
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    masthead
                        .entrance(0)

                    HowItWorks()
                        .entrance(1)

                    AICard(ai: ai)
                        .entrance(2)

                    Label("No account, no sign-in. One phone between the two of you.", systemImage: "iphone")
                        .font(.caption)
                        .foregroundStyle(Theme.ink.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                        .entrance(3)
                }
                .padding(Theme.screenPadding)
                .padding(.bottom, 12)
            }
            // Starts at the top, explicitly.
            //
            // On a short screen this content overflows, and a `ScrollView` with a
            // bottom `safeAreaInset` was resolving its initial offset partway
            // down — far enough on a 12 mini to slice the mark in half against
            // the top of the sheet. The first thing anyone sees of this app
            // cannot be a cropped logo.
            .defaultScrollAnchor(.top)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    PrimaryButton(title: "Use the AI") {
                        ai.choose(useAI: true)
                        onDone()
                    }
                    // The card above says all of this at length. VoiceOver reads
                    // a button by its label alone when the focus lands on it, so
                    // the part that has to be true at the moment of consent is
                    // repeated here rather than left three swipes up the screen.
                    .accessibilityLabel("Use the AI")
                    .accessibilityHint(
                        "Sends what you both write to \(CloudEngine.recipients) to be read by "
                            + "the model. It is free and is not used to train anything. "
                            + "You can change this later in Settings."
                    )

                    SecondaryButton(title: "Do it by hand") {
                        ai.choose(useAI: false)
                        onDone()
                    }
                    .accessibilityLabel("Do it by hand")
                    .accessibilityHint(
                        "Nothing leaves this phone. You write your own points and name "
                            + "the crux together."
                    )

                    // Names the provider inside the pinned footer, which is the
                    // only part of this screen guaranteed to be on screen at the
                    // moment either button can be pressed.
                    //
                    // The long version lives on the card above and used to be the
                    // only version. That was fine until it was looked at with
                    // Larger Text turned up: at the accessibility sizes the card
                    // scrolls, and the sentence naming the company was below the
                    // fold while "Use the AI" was perfectly tappable. A consent
                    // screen whose disclosure is reachable only by scrolling is
                    // one that most people consent without reading, and at AX5 it
                    // was not reachable by accident at all.
                    Text("The AI sends what you both write to \(CloudEngine.recipients). "
                        + "Either way, you can change it in Settings.")
                        .font(.caption2)
                        .foregroundStyle(Theme.ink.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 10)
                .padding(.bottom, 20)
                .background(.bar)
            }
        }
    }

    private var masthead: some View {
        HStack(alignment: .center, spacing: 14) {
            GavelMark(size: 54)

            VStack(alignment: .leading, spacing: 2) {
                Text("Dispute")
                    .font(.system(.largeTitle, design: .serif, weight: .bold))
                    .foregroundStyle(Theme.ink)

                Text("A referee for arguments going in circles.")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Introduction") {
    IntroductionView(ai: AIAvailability()) {}
}
