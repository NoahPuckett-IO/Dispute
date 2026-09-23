import Foundation

public extension String {
    /// The same sentence with its dashes turned into ordinary punctuation.
    ///
    /// Everything a model writes here is shown to two people as the app's own
    /// words: the points on the checklist, the crux question, the write-up. The
    /// app's voice has no em dashes in it, and asking a model not to use one is
    /// a request rather than a guarantee. A 1.7B model in particular writes
    /// whatever its training data was fond of, whatever the prompt says, so the
    /// prompt asks and this enforces.
    ///
    /// Only applied to generated text. What the two people typed themselves is
    /// left exactly as they typed it, dashes and all: those are their words, and
    /// the app does not edit them.
    var withoutEmDashes: String {
        // A spaced dash is nearly always parenthetical, so a comma reads right,
        // and an unspaced one usually joins two clauses just as tightly. Spaced
        // en dashes go too; unspaced ones are left alone because those are
        // ranges, and "3–5 hours" must not become "3, 5 hours".
        var text = replacingOccurrences(of: " — ", with: ", ")
            .replacingOccurrences(of: " – ", with: ", ")
            .replacingOccurrences(of: " -- ", with: ", ")
            .replacingOccurrences(of: "—", with: ", ")

        // Tidy what that leaves behind where punctuation was already doing the
        // job. Every rule here shortens the string, so none of them can spin.
        let tidyUps = [(" ,", ","), (",,", ","), (":,", ":"), (".,", "."), ("  ", " ")]
        for (mess, fix) in tidyUps {
            while text.contains(mess) {
                text = text.replacingOccurrences(of: mess, with: fix)
            }
        }

        return text.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
    }

    /// The same sentence without the conjunction it opened on.
    ///
    /// Claims arrive attached to the sentence before them: "And if automation
    /// continues, the income will cover it", "Also their stuff is corporate
    /// slop". Nothing precedes them on a checklist, so the first word is joining
    /// them to nothing, and a point that reads like the back half of somebody
    /// else's sentence is one people skim rather than answer. Measured over 300
    /// generated claims this was 43 of them, and 43 of the 44 were "And".
    ///
    /// Done here rather than in the prompt because asking made it worse. Told
    /// not to open on "and", "but", "also" or "one might argue", the model
    /// opened 38 of 60 claims with "One might argue that", which is what naming
    /// a phrase to a model this size does. The prompt asks for one plain
    /// sentence and this makes it one.
    ///
    /// "So" is deliberately not in the list: it never once appeared as a
    /// conjunction here, and "So many people go there" would lose its meaning.
    var withoutLeadingConjunction: String {
        let text = trimmingCharacters(in: .whitespacesAndNewlines)
        // "and also" comes first: alternation is leftmost-first, so listing
        // "and" ahead of it would strip the "and" and leave the "also".
        guard let opening = text.range(
            of: #"^(?:and also|and|but|also),?\s+"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return text }

        let rest = String(text[opening.upperBound...])
        guard let first = rest.first else { return text }
        return first.uppercased() + rest.dropFirst()
    }

    /// The same sentence, ending in something.
    ///
    /// The write-up is composed on the phone out of settled facts, and every
    /// sentence in it carries its own full stop except the two that are a model's
    /// words dropped in whole: the crux question and the test. The prompt asks
    /// for a sentence and a model hands back a phrase about as often as not, so
    /// those two run straight into whatever the recap says next.
    ///
    /// From the session of 6 August 2026: *"What's left is one question: Does FDT
    /// produce better outcomes than other decision theories on a subset problem
    /// of the prisoners dilemma Matthew adelstein says FDT does not make
    /// meaningful claims."* Two sentences welded into one on the last screen of
    /// the app, which is the screen the whole thing is for.
    ///
    /// Added rather than replaced, so a model that did punctuate is left alone,
    /// and closing quotes and brackets are stepped over on the way in — a stop
    /// belongs after `(like this)`, not inside it.
    func ending(with mark: Character) -> String {
        let text = trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = text.reversed().first(where: { !")]”’\"'".contains($0) })
        else { return text }
        return ".?!:;".contains(last) ? text : text + String(mark)
    }
}
