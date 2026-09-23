import SwiftUI
import DisputeCore

/// The AI offer, as one card. Shown on the first-run screen and again in
/// Settings.
///
/// It reads as an offer: what you get, what it costs, and what happens if you
/// turn it down — which is always "the app works, by hand". Neither answer is
/// blocked, and neither waits on anything.
///
/// There used to be five shapes of this, because there were three kinds of phone
/// and two states per phone. Then two, for a key or no key. There are two again,
/// and the split is no longer about what the phone can do — it is about whether
/// the question has been answered yet.
///
/// **Before the choice** it is an offer, and it is the screen where the argument
/// is agreed to be sent to the provider. Every word of it is written as *would*, and
/// the buttons underneath are the answer.
///
/// **After the choice** it reports which way it went, in Settings and nowhere
/// else, and the switch beside it is how somebody changes their mind.
struct AICard: View {
    @Bindable var ai: AIAvailability
    /// Settings has its own section headers and doesn't need the benefit list
    /// repeated at it every time someone opens the screen.
    var showsBenefits = true

    /// What the AI does, in the only terms that matter to someone deciding:
    /// which screens change.
    ///
    /// Kept to one short line each. These sit above the button on the smallest
    /// screen the app supports, and every line added here pushes it below the
    /// fold on a 12 mini.
    static let benefits: [(icon: String, title: String, detail: String)] = [
        ("list.bullet.rectangle", "Writes the list of points", "From both sides, shuffled."),
        ("key", "Names the crux", "The one question underneath it all."),
        ("checklist", "Says how to settle it", "Something you can go and do."),
    ]

    /// Before anybody has answered, this card is an offer rather than a report
    /// of a state — so it asks, and the two buttons under it are the answer.
    ///
    /// Reading `hasChosen` rather than taking a parameter, because the two are
    /// the same fact and a parameter is a second copy of it that can be passed
    /// wrongly. Settings only ever draws this after a choice exists.
    private var isOffer: Bool { !ai.hasChosen }

    var body: some View {
        Card(tint: isOffer || ai.isReady ? Theme.assist : nil) {
            VStack(alignment: .leading, spacing: 14) {
                header

                if showsBenefits {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Self.benefits, id: \.title) { benefit in
                            FeatureRow(
                                systemImage: benefit.icon,
                                title: benefit.title,
                                detail: benefit.detail,
                                tint: Theme.brand
                            )
                        }
                    }
                }

                // Only on the first-run screen. In Settings this same sentence is
                // the section footer under the switch it tells you to use, which
                // is where a Form puts it and where somebody looks for it — and
                // printing it twice, four lines apart, reads as the app being
                // nervous about the answer.
                //
                // "Turn the AI off" rather than "turn it off below": there is no
                // below on the first-run screen, only a line under the Start
                // button saying the setting can be changed later.
                if showsBenefits {
                    Text(disclosure)
                        .font(.caption)
                        .foregroundStyle(Theme.ink.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The sentence this whole card exists for.
    ///
    /// Before the choice it is written as what *would* happen, because nothing
    /// has happened yet and saying otherwise would be a lie on the one screen
    /// that cannot afford one. Afterwards it is written as what is happening.
    /// Neither version softens it, and both name the provider.
    ///
    /// **The training sentence is a claim about an account setting, not about a
    /// default.** Mistral's free tier trains on inputs unless the account opts
    /// out, so this copy is true only while "Allow your interactions to be used
    /// to train our models" is off in the Mistral console. That toggle is part of
    /// shipping this app, not part of setting it up once — see the release
    /// checklist. If it is ever turned back on, this sentence has to change in
    /// the same commit.
    ///
    /// It is worth saying what this replaced, because the change is real: the
    /// Gemini free tier had no opt-out, so this screen had to say that what two
    /// people wrote might be used to improve somebody's products. It no longer
    /// has to say that, and that is the single clearest thing the two people in
    /// front of the phone gained from the move.
    private var disclosure: String {
        if isOffer {
            return "What you both write would be sent to \(CloudEngine.recipients) to be "
                + "read by the model. It's free, and it isn't used to train anything. "
                + "Choose \"Do it by hand\" and nothing leaves this phone."
        }
        return ai.isReady
            ? "What you both write is sent to \(CloudEngine.recipients) to be read by the model. It's free, and it isn't used to train anything. Turn the AI off and none of it leaves the phone."
            : "By hand: you write your own points and name the crux together, and the app walks you through both. Nothing leaves this phone."
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusPill(
                text: pill.text,
                systemImage: pill.icon,
                tint: isOffer || ai.isReady ? Theme.assist : Theme.accent
            )

            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(Theme.ink.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pill: (text: String, icon: String) {
        if isOffer { return ("Free", "sparkles") }
        return ai.isReady ? ("Ready", "checkmark.seal") : ("Off", "hand.raised")
    }

    /// A question while it is a question, and a statement once it is settled.
    private var title: String {
        if isOffer { return "Shall the AI do the hard parts?" }
        return ai.isReady ? "The AI is on" : "You're doing this by hand"
    }

    /// The offer names the provider here as well as in the disclosure below, and
    /// that is deliberate rather than nervous repetition.
    ///
    /// On the shortest screen the app supports the card scrolls, and the
    /// paragraph at the bottom of it is below the fold at the moment somebody
    /// could press "Use the AI". Everything down to this line is visible on
    /// every phone — so the sentence that decides whether the choice is an
    /// informed one has to be up here, and the paragraph underneath is then the
    /// long version rather than the only version.
    private var subtitle: String {
        if isOffer {
            return "Free, nothing to sign up for. Needs a connection, and what "
                + "you both write goes to \(CloudEngine.recipients)."
        }
        return ai.isReady
            ? "Free, nothing to sign up for. Needs a connection, and what you both write goes to \(CloudEngine.recipients)."
            : "The app walks you through the same argument without it."
    }
}

/// The AI section of Settings: the switch, the key, and where to get one.
///
/// Deliberately the same card as the first-run screen at the top of it rather
/// than a Form-native rewrite. The two screens answer the same question — "what
/// would this cost me and what do I get?" — and the fastest way for those answers
/// to drift apart is to build them twice.
struct AISection: View {
    @Bindable var ai: AIAvailability

    @State private var isEnteringKey = false
    @State private var typedKey = ""

    var body: some View {
        Section {
            AICard(ai: ai, showsBenefits: false)
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowBackground(Color.clear)

            Toggle("Use the AI", isOn: $ai.isEnabled)
                .onChange(of: ai.isEnabled) { Haptics.selection() }

            // "Provider" rather than "Model": the app is not in a position to
            // name the model, because the Worker chooses it and ignores what the
            // phone asked for. See `CloudEngine.modelDisplayName`.
            LabeledContent("Provider", value: CloudEngine.providerName)
        } header: {
            Text("AI")
        } footer: {
            Text(ai.isEnabled
                ? "What you both write is sent to \(CloudEngine.recipients) to be read by the model. It's free, and it isn't used to train anything. Needs a connection."
                : "With it off, the app runs by hand: you write your own points and name the crux together. Nothing leaves this phone. It works, and it's how the app started.")
        }

        // A section of its own, and below the one that matters, because this is
        // now an answer to a problem most people will never have. It was the
        // first thing on this screen when it was the only way to use the AI at
        // all; leaving it there would say the setup is still somebody's job.
        Section {
            keyRow

            if !ai.hasAPIKey {
                Link(destination: CloudEngine.keyURL) {
                    Label(
                        "Get a key from the \(CloudEngine.providerName) console",
                        systemImage: "arrow.up.right.square"
                    )
                    .font(.footnote.weight(.medium))
                }
            }
        } header: {
            Text("Your own key")
        } footer: {
            Text(ai.hasAPIKey
                ? "Requests go on your key and your quota, not the app's shared one."
                : "Optional. The free limit is shared between everyone using Dispute, so on a busy day it can run out. Your own key gets you your own limit. Most people won't need this.")
        }
    }

    /// One row, three states: no key, a key, or the field open.
    ///
    /// A stored key is never shown again, not even masked. This screen gets
    /// opened in front of the other person — that is the shape of the whole app,
    /// one phone between two people — so there is no reason for a credential to
    /// stay on screen after the moment it is typed.
    @ViewBuilder
    private var keyRow: some View {
        if isEnteringKey {
            HStack {
                SecureField("Paste your API key", text: $typedKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(save)

                Button("Save", action: save)
                    .font(.subheadline.weight(.semibold))
                    .disabled(typedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } else if ai.hasAPIKey {
            HStack {
                Label("Using your key", systemImage: "key.fill")
                    .foregroundStyle(Theme.assist)
                Spacer()
                Button("Replace") {
                    typedKey = ""
                    isEnteringKey = true
                }
                .font(.subheadline)
                Button("Remove", role: .destructive) {
                    Haptics.notify(.warning)
                    ai.forgetAPIKey()
                }
                .font(.subheadline)
            }
        } else {
            Button {
                typedKey = ""
                isEnteringKey = true
            } label: {
                Label("Use my own API key", systemImage: "key")
            }
        }
    }

    private func save() {
        let trimmed = typedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        ai.setAPIKey(trimmed)
        typedKey = ""
        isEnteringKey = false
        Haptics.notify(.success)
    }
}
