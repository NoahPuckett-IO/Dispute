import Foundation

/// The written record of an argument, built from everything the two of them did.
///
/// Composed on the phone, with no model involved — and now the only version
/// there is. A model used to be handed these same settled facts and asked to
/// say them again in better sentences. That is gone, for three reasons that all
/// point the same way: the last screen costs nothing and appears instantly; it
/// says only things that actually happened, which no summariser can promise; and
/// the moment two people finish an argument is the worst moment in the app to
/// show them a spinner.
public enum ArgumentRecap {

    // MARK: - The paragraph on the last screen

    /// Four or five plain sentences: what they argued about, how much of it
    /// they turned out to agree on, the one question left, and what each of them
    /// said would change their mind.
    ///
    /// Written in the second person, because both of them are reading it at the
    /// same time on the same phone — "you agreed on five of seven" is addressed
    /// to the pair, and there is deliberately no sentence addressed to one of
    /// them.
    public static func compose(from dispute: Dispute) -> String {
        var sentences: [String] = []

        let title = dispute.title.trimmed
        sentences.append(
            title.isEmpty
                ? "You worked this through together."
                : "You started on “\(title)”."
        )

        if let counted = countedPoints(in: dispute) { sentences.append(counted) }
        if let looked = secondLooks(in: dispute) { sentences.append(looked) }

        if let crux = dispute.crux, crux.isUsable {
            // A question mark, because it is one, and because the recap runs on
            // into "<name> says …" immediately afterwards.
            sentences.append("What's left is one question: \(crux.question.ending(with: "?"))")
            sentences.append(contentsOf: whereTheyLand(on: crux, in: dispute))
            if crux.needsConversation {
                sentences.append(
                    "That one isn't settled by either of you being right, so it stays a conversation."
                )
            }
            // The last sentence of the paragraph, deliberately. The write-up is
            // read top to bottom by two people who have finished and want to
            // know what happens now, and this is the only sentence in it that
            // says.
            if crux.hasTest {
                sentences.append("What settles it: \(crux.test.ending(with: "."))")
            }
        } else if dispute.contestedClaims.isEmpty && !dispute.claims.isEmpty {
            sentences.append(
                "Nothing on the list still splits you. Whatever the argument was about, it isn't in these points."
            )
        }

        sentences.append(contentsOf: whatWouldChangeTheirMinds(in: dispute))

        return sentences.joined(separator: " ")
    }

    private static func countedPoints(in dispute: Dispute) -> String? {
        let total = dispute.claims.count
        guard total > 0 else { return nil }

        let shared = dispute.sharedClaims.count
        if shared == total {
            return "You went through \(total) points and answered every one of them the same way."
        }
        return "You went through \(total) points and answered \(shared) of them the same way."
    }

    private static func secondLooks(in dispute: Dispute) -> String? {
        let both = Party.allCases.allSatisfy { dispute.rethinks[$0]?.isComplete == true }
        let either = Party.allCases.contains { dispute.rethinks[$0]?.isComplete == true }

        if both {
            return "You each then made the case for a point you'd crossed out."
        } else if either {
            let party = Party.allCases.first { dispute.rethinks[$0]?.isComplete == true }!
            return "\(dispute.name(for: party)) made the case for a point they'd crossed out."
        }
        return nil
    }

    private static func whereTheyLand(on crux: Crux, in dispute: Dispute) -> [String] {
        let names = dispute.capitalisedNames
        return Party.allCases.compactMap { party in
            let stance = crux.positions[party].trimmed
            guard !stance.isEmpty else { return nil }
            return "\(dispute.name(for: party)) says \(stance.midSentence(keeping: names))."
        }
    }

    private static func whatWouldChangeTheirMinds(in dispute: Dispute) -> [String] {
        Party.allCases.compactMap { party in
            guard let clause = dispute.rethinks[party]?.conditionClause, !clause.isEmpty
            else { return nil }
            return "\(dispute.name(for: party)) would change their mind if \(clause)."
        }
    }

    // MARK: - The whole thing, for taking away

    /// Everything the session produced, as plain text to copy or send.
    ///
    /// Sections are dropped rather than left empty, so a short argument gives a
    /// short record instead of a form with blanks in it.
    public static func transcript(of dispute: Dispute) -> String {
        var blocks: [String] = []

        let title = dispute.title.trimmed
        blocks.append(
            """
            \(title.isEmpty ? "An argument" : title)
            \(dispute.name(for: .a)) and \(dispute.name(for: .b)) · \
            \(dispute.createdAt.formatted(date: .abbreviated, time: .omitted))
            """
        )

        let recap = dispute.recap.trimmed.isEmpty ? compose(from: dispute) : dispute.recap.trimmed
        blocks.append(recap)

        let positions = Party.allCases.compactMap { party -> String? in
            let text = dispute.positions[party].trimmed
            guard !text.isEmpty else { return nil }
            return "\(dispute.name(for: party)): \(text)"
        }
        if !positions.isEmpty {
            blocks.append(section("WHAT YOU EACH SAID", lines: positions))
        }

        let agreed = dispute.sharedClaims.map { "• \($0.text)" }
        if !agreed.isEmpty {
            blocks.append(section("WHAT YOU BOTH SIGNED UP TO", lines: agreed))
        }

        let contested = dispute.contestedClaims.map { "• \($0.text)" }
        if !contested.isEmpty {
            blocks.append(section("WHERE YOU SPLIT", lines: contested))
        }

        if let crux = dispute.crux, crux.isUsable {
            blocks.append(
                section(
                    "THE CRUX",
                    lines: [crux.question.ending(with: "?")] + Party.allCases.compactMap { party in
                        let stance = crux.positions[party].trimmed
                        return stance.isEmpty ? nil : "\(dispute.name(for: party)): \(stance)"
                    }
                )
            )
            // Its own section rather than a line under the crux. This is the part
            // somebody goes back to the transcript for a week later, and a
            // heading is what makes it findable.
            if crux.hasTest {
                blocks.append(section("HOW TO SETTLE IT", lines: [crux.test]))
            }
        }

        let tests = Party.allCases.compactMap { party -> String? in
            guard let rethink = dispute.rethinks[party], rethink.isComplete else { return nil }
            return "\(dispute.name(for: party)): \(rethink.changeCondition)"
        }
        if !tests.isEmpty {
            blocks.append(section("WHAT WOULD CHANGE YOUR MINDS", lines: tests))
        }

        return blocks.joined(separator: "\n\n")
    }

    private static func section(_ heading: String, lines: [String]) -> String {
        ([heading] + lines).joined(separator: "\n")
    }
}
