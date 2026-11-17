# Kid Tutor — Plan

A custom iPad tutor for one elementary-school child that works fully offline. It uses FSRS
spaced repetition (the algorithm modern Anki uses) and goes beyond flashcards: everything is
spoken aloud, answers are handwritten with Apple Pencil, and sessions are short. Practice earns
tokens for a claw-machine game that wins stuffed animals for a toy chest. Lessons are TOML files
a parent writes in an iCloud Drive folder, and progress is saved to the same folder. A parent
dashboard sits behind a PIN.

## Status (2026-11-17)

**Built:** Reading, Writing, Spelling, Math and Puzzles; the claw machine and toy chest; the grown-up
area (settings, handwriting calibration, recognizer test and results, per-subject Progress pages with
resets). Each section below ends with what was built and what's left. The README lists the features;
ARCHITECTURE.md maps the code.

**Not built yet:** "A bit of everything" (shows "coming soon"), Vocab, FSRS scheduling (each subject has
a simple planner, so there are no due dates yet), lesson files and the iCloud folder (content is the
built-in starter lists), milestones and real-world rewards, the PIN-protected parent dashboard.

**Known limitations**

- Handwriting accuracy depends on calibration samples; with only a few per character expect misreads.
  Characters with fewer than 2 samples are accepted unchecked so the child isn't blocked.
- The wide whole-word box (Spelling's top level, Writing's look-cover-write) splits a word into letters;
  letters that touch can't be split, and then Apple Vision decides. Checked mostly with synthetic ink.
- Apple Vision is only a baseline: it can't read single letters in `.accurate` mode.
- Reading's matching is generous ("book" counts for "look"); it may need to be stricter. Listening has
  been tested on the iPad, but only by the owner, not yet with the child.
- Puzzles were played through in the Simulator; try them on the iPad, including landscape.

**Next steps (owner to choose)**

1. Try everything on the iPad with the child: Pencil handwriting, Reading's listening, puzzles, voices.
2. Puzzles, part 2: groups of things (animals, food, vehicles), shape sudoku, balance scales, ordering, Pencil mazes.
3. "A bit of everything": a mixed session drawn from the built subjects.
4. The iCloud lesson folder (Storage below): TOML lessons, progress and logs in the folder. Needs the
   paid developer account's iCloud entitlement.
5. Rewards, part 2: milestones, special plushes, real-world reward tickets, arranging the toy chest,
   photos of the child's own stuffed animals.

## Constraints

- iPad + Apple Pencil only.
- Works fully offline. The app itself makes no network calls; iCloud Drive syncs the Kid Tutor
  folder in the background when the iPad is online. No other accounts or services.
- One child, one device.
- Short sessions (default 15 min); tokens earned in practice are spent in a claw-machine game.
- Parent dashboard.

## Requirements

1. **Text-to-speech**: the child never has to read instructions, in a natural-sounding voice.
2. **Handwriting recognition**: the child writes, and the app turns it into text.
3. **Home screen lists the subjects** (with a settings gear, top right, for grown-ups):
   - **Reading**: flashcards the child reads aloud; on-device speech-to-text approves the answer.
   - **Writing**: letters, then whole words, in handwriting boxes.
   - **Spelling**: the app says a word and shows it with letters missing, adding blanks until the child writes the whole word.
   - **Math**: flashcards, answered in handwriting.
   - **Logic puzzles**: multiple choice.
   - **A bit of everything**: a mixed session drawn from all of the above.
4. **Vocab**: the app says a word, and the child picks its meaning from pictures. Tapping a picture reads its definition.

## Key decisions

| Area | Choice | Why |
|---|---|---|
| Platform | iPadOS 26, SwiftUI, Apple Pencil required | One device type, so no work making layouts fit other screens |
| Scheduling | [swift-fsrs](https://github.com/open-spaced-repetition/swift-fsrs) (MIT) | The same algorithm modern Anki uses, without the Anki codebase or its sync |
| Storage | **iCloud Drive folder** (the app's iCloud container, shown as "Kid Tutor" in Finder and Files), with a local copy when iCloud is off | Parents edit lessons on the Mac, progress is backed up automatically, and logs can be read from the Mac |
| Lessons | **TOML files** in `Lessons/`, parsed with [TOMLDecoder](https://github.com/dduan/TOMLDecoder) (MIT, pure Swift, `Codable`) | Easy to write by hand in any text editor; comments allowed |
| Speech | `AVSpeechSynthesizer` with a **Premium voice** (free download) or **Personal Voice** (a parent's own voice), chosen in Settings; recorded audio for lesson words | All work offline once set up; see Voice below |
| Reading check | On-device speech-to-text (`SFSpeechRecognizer`, `requiresOnDeviceRecognition`), hinted with the expected word | Approves reading without the network; a grown-up can override |
| Handwriting | PencilKit, one character per box, a **bundled Core ML model trained partly on the child's own writing** | Fully offline, and accurate because it's trained for one child |
| Font | **Andika** (SIL, Open Font License, bundled), for every letter or number the child copies or reads | Made for early readers: "a" and "g" look the way kids write them |
| Content | Lesson files in iCloud, a few built-in starter lessons, and quick in-app additions (camera photos, voice recordings) saved back as lesson files | One format for everything a parent adds |
| Rewards | **Claw-machine game** in SpriteKit (built in, offline) that wins stuffed animals for a **toy chest** | A reward the child looks forward to, decided by aim rather than luck |
| Installing | Paid Apple Developer account ($99/yr) | A free-account install stops working after 7 days, and **iCloud containers require a paid account** |

### Handwriting approach

- ML Kit's handwriting recognizer needs a one-time model download. A Core ML model ships inside the app, so the app stays fully offline.
- One character per box, matched against the expected letters rather than open-ended recognition. This is the biggest accuracy gain.
- **Calibration step**: the child writes each letter and digit a few times.
- **Learning from corrections**: every corrected misread is saved as a labelled `InkSample`. Retrain on the Mac with Create ML whenever you want, then ship the updated model.
- Always offer a fallback: "I read *b*, is that right?", plus letter tiles to tap.
- A setting controls whether b/d and p/q reversals count as correct.

## Storage: the Kid Tutor iCloud folder

The app uses its own iCloud Drive container. On the Mac it appears in Finder under
**iCloud Drive › Kid Tutor**; on the iPad, in the Files app. The folder is the source of truth:

```
Kid Tutor/
├── README.md                 written by the app: how to write lessons, with examples
├── Lessons/                  ← parents edit these
│   ├── spelling-week-12.toml
│   ├── vocab-animals.toml
│   ├── math-add-within-10.toml
│   └── media/                photos (.jpg/.heic) and recordings (.m4a) that lessons refer to
├── Progress/                 ← the app writes these; read-only for parents
│   ├── cards.json            scheduling state for every card (FSRS, scaffold level)
│   ├── reviews-2026-11.jsonl one line per answer, appended; one file per month
│   ├── sessions.jsonl        one line per session: start, end, items, tokens earned
│   ├── rewards.json          token balance, plush collection, toy-chest layout, real-world rewards
│   └── handwriting/samples.json   InkSamples for recognizer training
├── Reports/                  ← the app writes a readable summary after each session
│   └── 2026-W46.md           this week's practice, accuracy, struggling items
├── Logs/                     app logs (one file per day), readable from the Mac
└── Problems.txt              lesson files that failed to load, with line numbers and what's wrong
```

**Lesson files.** Each file is one lesson: an `id`, a `title`, a `subject`, and a list of items.
Progress is keyed by lesson id plus the item's word or text, so fixing a sentence or a definition keeps
the child's progress, while changing the word itself starts a new item. Setting `active = false`
pauses a lesson without losing progress.

```toml
# Lessons/spelling-week-12.toml
id = "spelling-week-12"
title = "Week 12 spelling"
subject = "spelling"
active = true

[[word]]
word = "friend"
sentence = "My friend came over to play."

[[word]]
word = "because"
sentence = "I smiled because I was happy."
audio = "media/because.m4a"      # optional; otherwise text-to-speech
```

```toml
# Lessons/vocab-animals.toml
id = "vocab-animals"
title = "Animals"
subject = "vocab"

[[word]]
word = "ladder"
definition = "Something with steps you climb to reach high places."
picture = "media/ladder.jpg"
```

```toml
# Lessons/math-add-within-10.toml
id = "math-add-within-10"
title = "Adding within 10"
subject = "math"

[[facts]]
operation = "add"
a = [0, 10]          # range for the first number
b = [0, 10]
max_answer = 10
```

Reading cards use `[[card]] text = "the"`; puzzle lessons come later.

**Rules that keep this safe:**

- **The app never edits `Lessons/`** except to add new files from in-app additions (camera photo,
  recording). Parents never need to edit `Progress/`.
- **Bad lesson files don't break the app.** Each file is checked on load; errors (with line numbers)
  go to `Problems.txt`, the parent dashboard and the log, and the rest of the lessons still load.
- **Changes are picked up live.** The app watches `Lessons/` (`NSMetadataQuery`) and reloads a lesson
  when its file changes, downloading files iCloud hasn't fetched yet.
- **Safe writes.** Progress files are written with `NSFileCoordinator`, atomically; review history is
  append-only, so a sync conflict can lose at most the last few answers, never earlier history.
- **No iCloud?** If the iPad is signed out of iCloud, the app uses the same folder layout inside its
  local Documents folder and moves it into iCloud when iCloud becomes available.
- **Privacy note:** this is the one change from "nothing leaves the iPad": lesson files, progress
  and logs sync to your own iCloud account. Nothing goes anywhere else.

## Data model

```
Lesson          id, title, subject, active, items[]                 ← loaded from Lessons/*.toml
Item            lessonId, key (the word or text), fields{}, media[]  ← from the lesson file, not stored separately
Card            itemKey, skillKey, fsrsState{stability, difficulty, due, reps, lapses}, scaffoldLevel, suspended
ReviewLog       cardId, at, rating, durationMs, errors, hintsUsed, inkSampleIds[]
InkSample       strokes, expectedChar, recognizedChar, confirmedLabel   ← used to train the handwriting model
Session         start, end, cardIds[], tokensEarned, endedReason
Milestone       definition, progress, unlockedAt, reward (plush or real-world)
Rewards         tokens, plushes[] (id, wonAt), chestLayout[], clawAssist, realWorld[] (title, unlockedAt, givenAt)
Settings        sessionMinutes, newPerSession, subjectWeights, reversalsOK, tokensPerSession, parentPIN
```

Math facts and puzzles are **generated in code**, so there's no stored note per problem.
Their `Card` is the skill itself, such as `add:+2` or `pattern:level3`.

## Automatic grading

The child never rates themselves. The app picks the FSRS rating from how they did:

| Rating | Rule |
|---|---|
| Again | Wrong after the hint, or skipped |
| Hard | Right, but needed a hint, made more than one mistake, or took over 2× their usual time |
| Good | Right on the first try at a normal pace |
| Easy | Right on the first try, and faster than half their usual time |

If the app misread their handwriting ("that's not what I wrote"), the attempt isn't counted against them.

## Home screen

Six large picture tiles: Reading, Writing, Spelling, Math, Puzzles, and A bit of everything, with the
question spoken aloud ("What do you want to practice? …"). A tile starts a session in that subject; "A bit
of everything" starts a mixed session. The settings gear in the top right opens the grown-ups area only
on a press and hold; a tap says "Ask a grown-up." (Built: the tiles and gear; Reading, Writing, Spelling and Math are built;
the other subjects say "coming soon". While letters or numbers have too few handwriting samples, an orange
note at the bottom says so and opens handwriting setup.)

## Voice

The built-in Standard voices sound mechanical. In order of effort:

1. **Premium voices** (built: picker with previews and speed in Settings). Free downloads in
   Settings › Accessibility › Spoken Content › Voices › English (for example Ava, Zoe or Evan Premium).
   Much more natural, offline once downloaded.
2. **Personal Voice** (built: permission button). A parent records their own voice once in
   Settings › Accessibility › Personal Voice; the app can then speak everything in it.
3. **Recorded audio** for words that matter: lesson files can point at `.m4a` recordings.
4. **Possible later:** generate audio for all fixed prompts and lesson words on the Mac with an
   open-source neural voice (such as Kokoro or Piper) and save it into `Lessons/media/`, so even
   generated speech sounds human. Still offline on the iPad.

## Session design (default 15 minutes, adjustable)

1. **Warm-up**: 2–3 easy review cards so the session starts with success.
2. **Main part**: due reviews from all subjects mixed together, plus **at most 3–5 new items**. Every subject gets some time even when a lot is due.
3. **Timed stop**: when time is up, the current item finishes and the session always ends on an item likely to be right.
4. **Celebration screen**: tokens earned, progress toward the next milestone, then
   "Play the claw machine!" (spending tokens is optional; they keep).

Everything is spoken aloud. Each screen has one large replay button and a large "I need help" button
(a hint: reveal a letter, or read the answer choices again).

## Exercise screens

- **Spelling**: "Spell *friend*… *my friend came over*." The child writes the missing letters in the blank boxes.
  The number of blanks moves through scaffold levels: 1 blank → 2 → only the first letter shown → whole word.
  Right moves the word up a level, wrong moves it down. Vowels and common letter groups (sh, ch, -ight) are
  blanked first, then letters the child has missed before.
- **Spelling (built, first version)**: 5 words per session from 23 built-in starter words (lesson files
  replace these in the storage phase). Each blank is its own handwriting box, judged by the personal
  recognizer as soon as the pencil pauses. A wrong letter turns red and is cleared with "Almost! Try that
  letter again"; a second miss, or Help, shows the letter faded to trace. First try moves the word up a level,
  a retry keeps it, a hint moves it down; two first tries at the whole-word level master it. Letters the
  recognizer has fewer than 2 examples of are accepted and saved as new examples, so practice also trains it.
  Progress is saved in `Progress/spelling.json`; a simple planner picks words until FSRS arrives.
  **Changed 2026-11-16:** level *n* blanks *n* random letters; two first tries in a row move up; the top level is the
  whole word written in one wide box, split into letters for checking (with Vision text reading as a fallback).
- **Reading (built, first version)**: 8 cards per session from 30 sight words, then short sentences, then 100 more Dolch sight words
  (built-in until lesson files). Speech recognition is required to run on-device; if the iPad can't, the grown-up
  buttons are the way to answer. Permission is asked on the first mic tap (or from Settings › Reading), never on
  opening the screen. Matching accepts sound-alikes and one-letter slips in longer words; a miss gets
  "Let's try once more", a second miss reads the word for the child to repeat, a third moves on. Progress in
  `Progress/reading.json`.
- **Reading (design)**: shows a word or sentence; the child taps the microphone and reads it aloud. On-device
  speech-to-text, given the expected word as a hint, approves it when it hears a match. Children's speech
  is hard to recognize, so a near miss is treated kindly ("Let's try once more"), the child can tap any word
  to hear it, and a grown-up can approve it by hand. Results are logged so we can see how reliable it is.
- **Writing (built, first version)**: 6 items per session. Characters come in by shape family (lowercase, then
  numbers, then capitals) and are written three times beside an example; levels are trace, copy, then from memory.
  Words from the spelling list join once 8 lowercase letters are written from memory: trace, copy, then "look,
  cover, write" in one wide box. One clean pass moves up a level; two at the top master the item. Progress in
  `Progress/writing.json`.
- **Vocab**: the app says the word, then shows 4 pictures. Tapping a picture reads its definition, and
  "This one!" confirms. Wrong choices come from words the child already knows. Pictures can be your own
  photos of real things around the house, with bundled ARASAAC pictograms (free for non-commercial use) for the rest.
- **Math (built, first version)**: 8 facts per session, written in digit boxes (one per digit of the answer).
  Skills in order: add within 5, add within 10, take away within 10, add within 20, take away within 20; the
  next unlocks when 80% of the current one is mastered, and a couple of mastered facts from earlier skills come
  back for review. Help shows counting dots first (two colored groups, or crossed-out dots for taking away),
  then the answer to trace. Each fact moves up a box on a first-try answer and is mastered at box 3.
  Progress in `Progress/math.json`.
- **Logic puzzles**: multiple choice, with every choice read aloud on tap. Each type has difficulty levels,
  and the app raises the level after repeated success.
  **Built:** picture tiles (shape, color, size, how many) in four kinds: what comes next?, odd one out,
  finish the grid (joins once "what comes next?" reaches level 3) and who am I? (spoken clues shown as
  picture chips; nothing fades or moves on by itself, the puzzle waits for the child). 6 puzzles a session from up to 3 kinds. A wrong pick fades with a spoken pointer; each Help
  says a hint and takes away a wrong choice. Up a level after 3 first tries in a row, down after 2 puzzles in
  a row that needed a retry or Help. Every puzzle is made from kind + level + seed, and tests check each one
  has exactly one answer. Progress in `Progress/puzzles.json`.
  **Later:** odd one out with groups of things (animals, food), shape sudoku, balance scales, ordering,
  Pencil mazes, number bonds.

## Rewards: the claw machine and the toy chest

**Earning tokens.** Tokens come from effort, not only correct answers: a finished session earns a set
amount (default 3, so roughly 3 tries a day), plus bonus tokens for milestones. Milestones are based on
lasting mastery, not volume: "25 spelling words mastered" (whole-word level and predicted to stick for at
least 21 days), "all the +2 facts", "5 sessions this week".

**The claw machine.** One token buys one try. The child sees a glass case full of stuffed animals,
moves the claw left and right (drag the claw itself, or big arrow buttons), and taps **Drop**. The claw lowers,
closes, and lifts; if it caught a plush, it carries it over a glass wall and drops it into an open
treasure chest.

**The toy chest.** Won animals go into a toy chest (a shelf-and-chest scene) that the child can
decorate: drag plushes around, sit them on shelves, line them up. The chest is the child's to keep;
nothing is ever taken away.

**Making it fair: aim, not luck.** Real claw machines are games of chance tuned to make players
lose, which is close to gambling. This one must not work that way:

- **Success depends on aim.** If the claw is centered over a plush when it drops, it catches it. Being
  off-center means it slips; there is no hidden random "grip strength".
- **Misses help next time.** After a miss the plush shifts closer to the chest or the claw opens a little
  wider ("claw assist"), so every few tokens guarantees a win.
- **Everything is visible.** The child sees exactly which plushes are in the machine. No mystery
  prizes, and no duplicates until the current set is complete.
- **Tokens can't be bought**, are never lost, and don't expire.
- **Milestones add special plushes** to the machine (a golden one for a big milestone), so mastery,
  not luck, unlocks the rare ones.
- **Real-world rewards** are plushes too: a "park trip" ticket plush that, when won, says "Ask your
  grown-up for your reward!"; the parent marks it given in the dashboard.

**Art.** Plush animals as simple original illustrations, or **photos of the child's own stuffed
animals** (cut out on the iPad with Lift Subject from Background) added as lesson-folder media. SpriteKit
(built in) handles the claw, the swinging, and the plushes tumbling with simple physics.

**Built (first version, 2026-11-16).** Home's yellow Rewards button opens the machine. A finished session
earns `tokensPerSession` (default 3, in Settings › Rewards, where a grown-up can also give or take back a
token). The machine holds a messy pile of 20 squishy toy balls, built like a physics drop (each falls, rolls off what it lands on, and rests on two things); the pile is saved and settles when a toy is won. A caught toy is carried over a glass wall into an open treasure chest. The claw lands on the
highest toy under it; grabbed within half a toy's radius of its middle the toy holds, grabbed further off it
rides up and squeezes out (sooner the further off). Each miss or slip widens the secure grip, so from the third
try in a row any drop onto the pile wins. Nothing is highlighted (changed 2026-11-16 at the owner's request, to
make aiming a little harder). The win is saved before the animation. Prizes are 31 animals (emoji, plus a drawn capybara) on colored
cushions, offered in order with no duplicates until all are won. The toy chest is shelves of won toys. Not yet: milestones, special plushes, real-world rewards,
arranging the chest, photo plushes.

**Limits.** The game is a short reward, not a second app: play happens only after a session, uses
only earned tokens, and the parent can set tokens per session.

**What to avoid** (unchanged): punishing a broken streak (allow 1–2 missed days a week), surprise
rewards bought with tokens, and anything the child can lose once earned.

## Parent dashboard (behind a parent PIN, separate from the iPad passcode)

- **Overview**: sessions and minutes this week, accuracy by subject, forecast of reviews coming due.
- **Struggling items**: words with many misses or stuck at the same scaffold level. Edit, add a recording, suspend or reset.
- **Handwriting**: how often recognition is right, and misread samples to relabel (feeds retraining).
- **Lessons**: which lessons loaded, which are paused, and any **problems in lesson files** (with the line).
  Quick additions on the iPad (a word list, a photo with a recorded definition) are saved as new lesson files.
- **Rewards**: token balance, plush collection, tokens per session, claw assist, real-world rewards to give.
- **Settings**: session length, new items per session, subject balance, b/d reversals.
- **Backup**: everything is already in iCloud Drive; the dashboard shows when it last synced.

## Build phases

0. **Handwriting test first (1 weekend)**: a page with single-character boxes and a recognizer, tested with the
   child's real writing. It's the biggest risk, so prove it before building the rest.
1. **Storage and lessons**: the iCloud folder (with local fallback), TOML lesson loading and checking,
   `Problems.txt`, progress files, logs moved into the folder.
2. **Core**: FSRS, session engine, text-to-speech, spelling, math facts, weekly reports.
3. **Rewards**: tokens, claw machine, toy chest, milestones; dashboard v1.
4. **Reading, vocab, in-app additions** (camera photos, recordings).
5. **Puzzles.**
6. **Polish**: handwriting retraining loop, more dashboard insights.

## Open questions

- [ ] Child's age or grade.
- [ ] Does the school teach lowercase first, and which letter style (D'Nealian, Zaner-Bloser, …)? Decides the font and handwriting training data.
- [ ] Parent's comfort level with Swift and Xcode.
- [ ] Starter content: which word lists (e.g. Dolch/Fry sight words, school spelling lists)?
- [ ] Plush art: drawn illustrations, photos of the child's own stuffed animals, or both?
- [ ] Toy chest look: a chest, shelves, a bedroom? (worth a wireframe)
- [ ] Tokens per session, and how many misses before claw assist guarantees a catch.
- [ ] Should Reading show "I heard …" to the child?
- [ ] Should subjects with nothing due hide from the home screen (once FSRS gives due dates)?
