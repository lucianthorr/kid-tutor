# Kid Tutor

Offline iPad + Apple Pencil tutor for one elementary-school child. Starting a new session? Read
[docs/PLAN.md](docs/PLAN.md) › Status (what's built, known limitations, next steps), then
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the code map and gotchas; each PLAN.md section ends
with what was built for that area. The owner is a developer but not a designer: explain design choices
in plain language and show them as wireframes before building UI.

## Commands

```sh
make test                      # KidTutorKit tests (Swift Testing)
nix develop -c make project    # regenerate KidTutor.xcodeproj from project.yml (after adding/removing files; signing team from Local.mk)
nix develop -c make sim        # build, install and launch in the "Kid Tutor iPad" simulator
make screenshot                # save the simulator screen to design/screenshots/
make wireframes                # open design/index.html in Safari
make logs                      # the app's own log from the simulator (LINES=500 for more)
make device-logs               # the app's own log from the connected iPad
make syslog                    # system-log errors/faults for the app (LAST=2h)
make selfcheck                 # relaunch and score every recognizer on the saved samples
```

## Logs

The app logs through `Log` (App/KidTutor/Log.swift) to both the unified log (subsystem
`BUNDLE_ID` from `Local.mk`) and a daily file in `Documents/Logs/`. When the owner reports a problem,
read `make logs` first (`make device-logs` if it happened on the iPad): it shows what the child was asked, the ink summary, every recognizer's
guesses and timings, and what was saved. Add a `Log` call for any new user action or failure path.
Known noise: NaN warnings from `_UIPointerEffectPlatterView` are the Simulator's mouse-pointer
hover effect, not app code.

Launch arguments for testing (`xcrun simctl launch --terminate-running-process "Kid Tutor iPad" $(make -s bundle-id) …`):
`-openSubject <reading|writing|spelling|math|logic>` opens a subject (`logic` is Puzzles; add `-puzzle grid:3`
for a session of one kind at one level: `next`, `oddOneOut`, `grid`, `whoAmI`); `-openGrownUps` opens the grown-up area as the gear does (Calibrate if handwriting needs samples, else Settings), `-openSettings` always on Settings, and `-openProgress <reading|writing|spelling|math|logic>` that subject's Progress page; `-openRewards` opens the claw machine
(add `-openToyChest` for the chest, or `-clawDrop 0.55` to move the claw there and drop); `-recognizerSelfCheck` scores the
handwriting recognizers; `-speechProbe <file.wav in Documents>` checks and runs the iOS 26 speech model.

**Speech recognition does not work in the Simulator** (checked 2026-11-15, Xcode 27.2): SFSpeechRecognizer
fails with "Failed to initialize recognizer", SpeechTranscriber is "unsupported", DictationTranscriber reports
installed but has no audio formats. Test Reading's listening on a real iPad; in the Simulator, Reading shows a
text box for typing what was "heard".

Device build check without signing:
`xcodebuild -project KidTutor.xcodeproj -scheme KidTutor -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## Working in the Simulator

- You can't tap or draw in the Simulator. To see a screen, launch it with the arguments above and take a
  screenshot; to try interactions, add a temporary launch-argument hook and remove it before committing.
  The owner does the drawing and speaking on the iPad, and you read the logs afterwards.
- After launching with test arguments (`-puzzle`, `-open…`), relaunch without them, or the owner's next
  session starts in the test setup.
- The Simulator holds the owner's real data (handwriting samples, progress). Don't delete or reset it
  without asking.
- Workflow the owner likes: wireframe first (new screens) → logic in KidTutorKit with tests → thin
  SwiftUI → build → screenshot → commit with a message that explains why.

## Rules

- **Works offline.** Never add network calls, analytics, third-party SDKs that phone home, or
  anything that requires an account. On-device Apple frameworks are fine, and so is reading and writing
  the app's iCloud Drive folder through file APIs (the system syncs it). Pure-Swift packages that only
  parse data (like TOMLDecoder) are fine.
- **Logic goes in `Packages/KidTutorKit` with tests**; the app target stays a thin SwiftUI layer.
  Run `make test` after package changes.
- **Verify UI changes in the simulator**: `make sim`, then `make screenshot` and look at the result.
  A build that compiles isn't the same as a screen that works.
- **Design first for new screens**: add or update a wireframe in `design/wireframes/`, link it from
  `design/index.html`, and check it against `design/PRINCIPLES.md` before writing SwiftUI.
- **Keep design tokens in sync**: colors, type sizes and spacing live in `design/tokens.css`. When the
  app gets a `Theme.swift`, it mirrors those values; change both together.
- **Child-facing screens**: every instruction is spoken, touch targets are at least 60 pt, one main
  action per screen, no reading required to get around. Grown-up screens can be normal iPad UI.
- `KidTutor.xcodeproj` is generated; edit `project.yml`, never the project file.
- The package uses Swift 6 language mode; the app uses Swift 5 mode.
- Don't call `AVSpeechSynthesisVoice.speechVoices()` on the main thread (hangs at launch).
- Lesson files in `Lessons/` belong to the parent: the app may add new files but never rewrites
  theirs. Bad lesson files must produce a readable problem, never a crash.
- The claw game decides catches by aim plus claw assist, never hidden randomness (PLAN.md › Rewards).

## Git

Work on a branch for anything bigger than a small fix; commit messages explain why, not just what.
