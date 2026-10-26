# Make your own pet

Everything that makes the pet *yours* lives in one folder, `Pet/`:

```text
Pet/
├── pet.json          name, pronouns, sprite measurements, which moments are on, schedule, colors, text
├── sprites/          the animation frames (68×46 PNGs by default, facing right)
│   ├── stand.png         ← the only one that's required
│   ├── walk_0.png … walk_3.png
│   ├── run_0.png … run_3.png
│   ├── sit.png  sleep.png  eat.png  play_bow.png
│   ├── carry_ball_0.png … carry_ball_3.png
│   └── portrait.png      front-facing face for the menu bar and app icon
└── props/            bowls, kibble, jug, ball, folder (shared by most pets, swap if you like)
```

You never need to touch Swift. Swap the art, edit `pet.json`, run `python3 tools/check_pet.py`, run the app.

## 1. Take a few photos

**You need 1 photo to start. 3–5 is best.**

| Photo | Why | Needed? |
| --- | --- | --- |
| **Side view, whole body, standing**, camera at pet height, plain background | Every frame is drawn from the side. This one photo is the model for all of them. | **Yes** |
| Front-on face | The portrait in the menu bar and the app icon | Recommended |
| 1–3 close-ups of coat, markings, ears, tail, collar or harness | Gets the colors and details right | Recommended |
| Sitting, lying down | Makes those poses look like your pet instead of a guess | Nice to have |
| A short side-on video of walking | Only if you want to trace real movement (route D) | Optional |

The frames face **right**, so you're looking at your pet's **left side**. If its markings differ side to side, photograph the left side.

You don't need a photo per pose. The poses get drawn *from* the side-view photo.

## 2. Make the frames

Pick whichever route suits you. You can mix them, e.g. Claude for the walk cycle and an image generator for the portrait.

### Route A: Claude Code draws it (recommended if you have Claude Code)

Open this repo in Claude Code and run:

```text
/make-my-pet
```

Then drop in your photos. Claude can't paint images directly, but it can write code that draws pixel art. That's how the original Mars frames were made (`tools/examples/make_mars_sprites.py` builds her from ellipses and limbs). Claude studies your photos, writes a generator for your pet, renders every frame, checks them, and shows you a preview sheet to give feedback on. Expect a few rounds of "ears longer, tail curlier."

Without the skill, paste this into Claude (Claude Code, or claude.ai with code execution):

> Here are photos of my pet [name], a [species/breed]. In this repo, `tools/examples/make_mars_sprites.py` draws a dog as 68×46 pixel-art frames from simple body parts. Write `tools/make_my_pet.py` that draws **my** pet the same way: match its silhouette, coat colors, markings, ears and tail from the photos, facing right, feet on row 43. Pick a 12–20 color palette from the photos. Export with `--frames Pet/sprites`, run `python3 tools/check_pet.py`, look at `build/pet-preview.png`, and fix anything off before showing me.

### Route B: an AI image generator + `tools/pixelate.py`

Image generators (ChatGPT, Gemini, Midjourney…) make "pixel-art-looking" images. They aren't on a real pixel grid, and the frames drift in size and color. `tools/pixelate.py` fixes that: it removes the background, snaps the image onto the real grid, limits the palette and puts the feet on the ground line.

1. **Make the main frame first.** Attach your side-view photo and use:

   > Pixel art game sprite of this [species], [main colors, markings, collar or harness]. Full body, side view, **facing right**, standing still. 16-bit style, crisp hard-edged pixels, no anti-aliasing, a limited palette of about 16–20 colors, 1-pixel dark outline. **Plain flat white background**, no shadow, no ground, no text. The sprite is wide and low, about 3:2, filling the image.

   ```bash
   python3 tools/pixelate.py stand-big.png --name stand --outline
   ```

2. **Make the other poses from that one.** Attach the stand image you liked and say "the exact same character, same colors and size", plus one of:

   | Frame(s) | Add to the prompt |
   | --- | --- |
   | `walk_0…3` | "a 4-frame walk cycle, one row of 4 evenly spaced frames" |
   | `run_0…3` | "a 4-frame running cycle, one row of 4 evenly spaced frames" |
   | `sit` | "sitting, facing right, head up" |
   | `sleep` | "lying down asleep, eyes closed, curled up low" |
   | `eat` | "head down, eating from a small bowl on the ground" |
   | `play_bow` | "play bow: front legs flat on the ground, rear up, tail up" |
   | `carry_ball_0…3` | "a 4-frame walk cycle with a yellow-green tennis ball in its mouth, one row of 4 frames" |
   | `portrait` | "front-facing head and shoulders portrait, looking at the camera" |

3. **Convert them**, reusing the stand frame's colors so everything matches:

   ```bash
   python3 tools/pixelate.py walk-sheet.png --sheet 4x1 --name walk --palette Pet/sprites/stand.png --outline
   python3 tools/pixelate.py sit-big.png --name sit --palette Pet/sprites/stand.png --outline
   python3 tools/pixelate.py face.png --name portrait --size 38x56 --palette Pet/sprites/stand.png
   ```

   If it faces left, add `--flip`. If a pose comes out bigger or smaller than the rest, add `--height N` with the same N for every frame. For a cat or a bird that isn't wide and low, change the frame size in `pet.json` (see below).

4. **Fix by hand** wherever it's off, in [Piskel](https://www.piskelapp.com) (free, in the browser) or [Aseprite](https://www.aseprite.org). Generated frames rarely line up perfectly. Lining up the eye and ear from frame to frame is what makes the animation read.

### Route C: draw it yourself

Open [Piskel](https://www.piskelapp.com) or Aseprite, make a 68×46 canvas, put your photo on a layer underneath, and trace. Feet go on row 43, facing right. Export each frame as a PNG with the names above. Start with `stand`, then make `walk_0…3` by moving the legs. Everything else is optional.

### Route D: trace real video (rotoscoping)

Most faithful, most work. Film your pet walking side-on against a plain wall, then pull out frames:

```bash
ffmpeg -i walk.mov -vf "fps=8" frames/walk_%02d.png
```

Pick 4 frames that make one full stride. Cut each one out: in Finder, right-click the image → **Quick Actions → Remove Background**. Then:

```bash
python3 tools/pixelate.py frames/walk_03.png --name walk_0 --bg none --colors 16 --outline --height 40
# …same --height for walk_1…3
```

Raw photos come out looking like tiny photos. Clean them up in Piskel to make them read as pixel art.

## 3. Edit `pet.json`

Only include what you want to change. Anything missing falls back to the defaults in `Sources/DesktopPet/Pet/PetConfig.swift`. A whole valid file can be:

```json
{
  "name": "Biscuit",
  "pronouns": { "they": "he", "them": "him", "their": "his" },
  "features": { "fetch": false }
}
```

| Key | What it does |
| --- | --- |
| `name` | Shown everywhere: menu, Settings, "Thanks, Biscuit" |
| `pronouns` | `they` / `them` / `their`, used in text like "Send Biscuit to his bed" |
| `menuBarSymbol` | Any [SF Symbol](https://developer.apple.com/sf-symbols/): `pawprint.fill`, `bird.fill`, `fish.fill`, `hare.fill`, `tortoise.fill`, and on macOS 14+ `cat.fill`, `dog.fill` |
| `photosFolderName` | The folder in ~/Pictures the daily photo comes from |
| `sprite.frameWidth`, `frameHeight` | Size of every frame in pixels |
| `sprite.feetY` | Row (from the top) where the feet touch the ground |
| `sprite.mouth` | `[x, y]` where carried things (photo, ball, screenshot) sit |
| `sprite.scale` | How big it is on screen. 2–3 looks right. |
| `movement` | `walkSpeed`, `runSpeed`, `tidySpeed` (points/sec), `walkFrameSeconds`, `runFrameSeconds` |
| `features` | `photoDrop`, `meals`, `fetch`, `tidy`, `statusBubbles`: `false` removes it completely |
| `schedule` | Default meal and photo times (`"HH:mm"`), `breakIntervalMinutes`, `fetchThrows` |
| `theme` | `background`, `card`, `ink`, `border`, `accent` hex colors for the windows and speech bubbles |
| `text` | Every line the app shows. Placeholders: `{name}` `{they}` `{them}` `{their}` `{photosFolder}` `{count}` |

To find `feetY` and `mouth`, open `stand.png` in Piskel (or any editor that shows the cursor position) and hover over the bottom of a paw and the mouth. `check_pet.py` warns when they look wrong.

**Not a dog?** Cats don't fetch or eat kibble from a bag (well…). Turn off what doesn't fit (`"features": { "fetch": false }`), change the bubbles (`"mealBubble": "feed me, human"`), and draw different props: a fish instead of kibble, a yarn ball instead of a tennis ball. Keep the prop file names the same.

## 4. Check it and run it

```bash
python3 tools/check_pet.py        # errors, warnings, and build/pet-preview.png
swift run                         # the pet appears above your Dock
```

Look at `build/pet-preview.png`. The red line should sit under every frame's feet, the cyan circle should be on the mouth, and everything should face right.

You don't need to rebuild after changing art or `pet.json`. Quit from the menu bar and `swift run` again.

When you're happy with it, `./scripts/build-app.sh` makes `build/<Name>.app` to keep in /Applications.

## Frames reference

| File | Used for | If it's missing |
| --- | --- | --- |
| `stand.png` | Standing, picking things up | **required** |
| `walk_N.png` | Wandering | `stand` |
| `run_N.png` | Photo drop, fetch, tidy | `walk` |
| `sit.png` | Idle, waiting with the photo or by the bowls | `stand` |
| `sleep.png` | Idle naps | `sit` |
| `sniff.png` | Idle sniffing (bobs up and down) | `stand` |
| `dangle.png` | Being dragged (tilted) | `stand` |
| `eat.png` | Meals | `sit` |
| `play_bow.png` | Inviting you to throw the ball | `stand` |
| `carry_ball_N.png` | Bringing the ball back | `run` |
| `portrait.png` | Menu header, app icon (any size; 38×56 for Mars) | no picture |

Animations (`_N`) can have any number of frames, from `_0` up to the first gap.
