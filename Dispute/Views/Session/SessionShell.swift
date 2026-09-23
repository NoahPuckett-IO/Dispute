import SwiftUI
import DisputeCore

/// Routes the session to the right screen for the current stage and phase.
struct SessionShell: View {
    @Bindable var model: SessionViewModel

    var body: some View {
        Group {
            switch model.phase {
            case let .handoff(party):
                HandoffView(
                    party: party,
                    personName: model.name(for: party),
                    stage: model.stage
                ) {
                    model.acceptPhone()
                }
                .transition(.opacity)

            case let .thinking(message):
                ThinkingView(message: message)

            // Its own screen rather than a variant of `FailureView`, because it
            // is not a failure report: there is nothing to tell them about what
            // went wrong, only something to ask them for. See `SayMoreView`.
            //
            // Unconditional, deliberately. Guarding this on
            // `canGoBackToPositions` reads as the careful thing to do and is the
            // opposite: this error is only ever thrown while building the
            // checklist, so the guard can never be false, and if it ever were the
            // fallback below would draw a screen with no buttons on it at all.
            case .failed(.notEnoughToWorkWith):
                SayMoreView(
                    firstName: model.name(for: .a),
                    secondName: model.name(for: .b),
                    onRewrite: model.goBackAndEdit
                )

            case let .failed(error):
                FailureView(
                    error: error,
                    canGoBack: model.canGoBackToPositions,
                    onRetry: model.retry,
                    onGoBackAndEdit: model.goBackAndEdit,
                    // Withheld in a session that is already by hand, where it
                    // would be a button offering to do what is happening.
                    canCarryOnByHand: model.mode != .manual,
                    onCarryOnByHand: model.carryOnByHand
                )

            case let .assumptions(flags):
                AssumptionsView(
                    flags: flags,
                    onContinue: model.dismissAssumptions,
                    onGoBackAndEdit: model.goBackAndEdit
                )

            case .working:
                stageView
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.phase)
    }

    @ViewBuilder
    private var stageView: some View {
        switch model.stage {
        case .setup:
            StartView(
                title: $model.title,
                firstName: model.nameBinding(for: .a),
                secondName: model.nameBinding(for: .b),
                canStart: model.canAdvance,
                mode: model.mode,
                onStart: model.finishTurn
            )

        case .positions:
            PositionEntryView(
                disputeTitle: model.title,
                party: model.currentParty,
                personName: model.name(for: model.currentParty),
                otherName: model.name(for: model.currentParty.opponent),
                text: Binding(
                    get: { model.position(for: model.currentParty) },
                    set: { model.setPosition($0, for: model.currentParty) }
                ),
                // In manual mode this turn collects the points too, so the phone
                // still changes hands exactly twice.
                points: model.mode == .manual
                    ? Binding(
                        get: { model.currentPoints },
                        set: { model.setPoints($0, for: model.currentParty) }
                    )
                    : nil,
                toImproveOn: model.positionToImproveOn(for: model.currentParty),
                onContinue: model.finishTurn
            )
            // Without this, SwiftUI reuses the editor across the handoff and the
            // second person sees the first person's text.
            .id(model.currentParty)

        case .checklist:
            // Two screens, one turn. The list, then the point they crossed out
            // — the phone changes hands the same number of times either way.
            switch model.checklistStep {
            case .ticking:
                ChecklistView(
                    claims: model.claims,
                    party: model.currentParty,
                    personName: model.name(for: model.currentParty),
                    onAnswer: { model.answer($0, agrees: $1) },
                    onContinue: model.finishTicking
                )
                .onAppear(perform: model.prepareClaimsIfNeeded)
                .id(model.currentParty)

            case .secondLook:
                SecondLookView(
                    personName: model.name(for: model.currentParty),
                    party: model.currentParty,
                    rejected: model.rejectedByCurrentParty,
                    existing: model.rethinkForCurrentParty,
                    onBack: model.returnToTicking,
                    onDone: model.saveSecondLook
                )
                .id(model.currentParty)
            }

        case .crux:
            if model.mode == .manual {
                ManualCruxView(
                    contested: model.contestedClaims,
                    crux: model.crux,
                    names: model.names,
                    rethinks: model.dispute.rethinks,
                    sharedCount: model.sharedCount,
                    draft: model.draftCrux,
                    onSet: model.setCrux,
                    onContinue: model.finishTurn
                )
            } else {
                CruxView(
                    crux: model.crux,
                    names: model.names,
                    rethinks: model.dispute.rethinks,
                    sharedCount: model.sharedCount,
                    contestedCount: model.contestedCount,
                    onAppear: model.findCruxIfNeeded,
                    onContinue: model.finishTurn
                )
            }

        case .summary:
            SummaryView(
                dispute: model.dispute,
                transcript: model.transcript,
                onStartAnother: model.startOver
            )
            .onAppear(perform: model.composeRecapIfNeeded)
        }
    }
}

#Preview("Shell") {
    SessionShell(model: SessionViewModel())
}
