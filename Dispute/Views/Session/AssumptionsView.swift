import SwiftUI
import DisputeCore

/// Shown once between the two turns: what each side is standing on without
/// having said so.
///
/// The screen this replaced flagged facts that looked wrong, and it was the
/// hardest thing in the app to get right because it never could be — telling two
/// arguing people that one of them has a fact wrong is the app taking a side,
/// however carefully it is worded. Naming an assumption is not: it says nothing
/// about whether the assumption holds, and the people in the room are the only
/// ones who can say.
///
/// The wording rules survive from that screen intact, because they were right
/// even when the feature wasn't. Nothing here says who wrote what — the cards are
/// not labelled by person, and they are shown together — nothing says anyone is
/// wrong, and nothing blocks. "Carry on" is always there and always the larger
/// button.
struct AssumptionsView: View {
    let flags: [AssumptionFlag]
    let onContinue: () -> Void
    let onGoBackAndEdit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScreenHeader(
                        title: flags.count == 1
                            ? "One thing you're both taking as given"
                            : "What you're both taking as given",
                        subtitle: "Not a correction, and not a comment on who's right. These are the steps neither of you said out loud.",
                        eyebrow: "Before you carry on"
                    )

                    ForEach(flags) { flag in
                        Card(tint: Theme.caution) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "quote.opening")
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(Theme.caution)
                                        .accessibilityHidden(true)

                                    Text("“\(flag.quote)”")
                                        .font(.callout.italic())
                                        .foregroundStyle(Theme.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Text(flag.assumption)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.ink.opacity(0.8))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    Text("An assumption isn't a mistake. It's just something one of you is treating as settled that the other might not be, which is usually where an argument gets stuck.")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.screenPadding)
                .padding(.bottom, 12)
            }

            VStack(spacing: 10) {
                PrimaryButton(title: "Carry on", action: onContinue)
                SecondaryButton(title: "Go back and add to it", systemImage: "arrow.uturn.backward", action: onGoBackAndEdit)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .background(.bar)
        }
    }
}

/// A recoverable failure. Never a dead end — there is always a way forward, and
/// after a safety refusal that way is backwards.
struct FailureView: View {
    let error: EngineError
    let canGoBack: Bool
    let onRetry: () -> Void
    let onGoBackAndEdit: () -> Void
    /// False in a session that is already by hand, which is the only case where
    /// this screen has nothing to offer. A flag and a closure rather than an
    /// optional closure: this is built inside a `switch` in a `ViewBuilder`, and
    /// an optional function type in there is the sort of expression the type
    /// checker gives up on with a diagnostic about filing a bug report.
    var canCarryOnByHand = false
    var onCarryOnByHand: () -> Void = {}

    /// The safety filter specifically, and not every refusal.
    ///
    /// This used to match any `refused`, which was harmless while the only other
    /// one was a rejected key that nobody hit twice. It stopped being harmless
    /// when a credential could be turned down without anybody having typed one:
    /// the screen would say "it won't work with that wording" and send two people
    /// off to rewrite a position that was never the problem.
    private var isRefusal: Bool {
        if case .refused(.safety, _) = error { return true }
        return false
    }

    /// A rejected key, which is the only failure this screen shows that somebody
    /// standing here can go and fix in about fifteen seconds.
    ///
    /// It gets its own branch below because the ordering rule that governs every
    /// other failure is argued from the opposite premise: "carry on without the
    /// AI" goes on top for the failures *nobody in this room can do anything
    /// about*. This is not one of those. Settings is two taps away behind the
    /// gear, `EngineSource` builds a fresh engine per call so a corrected key is
    /// live the moment it is saved, and putting the giving-up button on top would
    /// be offering to abandon the AI for the rest of the session to somebody who
    /// mistyped a character.
    private var isRejectedKey: Bool {
        if case .refused(.key, _) = error { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // The one place in the app that draws itself in the alert
                    // colour, which is the whole reason that colour exists. Every
                    // other screen is the house verdigris or the brass
                    // complement, so arriving here is visibly different before a
                    // word of it is read — and nothing that is merely *emphasis*
                    // can be mistaken for this.
                    StatusPill(
                        text: isRefusal ? "Nothing you did wrong" : "Didn't work",
                        systemImage: "exclamationmark.triangle.fill",
                        tint: Theme.alert
                    )

                    ScreenHeader(
                        title: isRefusal ? "It won't work with that wording" : "That didn't work",
                        subtitle: message
                    )
                }
                .padding(Theme.screenPadding)
            }

            VStack(spacing: 10) {
                // Whichever action is actually likely to work goes on top, in the
                // shape people press without reading. For a refusal that is going
                // back: the same request will be declined the same way.
                if isRejectedKey {
                    PrimaryButton(title: "Try again", action: onRetry)
                    if canCarryOnByHand {
                        SecondaryButton(
                            title: "Carry on without the AI",
                            systemImage: "hand.raised",
                            action: onCarryOnByHand
                        )
                    }
                } else if error.isFixedByRewriting, canGoBack {
                    PrimaryButton(title: "Go back and reword", action: onGoBackAndEdit)
                    if error.isRetryable {
                        SecondaryButton(title: "Try again", systemImage: "arrow.clockwise", action: onRetry)
                    }
                } else if canCarryOnByHand, error.isFixedByCarryingOnByHand {
                    // Above "try again", and it is worth saying why, because the
                    // other order is the obvious one. These are the failures
                    // nobody in this room can do anything about: the shared quota
                    // is spent, the phone has no signal, the provider is down. Retrying
                    // is a coin flip that can stay landing the same way for hours,
                    // and the two people holding the phone are arguing now.
                    PrimaryButton(title: "Carry on without the AI", action: onCarryOnByHand)
                    if error.isRetryable {
                        SecondaryButton(title: "Try again", systemImage: "arrow.clockwise", action: onRetry)
                    }
                } else {
                    if error.isRetryable {
                        PrimaryButton(title: "Try again", action: onRetry)
                    }
                    if canGoBack {
                        // The whole point of this screen. Before it existed, a
                        // refusal meant throwing the session away and starting
                        // over.
                        SecondaryButton(title: "Go back and reword", systemImage: "arrow.uturn.backward", action: onGoBackAndEdit)
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .background(.bar)
        }
    }

    private var message: String {
        if isRefusal {
            "\(CloudEngine.providerName) declined to work with something in what one of you wrote. It's fussy about certain topics, and it isn't judging the argument. Rewording that bit usually clears it, and you don't have to start over."
        } else {
            error.errorDescription ?? "Something went wrong."
        }
    }
}

#Preview("Assumptions") {
    AssumptionsView(
        flags: [
            AssumptionFlag(
                party: .a,
                quote: "offers like this don't come round twice",
                assumption: "This treats the current offer as the last one, with no allowance for a similar one later."
            ),
            AssumptionFlag(
                party: .b,
                quote: "moving the kids mid-year",
                assumption: "This takes it as given that the move would have to happen before the school year ends."
            ),
        ],
        onContinue: {},
        onGoBackAndEdit: {}
    )
}

#Preview("Refusal") {
    FailureView(
        error: .refused(cause: .safety, explanation: nil),
        canGoBack: true,
        onRetry: {},
        onGoBackAndEdit: {}
    )
}
