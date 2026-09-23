1. I don’t know how to do this. As you go through the next steps, start by giving me a tutorial on how to get you your key.
2. Disagreement
	Side A
	Side B
	Actual crux
	AI will create more jobs than it destroys
	"New technologies have always created new industries and employment. AI will raise productivity and generate new kinds of work."
	"This wave is different because AI automates cognitive work itself, potentially eliminating many jobs faster than new ones appear."
	Whether AI-driven productivity creates enough new demand and occupations to offset automation, and over what time horizon.
	Universal basic income
	"Everyone should receive an unconditional income to reduce poverty and prepare for automation."
	"Guaranteed income weakens work incentives and is an inefficient use of public money."
	Empirical disagreement about how people respond to unconditional cash and whether the benefits outweigh the costs.
	Nuclear power for climate change
	"Nuclear energy is one of the safest low-carbon electricity sources and is necessary for decarbonization."
	"It is too expensive, too slow to build, and poses waste and accident risks."
	Whether cost and deployment speed matter more than nuclear's reliability and low emissions.
	Remote work vs. office work
	"Most knowledge work can be done just as effectively from home, with happier employees."
	"In-person work improves collaboration, mentoring, creativity, and organizational culture."
	How much informal interaction contributes to long-term productivity compared with flexibility and autonomy.
	Regulating social media
	"Platforms should moderate harmful misinformation and abusive content."
	"Heavy moderation risks censorship and suppresses legitimate debate."
	Where to draw the line between reducing harm and protecting free expression.
	College is worth the cost
	"A degree still substantially increases lifetime earnings and opportunities."
	"Tuition has risen so much that many degrees no longer justify their cost."
	Whether the average return on higher education remains positive after accounting for debt, field of study, and alternatives.
	Open-source AI vs. closed AI
	"Open models promote innovation, transparency, and broad access."
	"Restricting advanced models reduces misuse and allows safer deployment."
	Whether openness produces greater net benefits or greater net risks.
	Raising the minimum wage
	"Higher minimum wages improve living standards with little effect on employment."
	"Higher wage floors reduce hiring, especially for low-skill workers."
	The size of the employment effects relative to the gains for workers who remain employed.
	3. Sure. Just say have a conversation or try to talk through it? Better language
4. I think it looks good the swift file.
5. Make the people just keep doing it until they both understand each other restatement (can include a button after 3 tries for an AI summary ig)
6. Rope question: Just push 3 Ms at a time and keep going. Tell me what to do on my end in the summary of each push.
7. I don’t have an account yet. Ill get one when we need one.
8. Just go for it.

## The quota went in an afternoon, and most of it went on thinking

**What happened.** On 2026-08-05, two people testing the app hit
`RESOURCE_EXHAUSTED` after about twenty successful requests, and it stayed spent
for the rest of the evening. It reads like a bug and is not one: the app makes
four to five calls per session, sequentially, and retries nothing on failure. The
requests in the console match the sessions one for one. Nothing is looping.

**Where the tokens went.** 23 requests over 24 hours: 14k tokens in, 1.5k tokens
of answer out, and **24k tokens of thinking**. Gemini 3 models think before they
answer, cannot be told not to, and default to `medium` on every call — so the app
was paying for sixteen tokens of deliberation per token of JSON, on calls whose
answer was already sitting in the prompt. Thinking is billed as output and drawn
from the same quota, so it is spent twice over: the free tier empties sooner, and
p95 latency was 16.2s on the one screen where two people are waiting.

**What changed.** `Thinking` is now a parameter on `GeminiTransport`, and the
choice is per call rather than per app:

| Call | Thinking | Why |
|---|---|---|
| Claims | `.low` | Both positions are in the prompt; the job is to restate them |
| Assumptions | `.low` | One paragraph in, two sentences out |
| Crux | `.standard` | The reasoning *is* the product, and the fixtures score it |

The crux is left on the model's own default rather than pinned to a named level,
because a level asked for is a level this app then owns. `CloudEngineTests`
asserts which call gets which, so an economy quietly extended to the crux fails a
test rather than quietly costing the answer the app exists to produce.

**Fewer tokens is not fewer requests, so the assumptions pass was merged too.**
It was one call per person, each seeing only its own paragraph; it is now one
call seeing both. That is a session down from four or five requests to three or
four — half of what the pass cost, on the half of the session nothing downstream
depends on — and one round trip rather than two end to end on a screen where the
phone is face up between two people.

The risk is the reason the checklist hides whose point is whose. A model holding
both paragraphs can start naming what one person assumes *because the other
contradicted it*, which is a rebuttal handed back as somebody's own reasoning, on
the one screen in the app that says something about a person's own words. Three
things hold it: a paragraph in the prompt saying both are there to save a call
rather than to be compared, a cap of two flags *each* rather than two between
them, and a live test asserting that a flag on one person quotes that person's
paragraph. None of the three is proof. Reading the answers still is.

**What none of this fixes.** If the wall is requests-per-day rather than
tokens-per-day, spending fewer tokens buys nothing on its own — though the merge
now cuts requests as well. Which dimension it was is written in the trace's own
error, in the console. The durable answer to a shared free tier is Blaze:
measured on the day above, a hard day of testing cost about **$0.21** at $1.50/M
in and $7.50/M out, or roughly four cents a session. That was ruled out for now.

`Fixtures/debates.json` has not been re-scored at `.low`, and the merged
assumptions prompt has never been run against a real model at all. Both should
happen before a build goes out on them.

## Free AI on every iPhone (this pass)

**The split.** Phones with Apple Intelligence already have a model; every other
phone does not. Rather than a table of phone models — "iPhone 15 and up" is
wrong in both directions, since the 15 and 15 Plus can't run Apple Intelligence
and the 15 Pro can — the app asks the system what it can do and picks
accordingly. That is correct today and correct for phones that don't exist yet.

**Manual mode is a first-class path, not a degraded one.** It reaches the same
screens and produces the same `Dispute`. The two things the model does are the
two things it hands back: each person writes their own points, and the pair name
the crux together. Both were placed so the phone still changes hands exactly
twice — the app already learned that more handoffs is what makes people stop
before they reach the crux.

**Naming the crux is the hardest thing the app asks of anyone**, so manual mode
never shows a blank box. They pick the point they split on that feels closest to
the root, and the app hands back a question with both their answers already in
it. Every field stays editable.

**Which model.** Qwen3 1.7B, 4-bit, 1.1 GB. Every candidate was run through the
app's own prompts over all eight debates in `Fixtures/debates.json`. Qwen3 1.7B
matched the answer key on 7 of 8; Gemma 3 1B managed about 2; LFM2.5 1.2B and
Qwen3 0.6B produced questions that restate the topic or echo the instruction back
("What is the underlying question that explains why they answered the same
way?"). Apache 2.0 also settles any question about shipping it in an App Store
app, which the Gemma and Llama licences do not.

**The crux prompt was left alone, having tried to improve it.** The current
prompt makes the model lean on one phrase — six of eight cruxes opened with "How
much weight should be given to…" — which reads as formulaic. Two rewrites were
measured against the same eight debates: removing the phrase the model was
copying, and adding worked examples. Both were **worse**, collapsing into vague
meta-questions ("What is the most important factor in determining whether
guaranteed income is a good policy?"). The formula turns out to be the right
shape: the answer key is itself mostly weighing questions. What was fixed instead
was the real defect — the second crux was often the first one reworded, so
`Crux.deduplicated` now drops it.

**Fact checking is off on the downloaded model.** It flagged something in all
eight debates, including statements it had just described as unfalsifiable, and
in one case answered a contested empirical question with a verdict of its own.
Taking a side is the one thing this app must never do. `canFactCheck` lets an
engine decline a job rather than the app shipping it and apologising, and the
settings toggle disappears rather than sitting there doing nothing.

**The download is opt-in, Wi-Fi only, and deletable.** A gigabyte of someone's
storage is not a default anyone should get by accident, and it must not be spent
on their mobile data. It is excluded from iCloud backup: it can be fetched again
for free, and a person whose phone is nearly full should not pay for it twice.

## Is the model good enough? (measured after the Starbucks session)

Two debug transcripts came back with points nobody could tick, so the question
was whether Qwen3 1.7B is simply too small for this and something else should be
doing the work. Eleven configurations were run through the app's own prompts and
the app's own GBNF, over the eight debates in `Fixtures/debates.json` plus the
two real sessions that failed. What is counted is defects, not taste: how many
generated claims are sentences lifted out of a position, how many are in the
first person, how many run their words together, how many open on a conjunction,
and how often a usable list of four comes out the far end.

**The faults split cleanly in two, and only one half is about the model.**

Some of what the transcripts showed was the app's own doing, and those went to
zero. Thirty sessions each way, 180 generated points, same weights:

| | before | after |
|---|---|---|
| points opening on "And", "But", "Also" | 29.4% | 0 |
| points with their last words run together | 3.9% | 0 |
| stances carrying the crux prompt's own example | 17 of 52 | 0 of 52 |

Each is a grammar bound, a line taken out of a prompt, or six lines of Swift, and
each was a fault the app had introduced rather than one the model has.

The other half did not move, and that is the answer to the question as asked.
Whether the model hands back sentences it was given, or writes them in the first
person, is not something the prompt reaches:

| | before | after |
|---|---|---|
| points copied out of a position | 15.0% | 12.8% |
| points in the first person | 13.9% | 15.0% |
| sessions yielding four usable points | 24/30 | 25/30 |

That is noise. On a rambling or very short position this model copies, and no
arrangement of words in the prompt stopped it. What changed is what the app does
about it: the copies are detected, the list is asked for a second time, and if
that is no better the screen says so and offers a retry. Before, the floor under
deduplication filled the list back up with the copies and the session carried on
top of them.

The two real sessions are the sharp end of this. Run three times each, only one of
those six produced a list of four points that neither person had written — the same
before and after. The difference is that the other five now end on a retry button
instead of on a checklist asking each person whether they agree with themselves.

Two attempts to fix this *in the prompt* were measured and both were worse.
Naming the fault made the model commit it: told not to open a claim on "and",
"but", "also" or "one might argue", it opened 38 of 60 claims with "One might
argue that". The other put a worked example in front of it, and it copied the
example. Both are the same lesson as the two rewrites above and the one in
`AppleFoundationEngine.breakDown`.

**A bigger model does not fit the phones that need one.** This is the constraint
that settles it, and it is worth writing down because it does not improve over
time in the direction you would hope. The downloaded model exists for phones
without Apple Intelligence, which is everything up to and including the iPhone 15
bar the two Pros — so the floor to design against is a 4 GB device like the 12
mini. Qwen3 1.7B at 4-bit measures 1.57 GB resident with a 4k context. Qwen3 4B
at 4-bit is 2.33 GB of weights before any context at all, against an iOS
foreground allowance on a 4 GB phone of roughly 2 GB. The phones new enough to
hold a 4B model are exactly the phones that already have Apple's.

Its answers *are* better to read: nothing in the first person, nothing opening on
a conjunction, and crux questions that sound like questions ("How much weight
should be given to a company's perceived cultural context when evaluating whether
it is good?"). It did not fix the copying — 32% of its points were sentences
lifted out of a position, higher than the 1.7B — and it ran 2.5× slower. Worth
revisiting if the memory floor ever moves. Not shippable now, and not the fix for
the fault that prompted the question.

**8-bit weights buy nothing.** Qwen3 1.7B at Q8_0 is 1.71 GB against 1.03 GB, a
730 MB tax on someone's storage, and it was *worse* on this set: 27% copied
against 15%, 6 usable lists against 7. Quantisation is not what is limiting this
model, so the cheapest-looking upgrade on the list is not an upgrade.

**Reasoning is switched off for the right reason.** Qwen3 is a hybrid, and the
app pre-closes its think block. Turning that on properly needs two passes,
reasoning to `</think>` unconstrained and then the answer under the grammar, and
it was measured that way rather than assumed. Worth knowing that the obvious
shortcut is not a test of anything: simply *not* pre-closing the block, while
still holding the output to the grammar from the first token, produces a model
that cannot reason and copies more than ever — 52% of points lifted out of a
position, the worst number in the whole sweep.

Done properly it fixes the cosmetics, nothing in the first person and nothing
opening on a conjunction, and it still copied on 15% of points. The cost is a mean
of 3,900 characters of discarded reasoning per call and 7 to 10× the wall time: on
the machine this was measured on, 100 seconds a session. On a 12 mini that is
minutes of spinner between two people who are already annoyed, to fix two things
that six lines of Swift fix for free. No.

**Sampling was the last cheap thing on the list, and it is not one.** The app
samples at temperature 0.3 with no top-p or top-k; Qwen's own recommendation for
non-thinking mode is 0.7 with top-p 0.8 and top-k 20. Over one sweep of ten it
looked slightly better, so it was run thirty times against the shipping settings:
21 usable lists against 25. Left alone.

**What this measurement is not.** Ten sessions per configuration, one run each,
and three runs of thirty for the before-and-after pair. Everything decided on a
single sweep of ten should be read as a hint — the sampling change looked like a
win at that size and was not — and only the thirty-session numbers are worth
leaning on.

It also counts only defects that can be counted. Whether the crux is the real
question underneath the argument is still judgeable only by reading, and one of
the things these sessions produced was a stance nobody had said: "Starbucks is
good because it's a well-known brand with a wide range of products."

A filter for that was tried and abandoned, which is worth recording so nobody
tries it twice. Measured as the share of a stance's meaningful words that appear
anywhere in the session, the invented sentence scores 0.40 against a median of
0.43 over 204 stances, and 93 of those 204 score at or below it. A real crux
paraphrases, so there is no threshold that catches invention without throwing away
half the good answers. Nothing in the app can tell the difference; a person
reading the transcript can. That is what the transcript is for.


---

## One model on every phone

The app used to run Apple's model on phones that had Apple Intelligence and a
downloaded one on phones that didn't. That sounds like getting the best out of
each handset and was in practice two products with one name.

What made it untenable was not the code, which was fine. It was that no session
could be reproduced. The same argument on two phones came back different; a
transcript was only interpretable if you knew which iPhone produced it; and every
prompt change had to be judged twice, against hardware nobody had both of. The
"which model is good enough" question in this document was only ever answered for
the downloaded one — Apple's was still unmeasured after months, because measuring
it needed a harness that drove a device rather than a Mac.

Every phone now downloads the same model. This is a **worse first run** for
someone with a new iPhone, who pays 1.26 GB they used not to, and it is worth
being honest that this is a real cost rather than a wash. What it buys: what the
app does is a property of the app. One prompt to tune, one set of failures, one
answer to "why did it say that".

## Assumptions, not facts

Fact checking is gone, replaced by naming what each position takes for granted.

The fact checking never worked and could not have. Asking a model whether a
statement about the world is true requires knowledge it may not have, produces an
answer nobody in the room can verify, and when it is wrong it hands one side of
an argument a weapon. Measured over the eight tuning debates the on-device model
flagged something in all eight, including statements of value it had itself just
described as unfalsifiable, and once answered a contested empirical question with
a verdict of its own. It had no way to say "nothing here".

An assumption is a question about the text rather than about the world. The
evidence is entirely in the prompt, the answer needs no reference to settle, and
the worst failure is a dull observation rather than a false accusation aimed at
one of two people mid-argument. It is also the more useful half: arguments go in
circles because each side is standing on something the other never agreed to, and
neither has noticed which thing that is.

Two safeguards, because a prompt is a request and not a guarantee. The grammar
permits an empty list, so "nothing" is reachable. `AssumptionFlag.isUsable` drops
anything that is the quote wearing a hat, which is this model's characteristic
failure when asked this question.

## The model no longer rewrites anything

`writeRecap` is gone. The last screen is composed on the phone from what the two
of them did.

The model was handed only settled facts and asked to say them again more
fluently, which is the smallest and safest version of that job. It still wasn't
worth it. Nothing it wrote was better enough to notice, everything it wrote was
an opportunity to invent a sentence about who had been closer to right, and it
cost the final screen a spinner of up to a minute at the exact moment two people
have finished arguing and want to put the phone down.

## What the model costs the phone

The complaint that prompted this pass was not about the app. It was that using
the app made the *whole phone* slow, and that it stayed slow afterwards.

Four causes, all the same mistake — the app took everything the device had and
gave none of it back:

1. **Threads.** `activeProcessorCount - 1`, which on an iPhone counts efficiency
   cores: five threads on a phone with two fast cores and four the system needs
   for everything else. ggml splits work evenly and waits at a barrier, so the
   threads on the slow cores hold up the ones that could have finished — they
   cost the app time *and* cost the phone its responsiveness. Now the performance
   core count, capped at four, halved under thermal pressure. Five threads down
   to two on a phone.
2. **Memory never released.** ~1.2 GB of weights, most of it wired into the GPU
   where iOS cannot compress or reclaim it, held from the first session until the
   app was killed — including the hours it spent in the background. This is why
   the symptom was never "Dispute is slow" but "everything else is slow while
   Dispute isn't even open". The fix needed a structural change: `SessionViewModel`
   held the engine, so `AIAvailability` dropping its own reference freed nothing.
   It now holds an `EngineSource` closure and asks per call.
3. **A key/value cache sized for a context nothing reached.** Allocated in full
   regardless of use: ~470 MB at 4k tokens. Now 3k and quantised to Q8_0, ~176 MB.
4. **Priority.** Every engine call ran at the same quality of service as the
   thing drawing the screen, so iOS scheduled a minute of inference ahead of the
   system's own work. Now `.utility`.

None of this is visible in a simulator, which has a Mac's cores and nothing else
competing for them. That is why it survived so long, and why the numbers above
still need checking on hardware.

## Why not a smarter model

Asked for. Not possible while "the same version on every phone" also holds.

The app's deployment target reaches phones with 3 GB of RAM, where roughly 1.4 GB
is available to a single app. The weights are not the whole cost — the key/value
cache and compute buffers sit beside them — so the practical ceiling for the
model file is a little over a gigabyte. Qwen3 1.7B at Q5_K_M is 1.26 GB and is
close to the best available at that size; Qwen3 4B, the next real step up in
reasoning, is 2.5 GB and simply cannot load on those devices.

Raising the deployment target would buy the headroom, at the cost of dropping
phones the app currently runs on. That is a product decision rather than a
technical one and has not been made here.

The honest way past the ceiling is not a bigger download. It is a hosted model —
which the app deliberately does not have, for the privacy reason recorded in the
README. Anything that changes that has to answer the same question: an argument
is among the most sensitive text a person will type, and "nothing leaves the
phone" stops being true the moment one code path can send it somewhere.


---

## The crux carries a test now

The app used to name the disagreement and stop. That is a diagnosis: two people
who walked in stuck walked out stuck, holding a better description of being
stuck.

Two changes. First, the crux has to be a *double* crux in the sense the technique
means — the one question where **both** of them would move, not a thing they
happen to disagree about. A question only one person's mind hangs on is that
person's objection; settle it and the argument carries on exactly as before,
which is the failure this app exists to stop. The prompt now says so, tells the
model to test its answer once per person, and `Crux.isShared` catches the
characteristic failure where a model that could not find a real split writes the
same stance into both slots.

Second, the crux carries `test`: the one concrete thing they could go and find
out. "Write down a year of costs and compare the number against the raise" is a
thing that happens on a Tuesday. `Crux.hasTest` rejects the two sentences a model
writes when it has nothing — talk more, research more — because both are what
these two have already been failing to do, and telling them so on the last screen
would be the most insulting thing in the app. Manual mode drafts a test by
splicing both people's "what would change my mind" answers, which is the same
material the model is asked to build one from.

## Gemini as an option

The privacy promise is no longer absolute, and this is the decision that changed
it. The on-device 1.7B is fine at splitting positions into claims and weak at the
part that matters: reading two paragraphs of a real argument closely enough to
find the question underneath rather than a question near it.

So Gemini 3.6 Flash is an option, off by default, behind a free key the person
gets themselves. What changes when it is on is said on the screen that turns it
on, and the privacy line in Settings changes with it. That conditional copy is
the part worth keeping: the old line said "nothing is uploaded" unconditionally
and would have gone on saying it, which is worse than having no privacy section
at all, because somebody reads it and believes it.

The key lives in the Keychain, not `UserDefaults` — a plist in the container that
goes into iCloud and device backups would put somebody's credential in every
backup they ever restore from.

## The loop

Two screens could not be escaped, and both were the same bug.

The assumptions screen offers "go back and add to it". That returns to the
positions stage and clears everything derived from it, including the flags — so
when the stage ended again the pass ran again, found assumptions again (there are
always assumptions), and put them back on the same screen. Going back was a
button with no exit; the only way on was to notice the other, quieter button.

The fix is that the screen shows at most once per argument, and the record of
having shown it deliberately survives `returnToPositions` — it has to survive the
thing that clears everything else, which is the whole point.

The second: `notEnoughToWorkWith` sends them to a screen asking for more words,
which sends them back to positions, which can fail identically. Now the second
failure stops asking and builds the checklist out of their own sentences.
Duller than drawn-out claims, and infinitely better than a screen with no way
past. Both counters persist, so a relaunch does not reopen either cycle.

## Verdigris leads, brass complements, rust warns

Three roles, arrived at in two goes.

Rust was the house colour. It is a hot colour — it reads as alert, as the thing
you press when something is wrong — and on every primary button it meant an app
about two people arguing was also shouting at them from the first tap. The point
of this app is to take heat out of a disagreement; it should not be the loudest
thing in the room while doing it. So verdigris leads.

Demoting rust to "general accent" was better and still wrong. It was on the "by
hand" pill, on the entry hint, and on the half of the agreement meter showing
what the two of them still disagree about — so an app whose entire claim is that
it takes no side was colouring *disagreement itself* in warning red. Nothing
about two people not yet agreeing is an error.

So rust means one thing now: the app has failed at something. It appears on the
failure screen and nowhere else, which is what makes it mean anything — a colour
used for emphasis cannot also be used for alarm.

What took over the emphasis work is brass. Warm metal against cool oxide is the
pairing you get on any old copper fitting, and it works here for the same reason:
both aged, neither shiny, and on tan paper it reads as highlighted rather than
flagged. It is deep enough to carry caption-sized text on the light background,
which is what rules out the brighter golds — a yellow that looks best as a large
fill is a yellow that fails on the 11pt label under it.

Party A moved twice for the same reason each time. It was rust while rust was
every button, so A's colour read as the app agreeing with A; then rust became the
alert colour, so A's colour read as the app flagging A. Brass against ink-blue is
warm versus cool with nothing implied about either.


---

## The on-device model is gone

The app downloaded Qwen3 1.7B and ran it through llama.cpp. That is all removed:
the `DisputeLlama` target, the 31 MB vendored xcframework, `LocalModel`,
`ModelStore`, `ModelDownloader`, `InferenceBudget`, the GBNF grammars, the
download UI, the background-session app delegate, and everything in
`AIAvailability` that existed to manage a gigabyte. Gemini is the only engine.

It is worth being precise about what was lost, because it was not nothing. The
downloaded model needed no key, no account and no connection; it worked on a
train and it worked for somebody who would never sign up for anything. Every
sentence in this app about nothing leaving the phone was true because of it.

What it could not do was the job. Both remaining tasks — read two paragraphs of a
real argument and name the question underneath, name what those paragraphs take
for granted — reward reading closely, which is exactly what a 1.7B model does
not do. It returned something well-formed, correctly shaped, grammatically
constrained and shallow, and two people who had just typed out a genuine
disagreement could tell immediately. Nothing in the app could tell: it parsed,
it passed every assertion, and it was still a question *near* the argument
rather than the one underneath it.

Everything else about it was infrastructure in service of that answer. A 1.26 GB
download over Wi-Fi with a checksum. A background `URLSession` that had to
survive the app being killed mid-transfer. A gigabyte of wired GPU memory that
made the whole phone slow until it was released on backgrounding and on memory
warnings. A thread budget tuned against the rest of iOS. Deleting weights left
behind by earlier versions. All of it worked, and all of it was in aid of a
result nobody was happy with.

**The app got smaller in every direction.** The binary is 4.9 MB against roughly
11. The package links nothing and builds with the command line tools alone. The
test suite went from 235 to 186, and the ones that went were the ones testing
machinery rather than behaviour.

**What it costs.** The app now needs a free API key before the AI does anything,
and a connection while it does. That is a real barrier: some people will not get
a key, and the by-hand path — which is still the default on first run and still a
complete way to use the app — is what they get. If that turns out to be most
people, this decision was wrong and the answer is a hosted key behind the app's
own server rather than a return to a model that could not do the job.


---

## The key is gone too

The last entry ended by naming the condition under which it was wrong: *if that
turns out to be most people, the answer is a hosted key behind the app's own
server.* It was most people. Getting a key out of AI Studio takes about a minute,
and it is a minute spent standing in a kitchen mid-argument, which is the worst
moment anybody has ever been asked to go and make an account. The AI card was
doing the work of a signup page on the screen before the Start button.

So: **Firebase AI Logic**, on the Gemini Developer API's no-cost tier. Requests
go through the app's own Firebase project. Nobody signs up, nobody pastes
anything, and nobody pays — not the two people arguing, and not the person who
made the app.

**Not a server of our own.** The obvious alternative was a small proxy holding
the key. That is a thing to deploy, a thing to pay for, a thing to keep patched,
and a thing that goes down at two in the morning. Firebase AI Logic is that
proxy, run by Google, and the phone's half of it is an App Check token rather
than a credential — a statement from Apple, signed by the Secure Enclave, that
this is an unmodified build of this app on a real device. Without that the
project's endpoint would be open to anybody who read `GoogleService-Info.plist`
out of the app bundle, and one script would spend the day's quota before either
of two people had finished typing.

**What it costs, and who pays it.**

- *The quota is shared.* The no-cost limits belong to the project, not to the
  phone, so a busy day means somebody hits `rateLimited` having done nothing
  wrong. This is the real price of the change and it is not hidden: the failure
  screen offers to finish the argument by hand, and anybody who would rather not
  share the pool can still add a key of their own in Settings and get their own.
- *Free means Google may read it.* The no-cost tier is covered by Google's terms
  for unpaid services: what is sent may be used to improve Google's products, and
  human reviewers may see samples. This was already true of the free AI Studio
  keys people were pasting in, so nothing about the arrangement is new — but it
  is now true by default rather than by somebody's choice, which makes it the
  app's job to say so. It is on the AI card, in plain words, before anything is
  typed.

**What it bought, beyond the minute.** The seam that made it possible —
`GeminiTransport` — made `CloudEngine` testable without a network for the first
time. Eleven tests now cover what the app does with a fenced JSON reply, a
too-thin list, a crux with no test in it: all things that previously could only
be asked by spending real quota and hoping the model misbehaved that day.

**And a dead end closed.** Writing "or carry on by hand" into the rate-limit
message meant a button had to exist for it, and it did not. `continueByHand()`
now gives up on the model mid-session and builds the checklist out of their own
sentences. That failure was survivable when the quota was one person's key and
they could go and check it; it is ordinary now, and the screen that handles it
was offering a retry against something that would not work for hours.


---

## Rust leads after all

The palette has now been round twice, and the entry above ("Verdigris leads,
brass complements, rust warns") is superseded rather than wrong. Its objection
still stands on its own terms: a hot orange-red on every primary button made an
app about two people arguing feel like it was shouting at them.

What that objection missed is that rust has a brown end. Iron oxide the colour of
a rusted hinge or a terracotta pot is dark, dull and completely calm — nothing
like the red-orange that got demoted. Verdigris and rust are the same idea told
twice anyway: both are what a metal becomes when it is left alone for years, one
copper and one iron, and neither is in a hurry. The house colour is now the brown
end of that, 7.2:1 against white so the button label has room to spare.

**The forced move.** Rust cannot be the house colour and the alarm at once — a
colour used for emphasis cannot also be used for alarm, which is the rule the
palette already had. `alert` is oxblood now: redder, more saturated, no brown in
it, and it still only appears on a screen that has already said "didn't work" in
words with a triangle next to it.

**What did not move, and why that took arguing with.** Brass stayed the
complement. Verdigris was suddenly free and was the obvious swap, and it would
have put two greens either side of the agreement meter — sage for what the two of
them agreed on, verdigris for what they did not. A meter whose halves are both
green is unreadable at a glance, which is the only way it is ever read: over
somebody's shoulder while the phone changes hands.

**And the AI card stopped being green.** Its "Ready" state was drawn in `agree`,
the sage that means *the two of you already agree about this*. The AI being
switched on is not agreement, and it was the largest green shape on the first
screen anybody sees. It is `assist` now, which is the house colour, which is
what that name was kept for.

---

## The model is Mistral now

Gemini's free tier gave `gemini-3.6-flash` about 20 requests a day, and the quota
belongs to the project rather than to each phone. Three calls a session makes that
six sessions a day, shared between everybody who has the app. That is not a free
tier with a tight ceiling; it is a demo.

Mistral's free tier is 1 request/second, 500K tokens/minute and 1 billion tokens a
month. A session costs about 7,000 tokens — measurable from the prompts, and
measured — which is roughly 4,700 sessions a day. Same order of capability on the
two jobs that matter here, three orders of magnitude more of it.

**The alternatives were checked rather than assumed.** Groq's advertised 14,400
requests a day is only on Llama 3.1 8B, which is the class of model this app
already rejected once and for exactly these two tasks; its good models are capped
at 100–200K tokens a day, or 14–28 sessions. Cerebras' free tier became $5 of
expiring credits behind a payment method. OpenRouter's free models cannot be used
without enabling *may train on inputs* and *may publish prompts*, which is not
shippable for an app whose entire consent screen is about what happens to two
people's argument. NVIDIA is 5,000 lifetime credits. Chutes closed its free tier.

**What it cost.** Firebase AI Logic did two jobs — held the credential and made
the call — and it will not proxy to anybody but Google. So the app has a server
now, for the first time: a Cloudflare Worker on the free plan that holds the key
and forwards the request. That is a real loss. "There is no server of ours" was a
true sentence in the review notes and is not one any more, and the privacy policy
had to grow a paragraph rather than lose one.

What softened it: the Worker stores nothing, and App Check did not change at all.
The same App Attest token, checked against the same Google public keys, just
checked in our Worker instead of inside Firebase — which needs only the public
half, so it costs nothing on either side and the entitlement in the app's
declarations is still accurate.

**What it bought, beyond quota.** Gemini's free tier had no way to opt out of
having user content used to improve Google's products, and the AI card had to say
so before anybody typed. Mistral's does, and the account uses it. The card now
says the opposite. That is the clearest thing the two people in front of the phone
got out of this, and it is also the most fragile: it is a claim about an account
setting, asserted in three documents that have to change together if it is ever
turned back on.

**What the seam was worth.** `GeminiTransport` existed so that how the bytes
travel could change without touching what gets asked or what counts as an answer.
That bet paid: the prompts, the retries, the JSON tolerance, the failure mapping
and every screen are untouched. The protocol was renamed `ModelTransport` in the
same commit, because a protocol named for a company the app no longer talks to is
the kind of thing that is still there three providers later.
