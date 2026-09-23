import SwiftUI
import DisputeCore

/// The heart of the app: both people work through the same list and tick what
/// they agree with.
///
/// Whose claim is whose is deliberately hidden. Told that a point came from the
/// person you're arguing with, you answer the person rather than the point.
struct ChecklistView: View {
    let claims: [Claim]
    let party: Party
    let personName: String
    let onAnswer: (Claim, Bool) -> Void
    let onContinue: () -> Void

    private var answered: Int {
        claims.filter { $0.isAnswered(by: party) }.count
    }

    private var isComplete: Bool {
        !claims.isEmpty && answered == claims.count
    }

    /// Whether one more screen is coming before the phone changes hands.
    ///
    /// The button used to say "Done" and then produce another screen, which
    /// reads as the app having lost track of where you are. Someone who ticked
    /// everything really is done, and is told so.
    private var hasCrossedSomethingOut: Bool {
        claims.contains { $0.agreement[party] == false }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScreenHeader(
                        title: "\(personName), which of these do you agree with?",
                        subtitle: "Tick the ones you'd sign your name to.",
                        eyebrow: "\(answered) of \(claims.count)"
                    )

                    ProgressView(value: Double(answered), total: Double(max(claims.count, 1)))
                        .tint(Theme.color(for: party))

                    // Testers asked why they were being shown points that came
                    // from their own argument. Answering that up front is the
                    // difference between "this is rigged" and "this is a test".
                    ExplainerCard()

                    VStack(spacing: 10) {
                        ForEach(claims) { claim in
                            ClaimRow(
                                claim: claim,
                                party: party,
                                onAnswer: { onAnswer(claim, $0) }
                            )
                        }
                    }
                }
                .padding(Theme.screenPadding)
                .padding(.bottom, 12)
            }

        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(
                title: isComplete
                    ? (hasCrossedSomethingOut ? "Next" : "Done")
                    : "Tick or cross each one",
                isEnabled: isComplete,
                action: onContinue
            )
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .background(.bar)
        }
    }
}

/// Answers the two questions testers actually asked: where did these come
/// from, and why am I being asked about my own point.
///
/// One line each, and each one a whole answer. The long version of the middle
/// line explained the reasoning as well as the rule, and on a small screen that
/// pushed the first claim off the bottom — so the card that exists to stop
/// people bouncing was the reason they never saw anything to tick.
struct ExplainerCard: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("Both your answers, mixed together.", systemImage: "shuffle")
                Label("Whose is whose is hidden, so judge the point.", systemImage: "eye.slash")
                Label("You both get this exact list.", systemImage: "equal")
            }
            .font(.footnote)
            .foregroundStyle(Theme.ink.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One claim, with a yes and a no.
///
/// Two explicit buttons rather than a single toggle: an untouched checkbox and a
/// deliberate "no" look identical, and the difference matters — the app needs to
/// know they actually considered it.
struct ClaimRow: View {
    let claim: Claim
    let party: Party
    let onAnswer: (Bool) -> Void

    private var answer: Bool? { claim.agreement[party] }

    var body: some View {
        Card(tint: answer == nil ? nil : Theme.color(for: party)) {
            VStack(alignment: .leading, spacing: 14) {
                Text(claim.text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    ChoiceButton(
                        label: "Agree",
                        symbol: "checkmark",
                        isSelected: answer == true,
                        tint: Theme.agree
                    ) { onAnswer(true) }

                    ChoiceButton(
                        label: "Don't agree",
                        symbol: "xmark",
                        isSelected: answer == false,
                        tint: Theme.disagree
                    ) { onAnswer(false) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(claim.text)
        .accessibilityValue(
            answer == nil ? "Not answered" : (answer == true ? "Agree" : "Don't agree")
        )
    }
}

struct ChoiceButton: View {
    let label: String
    let symbol: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                Text(label)
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? tint : Color(.tertiarySystemFill))
            }
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    ChecklistView(
        claims: [
            Claim(text: "The higher salary would cover the cost of moving.", origin: .a),
            Claim(
                text: "A comparable offer is unlikely to come along soon.",
                origin: .b,
                agreement: PartyPair(a: true, b: nil)
            ),
        ],
        party: .a,
        personName: "Alex",
        onAnswer: { _, _ in },
        onContinue: {}
    )
}
