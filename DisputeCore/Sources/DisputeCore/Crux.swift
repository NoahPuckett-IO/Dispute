import Foundation

/// A single identified point of genuine disagreement, and the thing that would
/// settle it.
///
/// Phrased as a neutral question both people can look at together, rather than
/// as a verdict about who is right — the app never takes a side.
///
/// ## Why there is exactly one, and why it carries a test
///
/// This is a *double* crux, in the sense the technique means: not "a thing they
/// disagree about" but the one question where **both** of them would move. A
/// question only one person's mind hangs on is not a crux, it is that person's
/// objection — settle it and the argument carries on exactly as before, which is
/// the failure this app exists to stop.
///
/// So the app collects, blind and separately, what each of them said would change
/// their mind (`Rethink.changeCondition`), and the crux is where those two answers
/// meet. `test` is what falls out of that meeting: the one concrete thing they
/// could go and find out that would move whichever of them is wrong.
///
/// Without `test` the app named the disagreement and stopped, which is a
/// diagnosis. Two people who came in stuck went out stuck, holding a better
/// description of being stuck. The test is the part that makes the session worth
/// having: it turns "we disagree about whether the raise covers the move" into
/// "write down a year of costs and look at the number", which is a thing that can
/// actually happen on a Tuesday.
public struct Crux: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    /// The disagreement, stated as a question. "Does taking the job require
    /// moving?" not "Noah is wrong about the commute."
    public var question: String
    /// Where each party lands on that question.
    public var positions: PartyPair<String>
    /// The one thing that would settle it, for both of them.
    ///
    /// Concrete and doable: a number to look up, a person to ask, a thing to try
    /// for a fortnight. Not "communicate more" and not "do more research", which
    /// are the two ways a model fills this field when it has nothing.
    ///
    /// Empty is allowed and honest — some disagreements have no test, and
    /// `needsConversation` is usually true when this is blank.
    public var test: String
    /// Set when the crux is about how the parties feel or relate rather than
    /// about a checkable fact. Surfacing "I don't think you respect me" bluntly
    /// can escalate, so the UI softens its framing when this is true.
    public var needsConversation: Bool

    public init(
        id: UUID = UUID(),
        question: String,
        positions: PartyPair<String>,
        test: String = "",
        needsConversation: Bool = false
    ) {
        self.id = id
        self.question = question
        self.positions = positions
        self.test = test
        self.needsConversation = needsConversation
    }

    /// Read by hand so a crux saved before `test` existed still loads. A decode
    /// failure here is thrown away as "no saved session" by `DisputeStore`, which
    /// would cost somebody the argument they were in the middle of.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        question = try container.decode(String.self, forKey: .question)
        positions = try container.decode(PartyPair<String>.self, forKey: .positions)
        test = try container.decodeIfPresent(String.self, forKey: .test) ?? ""
        needsConversation = try container.decodeIfPresent(Bool.self, forKey: .needsConversation) ?? false
    }

    /// Discards an answer that is not usable as a question.
    ///
    /// Engines are asked for one crux and occasionally return a blank string, or
    /// the instruction they were given back at us. A card with nothing on it is
    /// worse than the screen saying it found nothing, because the second has a
    /// way forward and the first looks like a crash.
    public var isUsable: Bool {
        question.trimmed.count >= 8
    }

    /// Whether this actually is a double crux rather than one side's objection.
    ///
    /// Both stances present and different. A crux where the model wrote the same
    /// sentence into both slots is one it could not find a real split for, and
    /// showing it as "here is where you two differ" is the app inventing a
    /// disagreement to justify the screen.
    public var isShared: Bool {
        let a = positions[.a].trimmed
        let b = positions[.b].trimmed
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a.lowercased() != b.lowercased()
    }

    /// Whether there is something to go and do about it.
    ///
    /// Guards against the two sentences a model writes when it has no test:
    /// an instruction to talk more, or an instruction to research more. Both are
    /// what the two of them were already failing to do.
    public var hasTest: Bool {
        let text = test.trimmed
        guard text.count >= 15 else { return false }
        let empty = [
            "communicate", "talk more", "more research", "do research",
            "further research", "discuss it", "have a conversation", "more information",
        ]
        let lowered = text.lowercased()
        return !empty.contains { lowered.contains($0) }
    }

    /// A starting point for the pair to edit, built from a point they answered
    /// differently.
    ///
    /// Manual mode asks two people mid-argument to name the question underneath
    /// their disagreement, which is the hardest thing the app asks of anyone.
    /// Handing them a filled-in first draft — the point they split on, turned
    /// into a question, with each side's answer already in — turns writing from
    /// scratch into editing. Every field stays editable.
    ///
    /// Where someone has said what would change their mind about this exact
    /// point, that sentence is the better answer to put in front of them than
    /// "Yes" or "No": it is what they actually think, in their own words.
    ///
    /// `names` is what the two of them capitalise, so a point that opens on one
    /// is not folded into the question with a small letter. `Dispute` has it.
    public static func draft(
        from claim: Claim,
        rethinks: PartyPair<Rethink?> = PartyPair(both: nil),
        keeping names: Set<String> = []
    ) -> Crux {
        Crux(
            question: "Is it true that \(claim.text.midSentence(keeping: names))?",
            positions: PartyPair(
                a: position(for: .a, on: claim, rethinks: rethinks),
                b: position(for: .b, on: claim, rethinks: rethinks)
            ),
            test: draftTest(rethinks: rethinks)
        )
    }

    /// A first draft of the test, built from what the two of them already wrote.
    ///
    /// Manual mode has no model to write one, and a blank box on the hardest
    /// field of the hardest screen gets left blank. But the two of them have
    /// each already answered "what would change my mind", blind and separately —
    /// which is the raw material a test is made of. Splicing both answers
    /// together gives them something to cut down rather than something to start.
    ///
    /// Both, or nothing. One person's condition alone is not a double crux, and
    /// offering it as one would teach exactly the wrong thing about what they are
    /// looking for.
    private static func draftTest(rethinks: PartyPair<Rethink?>) -> String {
        let conditions = Party.allCases.compactMap { party -> String? in
            guard let clause = rethinks[party]?.conditionClause, !clause.isEmpty else { return nil }
            return clause
        }
        guard conditions.count == Party.allCases.count else { return "" }
        return "Find out whether \(conditions[0]), and whether \(conditions[1])."
    }

    private static func position(
        for party: Party,
        on claim: Claim,
        rethinks: PartyPair<Rethink?>
    ) -> String {
        if let rethink = rethinks[party],
           rethink.claimID == claim.id,
           !rethink.conditionClause.isEmpty {
            return "No, unless \(rethink.conditionClause)"
        }
        return switch claim.agreement[party] {
        case true: "Yes"
        case false: "No"
        case nil: ""
        }
    }
}

extension String {
    /// A stance with the model's own attribution taken off the front.
    ///
    /// The crux prompt calls the two of them Person A and Person B, because
    /// their names are never sent to a model. Asked where each of them lands, a
    /// model answers in the third person as often as not — "Person B believes
    /// that visual appeal matters more" — and every screen that shows a stance
    /// has already put the name beside it. The last screen read "Noah says
    /// person B believes that visual appeal matters more", which sounds like a
    /// third person is in the room, and the crux card and the shared transcript
    /// had the same doubled attribution in them.
    ///
    /// The prompt asks for the bare stance. This is what makes it true, because
    /// a 1.7B model treats a prompt as a suggestion.
    ///
    /// Only a leading subject and its reporting verb are removed, and only
    /// together. "Believes" anywhere else in the sentence is the model saying
    /// what someone thinks, which is the answer, not a label on it.
    public var withoutAttribution: String {
        let text = trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = #"(?:person [ab]|the (?:first|second) person|this person|they)"#
        let verb = #"(?:believes?|thinks?|says?|argues?|holds?|feels?|maintains?|claims?|considers?)"#

        guard let attribution = text.range(
            of: #"^\#(subject)\s+\#(verb)\s+(?:that\s+)?"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return text }

        let stance = String(text[attribution.upperBound...])
        guard let first = stance.first else { return text }
        return first.uppercased() + stance.dropFirst()
    }

    /// Lowercases the first letter and drops a trailing full stop, so a claim
    /// reads as the middle of a question or a clause rather than a whole
    /// sentence jammed into one.
    var midSentence: String {
        var text = trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix(".") || text.hasSuffix("?") || text.hasSuffix("!") {
            text.removeLast()
        }
        guard let first = text.first, first.isUppercase else { return text }
        // Only when the word is not an acronym or a name we'd be mangling.
        let firstWord = text.split(separator: " ").first.map(String.init) ?? text
        guard firstWord.dropFirst().contains(where: \.isLowercase) else { return text }
        return first.lowercased() + text.dropFirst()
    }

    /// The same, for a sentence that might open on a name.
    ///
    /// The plain version reads the first word alone, and a first word with a
    /// small letter anywhere in it is taken for an ordinary one. So a crux that
    /// landed on "Starbucks is good because it's a well-known brand" reached the
    /// last screen as "Henry says starbucks is good", which is the app
    /// misspelling the thing the two of them spent the session arguing about.
    ///
    /// `names` is what the two of them capitalise, taken from their own words by
    /// `capitalisedNames`. Nothing is guessed and no list is kept: a word is a
    /// name here only because one of them wrote it as one.
    func midSentence(keeping names: Set<String>) -> String {
        let plain = midSentence
        let firstWord = plain.prefix { !$0.isWhitespace }
            .filter { $0.isLetter || $0.isNumber }
            .lowercased()

        guard names.contains(firstWord) else { return plain }
        // Only the opening letter was ever going to change, so restoring it is
        // the whole of the difference. The trailing full stop still goes.
        guard let first = trimmingCharacters(in: .whitespacesAndNewlines).first else { return plain }
        return first.uppercased() + plain.dropFirst()
    }

    /// Every word these two write as a name.
    ///
    /// A word capitalised anywhere other than the start of a sentence was
    /// capitalised deliberately: "Starbucks" in "Is Starbucks good", "Alex" in
    /// "moving would suit Alex". A word capitalised only because a sentence
    /// began there tells us nothing and is not collected, so an argument that
    /// opens "Cost is what matters" does not go on to protect "Cost".
    /// A line break starts a sentence too. Positions, points and claims are
    /// gathered onto separate lines and most of them are one sentence with no
    /// full stop on the end, so reading them as continuous prose would take the
    /// opening word of every line for a name.
    var capitalisedNames: Set<String> {
        var names: Set<String> = []

        for line in split(whereSeparator: \.isNewline) {
            var startsSentence = true

            for word in line.split(whereSeparator: \.isWhitespace) {
                let letters = word.filter { $0.isLetter || $0.isNumber }
                // Punctuation on its own, a bullet, a stray dash: carries no
                // capital of its own and does not end the sentence either.
                guard let first = letters.first else { continue }

                if !startsSentence, first.isUppercase {
                    names.insert(letters.lowercased())
                }
                startsSentence = word.contains { ".?!:".contains($0) }
            }
        }
        return names
    }
}
