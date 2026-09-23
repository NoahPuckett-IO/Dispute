import XCTest
@testable import DisputeCore

/// The app's voice has no dashes in it, and a model will write them anyway.
/// See `String.withoutEmDashes`.
final class PlainPunctuationTests: XCTestCase {

    func testASpacedEmDashBecomesAComma() {
        XCTAssertEqual(
            "The cost is real — it just isn't the whole story.".withoutEmDashes,
            "The cost is real, it just isn't the whole story."
        )
    }

    func testAnUnspacedEmDashBecomesAComma() {
        XCTAssertEqual(
            "Mentoring—the part nobody measures—happens in person.".withoutEmDashes,
            "Mentoring, the part nobody measures, happens in person."
        )
    }

    func testASpacedEnDashGoesTooButARangeSurvives() {
        XCTAssertEqual("Two things – both true.".withoutEmDashes, "Two things, both true.")
        XCTAssertEqual("It takes 3–5 hours.".withoutEmDashes, "It takes 3–5 hours.")
    }

    /// A dash next to punctuation that was already doing the job would otherwise
    /// leave "the point,, which".
    func testItDoesNotDoubleUpPunctuation() {
        XCTAssertEqual("The point, — which is this.".withoutEmDashes, "The point, which is this.")
        XCTAssertEqual("What matters: — the cost.".withoutEmDashes, "What matters: the cost.")
    }

    func testADashAtEitherEndIsDropped() {
        XCTAssertEqual("— The one question left".withoutEmDashes, "The one question left")
        XCTAssertEqual("The one question left —".withoutEmDashes, "The one question left")
    }

    /// Hyphens are not dashes. "One-off" and "on-device" are words.
    func testHyphenatedWordsAreLeftAlone() {
        XCTAssertEqual(
            "A free one-off download for on-device work.".withoutEmDashes,
            "A free one-off download for on-device work."
        )
    }

    func testTextWithoutDashesIsUnchanged() {
        let plain = "Does the raise actually cover what the move costs?"
        XCTAssertEqual(plain.withoutEmDashes, plain)
    }
}

final class LeadingConjunctionTests: XCTestCase {
    /// Nothing comes before a point on a checklist, so a point that opens on a
    /// conjunction is joined to nothing. Real claims, all of them.
    func testAClaimJoinedToNothingIsUnjoined() {
        XCTAssertEqual(
            "And if automation continues, the income will cover it.".withoutLeadingConjunction,
            "If automation continues, the income will cover it."
        )
        XCTAssertEqual(
            "Also their stuff is corporate slop.".withoutLeadingConjunction,
            "Their stuff is corporate slop."
        )
        XCTAssertEqual("But the rent is higher.".withoutLeadingConjunction, "The rent is higher.")
        XCTAssertEqual("and, the queue is long".withoutLeadingConjunction, "The queue is long")
    }

    /// Only the whole word, only at the front. "Android" is not a conjunction,
    /// and "so" never once opened one of these — but "So many people go there"
    /// would lose its meaning, so it is left alone.
    func testOnlyAConjunctionAtTheFrontGoes() {
        for claim in [
            "Android phones are cheaper to replace.",
            "So many people go there that the queue is the point.",
            "The commute costs more, and the rent is worth it.",
            "Andy is not a party to this argument.",
        ] {
            XCTAssertEqual(claim.withoutLeadingConjunction, claim)
        }
    }

    // MARK: - Sentences that have to end

    /// From the session of 6 August 2026, transcript `dispute-debug-1786024776`,
    /// where the model returned a crux question with no question mark and a test
    /// with no full stop. The recap welded each onto the sentence after it.
    func testAnUnpunctuatedSentenceGetsItsEnding() {
        XCTAssertEqual(
            "Does FDT produce better outcomes on a subset of the prisoners dilemma".ending(with: "?"),
            "Does FDT produce better outcomes on a subset of the prisoners dilemma?"
        )
        XCTAssertEqual(
            "Run the test and compare the outcomes".ending(with: "."),
            "Run the test and compare the outcomes."
        )
    }

    /// A model that did punctuate is left exactly as it wrote it, whichever mark
    /// it chose.
    func testAlreadyPunctuatedIsLeftAlone() {
        for text in [
            "Is the rent saving worth the commute?",
            "Write down a year of costs and compare them.",
            "Ask the school whether they can take them in September!",
        ] {
            XCTAssertEqual(text.ending(with: "."), text)
            XCTAssertEqual(text.ending(with: "?"), text)
        }
    }

    /// The stop belongs after the bracket, not inside it, and trailing space is
    /// not punctuation.
    func testTheEndingGoesOutsideClosingMarks() {
        XCTAssertEqual(
            "Compare a year of costs (both of you)".ending(with: "."),
            "Compare a year of costs (both of you)."
        )
        XCTAssertEqual("Ask the school  ".ending(with: "."), "Ask the school.")
        XCTAssertEqual("".ending(with: "."), "")
    }
}
