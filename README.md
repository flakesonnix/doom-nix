# DOOM / NIX

A playable, Doom-inspired single-player FPS written in **Nix**, using
[nixray](https://github.com/flakesonnix/nixray) for graphics, input, and audio.
The raycaster, collision detection, combat, enemy AI, campaign, pixel artwork,
and sound synthesis are Nix expressions. No C game engine, JavaScript, Python,
downloaded artwork, or original Doom assets are used.

**This is an original grid-based game, not a complete reimplementation of id
Software's Doom.** It does not load WADs or reproduce Doom's BSP renderer, maps,
physics, multiplayer, or demo format.

## Play

```sh
cd doom-nix
nix run .
```

Requires Linux, Nix with flakes enabled, and an X11 or Wayland display. The flake
pins nixray and the matching Nix evaluator together; do not load its plugin into
an arbitrary system Nix.

```sh
nix run . -- --arg audio false          # No audio device
nix run . -- --arg columns 120          # Lower raycasting resolution
nix run . -- --arg columns 240          # Higher raycasting resolution
NIXRAY_GRAPHICS=system nix run .         # Use an existing system driver setup
nix build
./result/bin/doom-nix
```

The default is 160 ray columns in a 960×640 window. `columns` must divide 960.
Nix evaluation and your graphics driver determine the achievable frame rate;
60 FPS is a target, not a guarantee. State is printed as JSON when you quit.

### Controls

| Key | Action |
| --- | --- |
| Enter / Space | Start, continue, or retry |
| W/S or Up/Down | Forward/backward |
| A/D | Strafe |
| Left/Right | Turn; select difficulty on the title screen |
| Shift | Run |
| Space / Ctrl / left click | Fire (hold for automatic fire) |
| E | Use a nearby door or exit terminal |
| 1/2/3/4 | Fist / pistol / shotgun / chaingun |
| C | Toggle mouse capture and horizontal mouse look |
| Tab | Automap (the game keeps running) |
| P | Pause/resume |
| R | Restart the current sector |
| M | Mute/unmute effects |
| Escape | Quit |

### Campaign

Three sectors: **The Derivation**, **Impure Evaluation**, and **Garbage Collector**.
Find the red keycard, open the red-striped door, and use the green exit terminal.
The final sector requires killing both barons before the exit releases.

- Guards use hitscan attacks; imps and barons throw dodgeable fireballs.
- Shotguns fire seven individual pellets; enemies and walls block shots.
- Medkits restore health; armor absorbs half of incoming damage.
- Green sludge hurts over time. Keep moving and use cover.
- Each sector contains a disguised secret door. Use suspicious metal walls.
- Weapons, ammunition, health, and armor carry between sectors; keycards do not.
- Retrying resets that sector's inventory and stats. There is no save system.
- Artwork and nine sound effects are generated from Nix. The build's shell code
  only serializes the Nix-computed WAV bytes and launches nixray.

## Tests

```sh
nix-instantiate --eval --strict --json tests/default.nix
nix flake check -L
```

The pure suite covers map reachability and key gating, ray intersections,
collision, movement, all weapons, pickups, damage, AI, projectiles, campaign
transitions, controls, and every generated artwork pixel. The flake also runs
real rendering under Xvfb across title/game/pause/death/intermission/victory,
all maps, automap, gun effects, and moving doors, plus a packaged launcher/audio
smoke test with a null audio device.

For local development beside the existing `../nixray` checkout:

```sh
../nixray/result/bin/nixray doom.nix
```

That direct command defaults to no audio assets. The packaged launcher supplies
the generated sound directory automatically.
