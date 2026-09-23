import XCTest
@testable import DisputeCore

final class ClaimTests: XCTestCase {
    func testStartsUnanswered() {
        let claim = Claim(text: "Cost should drive the decision.", origin: .a)

        XCTAssertFalse(claim.isAnsweredByBoth)
        XCTAssertFalse(claim.isAnswered(by: .a))
        XCTAssertFalse(claim.isContested)
        XCTAssertFalse(claim.isShared)
    }

    /// The distinction the whole app rests on: same answer is common ground,
    /// different answers are the disagreement.
    func testAgreementAndDisagreementAreDistinguished() {
        var claim = Claim(text: "Cost should drive the decision.", origin: .a)

        claim.setAgreement(true, for: .a)
        XCTAssertFalse(claim.isAnsweredByBoth, "one answer is not enough")
        XCTAssertFalse(claim.isContested)

        claim.setAgreement(false, for: .b)
        XCTAssertTrue(claim.isAnsweredByBoth)
        XCTAssertTrue(claim.isContested)
        XCTAssertFalse(claim.isShared)
    }

    func testBothTickingItIsCommonGround() {
        var claim = Claim(text: "Emissions matter.", origin: .b)
        claim.setAgreement(true, for: .a)
        claim.setAgreement(true, for: .b)

        XCTAssertTrue(claim.isShared)
        XCTAssertFalse(claim.isContested)
    }

    /// Both rejecting a claim is agreement too — just in the negative.
    func testBothRejectingItIsAlsoCommonGround() {
        var claim = Claim(text: "Renewables alone can cover baseload.", origin: .a)
        claim.setAgreement(false, for: .a)
        claim.setAgreement(false, for: .b)

        XCTAssertTrue(claim.isMutuallyRejected)
        XCTAssertFalse(claim.isContested)
    }

    func testAnswersCanBeChanged() {
        var claim = Claim(text: "Timelines are the obstacle.", origin: .b)
        claim.setAgreement(true, for: .a)
        claim.setAgreement(false, for: .a)

        XCTAssertEqual(claim.agreement.a, false)
    }

    func testSurvivesARoundTrip() throws {
        var claim = Claim(text: "Waste has a workable solution.", origin: .a)
        claim.setAgreement(true, for: .a)
        claim.setAgreement(false, for: .b)

        let data = try JSONEncoder().encode(claim)
        XCTAssertEqual(try JSONDecoder().decode(Claim.self, from: data), claim)
    }
}

final class ClaimDeduplicationTests: XCTestCase {
    /// The real case that prompted this: both sides drew the same idea out of
    /// the same sentence, in separate generation calls.
    func testNearDuplicatesAreDropped() {
        let claims = [
            Claim(text: "Most mentoring happens in the office.", origin: .b),
            Claim(text: "Mentoring and accidental conversations happen in the office.", origin: .b),
            Claim(text: "Knowledge workers are happier with flexibility.", origin: .a),
            Claim(text: "Output is easy to measure remotely.", origin: .a),
            Claim(text: "Culture erodes without regular contact.", origin: .b),
            Claim(text: "Commuting time is wasted time.", origin: .a),
        ]

        let kept = Claim.deduplicated(claims)

        XCTAssertEqual(kept.count, 5, "one restatement removed")
        XCTAssertTrue(kept.contains { $0.text == "Most mentoring happens in the office." })
        XCTAssertFalse(
            kept.contains { $0.text.contains("accidental conversations") },
            "the later restatement is the one dropped"
        )
    }

    /// The floor matters more than tidiness: a list this short can't find a
    /// crux, so deduplication stops rather than shrink it further.
    func testAShortListIsNeverShrunk() {
        let claims = [
            Claim(text: "Most mentoring happens in the office.", origin: .b),
            Claim(text: "Mentoring happens in the office mostly.", origin: .b),
        ]

        XCTAssertEqual(Claim.deduplicated(claims).count, 2)
    }

    func testGenuinelyDifferentClaimsAreAllKept() {
        let claims = [
            Claim(text: "Knowledge workers are happier with the flexibility.", origin: .a),
            Claim(text: "Culture erodes without regular in-person contact.", origin: .b),
            Claim(text: "Output is easy to measure remotely.", origin: .a),
        ]

        XCTAssertEqual(Claim.deduplicated(claims).count, 3)
    }

    /// Opposing claims share vocabulary but are the most valuable thing in the
    /// list — losing them would defeat the point of the app.
    func testOpposingClaimsAboutTheSameThingSurvive() {
        let claims = [
            Claim(text: "Remote work improves productivity for most roles.", origin: .a),
            Claim(text: "Remote work harms collaboration between teams.", origin: .b),
        ]

        XCTAssertEqual(Claim.deduplicated(claims).count, 2)
    }

    func testIdenticalTextIsCaught() {
        let claims = [
            Claim(text: "Flexibility matters most.", origin: .a),
            Claim(text: "Flexibility matters most.", origin: .b),
            Claim(text: "Culture erodes without contact.", origin: .b),
            Claim(text: "Output is measurable remotely.", origin: .a),
            Claim(text: "Commuting wastes time.", origin: .a),
        ]

        XCTAssertEqual(Claim.deduplicated(claims).count, 4)
    }

    /// The regression that prompted the rewrite: dividing by the smaller set
    /// meant a short claim inside a longer one scored 1.0, and a six-point list
    /// collapsed to two.
    func testARealisticListKeepsMostOfItsPoints() {
        let claims = [
            Claim(text: "Most knowledge workers are happier with the flexibility of remote work.", origin: .a),
            Claim(text: "Mentoring and accidental conversations happen more in the office.", origin: .b),
            Claim(text: "Output is easy to measure without watching people work.", origin: .a),
            Claim(text: "Culture erodes without regular in-person contact.", origin: .b),
            Claim(text: "Commuting time is better spent on the work itself.", origin: .a),
            Claim(text: "Junior staff learn faster when surrounded by colleagues.", origin: .b),
        ]

        XCTAssertEqual(Claim.deduplicated(claims).count, 6, "none of these are restatements")
    }

    func testOverlapIgnoresFillerWords() {
        // Same content words, different filler — should read as a repeat.
        let score = Claim.overlap(
            "The mentoring is done in the office",
            "Mentoring is done at an office"
        )

        XCTAssertGreaterThanOrEqual(score, 0.6)
    }

    func testEmptyInputIsHandled() {
        XCTAssertTrue(Claim.deduplicated([]).isEmpty)
        XCTAssertEqual(Claim.overlap("", "anything"), 0)
    }

    // MARK: - Points that are only somebody's own sentence handed back

    /// From a real session, where the model stopped drawing claims out of the
    /// second position and started copying lines out of it. Both people were
    /// then asked whether they agreed with their own words, and both said no.
    private static let positionB = """
        I think that vanilla is the better flavor because it has a more visually \
        appealing color, a more calm and refined taste. I think it's less chaotic \
        and I think it has a more clean and refined pallet.
        """

    func testAPointCopiedOutOfAPositionIsDropped() {
        let claims = [
            Claim(text: "The visual appeal of a flavor is a subjective judgement.", origin: .a),
            Claim(text: "I think it's less chaotic and I think it has a more clean and refined pallet.", origin: .b),
            Claim(text: "A calmer taste is worth more than a stronger one.", origin: .a),
            Claim(text: "Nootropic effects are a reason to prefer a flavor.", origin: .a),
            Claim(text: "Tolerance to a stimulant matters when choosing one.", origin: .b),
        ]

        let kept = Claim.deduplicated(claims, orEchoing: [Self.positionB])

        XCTAssertEqual(kept.count, 4)
        XCTAssertFalse(kept.contains { $0.text.hasPrefix("I think") }, "the copied line survived")
    }

    /// A claim drawn out of a position shares its subject, and must not be read
    /// as a copy of it. The Jaccard score used between claims cannot tell these
    /// apart from copies, which is why containment is measured instead.
    func testAPointDrawnFromAPositionIsKept() {
        for text in [
            "The visual appeal of a flavor is a subjective judgement.",
            "A calm taste is the better one to build a preference on.",
            "How a flavor looks matters less than how it tastes.",
        ] {
            XCTAssertFalse(
                Claim.isEcho(text, of: Self.positionB),
                "a real point read as a copy: \(text)"
            )
        }
    }

    /// The floor holds where it was written to hold: against dropping points
    /// that merely resemble each other. Five distinct claims about one subject
    /// score high against each other, and cutting that to two leaves nothing to
    /// find a crux in.
    func testTheFloorHoldsAgainstDroppingPointsForResemblingEachOther() {
        let claims = [
            Claim(text: "Flexibility matters most.", origin: .a),
            Claim(text: "Culture erodes without contact.", origin: .b),
            Claim(text: "Output is measurable remotely.", origin: .a),
            Claim(text: "Flexibility, in the end, is what matters.", origin: .b),
            Claim(text: "Culture erodes without any contact.", origin: .a),
        ]

        XCTAssertEqual(Claim.deduplicated(claims).count, Claim.minimumUsableClaims)
    }

    /// And never against the same sentence twice, however short the list.
    func testTheFloorNeverKeepsThePointItAlreadyHas() {
        let claims = [
            Claim(text: "Flexibility matters most.", origin: .a),
            Claim(text: "Culture erodes without contact.", origin: .b),
            Claim(text: "flexibility matters most", origin: .b),
            Claim(text: "Flexibility matters most!", origin: .a),
        ]

        XCTAssertEqual(Claim.deduplicated(claims).count, 2)
    }

    /// And does not hold against a played-back sentence, which is the change
    /// this session forced. Filling a list to four with points neither of them
    /// can answer buys a screen at the cost of the stage it feeds: the two of
    /// them tick their own words, the crux is drawn from whichever way they
    /// happened to tick, and the write-up reports it as their disagreement.
    func testTheFloorDoesNotRescueAPlayedBackSentence() {
        let claims = (1...5).map { _ in
            Claim(text: "It's less chaotic and it has a more refined pallet.", origin: .b)
        }

        XCTAssertTrue(Claim.deduplicated(claims, orEchoing: [Self.positionB]).isEmpty)
    }

    /// Not a copy of anything, so no similarity measure catches it, and still
    /// unusable: the first two words say whose point it is.
    func testAPointLeftInSomebodysOwnVoiceIsDropped() {
        let claims = [
            Claim(text: "The visual appeal of a flavor is a subjective judgement.", origin: .a),
            Claim(text: "I think vanilla is better because it doesn't make me thirsty.", origin: .b),
            Claim(text: "A calmer taste is worth more than a stronger one.", origin: .a),
            Claim(text: "Nootropic effects are a reason to prefer a flavor.", origin: .a),
            Claim(text: "Tolerance to a stimulant matters when choosing one.", origin: .b),
        ]

        let kept = Claim.deduplicated(claims, orEchoing: [Self.positionB])

        XCTAssertEqual(kept.count, 4)
        XCTAssertFalse(kept.contains { $0.text.hasPrefix("I think") })
    }

    /// Quoting one of them mid-claim is allowed. Nothing outside the quotation
    /// marks is theirs.
    func testAnIInsideAQuotationIsLeftAlone() {
        XCTAssertFalse(Claim.isInSomeonesVoice("Saying \"I don't need water\" is a claim about thirst."))
        XCTAssertFalse(Claim.isInSomeonesVoice("Calling it “my kind of place” is a claim about taste."))
        XCTAssertTrue(Claim.isInSomeonesVoice("I believe the colour matters."))
        XCTAssertTrue(Claim.isInSomeonesVoice("  My preference is the refined one."))
    }

    /// The opening is not the only place a claim gives away whose it is. Every
    /// one of these reached a real checklist, and each of them asks one of the
    /// two people to say whether they agree with themselves.
    func testFirstPersonAnywhereInAClaimIsSomebodysVoice() {
        for text in [
            "I like the smores frappe",
            "They're green and they rejected me from a job",
            "And I feel like there's a wealth disparity there.",
            "The coffee is too expensive for us to buy every day.",
            "Our evenings are worth more than the rent difference.",
        ] {
            XCTAssertTrue(Claim.isInSomeonesVoice(text), "read as neutral: \(text)")
        }
    }

    /// The words a claim is allowed to be built out of. "Mine" as a noun and
    /// "mine" as a hole in the ground are the same string, but a claim about
    /// mining is not what this model produces and a possessive is.
    func testAClaimAboutOtherPeopleIsNotSomebodysVoice() {
        for text in [
            "Changing schools would set the kids back.",
            "The commute costs more than the cheaper rent is worth.",
            "Informal conversation drives most good ideas.",
            "Whether they are rich is not what makes the coffee good.",
        ] {
            XCTAssertFalse(Claim.isInSomeonesVoice(text), "read as somebody's voice: \(text)")
        }
    }

    // MARK: - The list that came back from the Starbucks session

    /// Six points, every one of them a sentence lifted out of a position, and
    /// two of them the same sentence twice.
    ///
    /// The floor let all four of the last ones through: it was checked before
    /// each claim and switched the filtering off entirely for the rest of the
    /// list once the count could no longer afford a drop. So the checklist
    /// carried "They're green and they rejected me from a job" twice, and asked
    /// the person who wrote "I like the smores frappe" whether they agreed with
    /// it. They said yes. The other said no, and that became the crux.
    private static let starbucksA = "I like the smores frappe"
    private static let starbucksB = """
        Like Starbucks because it's overly sugary and has a very very high \
        calorie count and a lot of the people who go there are like rich and \
        I'm not very rich and I feel like there's a wealth disparity there and \
        they just like hate poor people. Also their stuff is like corporate \
        slop, and like corporate jargon and it's like can we circle back around \
        to this later? Also I don't like that they're green and they rejected \
        me from a job
        """

    private static var starbucksClaims: [Claim] {
        Claim.interleave(
            [
                "I like the smores frappe",
                "They're green and they rejected me from a job",
                "They're like corporate slop",
            ].map { Claim(text: $0, origin: .a) },
            [
                "And I feel like there's a wealth disparity there and they just like hate poor people.",
                "they're green and they rejected me from a job",
                "I like the smores frappe",
            ].map { Claim(text: $0, origin: .b) }
        )
    }

    func testTheSameSentenceNeverAppearsOnTheListTwice() {
        let kept = Claim.deduplicated(
            Self.starbucksClaims,
            orEchoing: [Self.starbucksA, Self.starbucksB]
        )

        let texts = kept.map { $0.text.lowercased() }
        XCTAssertEqual(Set(texts).count, texts.count, "the same point is on the list twice")
    }

    /// No floor rescues a list made only of played-back sentences. Four points
    /// nobody can answer is not a checklist, and `breakDown` turning that into
    /// an error gives the two of them a retry instead of a screen that wastes
    /// the rest of their session.
    func testAListThatIsAllPlayedBackSentencesComesBackEmpty() {
        XCTAssertTrue(
            Claim.deduplicated(
                Self.starbucksClaims,
                orEchoing: [Self.starbucksA, Self.starbucksB]
            ).isEmpty
        )
    }

    /// Manual mode passes no positions, because there the two of them typed the
    /// points themselves and their own words are the whole list.
    func testPointsPeopleTypedThemselvesAreNeverTreatedAsEchoes() {
        let claims = [
            Claim(text: "I think it's less chaotic and nothing like the other one.", origin: .b),
            Claim(text: "I think it has a more refined pallet.", origin: .b),
            Claim(text: "Chocolate has a nootropic effect worth having.", origin: .a),
            Claim(text: "Tolerance builds slower with theobromine.", origin: .a),
            Claim(text: "A calm taste beats a strong one.", origin: .b),
        ]

        XCTAssertEqual(Claim.deduplicated(claims).count, 5)
    }

    // MARK: - Short positions, where the borrowed-words ratio stops working

    /// From the session of 6 August 2026, transcript `dispute-debug-1786024776`.
    ///
    /// One dense sentence each about functional decision theory. The model
    /// returned six clean claims on every one of four attempts and this filter
    /// threw four of them away each time, so the stage failed twice and the app
    /// fell back to putting these two positions on the checklist as the points.
    /// Each person was then asked whether they agreed with their own sentence.
    /// Nought agreed, two split, and the crux was drawn from that.
    private static let fdtA = """
        No, it doesn't make meaningful claims and is under specified as it \
        assumes agents can calculate counterfactual outcomes of alternate decisions
        """
    private static let fdtB = """
        Two agents using FDT would be able to cooperate on the prisoners dilemma, \
        a concrete falsifiable example of an outcome of FDT that is preferable to \
        other outcomes
        """

    func testClaimsDrawnFromAShortDensePositionSurvive() {
        let claims = [
            Claim(text: "FDT makes no meaningful claims", origin: .a),
            Claim(text: "Agents cannot calculate counterfactual outcomes of alternate decisions", origin: .a),
            Claim(text: "FDT is underspecified", origin: .a),
            Claim(text: "Two agents using FDT would cooperate in the prisoner's dilemma", origin: .b),
            Claim(text: "The outcome of FDT in the prisoner's dilemma is preferable to other outcomes", origin: .b),
            Claim(text: "The prisoner's dilemma is a concrete falsifiable example of FDT", origin: .b),
        ]

        let kept = Claim.deduplicated(claims, orEchoing: [Self.fdtA, Self.fdtB])

        XCTAssertEqual(kept.count, 6, "the filter cut a good list back to \(kept.count)")
    }

    /// The model's second attempt at the same list, which is the harder half of
    /// the same bug: written without the apostrophe and with "can" for "would",
    /// every meaningful word in the first of these appears in the position, so
    /// the borrowed-words ratio is exactly 1.0. It is still a claim, and the
    /// position is still too short for that number to mean anything.
    func testTheSameListWordedSoThatEveryWordIsBorrowedSurvives() {
        let claims = [
            Claim(text: "FDT makes no meaningful claims", origin: .a),
            Claim(text: "Agents cannot calculate counterfactual outcomes of alternate decisions", origin: .a),
            Claim(text: "FDT is under specified", origin: .a),
            Claim(text: "Two agents using FDT can cooperate in the prisoners dilemma", origin: .b),
            Claim(text: "The outcome of FDT in the prisoners dilemma is preferable to other outcomes", origin: .b),
            Claim(text: "The prisoners dilemma is a concrete falsifiable example of FDT", origin: .b),
        ]

        let kept = Claim.deduplicated(claims, orEchoing: [Self.fdtA, Self.fdtB])

        XCTAssertEqual(kept.count, 6, "the filter cut a good list back to \(kept.count)")
    }

    /// The one that hurt most. It is the position's own assumption negated,
    /// which makes it the most answerable row the list was ever going to have,
    /// and six of its seven words come from the position because there is
    /// nowhere else in a sentence that short for them to come from.
    func testANegationOfThePositionIsNotAnEcho() {
        XCTAssertFalse(
            Claim.isEcho("Agents cannot calculate counterfactual outcomes of alternate decisions", of: Self.fdtA)
        )
    }

    /// And the rule still does its job on the same positions: a whole one handed
    /// back is caught however short it is, which is the case the fallback
    /// produced and nothing downstream could tell from a real point.
    func testAShortPositionHandedBackIsStillAnEcho() {
        XCTAssertTrue(Claim.isEcho(Self.fdtA, of: Self.fdtA))
        XCTAssertTrue(Claim.isEcho(Self.fdtB, of: Self.fdtB))
        XCTAssertTrue(
            Claim.isEcho("it assumes agents can calculate counterfactual outcomes", of: Self.fdtA),
            "a run lifted straight out of a short position"
        )
    }

    /// Word order is the measure, so the small words count. These two differ by
    /// one preposition and that is the difference between a lift and a claim.
    func testRunCoverageReadsWordOrderRatherThanVocabulary() {
        XCTAssertEqual(
            Claim.longestRunCoverage(of: "cooperate on the prisoners dilemma", in: Self.fdtB),
            1.0,
            accuracy: 0.001
        )
        XCTAssertLessThan(
            Claim.longestRunCoverage(of: "cooperate in the prisoners dilemma", in: Self.fdtB),
            0.85
        )
    }
}
