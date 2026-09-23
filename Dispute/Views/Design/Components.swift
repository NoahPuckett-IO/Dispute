import SwiftUI
import DisputeCore

/// The pieces every screen is built from. If a shape appears twice in the app it
/// belongs here, so the two copies can't drift.

// MARK: - Containers

/// A soft card. Used for anything quoted, listed, or grouped.
struct Card<Content: View>: View {
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .fill(tint?.opacity(0.12) ?? Theme.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .strokeBorder(tint?.opacity(0.35) ?? Theme.hairline.opacity(0.6), lineWidth: 1)
            }
    }
}

/// A small caps label on a tinted pill. Says what kind of thing you're looking
/// at in two words, so the sentence underneath doesn't have to.
struct StatusPill: View {
    let text: String
    var systemImage: String?
    var tint: Color = Theme.brand

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
            }
            Text(text.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.8)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            Capsule().fill(tint.opacity(0.14))
        }
        .accessibilityLabel(text)
    }
}

/// An icon in a tinted circle. The app's unit of "showing" rather than telling.
struct IconBadge: View {
    let systemImage: String
    var tint: Color = Theme.brand
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background { Circle().fill(tint.opacity(0.15)) }
            .accessibilityHidden(true)
    }
}

/// Icon, one bold line, one quiet line. Used wherever a benefit or a step is
/// being shown rather than described in a paragraph.
struct FeatureRow: View {
    let systemImage: String
    let title: String
    var detail: String?
    var tint: Color = Theme.brand

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(systemImage: systemImage, tint: tint, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.ink.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Actions

/// The main action on every screen, so the button never moves or changes shape.
struct PrimaryButton: View {
    let title: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap(.medium)
            action()
        } label: {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(isEnabled ? Color.white : Theme.ink.opacity(0.4))
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isEnabled ? Theme.brand : Theme.hairline.opacity(0.45))
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .animation(.easeInOut(duration: 0.15), value: isEnabled)
    }
}

/// A secondary action — present but not competing with the primary one.
struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    var tint: Color = Theme.brand
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(0.45), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

/// One claim offered as a choice, with a chevron.
///
/// The same shape on the two screens that ask someone to pick a point out of a
/// list — the second look at the end of a checklist turn, and naming the crux by
/// hand. They are one screen apart in the flow, and the two copies had already
/// drifted: one drew itself on warm paper and the other on the system's grey,
/// which on this palette reads as a different app.
struct PickRow: View {
    let text: String
    var hint: String?
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(text)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .opacity(0.4)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .fill(Theme.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .strokeBorder(Theme.hairline.opacity(0.6), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint ?? "")
    }
}

// MARK: - Structure

/// Screen title and one line of explanation. Same shape everywhere, so people
/// learn where to look.
struct ScreenHeader: View {
    let title: String
    let subtitle: String
    var eyebrow: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.brand)
            }

            Text(title)
                .font(.system(.title, design: .serif, weight: .bold))
                .foregroundStyle(Theme.ink)

            // Not `.secondary`: testers called the guidance text faint and
            // skipped it.
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.ink.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The steps across the top. People kept asking how much longer this takes;
/// showing the shape of the process answers that without a word.
struct StageProgress: View {
    let stage: SessionStage

    var body: some View {
        HStack(spacing: 7) {
            ForEach(SessionStage.visibleSteps, id: \.self) { step in
                let isDone = stage > step
                let isCurrent = stage == step

                HStack(spacing: 6) {
                    Circle()
                        .fill(isDone || isCurrent ? Theme.brand : Theme.hairline)
                        .frame(width: isCurrent ? 7 : 5, height: isCurrent ? 7 : 5)

                    if isCurrent {
                        Text(step.shortTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
        }
        .animation(Motion.animation(.easeInOut(duration: 0.25)), value: stage)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(stage.shortTitle)")
    }
}

// MARK: - Motion

/// Fades and lifts its content in, a beat after the thing above it.
///
/// Used on the screens that are mostly reading — the introduction and the crux —
/// where everything arriving at once is a wall, and arriving in order makes the
/// eye start at the top. Deliberately absent from the working screens: nobody
/// mid-argument wants to wait for a text field to animate in.
struct Entrance: ViewModifier {
    let index: Int
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            // Reduce Motion keeps the fade and drops the travel, which is the
            // swap Apple's guidance actually asks for. The stagger stays either
            // way: arriving in order is what makes the eye start at the top, and
            // it is a question of timing rather than movement.
            .offset(y: hasAppeared ? 0 : Motion.offset(14))
            .onAppear {
                Motion.run(
                    .spring(response: 0.5, dampingFraction: 0.85)
                    .delay(Double(index) * 0.07)
                ) { hasAppeared = true }
            }
    }
}

extension View {
    /// `index` is the position in the stagger, not a z-order.
    func entrance(_ index: Int) -> some View {
        modifier(Entrance(index: index))
    }
}
