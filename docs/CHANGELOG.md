# Changelog

## The claim filter stopped eating good claims

A session about functional decision theory, one dense sentence per side, produced
six clean claims from the model on all four attempts and put two on the checklist.
The stage failed twice, so the app fell back to building the list out of their own
sentences, and because each position was a single sentence, each person was asked
whether they agreed with their own paragraph. Nought agreed, two split, and the
crux was drawn from that.

`Claim.isEcho` was the cause. It asks how much of a claim's vocabulary came from
the position, which is a good question when the position is four times the length
of the claim and a meaningless one when it is twice: a claim drawn from a short,
dense sentence has nowhere else to get its words. The worst casualty was the exact
negation of a position — *agents **cannot** calculate counterfactual outcomes*
against *assumes agents **can*** — which scored 0.857 and died, and which was the
most answerable row that list was ever going to have.

- The borrowed-words ratio is now consulted only where the position has room to
  have said something the claim did not (three times its length).
- Below that, what catches a played-back sentence is `longestRunCoverage`: a run
  of the claim's own words appearing in the position in order. Word-for-word is
  what the rule was always about, so word order is what it now measures.
- Both real sessions are regression tests, the old one and this one.

## The write-up stopped welding sentences together

The crux question came back without a question mark and the test without a full
stop, and the recap joined each straight onto the sentence after it: *"…on a
subset problem of the prisoners dilemma Matthew adelstein says…"*. Every other
sentence in the write-up carries its own stop; these two are a model's words
dropped in whole. `String.ending(with:)` adds one when there isn't one, outside
any closing bracket, and leaves a model that punctuated alone.

## The model provider is Mistral

The AI is **Mistral Medium 3.5**, reached through a Cloudflare Worker this project
operates. It was Gemini 3.6 Flash through Firebase AI Logic.

The reason is quota: Gemini's free tier was about 20 requests a day for the whole
app, which is six sessions shared between everybody. Mistral's is 1B tokens a
month, or roughly 4,700 sessions a day. See `docs/DECISIONS.md` for what else was
considered and why it lost.

### What changed

- **`GeminiTransport` is `ModelTransport`**, with `MistralTransport` (your own
  key) and `ProxyTransport` (everybody, free, no key) behind it. `ProxyTransport`
  moved down into `DisputeCore` — it takes an App Check token as an `async`
  closure instead of fetching one, so the package still links no binaries.
- **`worker/`** is new: the proxy, its config, and the curl that proves it refuses
  a request with no App Check token.
- **`CloudEngine.providerName`** is new. Every user-facing mention of the company
  reads from it, because the last one ended up hardcoded in nine places across two
  targets.
- **The AI card no longer says the content may be used to improve anybody's
  products.** Mistral's free tier allows opting out of training and the account
  has. That sentence is true only while the toggle stays off.
- **`FirebaseAILogic` is gone** from the project. `FirebaseAppCheck` stays, and so
  does the App Attest entitlement — only the place the token is verified moved.
- **A stored Gemini key is deleted from the Keychain** on first launch. It could
  not have signed a Mistral request, and a key that fails every call reads worse
  than no key at all.
- **`scripts/check-mistral.sh`** confirms a key works, the pinned model id is still
  served, and a real reply parses.

## Ask before sending, and a folder for Beta App Review

The AI is off until somebody says yes. The first screen asks — **Use the AI** or
**Do it by hand** — and nothing leaves the phone until it is answered.

This is Apple's guideline 5.1.2(i), amended November 2025: explicit permission is
required before personal data is shared with a third-party AI, and two people's
account of the argument they are having is about as personal as data gets. The
distinction it draws is the one the app was on the wrong side of. The first screen
already named Google, named the model, and said what the free tier means, all
before anybody could type — but above a button marked **Start**, with the AI
already on. That is a disclosure. It is not a permission.

### What changed

- **Two buttons instead of one.** Both in the pinned bottom inset, so both are on
  screen at every text size and on every phone the app supports — including a
  4.7-inch SE, where the card behind them scrolls.
- **`AIAvailability.hasChosen`**, stored as `aiChoiceMade`. `isEnabled` is now
  `chosen && stored`, which is the load-bearing part: an `aiEnabled = true`
  inherited from the build that defaulted it on does not count as somebody having
  said yes, so anyone updating is asked once, properly.
- **`choose(useAI:)` writes both defaults directly**, rather than leaning on
  `isEnabled`'s `didSet` — which is guarded on the value having changed, and so
  would persist nothing at all when "by hand" sets `false` over `false`. That bug
  would have been invisible: the session would have run by hand exactly as asked,
  and the question would have come back on the next launch.
- **The card is an offer before it is a state.** "Shall the AI do the hard
  parts?", and every sentence written as *would be sent*. The line naming Google
  moved into the subtitle, which is above the fold on the shortest screen; the
  full paragraph stays below it.
- **Reaching for the switch in Settings counts as an answer too**, so somebody
  who turns it on there is not asked again.

### Around it

- **`Beta App Review/`** — every field App Store Connect asks for before external
  testers, one file per field, in the order it asks: age rating, App Privacy,
  export compliance, beta description, what to test, review notes and contact,
  the two URLs, the build, the group. Plus the support site and privacy policy to
  publish, and what would most plausibly be rejected.
- **`scripts/screenshots.sh`** — the seven App Store screenshots at 1242 × 2688,
  from a simulator that is that size natively. `-screenshotMode` hides the debug
  beetle, which was otherwise in every one of them.
- The App Store listing copy moved to `docs/APP_STORE_LISTING.txt`, and the debug
  transcripts that were loose in the project root moved to `transcripts/`.

## Free AI, for everybody, with nothing to set up

The AI no longer needs an API key. Requests go through Firebase AI Logic on the
app's own project, on the Gemini Developer API's no-cost tier, with App Check
proving the request came from a real copy of this app. Somebody who installs
Dispute and starts arguing gets the model, immediately, at no cost to them or to
us. See docs/DECISIONS.md.

### What changed

- **No key, no account, no wait.** The first-run card no longer asks anybody to
  go to AI Studio. The AI is on by default and the first session is an assisted
  one.
- **A key is still allowed**, in a section of its own at the bottom of Settings.
  The free limit is shared between everybody using the app; a key of your own
  buys your own. Most people will not need it.
- **The card says what leaves the phone.** Free tier means Google may use what is
  sent to improve their products, and human reviewers may see samples. That was
  already true of the keys people were pasting in. It is said out loud now,
  before anybody types their side of an argument.
- **"Carry on without the AI"** on the failure screen. A shared quota can run out
  through nobody's fault, and the screen used to answer that with a retry button
  against something that would not work for hours. It now builds the checklist
  out of what the two of them already wrote and finishes the session by hand.

### Under it

- `GeminiTransport` splits *what to ask* from *how it travels*. `CloudEngine`
  keeps the prompts, the retries and the failures; `FirebaseTransport` and
  `DirectGeminiTransport` are the two pipes. The engine can be tested without a
  network for the first time — eleven new tests.
- `RefusalCause` replaces a `String` compared against `"key"` in four places.
  A rejected key, an app that App Check would not vouch for, and the safety
  filter are the same HTTP status and three different ways out. Telling somebody
  who never typed a key to go and check theirs was the bug waiting to happen.
- Three failure messages still sent people to "the model on this phone", which
  was deleted two releases ago. A test now fails if one comes back.
- `EngineError.onDeviceUnavailable` is `serviceUnavailable`. It had been
  apologising for the phone when the fault was five hundred miles away.

## Give the phone back

One report: using the app made the whole phone unusable, and it stayed that way
after the argument was over. Everything here follows from that, plus three things
asked for at the same time — one model on every phone, assumptions instead of
misinformation, and nothing that rewrites what anybody wrote.

### The lag

Four causes, all the same mistake. The app took everything the device had and
gave none of it back.

- **llama.cpp was given every core but one.** On an iPhone `activeProcessorCount`
  counts the efficiency cores: six logical CPUs, two of them fast. "Leave one for
  the UI" therefore left five threads on a phone with two cores worth having and
  four that the system needed for SpringBoard, the keyboard and the audio daemon.
  The extra threads did not even buy speed — ggml splits work evenly and waits at
  a barrier, so a thread on a slow core holds up the two that had finished.

  Now the performance-core count, asked of the kernel rather than guessed, capped
  at four and halved again when iOS reports thermal pressure. Five threads down to
  two on a phone. `InferenceBudget` holds the numbers and the reasoning.

- **The loaded model was never released.** Around 1.2 GB of weights, most of it
  wired into the GPU where iOS cannot compress it, page it out, or reclaim it
  under pressure — held from the first session until the app was killed, including
  the whole time the app sat in the background. This is why the symptom was never
  "Dispute is slow": it was Safari reloading tabs and the keyboard stuttering in
  Messages while Dispute was not even on screen.

  Fixing it needed a structural change rather than a call to a release function.
  `SessionViewModel` held the engine for the life of the session, so
  `AIAvailability` dropping its own reference freed precisely nothing. It now
  holds an `EngineSource` — a closure — and asks for an engine per call, which
  means the model can genuinely be dropped when the app backgrounds and when iOS
  sends a memory warning.

- **The key/value cache was sized for a context nothing reached.** It is allocated
  for the full context whether or not the context is used, so 4k tokens cost about
  470 MB on phones that have 4 GB in total. The prompts come to roughly 1,400
  tokens. Now 3k, quantised to Q8_0 with flash attention: about 176 MB. The lean
  configuration falls back to plain parameters if a backend refuses it, because a
  model that will not load is manual mode with no explanation.

- **Every engine call ran at the priority of the screen.** A minute of inference
  was scheduled as though it were the thing drawing the UI. Now `.utility`.
  Somebody is waiting either way; the choice is only whether the rest of the phone
  waits with them.

Also: the model is no longer read at launch. It used to be loaded up front and
handed to the session, so every cold start with the AI on read a gigabyte off disk
before the first screen appeared, whether or not anybody was about to start an
argument.

### One model, every phone

`AppleFoundationEngine` is gone, along with `AIOption`, `AppleIntelligenceStatus`,
`AppleIntelligenceHardware` and `SimulatedDevice`. Every iPhone downloads and runs
the same model.

The old split used Apple's model where it existed and a downloaded one elsewhere,
which sounds like getting the best out of each phone and was in practice two
products with one name: the same argument came back different on two handsets, a
transcript could not be interpreted without knowing which phone made it, and every
prompt change had to be judged twice against hardware nobody had both of. Apple's
model was still unmeasured against the fixtures after months, because measuring it
needed a harness that drove a device rather than a Mac.

This is a worse first run for someone with a new iPhone, who now pays a download
they used not to. It is worth naming that as a real cost rather than a wash.

The model itself moved from Q4_K_M to Q5_K_M — same weights, 150 MB more of them
surviving quantisation. Both jobs the app asks for are held to a grammar, so a
too-squashed model does not produce malformed output; it produces a well-formed
sentence that misses the point, which only a person reading the screen catches.
The context change above gave back more than this cost.

`ModelStore.removeModelsOtherThan` deletes weights left by a previous version.
Without it, changing the model would strand the old gigabyte on disk: referenced
by nothing, listed by nothing, and removable through no button in the app, while
"Remove the model" deleted the new one and left the old.

### Assumptions instead of facts

The fact check is gone. In its place the app names what each position takes for
granted — the step somebody's argument depends on but never states.

The fact check never worked and could not have. Asking a model whether a statement
about the world is true needs knowledge it may not have, gives an answer nobody in
the room can check, and hands one side a weapon when it is wrong. Over the eight
tuning debates it flagged something in all eight, including statements of value it
had itself just called unfalsifiable, and once answered a contested empirical
question with a verdict. It had no way to say "nothing here".

An assumption is a question about the text, which is the thing the model can see.
It says nothing about whether the assumption holds, and it is the more useful half:
arguments go in circles because each side is standing on something the other never
agreed to. It is on for the downloaded model, where fact checking was off.

Two safeguards, because a prompt is a request rather than a guarantee. The grammar
permits an empty list, so "nothing" is reachable. `AssumptionFlag.isUsable` drops
anything that is the quote in different words, which is this model's
characteristic failure when asked this question.

The wording rules from the old screen survive intact, because they were right even
when the feature wasn't: nothing says who wrote what, nothing says anyone is
wrong, and "Carry on" is always there and always the larger button.

### Nothing rewrites anything

`writeRecap` is gone from the protocol and from both engines. The last screen is
composed on the phone from what the two of them did.

The model was handed only settled facts and asked to say them again more fluently
— the smallest and safest version of that job. It still was not worth it. Nothing
it wrote was better enough to notice, everything it wrote was a chance to invent a
sentence about who had been closer to right, and it cost the final screen a spinner
of up to a minute at the exact moment two people have finished and want to put the
phone down. The placeholder bars that animated while they waited are gone with it.

### Also

- `-seedAssumptions` lands on the assumptions screen with two flags on it. That
  screen otherwise appears only when a real model happens to find something, which
  cannot be arranged — so the one screen that says something about a person's own
  words back to them was the one screen nobody ever looked at.
- The offer card lost a line of copy it was saying three times. The third benefit
  row pushed the download button below the fold on a 12 mini, exactly as the
  comment above that list warned it would.
- `CruxTests.swift` removed. It was untracked, referenced `Crux.restsOnCommonGround`
  and `Crux.chosen` — neither of which has ever existed in this repository — and so
  had been preventing `swift test` from compiling at all.

## What one bad argument about Starbucks found

A session where one person wrote "I like the smores frappe" and stopped. The
checklist it produced carried the same sentence twice, asked each of them whether
they agreed with their own position, and the last screen called the company
"starbucks". Every fix below is either something that session did or something
found while measuring why.

### Fixed

- **The same point appeared on the checklist twice.** Word for word, differing
  only in a capital letter, because the two sides are generated in separate calls
  and both landed on the same sentence. What let it through was the floor under
  deduplication: it was read *before* each point rather than after the filtering,
  so once the list could no longer afford a drop, everything still to come was
  kept unexamined. Four of six points got that free pass.

  The floor now sits under one rule instead of all three. A point that merely
  resembles one already kept is still protected by it, which is what it was
  written for. A point that is already on the list word for word, or that is not
  a claim at all, is dropped however short the list gets.

- **Both people were asked whether they agreed with their own words.** Three of
  the four points were sentences lifted out of the two positions, including one
  that was the whole of Position A. The person who wrote it ticked yes, the other
  ticked no, and that non-disagreement became the crux and then the write-up.

  These were being detected correctly and kept anyway, by the same floor. When
  nothing usable survives, `breakDown` now asks the model a second time — the
  sampler is seeded randomly, so the same prompt gives a genuinely different
  answer — and if that also comes back empty it fails to a screen with a retry
  button. Four points nobody can answer is not a checklist, and it costs the
  rest of the session rather than saving it.

  The copying itself is not fixed and could not be fixed here. Measured over
  thirty sessions, this model hands sentences back on roughly one in five
  whatever the prompt says, and neither a 4B model, nor 8-bit weights, nor
  switching its reasoning on changed that. What changed is that the app now
  notices.
  See DECISIONS → "Is the model good enough?".

- **And that screen asks you to write a bit more, instead of offering a retry.**
  A retry there was the wrong shape twice over: the app has already asked the
  model twice by the time you see it, and measured over the two sessions that hit
  this, the same prompt came back unusable five times in six. Pressing it spent
  twenty seconds arriving back at the same screen.

  So there is one button, and it takes you back to what you wrote. Above it are
  the three things that actually help, because sending somebody back to a box
  they have already filled in with nothing but "that didn't work" is asking them
  to guess. Nobody is told their argument was bad, or short, or wrong, and it
  never says which of the two of you was at fault — the points come out of both
  positions together and the app has no idea.

  Coming back, Done waits until you have changed something. Your text is already
  past the length gate, so without that the button is live the moment you arrive
  and pressing it runs the same half minute to the same place, which is the retry
  button again wearing a hat. Any edit at all clears it and the screen says so.

  `EngineError.notEnoughToWorkWith` carries this, and `isFixedByRewriting` sits
  beside `isRetryable` rather than being read as its opposite: a refusal is
  neither retryable nor hopeless, and writing that down caught `truncated` on the
  wrong side of it. The context window filling is fixed by writing less, never by
  running it again.

- **A point in the first person went out on the blind list.** "I like the smores
  frappe", "They're green and they rejected me from a job", "And I feel like
  there's a wealth disparity there." The check read only the opening of a claim,
  on the reasoning that an "I" further in was probably inside a quotation. All
  three of those got past it: one opens on a pronoun that was not in the list of
  openings, one hides the opening behind a conjunction, and one reaches the far
  side of the sentence before it gives itself away. Every first person word now
  counts wherever it falls, in both numbers, and the quoting exception is
  narrowed to words actually inside quotation marks.

- **The last screen read "Henry says starbucks is good".** Stances are folded
  into the app's own sentence, which means lowercasing the first letter, and the
  old rule took any first word with a small letter in it for an ordinary word.
  Their own words are now the dictionary: a word one of them capitalised away
  from the start of a sentence is kept capitalised. Nothing is guessed, and an
  argument that opens "Cost is what matters" does not go on to protect "Cost".

- **Points ran their last words together.** "The rate at which new
  jobs,skills,orindustriesarecre". This is the mid-word truncation fixed last
  pass, back in a different hat: a word bound does not stop a model that still
  has more to say, it stops it using a *space*, so it carried on writing and the
  spaces went missing. Measured over 180 generated claims the median was 15 words
  and the ninetieth percentile 26, against a bound of 30. The bound is 45 now,
  and the per-word cap is down to the length of a long English word so the rare
  jam is short.

- **The crux prompt's own example came back inside the answer.** The rule about
  giving the bare stance carried a worked example, *not "Person A believes that
  cost matters most", just "cost matters most"*, and over the eight tuning
  debates the model copied it into 6 of 16 stances: "Alex says cost matters most:
  the pace at which new work is created" reached the last screen. The example was
  added last pass to fix the doubled attribution and quietly caused this. It is
  gone; `String.withoutAttribution` was already doing the work.

  Third time this model has copied an example out of a prompt, after the two in
  this file and the one in `AppleFoundationEngine.breakDown`. Rules go in the
  prompt, sample answers do not, and anything that has to be true is enforced in
  code.

- **Three points in ten opened on "And".** They read as the back half of somebody
  else's sentence, and nothing precedes them on a checklist.
  `String.withoutLeadingConjunction` takes it off. Asking instead made it much
  worse: told not to open on "and", "but", "also" or "one might argue", the model
  opened 38 of 60 claims with "One might argue that".

- **"I like the smores frappe" was accepted as a position.** There are not three
  claims in five words, so the model had two ways to answer and used both: it
  handed the sentence back and it invented. No model fixes that. The assisted
  path now asks for a bit more before it will run, twelve words, which is not a
  standard for a good position but the point below which the next screen cannot
  be built. The screen says so once you have started typing rather than up front.
  Manual mode keeps no such floor: there the points are typed by hand and a short
  position is only context.

## A way to read the prompting, and a palette that isn't anyone else's

### Added

- **A debug transcript, in debug builds only.** A beetle sits beside the gear on
  every screen. It opens the whole session as plain text: what the two of you
  typed, the list as built with each person's answers and where they split, both
  second looks, the crux the app decided to show, and then every prompt the model
  was given with its raw answer underneath, in order, with how long each took.
  Copy it, share it as a `.txt`, or write it into the app's Documents folder and
  pull it off a simulator with `simctl get_app_container`.

  This is the one part of the app that passing tests cannot vouch for. Every test
  can be green, the engine can return a well-formed `Crux`, and the question in
  it can still be a restatement of the topic rather than the thing underneath the
  argument. Reading the prompt and the raw answer side by side is the only way to
  see that, and until now that meant a debugger and a breakpoint.

  Notes sit in the same stream as the calls, because the app is as likely to be
  at fault as the model: a crux thrown away for being too short, a write-up
  rejected as too thin, claims dropped as near-duplicates. A log of prompts alone
  makes all three look like the model found nothing.

  `PromptLog` and `DebugTranscript` are wrapped in `#if DEBUG`, nothing records
  until the app switches it on, and the release binary contains none of the
  strings. It holds everything two people wrote about their argument, which is
  why it never ships and why nothing writes it to disk on its own.

### Changed

- **No em dashes anywhere in the app's voice.** Every screen, every error, and
  every prompt now uses a comma, a colon, or a second sentence. The system prompt
  asks the model for the same, and `String.withoutEmDashes` enforces it on
  everything a model writes, because asking is a request rather than a guarantee.
  What the two people typed themselves is left exactly as they typed it: those
  are their words.

- **The house colour is iron oxide rather than terracotta**, and the AI's colour
  is verdigris rather than violet. The old pair, a light terracotta with a purple
  sparkle beside it, is what every AI feature shipped since 2023 looks like, and
  this is an app about two people arguing. Going deeper on the rust also fixed a
  contrast failure: white on the primary button passes now, and did not before.

### Fixed

- **Points stopped mid-word.** The grammar bounded each string at 160
  characters, so the only place it could close one was character 160, wherever
  in the sentence that fell. Three of six points in one session ended "whether
  one considers theobromine's effects a", "of quantities of它I", and "other
  stimulants (eg modaf". Both people ticked those anyway, and one of them wrote
  "this is cut off so I don't know what the belief here is" into the app. The
  bound counts words now, so every place the grammar can close a string is a
  place a word has just finished. Raising the character bound would only have
  moved the cliff.

- **The last screen read "Henry says person A believes that…".** The crux prompt
  calls the two of them Person A and Person B, because their names are never
  sent to a model, and the model answers in the third person as often as not.
  Every screen showing a stance has already put the name beside it, so the write
  up, the crux card and the shared transcript all read as though a third party
  were in the room. `String.withoutAttribution` takes a leading subject and
  reporting verb off what an engine returns, and the prompt asks for the bare
  stance. Both, because a 1.7B model treats a prompt as a suggestion.

- **Two of six points were sentences handed straight back.** One was Position A
  word for word, one the last two lines of Position B. Each person was asked
  whether they agreed with their own words, and each said no. Copies like these
  survive every similarity measure the app had: a position is far longer than a
  claim drawn from it, so the union is dominated by words the claim was never
  going to contain, and they scored 0.21 and 0.50. Measuring how much of the
  *claim* came from the position separates them cleanly, 0.31 against 0.94 on
  that session. A point still in the first person goes for the same reason: the
  list is ticked blind, and "I think vanilla is better" says whose it is in
  three words. The floor comes first either way, so a model that plays
  everything back leaves a poor list rather than an error.

- **The model wrote Chinese in the middle of an English sentence.** Qwen is
  trained heavily on Chinese and code-switches often enough to have done it in
  ordinary testing. The CJK blocks, Hangul and the fullwidth forms are
  unreachable in the grammar now. Nothing else is excluded, so accents, curly
  quotes and brackets all still generate.

  The prompt changes alongside these are deliberately small and carry no
  examples. Two attempts at steering the model harder each made it worse in a
  new way: naming the third person put "One thing the first person accepts is
  that…" in front of every point, and a worked example came back copied verbatim
  as "Andy says:". Same lesson as `AppleFoundationEngine.breakDown` already
  records, so the enforcement is in code and the prompt only asks.

## One question at the end, and something to build it out of

### Added

- **You now argue for a point you crossed out.** At the end of your checklist
  turn, still holding the phone, you pick one point you rejected and answer two
  questions about it: the best case someone could make *for* it, and what would
  have to be true for you to change your mind. Both of you do this blind, before
  the phone changes hands. No extra handoffs — it sits inside the turn you were
  already taking.

  This exists because ticking a list only ever produced *where* two people
  split. The app was naming the question underneath an argument from nothing but
  which rows differed, which is a guess dressed up as an answer. What someone
  says would change their mind names the thing their whole position is resting
  on, and it goes into the crux prompt as the strongest evidence there is.

- **A written record at the end.** The last screen now opens with a paragraph
  saying what the argument turned out to be: what you started on, how much of
  the list you answered the same way, the one question left, where each of you
  landed, and what each of you said would settle it. Underneath it are the
  meter, the crux, both tests, what you both signed up to, and where you each
  started.

  It is composed on the phone from what the two of you actually did, so it
  appears instantly, costs nothing, and cannot say anything that didn't happen.
  Where there is a model, that composed record is what it is handed to retell —
  never the raw argument, because a model given two positions starts reasoning
  about them again and ends up with an opinion. **Keep a copy** shares the whole
  session as plain text.

### Changed

- **The crux is one question, not a list.** `Dispute.cruxes` became
  `Dispute.crux`, every engine returns one or none, and both end screens show a
  single card given the width and the serif it deserves. The manual path lost
  its "Add another" button for the same reason: an argument with four cruxes
  named is an argument nobody has narrowed, and choosing is the work.

  For the downloaded model the enforcement is the GBNF grammar — the array
  brackets are gone, so a second crux is now unrepresentable rather than
  discouraged. `Crux.deduplicated`, which existed only to clean up the second
  crux the old shape invited, went with them. Sessions saved with the old array
  keep their first crux.

### Fixed

- **The downloaded model failed on every real argument while the tests passed.**
  Cutting the crux token cap to 220 — reasonable, since it now writes one crux
  instead of two — was fine for the three-claim test fixture and broke every
  six-point session with both second looks in it. `LlamaRunner` stopped at the
  cap and handed back what it had, mid-object, which reached the screen as
  "unexpected response". Two causes, both fixed: the grammar's whitespace rule
  was unbounded, so the model spent its budget pretty-printing `"  \n  ,  \n  "`
  between fields; and the cap is now 512 with the bound in place. Generation
  still stops when the model closes the brace, so the ceiling costs nothing.

  `LlamaRunner` now tells the two apart. Running out of room throws `.truncated`
  instead of returning a valid prefix of a valid answer for the caller to report
  as a malformed one — the difference between "raise the cap" and hunting a
  grammar bug that isn't there.

  The integration test that missed it is now built from the largest input the UI
  can produce, not the smallest one that exercises the code path.

## One model in memory, and the mark keeps swinging

### Fixed

- **Switching the AI on left the session by hand, sometimes for a minute.** The
  rebuild waited on the engine before swapping the session in, and loading the
  downloaded model reads and maps a gigabyte — tens of seconds on the phones
  that need it. For all of that the old manual session was still on screen with
  nothing saying why, so the switch read as broken. Restarting "fixed" it
  because by then the model was already loaded. The wait is now announced in the
  top bar, and the load starts the moment the switch is thrown rather than when
  a session first asks for it.
- **Playing with the AI switch could take the whole phone down.** Every flip
  started another load, in a detached task nothing cancelled. Measured on a 12
  mini with twelve rapid toggles: **peak resident memory 5999 MB** — five or six
  copies of a 1.1 GB model in flight at once, on a phone with four gigabytes.
  There is now one load allowed at a time and later callers wait on it, and the
  rebuild waits 400 ms for the switch to settle before acting. Same test, same
  phone: **peak 1462 MB**, and the app survives.
- **A new session could be marked assisted with no engine behind it.** Its mode
  came from what was asked for rather than from what actually loaded, so a load
  that failed — running out of memory on an older phone is the realistic way —
  produced a checklist built from points nobody was asked for. It follows the
  engine now, the same way `startOver` already did.
- **The Haptics switch in Settings did nothing.** Nothing ever read it. The kind
  of bug nobody reports, because from the outside it looks the same as the
  feature just not being very noticeable.

### Changed

- **The gavel goes on striking while anything is loading**, on the splash and on
  the thinking screen, instead of falling once and then sitting still. How long
  either screen lasts is not fixed — on an older phone reading a gigabyte it is
  a while — and a mark that had stopped moving read as an app that had stopped.
  The splash taps once per blow; the thinking screen does not, because it runs
  for minutes and a phone buzzing every second stops reading as feedback.
- **More of the app answers back.** Pause, Stop, the appearance picker, both
  Settings toggles, Done, the delete confirmation, and the crux Edit/Remove/Add
  controls were all silent. Weights are deliberate rather than uniform: a tap to
  acknowledge, something heavier for throwing a download away, a warning for the
  two irreversible things.

## The download is one download, and the gear can be hit

### Fixed

- **The "one-time" download asked to be done again on every launch, and each
  yes cost another gigabyte.** A background transfer outlives the app; nothing
  in `ModelDownloader` did. On relaunch it began at `.notStarted`, so a transfer
  still running in `nsurlsessiond` was invisible, the card offered "Download the
  AI" as though nothing had happened, and a tap started a second copy alongside
  the first. Do that a few times and the phone is fetching the same gigabyte
  four ways at once. It now asks the session what is already running and takes
  that over — before starting anything, on launch *and* on tap — cancelling any
  duplicates it finds, which is what gets a phone that already has them back to
  one. A note in defaults says a transfer is outstanding, so the button cannot
  appear in the moment before the session answers. Verified by starting a
  download, force-quitting mid-flight and relaunching four times: 81 MB → 103 MB
  → 140 MB, one transfer, no re-prompt.
- **The app built a fresh `AIAvailability` on most renders of the root view**,
  and with it another background `URLSession` under an identifier iOS allows
  exactly one of. `@State private var ai = AIAvailability()` reads as build-once
  and is not: SwiftUI evaluates the default every time the view struct is
  initialised and keeps the first. It is `AIAvailability.shared` now.
- **Deleting the model left the download that was fetching it running**, so the
  gigabyte came back moments after being asked to go.
- **A transfer still running for a model already on the phone was left to
  finish**, spending the rest of a gigabyte arriving at a copy of what was
  already there. Launching now stops anything in flight the moment it finds the
  model installed. On a 12 mini carrying both, the container dropped from 1.4 GB
  to 1.0 GB on the next launch and stayed there.
- **A download interrupted by the system froze the progress bar** with no way
  back to the button. It returns to the button, keeping the resume data, so the
  next tap picks up rather than starting over.
- **The settings gear was about 15pt of tappable corner** — under a third of
  Apple's minimum, and the only way into Settings from a session. It is a 44pt
  target on a tinted disc. The **Pause** button under a running download was a
  12pt word and is now padded out too.
- **The start screen raised the keyboard on arrival**, covering "How it works"
  and, on a 12 mini, most of what the screen is there to say. Two people
  deciding whether to trust this need to read it before typing into it, and the
  first field is one tap away. Both entry screens can now put the keyboard down
  — a Done item and an interactive dismiss — which on the position screen was
  previously impossible at all, its `TextEditor` taking Return as a newline.

### Added

- **Stop, next to Pause, under a running download.** Pause keeps what has
  arrived; Stop throws it away. There was only Pause, and the part-finished file
  lives in the system's transfer cache where the app never mentions it — so
  changing your mind halfway left several hundred megabytes parked on the phone
  with nothing in the interface admitting they were there.

### Changed

- `-startDownload`, a debug-only launch flag that taps the download button, so
  the start-quit-relaunch sequence can be run without a person sitting there.
  The bug above could only be caught that way, and so was never caught.
- `test-on-mac.sh` reads the bundle identifier from the project rather than
  holding its own copy. Xcode rewrites `PRODUCT_BUNDLE_IDENTIFIER` on its own —
  it had appended a digit — and the script then installed one app, cleared
  another's defaults, and launched a third that did not exist. The failure looks
  exactly like a broken simulator, and erasing does not help.

## Room for the offer, on the phone with least of it

- **The AI button is bigger on every phone** — full width, `.callout` semibold,
  15pt of vertical padding. It is the one thing the card is asking, and it now
  looks like it. `AIOnRow` matches it, so the card doesn't change size when the
  offer is accepted.
- **The band across the gavel's head is centred on the handle.** Set off toward
  the striking end it had nothing to line up with, which is exactly what it
  looked like. It reads as the collar where the two pieces meet now — a joint the
  eye already expects to find there. Also a touch lighter and a hair wider.

### Fixed

- **The introduction opened part-scrolled on a 12 mini, slicing the mark in half
  against the top of the sheet.** A `ScrollView` whose content overflows and which
  carries a bottom `safeAreaInset` was resolving its initial offset partway down.
  `.defaultScrollAnchor(.top)` pins it. The first thing anyone sees of this app
  cannot be a cropped logo.
- **`-freshInstall` reset nothing at all, in either of its last two forms.** The
  hand-written key list was replaced with `removePersistentDomain(forName:)`,
  which is documented as unreliable for an app's own bundle identifier; that was
  replaced with enumerating `persistentDomain(forName:)`, which returns nil for
  the app's own domain, so the loop never ran. Both shipped, both silently did
  nothing, and the visible symptom — the app skipping the first-run screen and
  claiming the AI was already on — looked like a bug in the app rather than in
  the flag. It is an explicit list of keys again, with a note saying why the two
  clever versions don't work.

## The mark is the icon, and it swings from the grip

`GavelMark` was a different gavel from the one on the home screen — mirrored,
with no band across the head — so the splash and the loading screen introduced
the app as something slightly other than the thing you tapped. It is now the
icon's gavel: same pose, same proportions, same lighter band.

**It swings from the grip instead of the middle.** Rotating about the centre of
the shape pivots it roughly through the head, so the head barely travelled and
the handle waved about behind it — the motion of a metronome needle, not a blow.
Anchored at the free end of the handle, the head swings through a real arc and
lands. The lift and the fall are also no longer the same speed: a blow is a slow
wind-up and a fast landing, and matched timings were half of why it read as a
pendulum.

The struck pose is the resting pose *and* the icon's pose, so every static use of
the mark is the icon and the animation is a departure from it and back.

- **The band across the head had to stop being rust.** It was drawn as rust at
  45% over a head that is already solid rust, which composites to exactly the
  head colour — it was in the code and invisible on screen. It is a white overlay
  now. Without it the head is a symmetrical bar and the mark reads as a mallet.
- **The raised pose is 3°, not further.** Past about 0° the head's far end leaves
  the circle the mark sits in. Worth knowing before anyone widens the swing.
- **The head is centred on the handle.** It was first drawn sliding along its own
  axis so more of it sat on the striking side, copying the icon. At mark sizes —
  54pt in the introduction, 96pt on the splash — that made the head hang out
  about twice as far on one end as the other, which reads as a misalignment
  rather than as a gavel. The band is what gives the head its direction; the
  silhouette doesn't need to. Verified rather than eyeballed: the handle axis now
  meets the head's centreline at exactly its midpoint.
- **The whole mark is recentred in its circle.** Swinging about the grip puts the
  head up and to the right of the pivot, so the shape sits high and right in its
  own frame and needs an offset to sit in the middle of the badge. That offset
  has to be retuned whenever the proportions change.

## Every phone gets the same offer, in the same shape

The two phones were asking for the same decision and not reading like it. An
older phone got a full-width filled button with the price on the right —
"Download the AI · 1.11 GB". A newer one got a `Toggle`, which sits quietly on
the right-hand edge and reads as a preference someone might adjust later, not as
the offer the card exists to make.

- **`AIActionButton`** is now that button, and both phones use it. The only thing
  that differs is the trailing price: "1.11 GB" or "Free". `ModelDownloadControl`
  was rebuilt on top of it, so the two cannot drift apart again.
- **`AIOnRow`** is the state after yes — "The AI is on", with a quiet "Turn off"
  — instead of a switch sitting in the on position. Once the offer has been
  accepted the card should read as settled.
- **Every phone still starts by hand.** Nothing here changes that: the button
  says "Turn on the AI" because it is off, on every phone, until someone taps it.

### Fixed

- **"Leave it off and you'll do those two steps yourselves" printed under a card
  that already said the AI was on.** That line is reassurance for someone still
  deciding. It only shows while the offer is open now.

## Tell them where to go, then notice when they've been

The switched-off card had a button reading "Open Settings". The only Settings URL
an app is allowed to open lands on *Dispute's own page*, which has no Apple
Intelligence switch on it — so the button took someone who had just been told to
look for "Apple Intelligence & Siri" and dropped them somewhere it doesn't
appear. The breadcrumb was right and the button was undoing it.

- **The button is gone.** The route is spelled out and they walk it themselves,
  which is one step longer and lands in the right place.
- **The app looks again when it comes back.** `AIAvailability.refresh()` runs on
  the return to the foreground.

### Fixed

- **Turning Apple Intelligence on changed nothing until the app was restarted.**
  `option` was decided once, in `init`. Someone who followed the app's own advice
  came back to the same card telling them to go and do the thing they had just
  done — and force-quitting was the only way past it. This was the more serious
  half of the button problem, and it would have outlived the button.
- **A cached engine could outlive the option it was built for.** `engine()`
  returns `loadedEngine` before it looks at `option` at all, so switching Apple
  Intelligence *off* mid-session would have kept running against a model iOS had
  withdrawn. `refresh()` clears it whenever the answer changes. Latent until now
  — nothing could change `option` at runtime before this.
- **`refresh()` leaves the download path alone.** Whether the hardware can run
  Apple Intelligence is fixed, so re-deciding it could only ever land a
  re-detection in the middle of a transfer.
- **It does not switch the AI on for them.** Enabling Apple Intelligence is a
  decision about the whole phone and plenty of people will have made it for some
  other app's sake. The downloaded model still does auto-enable — nobody spends a
  gigabyte on *this* app and wants it left off.

**There is no flag that fakes the switched-off phone.** One was written and then
removed. Every simulator on a Mac reports that Mac's own Apple Intelligence
answer, so the state cannot be configured — and a simulated version of it only
ever demonstrated that the simulation worked. Whether the app reads the real
switch, and notices it changing while backgrounded, is precisely the question a
fake answer cannot settle. That path is tested by switching Apple Intelligence
off on a real phone.

### The rules moved to where they can be tested

`AIOption` and everything that decides one now live in `DisputeCore`, under
`AIOption.swift`, with 18 tests behind them. They were in the app target, where
the only way to check them was to boot a simulator and look.

- **`AIOption.resolve`** — what to offer, given what iOS says and what the
  hardware could do.
- **`AIOption.adopting`** — what a re-check should adopt. Both guards are now
  pinned down: a phone on the download path is never moved off it, and an
  unchanged answer returns `nil` rather than itself, so an ordinary foreground
  can't discard a loaded engine.
- **`AppleIntelligenceHardware`** — the simulator's device-identifier table. The
  case worth having a test for is `iPhone15,4`: the *plain* iPhone 15, an earlier
  generation number despite the later name, which genuinely can't run Apple
  Intelligence. A line drawn on the marketing name gets it backwards.
- **`AppleFoundationEngine.Availability` became `AppleIntelligenceStatus`**, out
  from behind `#if canImport(FoundationModels)` so the rules acting on it compile
  and test on any SDK. The engine now only translates. It gained `unsupportedOS`
  for the case the app was already handling silently by falling through.

### Fixed, found while testing the above

- **`-freshInstall` did nothing on any simulator that `test-on-mac.sh ai` had
  touched.** That mode presets defaults with `simctl spawn defaults write`, which
  lands in a domain the app's own `removeObject(forKey:)` does not reach. Every
  later launch on that simulator skipped the first-run screen and reported the AI
  already on, whatever flags it was given. `DebugSeed` clears the whole
  persistent domain now, which also means a default added later can't be
  forgotten there. The downloaded model is a file, not a default, so it still
  survives.
- **`test-on-mac.sh` targeted `booted`, which is not a device.** It means "the
  booted device" and there is usually more than one — three, if you are looking
  at a new phone, an old phone and a switched-off phone side by side. simctl then
  picks one, and the install, the container copy and the launch can each pick a
  different one. The script resolves the name to a single UDID up front and uses
  that throughout.
- **It also relied on a launch that might not be cold.** `simctl launch` on an
  already-running process foregrounds it and silently drops the arguments, so a
  mode flag would appear to do nothing. It terminates first now.

## Three phones, three answers — and manual by default

The app had two answers for a question with three. A new iPhone with Apple
Intelligence *switched off* was being told its phone couldn't do this and
offered a gigabyte download, when the real answer was a free switch in iOS
Settings.

- **`AIOption` gained a third case.** `builtInButOff(stillDownloading:)` is
  eligible hardware with the feature off, or Apple's model still arriving. It
  never offers the download — that would be both false and expensive.
- **Manual is the default on every phone.** Not a fallback for phones that can't
  do better: the same default everywhere, so the first run is one thing to
  explain. The AI is an offer with its price stated, and the price is the only
  thing that varies.
- **The offer is worded per phone, from one place.** `AIOffer` maps the phone's
  state to the pill, the headline, the reason and the reassurance, so the
  first-run screen and Settings cannot tell the same phone two different stories.
- **An older phone is told so plainly, and told why** — "that needs an iPhone 15
  Pro or newer" — so "older" is a fact rather than a judgement, and nobody goes
  hunting iOS Settings for a switch their hardware doesn't have.
- **A phone with it switched off gets the route**, drawn as a breadcrumb through
  Settings rather than written as a sentence with arrows in it.
- **Nothing is blocked.** Start never waits on a download.

### Fixed

- **Downloading the model left the AI switched off.** A gigabyte and a Wi-Fi
  session bought a model that then sat there inert, with the toggle that would
  have used it two screens away in Settings. Installing now turns it on — only
  on that transition, so turning it off afterwards sticks.
- **A download finishing didn't change the current session.** `isReady` asked
  the store whether the model was on disk, and a disk check isn't an observable
  property — so nothing recomputed until the next launch. It reads
  `downloadState` now, which is.
- **`-seedStage` landed on the first-run screen and stayed there.** The sheet is
  modal and `interactiveDismissDisabled`, so every seeded launch silently did
  nothing.
- **A simulated iPhone 12 mini claimed to have Apple Intelligence**, because the
  simulator answers that for the Mac underneath it. In the simulator the app now
  reads `SIMULATOR_MODEL_IDENTIFIER` instead, so booting an old phone gives the
  old phone's experience without remembering a launch argument. Confined to
  `#if targetEnvironment(simulator)` — on hardware the system is still asked.
- **`handleEventsForBackgroundURLSession` is implemented.** A download that
  finished while the app was shut used to sit on disk until someone next opened
  the app. The downloader is also rebuilt on every launch, not just when someone
  taps download, because a background transfer only delivers to a session with
  the same identifier — without it the next tap started the gigabyte again.
- **New sessions no longer assume an engine.** `startOver` built an assisted
  dispute unconditionally, so a manual session got a checklist built from points
  nobody had been asked for.

### Less to read, more to look at

- **The three steps are drawn, not written** — numbered, connected by a rail,
  one line each. The long version of step three was the first thing anyone's
  eyes slid off.
- **The agreement count is a bar.** The old sentence claimed the argument was
  "smaller than it felt", which on a list they mostly split on reads as the app
  not paying attention. The bar states the proportion and lets it speak.
- **The waiting screen keeps talking.** After ten seconds it says why on-device
  generation is slow; after thirty it says outright that it hasn't frozen. The
  reassurance is time-based because there is no honest progress figure to show.
- **A mode badge on the setup screen**, so "write three points of your own" two
  screens later is something you were told about rather than something that
  happens to you.
- **The gavel comes down** on the splash, and swings slowly while the model
  works.
- **The checklist explainer is three single lines.** The long middle line pushed
  the first claim off the bottom of a 12 mini — the card that exists to stop
  people bouncing was the reason they saw nothing to tick.

### Moved

`Views/` was twelve flat files. Now `Design/` (palette, components, the mark),
`Onboarding/`, `AI/` and `Session/` (one file per screen). The Xcode project
uses synchronised folders, so the moves needed no project edits.


## Free AI on every iPhone

The app worked well on a phone with Apple Intelligence and did nothing useful on
one without. Now both work, and neither costs anything.

- **Two modes, same screens.** `DisputeMode` is fixed for the life of a session:
  `.assisted` when a model is doing the middle steps, `.manual` when the two
  people are. Nothing downstream of the checklist can tell which built it.
- **Manual mode, end to end.** Each person writes their own points on the same
  turn they say what they think, so the phone still changes hands exactly twice.
  At the end the pair name the crux themselves, starting from a filled-in draft
  built out of a point they split on rather than a blank box.
- **A downloadable model for phones without Apple Intelligence.** Qwen3 1.7B,
  4-bit, 1.1 GB, run by llama.cpp on the phone's GPU. Free, opt-in, Wi-Fi only,
  deletable, checksum-verified, excluded from iCloud backup. Chosen by running
  every candidate through the app's own prompts over all eight tuning debates —
  it matched the answer key 7 times out of 8, where the next best managed 2.
- **The app asks the system what it can do** rather than checking a list of phone
  models, which would be wrong for the iPhone 15 and wrong again every September.
- **Fact checking is now a capability an engine can decline.** The downloaded
  model flagged something in all eight tuning debates, including pure value
  statements, and once answered a contested question with a verdict — so it says
  `canFactCheck: false` and the settings toggle disappears rather than lying.
- **A first-run screen** says which mode this phone is on, what the AI would add,
  what it costs in storage, and that nothing leaves the phone either way.

Fixed along the way:

- **The crux stage could deadlock.** The engine is allowed to answer "they agree
  on everything" with an empty list, and the Continue button then stayed disabled
  forever with nothing on screen to do about it.
- **A second crux that only restates the first is dropped.** Every engine does
  this — "the impact of minimum wage increases on employment for low-skill
  workers" followed by "the impact of wage floors on employment for low-skill
  workers". Two cards saying one thing reads as broken.
- **Sessions saved by an older build still load.** `Dispute` decodes by hand now,
  because `DisputeStore` treats a decode failure as "no saved session" — the
  synthesised initialiser would have thrown away an argument in progress the
  first time anyone updated.
- **The mark is a gavel now.** It was `hammer.fill` — SF Symbols has no gavel, so
  a claw hammer was standing in, which is a different object saying a different
  thing. It is drawn from shapes, so it scales and follows the palette.
- **The model could not run in the simulator at all.** The simulator's Metal
  device advertises no simdgroup support and a 0 MB working set; handing it
  layers doesn't fail, it sits on "Reading both sides…" indefinitely. The
  simulator is where this gets tried before it reaches a phone, so `LlamaRunner`
  now falls back to the CPU there.
- **Prompts longer than one batch crashed the app** on the downloaded model.
  `llama_decode` does not return an error for this; it trips an assertion and
  takes the process down. The crux prompt is long enough to hit it, so it took
  the app out every time. Prompts are now read in slices.

Measured and rejected:

- **Two rewrites of the crux prompt.** The current one makes the model lean on
  "How much weight should be given to…" in six of eight debates. Removing the
  phrase, and separately adding worked examples, both made the answers *worse* —
  vague meta-questions instead of the actual disagreement. The prompt is
  unchanged; the duplicate-crux filter fixed the real problem.

## Fairness and clarity pass

Testers said they didn't trust it to be fair, and found it confusing. Root
cause: the app assigned people to "Person A" and "Person B" without asking, so
it looked like it had picked sides before anyone said anything.

- **Both people enter their names at setup.** Every screen afterwards uses them:
  "Alex, what do you think?", "Pass the phone to Sam", "I'm Sam".
- **Setup states plainly that order doesn't matter** — "Going first changes
  nothing. You both do exactly the same steps, in the same order."
- **The positions screen says the writing is blind, both ways** — "Sam can't see
  this, and you won't see theirs until you've both written."
- **The checklist explains itself** before the first tick: the points come from
  both answers mixed together, you aren't told which are whose so you judge the
  point rather than the person, and you both answer the identical list. This
  answers the "why am I being asked about my own argument?" complaint — you're
  not, necessarily; you can't tell, and that's the design.
- **No faint placeholder text.** Field labels sit above the box and examples sit
  below it. Grey text inside a field reads as content that's already there.
- **Contrast raised throughout** — guidance text is primary at reduced opacity
  rather than `.secondary`, which testers called faint and skipped.

### SIGTERM

Not a bug and never was. `SIGTERM` is the system asking the app to quit — which
is exactly what closing the simulator, pressing Stop, or re-running does. Xcode
pauses on it and prints "Thread 1: signal SIGTERM", which reads like a crash.
`~/.lldbinit-Xcode` now passes it through without stopping.

## First real fixture result

Ran the nuclear-power debate from `Fixtures/debates.json` end to end on-device.

- **Your expected crux:** "Whether cost and deployment speed matter more than
  nuclear's reliability and low emissions."
- **What the app produced:** "How much weight should we give to the cost per
  megawatt when deciding between nuclear and renewables?"

Same disagreement, and phrased as a question rather than a verdict. One fixture
is not a score, but it is the first evidence the small on-device model can find a
real crux.

### Fixed while testing

- **Claim generation was unusably slow.** One structured generation of eight
  claim objects took minutes and pinned the device hard enough that the simulator
  stopped redrawing. Split into two calls of three plain strings — **26 seconds**,
  and the model no longer has to label origins because the caller knows them.
- **Half the generated claims were undisputed facts.** "Nuclear plants produce
  radioactive waste" tells you nothing about where two people split. The prompt
  now asks for judgements, predictions and weightings, with at most one
  gimme for common ground.
- **The pinned button overlapped the last card.** A `VStack` sibling doesn't
  reserve space in a `ScrollView`; `safeAreaInset` does.
- **Schema bytes weren't stable.** Two encodes of the same schema differed,
  defeating the API's schema cache — `JSONEncoder` doesn't preserve `JSONValue`'s
  own key sorting without `.sortedKeys`. Caught by a test.

## Redesign — checkboxes, and two handoffs instead of eight

Noah's feedback after using it: too much passing back and forth, the process was
confusing, and it should be checkboxes.

**The flow is now four steps with two handoffs.**

| Before (8 handoffs) | After (2 handoffs) |
|---|---|
| name → positions ×2 → excavation ×2 → steelman write/judge ×2+ → crux | name → positions ×2 → checklist ×2 → crux |

- Added `Claim`: one checkable statement, with each person's yes/no. Where the
  two answers differ **is** the disagreement; where they match is common ground.
- Replaced the `excavation` and `steelman` stages with a single `checklist`.
  The AI breaks **both** positions into one combined list, and each person ticks
  what they agree with.
- **Whose claim is whose is hidden.** Told a point came from the person you're
  arguing with, you answer the person rather than the point.
- Two explicit buttons (Agree / Don't agree) rather than one checkbox: an
  untouched box and a deliberate "no" look identical, and the difference matters.
- Removed `Assumption` and `Steelman` and their tests. The steelman round was
  the biggest source of handoffs; the checklist does its job more cheaply — you
  see what the other person actually believes rather than guessing at it. Both
  types remain in git history.
- The crux screen now leads with common ground: "You agreed on 5 of 7 points."
  Most people are surprised, and it lowers the temperature before the split.

### Look

- Added `Theme`: one place for colour, cards, buttons and headers, so the app
  reads as one thing. Each side has a colour — blue and amber, never red/green,
  so neither side looks like the wrong one.
- Added a three-dot stage indicator. People kept asking how much longer it takes.
- Added "How it works" on the front screen — three lines, because people were
  reaching the checklist without knowing what would happen to their answers.
- Progress bar and running count on the checklist.
- Named loading states ("Reading both sides…") instead of a bare spinner, since
  on-device generation takes a few seconds and silence reads as a hang.

## On-device engine — the free path

Added `AppleFoundationEngine`, a second `DisputeEngine` backed by Apple's
on-device Foundation Models framework. No API key, no per-token cost, and the
argument never leaves the phone.

- Verified against the installed iOS 26.5 SDK — `SystemLanguageModel`,
  `LanguageModelSession`, `@Generable`, `@Guide` all present.
- Uses guided generation (`respond(to:schema:)` + `@Generable` types) so answers
  arrive as typed data, mirroring the JSON-schema approach used for Claude.
- `AppleFoundationEngine.isAvailable` gates use; unavailability is surfaced as
  `EngineError.onDeviceUnavailable(reason:)` with the real reason — device not
  eligible, Apple Intelligence off, or model still downloading.
- `RootView` now prefers on-device and falls back to the mock, so the app runs
  everywhere. A `-forceMockEngine` debug flag pins the mock.
- Requires iOS 26 and an Apple Intelligence-capable device. Deployment target
  stays at iOS 17; the engine is `@available(iOS 26)` and simply isn't selected
  on older systems.

**This is exactly what the `DisputeEngine` protocol was for.** Swapping the
reasoning backend touched no view, no model type, and no test.

**If on-device becomes the shipping engine, M10 disappears** — there is no key to
hide, so there is no proxy to build.

## M7–M9 — The three working stages

- **M7, positions and excavation.** `PositionEntryView` for stating a view in
  your own words; `ExcavationView` showing the assumption tree, with a recursive
  `AssumptionRow`. Each node offers "Why is that?" and "That's just what I
  value", and the depth-3 cap hides the first once it is reached.
- **M8, the steelman gate.** `SteelmanWriteView` and `SteelmanJudgeView`, with
  sub-turns inside a single stage: A writes → B judges → A rewrites, until
  approved; then the roles swap. A rejection shows the author what the other
  person said they missed.
- **M9, crux and summary.** `CruxView` and `SummaryView`. Cruxes render as
  neutral questions with each side's position, never as a verdict.

### Design change: the steelman gate no longer has an attempt cap

Previously three failed attempts force-resolved the stage. Per Noah: they keep
going until both people actually agree they have been understood, with an
AI-suggested rewrite offered after three misses as help rather than a bypass.

- `Steelman.maxAttempts` → `attemptsBeforeRewriteOffer`; added `shouldOfferRewrite`
  and `latestCorrection`. Removed `isExhausted`; `isResolved` now means approved.
- `DisputeError.noAttemptsRemaining` → `steelmanAlreadyApproved`.
- Emotional cruxes now read "This one's worth talking through rather than
  settling" rather than clinical framing.

### Other

- Added `Fixtures/debates.json` — eight debates with both sides and the expected
  crux, supplied by Noah. This is the answer key for M5: success is the model's
  crux matching the expected one in substance, not merely sounding plausible.
- Added a `-seedSkipHandoff` debug launch flag so seeded launches land directly
  on a working screen.

## M6 — Pass-the-phone shell

Built, installed, and launched on an iPhone 17 Pro simulator (iOS 26.5). The
start screen renders and correctly disables its button until the dispute has a
title.

- Added `DebugSeed` — a `#if DEBUG` launch-argument hook that starts the app at
  any stage (`-seedStage steelman`), for development and screenshots. Never ships.
- `SessionViewModel` now starts in `.handoff` whenever the current stage is taken
  in turns, so a resumed session never drops someone straight into a turn that
  might not be theirs.
- Added `SessionViewModel` — `@Observable`, `@MainActor`, sole owner of the live
  `Dispute`. Views observe and send intent; they never mutate the model or call
  the engine directly.
- Turn taking: within a per-party stage the phone passes A → B, then the stage
  advances. Non-per-party stages advance immediately.
- Engine failures land in `phase` as a recoverable state with a retry, rather
  than throwing at a view. No dead ends.
- Added `HandoffView` — the screen the second person sees first, and the
  highest-risk UI in the product. States who is being handed the phone, what
  they are about to be asked to do, and that their answer stays private until
  they are done.
- Added `StartView` (naming the dispute) and `SessionShell` (stage routing).
- Per-stage screens are placeholders that drive the state machine, so the shell
  can be walked end to end. M7–M9 replace them.

## M1 — Xcode project

- Added `Dispute.xcodeproj`: SwiftUI iOS app target, deployment target iOS 17,
  portrait only, bundle id `com.noahpuckett.Dispute`.
- Uses Xcode 16+ synchronized folders, so files added on disk are picked up
  without editing the project file. Keeps merge conflicts out of `project.pbxproj`.
- `DisputeCore` wired in as a local package dependency; the package graph
  resolves cleanly.
- Added `RootView` and the asset catalog.
- Builds and runs. The blocker was never Xcode itself — it was the missing iOS
  platform runtime, installed with `xcodebuild -downloadPlatform iOS`.

## Tests — ported to XCTest

- Replaced the `DisputeCoreChecks` executable with a real `DisputeCoreTests`
  target now that Xcode makes XCTest available. 60 tests, all passing.
- Being in-package, tests now reach internal types directly — the live JSON
  schemas in `DisputePrompts` are verified rather than a stand-in.

## M4 — Claude client over URLSession

- Added `ClaudeDisputeEngine`, speaking raw HTTPS to `POST /v1/messages`. There is
  no official Anthropic SDK for Swift.
- Uses `claude-opus-5` with structured outputs (`output_config.format` +
  JSON Schema), so responses arrive as typed data rather than prose to parse.
- Opted into server-side fallbacks (`fallbacks: "default"`) — safety classifiers
  can decline heated arguments, and without this a declined request just stops.
- Handles `stop_reason: "refusal"` before reading content, since a refusal
  arrives as a successful HTTP 200 with empty or partial content.
- Added `MessagesTransport` so the engine is verifiable without a network.
- Added `ClaudeConfiguration` with a swappable `baseURL`, so moving the key
  behind a proxy in M10 is configuration rather than a rewrite.
- Added `JSONValue` for schema literals, and explicit `CodingKeys` on every wire
  type — a key encoding strategy would rewrite schema keys like
  `additionalProperties` and break the request.
- Added `DisputePrompts`: the neutral-referee system prompt and the four task
  prompts. Drafts, not yet tuned against real responses — that is M5.
- Checks now cover request construction, header and body contents, crux decoding,
  refusal, truncation, 429/500/401 mapping, schema mismatch, and the proxy path.

## M3 — Engine protocol and mock

- Added the `DisputeEngine` protocol: excavate, deepen, findCruxes, suggestRewrite.
- Added `MockDisputeEngine` — deterministic, offline, with optional simulated
  latency and failure injection, so the whole UI can be built with no API key.
- Added `EngineError`, a small set of recoverable states with `isRetryable`.

## M2 — Data model and session state machine

- Added `DisputeCore`, a standalone Swift package holding all model types and
  business rules, with no UI dependency so it builds and tests without Xcode.
- Added `Party` and generic `PartyPair<Value>`.
- Added `SessionStage` with explicit legal-transition rules.
- Added `Assumption` (recursive tree, depth cap 3, bedrock terminals).
- Added `Steelman` with a 3-attempt approval gate.
- Added `Crux`, including an `needsConversation` flag for emotional cruxes.
- Added `Dispute` aggregate root and `DisputeError`.
- Added `DisputeCoreChecks`, a runnable verification executable covering stage
  transitions and gating, depth capping, bedrock terminals, the steelman attempt
  cap, and Codable round trips. 103 checks, all passing.
- Used an executable rather than a test target because XCTest and Swift Testing
  are both Xcode-only on macOS, and this machine has Command Line Tools alone.
  Converts to XCTest once Xcode is installed.

## M1 — Xcode project

- **Blocked.** Xcode is not installed on this machine (Command Line Tools only:
  no iOS SDK, no simulators). Install Xcode to unblock.

## M0 — Repo and docs

- Initialised the git repository.
- Committed the original idea note under its own filename, then renamed it to
  `IDEA.md` so the history preserves the original.
- Added `PROJECT_PLAN.md`, `ARCHITECTURE.md`, `CHANGELOG.md`, `TODO.md`.
- Added `.gitignore` covering macOS, Xcode, SwiftPM, and secrets.
