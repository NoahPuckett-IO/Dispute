import SwiftUI
import DisputeCore

@main
struct DisputeApp: App {
    init() {
        // Before anything asks whether this session gets a model, because the
        // answer is partly "did Firebase start". Cheap: it reads a plist and
        // registers a provider, and opens no connection.
        FirebaseSetup.configure()

        #if DEBUG
        // Has to run before any view reads a stored default, which rules out
        // doing it in `.task` or `onAppear` — `RootView`'s `@AppStorage` and
        // `AIAvailability` both read theirs while the first frame is built.
        DebugSeed.resetIfRequested()
        // Keeps every prompt and raw answer of this run in memory, for the
        // debug transcript behind the beetle in the top bar. Debug builds only,
        // and the switch itself does not exist in a release build.
        PromptLog.shared.isEnabled = true
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

// There is no `AppDelegate` any more. It existed for exactly one callback —
// `handleEventsForBackgroundURLSession` — because a model download could finish
// while the app was suspended or closed, and iOS relaunches the app in the
// background to hand over a completion handler that must be called once the
// transfer has been dealt with. Without it, "carry on, this finishes in the
// background" was not true.
//
// Nothing is downloaded now, so there is no background session to be woken for.
