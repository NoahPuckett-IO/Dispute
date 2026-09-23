import Foundation

/// The words every engine is given, in one place.
///
/// Shared deliberately. Both engines run on the phone and both are asked the
/// same things in the same order, so a prompt improved for one is improved for
/// the other — and a difference between what an iPhone 17 and an iPhone 12 are
/// asked would be invisible until someone compared two phones side by side.
///
/// What each engine does *not* share is how it is held to a shape: Apple's
/// takes a `@Generable` type, the downloaded model takes a GBNF grammar. Those
/// live with their engines, because they are facts about the model rather than
/// about the request.
public enum DisputePrompts {

    // MARK: - Voice

    /// Prepended to every request. The app is a referee, not a participant and
    /// not a therapist — and its users are upset while reading it.
    public static let systemPrompt = """
        You are the neutral referee inside Dispute, an app two people use when an \
        argument is going in circles. They are passing one phone back and forth.

        Your job is to expose the structure of their disagreement. It is not to \
        settle it.

        Rules you never break:
        - Never take a side, and never hint at one. Not in word choice, not in \
        ordering, not in which point you spend more words on.
        - Never diagnose, counsel, or comment on the relationship between these \
        people. You do not know who they are to each other.
        - Never moralise, and never praise them for using the app.
        - Write plainly. Short sentences. No jargon, no therapy-speak, no \
        headings, no emoji.
        - Never use a dash as punctuation. Use a comma, a colon, or a full stop \
        and a second sentence.
        - Use their own words wherever you can.
        - Assume the reader is angry and impatient. Anything that reads as \
        condescending gets the app closed.
        """

    // MARK: - Breaking a position into claims

    /// One side at a time, for engines where a single large structured
    /// generation is too slow — notably the on-device model, where asking for
    /// eight claim objects in one go takes minutes and pins the device.
    ///
    /// Splitting it also removes a job the model was doing badly: it no longer
    /// has to label which position a claim came from, because the caller knows.
    public static func claimsForOneSide(
        position: String,
        otherPosition: String,
        disputeTitle: String
    ) -> String {
        """
        The argument: \(disputeTitle)

        This person says:
        \(position)

        The person they're arguing with says:
        \(otherPosition)

        Write three claims that the first person's view depends on.

        Every claim must come from the two statements above and be about that \
        subject. Use their words and their subject matter. Do not introduce a \
        topic, example, or field that neither of them mentioned. If it isn't in \
        what they wrote, it doesn't belong.

        A claim is one specific thing that could be true or false, which either \
        of them could accept or reject on its own. Most should be things the two \
        might answer differently: a judgement, a prediction, or a weighing of one \
        thing against another. Avoid anything both would obviously accept, since \
        that tells you nothing about where they split. Include one they'd both \
        likely accept, but only one.

        Write each so someone on either side could answer it. Do not name either \
        person, and do not phrase it so one answer is obviously right.

        Never copy a sentence out of what either of them wrote. A line handed \
        back is not a claim, it is their own turn played back at them, and they \
        will be asked whether they agree with it.

        Give the claim on its own, with no lead-in and nothing about whose it \
        is. Both of them work through this list without being told which points \
        came from which side.

        One plain sentence each.
        """
    }

    /// Both sides in one request, for a model big enough to hold them at once.
    ///
    /// The split version above exists because one large structured generation
    /// takes minutes on a phone. Where that constraint is gone, joining them back
    /// up is not just cheaper — it is better. A model shown both positions can
    /// see when the two of them are making the same claim in different words and
    /// decline to write it twice, which is a judgement the deduplication
    /// afterwards can only approximate by comparing strings.
    ///
    /// It also lets the instruction that matters most be stated once and apply to
    /// the whole list: the points have to be answerable by both of them, and the
    /// list has to be worth ticking rather than six things everybody agrees with.
    public static func claimsForBothSides(
        positionA: String,
        positionB: String,
        disputeTitle: String
    ) -> String {
        """
        The argument: \(disputeTitle)

        The first person says:
        \(positionA)

        The second person says:
        \(positionB)

        Write three claims each side's view depends on: three for the first \
        person, three for the second.

        A claim is one specific thing that could be true or false, which either \
        of them could accept or reject on its own. Both of them will work through \
        the combined list without being told which point came from which side, so \
        every one has to be answerable by either of them.

        Make the list worth ticking. Most claims should be things the two might \
        answer differently: a judgement, a prediction, or a weighing of one thing \
        against another. One or two they would both accept is useful, because \
        finding unexpected agreement is half of what this is for. Six things \
        nobody would dispute is a wasted screen.

        Seeing both positions at once, do not write the same claim twice in \
        different words. Where they are making the same point from opposite \
        sides, pick the side it belongs to and leave the other slot for something \
        else.

        Every claim must come from the two statements above and be about that \
        subject. Use their words and their subject matter. Do not introduce a \
        topic, example, or field that neither of them mentioned.

        Never copy a sentence out of what either of them wrote. A line handed \
        back is not a claim, it is their own turn played back at them, and they \
        will be asked whether they agree with it.

        Do not name either person, and do not phrase a claim so that one answer \
        is obviously right. One plain sentence each, no lead-ins.

        Answer as JSON: {"claims_a": ["…", "…", "…"], "claims_b": ["…", "…", "…"]}
        """
    }

    // MARK: - Assumptions

    /// Names what a position is standing on without saying so.
    ///
    /// This is the one job in the app where the model is asked to say something
    /// about a person's own words back to them, so the whole prompt is built
    /// around making that safe. Three rules do the work:
    ///
    /// - it describes, never challenges. "This takes as given that …" is a
    ///   sentence about the shape of an argument; "you have not shown that …" is
    ///   the app joining in;
    /// - it never says whether the assumption is *right*. That is the fact check
    ///   this replaced, and the reason it was replaced — see `AssumptionFlag`;
    /// - it is asked for the assumption the person themselves would not have
    ///   thought to state, because an assumption they would happily state out
    ///   loud is just their position again, and being handed your own view back
    ///   as a discovery is the most annoying thing a referee can do.
    ///
    /// Two at most. This is one card between two turns, not a critique, and a
    /// list of six unstated premises reads as the app finding fault with the
    /// person whose turn just ended.
    /// Both positions in one call, and the one rule that makes that safe.
    ///
    /// This was two calls, one per person, each seeing only its own paragraph.
    /// Merging them halves what the pass costs a shared quota and takes a screen
    /// two people are waiting on from two round trips to one. What it risks is
    /// the reason the checklist hides whose point is whose: a model holding both
    /// paragraphs can start naming what A assumes *that B disputes*, which is B's
    /// rebuttal wearing an assumption's clothes, and the app would be handing
    /// somebody the other side's objection while calling it their own reasoning.
    /// Hence the paragraph telling it to read each on its own.
    public static func assumptions(
        positionA: String,
        positionB: String,
        disputeTitle: String
    ) -> String {
        """
        The argument: \(disputeTitle)

        The first person wrote:
        \(positionA)

        The second person wrote:
        \(positionB)

        Name what each of them takes for granted. An assumption is a step the \
        writing depends on but never states: something that would have to be true \
        for their point to follow, and that the other person might simply not \
        grant.

        Read each of them on its own. Both are here to save a call, not to be \
        compared: what one person wrote is not evidence about the other, and \
        anything you would name only because the other person contradicted it is \
        their rebuttal rather than something being taken as given. Judge each \
        paragraph on its own words.

        Find at most two each, and fewer is better. Pick the ones the writer would be \
        surprised to be asked about, because those are the ones an argument gets \
        stuck on. Something they clearly meant to say is their position, not an \
        assumption, so do not hand it back to them.

        For each one:
        - "quote": the exact words from what they wrote that rest on it. Copy \
        them exactly, and keep it short.
        - "assumption": one plain sentence naming what is being taken as given.

        Say only what is being assumed. Do not say whether it is true, likely, \
        reasonable, or mistaken. Do not say the other person disagrees with it. \
        Do not suggest what they should do about it, and do not address them \
        directly. You are describing the shape of an argument, not answering it.

        Return an empty list for either of them if nothing qualifies. That is a \
        normal answer, and a weak assumption is worse than none.

        Answer as JSON: {"assumptions_a": [{"quote": "…", "assumption": "…"}], \
        "assumptions_b": [{"quote": "…", "assumption": "…"}]}
        """
    }

    // MARK: - The crux

    /// One question. Not a list.
    ///
    /// The model used to be asked for "at most two, most important first", and
    /// would take that as permission to hedge — two questions where one was the
    /// crux and the other was a restatement of the topic. Asking for exactly one
    /// makes it choose, which is the work.
    ///
    /// Nothing quotable in it, for the third time. The stance rule below was
    /// written out with a worked example on it — *not "Person A believes that
    /// cost matters most", just "cost matters most"* — and measured over the
    /// eight debates the model copied the example into the answer on 6 of 16
    /// stances, which reached the last screen as "Alex says cost matters most:
    /// the pace at which new work is created". That is the same thing this
    /// model did to the last two examples anyone put in front of it, recorded in
    /// docs/DECISIONS.md and in `AppleFoundationEngine.breakDown`. It copies
    /// what it is shown. Rules here are stated abstractly and anything that has
    /// to be *true* rather than asked for is enforced in code afterwards, which
    /// is what `String.withoutAttribution` is.
    public static func findCrux(
        disputeTitle: String,
        positionA: String,
        positionB: String,
        agreed: String,
        contested: String,
        secondLooks: String
    ) -> String {
        """
        The argument: \(disputeTitle)

        Person A says: \(positionA)
        Person B says: \(positionB)

        They both went through the same list of claims. These are the ones they \
        answered the same way, their common ground:
        \(agreed.isEmpty ? "(none)" : agreed)

        These are the ones they answered differently:
        \(contested.isEmpty ? "(none)" : contested)

        \(secondLooks.isEmpty ? "" : """
        Each of them then took one point they had rejected, argued the other \
        side of it, and said what would change their mind:
        \(secondLooks)

        Those last answers are the best evidence you have. What someone says \
        would change their mind names the thing their whole position is resting \
        on. Where the two of them are waiting on different things, that gap is \
        usually the crux itself.
        """)

        Name the crux, and say what would settle it.

        A crux is a question where, if it were settled, someone would change \
        their mind about the argument itself. What you are looking for is the one \
        that works on BOTH of them: settle it one way and the first person \
        concedes, settle it the other way and the second does. That is the whole \
        job. A question only one of them is waiting on is that person's \
        objection, not the crux, and answering it leaves the argument exactly \
        where it was.

        Test yours twice, once per person: if that person got the answer they did \
        not expect, would they actually shift? If either answer is no, you have \
        the wrong question, so go deeper. Usually both positions are reasonable \
        given what each believes about one underlying question. Find that \
        question. It is often about how much weight to give two things they both \
        agree matter, or a fact neither has established.

        It must be about this argument and their words, never a topic neither of \
        them raised. Return exactly one. Do not hedge by naming something broad \
        enough to cover everything they said.

        - "question": the disagreement as a neutral question they can both look \
        at. Not a verdict, and not phrased so one answer sounds correct.
        - "position_a" and "position_b": where each lands, one short sentence, in \
        their own words where possible. These must differ from each other. Give \
        the stance by itself. Do not name either person in it and do not open on \
        a verb of believing or saying. The app writes their name in front of your \
        sentence, so anything of that kind you put there arrives twice.
        - "test": the one thing they could actually go and do that would settle \
        it. Concrete and small enough to finish: a number to look up, a person to \
        ask, a thing to try for two weeks and then compare. Name the thing and \
        where the answer comes from. It must be something whose result would move \
        whichever of them turns out to be wrong, so build it out of what they \
        each said would change their mind. Never "communicate more", never "do \
        more research", never "discuss it further" — those are what they have \
        been doing, and they are why they opened this app.
        - "needs_conversation": almost always false. True only when the \
        disagreement is about the relationship between these two people: feeling \
        dismissed, disrespected, or not listened to. Anything about facts, costs, \
        risks, predictions, or which of two things matters more is false, even \
        when people feel strongly. If unsure, false. When this is true the test \
        may be a conversation to have rather than a fact to find, and should name \
        what that conversation has to establish.

        If they genuinely agree on everything, return an empty question string.

        Answer as JSON, with exactly these keys: {"question": "…", \
        "position_a": "…", "position_b": "…", "test": "…", \
        "needs_conversation": false}
        """
    }

    // MARK: - The write-up
    //
    // There isn't one, and that is deliberate. The last screen is composed by
    // `ArgumentRecap` out of what the two of them actually did. The model used to
    // be handed those same settled facts and asked to say them again more
    // fluently, which is the smallest possible job and still cost the final
    // screen a spinner — at the one moment in the app where two people have
    // finished and want to put the phone down. Nothing it wrote was better
    // enough to be worth the wait, and everything it wrote was a chance to
    // invent a sentence about who had been closer to right.

    /// Claims as a plain bulleted list, the shape every prompt above expects.
    public static func list(_ claims: [Claim]) -> String {
        claims.map { "- \($0.text)" }.joined(separator: "\n")
    }

    /// What each person said when asked to argue for a point they had rejected.
    ///
    /// Empty when neither of them was asked — an argument where both ticked
    /// everything skips that screen, and a heading with nothing under it invites
    /// the model to fill the gap.
    public static func secondLooks(in dispute: Dispute) -> String {
        Party.allCases.compactMap { party -> String? in
            guard let rethink = dispute.rethinks[party], rethink.isComplete,
                  let claim = dispute.claim(withID: rethink.claimID)
            else { return nil }

            let label = party == .a ? "Person A" : "Person B"
            return """
            \(label) rejected "\(claim.text)".
            The best case \(label) could make for it: \(rethink.bestCase)
            What would change \(label)'s mind: \(rethink.changeCondition)
            """
        }
        .joined(separator: "\n\n")
    }
}
