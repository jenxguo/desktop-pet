---
name: make-my-pet
description: Turn photos of someone's pet into this desktop pet — pixel-art sprite frames in Pet/sprites, a portrait, and a filled-in Pet/pet.json. Use when the user runs /make-my-pet, shares photos of their pet, or asks to make the desktop pet look like their own animal.
---

# Make my pet

You're helping someone turn their real pet into this app's pixel-art desktop pet. The result is a `Pet/` folder that `python3 tools/check_pet.py` passes and that looks recognizably like *their* animal. Read `docs/MAKE_YOUR_OWN_PET.md` first; it's the user-facing version of this and the frame reference.

## 1. Get photos and facts

Ask for what's missing, in one message:

- **Photos.** One side-on, full-body standing photo is enough to start; 3–5 is better (front face, close-ups of markings). If they only have photos from the wrong side, say you'll mirror it. Frames face right, which shows the pet's left side.
- **Name and pronouns**, and which moments fit this animal (`photoDrop`, `meals`, `fetch`, `tidy`). A cat probably doesn't fetch; ask rather than assume.
- Anything distinctive they care about: "one ear always flops", "she wears a red bandana".

Look at the photos closely and write down, before drawing anything: silhouette and proportions (leg length vs body, head size, muzzle length), ear shape and how they hang, tail shape and carriage, coat texture, every color as a hex (5 shades for the main coat, highlight to deep, plus outline, nose and eyes), markings and where they sit, accessories. Show this description to the user. It's cheap to correct now and expensive later.

## 2. Draw the frames with code

You draw by writing a Python generator, like `tools/examples/make_mars_sprites.py`. Read that file first. It builds the dog from shaded ellipses and limbs on a 68×46 grid, adds a curly fur edge, an outline and pixel overrides for the eyes and nose, and exports every frame with `--frames DIR`.

Make `tools/make_<petname>_sprites.py`:

- **Same species and roughly the same shape:** copy the Mars script. Change `PAL` to their colors, reshape the body parts (`head()`, the leg and body ellipses in `dog()`), redo the ears, tail and markings, and drop or replace the harness. Remove the curl texture for smooth-coated pets.
- **Different animal:** keep the `Canvas` machinery (ellipse and limb parts, shading, outline, render) and write new pose functions. Keep the same `FRAMES` list and file names.
- Keep the conventions: facing right, feet on row 43 (or update `sprite.feetY`), mouth around (53, 18) in standing frames (or update `sprite.mouth`). Every frame is the same size. Every animation's frames share the body and only move the legs, ears and tail, so it doesn't jitter.
- A wider or taller animal can use a different frame size. Set `sprite.frameWidth` / `frameHeight` / `feetY` / `mouth` / `scale` in `pet.json` to match.
- Write the portrait (`Pet/sprites/portrait.png`, front-facing head and shoulders, about 38×56) from the front-face photo, as a separate function in the same script.

Start with `stand` alone. Render it big, look at it next to the photo, fix it, and only then do the other poses. The order after that: `walk_0…3`, `sit`, `sleep`, `run_0…3`, then `eat`, `play_bow` and `carry_ball_0…3` for the moments that are on.

## 3. Check and show

```bash
python3 tools/make_<petname>_sprites.py --frames Pet/sprites
python3 tools/check_pet.py
```

Look at `build/pet-preview.png` yourself, with the Read tool, before showing the user. Check it faces right, feet sit on the red line, the cyan mouth circle is on the mouth, walk frames don't jitter, and it looks like the photo. Fix what you see, then show the user the preview and ask what to change. Iterate. "Ears longer" and "nose pinker" are normal rounds.

If the user would rather have an AI image generator do the drawing, point them to Route B in `docs/MAKE_YOUR_OWN_PET.md` and run `tools/pixelate.py` on the images they bring back.

## 4. Fill in pet.json

Edit `Pet/pet.json`: `name`, `pronouns`, `menuBarSymbol`, `photosFolderName` ("<Name> Photos"), `sprite` measurements if they changed, `features` for the moments they chose, and `theme.accent` from an accent color on the pet (collar, harness, eyes). Rewrite the `text` bubbles in the pet's voice if they want; keep the `{placeholders}`. Only include keys that differ from the defaults in `Sources/DesktopPet/Pet/PetConfig.swift`.

Props in `Pet/props/` are generic (bowls, kibble, ball, folder). Offer to redraw any that don't fit the animal, keeping the same file names and roughly the same sizes.

## 5. Run it

Tell the user to run `swift run` (art and `pet.json` changes need no rebuild, just a relaunch), and `./scripts/build-app.sh` for a real `.app` once they're happy. You can't see their screen, so ask how it looks moving. Speed (`movement`) and size (`sprite.scale`) are easy to tune in `pet.json`.

Delete any scratch files you made outside `Pet/` and `tools/`. Keep their generator script: they'll want it later to add poses.
