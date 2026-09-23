#if DEBUG
import SwiftUI

/// The debug transcript on screen, with the three ways of getting it off the
/// phone: the clipboard, the share sheet, or a file in the app's own folder.
///
/// Debug builds only. There is no route to this screen in a release build, and
/// the file it renders does not compile into one.
///
/// It is deliberately plain. This is a screen for reading prompts, so it is a
/// monospaced dump with no card, no tint and no animation — anything that made
/// it look like the rest of the app would invite someone to treat it as part of
/// the app.
struct DebugTranscriptView: View {
    let text: String
    let onClose: () -> Void

    @State private var savedPath: String?
    @State private var didCopy = false
    /// Written once when the screen opens, because `ShareLink` wants a file that
    /// exists. The temporary directory is right for this one: the share sheet
    /// copies it wherever it is going, and nothing needs it afterwards.
    @State private var shareable: URL?

    private let filename = "dispute-debug-\(Int(Date().timeIntervalSince1970)).txt"

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Debug transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onClose)
                }
                ToolbarItem(placement: .primaryAction) {
                    if let shareable {
                        ShareLink(item: shareable) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .onAppear {
                let url = FileManager.default.temporaryDirectory.appending(path: filename)
                do {
                    try text.write(to: url, atomically: true, encoding: .utf8)
                    shareable = url
                } catch {
                    shareable = nil
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Button {
                            UIPasteboard.general.string = text
                            didCopy = true
                            // Goes back to saying "Copy", so a second copy after
                            // taking more of the session still confirms itself.
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                didCopy = false
                            }
                        } label: {
                            Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            savedPath = save()
                        } label: {
                            Label("Save to app folder", systemImage: "folder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(.footnote)

                    // The path is the point of the button: on the simulator this
                    // is how the file gets to a Mac, via
                    // `xcrun simctl get_app_container <device> <bundle id> data`.
                    if let savedPath {
                        Text(savedPath)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
    }

    /// Writes into the app's Documents folder, which is the one place a file can
    /// be pulled off a simulator without a share sheet.
    private func save() -> String {
        guard let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return "no documents directory" }

        let url = documents.appending(path: filename)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url.path(percentEncoded: false)
        } catch {
            return "couldn't write it: \(error.localizedDescription)"
        }
    }
}

#Preview {
    DebugTranscriptView(
        text: """
            DISPUTE DEBUG TRANSCRIPT
            Engine: On this device

            SESSION

            Title: Remote work vs office work
            """,
        onClose: {}
    )
}
#endif
