import Foundation
import FirebaseAppCheck
import DisputeCore

/// The free path: the app's own Worker, and the token that gets through it.
///
/// This is the app-target half of `ProxyTransport`. The transport itself lives in
/// `DisputeCore` and knows nothing about Firebase — it takes a closure that
/// produces a token — and this is the file that knows how to produce one. That
/// split is what keeps `DisputeCore` linking no binaries and testable in a
/// second, and it is why the provider swap did not reach into the package's
/// dependencies at all.
///
/// ## What replaced what
///
/// Firebase AI Logic used to be both halves of this: it held the credential *and*
/// made the call, because the credential was Google's and the model was Google's.
/// Mistral is neither, and Firebase will not proxy to it. So the proxy is ours
/// now — a Cloudflare Worker on the free plan, with the Mistral key as a secret
/// that never leaves Cloudflare.
///
/// What did *not* change is the part that matters for review: App Check, App
/// Attest, and the entitlement that goes with them all stay exactly where they
/// were. The Worker verifies the same token Firebase used to verify, against the
/// same public keys. The phone still carries no credential and still proves it is
/// a genuine copy of this app before anything is spent on its behalf.
enum HostedEngine {
    /// Where the Worker lives.
    ///
    /// Deployed 6 August 2026. Not a secret and not worth hiding: it is a public
    /// endpoint that refuses everything without a valid App Check token, which is
    /// the whole design. See `worker/README.md`.
    ///
    /// An empty string here is a supported state rather than an oversight waiting
    /// to happen. It makes `isConfigured` false, which makes the app behave
    /// exactly as it does in a build with no `GoogleService-Info.plist` — the
    /// by-hand path, offered honestly on the first screen. That is what a build
    /// made before the Worker existed did, and it is what a build should do again
    /// if this ever has to be pulled. The alternative is a URL that resolves to
    /// nothing and fails on the third screen of somebody's argument, which is the
    /// bug the `isConfigured` flag was invented to avoid.
    private static let endpointString = "https://dispute-ai.puckett.workers.dev/"

    static var endpoint: URL? {
        guard !endpointString.isEmpty else { return nil }
        return URL(string: endpointString)
    }

    /// Whether the free path is available in this build.
    ///
    /// Both halves are required and they fail for different reasons: no endpoint
    /// is a build made before the Worker was deployed, and no Firebase is a build
    /// made without the plist. Either way there is nothing to attest to and
    /// nowhere to send it.
    static var isConfigured: Bool { endpoint != nil && FirebaseSetup.isConfigured }

    /// The transport for somebody who has installed this and typed nothing.
    static func transport() -> ProxyTransport? {
        guard let endpoint else { return nil }
        return ProxyTransport(endpoint: endpoint) { try await token() }
    }

    /// One App Check token, for one request.
    ///
    /// Not cached here. The Firebase SDK already caches and refreshes these
    /// internally, so a cache in front of it would be a second policy about
    /// expiry that could disagree with the first — and the failure mode of
    /// disagreeing is a token that looks fresh here and is rejected at the
    /// Worker, which reads to two people mid-argument as the app being broken.
    ///
    /// `forcingRefresh: false` for the same reason: the SDK knows when its token
    /// is stale and forcing it on every call spends a Secure Enclave round trip
    /// per request for nothing.
    ///
    /// Throwing is meaningful. `ProxyTransport` turns a throw from here into
    /// `refused(cause: .app)` — this copy of the app could not be vouched for —
    /// which is the honest thing to say and, crucially, does not send somebody
    /// looking for a key they never typed.
    private static func token() async throws -> String {
        do {
            return try await AppCheck.appCheck().token(forcingRefresh: false).token
        } catch {
            #if DEBUG
            reportDebugTokenSetup(error)
            #endif
            throw error
        }
    }

    #if DEBUG
    /// Says out loud what to do about the one failure everybody hits once.
    ///
    /// Debug builds attest with App Check's debug provider, because App Attest
    /// needs the Secure Enclave and there isn't one on a simulator. That
    /// provider mints a token that Firebase will not honour until somebody
    /// pastes it into the console, once per simulator and once per debug device.
    /// Until they do, every call fails and the screen says the app was turned
    /// down, which is true and useless.
    ///
    /// Firebase prints the token itself, once, on the first launch after install
    /// — several hundred lines above wherever you are when you find out you
    /// needed it. This prints it at the moment it is wanted, with the reason and
    /// the fix attached, because a token you have to go and find is a token you
    /// go and find three times.
    private static func reportDebugTokenSetup(_ error: any Error) {
        // Where the SDK keeps it. Reading the default rather than asking the
        // provider, because the provider's accessor has moved between Firebase
        // major versions and this file should not care.
        //
        // Two keys because the prefix moved with it: App Check was extracted
        // into the standalone AppCheckCore library and took its defaults from
        // `FIRA` to `GAC`. Both are read so this keeps working across an SDK
        // bump in either direction — and the `GAC` one is what this project
        // actually writes today, which was worth finding out by looking rather
        // than by assuming.
        let stored = ["GACAppCheckDebugToken", "FIRAAppCheckDebugToken"]
            .lazy
            .compactMap { UserDefaults.standard.string(forKey: $0) }
            .first
        print("""

        ┌── Dispute: App Check could not get a token ──────────────────
        │ \(error.localizedDescription)
        │
        │ Debug builds use App Check's debug provider, and Firebase will
        │ not issue a token until this install's debug token is registered.
        │
        │ Debug token: \(stored ?? "not printed yet — relaunch once after install")
        │
        │ Register it: Firebase console → App Check → Dispute (iOS)
        │              → ⋮ → Manage debug tokens → Add
        │              Project dispute-4ccdf. Once per simulator or device.
        │
        │ Or skip the hosted path entirely while testing:
        │   Settings → "Use my own API key" → paste a Mistral key
        │   or set DISPUTE_API_KEY in the scheme's environment.
        │
        │ Release builds use App Attest and need none of this.
        └──────────────────────────────────────────────────────────────

        """)
    }
    #endif
}
