# Doom 1.9 shareware / Nix

A Nix game engine targeting the **original Doom 1.9 shareware IWAD**, using
[nixray](https://github.com/flakesonnix/nixray) for native graphics, input, and
audio. The earlier custom three-map raycaster has been replaced with the
original nine-map episode and a WAD/sector/BSP-based implementation.

**This is not yet a one-to-one Doom port.** Original map and asset data are used,
but gameplay compatibility is incomplete. In particular:

- Rendering uses textured GPU geometry generated from the original BSP, not
  Doom's column/visplane software renderer. Lighting, masked surfaces, moving
  floor side walls, palette flashes, and some texture alignment differ.
- Enemy decisions, collision details, action ordering, and several specials are
  approximations. Vanilla demo playback and deterministic equivalence are not
  implemented; the episode has not been verified by a complete playthrough.
- MUS music, original savegames, multiplayer, attract demos, screen wipes, and
  the complete original menu/intermission behavior are not implemented.
- Map transitions recreate the nixray window to load the next map's assets.
  Escape currently quits instead of opening Doom's menu.

## Run

```sh
cd doom-nix
nix run .
```

Requires Linux, a display, and Nix with flakes. The first build downloads the
unchanged shareware distribution from the idgames mirror, checks its SHA-256,
extracts `DOOM1.WAD` without executing the DOS installer, and checks the IWAD's
SHA-256 too. No registered/commercial IWAD is downloaded or required.

```sh
nix run . -- --arg audio false
nix run . -- --arg map 3 --arg skill 3 --arg start true
NIXRAY_GRAPHICS=system nix run .
nix build
./result/bin/doom-nix
```

`map` is 1–9; `skill` is 0–4. The default starts on the original title screen.
Press Enter to show the skill menu, select with arrows, and press Enter again.
The display is 320×200 internally, stretched to 960×720 for Doom's 4:3 aspect.
Finite headless runs accept `--arg hidden true --arg maxFrames 3`.

## Controls

| Key | Action |
| --- | --- |
| W/S or Up/Down | Forward/back |
| A/D | Strafe |
| Left/Right | Turn |
| Shift | Run |
| Ctrl / left mouse | Fire |
| Space / E | Use doors and switches |
| 1 | Fist / chainsaw |
| 2/3/4/5 | Pistol / shotgun / chaingun / rocket launcher |
| Tab | Automap; simulation continues |
| P | Pause |
| C | Mouse capture / horizontal mouse look |
| M | Mute effects |
| R | Restart the map with starting inventory |
| Enter | Continue intermission / retry |
| Escape | Quit |

## What is Nix

`vanilla/binary.nix` and `vanilla/wad.nix` decode little-endian structures, lump
directories, patches, palettes, composite textures, flats, map records, BSP
nodes, and blockmaps. `vanilla/geometry.nix` clips convex subsectors and produces
textured geometry. Simulation, weapon states, damage, pickups, triggers,
sector movers, sprites, HUD composition, and input handling are Nix.

Native tools provide infrastructure only: unzip extracts the distribution,
`od` transports binary bytes as hex, `printf` writes Nix-computed image/sound
bytes, ImageMagick losslessly serializes the decoded images as PNG, and nixray
loads/draws assets and plays audio. No C Doom engine, DOS emulator, JavaScript
game, or Python game implementation is launched.

The original artwork, maps, sounds, and shareware distribution remain copyright
id Software and subject to their original terms, **not** the engine's license.
The data derivation retains the original archive and its README. Engine rule
constants and the deterministic random table are based on id Software's
GPL-released Doom sources; see `LICENSE`.

## Verify

```sh
nix flake check -L
```

The checks compare original IWAD dimensions/counts and spawn data, decode
textures/patches, exercise BSP/collision/35 Hz simulation and gameplay rules,
load and render all nine maps under Xvfb, verify lossless image/alpha decoding,
play original effects through a null audio device, and smoke-test the packaged
launcher. These checks establish the stated coverage, **not** vanilla parity.
