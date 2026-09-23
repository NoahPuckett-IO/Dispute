import SwiftUI
import DisputeCore

/// How the app should look. Stored across launches.
enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = AppearanceChoice.system
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage(SessionViewModel.assumptionsEnabledKey) private var assumptionsEnabled = true

    @Bindable var ai: AIAvailability
    let engineName: String
    /// False in manual mode, where there is nothing to do the flagging. Hidden
    /// rather than disabled: a switch that does nothing is worse than no switch.
    let isAssumptionFlaggingAvailable: Bool
    let onDeleteEverything: () -> Void
    let onClose: () -> Void

    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                AISection(ai: ai)

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppearanceChoice.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: appearance) { Haptics.selection() }
                }

                Section {
                    Toggle("Haptics", isOn: $hapticsEnabled)
                        // Fires on the way off as well as on, so the last thing
                        // felt before they stop is the one confirming it worked.
                        .onChange(of: hapticsEnabled) { _, isOn in
                            if isOn { Haptics.tap() } else { Haptics.notify(.success) }
                        }

                    if isAssumptionFlaggingAvailable {
                        Toggle("Flag assumptions between turns", isOn: $assumptionsEnabled)
                            .onChange(of: assumptionsEnabled) { Haptics.selection() }
                    }
                } footer: {
                    if isAssumptionFlaggingAvailable {
                        Text("Names what each of you is taking as given without saying so. It never says whether the assumption is right, and you can carry on either way.")
                    }
                }

                Section {
                    LabeledContent("Where this runs", value: engineName)
                } footer: {
                    Text("There is no account and no sign-in. The only things stored on this phone are the argument itself, and a key if you added one.")
                }

                Section {
                    Button(role: .destructive) {
                        Haptics.tap(.medium)
                        isConfirmingDelete = true
                    } label: {
                        Text("Delete this argument")
                    }
                } footer: {
                    Text(ai.hasAPIKey
                        ? "Erases the argument stored on this phone and starts over. Your key is kept, and Remove above takes it out."
                        : "Erases the argument stored on this phone and starts over.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Haptics.tap()
                        onClose()
                    }
                }
            }
            .confirmationDialog(
                "Delete this argument?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete the argument", role: .destructive) {
                    // The one irreversible thing in the app, and the only place
                    // a warning notification is the right weight.
                    Haptics.notify(.warning)
                    // The key is not included, and it used to be. The button was
                    // called "delete everything" and the reasoning was that a
                    // credential left behind makes that word a lie.
                    //
                    // What that missed is who presses this and why. Starting a
                    // fresh argument is the ordinary end of a session, not a
                    // handover of the phone, and it took the key with it every
                    // time: the next argument silently dropped onto the shared
                    // quota, and the person who had pasted a key in had no reason
                    // to suspect it was gone. A destructive button people press
                    // routinely must not quietly undo a setting they made once.
                    //
                    // Removing the key is still one tap, in the row that is about
                    // the key, where somebody handing the phone on would look for
                    // it. Deleting the app still takes everything.
                    onDeleteEverything()
                    onClose()
                }
                Button("Keep it", role: .cancel) { Haptics.tap() }
            }
        }
    }
}
