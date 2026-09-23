import SwiftUI
import DisputeCore

/// The end of your checklist turn: take one point you crossed out and argue for
/// it.
///
/// The list on its own only ever produced *where* two people split. This screen
/// is where the app finds out why, and it asks the one person who can answer —
/// each of them does this alone, still holding the phone, before it changes
/// hands, so neither is performing for the other.
///
/// Two questions, in this order deliberately. Making the case for something you
/// just rejected is the one that changes how the rest of the session feels;
/// saying what would change your mind is the one the crux is built out of. The
/// second is much easier after the first.
///
/// Nothing on this screen names the exercise. The words for it all sound like
/// being told you are arguing badly.
struct SecondLookView: View {
    let personName: String
    let party: Party
    /// The points this person crossed out. Never their whole list.
    let rejected: [Claim]
    let existing: Rethink?
    let onBack: () -> Void
    let onDone: (Rethink) -> Void

    @State private var claimID: UUID?
    @State private var bestCase = ""
    @State private var changeCondition = ""
    @FocusState private var focus: Field?

    private enum Field { case bestCase, changeCondition }

    private var chosen: Claim? {
        rejected.first { $0.id == claimID }
    }

    private var isComplete: Bool {
        chosen != nil
            && !bestCase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !changeCondition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // The title holds still across both halves of this screen. It
                // moved once, and a heading that changes under you while you
                // are choosing reads as having got something wrong.
                ScreenHeader(
                    title: "Now take the other side",
                    subtitle: chosen == nil
                        ? "\(personName), pick the point you crossed out that you'd least like to be wrong about."
                        : "You don't have to believe it. You have to be able to say it.",
                    eyebrow: "Still your turn"
                )

                if let chosen {
                    ChosenPointCard(text: chosen.text, party: party) {
                        Motion.run(.easeInOut(duration: 0.2)) {
                            claimID = nil
                            focus = nil
                        }
                    }

                    answerField(
                        number: 1,
                        title: "Why might someone believe this?",
                        help: "Make the best case you can for it, not the worst.",
                        placeholder: "Because…",
                        text: $bestCase,
                        field: .bestCase
                    )

                    answerField(
                        number: 2,
                        title: "What would change your mind?",
                        help: "Something that could actually be shown, or that could happen. This is what the app builds the last screen from.",
                        placeholder: "If…",
                        text: $changeCondition,
                        field: .changeCondition
                    )
                } else {
                    WhyThisCard()

                    VStack(spacing: 10) {
                        ForEach(rejected) { claim in
                            PickRow(
                                text: claim.text,
                                hint: "Choose this point to argue for"
                            ) {
                                Motion.run(.easeInOut(duration: 0.2)) {
                                    claimID = claim.id
                                }
                                focus = .bestCase
                            }
                        }
                    }
                }
            }
            .padding(Theme.screenPadding)
            .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if chosen != nil {
                    // Not "Done". The keyboard's own dismiss button says that,
                    // and with a hardware keyboard the two sit one above the
                    // other saying the same word for different things.
                    PrimaryButton(
                        title: isComplete ? "Finish my turn" : "Answer both to carry on",
                        isEnabled: isComplete
                    ) {
                        guard let chosen else { return }
                        onDone(
                            Rethink(
                                claimID: chosen.id,
                                bestCase: bestCase,
                                changeCondition: changeCondition
                            )
                        )
                    }
                }

                // Gone while the keyboard is up. Above a keyboard the bar has
                // about a third of the screen to sit in, and two stacked
                // controls in it pushed the second question off the bottom —
                // which is the question the rest of the app is built out of.
                if focus == nil {
                    Button("Back to the list", action: onBack)
                        .font(.footnote)
                        .foregroundStyle(Theme.ink.opacity(0.65))
                }
            }
            // Without this the bar is only as wide as its widest child, and on
            // the picking step — where the only child is a footnote-sized text
            // button — that draws the material as a small white box floating in
            // the middle of the screen.
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .background(.bar)
        }
        .toolbar {
            // "Next" rather than only "Done": the second field sits below the
            // fold with a keyboard up, so the way to reach it has to be on the
            // keyboard itself. Moving focus scrolls it into view for free.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                if focus == .bestCase {
                    Button("Next") { focus = .changeCondition }
                } else {
                    Button("Done") { focus = nil }
                }
            }
        }
        .onAppear {
            // Reopened after going back to the list: keep what they wrote.
            guard let existing, rejected.contains(where: { $0.id == existing.claimID }) else { return }
            claimID = existing.claimID
            bestCase = existing.bestCase
            changeCondition = existing.changeCondition
        }
    }

    private func answerField(
        number: Int,
        title: String,
        help: String,
        placeholder: String,
        text: Binding<String>,
        field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number)")
                    .font(.caption2.weight(.bold))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Theme.color(for: party).opacity(0.18)))
                    .accessibilityHidden(true)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField(placeholder, text: text, axis: .vertical)
                .font(.body)
                .lineLimit(2...5)
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                        .strokeBorder(Theme.color(for: party).opacity(0.35), lineWidth: 1)
                }
                .focused($focus, equals: field)
                .accessibilityLabel(title)

            Text(help)
                .font(.caption)
                .foregroundStyle(Theme.ink.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The point they picked, with a way back out of it.
private struct ChosenPointCard: View {
    let text: String
    let party: Party
    let onChange: () -> Void

    var body: some View {
        Card(tint: Theme.color(for: party)) {
            VStack(alignment: .leading, spacing: 10) {
                Label("You crossed this out", systemImage: "xmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.color(for: party))

                Text(text)
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)

                Button("Pick a different one", action: onChange)
                    .font(.footnote)
            }
        }
    }
}

/// Why anyone would do this, in the two lines someone mid-argument will read.
private struct WhyThisCard: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("The other side gets made properly, once.", systemImage: "arrow.2.squarepath")
                Label("Then you say what would settle it.", systemImage: "target")
                Label("They still won't be told whose point it was.", systemImage: "eye.slash")
            }
            .font(.footnote)
            .foregroundStyle(Theme.ink.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Pick one") {
    SecondLookView(
        personName: "Alex",
        party: .a,
        rejected: [
            Claim(text: "Mentoring junior people works worse over video.", origin: .b),
            Claim(text: "Culture erodes without regular in-person contact.", origin: .b),
        ],
        existing: nil,
        onBack: {},
        onDone: { _ in }
    )
    .background(Theme.background)
}
