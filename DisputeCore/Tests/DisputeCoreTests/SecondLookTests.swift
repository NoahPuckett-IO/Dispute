import XCTest
@testable import DisputeCore

/// The follow-up on the checklist turn: argue for one point you crossed out,
/// and say what would change your mind about it.
final class SecondLookTests: XCTestCase {
    private func ticked() -> Dispute {
        var dispute = Dispute(names: PartyPair(a: "Alex", b: "Sam"))
        dispute.claims = [
            Claim(text: "Rent is cheaper there.", origin: .a, agreement: PartyPair(a: true, b: false)),
            Claim(text: "The kids would change schools.", origin: .b, agreement: PartyPair(a: false, b: true)),
            Claim(text: "The commute costs more than it saves.", origin: .a, agreement: PartyPair(a: true, b: true)),
        ]
        return dispute
    }

    func testSomeoneIsOnlyOfferedThePointsTheyCrossedOut() {
        let dispute = ticked()

        XCTAssertEqual(
            dispute.rejectedClaims(by: .a).map(\.text),
            ["The kids would change schools."]
        )
        XCTAssertEqual(
            dispute.rejectedClaims(by: .b).map(\.text),
            ["Rent is cheaper there."]
        )
    }

    /// Someone who ticked everything has nothing of theirs to argue for, and
    /// asking them anyway would be busywork on the one screen that has to feel
    /// worth the typing.
    func testTickingEverythingSkipsTheFollowUpEntirely() {
        var dispute = ticked()
        for index in dispute.claims.indices {
            dispute.claims[index].setAgreement(true, for: .a)
        }

        XCTAssertTrue(dispute.rejectedClaims(by: .a).isEmpty)
        XCTAssertFalse(dispute.owesRethink(.a))
        XCTAssertTrue(dispute.owesRethink(.b), "the other one still crossed something out")
    }

    func testAHalfAnsweredFollowUpStillCounts() {
        var dispute = ticked()
        let claim = dispute.rejectedClaims(by: .a)[0]

        dispute.setRethink(
            Rethink(claimID: claim.id, bestCase: "Moving mid-year is hard on them.", changeCondition: ""),
            for: .a
        )

        XCTAssertTrue(dispute.owesRethink(.a), "one field is not an answer")

        dispute.setRethink(
            Rethink(
                claimID: claim.id,
                bestCase: "Moving mid-year is hard on them.",
                changeCondition: "the new school could take them in September"
            ),
            for: .a
        )

        XCTAssertFalse(dispute.owesRethink(.a))
    }

    /// A field holding a space bar has not been answered.
    func testWhitespaceIsNotAnAnswer() {
        var dispute = ticked()
        let claim = dispute.rejectedClaims(by: .a)[0]

        dispute.setRethink(
            Rethink(claimID: claim.id, bestCase: "   ", changeCondition: "\n "),
            for: .a
        )

        XCTAssertTrue(dispute.owesRethink(.a))
        XCTAssertEqual(dispute.rethinks[.a]?.bestCase, "", "blanks are stored trimmed, not padded")
    }

    func testTheAnswerIsTiedToThePointItWasAbout() {
        var dispute = ticked()
        let claim = dispute.rejectedClaims(by: .b)[0]

        dispute.setRethink(
            Rethink(claimID: claim.id, bestCase: "Rents really are lower.", changeCondition: "the listings said so"),
            for: .b
        )

        XCTAssertEqual(dispute.claim(withID: claim.id)?.text, "Rent is cheaper there.")
        XCTAssertEqual(dispute.rethinks[.b]?.claimID, claim.id)
        XCTAssertNil(dispute.rethinks[.a])
    }

    /// Where someone said what would change their mind about this exact point,
    /// that sentence is a better answer to show them than "No".
    func testAManualDraftUsesWhatWouldChangeTheirMind() {
        var dispute = ticked()
        let claim = dispute.contestedClaims[0]
        dispute.setRethink(
            Rethink(
                claimID: claim.id,
                bestCase: "Rents really are lower.",
                changeCondition: "The listings showed otherwise."
            ),
            for: .b
        )

        let draft = Crux.draft(from: claim, rethinks: dispute.rethinks)

        XCTAssertEqual(draft.question, "Is it true that rent is cheaper there?")
        XCTAssertEqual(draft.positions[.a], "Yes")
        XCTAssertEqual(draft.positions[.b], "No, unless the listings showed otherwise")
    }

    func testADraftWithoutASecondLookStillReadsYesAndNo() {
        let dispute = ticked()
        let draft = Crux.draft(from: dispute.contestedClaims[0], rethinks: dispute.rethinks)

        XCTAssertEqual(draft.positions[.a], "Yes")
        XCTAssertEqual(draft.positions[.b], "No")
    }

    /// Rewording a position throws away everything derived from it, and the
    /// second looks were derived from a list that is about to be rebuilt.
    func testGoingBackToRewordClearsTheFollowUps() {
        var dispute = ticked()
        dispute.setRethink(
            Rethink(claimID: dispute.claims[0].id, bestCase: "b", changeCondition: "c"),
            for: .a
        )
        dispute.crux = Crux(question: "Anything?", positions: PartyPair(both: "Yes"))
        dispute.recap = "Written."

        dispute.returnToPositions()

        XCTAssertNil(dispute.rethinks[.a])
        XCTAssertNil(dispute.crux)
        XCTAssertEqual(dispute.recap, "")
    }
}

final class RecapTests: XCTestCase {
    private func finished() -> Dispute {
        var dispute = Dispute(
            title: "Whether to move",
            names: PartyPair(a: "Alex", b: "Sam")
        )
        dispute.positions = PartyPair(a: "We should move.", b: "We should stay.")
        dispute.claims = [
            Claim(text: "Rent is cheaper there.", origin: .a, agreement: PartyPair(a: true, b: false)),
            Claim(text: "The kids would change schools.", origin: .b, agreement: PartyPair(a: false, b: true)),
            Claim(text: "The commute costs more than it saves.", origin: .a, agreement: PartyPair(a: true, b: true)),
            Claim(text: "We can afford either.", origin: .b, agreement: PartyPair(a: false, b: false)),
        ]
        dispute.setRethink(
            Rethink(
                claimID: dispute.claims[1].id,
                bestCase: "Changing schools mid-year is genuinely hard.",
                changeCondition: "the new school could take them in September"
            ),
            for: .a
        )
        dispute.setRethink(
            Rethink(
                claimID: dispute.claims[0].id,
                bestCase: "The listings really are cheaper out there.",
                changeCondition: "the total after the commute still came out lower"
            ),
            for: .b
        )
        dispute.crux = Crux(
            question: "Does the rent saving survive the commute?",
            positions: PartyPair(a: "Yes, comfortably", b: "No, not once the season ticket is in")
        )
        return dispute
    }

    func testTheRecordSaysWhatTheyArguedAboutAndHowMuchTheyAgreedOn() {
        let text = ArgumentRecap.compose(from: finished())

        XCTAssertTrue(text.contains("Whether to move"))
        XCTAssertTrue(text.contains("4 points"))
        XCTAssertTrue(text.contains("2 of them the same way"))
    }

    /// The field is prompted with "If…", so this is what people actually type.
    func testALeadingIfIsNotDoubledUp() {
        var dispute = finished()
        dispute.setRethink(
            Rethink(
                claimID: dispute.claims[1].id,
                bestCase: "Mid-year moves are hard.",
                changeCondition: "If the school could take them in September"
            ),
            for: .a
        )

        let text = ArgumentRecap.compose(from: dispute)

        XCTAssertFalse(text.contains("if if"))
        XCTAssertTrue(text.contains("Alex would change their mind if the school could take them in September."))
    }

    /// "If" anywhere but the front is theirs to keep.
    func testAnIfInsideTheSentenceSurvives() {
        let rethink = Rethink(
            claimID: UUID(),
            bestCase: "b",
            changeCondition: "They said they'd move if the rent dropped."
        )

        XCTAssertEqual(rethink.conditionClause, "they said they'd move if the rent dropped")
    }

    func testTheRecordEndsOnTheOneQuestionAndBothTests() {
        let text = ArgumentRecap.compose(from: finished())

        XCTAssertTrue(text.contains("What's left is one question: Does the rent saving survive the commute?"))
        XCTAssertTrue(text.contains("Alex would change their mind if the new school could take them in September."))
        XCTAssertTrue(text.contains("Sam would change their mind if the total after the commute still came out lower."))
    }

    /// It is written to both of them at once, on one phone.
    func testTheRecordNeverSaysWhoWasRight() {
        let text = ArgumentRecap.compose(from: finished())

        for word in ["right", "wrong", "better", "should", "win", "lost"] {
            XCTAssertFalse(
                text.localizedCaseInsensitiveContains(" \(word)"),
                "the record editorialised: \(text)"
            )
        }
    }

    func testAgreeingOnEverythingIsSaidPlainlyRatherThanLeftBlank() {
        var dispute = finished()
        dispute.crux = nil
        for index in dispute.claims.indices {
            dispute.claims[index].setAgreement(true, for: .a)
            dispute.claims[index].setAgreement(true, for: .b)
        }

        let text = ArgumentRecap.compose(from: dispute)

        XCTAssertTrue(text.contains("every one of them the same way"))
        XCTAssertTrue(text.contains("Nothing on the list still splits you"))
    }

    /// An argument abandoned early still produces a sentence rather than a
    /// half-built one with an empty count in it.
    func testAnEmptySessionStillComposesSomething() {
        let text = ArgumentRecap.compose(from: Dispute())

        XCTAssertFalse(text.isEmpty)
        XCTAssertFalse(text.contains("0 points"))
    }

    func testTheTranscriptCarriesEverySectionThatHasContent() {
        let text = ArgumentRecap.transcript(of: finished())

        XCTAssertTrue(text.contains("Whether to move"))
        XCTAssertTrue(text.contains("WHAT YOU EACH SAID"))
        XCTAssertTrue(text.contains("WHAT YOU BOTH SIGNED UP TO"))
        XCTAssertTrue(text.contains("WHERE YOU SPLIT"))
        XCTAssertTrue(text.contains("THE CRUX"))
        XCTAssertTrue(text.contains("WHAT WOULD CHANGE YOUR MINDS"))
        XCTAssertTrue(text.contains("Alex and Sam"))
    }

    /// A short argument gives a short record, not a form with blanks in it.
    func testEmptySectionsAreDroppedFromTheTranscript() {
        var dispute = Dispute(title: "Quick one", names: PartyPair(a: "Alex", b: "Sam"))
        dispute.positions = PartyPair(a: "Yes.", b: "No.")

        let text = ArgumentRecap.transcript(of: dispute)

        XCTAssertTrue(text.contains("WHAT YOU EACH SAID"))
        XCTAssertFalse(text.contains("THE CRUX"))
        XCTAssertFalse(text.contains("WHERE YOU SPLIT"))
    }

    /// The transcript is what leaves the phone when someone shares it, so it
    /// uses the written record where there is one.
    func testTheTranscriptPrefersTheRecapThatWasActuallyShown() {
        var dispute = finished()
        dispute.recap = "The version the model wrote."

        XCTAssertTrue(ArgumentRecap.transcript(of: dispute).contains("The version the model wrote."))
    }
}

/// The app puts the name beside the stance, so the stance must not carry one of
/// its own. See `String.withoutAttribution`.
final class CruxAttributionTests: XCTestCase {

    func testAModelsOwnAttributionIsTakenOffTheFront() {
        XCTAssertEqual(
            "Person A believes that cost matters most.".withoutAttribution,
            "Cost matters most."
        )
        XCTAssertEqual("Person B thinks the school is worth it".withoutAttribution, "The school is worth it")
        XCTAssertEqual("They say the commute is survivable.".withoutAttribution, "The commute is survivable.")
        XCTAssertEqual(
            "The second person argues that nothing has changed.".withoutAttribution,
            "Nothing has changed."
        )
    }

    /// The verb is the answer wherever it isn't a label. A stance that opens on
    /// the subject of the argument keeps every word of it.
    func testAStanceThatIsNotAttributedIsLeftAlone() {
        for stance in [
            "Cost matters most.",
            "Believing the quote was the mistake.",
            "Person A is the one paying for it.",
            "No, not once the season ticket is in",
        ] {
            XCTAssertEqual(stance.withoutAttribution, stance)
        }
    }

    /// The last screen read "Noah says person B believes that visual appeal
    /// matters more", which is what this whole thing is for. The stances here
    /// are a real answer from the downloaded model, taken in through the same
    /// step both engines put it through.
    func testTheRecordNamesEachPersonOnlyOnce() {
        var dispute = Dispute(title: "Vanilla or chocolate", names: PartyPair(a: "Henry", b: "Noah"))
        dispute.crux = Crux(
            question: "How much does how it looks matter?",
            positions: PartyPair(
                a: "Person A believes that the nootropic effects are what count.".withoutAttribution,
                b: "Person B believes that visual appeal and taste matter more.".withoutAttribution
            )
        )

        let text = ArgumentRecap.compose(from: dispute)

        XCTAssertTrue(text.contains("Henry says the nootropic effects are what count."))
        XCTAssertTrue(text.contains("Noah says visual appeal and taste matter more."))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("says person"))
    }

    /// And spells it the way they spell it. The last screen of the Starbucks
    /// session read "Henry says starbucks is good", which is the app
    /// miscapitalising the one word the whole argument was about.
    func testTheRecordKeepsAName() {
        var dispute = Dispute(title: "Is Starbucks good", names: PartyPair(a: "Henry", b: "Noah"))
        dispute.positions = PartyPair(
            a: "I like the smores frappe",
            b: "Their stuff is corporate slop and they rejected me from a job"
        )
        dispute.crux = Crux(
            question: "How much does the coffee matter against how the place behaves?",
            positions: PartyPair(
                a: "Starbucks is worth it for the drinks alone.",
                b: "Starbucks is not good, whatever the drinks are like."
            )
        )

        let text = ArgumentRecap.compose(from: dispute)

        XCTAssertTrue(text.contains("Henry says Starbucks is worth it for the drinks alone."))
        XCTAssertTrue(text.contains("Noah says Starbucks is not good, whatever the drinks are like."))
    }

    /// An ordinary word that only ever opened a sentence is still lowercased.
    /// Protecting every capital would give "Noah says Cost matters most".
    func testAnOrdinaryOpeningWordIsStillFoldedIn() {
        var dispute = Dispute(title: "Whether to move", names: PartyPair(a: "Alex", b: "Sam"))
        dispute.positions = PartyPair(
            a: "Cost is the thing that decides it.",
            b: "The commute is what decides it."
        )
        dispute.crux = Crux(
            question: "Which of the two costs more over a year?",
            positions: PartyPair(a: "Cost matters most.", b: "Time matters most.")
        )

        let text = ArgumentRecap.compose(from: dispute)

        XCTAssertTrue(text.contains("Alex says cost matters most."))
        XCTAssertTrue(text.contains("Sam says time matters most."))
    }

    func testOnlyWordsCapitalisedAwayFromTheStartOfASentenceCount() {
        let names = """
            Is Starbucks good
            I like the smores frappe
            Their stuff is corporate slop. Also the queue at Waterloo is long.
            """.capitalisedNames

        XCTAssertEqual(names, ["starbucks", "waterloo"])
    }
}

final class SingleCruxTests: XCTestCase {
    func testABlankQuestionIsNotAUsableCrux() {
        XCTAssertFalse(Crux(question: "", positions: PartyPair(both: "")).isUsable)
        XCTAssertFalse(Crux(question: "  Why? ", positions: PartyPair(both: "")).isUsable)
        XCTAssertTrue(
            Crux(question: "Does the raise cover the move?", positions: PartyPair(both: "")).isUsable
        )
    }

    /// A session saved when the app still kept a list keeps its first crux —
    /// which was always the one it called most important. `DisputeStore` treats
    /// a decode failure as "no saved session", so this silently throws an
    /// argument away if it regresses.
    func testASessionSavedWithAListOfCruxesKeepsTheFirstOne() throws {
        let legacy = """
        {
          "id": "6C7C6B4E-3C09-4E51-9F0E-2F3B9E8E1A11",
          "title": "Whether to move",
          "createdAt": 774000000,
          "stage": "crux",
          "names": {"a": "Alex", "b": "Sam"},
          "positions": {"a": "Move.", "b": "Stay."},
          "claims": [],
          "factFlags": [],
          "cruxes": [
            {
              "id": "A1B2C3D4-3C09-4E51-9F0E-2F3B9E8E1A11",
              "question": "The important one?",
              "positions": {"a": "Yes", "b": "No"},
              "needsConversation": false
            },
            {
              "id": "B1B2C3D4-3C09-4E51-9F0E-2F3B9E8E1A11",
              "question": "The one that restated it?",
              "positions": {"a": "Yes", "b": "No"},
              "needsConversation": false
            }
          ]
        }
        """.data(using: .utf8)!

        let dispute = try JSONDecoder().decode(Dispute.self, from: legacy)

        XCTAssertEqual(dispute.crux?.question, "The important one?")
        XCTAssertEqual(dispute.recap, "")
        XCTAssertNil(dispute.rethinks[.a])
    }

    func testASessionWithTheNewFieldsRoundTrips() throws {
        var original = Dispute(title: "Whether to move", names: PartyPair(a: "Alex", b: "Sam"))
        original.claims = [
            Claim(text: "Rent is cheaper.", origin: .a, agreement: PartyPair(a: true, b: false))
        ]
        original.setRethink(
            Rethink(claimID: original.claims[0].id, bestCase: "Best.", changeCondition: "Changed."),
            for: .b
        )
        original.crux = Crux(question: "Is it cheaper?", positions: PartyPair(a: "Yes", b: "No"))
        original.recap = "Written up."

        let decoded = try JSONDecoder().decode(
            Dispute.self,
            from: try JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded.crux, original.crux)
        XCTAssertEqual(decoded.rethinks[.b], original.rethinks[.b])
        XCTAssertEqual(decoded.recap, "Written up.")
    }

    /// The encoder must not start writing the old key again — a build that
    /// wrote `cruxes` and read `crux` would lose the crux on every relaunch.
    func testTheOldKeyIsNoLongerWritten() throws {
        var dispute = Dispute()
        dispute.crux = Crux(question: "Anything?", positions: PartyPair(both: "Yes"))

        let text = String(decoding: try JSONEncoder().encode(dispute), as: UTF8.self)

        XCTAssertTrue(text.contains("\"crux\""))
        XCTAssertFalse(text.contains("\"cruxes\""))
    }
}
