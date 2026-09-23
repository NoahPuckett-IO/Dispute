import SwiftUI
import DisputeCore

/// The one thing the two of you actually disagree about.
///
/// Shown to both people at once — no handoff. One question, never a list: a
/// screen with three questions on it is the argument they walked in with, and
/// picking the one that would move somebody is the whole job. Framed as a
/// question, never a verdict: the app has no opinion about who is right and must
/// not imply one through wording or ordering.
struct CruxView: View {
    let crux: Crux?
    let names: PartyPair<String>
    let rethinks: PartyPair<Rethink?>
    let sharedCount: Int
    let contestedCount: Int
    let onAppear: () -> Void
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    title: crux == nil ? "Nothing left splitting you" : "It comes down to this",
                    subtitle: crux == nil
                        ? "You answered every point on the list the same way."
                        : "Settle this one and one of you changes their mind. The rest, you already agree on.",
                    eyebrow: "Look at this together"
                )
                .entrance(0)

                if sharedCount > 0 {
                    AgreementMeter(shared: sharedCount, contested: contestedCount)
                        .entrance(1)
                }

                if let crux {
                    CruxCard(crux: crux, names: names)
                        .entrance(2)

                    // The thing to go and do. Above what each of them wrote,
                    // because it is the answer and those are the working.
                    if crux.hasTest {
                        NextStepCard(test: crux.test, needsConversation: crux.needsConversation)
                            .entrance(3)
                    }

                    SettleItCard(names: names, rethinks: rethinks)
                        .entrance(4)
                }
            }
            .padding(Theme.screenPadding)
            .padding(.bottom, 12)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Continue", isEnabled: true, action: onContinue)
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .background(.bar)
        }
        // Deliberately not `.task`: this work outlives the view, which is
        // swapped out the moment the request starts.
        .onAppear(perform: onAppear)
    }
}

/// The question, and where each of them lands on it.
///
/// Given the whole width and a serif line, because it is the one sentence the
/// app exists to produce. It used to be a `.headline` in a stack of identical
/// cards, which read as an item in a list rather than the answer.
struct CruxCard: View {
    let crux: Crux
    let names: PartyPair<String>
    var isCompact = false

    var body: some View {
        Card(tint: Theme.brand) {
            VStack(alignment: .leading, spacing: 16) {
                if !isCompact {
                    StatusPill(text: "The crux", systemImage: "scope")
                }

                // A question mark, because it is a question and the model
                // supplies one about half the time. Set in the largest serif on
                // the screen this app exists to reach, so a missing one is not a
                // small thing: "Do juniors say they learn less when mentoring
                // happens over video" reads as a heading rather than as the
                // thing the two of them are being asked to look at together.
                //
                // The same helper the write-up uses, and for the same reason —
                // see `String.ending(with:)`, which was added when the recap
                // welded this sentence onto the one after it.
                Text(crux.question.ending(with: "?"))
                    .font(.system(isCompact ? .title3 : .title2, design: .serif, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 12) {
                    ForEach(Party.allCases, id: \.self) { party in
                        StanceRow(
                            name: names[party],
                            stance: crux.positions[party],
                            tint: Theme.color(for: party)
                        )
                    }
                }

                if crux.needsConversation {
                    // Some cruxes aren't settled by being right. Saying so
                    // plainly is kinder than dressing it up as a factual dispute.
                    Label(
                        "This one isn't settled by either of you being right. Worth talking through instead.",
                        systemImage: "bubble.left.and.bubble.right"
                    )
                    .font(.caption)
                    .foregroundStyle(Theme.ink.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The one thing they can go and do about it.
///
/// This is the card that makes the difference between an app that describes a
/// disagreement and one that ends it. Everything before this point is diagnosis:
/// here is your common ground, here is the question underneath, here is where you
/// each land. All true, all interesting, and two people who walked in stuck
/// walked out stuck holding a better description of being stuck.
///
/// A crux is only useful if it can be settled, so the app asks the model for the
/// settling as part of the same answer and puts it here, in the house colour, in
/// a card that reads as an instruction rather than an observation. "Write down a
/// year of costs and compare the two numbers" is a thing that happens on a
/// Tuesday. "You disagree about whether the raise covers the move" is not.
///
/// Absent rather than empty when there is no usable test — see `Crux.hasTest`,
/// which drops the "communicate more" non-answers. A card telling two people who
/// have just done this exercise that they should talk more would be the single
/// most insulting screen in the app.
struct NextStepCard: View {
    let test: String
    var needsConversation = false

    var body: some View {
        Card(tint: Theme.brand) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    IconBadge(
                        systemImage: needsConversation ? "bubble.left.and.bubble.right.fill" : "checklist",
                        tint: Theme.brand,
                        size: 28
                    )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(needsConversation ? "What to talk through" : "How to settle it")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)

                        Text(needsConversation
                            ? "Not a fact to look up. This one needs the two of you."
                            : "Do this and one of you has an answer.")
                            .font(.caption)
                            .foregroundStyle(Theme.ink.opacity(0.7))
                    }
                }

                Text(test)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One person's answer to the crux, against their colour.
struct StanceRow: View {
    let name: String
    let stance: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)

                Text(stance.isEmpty ? "Not said" : stance)
                    .font(.callout)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// What each of them said, on their own turn, would change their mind.
///
/// The most useful thing in the app and the part neither of them expects to
/// see: two conditions written blind, side by side, that turn "we disagree" into
/// something with a result. Absent rather than empty when nobody wrote one.
struct SettleItCard: View {
    let names: PartyPair<String>
    let rethinks: PartyPair<Rethink?>

    private var written: [(party: Party, condition: String)] {
        Party.allCases.compactMap { party in
            guard let condition = rethinks[party]?.changeCondition,
                  !condition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return (party, condition)
        }
    }

    var body: some View {
        if !written.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("What would change your minds", systemImage: "target")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)

                        Text("You each wrote this before seeing the other.")
                            .font(.caption)
                            .foregroundStyle(Theme.ink.opacity(0.7))
                    }

                    ForEach(written, id: \.party) { entry in
                        StanceRow(
                            name: names[entry.party],
                            stance: entry.condition,
                            tint: Theme.color(for: entry.party)
                        )
                    }
                }
            }
        }
    }
}

#Preview("Crux") {
    CruxView(
        crux: Crux(
            question: "Does the raise actually cover what the move costs?",
            positions: PartyPair(a: "Yes, with room to spare", b: "No, not once childcare is counted"),
            test: "Get three nursery quotes near the new place, add them to the rent difference, and compare that total against the raise."
        ),
        names: PartyPair(a: "Alex", b: "Sam"),
        rethinks: PartyPair(
            a: Rethink(
                claimID: UUID(),
                bestCase: "Childcare here is already expensive, so the gap may be smaller than it looks.",
                changeCondition: "If the nursery quotes came back over £1,200 a month."
            ),
            b: Rethink(
                claimID: UUID(),
                bestCase: "The salary difference is real money and it compounds.",
                changeCondition: "If we wrote down every cost for a year and it still came out ahead."
            )
        ),
        sharedCount: 5,
        contestedCount: 2,
        onAppear: {},
        onContinue: {}
    )
    .background(Theme.background)
}

#Preview("Nothing contested") {
    CruxView(
        crux: nil,
        names: PartyPair(a: "Alex", b: "Sam"),
        rethinks: PartyPair(both: nil),
        sharedCount: 6,
        contestedCount: 0,
        onAppear: {},
        onContinue: {}
    )
    .background(Theme.background)
}
