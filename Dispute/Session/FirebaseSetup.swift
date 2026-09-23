import Foundation
import FirebaseCore
import FirebaseAppCheck

/// Starting Firebase, and deciding whether it started.
///
/// One place, called once, before the first view reads anything — the same
/// constraint `DebugSeed` has and for the same reason: `AIAvailability` decides
/// on the first frame whether this session gets a model, and it cannot decide
/// that before the thing it is asking about exists.
///
/// The `isConfigured` flag is the part that earns this a file of its own. A
/// missing or malformed `GoogleService-Info.plist` is a build somebody made
/// without it, and the honest response to that is the by-hand path — not a crash
/// on launch, which is what `FirebaseApp.configure()` does on its own, and not a
/// spinner that fails on the third screen of somebody's argument.
///
/// ## Firebase is here for App Check and nothing else
///
/// It used to be here for two things: App Check, and Firebase AI Logic making the
/// model call. The model call went to Mistral, which Firebase will not proxy, so
/// `FirebaseAILogic` is gone from the project and `HostedEngine` talks to the
/// app's own Worker instead.
///
/// App Check stayed, and keeping it was the deliberate part. It is the reason the
/// phone carries no credential, the reason the shared quota cannot be drained by
/// anybody who pulls the configuration out of the binary, and the reason the App
/// Attest entitlement in this app's declarations is still accurate. The Worker
/// verifies exactly the token this sets up, against Google's public keys — no
/// Firebase billing plan involved, because verification needs nothing but the
/// public half.
enum FirebaseSetup {
    /// Whether the hosted path is available at all in this build.
    private(set) static var isConfigured = false

    @MainActor
    static func configure() {
        guard !isConfigured else { return }

        // `configure()` raises rather than throws when the plist is missing, and
        // an exception from Objective-C is not something Swift can catch. So the
        // check happens first.
        guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
        else {
            assertionFailure("GoogleService-Info.plist is not in the app bundle")
            return
        }

        // Set before `configure()`, which is when App Check reads it.
        AppCheck.setAppCheckProviderFactory(providerFactory)
        FirebaseApp.configure()
        isConfigured = FirebaseApp.app() != nil
    }

    /// How this build proves it is this app.
    ///
    /// ## The entitlement, and why it says `production`
    ///
    /// `Dispute.entitlements` declares
    /// `com.apple.developer.devicecheck.appattest-environment` as `production`.
    /// That is what App Check uses to prove a request came from a real,
    /// unmodified copy of this app on a real Apple device, and it is the whole
    /// reason the AI can be free: without it the Worker's endpoint is open to
    /// anybody who reads the configuration out of the app bundle, and one script
    /// would spend the day's quota before either of the two people this is for
    /// had finished typing.
    ///
    /// `production` is right even though most builds here are development ones.
    /// Debug builds use App Check's debug provider instead and never touch App
    /// Attest at all, and TestFlight and the App Store are both production. The
    /// team provisioning profile permits either value, so the development builds
    /// that do reach a device sign cleanly with it.
    ///
    /// **That paragraph lives here rather than in the entitlements file**, where
    /// it used to be. Xcode rewrites that plist whenever a capability is toggled
    /// in its UI, so a comment in it is prose with a deletion date — and comments
    /// inside the `<dict>` are also what its signing pass reads when it reports
    /// that "the capability associated with APP_ATTEST could not be determined".
    ///
    /// ## The provider
    ///
    /// App Attest is Apple's, runs on the Secure Enclave, and does not exist on
    /// the simulator — which is where most of this app is built and looked at.
    /// The debug provider stands in there: it prints a token on first launch that
    /// has to be pasted into the Firebase console once per simulator or debug
    /// device, and after that the console treats that install as trusted.
    ///
    /// A debug token is a bypass, which is the whole reason the two halves of
    /// this are split by build configuration rather than by a runtime check on
    /// the simulator. A release build has no path to the debug provider at all.
    private static var providerFactory: any AppCheckProviderFactory {
        #if DEBUG
        AppCheckDebugProviderFactory()
        #else
        AppAttestProviderFactory()
        #endif
    }
}
