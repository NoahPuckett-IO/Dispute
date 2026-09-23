import Foundation
import Observation
import SwiftUI
import DisputeCore

/// Owns the live dispute and is the only thing allowed to mutate it.
///
/// Views observe and send intent; they never touch the model or the engine
/// directly. The session is a state machine with real invariants, and those
/// invariants need exactly one owner.
@MainActor
@Observable
final class SessionViewModel {
    /// What the screen should be showing right now.
    enum Phase: Equatable {
        case working
        case handoff(to: Party)
        case thinking(String)
        case failed(EngineError)
        /// What the two positions take for granted. Shown once, between turns.
        case assumptions([AssumptionFlag])
    }

    /// Where someone is within their own turn on the checklist.
    ///
    /// A stage of its own would have meant two more handoffs — the app already
    /// learned that more handoffs is what makes people stop before the end — so
    /// the second look happens on the turn they are already taking, while they
    /// still have the phone.
    enum ChecklistStep: Equatable {
        /// Working through the list.
        case ticking
        /// Arguing for one of the points they crossed out.
        case secondLook
    }

    private(set) var dispute: Dispute
    private(set) var phase: Phase = .working
    /// Whose turn it is. Meaningless on stages where `isPerParty` is false.
    private(set) var currentParty: Party = .a
    private(set) var checklistStep: ChecklistStep = .ticking

    /// Where an engine comes from, or `nil` in manual mode.
    ///
    /// Optional rather than a do-nothing engine: a null object would let a
    /// manual session silently reach a screen that waits for an answer nobody is
    /// going to give, and the compiler would not say a word about it.
    ///
    /// A source rather than an engine, so that nothing here keeps a gigabyte
    /// alive between calls. See `EngineSource`.
    /// `var` because of `carryOnByHand()`, which is the one thing that can take
    /// it away mid-session.
    private var engineSource: EngineSource?
    private let store: DisputeStore?
    private var lastFailedAction: (() -> Void)?
    /// Owned here, not by a view.
    ///
    /// Engine work used to start from a view's `.task`, so the moment `phase`
    /// became `.thinking` the shell swapped that view out, SwiftUI tore it down,
    /// and the in-flight request was cancelled — the view killing the work it
    /// had just started. The model outlives the swap, so it holds the task.
    private var activeTask: Task<Void, Never>?

    init(
        dispute: Dispute = Dispute(),
        engineSource: EngineSource? = .fixed(MockDisputeEngine(), description: "Offline sample data"),
        store: DisputeStore? = nil,
        beginAtHandoff: Bool = true
    ) {
        self.dispute = dispute
        self.engineSource = engineSource
        self.store = store
        // Entering a stage taken in turns always starts with the phone changing
        // hands, so a resumed session never drops someone into a turn that might
        // not be theirs. `beginAtHandoff` is for development only.
        self.phase = (beginAtHandoff && dispute.stage.isPerParty) ? .handoff(to: .a) : .working
    }

    // MARK: - Derived state

    var stage: SessionStage { dispute.stage }
    var canAdvance: Bool { dispute.canAdvance }
    var claims: [Claim] { dispute.claims }
    var sharedCount: Int { dispute.sharedClaims.count }

    /// Whether the current failure can be escaped by rewording.
    var canGoBackToPositions: Bool { dispute.stage > .positions }

    var mode: DisputeMode { dispute.mode }

    /// Nothing has been typed into this session yet, so it can be thrown away
    /// and rebuilt without losing anything. Used when the AI setting changes
    /// before an argument has actually started.
    var isUntouched: Bool {
        dispute.stage == .setup
            && dispute.title.isEmpty
            && dispute.names.allSatisfy(\.isEmpty)
    }

    var engineDescription: String {
        engineSource?.description ?? "Nothing, you're doing this by hand"
    }
    var contestedCount: Int { dispute.contestedClaims.count }

    /// What each of them had written when the checklist could not be built, or
    /// `nil` if that has not happened in this session.
    ///
    /// Kept so the entry screen can hold its Done button until something has
    /// actually been added. Without it, `SayMoreView` sends someone back to a box
    /// that already contains text long enough to satisfy the length gate, so Done
    /// is live the moment they arrive: press it twice and the app spends another
    /// half minute reaching the same screen. That is the retry button this change
    /// removed, wearing a different hat.
    ///
    /// Nobody can be trapped by it. Any edit at all clears the condition, and the
    /// screen says so rather than leaving a dead button to be puzzled over.
    private(set) var positionsThatFailed: PartyPair<String>?

    /// What this person has to change before they can go on, if anything.
    func positionToImproveOn(for party: Party) -> String? {
        positionsThatFailed?[party]
    }

    #if DEBUG
    /// Puts the session in the state it is in after `SayMoreView`, so that screen
    /// and the entry screen behind it can be looked at without getting a real
    /// model to play both positions back first.
    ///
    ///     -seedStage positions -seedSkipHandoff -seedAfterFailedClaims
    func debugMarkCurrentPositionsAsFailed() {
        positionsThatFailed = dispute.positions
    }

    /// Puts the session on the assumptions screen with flags already found.
    ///
    /// Through `phase` rather than by calling `runAssumptionPass`, because the
    /// point is to look at the screen rather than to wait a minute for a model
    /// that may find nothing. The flags are stored on the dispute too, so the
    /// debug transcript and "carry on" both behave as they would for real.
    ///
    ///     -seedStage positions -seedSkipHandoff -seedAssumptions
    func debugShowAssumptions(_ flags: [AssumptionFlag]) {
        dispute.assumptionFlags = flags
        phase = .assumptions(flags)
    }
    #endif

    /// The points one person has written for themselves, for the entry screen.
    var currentPoints: [String] { dispute.ownPoints[currentParty] }

    func setPoints(_ points: [String], for party: Party) {
        dispute.setPoints(points, for: party)
    }

    var hasEnoughPoints: Bool { dispute.hasEnoughPoints(currentParty) }

    /// The points they answered differently, which is what a manual crux is
    /// built from.
    var contestedClaims: [Claim] { dispute.contestedClaims }

    /// The points the person whose turn it is crossed out. The only ones they
    /// can be asked to argue for.
    var rejectedByCurrentParty: [Claim] { dispute.rejectedClaims(by: currentParty) }

    var rethinkForCurrentParty: Rethink? { dispute.rethinks[currentParty] }

    var crux: Crux? { dispute.crux }

    var recap: String { dispute.recap }

    var title: String {
        get { dispute.title }
        set { dispute.title = newValue }
    }

    var names: PartyPair<String> {
        PartyPair(a: dispute.name(for: .a), b: dispute.name(for: .b))
    }

    func name(for party: Party) -> String { dispute.name(for: party) }

    func nameBinding(for party: Party) -> Binding<String> {
        Binding(
            get: { self.dispute.names[party] },
            set: { self.dispute.names[party] = $0 }
        )
    }

    func position(for party: Party) -> String { dispute.positions[party] }

    func setPosition(_ text: String, for party: Party) {
        dispute.positions[party] = text
    }

    // MARK: - Turn taking

    func passPhone(to party: Party) {
        currentParty = party
        checklistStep = .ticking
        phase = .handoff(to: party)
    }

    func acceptPhone() {
        phase = .working
    }

    /// Steps back so someone can rewrite what they said.
    ///
    /// The only backwards move in the app. It exists because the model's safety
    /// filters can decline a position outright, and before this the only escape
    /// was to throw the session away.
    func goBackAndEdit() {
        cancelEngineWork()
        dispute.returnToPositions()
        currentParty = .a
        checklistStep = .ticking
        phase = .handoff(to: .a)
        persist()
    }

    private func cancelEngineWork() {
        activeTask?.cancel()
        activeTask = nil
        lastFailedAction = nil
    }

    /// Called by `startOver`, where a stale copy of somebody else's argument
    /// would hold the Done button on a screen that has never been filled in.
    private func forgetTheFailedPositions() {
        positionsThatFailed = nil
    }

    // MARK: - The second look

    /// Ends the ticking half of a checklist turn.
    ///
    /// Someone who crossed nothing out is not asked to argue for anything —
    /// there is nothing of theirs to argue against — and their turn ends here.
    func finishTicking() {
        guard dispute.owesRethink(currentParty) else {
            finishTurn()
            return
        }
        checklistStep = .secondLook
        persist()
    }

    /// Back to the list. Someone who wants to change an answer before arguing
    /// for one should not have to finish the argument first.
    func returnToTicking() {
        checklistStep = .ticking
    }

    func saveSecondLook(_ rethink: Rethink) {
        dispute.setRethink(rethink, for: currentParty)
        checklistStep = .ticking
        Haptics.tap(.medium)
        finishTurn()
    }

    /// Finishes the current person's turn.
    ///
    /// Within a stage taken in turns the other person goes next; once both have
    /// gone, the session advances. Other stages advance immediately.
    func finishTurn() {
        persist()

        guard stage.isPerParty else {
            advanceStage()
            return
        }

        if currentParty == .a {
            passPhone(to: .b)
        } else if stage == .positions {
            // Both have written. Named before the list is built, so what each
            // side is standing on is visible before they start ticking things
            // derived from it.
            runAssumptionPass()
        } else {
            advanceStage()
        }
    }

    /// Whether assumption flagging should run at all.
    ///
    /// Answered without loading a model: the engine source knows, and this is
    /// read by Settings, which has to open instantly.
    var isAssumptionFlaggingAvailable: Bool { engineSource?.canFlagAssumptions ?? false }

    /// Names what each position takes for granted, then moves on either way.
    ///
    /// Runs at `.utility`, like every other engine call here. Two people have
    /// just finished typing and are about to pass the phone; a few seconds of
    /// difference in how fast this comes back is not worth the app outbidding
    /// the rest of the system for the fast cores.
    private func runAssumptionPass() {
        // Once per argument, and this guard is the fix for the loop.
        //
        // The screen offers "go back and add to it". That returns to the
        // positions stage and clears everything derived from it, so when the
        // stage ended again the pass ran again, found assumptions again — there
        // are always assumptions — and put them back on the same screen. Going
        // back was therefore a button that could not be escaped except by
        // force-quitting, and the way out was the *other*, quieter button.
        //
        // Checked before the engine is asked, so a second trip through positions
        // does not even spend the call. See `Dispute.hasShownAssumptions`.
        guard !dispute.hasShownAssumptions else {
            advanceStage()
            return
        }

        guard let engineSource, isAssumptionFlaggingAvailable,
              UserDefaults.standard.object(forKey: Self.assumptionsEnabledKey) as? Bool ?? true
        else {
            advanceStage()
            return
        }

        phase = .thinking("Reading what you both wrote…")
        activeTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            guard let engine = await engineSource.provide() else {
                // The model would not load. Never a dead end: this pass is the
                // one part of the session nothing downstream depends on.
                self.activeTask = nil
                self.advanceStage()
                return
            }

            // One call for both, where this was one each. Half the requests a
            // session spends, and one wait rather than two end to end on a screen
            // where the phone is face up between two people.
            let found = (try? await engine.findAssumptions(
                positionA: self.dispute.positions[.a],
                positionB: self.dispute.positions[.b],
                disputeTitle: self.dispute.title
            )) ?? []
            self.activeTask = nil
            self.dispute.assumptionFlags = found
            // Marked shown whether or not anything was found, and before the
            // screen appears. A pass that came back empty has still had its one
            // go, so a later trip through positions does not spend the call
            // again — and marking it here rather than on dismissal means the
            // record survives someone backgrounding the app on this screen.
            self.dispute.hasShownAssumptions = true
            // A pass that found nothing, or failed, must never block the
            // argument.
            if found.isEmpty {
                self.advanceStage()
            } else {
                Haptics.tap()
                self.phase = .assumptions(found)
            }
            self.persist()
        }
    }

    static let assumptionsEnabledKey = "assumptionsEnabled"

    /// Acknowledge the flags and carry on.
    func dismissAssumptions() {
        dispute.acknowledgeAllFlags()
        advanceStage()
    }

    // MARK: - Checklist

    func answer(_ claim: Claim, agrees: Bool) {
        dispute.setAgreement(agrees, for: currentParty, claimID: claim.id)
        Haptics.selection()
        persist()
    }

    // MARK: - Storage

    func persist() {
        try? store?.save(dispute)
    }

    /// Removes everything stored on the device and starts fresh.
    func startOver() {
        try? store?.deleteEverything()
        cancelEngineWork()
        #if DEBUG
        // A debug transcript is about one argument. Carrying the last one's
        // prompts into the next is how you end up reading the wrong session.
        PromptLog.shared.clear()
        #endif
        // The new argument runs the way this session actually can. Defaulting to
        // assisted here handed someone with no engine a dispute that expected
        // one, and the checklist then got built from points nobody was asked for.
        dispute = Dispute(mode: engineSource == nil ? .manual : .assisted)
        forgetTheFailedPositions()
        currentParty = .a
        checklistStep = .ticking
        phase = .working
    }

    // MARK: - Stage transitions

    private func advanceStage() {
        do {
            try dispute.advance()
        } catch {
            // The button that calls this is disabled unless `canAdvance`, so a
            // throw here means the gate and the UI have drifted apart.
            assertionFailure("advanced without meeting the gate: \(error)")
            return
        }

        if stage.isPerParty {
            passPhone(to: .a)
        } else {
            currentParty = .a
            phase = .working
        }

        persist()
    }

    // MARK: - Engine

    /// Called when the checklist appears. Safe to call repeatedly.
    ///
    /// In manual mode this is instant and cannot fail — the list is built from
    /// what the two of them already typed, by the same interleave-and-deduplicate
    /// rules the engine's output goes through.
    func prepareClaimsIfNeeded() {
        guard dispute.claims.isEmpty else { return }

        guard let engineSource else {
            dispute.buildClaimsFromOwnPoints()
            persist()
            return
        }

        run("Reading both sides…") {
            guard let engine = await engineSource.provide() else {
                throw EngineError.serviceUnavailable(reason: "Dispute couldn't reach the AI")
            }
            let claims = try await engine.breakDown(
                positionA: self.dispute.positions[.a],
                positionB: self.dispute.positions[.b],
                disputeTitle: self.dispute.title
            )
            self.dispute.claims = claims
            self.dispute.failedClaimAttempts = 0
        }
    }

    /// How many words the shorter of the two positions has, for the screen that
    /// asks for more of them.
    var shortestPositionWordCount: Int {
        Party.allCases
            .map { dispute.positions[$0].split(whereSeparator: \.isWhitespace).count }
            .min() ?? 0
    }

    /// Whether the app has already asked them for more words once.
    ///
    /// The second time is the last time. Past that the app builds the checklist
    /// out of their own sentences rather than asking again — see
    /// `Dispute.buildClaimsFromPositions`.
    var hasAlreadyAskedForMore: Bool { dispute.failedClaimAttempts >= 2 }

    /// Called when the crux screen appears. Safe to call repeatedly.
    ///
    /// Does nothing in manual mode: there, the two of them write the crux, and
    /// the screen is waiting on people rather than on a model.
    func findCruxIfNeeded() {
        guard let engineSource, dispute.crux == nil else { return }
        // They answered every point the same way. A model asked for the question
        // underneath an argument that isn't there will invent one, and the
        // screen already says this plainly.
        guard !dispute.contestedClaims.isEmpty else { return }

        run("Finding the one question…") {
            guard let engine = await engineSource.provide() else {
                throw EngineError.serviceUnavailable(reason: "Dispute couldn't reach the AI")
            }
            self.dispute.crux = try await engine.findCrux(in: self.dispute)
        }
    }

    // MARK: - Naming the crux by hand

    /// A filled-in first draft for a point they split on, for them to edit.
    func draftCrux(from claim: Claim) -> Crux {
        Crux.draft(from: claim, rethinks: dispute.rethinks, keeping: dispute.capitalisedNames)
    }

    func setCrux(_ crux: Crux?) {
        dispute.crux = crux
        Haptics.tap()
        persist()
    }

    // MARK: - The write-up

    /// Called when the last screen appears. Safe to call repeatedly.
    ///
    /// Instant, and identical in both modes. A model used to be given the chance
    /// to say the same settled facts more fluently; that path is gone, so the
    /// last screen no longer waits on anything at the one moment two people have
    /// finished and want to put the phone down. See `ArgumentRecap`.
    func composeRecapIfNeeded() {
        guard dispute.recap.isEmpty else { return }
        dispute.recap = ArgumentRecap.compose(from: dispute)
        persist()
    }

    /// The whole session as plain text, for them to keep or send on.
    var transcript: String { ArgumentRecap.transcript(of: dispute) }

    #if DEBUG
    /// The same session, plus every prompt the model was given and every raw
    /// answer it gave back. Debug builds only, and never shown to anyone using
    /// the app: it exists so the prompting can be read by someone who wasn't
    /// holding the phone. See `DebugTranscript`.
    var debugTranscript: String {
        DebugTranscript.text(
            for: dispute,
            engine: engineDescription,
            device: Self.deviceDescription
        )
    }

    private static var deviceDescription: String {
        var parts = ["\(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)"]
        #if targetEnvironment(simulator)
        // The thing the simulator is pretending to be. No longer decides which
        // half of the app ran — there is only one half now — but it is still the
        // difference between a transcript taken on a 12 mini's screen and one
        // taken on a 17 Pro's, and the model runs on the CPU here either way.
        parts.append(
            "simulator as \(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown")"
        )
        #endif
        return parts.joined(separator: ", ")
    }
    #endif

    func retry() {
        guard let action = lastFailedAction else { return }
        lastFailedAction = nil
        action()
    }

    /// Finishes this session without the model.
    ///
    /// Offered on the failure screen for everything nobody in the room can fix —
    /// a spent quota, no signal, the provider being down. The quota one is why this
    /// exists: it belongs to the whole app now rather than to one person's key,
    /// so "wait and try again" can mean waiting until tomorrow, and the two
    /// people holding the phone are mid-argument tonight.
    ///
    /// Drops the engine as well as changing the mode, so nothing later in the
    /// session goes back and asks again — the crux screen especially, which is
    /// where the second identical wall used to be.
    func carryOnByHand() {
        engineSource = nil
        dispute.continueByHand()
        lastFailedAction = nil
        phase = .working
        Haptics.tap()
        persist()
    }

    /// Runs an engine call, mapping failure into `phase` rather than throwing at
    /// a view. Nothing in the UI should ever hit a dead end.
    ///
    /// `.utility`, deliberately, for every engine call in the app. At the default
    /// priority these tasks — and the llama.cpp threads they start — are
    /// scheduled as though they were the thing drawing the screen, which on a
    /// phone means the fast cores, ahead of the system's own work, with the
    /// thermal budget that implies. Somebody is waiting either way; the choice is
    /// only whether the rest of the phone waits with them. See `InferenceBudget`.
    private func run(_ message: String, _ action: @escaping () async throws -> Void) {
        guard activeTask == nil else { return }

        phase = .thinking(message)
        activeTask = Task(priority: .utility) { [weak self] in
            do {
                try await action()
                self?.activeTask = nil
                // Whatever they added worked, so the condition on the entry
                // screen has done its job and must not outlive it.
                self?.positionsThatFailed = nil
                self?.phase = .working
                self?.persist()
            } catch let error as EngineError {
                self?.activeTask = nil
                self?.lastFailedAction = { self?.run(message, action) }
                if case .notEnoughToWorkWith = error, let self {
                    dispute.failedClaimAttempts += 1
                    // Twice is enough. A third "write a bit more" is the app
                    // blaming two people for a model's limitation, and it is the
                    // same trip round the same two screens they have just made.
                    // Their own sentences make a duller checklist than drawn-out
                    // claims and a far better one than a screen with no way past.
                    if dispute.failedClaimAttempts >= 2 {
                        dispute.buildClaimsFromPositions()
                        if !dispute.claims.isEmpty {
                            positionsThatFailed = nil
                            phase = .working
                            persist()
                            return
                        }
                    }
                    positionsThatFailed = dispute.positions
                }
                self?.phase = .failed(error)
            } catch {
                self?.activeTask = nil
                self?.lastFailedAction = { self?.run(message, action) }
                self?.phase = .failed(.malformedResponse(error.localizedDescription))
            }
        }
    }
}
