# Contributing

Thanks for helping make Pawse better! 🐾

## Setup

Requirements: macOS 13+, Xcode 15+ (or the Swift 5.9+ toolchain).

```bash
git clone https://github.com/salahu01/pawse-app.git
cd pawse-app
PAWSE_ARCHS=arm64 ./tools/bundle.sh   # fast local build -> build/Pawse.app
open build/Pawse.app
```

`swift build` alone compiles, but the app needs the bundle (`Info.plist`, icon, sounds) to run properly,
so use `tools/bundle.sh`.

## Project layout

```
Sources/Pawse/      the app (SwiftUI + AppKit + SceneKit), one file per area
  main.swift        menu bar, scheduler, windows
  PetView.swift     3D pets, built from primitives and animated procedurally
  PetOverlay.swift  the pet walking on screen and asking
  BlockScreen.swift hard-block screen      BreakScreen.swift  break countdown
  Habits.swift      habits model           ScreenTime.swift   active-use tracking
  Store.swift       water + settings       SoundFX.swift      voices and synth sounds
  MainView.swift    the main window        TrackerView.swift  water tracker
Resources/          Info.plist, entitlements, icon, bundled sounds
tools/              bundle.sh, make-dmg.sh, make_icon.py, relax_tpose.py
```

## Handy dev flags

```bash
APP=build/Pawse.app/Contents/MacOS/Pawse
$APP --render-pet kid happy out.png   # render a pet offscreen (moods: asking happy sad walking)
$APP --tab habits                     # open the main window on a tab
$APP --break                          # start a break immediately
$APP --block                          # show the hard-block screen for the first habit
```

## Guidelines

- One concern per pull request; describe what you changed and how you tested it.
- Keep it dependency-free. Pawse uses only Apple frameworks, on purpose.
- Keep it private: no network calls, analytics or tracking.
- New sounds or 3D assets must have a licence that allows redistribution; add them to `CREDITS.md`.
- Match the surrounding code style. Run the app and try the flow you changed before opening a PR.

## Ideas welcome

New pets, new habit presets, translations, accessibility improvements. Open an issue to discuss first.
