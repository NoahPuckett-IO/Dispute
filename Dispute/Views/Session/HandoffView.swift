import SwiftUI
import DisputeCore

/// Shown while the phone changes hands — which happens exactly twice.
///
/// The one screen in the app with nothing to read and nothing to type. It gets
/// the full screen and a piece of motion, because its whole job is to be
/// noticed across a table by someone who isn't holding the phone.
struct HandoffView: View {
    let party: Party
    let personName: String
    let stage: SessionStage
    let onAccept: () -> Void

    @State private var hasArrived = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.color(for: party))
                    .scaleEffect(hasArrived ? 1 : 0.7)
                    .opacity(hasArrived ? 1 : 0)
                    .accessibilityHidden(true)

                Text("Pass the phone to \(personName)")
                    .font(.system(.title2, design: .serif, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)

                StatusPill(
                    text: explanation,
                    systemImage: icon,
                    tint: Theme.color(for: party)
                )
            }
            .offset(y: hasArrived ? 0 : 10)

            Spacer()

            VStack(spacing: 10) {
                PrimaryButton(title: "I'm \(personName)", action: onAccept)

                Label("Nothing is shown to the other person until you're both done.", systemImage: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Theme.screenPadding)
        .padding(.bottom, 8)
        .onAppear {
            Motion.run(.spring(response: 0.5, dampingFraction: 0.7)) { hasArrived = true }
        }
    }

    /// Says what they're about to be asked to do, before they agree to do it.
    private var explanation: String {
        switch stage {
        case .positions: "You'll say what you think"
        case .checklist: "You'll tick a list of points"
        case .setup, .crux, .summary: "Your turn"
        }
    }

    private var icon: String {
        switch stage {
        case .positions: "pencil.line"
        case .checklist: "checklist"
        case .setup, .crux, .summary: "arrow.right"
        }
    }
}

#Preview("Handoff") {
    HandoffView(party: .b, personName: "Sam", stage: .checklist) {}
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
}
