# Design workspace

Plain HTML and CSS, no build step. Open `index.html` in Safari (`make wireframes`) and click through.

## What's here

| Path | What |
|---|---|
| `index.html` | Gallery and flow map: every screen, how they connect, and their status. Start here. |
| `PRINCIPLES.md` | Short checklist of UX rules for a young child. Use it to review any screen. |
| `tokens.css` | Design tokens: the colors, type sizes, spacing and corner radii the app will use. `Theme.swift` mirrors these. |
| `wireframe.css` | The wireframe kit: iPad frame, buttons, writing boxes, picture cards, notes. |
| `wireframes/*.html` | One file per screen, drawn at 13-inch iPad size (1376 × 1032 pt, landscape). Each has notes on the right: what's spoken, how it behaves, open questions. |
| `screenshots/` | Simulator screenshots (`make screenshot`) for comparing the real app with its wireframe. |

## How we work on a screen

1. **Describe it.** Tell Claude what the screen is for, in your own words ("the spelling exercise
   where letters are missing"). No design vocabulary needed.
2. **Sketch.** Claude adds or updates `wireframes/<screen>.html` and links it from `index.html`.
   Wireframes are deliberately plain (gray boxes, one accent color) so the discussion stays on
   layout and flow, not colors.
3. **Review in Safari.** Click through the flow. Check it against `PRINCIPLES.md`. Ideally, watch
   your child use the clickable version on the iPad. Point at what's confusing; that is the most
   useful feedback there is.
4. **Iterate** until it feels right, then mark it *Ready* in `index.html`.
5. **Build** it in SwiftUI with the same tokens, run it in the simulator, and save a screenshot to
   `screenshots/` to compare against the wireframe.

## Viewing on the iPad

The wireframes are plain files, so you can AirDrop the `design` folder to the iPad and open
`index.html` from the Files app, or run `python3 -m http.server -d design` on the Mac and visit
the Mac's address from the iPad on your home Wi-Fi. Checking touch-target sizes on the real
device is worth it.
