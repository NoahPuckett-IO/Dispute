import SwiftUI
import DisputeCore

/// The points one person's view rests on, written by that person.
///
/// This is the job the model does in assisted mode, handed back to the people
/// arguing. It sits on the same screen as their position, and on the same turn,
/// so the phone still changes hands exactly twice — the alternative was a third
/// and fourth handoff, and the app already learned that more handoffs is what
/// makes people stop before they reach the crux.
struct PointsEntryView: View {
    let party: Party
    let otherName: String
    @Binding var points: [String]

    @FocusState private var focused: Int?

    private var filled: Int {
        points.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Now break it into points")
                    .font(.headline)

                Text("Write the things your view rests on, one plain sentence each. \(otherName) will see these mixed in with their own, without being told which are whose.")
                    .font(.footnote)
                    .opacity(0.75)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(0..<Dispute.maximumPointsEach, id: \.self) { index in
                pointField(at: index)
            }

            GuidanceCard()

            Text(
                filled >= Dispute.requiredPointsEach
                ? "\(filled) written. You can add another, or carry on."
                : "At least \(Dispute.requiredPointsEach) needed."
            )
            .font(.caption)
            .foregroundStyle(filled >= Dispute.requiredPointsEach ? Theme.agree : .secondary)
            .accessibilityAddTraits(.updatesFrequently)
        }
        .onAppear {
            if points.count < Dispute.maximumPointsEach {
                points += Array(
                    repeating: "",
                    count: Dispute.maximumPointsEach - points.count
                )
            }
        }
    }

    private func pointField(at index: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
                .font(.caption2.weight(.bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.color(for: party).opacity(0.18)))
                .padding(.top, 10)
                .accessibilityHidden(true)

            TextField(
                "",
                text: Binding(
                    get: { index < points.count ? points[index] : "" },
                    set: { newValue in
                        while points.count <= index { points.append("") }
                        points[index] = newValue
                    }
                ),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1...3)
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.color(for: party).opacity(0.3), lineWidth: 1)
            }
            .focused($focused, equals: index)
            .accessibilityLabel(
                index < Dispute.requiredPointsEach
                ? "Point \(index + 1), required"
                : "Point \(index + 1), optional"
            )
        }
    }
}

/// What makes a point usable, in the fewest words that will actually be read.
///
/// This is the one place the app asks someone to do the model's job, and a
/// person mid-argument writes "I'm right about the money" unless told what the
/// list is for. Two examples do more than a paragraph of instruction.
struct GuidanceCard: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("A good point is one thing that could be true or false")
                    .font(.caption.weight(.semibold))

                Label("\"The raise would cover what the move costs.\"", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(Theme.agree)

                Label("\"I'm right and they're not listening.\"", systemImage: "xmark")
                    .font(.caption)
                    .foregroundStyle(Theme.disagree)

                Text("Write it so they could agree or disagree with it without knowing it was yours.")
                    .font(.caption)
                    .opacity(0.75)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Points") {
    @Previewable @State var points = ["The commute is costing us more than the rent saves.", ""]
    return ScrollView {
        PointsEntryView(party: .a, otherName: "Sam", points: $points)
            .padding()
    }
}
