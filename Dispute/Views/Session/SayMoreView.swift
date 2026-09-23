import SwiftUI
import DisputeCore

/// Asks one of them to write a bit more, when there wasn't enough to build a
/// list out of.
///
/// This replaced a retry button. The failure it handles is not a malfunction: the
/// model answered, in the right shape, and every point it gave back was one of
/// their own sentences returned to them. Running the same prompt again mostly
/// produces the same thing — five times in six, measured — so a retry spends
/// twenty seconds to arrive back here, and by then the app has already tried
/// twice on its own.
///
/// So the screen has one action, and it is the one that works. The three rows are
/// the whole reason it exists: sending someone back to a text box they have
/// already filled in, with nothing but "that didn't work", asks them to guess
/// what the app wanted.
///
/// Tone rules, which this screen is the most likely in the app to break. Nobody
/// is told their argument was bad, or too short, or that they did it wrong: it
/// says what the app needs and what to add. It also never says which of them was
/// at fault, because the app does not know — the points come out of both
/// positions together, and guessing would put one of two people mid-argument in
/// the wrong.
struct SayMoreView: View {
    let firstName: String
    let secondName: String
    let onRewrite: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScreenHeader(
                        title: "Tell it a bit more",
                        subtitle: "There wasn't enough in what you wrote to draw out points you could both answer. Nothing is lost, and you don't have to start again.",
                        eyebrow: "Nothing you did wrong"
                    )
                    .entrance(0)

                    Card(tint: Theme.assist) {
                        VStack(alignment: .leading, spacing: 16) {
                            StatusPill(text: "What helps", systemImage: "text.append", tint: Theme.assist)

                            ForEach(Self.suggestions, id: \.title) { suggestion in
                                FeatureRow(
                                    systemImage: suggestion.icon,
                                    title: suggestion.title,
                                    detail: suggestion.detail,
                                    tint: Theme.assist
                                )
                            }
                        }
                    }
                    .entrance(1)
                }
                .padding(Theme.screenPadding)
                .padding(.bottom, 12)
            }

            // The note sits with the button rather than under the card. Left in
            // the scroll view it ended a short screen on one small grey line with
            // a hand's depth of empty paper under it, which reads as a screen that
            // failed to finish drawing rather than one with little to say.
            VStack(spacing: 12) {
                // Says who is about to be asked, in order, so the phone changing
                // hands is expected rather than a surprise.
                Label(
                    "\(firstName) goes first, then \(secondName), the same way as before.",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.caption)
                .foregroundStyle(Theme.ink.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

                PrimaryButton(title: "Add to what you said", action: onRewrite)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .background(.bar)
        }
        // A dead end is what this screen exists to not be, and the sound of one
        // is what people remember. `.warning` rather than `.error`: nothing broke.
        .onAppear { Haptics.notify(.warning) }
    }

    /// Written from the three things that were actually wrong in the sessions
    /// that hit this, rather than from general advice about arguing well.
    private static let suggestions: [(icon: String, title: String, detail: String)] = [
        (
            "arrow.branch",
            "Say why, not just what",
            "The points come out of your reasons. \u{201C}It's too expensive for what it is\u{201D} gives more to work with than \u{201C}I don't like it\u{201D}."
        ),
        (
            "person.2",
            "Name something they might argue with",
            "A point only earns its place if the other one of you could genuinely answer it the other way."
        ),
        (
            "text.alignleft",
            "Two or three sentences is plenty",
            "Not an essay. Enough that there's something in there besides how you feel about it."
        ),
    ]
}

#Preview("Say more") {
    SayMoreView(firstName: "Henry", secondName: "Noah", onRewrite: {})
        .background(Theme.background)
}
