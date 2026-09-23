import SwiftUI
import DisputeCore

/// The last screen: what the whole argument came to, written down.
///
/// It takes the whole session as one value rather than a dozen parameters,
/// because that is honestly what it is a view of — every part of this screen is
/// drawn from something the two of them did, and a version of it that took only
/// the pieces it happens to show today would need editing every time the record
/// gained a line.
///
/// This is the screen people photograph. It is laid out to be read top to
/// bottom by two people holding one phone between them: the paragraph first,
/// then the numbers, then the question, then the way out of it.
struct SummaryView: View {
    let dispute: Dispute
    let transcript: String
    let onStartAnother: () -> Void

    private var names: PartyPair<String> {
        PartyPair(a: dispute.name(for: .a), b: dispute.name(for: .b))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    title: "Where you landed",
                    subtitle: dispute.title.isEmpty ? "The whole thing, written down." : dispute.title,
                    eyebrow: "Done"
                )
                .entrance(0)

                RecapCard(recap: dispute.recap)
                    .entrance(1)

                AgreementMeter(
                    shared: dispute.sharedClaims.count,
                    contested: dispute.contestedClaims.count
                )
                .entrance(2)

                if let crux = dispute.crux {
                    SectionLabel("The question that's left")
                    CruxCard(crux: crux, names: names, isCompact: true)
                        .entrance(3)

                    // The one actionable thing on the screen people photograph.
                    if crux.hasTest {
                        NextStepCard(test: crux.test, needsConversation: crux.needsConversation)
                            .entrance(4)
                    }

                    SettleItCard(names: names, rethinks: dispute.rethinks)
                        .entrance(5)
                }

                if !dispute.sharedClaims.isEmpty {
                    CommonGroundList(claims: dispute.sharedClaims)
                        .entrance(5)
                }

                if !dispute.positions.allSatisfy(\.isEmpty) {
                    WhatYouSaidList(positions: dispute.positions, names: names)
                        .entrance(6)
                }
            }
            .padding(Theme.screenPadding)
            .padding(.bottom, 12)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                PrimaryButton(title: "Start another", action: onStartAnother)

                // Sharing the record is the one thing people asked for that the
                // app can give away for nothing: it is text they wrote, on a
                // phone that never sent it anywhere, and where it goes next is
                // their decision rather than the app's.
                ShareLink(item: transcript) {
                    Label("Keep a copy", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.brand)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.brand.opacity(0.45), lineWidth: 1)
                        }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .background(.bar)
        }
    }
}

/// The write-up, in the app's serif, treated like something written rather than
/// something computed.
///
/// There is no loading state here any more, because there is nothing to load. The
/// paragraph is composed on the phone the instant this screen appears — see
/// `ArgumentRecap`. It used to be handed to a model to say again more fluently,
/// which meant a spinner, three animating placeholder bars, and a wait of up to a
/// minute on the one screen where two people have finished arguing and want to
/// put the phone down.
private struct RecapCard: View {
    let recap: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    IconBadge(systemImage: "text.alignleft", size: 26)
                    Text("What happened here")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)

                    Spacer(minLength: 0)
                }

                Text(recap)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A quiet heading between blocks, so the screen reads as sections rather than
/// a stack of cards.
private struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(Theme.ink.opacity(0.5))
            .padding(.top, 4)
    }
}

/// Everything they turned out to agree on, folded away.
///
/// Collapsed by default and counted in the label: on a list of eight it is the
/// longest thing on the screen, and it is reassurance rather than news — the
/// meter above has already said how much of it there is.
private struct CommonGroundList: View {
    let claims: [Claim]

    @State private var isExpanded = false

    var body: some View {
        Card(tint: Theme.agree) {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(claims) { claim in
                        Label {
                            Text(claim.text)
                                .font(.footnote)
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.agree)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
            } label: {
                Text("What you both signed up to (\(claims.count))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.ink.opacity(0.5))
        }
    }
}

/// What each of them said at the start, kept so the record is complete.
private struct WhatYouSaidList: View {
    let positions: PartyPair<String>
    let names: PartyPair<String>

    @State private var isExpanded = false

    var body: some View {
        Card {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Party.allCases, id: \.self) { party in
                        StanceRow(
                            name: names[party],
                            stance: positions[party],
                            tint: Theme.color(for: party)
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
            } label: {
                Text("Where you both started")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.ink.opacity(0.5))
        }
    }
}

#Preview("Summary") {
    var dispute = Dispute(
        title: "Whether to take the job",
        stage: .summary,
        names: PartyPair(a: "Alex", b: "Sam"),
        positions: PartyPair(
            a: "The money is life-changing and offers like this don't come round twice.",
            b: "We'd be moving the kids mid-year for a job neither of us knows will last."
        ),
        claims: [
            Claim(text: "The raise would cover what the move costs.", origin: .a,
                  agreement: PartyPair(a: true, b: false)),
            Claim(text: "A comparable offer is unlikely to come along soon.", origin: .a,
                  agreement: PartyPair(a: true, b: true)),
            Claim(text: "Changing schools mid-year would set the kids back.", origin: .b,
                  agreement: PartyPair(a: false, b: true)),
            Claim(text: "Neither of us wants to decide this in a hurry.", origin: .b,
                  agreement: PartyPair(a: true, b: true)),
        ],
        rethinks: PartyPair(
            a: Rethink(
                claimID: UUID(),
                bestCase: "Kids do notice a move, and this one lands mid-year.",
                changeCondition: "If the new school couldn't take them until September."
            ),
            b: Rethink(
                claimID: UUID(),
                bestCase: "The salary difference is real and it compounds.",
                changeCondition: "If we wrote down a year of costs and it still came out ahead."
            )
        ),
        crux: Crux(
            question: "Does the raise actually cover what the move costs?",
            positions: PartyPair(a: "Yes, with room to spare", b: "No, not once childcare is counted")
        )
    )
    dispute.recap = ArgumentRecap.compose(from: dispute)

    return SummaryView(
        dispute: dispute,
        transcript: ArgumentRecap.transcript(of: dispute),
        onStartAnother: {}
    )
    .background(Theme.background)
}
