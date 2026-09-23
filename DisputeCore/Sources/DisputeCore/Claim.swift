import Foundation

/// A single checkable statement drawn out of someone's position.
///
/// Claims are the heart of the app. Both people work through the same list and
/// tick the ones they agree with; the ones where their answers differ are the
/// disagreement, and everything else is common ground they usually didn't know
/// they had.
public struct Claim: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var text: String
    /// Which position this was drawn from. Never shown before both have answered
    /// — knowing whose claim it is biases the answer.
    public var origin: Party
    /// Each person's answer, `nil` until they've given one.
    public var agreement: PartyPair<Bool?>

    public init(
        id: UUID = UUID(),
        text: String,
        origin: Party,
        agreement: PartyPair<Bool?> = PartyPair(both: nil)
    ) {
        self.id = id
        self.text = text
        self.origin = origin
        self.agreement = agreement
    }

    public var isAnsweredByBoth: Bool {
        agreement.a != nil && agreement.b != nil
    }

    public func isAnswered(by party: Party) -> Bool {
        agreement[party] != nil
    }

    /// Both answered, and they differ. This is what a disagreement looks like.
    public var isContested: Bool {
        guard let a = agreement.a, let b = agreement.b else { return false }
        return a != b
    }

    /// Both ticked it. Common ground.
    public var isShared: Bool {
        agreement.a == true && agreement.b == true
    }

    /// Both rejected it — also agreement, just in the negative.
    public var isMutuallyRejected: Bool {
        agreement.a == false && agreement.b == false
    }

    public mutating func setAgreement(_ agrees: Bool, for party: Party) {
        agreement[party] = agrees
    }
}

public extension Claim {
    /// A list this short can't find a crux, so dropping points for *resembling*
    /// each other stops here. A restatement is a wasted slot; too few points is
    /// a broken stage.
    ///
    /// It is a floor under one rule and not under the others. A point that is
    /// not a claim at all — somebody's own sentence handed back, or a sentence
    /// still written as them — is dropped however short the list gets, and so is
    /// a point already on it word for word. See `deduplicated`.
    static let minimumUsableClaims = 4

    /// Alternates the two batches so the list doesn't read as "their points,
    /// then mine" — which would give the hidden origin away immediately.
    ///
    /// Used by both modes: the assisted path generates each side separately, and
    /// the manual path collects each side separately.
    static func interleave(_ first: [Claim], _ second: [Claim]) -> [Claim] {
        var result: [Claim] = []
        for index in 0..<max(first.count, second.count) {
            if index < first.count { result.append(first[index]) }
            if index < second.count { result.append(second[index]) }
        }
        return result
    }

    /// Drops near-duplicates, keeping the first of each.
    ///
    /// Each side's claims are generated in a separate call, so neither knows
    /// what the other produced — both can draw the same idea out of the same
    /// sentence.
    ///
    /// Pass the two positions as `orEchoing` wherever the list came from a
    /// model, and never where the two people typed the points themselves: in
    /// manual mode their own words are exactly what belongs on the list.
    ///
    /// Three rules, and only the last of them has a floor under it.
    ///
    /// The floor used to sit over all three, and be read before each point
    /// rather than after the filtering: once the list could no longer afford a
    /// drop, everything left in it was kept unexamined. A real session ended up
    /// with the same sentence on the checklist twice and with each person being
    /// asked whether they agreed with their own position, because the four
    /// points that happened to come later got a free pass. Filling a list to
    /// four with points neither of them can answer buys one screen at the cost
    /// of every stage that reads it: the crux comes out of however they ticked
    /// their own words, and the write-up reports that as their disagreement.
    static func deduplicated(
        _ claims: [Claim],
        orEchoing positions: [String] = [],
        similarity threshold: Double = 0.6
    ) -> [Claim] {
        // Rule one, no floor: not a claim at all.
        let usable = claims.filter { claim in
            guard !positions.isEmpty else { return true }
            return !isInSomeonesVoice(claim.text)
                && !positions.contains { isEcho(claim.text, of: $0) }
        }

        var kept: [Claim] = []
        var dropped = 0

        for claim in usable {
            // Rule two, no floor: already on the list. Two rows differing only
            // in a capital letter are indefensible at any length.
            if kept.contains(where: { isTheSameSentence($0.text, claim.text) }) {
                dropped += 1
                continue
            }

            // Rule three, floored: merely resembles something already kept.
            let wouldGoTooLow = usable.count - dropped <= minimumUsableClaims
            let isRestatement = kept.contains { overlap($0.text, claim.text) >= threshold }

            if isRestatement && !wouldGoTooLow {
                dropped += 1
            } else {
                kept.append(claim)
            }
        }
        return kept
    }

    /// The same point written twice, allowing for a capital letter, a full
    /// stop, or a stray run of spaces between them.
    ///
    /// The two calls are made independently and can land on the same sentence,
    /// and did: "They're green and they rejected me from a job" and "they're
    /// green and they rejected me from a job" both reached a checklist.
    private static func isTheSameSentence(_ first: String, _ second: String) -> Bool {
        func flattened(_ text: String) -> String {
            let letters = text.lowercased().unicodeScalars.map {
                CharacterSet.alphanumerics.contains($0) ? Character($0) : " "
            }
            return String(letters).split(separator: " ").joined(separator: " ")
        }
        return flattened(first) == flattened(second)
    }

    /// Whether a claim is nothing but somebody's own sentence handed back.
    ///
    /// Handed a long, rambling position, this model sometimes stops drawing
    /// claims out of it and starts copying lines out of it instead. That is not
    /// a claim, and the list it produces is worse than a short one: a real
    /// session came back with two of the six points lifted word for word from
    /// what the two of them had typed, so each of them was asked whether they
    /// agreed with their own sentence, and each of them said no.
    ///
    /// Measured by how much of the claim came from the position rather than by
    /// the Jaccard score used above, and the difference is the whole reason this
    /// works. A position is usually far longer than any one claim drawn from it,
    /// so the union is dominated by words the claim was never going to contain
    /// and every echo scores low: the copied points above came out at 0.21 and
    /// 0.50, below the threshold that catches genuine restatements. What makes a
    /// claim an echo is that it adds nothing, and what makes a claim a claim is
    /// the words it adds — "the key factor in whether", "depends on", "might be
    /// different". On that session the three real points scored 0.31 or less
    /// here and all three echoes scored 0.94 or more, which is the margin this
    /// threshold sits in.
    ///
    /// ## Why there are two measures
    ///
    /// Read the paragraph above again and notice the assumption holding it up:
    /// *a position is usually far longer than any one claim drawn from it*. When
    /// that is true the borrowed-words ratio is a good instrument. When it is
    /// false the instrument reports nonsense, and a session in August 2026 was
    /// the bill for that.
    ///
    /// Two people argued about functional decision theory in one dense sentence
    /// each. The model did its job and returned six clean, distinct claims. Four
    /// of them were thrown away here, twice, and the stage failed both times —
    /// so the app fell back to putting their two raw positions on the checklist,
    /// which is the precise disaster this rule exists to prevent, reached by the
    /// rule itself.
    ///
    /// The worst of them: the position said *it assumes agents **can** calculate
    /// counterfactual outcomes*, and the claim drawn from it was *agents
    /// **cannot** calculate counterfactual outcomes*. Six of its seven words came
    /// from the position, which scores 0.857 and dies. It is the exact negation
    /// of the position and the most answerable row that list was ever going to
    /// have. A short position gives a claim nowhere to get its words from except
    /// the position, so "borrowed nearly all its words" stops meaning "adds
    /// nothing" and starts meaning "is about the same subject".
    ///
    /// So the ratio is only consulted where its assumption holds — where the
    /// position has room to have said something the claim did not. Below that,
    /// what is left is the thing the rule was always really about: a sentence
    /// lifted rather than a claim drawn. That is `longestRunCoverage`, which asks
    /// whether a run of the claim's own words appears in the position in order,
    /// and it catches a word-for-word copy at any length — including a whole
    /// position handed back, which is the case that started all of this.
    static func isEcho(_ text: String, of position: String, threshold: Double = 0.85) -> Bool {
        let claimWords = meaningfulWords(text)
        guard !claimWords.isEmpty else { return false }

        // Lifted rather than drawn, whatever the lengths involved.
        if longestRunCoverage(of: text, in: position) >= threshold { return true }

        // And the borrowed-words ratio, where the position is long enough for it
        // to distinguish anything.
        let positionWords = meaningfulWords(position)
        guard Double(positionWords.count)
                >= Double(claimWords.count) * roomToHaveSaidSomethingElse
        else { return false }

        let borrowed = claimWords.intersection(positionWords).count
        return Double(borrowed) / Double(claimWords.count) >= threshold
    }

    /// How much longer than a claim a position has to be before "this claim
    /// borrowed most of its words" tells you anything.
    ///
    /// Three, from the sessions on both sides of it. The rambling vanilla
    /// position that forced this rule runs about four times the length of the
    /// claims drawn from it, and the ratio separates copies from claims cleanly
    /// there. The one-sentence FDT positions run about twice, and it separates
    /// nothing: every real claim scored between 0.8 and 1.0.
    private static let roomToHaveSaidSomethingElse = 3.0

    /// The longest run of the claim's words that appears, in order and unbroken,
    /// in the position — as a fraction of the claim.
    ///
    /// Word-for-word is the thing being looked for, so word order is the thing
    /// being measured. A claim drawn out of a position reorders it, drops its
    /// framing and adds a verb of its own; a claim lifted out of one does not
    /// have to, and its giveaway is a long stretch that survives intact.
    ///
    /// Stems and lowercases but keeps the small words, unlike `meaningfulWords`.
    /// "on the prisoners dilemma" and "in the prisoners dilemma" differ by
    /// exactly the word that would be thrown away as noise, and that difference
    /// is the whole signal here.
    static func longestRunCoverage(of text: String, in position: String) -> Double {
        let claim = orderedWords(text)
        let source = orderedWords(position)
        guard !claim.isEmpty, !source.isEmpty else { return 0 }

        // Longest common substring over words. The lists are a sentence and a
        // paragraph, so the quadratic version is the right one.
        var previous = [Int](repeating: 0, count: source.count + 1)
        var longest = 0

        for claimIndex in 1...claim.count {
            var current = [Int](repeating: 0, count: source.count + 1)
            for sourceIndex in 1...source.count
            where claim[claimIndex - 1] == source[sourceIndex - 1] {
                current[sourceIndex] = previous[sourceIndex - 1] + 1
                longest = max(longest, current[sourceIndex])
            }
            previous = current
        }
        return Double(longest) / Double(claim.count)
    }

    private static func orderedWords(_ text: String) -> [String] {
        let cleaned = text.lowercased().unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : " "
        }
        return String(cleaned).split(separator: " ").map { stem(String($0)) }
    }

    /// Whether a generated claim is still written as the person who holds it.
    ///
    /// "I think vanilla is better because it doesn't make me thirsty" is not a
    /// copy of anything and survives every similarity measure, and it is still
    /// unusable: the two of them tick this list without being told which points
    /// came from which side, and the first two words say. The prompt asks for
    /// the third person and this model agrees and then does it anyway, which is
    /// the same reason `withoutEmDashes` exists.
    ///
    /// Every first person word counts, wherever it falls. An earlier version
    /// read only the opening, on the reasoning that an "I" further in was
    /// usually inside something one of them had said. A real session showed how
    /// often that is wrong: "I like the smores frappe" opens with a pronoun this
    /// list of openings did not have, "And I feel like there's a wealth
    /// disparity there" hides the same opening behind a conjunction, and
    /// "They're green and they rejected me from a job" reaches the far side of
    /// the sentence before it gives itself away. All three went on a checklist.
    ///
    /// The quoting exception survives, narrowed to what it was always about:
    /// words actually inside quotation marks.
    static func isInSomeonesVoice(_ text: String) -> Bool {
        outsideQuotations(text)
            .lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split { !$0.isLetter && $0 != "'" }
            .contains { firstPerson.contains(String($0)) }
    }

    /// Both numbers, because a claim is a thing either of them could answer and
    /// "us" gives away which side wrote it exactly as surely as "I" does.
    private static let firstPerson: Set<String> = [
        "i", "i'm", "i've", "i'd", "i'll",
        "me", "my", "mine", "myself",
        "we", "we're", "we've", "we'd", "we'll",
        "us", "our", "ours", "ourselves",
    ]

    /// The claim with anything inside double quotation marks removed, so that
    /// quoting one of them stays allowed: `Saying "I don't need water" is a
    /// claim about thirst` is a claim, in nobody's voice.
    ///
    /// Single quotes are left alone, because there is no telling one from the
    /// apostrophe in "they're". An opening mark with no closing one gives back
    /// the whole claim rather than swallowing the rest of it, which would hide
    /// a first person behind a stray quote.
    private static func outsideQuotations(_ text: String) -> String {
        let pairs: [Character: Character] = ["\"": "\"", "\u{201C}": "\u{201D}"]
        var kept = ""
        var closing: Character?

        for character in text {
            if let expected = closing {
                if character == expected { closing = nil }
            } else if let expected = pairs[character] {
                closing = expected
            } else {
                kept.append(character)
            }
        }
        return closing == nil ? kept : text
    }

    /// Jaccard similarity over meaningful words: shared words divided by the
    /// total distinct words across both.
    ///
    /// An earlier version divided by the *smaller* set, which meant any short
    /// claim whose words appeared in a longer one scored 1.0. It cut a
    /// six-point list to two. Dividing by the union keeps opposing claims about
    /// the same subject — the most valuable rows in the list — while still
    /// catching genuine restatements.
    static func overlap(_ first: String, _ second: String) -> Double {
        let a = meaningfulWords(first)
        let b = meaningfulWords(second)
        guard !a.isEmpty, !b.isEmpty else { return 0 }

        let shared = a.intersection(b).count
        let total = a.union(b).count
        return Double(shared) / Double(total)
    }

    private static let ignored: Set<String> = [
        "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
        "of", "to", "in", "on", "at", "for", "with", "and", "or", "but",
        "that", "this", "these", "those", "it", "its", "as", "than", "then",
        "more", "most", "less", "least", "can", "could", "would", "should",
        "do", "does", "did", "have", "has", "had", "will", "not",
    ]

    private static func meaningfulWords(_ text: String) -> Set<String> {
        let cleaned = text.lowercased().unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : " "
        }
        let words = String(cleaned).split(separator: " ").map { stem(String($0)) }
        return Set(words).subtracting(ignored)
    }

    /// Crudely strips a trailing plural or third-person "s" so "happens" and
    /// "happen" count as the same word. Not linguistics — just enough that a
    /// restatement doesn't slip through on grammar alone.
    private static func stem(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") else { return word }
        return String(word.dropLast())
    }
}