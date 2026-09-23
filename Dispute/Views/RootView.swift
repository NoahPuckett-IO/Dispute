import SwiftUI
import DisputeCore

struct RootView: View {
    /// Built on the splash rather than in a `@State` default, which SwiftUI
    /// evaluates on every initialisation of the view struct and throws away all
    /// but the first.
    @State private var model: SessionViewModel?
    /// The shared instance, not a fresh one — see `AIAvailability.shared`.
    @State private var ai = AIAvailability.shared
    @State private var isShowingSettings = false
    @State private var hasFinishedSplash = false
    #if DEBUG
    @State private var isShowingDebugTranscript = false
    #endif
    @AppStorage("appearance") private var appearance = AppearanceChoice.system
    /// Shown once, before the first argument. Which mode this phone is on is not
    /// something anyone should have to discover halfway through one.
    @AppStorage("hasSeenIntroduction") private var hasSeenIntroduction = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if let model, hasFinishedSplash {
                SessionShell(model: model)
                    .safeAreaInset(edge: .top) { topBar(model: model) }
                    .transition(.opacity)
                    .sheet(isPresented: $isShowingSettings) {
                        SettingsView(
                            ai: ai,
                            engineName: model.engineDescription,
                            isAssumptionFlaggingAvailable: model.isAssumptionFlaggingAvailable,
                            onDeleteEverything: model.startOver,
                            onClose: { isShowingSettings = false }
                        )
                    }
                    .sheet(isPresented: .constant(needsIntroduction)) {
                        IntroductionView(ai: ai) { hasSeenIntroduction = true }
                            .interactiveDismissDisabled()
                    }
                    #if DEBUG
                    .sheet(isPresented: $isShowingDebugTranscript) {
                        DebugTranscriptView(text: model.debugTranscript) {
                            isShowingDebugTranscript = false
                        }
                    }
                    #endif
                    // The AI switch decides how the next argument runs, and the
                    // session was built during the splash — before Settings had
                    // been anywhere near. Without this, turning the AI off (or
                    // adding a key of your own) changed nothing until the app
                    // was relaunched.
                    //
                    // A session already under way keeps the mode it started in,
                    // which is why this only fires when nothing has been typed
                    // yet. Comparing modes rather than reacting to the toggle
                    // keeps it from rebuilding on first appearance, when the
                    // splash has just built exactly the same thing.
                    .task(id: ai.mode) {
                        guard model.isUntouched, model.mode != ai.mode else { return }
                        self.model = Self.makeModel(ai: ai)
                    }
            } else {
                SplashView()
                    .task {
                        if model == nil { model = Self.makeModel(ai: ai) }
                        // Long enough to register, short enough not to annoy.
                        try? await Task.sleep(for: .milliseconds(900))
                        Motion.run(.easeInOut(duration: 0.35)) { hasFinishedSplash = true }
                    }
            }
        }
        .preferredColorScheme(appearance.colorScheme)
    }

    /// A seeded launch asked for a particular stage and gets it. The sheet is
    /// modal, so leaving it up would mean `-seedStage` quietly did nothing.
    private var needsIntroduction: Bool {
        #if DEBUG
        if DebugSeed.isSeeded { return false }
        #endif
        return !hasSeenIntroduction
    }

    /// The gear is a 44pt target with a visible disc behind it.
    ///
    /// It used to be a footnote-sized glyph with no padding — around 15pt of
    /// tappable area in the corner of the screen, which is under a third of
    /// Apple's minimum and missable even when you know it is there. The disc is
    /// not decoration: an unbacked icon in a corner reads as a label, and this
    /// is the only way into Settings from anywhere in a session.
    private func topBar(model: SessionViewModel) -> some View {
        HStack {
            StageProgress(stage: model.stage)

            Spacer()

            // There is no "starting the AI…" indicator any more, and nothing to
            // put one on. It existed because the downloaded model took tens of
            // seconds to read off disk before the first call, so switching the
            // AI on and finding the session still by hand read as the switch not
            // working. Building a `CloudEngine` is building a struct.

            // Reachable from every screen on purpose. The interesting moment for
            // reading the prompting is usually the crux screen, and a transcript
            // you can only take at the end is one taken after the evidence has
            // scrolled past. Debug builds only.
            #if DEBUG
            if !DebugSeed.isScreenshot {
                Button {
                    isShowingDebugTranscript = true
                } label: {
                    Image(systemName: "ladybug.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink.opacity(0.55))
                        .frame(width: 34, height: 34)
                        .background { Circle().fill(Theme.ink.opacity(0.06)) }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Debug transcript")
            }
            #endif

            Button {
                Haptics.tap()
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink.opacity(0.75))
                    .frame(width: 34, height: 34)
                    .background { Circle().fill(Theme.ink.opacity(0.08)) }
                    // The disc stays 34pt so it doesn't loom over the step
                    // dots; the target around it is the full 44.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            // Pulls the widened target back to the screen margin, so the icon
            // sits where it always did rather than inset by the new padding.
            .padding(.trailing, -5)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.bottom, 6)
    }

    /// Builds the session for this launch.
    ///
    /// Nothing here loads a model. It used to: the engine was built up front and
    /// handed to the session, so every cold launch with the AI switched on read a
    /// gigabyte off disk before the first screen appeared, whether or not the
    /// person was going to start an argument. `EngineSource` defers that to the
    /// first call that actually needs it, which is the checklist — two screens and
    /// a lot of typing later.
    @MainActor
    private static func makeModel(ai: AIAvailability) -> SessionViewModel {
        let store = try? DisputeStore()
        let engineSource = makeEngineSource(ai: ai)

        #if DEBUG
        if let stage = DebugSeed.stageFromLaunchArguments() {
            // The seeded session's mode follows the engine this launch actually
            // got, not the stored AI setting. Reading `ai.mode` here meant
            // `-forceMockEngine` produced an engine and a session marked manual,
            // so every seeded screen was the by-hand one and the assisted crux
            // screen could not be reached by any combination of flags.
            let model = SessionViewModel(
                dispute: DebugSeed.dispute(at: stage, mode: engineSource == nil ? .manual : .assisted),
                engineSource: engineSource,
                store: nil, // seeded runs never touch real storage
                beginAtHandoff: !ProcessInfo.processInfo.arguments.contains("-seedSkipHandoff")
            )
            // Through the same door the app uses, rather than by setting the
            // step directly — a seed that could reach a state the app can't is
            // a seed that proves nothing.
            if DebugSeed.startsOnSecondLook { model.finishTicking() }
            if DebugSeed.startsAfterFailedClaims { model.debugMarkCurrentPositionsAsFailed() }
            if DebugSeed.startsOnAssumptions { model.debugShowAssumptions(DebugSeed.seededAssumptions) }
            return model
        }
        #endif

        // A session keeps the mode it started in. Flipping the toggle halfway
        // through an argument would otherwise land someone on a checklist built
        // from points nobody wrote.
        let resumed = store?.load()
        return SessionViewModel(
            dispute: resumed ?? Dispute(mode: engineSource == nil ? .manual : .assisted),
            engineSource: resumed.map { $0.mode == .assisted ? engineSource : nil } ?? engineSource,
            store: store
        )
    }

    /// Where this session's engine will come from, or `nil` for manual mode.
    ///
    /// One answer for every phone now. There is no branch here on what hardware
    /// this is: the app ships one model, every device downloads it, and a session
    /// is assisted exactly when that model is on disk and switched on. See
    /// `AIAvailability`.
    private static func makeEngineSource(ai: AIAvailability) -> EngineSource? {
        #if DEBUG
        // Every failure screen is otherwise reachable only by getting a real model
        // to misbehave on demand, which is the thing models do when nobody is
        // looking and refuse to do when somebody is.
        //
        //     -seedStage checklist -seedSkipHandoff -forceFailure notEnough
        //     -seedStage checklist -seedSkipHandoff -forceFailure refused
        if let failure = DebugSeed.forcedFailure {
            return .fixed(MockDisputeEngine(failure: failure), description: "Forced failure")
        }
        if ProcessInfo.processInfo.arguments.contains("-forceMockEngine") {
            return .fixed(MockDisputeEngine(), description: "Offline sample data")
        }
        #endif

        // `-forceManualMode` is handled inside `AIAvailability`, so that the
        // mode recorded on the session and the engine behind it can never
        // disagree.
        return ai.isReady ? .live(ai) : nil
    }
}

#Preview {
    RootView()
}
