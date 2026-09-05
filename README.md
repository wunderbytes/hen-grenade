# Hen Grenade

A local-multiplayer, Bomberman-style arena battler for **Windows** and **Raspberry Pi**, built for four people on one couch with four gamepads.

> **Status: design phase.** No code yet. The documents below are the plan, and they are up for review before anything gets implemented.

## What it is

Two to four players share a wide arena, dropping fuse-lit bombs to blast apart crates, grab power-ups, and blow each other up. It is a **timed deathmatch**: dying costs you a second and a half and some of your kit, never the round, so nobody ever sits and watches. Two minutes on the clock, most kills wins. No accounts, no online, no menus between rounds — plug in a controller, press A, play.

The tone is light and playful, but **the theme and the final title are deliberately still open** — the design is written theme-free so the decision can wait until art production starts.

## Planned targets

- **Windows** 10/11, x86_64
- **Raspberry Pi 400**, Raspberry Pi OS arm64 — the target machine, 60 FPS at 720p
- Up to four USB gamepads (Logitech F310 class), hot-pluggable. Four pads need a powered USB hub on a Pi 400; **three pads plus the built-in keyboard** is a supported four-player setup with no extra hardware

## Documents

| Document | What it answers |
|---|---|
| [Game design](docs/game-design.md) | What the game is: rules, arena, power-ups, modes, feel, non-goals |
| [Technical design](docs/technical-design.md) | How it is built: simulation architecture, input, Pi performance budget, repo layout, testing |
| [Roadmap](docs/roadmap.md) | Milestones M0–M6, exit criteria, and the risk register |
| [Milestone 0 build brief](docs/milestone-0-brief.md) | The executable spec for the first milestone: project settings, skeleton architecture, input contracts, the benchmark scene, and the measurement protocol |
| [ADR 0001 — Engine choice](docs/decisions/0001-engine-choice.md) | Why Godot 4.6 over LÖVE, pygame, SDL, and Bevy |

## The short version of the plan

- **Engine: Godot 4.6.3, GDScript, 2D.** It is the only candidate that ships official Windows x86_64 *and* Linux arm64 export templates from one project, and its SDL-backed gamepad layer handles the four-controller requirement without custom code.
- **A 25 × 15 arena at a 640 × 360 internal resolution**, integer-scaled ×2 to 720p and ×3 to 1080p, with the HUD in the side margins — the whole playfield on screen at once, filling a 16:9 display.
- **Gameplay runs in a pure, deterministic 60 Hz simulation** outside the scene tree, with rendering as a read-only view on top. That makes the rules unit-testable headless, gives us replays for bug reports and regression tests, makes bots and humans interchangeable, and leaves online play possible later without a rewrite.
- **Milestone 0 is a hardware spike, not a feature.** Four F310s and 60 FPS on a real Pi 400 — measured on a deliberate worst-case scene, not a hello-world — are proven before a single gameplay rule is written. The Pi 400's GPU is the biggest risk in the project, so it gets tested first, and the engine choice is written to be reversible at exactly that point.
