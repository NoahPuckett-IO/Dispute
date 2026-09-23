import SwiftUI
import DisputeCore

/// The two of them name the crux themselves.
///
/// Shown to both at once, like the assisted crux screen — no handoff, because
/// this is the part they are meant to do together. It is the hardest thing the
/// app asks of anyone, so it never starts from a blank field: they pick the
/// point they split on that feels closest to the root, and the app turns it into
/// a question with both their answers already filled in. Every word stays
/// editable.
///
/// One question, not a list. The screen used to offer "Add another" and people
/// took it — and an argument with four cruxes named is an argument nobody has
/// narrowed. Choosing is the work this screen exists to make them do.
struct ManualCruxView: View {
    let contested: [Claim]
    let crux: Crux?
    let names: PartyPair<String>
    let rethinks: PartyPair<Rethink?>
    let sharedCount: Int
    let draft: (Claim) -> Crux
    let onSet: (Crux?) -> Void
    let onContinue: () -> Void

    @State private var editing: Crux?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    title: crux == nil ? "What's the real question?" : "It comes down to this",
                    subtitle: crux == nil
                        ? "The one question where, if you agreed on the answer, one of you would change your mind."
                        : "Settle this one and one of you would change your mind.",
                    eyebrow: "Look at this together"
                )

                if sharedCount > 0 {
                    AgreementMeter(shared: sharedCount, contested: contested.count)
                }

                if let crux {
                    CruxCard(crux: crux, names: names)

                    HStack(spacing: 16) {
                        Button("Edit") {
                            Haptics.tap()
                            editing = crux
                        }
                        Button("Pick a different point", role: .destructive) {
                            Haptics.tap(.medium)
                            onSet(nil)
                        }
                    }
                    .font(.footnote)
                    .padding(.leading, 4)

                    SettleItCard(names: names, rethinks: rethinks)
                } else if contested.isEmpty {
                    NothingContestedCard()
                } else {
                    PickAPointCard(contested: contested) { claim in
                        editing = draft(claim)
                    }
                }
            }
            .padding(Theme.screenPadding)
            .padding(.bottom, 12)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(
                title: "Continue",
                isEnabled: crux != nil || contested.isEmpty,
                action: onContinue
            )
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .background(.bar)
        }
        .sheet(item: $editing) { draft in
            CruxEditor(crux: draft, names: names) { edited in
                onSet(edited)
                editing = nil
            } onCancel: {
                editing = nil
            }
        }
    }
}

/// The points they answered differently, as starting places.
private struct PickAPointCard: View {
    let contested: [Claim]
    let onPick: (Claim) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You split on \(contested.count == 1 ? "this" : "these"). Which one is closest to the root of it?")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            ForEach(contested) { claim in
                PickRow(
                    text: claim.text,
                    hint: "Turns this into a question you can both edit"
                ) {
                    onPick(claim)
                }
            }

            Text("Pick one and the app will turn it into a question, using what you each said would change your mind. You can rewrite it however you like.")
                .font(.caption)
                .opacity(0.7)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// They ticked everything the same way. That is a real outcome, not an error.
private struct NothingContestedCard: View {
    var body: some View {
        Card(tint: Theme.agree) {
            VStack(alignment: .leading, spacing: 6) {
                Label("You answered every point the same way", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                Text("On the list you both worked through, there's nothing left splitting you. Whatever the argument was about, it isn't in these points.")
                    .font(.footnote)
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Editing the crux: the question, where each of them lands, and whether it is
/// the kind of thing that gets settled at all.
struct CruxEditor: View {
    @State private var question: String
    @State private var positionA: String
    @State private var positionB: String
    @State private var needsConversation: Bool

    private let original: Crux
    private let names: PartyPair<String>
    private let onSave: (Crux) -> Void
    private let onCancel: () -> Void

    init(
        crux: Crux,
        names: PartyPair<String>,
        onSave: @escaping (Crux) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.original = crux
        self.names = names
        self.onSave = onSave
        self.onCancel = onCancel
        _question = State(initialValue: crux.question)
        _positionA = State(initialValue: crux.positions.a)
        _positionB = State(initialValue: crux.positions.b)
        _needsConversation = State(initialValue: crux.needsConversation)
    }

    private var canSave: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("The question", text: $question, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("The question underneath")
                } footer: {
                    Text("Phrase it so neither answer sounds like the right one. \"Would the raise cover what the move costs?\", not \"Am I right about the money?\"")
                }

                Section("Where you each land") {
                    LabeledContent(names.a) {
                        TextField("One short sentence", text: $positionA, axis: .vertical)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1...3)
                    }
                    LabeledContent(names.b) {
                        TextField("One short sentence", text: $positionB, axis: .vertical)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1...3)
                    }
                }

                Section {
                    Toggle("This is about how we treat each other", isOn: $needsConversation)
                        .onChange(of: needsConversation) { Haptics.selection() }
                } footer: {
                    Text("Some things don't get settled by one of you being right. Ticking this changes how the app words it, and nothing else.")
                }
            }
            .navigationTitle("Name the crux")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            Crux(
                                id: original.id,
                                question: question.trimmingCharacters(in: .whitespacesAndNewlines),
                                positions: PartyPair(a: positionA, b: positionB),
                                needsConversation: needsConversation
                            )
                        )
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

#Preview("Manual crux") {
    ManualCruxView(
        contested: [
            Claim(text: "The raise would cover what the move costs.",
                  origin: .a, agreement: PartyPair(a: true, b: false)),
            Claim(text: "Changing schools would set the kids back.",
                  origin: .b, agreement: PartyPair(a: false, b: true)),
        ],
        crux: nil,
        names: PartyPair(a: "Alex", b: "Sam"),
        rethinks: PartyPair(both: nil),
        sharedCount: 4,
        draft: { Crux.draft(from: $0) },
        onSet: { _ in },
        onContinue: {}
    )
    .background(Theme.background)
}
