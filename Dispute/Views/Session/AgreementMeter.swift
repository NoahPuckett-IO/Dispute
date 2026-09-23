import SwiftUI

/// How much of the list the two of them ticked the same way, drawn to scale.
///
/// The quiet win of the whole app. Most people are surprised how much of the
/// list they both answered identically, and seeing the bar is what lands that —
/// a sentence saying "you agreed on 5 of 7" gets read as a score, whereas the
/// bar gets read as a picture of the argument, most of which is green.
///
/// The bar fills on appear rather than being drawn at its final width. It is the
/// one number in the app worth a moment of drama, and the growth is what makes
/// the eye follow it to the end.
struct AgreementMeter: View {
    let shared: Int
    let contested: Int
    /// The crux screen has a headline above it already; the summary doesn't.
    var showsHeadline = true

    private var total: Int { shared + contested }

    @State private var hasFilled = false

    var body: some View {
        Card(tint: Theme.agree) {
            VStack(alignment: .leading, spacing: 12) {
                if showsHeadline {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Theme.agree)
                            .accessibilityHidden(true)

                        Text("You agreed on \(shared) of \(total)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                    }
                }

                bar

                HStack(spacing: 16) {
                    key(colour: Theme.agree, count: shared, label: "agreed")
                    key(colour: Theme.accent, count: contested, label: contested == 1 ? "still splits you" : "still split you")
                    Spacer(minLength: 0)
                }
            }
        }
        .onAppear {
            Motion.run(.spring(response: 0.75, dampingFraction: 0.85).delay(0.15)) {
                hasFilled = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You agreed on \(shared) of \(total) points. \(contested) still split you.")
    }

    private var bar: some View {
        GeometryReader { geometry in
            let fraction = total == 0 ? 0 : Double(shared) / Double(total)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.accent.opacity(0.35))

                Capsule()
                    .fill(Theme.agree)
                    .frame(width: geometry.size.width * (hasFilled ? fraction : 0))
            }
        }
        .frame(height: 10)
    }

    private func key(colour: Color, count: Int, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(colour)
                .frame(width: 8, height: 8)

            // The number carries the message, so it gets the weight.
            Text("\(count)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.ink)
                + Text(" \(label)")
                .font(.caption)
                .foregroundStyle(Theme.ink.opacity(0.7))
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        AgreementMeter(shared: 5, contested: 2)
        AgreementMeter(shared: 1, contested: 5, showsHeadline: false)
    }
    .padding()
    .frame(maxHeight: .infinity)
    .background(Theme.background)
}
