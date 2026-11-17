# Kid Tutor

An offline iPad + Apple Pencil tutor built for one elementary-school child. Everything is spoken aloud,
answers are handwritten or read out loud, sessions are short, and finished sessions earn tokens for a
claw-machine game that wins stuffed animals for a toy chest.

Everything stays on the iPad: no accounts, no network calls, no analytics. Handwriting and speech are
recognized on the device.

## What it does

| Subject | How it works |
|---|---|
| **Reading** | Sight words, then short sentences. The child taps the mic and reads; on-device speech recognition checks it, generously. Tapping a word reads it aloud. |
| **Writing** | Letters by shape family, then numbers, capitals and words. Each moves from tracing to copying to writing from memory. |
| **Spelling** | The app says a word and a sentence; the child fills in missing letters, with more blanks each level until the whole word is written from memory. |
| **Math** | Addition and subtraction facts within 20, answered in handwriting, with counting dots as help. |
| **Puzzles** | What comes next, odd one out, finish the grid, and "who am I?" clues. Every puzzle is generated, and a solver checks it has exactly one answer. |
| **Rewards** | A fair claw machine (aim decides, and misses make the next try easier) and a toy chest of won animals. |

Each subject tracks every card or item and brings back what the child finds hard. A grown-up area (press
and hold the gear) has settings, handwriting calibration and testing, and a **Progress** page per subject
showing how many cards are learned, in progress and still to do.

Handwriting is read mainly by a personal recognizer (`$P` point clouds) trained on the child's own
samples, collected in a short calibration and while practicing. Apple Vision and an optional Create ML
model can be compared against it in the grown-up Test and Results tabs.

## Getting started

Requirements: a Mac with Xcode 27 (first launch completed: `sudo xcodebuild -runFirstLaunch`) and
[Nix](https://nixos.org) for the dev shell with XcodeGen (or `brew install xcodegen` and drop the
`nix develop -c` prefix).

1. `cp Local.mk.example Local.mk` and set `BUNDLE_ID` (like `com.yourname.kidtutor`) and, to run on an
   iPad, `DEVELOPMENT_TEAM` (your Apple Developer team ID). `Local.mk` isn't committed.
2. **Simulator:** `nix develop -c make sim` creates a 13-inch iPad Pro simulator ("Kid Tutor iPad"),
   builds, installs and launches. Mouse drawing works there; speech recognition doesn't (Reading shows a
   text box instead).
3. **iPad:** `nix develop -c make open`, connect the iPad (turn on Developer Mode when asked), pick it
   as the run destination and press Run. A free Apple ID works, but the app expires after 7 days.
   For Reading, turn on Dictation in the iPad's settings so the on-device speech model downloads.

Keep the same `BUNDLE_ID` once the app is on an iPad: the app's data belongs to it, and a new id
installs a separate, empty app.

## Commands

```sh
make test                      # KidTutorKit tests (Swift Testing)
nix develop -c make project    # regenerate KidTutor.xcodeproj from project.yml
nix develop -c make sim        # build, install and launch in the simulator
make screenshot                # save the simulator screen to design/screenshots/
make wireframes                # open the design wireframes in Safari
make logs                      # the app's log from the simulator (make device-logs for the iPad)
```

## Data

The app keeps plain files in its Documents folder, visible in the Files app under
**On My iPad › Kid Tutor**: `samples.json` (handwriting samples), `Progress/*.json` (one file per
subject, plus rewards), `Logs/` (a daily log) and `Backups/` (copies made before a reset).

These are the child's data, so `.gitignore` keeps samples, progress, logs, recordings, training folders
and trained models out of the repository even if they're copied into it.

### Training a Core ML model (optional)

1. On the iPad: Settings › **Export samples**, or copy `samples.json` from the Files app.
2. `make export SAMPLES=$HOME/Downloads/samples.json OUT=$HOME/Desktop/kid-tutor-training` writes one
   folder of PNGs per character (`lower_a`, `upper_A`, `digit_3`, …).
3. In **Create ML** (Xcode › Open Developer Tool), make an Image Classifier from that folder and train.
4. Save it as `HandwritingClassifier.mlmodel` anywhere under `App/KidTutor/`, run `make project`, and
   rebuild. It stays on your Mac: git ignores `.mlmodel` files.

## Docs

- [docs/PLAN.md](docs/PLAN.md): the product plan, what's built, known limitations and next steps
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): code layout, data files and gotchas
- [design/](design/README.md): wireframes, design tokens and kid UX principles (`make wireframes`)
- [CLAUDE.md](CLAUDE.md): working rules for Claude Code in this repo

## License

The code is under the [MIT License](LICENSE). The bundled Andika font (in `App/KidTutor/Fonts`) is
© SIL International under the [SIL Open Font License](App/KidTutor/Fonts/OFL.txt).
