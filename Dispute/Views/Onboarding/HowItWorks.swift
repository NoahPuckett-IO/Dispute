import SwiftUI

/// The whole app in three steps, drawn as a route rather than written as a list.
///
/// This replaced three sentences of prose. The prose was accurate and nobody
/// read it: it is shown to two people who are mid-argument and want to get on
/// with it, so the version that works is the one that can be taken in without
/// being read. Numbers, icons and a line down the side do that; a paragraph
/// explaining that the points are shuffled does not.
///
/// Anything that only becomes true later — that the list is shuffled, that
/// neither of you sees the other's answers — is said on the screen where it
/// happens, where it is a reassurance rather than a rule to memorise.
struct HowItWorks: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    StepRow(
                        number: index + 1,
                        step: step,
                        isLast: index == Self.steps.count - 1
                    )
                }

                Divider()
                    .padding(.top, 4)
                    .padding(.bottom, 10)

                Label("One phone, passed over twice. It never takes a side.", systemImage: "hand.raised")
                    .font(.caption)
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    fileprivate struct Step {
        let icon: String
        let title: String
        let detail: String
    }

    fileprivate static let steps = [
        Step(icon: "pencil.line", title: "Say your side", detail: "Each of you, on your own."),
        Step(icon: "checklist", title: "Tick the same list", detail: "You won't know whose point is whose."),
        // Still three steps, though the middle one now has a second screen in
        // it. Taking the other side is exactly the kind of thing this file's
        // rule covers: it is said on the screen where it happens, where it is
        // an instruction rather than a warning about how long this will take.
        // What is worth promising up front is what comes out — one question,
        // and something to keep.
        Step(icon: "key.fill", title: "See the crux", detail: "One question, and the whole thing written up."),
    ]
}

/// One step, and the line connecting it to the next.
private struct StepRow: View {
    let number: Int
    let step: HowItWorks.Step
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // The rail. The circle marks the step and the line carries the eye
            // to the next one, which is the whole reason this isn't a bulleted
            // list — it reads as a sequence you move along.
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Theme.brand)
                        .frame(width: 24, height: 24)

                    Text("\(number)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                }

                if !isLast {
                    Rectangle()
                        .fill(Theme.brand.opacity(0.25))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: step.icon)
                        .font(.caption)
                        .foregroundStyle(Theme.brand)

                    Text(step.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }

                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 16)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(step.title). \(step.detail)")
    }
}

#Preview {
    HowItWorks()
        .padding()
        .background(Theme.background)
}
