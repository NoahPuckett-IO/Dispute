import Foundation

/// One person's second look at a point they crossed out.
///
/// Ticking a list tells the app *where* two people split. It does not tell
/// anyone *why*, and without the why the question underneath is guesswork — the
/// app was naming cruxes from nothing but which rows differed.
///
/// So each person, still on their own turn, picks one point they rejected and
/// answers two questions about it:
///
/// - `bestCase` — the strongest argument *for* the thing they just crossed out.
///   Written by the person who disagrees with it, which is the whole trick: you
///   cannot make someone's case badly and still believe you understood it.
/// - `changeCondition` — what would have to be true for them to tick it after
///   all. An answer here turns "we disagree" into a test with a result, and it
///   is the single most useful sentence either of them writes.
///
/// The app never uses the word for either of these on screen. Nobody
/// mid-argument wants to be told they are doing an exercise.
public struct Rethink: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID { claimID }
    /// The point they crossed out and then argued for.
    public let claimID: UUID
    /// The best case for it, in the words of the person who rejected it.
    public var bestCase: String
    /// What would have to be true for them to change their answer.
    public var changeCondition: String

    public init(claimID: UUID, bestCase: String = "", changeCondition: String = "") {
        self.claimID = claimID
        self.bestCase = bestCase
        self.changeCondition = changeCondition
    }

    /// Both answers written. Blank fields are the same as no answer — a screen
    /// that accepts a space bar has not been answered.
    public var isComplete: Bool {
        !bestCase.trimmed.isEmpty && !changeCondition.trimmed.isEmpty
    }

    /// `changeCondition` as a clause that can be folded into a sentence.
    ///
    /// The field it comes from is prompted with "If…", so most people write
    /// "If the quotes come back over three thousand" — and every sentence the
    /// app builds around it already supplies the "if". Without this the write-up
    /// reads "Alex would change their mind if if the quotes come back…", which
    /// is the first thing anyone notices on the last screen of the app.
    ///
    /// Only a leading "if" is dropped, and only when it is a whole word. "If"
    /// appearing anywhere else in the sentence is theirs.
    public var conditionClause: String {
        let text = changeCondition.trimmed
        guard let space = text.firstIndex(of: " "),
              text[text.startIndex..<space].lowercased() == "if"
        else { return text.midSentence }

        return String(text[text.index(after: space)...]).midSentence
    }
}
