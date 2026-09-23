import Foundation

/// Something a position rests on without ever saying so.
///
/// This replaced fact checking, and the reason is worth keeping written down. A
/// fact check asks the model "is this true?", which is a question about the world
/// — so it needs knowledge the model may not have, it is wrong in a way nobody in
/// the room can check, and being wrong about it hands one side a weapon. Every
/// version of that feature measured badly: the flags were confident, frequent,
/// and sometimes aimed at statements of value that cannot be true or false at all.
///
/// An assumption is a question about the *text*, which is the thing the model can
/// actually see. "You're treating it as given that the school would take them in
/// September" needs no reference to settle and cannot be a verdict on anybody: it
/// names an unstated step and hands it back to the two people, who between them
/// know whether it holds. It is also the more useful half. Arguments that go in
/// circles usually do it because each side is standing on something the other has
/// never agreed to, and neither has noticed which thing that is.
///
/// Never phrased as a correction, for the same reason the fact flags weren't: the
/// app has no side and cannot be seen to take one.
public struct AssumptionFlag: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    /// Whose position it came out of.
    public var party: Party
    /// The words that rest on it, exactly as they were written.
    ///
    /// Exact because the card sits next to what they typed, and a paraphrase
    /// there reads as the app putting words in somebody's mouth.
    public var quote: String
    /// What is being taken as given, in one plain sentence.
    ///
    /// Written as a description of the argument's shape, never as a challenge.
    /// "This takes for granted that …", not "But you haven't shown that …".
    public var assumption: String
    /// Set once someone has looked at it, so it stops interrupting.
    public var isAcknowledged: Bool

    public init(
        id: UUID = UUID(),
        party: Party,
        quote: String,
        assumption: String,
        isAcknowledged: Bool = false
    ) {
        self.id = id
        self.party = party
        self.quote = quote
        self.assumption = assumption
        self.isAcknowledged = isAcknowledged
    }

    /// Whether this is worth putting on screen.
    ///
    /// A small model asked for the assumption under a sentence will sometimes
    /// hand the sentence back, and an "assumption" that is a copy of the quote
    /// tells nobody anything — it is the model saying "you assume what you said".
    /// The other failure is a single word, which reads as a fragment of a thought
    /// rather than one.
    public var isUsable: Bool {
        let assumption = assumption.trimmed
        guard assumption.count >= 20 else { return false }
        guard assumption.split(whereSeparator: \.isWhitespace).count >= 4 else { return false }
        return !assumption.localizedCaseInsensitiveContains(quote.trimmed)
            || quote.trimmed.count < 12
    }
}
