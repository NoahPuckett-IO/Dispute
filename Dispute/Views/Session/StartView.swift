import SwiftUI
import DisputeCore

/// Naming the argument and the two people.
///
/// Names are asked for first because everything downstream reads better with
/// them — and because testers who were handed "Person A" and "Person B" assumed
/// the app had assigned them a side and stopped trusting it.
struct StartView: View {
    @Binding var title: String
    @Binding var firstName: String
    @Binding var secondName: String
    let canStart: Bool
    /// Shown as a badge. Which mode you're in changes what you'll be asked to do
    /// two screens from now, and finding that out then is a surprise.
    var mode: DisputeMode = .manual
    let onStart: () -> Void

    @FocusState private var focused: Field?

    private enum Field: Hashable { case title, first, second }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    ScreenHeader(
                        title: "What's the argument?",
                        subtitle: "You'll both explain properly in a moment.",
                        eyebrow: "Dispute"
                    )

                    ModeBadge(mode: mode)
                        .padding(.top, 20)
                }

                LabelledField(
                    label: "The argument, in one line",
                    example: "e.g. whether to take the job",
                    text: $title
                )
                .focused($focused, equals: .title)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Who's arguing?")
                        .font(.headline)

                    LabelledField(
                        label: "Goes first",
                        example: "whoever's holding the phone",
                        text: $firstName,
                        accent: Theme.color(for: .a)
                    )
                    .focused($focused, equals: .first)

                    LabelledField(
                        label: "Goes second",
                        example: "the other person",
                        text: $secondName,
                        accent: Theme.color(for: .b)
                    )
                    .focused($focused, equals: .second)

                    // Testers read the order as the app picking a favourite.
                    Label("Order changes nothing. You both do the same steps.", systemImage: "arrow.left.arrow.right")
                        .font(.caption)
                        .foregroundStyle(Theme.ink.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HowItWorks()
            }
            .padding(Theme.screenPadding)
            .padding(.bottom, 12)
        }
        // Deliberately no `onAppear { focused = .title }`. Raising the keyboard
        // on arrival covered the bottom half of the first screen anyone sees,
        // including "How it works" and — on a 12 mini — most of the reason to
        // trust the app at all. Two people deciding whether to use this need to
        // read it before they type into it, and the first field is one tap away.
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Start", isEnabled: canStart, action: onStart)
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .background(.bar)
        }
        .toolbar {
            // The fields grow vertically, so Return inserts a newline rather
            // than dismissing. Without this there is no way to put the keyboard
            // away except starting.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
    }
}

/// Which mode this session is running in, in two words.
///
/// Not a warning and not an upsell — by the time this is on screen the choice is
/// made and the session is fixed. It is here so that "write three points of your
/// own" two screens later is something you were told about rather than something
/// that happens to you.
struct ModeBadge: View {
    let mode: DisputeMode

    var body: some View {
        switch mode {
        case .manual:
            StatusPill(text: "By hand", systemImage: "pencil.line", tint: Theme.accent)
        case .assisted:
            StatusPill(text: "AI helping", systemImage: "cpu", tint: Theme.assist)
        }
    }
}

/// A labelled text field.
///
/// The label sits above the box and the example sits below it — neither is grey
/// text inside the field. Placeholder text reads as content that's already
/// there, and testers kept trying to delete it.
struct LabelledField: View {
    let label: String
    let example: String
    @Binding var text: String
    var accent: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.semibold))

            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...3)
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder((accent ?? .secondary).opacity(0.35), lineWidth: 1)
                }

            Text(example)
                .font(.caption)
                .foregroundStyle(Theme.ink.opacity(0.6))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityHint(example)
    }
}

#Preview("Start") {
    @Previewable @State var title = ""
    @Previewable @State var first = ""
    @Previewable @State var second = ""
    return StartView(
        title: $title,
        firstName: $first,
        secondName: $second,
        canStart: false
    ) {}
}
