# Hen Grenade

A local-multiplayer, Bomberman-style arena battler for **Windows** and **Raspberry Pi**, built for four people on one couch with four gamepads.

> **Status: Milestone 1 complete.** The hardware spike passed on a real Pi 400 (M0) and the rule set now exists, is unit-tested headless, and is playable with two keyboard players on programmer art (M1). Power-ups, the lobby, bots and real art are still ahead — see the [roadmap](docs/roadmap.md).

## Playing it

Open the project in **Godot 4.7.2** and press play, or run an exported build. The
game starts itself after a title beat.

| | Move | Bomb |
|---|---|---|
| **Player 1** | `W` `A` `S` `D` | `Space` |
| **Player 2** | arrow keys | `Right Ctrl` |

Gamepads join by pressing **A**; if none are connected the two keyboard layouts
are claimed automatically, because the lobby does not exist until M2. `F1` title,
`F2` stress benchmark, `F3` input sandbox, `F4` match, `F5` metrics overlay, `R`
to replay a finished round.

Every round is recorded to `user://replays/` as a seed plus an input log — about
29 KB for a full two-minute round, which is what makes "attach the replay to the
bug report" practical.

```bash
# Run the sim test suite headless (10 suites, 104 tests)
godot --headless --script res://tests/run_tests.gd

# Load and step every scene, the way CI does
godot --headless -- --smoke
```

## What it is

Two to four players share a wide arena, dropping fuse-lit bombs to blast apart crates, grab power-ups, and blow each other up. It is a **timed deathmatch**: dying costs you a second and a half and some of your kit, never the round, so nobody ever sits and watches. Two minutes on the clock, most kills wins. No accounts, no online, no menus between rounds — plug in a controller, press A, play.

The tone is light and playful, but **the theme and the final title are deliberately still open** — the design is written theme-free so the decision can wait until art production starts.

## Planned targets

- **Windows** 10/11, x86_64
- **Raspberry Pi 400**, Raspberry Pi OS **32-bit (armhf)** — the target machine, 60 FPS at 720p
- Up to four USB gamepads (Logitech F310 class), hot-pluggable. Four pads need a powered USB hub on a Pi 400; **three pads plus the built-in keyboard** is a supported four-player setup with no extra hardware

## Documents

| Document | What it answers |
|---|---|
| [Game design](docs/game-design.md) | What the game is: rules, arena, power-ups, modes, feel, non-goals |
| [Technical design](docs/technical-design.md) | How it is built: simulation architecture, input, Pi performance budget, repo layout, testing |
| [Roadmap](docs/roadmap.md) | Milestones M0–M6, exit criteria, and the risk register |
| [Milestone 0 build brief](docs/milestone-0-brief.md) | The executable spec for the first milestone: project settings, skeleton architecture, input contracts, the benchmark scene, and the measurement protocol |
| [Milestone 1 build brief](docs/milestone-1-brief.md) | The executable spec for the simulation layer: the determinism contract, arena generation, movement, blasts and chains, respawn, replays, and the test plan |
| [M0 completion notes](docs/progress/m0-completion.md) | What was implemented for M0 and the hardware pass result |
| [M1 completion notes](docs/progress/m1-completion.md) | What was implemented for M1, what was verified, the rule decisions taken, and what is still owed |
| [Pi 400 measurements](docs/measurements/m0-pi400.md) | The performance protocol and the running record every milestone appends to |
| [ADR 0001 — Engine choice](docs/decisions/0001-engine-choice.md) | Why Godot 4.7 over LÖVE, pygame, SDL, and Bevy |

## The short version of the plan

- **Engine: Godot 4.7.2, GDScript, 2D.** It is the only candidate that ships official Windows x86_64 *and* Linux arm32 export templates from one project, and its SDL-backed gamepad layer handles the four-controller requirement without custom code.
- **A 25 × 15 arena at a 640 × 360 internal resolution**, integer-scaled ×2 to 720p and ×3 to 1080p, with the HUD in the side margins — the whole playfield on screen at once, filling a 16:9 display.
- **Gameplay runs in a pure, deterministic 60 Hz simulation** outside the scene tree, with rendering as a read-only view on top. That makes the rules unit-testable headless, gives us replays for bug reports and regression tests, makes bots and humans interchangeable, and leaves online play possible later without a rewrite.
- **Milestone 0 was a hardware spike, not a feature.** Four F310s and 60 FPS on a real Pi 400 — measured on a deliberate worst-case scene, not a hello-world — were proven before a single gameplay rule was written. The Pi 400's GPU is the biggest risk in the project, so it got tested first, and the engine choice was written to be reversible at exactly that point. It passed; Godot stays.
- **Milestone 1 is the rule set, and it is testable rather than watchable.** Bombs, chains, kill credit, respawn and the round clock all live in `src/sim/` as a pure function of state and input, covered by 104 headless tests and a golden replay that must reproduce a committed state fingerprint. The programmer-art rendering on top is the last thing built, deliberately: if the rules are wrong, watching squares move around will not tell you.
