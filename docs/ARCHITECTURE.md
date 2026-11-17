# Architecture

Kid Tutor is an offline iPad app for one child. This document explains how the code is laid out
and why. For the product plan and phases, see [PLAN.md](PLAN.md).

## Principles

1. **Works offline.** The app makes no network calls: no accounts, no APIs, no analytics. Progress,
   samples and logs are plain files in the app's Documents folder, readable on the Mac; the plan moves
   them, with parent-written lessons, to the app's iCloud Drive folder, which the system syncs.
2. **Logic in the package, UI in the app.** Anything that can be tested without UIKit lives in
   `KidTutorKit` and has tests. The app target is a thin SwiftUI layer over it.
3. **The child never rates themselves.** The app decides how well an answer went from what
   happened (mistakes, hints, time), and spaced repetition (FSRS) schedules from that.
4. **Everything is spoken.** Every instruction a child needs has a spoken version.
5. **Design before code.** Screens are sketched as wireframes in [`design/`](../design) first,
   reviewed in Safari, then built in SwiftUI using the same design tokens.

## Layout

```
kid-tutor/
├── App/KidTutor/              iPad app (SwiftUI, PencilKit, SpriteKit, Vision, Speech, AVFoundation)
│   ├── Fonts/                 Andika (SIL OFL)
│   └── Recognizers/           recognizers that need Apple frameworks (Vision, optional Core ML)
├── Packages/KidTutorKit/      Swift package, no UIKit: models and logic, with tests
│   ├── Sources/KidTutorKit/
│   ├── Sources/kidtutor-export/  Mac tool: samples.json → training images
│   └── Tests/                 Swift Testing suites
├── design/                    wireframes, design tokens, kid UX principles, screenshots
├── docs/                      PLAN.md, ARCHITECTURE.md
├── project.yml                XcodeGen spec (KidTutor.xcodeproj is generated, not committed)
├── Local.mk.example           copy to Local.mk (not committed): bundle id and signing team
├── flake.nix                  dev shell with XcodeGen
└── Makefile                   test, project, sim, logs, screenshot, export, wireframes
```

## KidTutorKit

| File | Role |
|---|---|
| `Ink.swift` | `Ink` → `InkStroke` → `InkPoint`: pen strokes in canvas coordinates. The common currency between PencilKit, recognizers, storage and rendering. |
| `InkSample.swift` | One written character plus what it was supposed to be, what a grown-up confirmed it was, and each recognizer's guess. `SampleStore` saves them as JSON. |
| `Characters.swift` | `Alphabet` (which character sets are on) and `CharacterLabel` helpers: spoken names, folder-safe names, mapping recognizer output back to characters. |
| `Recognition.swift` | The `CharacterRecognizer` protocol every recognizer implements. |
| `PointCloudRecognizer.swift` | The $P recognizer: compares ink against the child's own confirmed samples. |
| `InkRenderer.swift` | Draws ink as a square black-on-white image for Vision, Core ML, training export and thumbnails. |
| `Calibration.swift` | `CalibrationPlan`: which characters still need samples, asked in rounds. |
| `AccuracyReport.swift`, `Evaluation.swift` | Per-recognizer accuracy, hardest characters and mix-ups; leave-one-out scoring for the self-check. |
| `AnswerBox.swift` | A handwritten answer box's state, and the `JSONFile` protocol every progress file uses. |
| `WordCheck.swift` | Splits a whole handwritten word into letters (`WordInk`) and checks it. |
| `Subject.swift` | The home screen's subjects and what's said about them. |
| `Spelling.swift` | Starter words, blanks per level (`SpellingScaffold`), `WordProgress` (levels, mastery), `LearningPlanner`, `LetterCheck`. |
| `Writing.swift` | Teaching order of characters, trace → copy → memory levels, `WritingPlanner`. |
| `Math.swift` | Facts and skills, Leitner-style `BoxProgress`, `MathPlanner` (next skill at 80% mastered). |
| `Reading.swift` | Starter cards, lenient `ReadingCheck` matching (sound-alikes, small slips), `ReadingPlanner`, and the mic's `SpeechErrorMeaning` / `ListeningRetries` rules. |
| `Puzzles.swift` | Tiles, `Puzzle` and everything it says, `PuzzleMaker` (kind + level + seed), `PuzzleSkill` levels, `PuzzlePlanner`. |
| `PuzzleSolver.swift` | Solves a puzzle from only what the child sees; the maker keeps a puzzle only if the one solution is the answer. |
| `Decks.swift` | `DeckReport`: each subject's cards as learned / in progress / to do, for the grown-up Progress pages. |
| `Rewards.swift` | Plush catalog, claw rules (aim plus claw assist, never chance), the toy pile, `RewardsState` (tokens, wins). |
| `VoiceCatalog.swift` | Which installed voices sound human enough to offer. |
| `LogFile.swift` | The daily log file, written off the main thread. |

The package uses Swift 6 language mode (strict concurrency). The app target uses Swift 5 mode,
so SwiftUI/UIKit code isn't fighting concurrency checks while the UI is still changing quickly.

## App

| File | Role |
|---|---|
| `KidTutorApp.swift`, `AppModel.swift` | Entry point; `AppModel` is the single `@Observable` state: settings, samples, recognizers, every progress file, resets. |
| `HomeView.swift` | Subject tiles, the grown-up gear, the calibration note, `SubjectScreen`, and `GrownUpView` (Settings, Test, Results, Calibrate). |
| `ExerciseParts.swift` | Shared exercise pieces: top bar (replay, progress, Help), answer boxes, check button, finished screen. |
| `ReadingView.swift`, `SpeechListener.swift`, `SpeechProbe.swift` | Reading; on-device listening that waits for the child; a probe for the iOS 26 speech model. |
| `WritingView.swift`, `SpellingView.swift`, `MathView.swift`, `PuzzleView.swift` | One screen per subject. |
| `WritingPad.swift`, `KidFont.swift` | PencilKit writing box with ruled guides, guide letters, thumbnails; the Andika font. |
| `RewardsView.swift`, `ClawScene.swift` | Claw machine (SpriteKit), toy chest, toy faces (including the drawn capybara). |
| `CalibrationView.swift`, `TestView.swift`, `ResultsView.swift` | Handwriting calibration, recognizer testing and results. |
| `SettingsView.swift`, `ProgressViews.swift`, `VoiceSettingsSection.swift` | Grown-up settings, the Progress section and subject pages, voice and Reading permissions. |
| `Speaker.swift`, `Log.swift` | Text-to-speech (with per-part callbacks); logging to the unified log and a daily file. |

## Handwriting pipeline

```
Apple Pencil
  → PKCanvasView (CharacterCanvas)        strokes as PKDrawing
  → Ink(drawing:size:)                     strokes as InkPoints
  → WritingPad pause timer                 "finished" after the pencil rests
  → AppModel.recognizeAll(ink)             every recognizer, limited to the active Alphabet
       ├─ PointCloudRecognizer             child's own samples ($P)
       ├─ VisionRecognizer                 InkRenderer → VNRecognizeTextRequest
       └─ CoreMLRecognizer (optional)      InkRenderer → bundled HandwritingClassifier
  → grown-up confirms the real label
  → InkSample saved (guesses recorded first) → $P templates rebuilt
```

Recording guesses before a sample becomes a template keeps the accuracy numbers honest.

Training loop for the Core ML model: export `samples.json` → `make export` writes one PNG folder per
character → Create ML image classifier → `HandwritingClassifier.mlmodel` under `App/KidTutor/`.
`InkRenderer.trainingImageSize` and `trainingPadding` must match on both sides.

## State and persistence

- `AppModel` is the single `@Observable` source of truth, injected with `.environment`.
- Files in the app's Documents folder (visible in the Files app): `samples.json` (handwriting samples),
  `Progress/{reading,writing,spelling,math,puzzles,rewards}.json`, `Logs/kidtutor-YYYY-MM-DD.log`, and
  `Backups/` copies taken before a grown-up resets progress or calibration. Settings are in `UserDefaults`.
- Each progress file is a `JSONFile`; decoding tolerates older files (missing keys get defaults).
- Planned (see PLAN.md › Storage): one **Kid Tutor folder** in the app's iCloud Drive container with a
  local fallback, holding `Lessons/*.toml` (written by parents), `Progress/`, `Reports/`, `Logs/` and
  `Problems.txt`. File access would go through one `KidTutorFolder` type: it resolves the iCloud or local
  root, watches `Lessons/` with `NSMetadataQuery`, and writes with `NSFileCoordinator` and atomic replaces.

## Planned structure for later phases

These don't exist yet; they're here so new code has an obvious home. (Today each subject has a simple
planner standing in for FSRS.)

| Concept | Where | Notes |
|---|---|---|
| `Lesson`, `Item` | KidTutorKit | Decoded from TOML (TOMLDecoder); validation returns readable problems with line numbers. |
| `Card`, `ReviewLog` | KidTutorKit | Pure models, saved as JSON / JSON Lines in `Progress/`. |
| `KidTutorFolder` | App | iCloud container or local fallback, file watching, coordinated writes. Path logic and file formats tested in the package. |
| Scheduler | KidTutorKit | Wraps swift-fsrs; maps graded outcomes to FSRS ratings. |
| Grader | KidTutorKit | Outcome (errors, hints, time vs. usual) → Again/Hard/Good/Easy. |
| Session engine | KidTutorKit | Warm-up, interleaved main part, new-item cap, timed stop, end on success. |
| Milestones | KidTutorKit (`Rewards.swift`) | Bonus tokens and special plushes for lasting mastery. |
| Parent dashboard | App | Behind a parent PIN; reads the same models as the Progress pages. |

## Gotchas

- **Speech voices:** `AVSpeechSynthesisVoice.speechVoices()` blocks forever on the main thread at
  launch. `Speaker` loads voices in a background task.
- **Simulator input:** the Simulator has no Apple Pencil; mouse clicks arrive as finger touches, so
  finger drawing is on by default in Simulator builds.
- **Xcode 27:** the Simulator app is now DeviceHub (`Xcode.app/Contents/Applications/DeviceHub.app`).
  When Xcode offers "recommended settings", make them in `project.yml` (and bump `xcodeVersion`): edits
  made in Xcode are lost when the project is regenerated.
- **Speech recognition doesn't work in the Simulator** with any Apple API, so Reading shows a text box
  there for typing what was "heard". Test listening on an iPad with Dictation turned on.
- **Bundle id:** it comes from `Local.mk` (default `com.example.kidtutor`). The app's data on a device
  belongs to it; changing it installs a separate, empty app.
- **Log noise:** NaN warnings from `_UIPointerEffectPlatterView` are the Simulator's mouse-pointer hover
  effect, not app code.
- **Case-insensitive folders:** training-image folders are named `lower_a`, `upper_A`, `digit_3`
  because macOS volumes usually treat `a` and `A` as the same folder.
