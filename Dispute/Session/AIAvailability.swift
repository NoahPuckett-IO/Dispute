import Foundation
import Observation
import DisputeCore

/// Whether this session gets a model, and the key that decides it.
///
/// One object so the settings screen, the first-run screen and the engine picker
/// cannot disagree about the answer.
///
/// ## What this used to be
///
/// Six hundred lines, most of it about a gigabyte. The app downloaded a 1.7B
/// model, verified its checksum, tracked a background transfer that had to
/// survive being killed mid-flight, kept the loaded weights in memory, released
/// them on backgrounding and on memory warnings, budgeted llama.cpp's threads
/// against the rest of the phone, and deleted files left by earlier versions.
/// All of that worked. None of it is here now, because the model it was for is
/// gone — see docs/DECISIONS.md.
///
/// What was left after that was the honest shape of the problem as it stood: a
/// key, or no key. With one, the app was assisted. Without one, the two of them
/// did it by hand.
///
/// That is no longer the question either, and this object shrank again. The AI
/// is available to everybody with nothing to set up: requests go through the
/// app's own Worker on the app's own account, and the phone proves it is a real
/// copy of the app rather than carrying a credential. So the only question that
/// remains is whether somebody *wants* it — which is now asked on the first
/// screen, and answered before anything can leave the phone. See `hasChosen`.
///
/// The key did not go away, it stopped being the price of entry. A key of your
/// own buys your own quota instead of a share of the app's, which matters on the
/// day the shared one runs out and matters to nobody else.
///
/// By hand is still a complete way to use this app, and still what happens when
/// the switch is off, when the hosted path is not configured, and when the
/// network is gone.
@MainActor
@Observable
final class AIAvailability {
    /// The app's one instance.
    ///
    /// `@State private var ai = AIAvailability()` looks like it builds this
    /// once. It does not: SwiftUI evaluates a `@State` default every time the
    /// view struct is initialised and throws away all but the first, so the app
    /// was building a fresh one on most renders of the root view.
    static let shared = AIAvailability()

    private let keys = APIKeyStore()

    /// Whether a key is stored, mirrored out of the Keychain.
    ///
    /// A cache, and it exists because `@Observable` can only see stored
    /// properties. Reading the Keychain from a computed property is a call
    /// SwiftUI cannot track, so a key typed into Settings would be saved
    /// correctly and change nothing on screen until something else caused a
    /// redraw — which reads exactly like the field not working.
    ///
    /// The Keychain stays the only place the key itself lives. This is one bool
    /// saying whether the slot is filled.
    private(set) var hasAPIKey = false

    /// Whether the person wants the AI on. Stored across launches.
    ///
    /// The only switch left, and the only one that was ever really about what
    /// somebody wanted. Separate from having a key, so that turning it off does
    /// not throw a key away and turning it back on does not mean finding it
    /// again.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            let defaults = UserDefaults.standard
            defaults.set(isEnabled, forKey: Self.enabledKey)
            // Reaching for the switch in Settings is an answer to the same
            // question the first screen asks, so it counts as one.
            defaults.set(true, forKey: Self.chosenKey)
            hasChosen = true
        }
    }

    /// Whether anybody has answered the question yet.
    ///
    /// **The AI is off until this is true, and that is a legal requirement
    /// rather than a preference.** Apple's guideline 5.1.2(i), as amended in
    /// November 2025, requires explicit permission before personal data is
    /// shared with a third-party AI — and two people's account of an argument
    /// they are having is about as personal as data gets.
    ///
    /// The distinction that matters, and the one this object used to be on the
    /// wrong side of: a screen that explains what will happen, above a button
    /// marked Start, is a *disclosure*. It is not a permission. The words were
    /// already good — the first screen named the provider, named the model, and said
    /// what the free tier means, all before anybody could type. What it did not
    /// have was a fork, so the only way to say no was to find a switch in
    /// Settings afterwards, which is opt-out, which is the shape the guideline
    /// was changed to stop.
    ///
    /// So the first screen asks, both answers are one tap, and nothing leaves
    /// the phone until one of them is given.
    private(set) var hasChosen: Bool

    private static let enabledKey = "aiEnabled"
    private static let chosenKey = "aiChoiceMade"

    init() {
        // A key issued by the previous provider cannot sign a request to this
        // one, so it is dead weight in the Keychain of every phone that upgrades.
        // Dropped here rather than in `setKey`, because the phones that have one
        // are exactly the phones nobody is going to open Settings on.
        //
        // A fresh instance because `self.keys` is not reachable until every
        // stored property has a value, and `APIKeyStore` is a stateless struct
        // around a Keychain query — building a second one costs nothing.
        APIKeyStore().forgetRetiredKeys()

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-forceManualMode") {
            self.isEnabled = false
            self.hasChosen = true
            self.hasAPIKey = false
            return
        }

        // A seeded launch skips the introduction, which is where the choice is
        // made — so without this every `-seedStage` would land in manual mode
        // and the screens that call a model would never call one. The seeds
        // exist to look at those screens.
        if DebugSeed.isSeeded {
            self.isEnabled = true
            self.hasChosen = true
            self.hasAPIKey = keys.hasKey
            return
        }
        #endif

        let defaults = UserDefaults.standard
        // A local, because `self` is not fully initialised until `isEnabled` has
        // a value and reading `self.hasChosen` to compute it does not compile.
        let chosen = defaults.bool(forKey: Self.chosenKey)
        self.hasChosen = chosen
        // Off until asked. The `&&` is the load-bearing part: a stored `true`
        // from a build that defaulted it on does not count as somebody having
        // said yes, so anyone updating from that build is asked once, properly.
        self.isEnabled = chosen && (defaults.object(forKey: Self.enabledKey) as? Bool ?? false)
        self.hasAPIKey = keys.hasKey
    }

    /// Records the answer to the question the first screen asks.
    ///
    /// Writes both defaults directly rather than leaning on `isEnabled`'s
    /// `didSet`, which is guarded on the value having changed — "do it by hand"
    /// sets `false` over a `false`, and would otherwise persist nothing at all.
    func choose(useAI: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Self.chosenKey)
        defaults.set(useAI, forKey: Self.enabledKey)
        hasChosen = true
        isEnabled = useAI
    }

    // MARK: - The key

    func setAPIKey(_ key: String?) {
        keys.setKey(key)
        hasAPIKey = keys.hasKey
    }

    /// Forgets the stored key.
    ///
    /// Called by Remove, in the row about the key, and by nothing else. Deleting
    /// the argument used to call this too, on the reasoning that a button saying
    /// "delete everything" should not leave a credential behind — which was true
    /// about the word and wrong about the button. People press that one at the
    /// ordinary end of a session, and it was quietly undoing a setting they had
    /// made once and had no reason to check again.
    func forgetAPIKey() {
        keys.removeKey()
        hasAPIKey = false
    }

    // MARK: - What a session can expect

    /// Whether there is any way to reach a model from this build.
    ///
    /// The Worker is the way for everybody, so this is nearly always true. It is
    /// false in a build made without `GoogleService-Info.plist` or before the
    /// Worker was deployed, and a key of somebody's own is enough on its own —
    /// which is what makes that build usable rather than broken.
    private var hasSomewhereToAsk: Bool { HostedEngine.isConfigured || hasAPIKey }

    /// Whether a session started right now would get a model.
    var isReady: Bool { isEnabled && hasSomewhereToAsk }

    var mode: DisputeMode { isReady ? .assisted : .manual }

    /// What the session is running on, for the line in Settings and the debug
    /// transcript.
    ///
    /// The transcript is the reason this says whose quota it went through. When
    /// somebody sends one back saying "it kept telling me to wait", the first
    /// thing worth knowing is whether they were sharing the app's allowance or
    /// spending their own.
    var engineDescription: String {
        guard isReady else { return "Nothing, you're doing this by hand" }
        return hasAPIKey
            ? "\(CloudEngine.modelDisplayName), on your own key"
            : CloudEngine.modelDisplayName
    }

    /// The engine for a session, or `nil` for manual mode.
    ///
    /// Built fresh each time and deliberately not cached. `CloudEngine` is a
    /// struct around a transport, which is itself a struct around a description
    /// of a request; there is nothing to load, nothing to keep warm, and nothing
    /// that would be wrong to build twice. The elaborate machinery this replaced
    /// — a shared load task, a cache, a release path — existed entirely because
    /// the thing being built was a gigabyte of weights.
    ///
    /// A stored key wins over the shared path. Somebody who went and got one did
    /// it for a reason, and the reason is almost always that they got tired of
    /// waiting behind everybody else.
    func engine() -> (any DisputeEngine)? {
        guard isEnabled else { return nil }
        #if DEBUG
        // A key straight from the environment, for tooling that needs a real
        // model and cannot type into a text field.
        //
        // This exists for `scripts/screenshots.sh`. Two of the seven shots —
        // the checklist and the crux — are seeded to stop *just before* the
        // thing the screen is a picture of, so photographing them requires a
        // real call. On the simulator the hosted path cannot make one: App
        // Attest does not exist there, App Check falls back to its debug
        // provider, and the Worker rightly refuses a token it has never been
        // told to trust. Before this, that produced two screenshots of the
        // failure screen.
        //
        // The environment rather than a launch argument, because arguments show
        // up in `ps` and this is a credential. `#if DEBUG` rather than a
        // runtime check on the simulator, so no release build has a path to it
        // at all — the same split, for the same reason, as `FirebaseSetup`'s
        // debug App Check provider.
        if let key = ProcessInfo.processInfo.environment["DISPUTE_API_KEY"],
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CloudEngine(apiKey: key)
        }
        #endif
        if let key = keys.key { return CloudEngine(apiKey: key) }
        guard let hosted = HostedEngine.transport() else { return nil }
        return CloudEngine(transport: hosted)
    }
}
