import SwiftUI
import DisputeCore

/// One person says what they think, in their own words.
struct PositionEntryView: View {
    let disputeTitle: String
    let party: Party
    let personName: String
    let otherName: String
    @Binding var text: String
    /// Manual mode only. When bound, this person also writes their own points
    /// here, on this turn — see `PointsEntryView`.
    var points: Binding<[String]>?
    /// What this person wrote when the checklist could not be built from it, on
    /// the second visit to this screen. `nil` on an ordinary first pass.
    var toImproveOn: String?
    let onContinue: () -> Void

    @FocusState private var isFocused: Bool

    private var hasWritten: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var wordsWritten: Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// Assisted mode only. There are no three claims inside "I like the smores
    /// frappe", and a model asked for them hands the sentence back or invents —
    /// a real session got both. In manual mode this person writes their own
    /// points, so a short position costs nobody anything.
    private var hasEnoughToWorkWith: Bool {
        points != nil || wordsWritten >= Dispute.minimumPositionWords
    }

    /// Set when this screen is a second visit after the checklist could not be
    /// built. Holds Done until the text differs from the text that failed: it is
    /// already long enough to pass the gate above, so without this Done is live
    /// on arrival and pressing it runs the same half minute to the same dead end.
    private var isUnchangedSinceItFailed: Bool {
        guard let toImproveOn else { return false }
        return !text.isDifferentWriting(from: toImproveOn)
    }

    private var canContinue: Bool {
        guard !isUnchangedSinceItFailed else { return false }
        guard let points else { return hasWritten && hasEnoughToWorkWith }
        let written = points.wrappedValue
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return hasWritten && written.count >= Dispute.requiredPointsEach
    }

    /// Why Done is waiting. Always says something when it is disabled for a
    /// reason this person can act on, because a button that does nothing and
    /// explains nothing is the thing people report as the app being broken.
    ///
    /// Nothing is shown before they have typed anything: opening a screen by
    /// telling somebody mid-argument that what they have not written yet is too
    /// short is the app being rude to them for no gain.
    private var entryHint: String? {
        if isUnchangedSinceItFailed {
            return "Add anything you like to this, then Done."
        }
        guard hasWritten, !hasEnoughToWorkWith else { return nil }
        return "Say a bit more about why. There's nothing to pull apart yet."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(
                    title: "\(personName), what do you think?",
                    subtitle: "Say it how you'd say it out loud.",
                    eyebrow: disputeTitle
                )

                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                            .strokeBorder(Theme.color(for: party).opacity(0.4), lineWidth: 1)
                    }
                    .frame(minHeight: points == nil ? 170 : 130)
                    .focused($isFocused)
                    .accessibilityLabel("Your view")

                // Says plainly that this is written blind, in both directions.
                // The symmetry is the thing testers didn't believe.
                Label("\(otherName) can't see this until you've both written.", systemImage: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)

                if let entryHint {
                    Label(entryHint, systemImage: "text.append")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(entryHint)
                        .transition(.opacity)
                }

                if let points {
                    Divider().padding(.vertical, 2)
                    PointsEntryView(party: party, otherName: otherName, points: points)
                }

                Spacer(minLength: 0)
            }
            .padding(Theme.screenPadding)
            .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Done", isEnabled: canContinue, action: onContinue)
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .background(.bar)
        }
        .toolbar {
            // A `TextEditor` takes Return as a newline, so there was no way at
            // all to put the keyboard down on this screen — and in manual mode
            // the points to be written next are behind it.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isFocused = false }
            }
        }
        // Kept, unlike the start screen: this screen exists to be typed into,
        // and its one field is the first thing on it.
        .onAppear { isFocused = true }
    }
}
