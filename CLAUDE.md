# Desktop pet for macOS

A pixel-art pet that wanders above the Dock and runs small self-care "moments" (photo drop, meals, fetch, screenshot tidy, status bubbles). It ships with Mars, an apricot doodle, as the example pet; forks replace her with their own. See `README.md`.

## Where things are

- `Pet/` is the pet: `pet.json` plus `sprites/` and `props/` PNGs. It's read at launch, so art and config changes need a relaunch, not a rebuild. Most fork customization happens here and should stay here. Don't hardcode a pet's name, text, colors or sizes in Swift. Add a `pet.json` key instead, with a default in `defaultsJSON` in `Sources/DesktopPet/Pet/PetConfig.swift`.
- `Sources/DesktopPet/Moments/` has one file per moment, conforming to `PetMoment` and listed in `PetMoments.all`. New behavior goes in a new moment, not in `PetScene`. `docs/ADDING_A_MOMENT.md` describes the pattern.
- `Sources/DesktopPet/Scene/PetScene.swift` holds wander, petting and dragging, plus the shared helpers moments use.
- `tools/` is Python (Pillow + numpy): `check_pet.py` validates `Pet/`, `pixelate.py` converts images to frames, `examples/make_mars_sprites.py` is the procedural generator for Mars.
- To make a new pet from photos, use the `make-my-pet` skill (`.claude/skills/make-my-pet/`).

## Conventions

- Native Swift: SwiftUI (menu bar + Settings) and SpriteKit (the pet) in a borderless, transparent, click-through `NSPanel`. macOS 13+, unsandboxed, not for the App Store.
- Everything stays local: no accounts, no network calls.
- Frames face right, default 68×46, nearest-neighbor filtering. `dog.position` is at the feet. Lay props out relative to `scene.bodyWidth` / `scene.headTopY`, not fixed pixels, so they fit pets of any size.
- A missing sprite falls back to a stand-in (`PetSprites.optional`). A missing prop is a launch-time error (`requiredProps`). Keep it that way so a fork can start with one frame.
- When a moment's sprites or props change, update the frames table in `docs/MAKE_YOUR_OWN_PET.md` and `FEATURE_SPRITES` in `tools/petlib.py`. `requiredProps` is read from the Swift directly.

## Build and check

```bash
swift build                     # compile
swift run                       # run from source (reads ./Pet)
python3 tools/check_pet.py      # validate Pet/, writes build/pet-preview.png
./scripts/build-app.sh          # build/<Name>.app with Pet/ bundled inside
PET_DIR=/path/to/OtherPet swift run   # try another pet folder without touching Pet/
```

There are no unit tests. Verify by building, running `check_pet.py`, and launching the app. Moments can be triggered from the menu bar without waiting for their schedule.
