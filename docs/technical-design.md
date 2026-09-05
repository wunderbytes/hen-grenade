# Hen Grenade — Technical Design

Engine choice and its rationale live in [ADR 0001](decisions/0001-engine-choice.md). This document covers how the game is built on top of it.

## 1. Target platforms

| Target | Spec | Notes |
|---|---|---|
| Windows | 10/11, x86_64 | Primary development platform |
| **Raspberry Pi 400**, Raspberry Pi OS (Debian 13 trixie), arm64 | BCM2711 (Cortex-A72 @ 1.8 GHz), VideoCore VI @ 500 MHz, OpenGL ES 3.1, 4 GB LPDDR4, microSD | **The runtime target.** Runtime only — the editor is never installed here |
| Raspberry Pi 4B / Pi 5 / Pi 500 | — | Should all work; none of them is what we design against |
| Desktop Linux x86_64 | Ubuntu/Debian current | Falls out of the Pi build for free; useful for CI |

Performance target: **60 FPS at 1280×720 on a Pi 400** with four players, a full screen of flames, and a crate-regeneration wave landing. 1080p is an option for people on better hardware, not something we tune for.

Targeting one exact machine is a real advantage and we should use it. There are no RAM variants to worry about (always 4 GB), no cooling variance (the full-width passive heatsink is why it ships at 1.8 GHz instead of the Pi 4B's 1.5 GHz, and it does not thermally throttle in a case-less desktop the way a bare Pi 4B can), and the performance number from one machine is the performance number for every user. "It runs at 60 on the Pi 400" is a fact, not an average.

Two consequences worth stating up front:

- **The Pi 400 is the fastest BCM2711 board.** If we hit the target here we have not automatically hit it on a Pi 4B, which is 17% slower on CPU and more prone to throttling. The Pi 4B is best-effort, not a promise.
- **The GPU is identical to a Pi 4B's** — VideoCore VI at 500 MHz. The extra CPU clock buys us nothing on the graphics side, and graphics is where the risk is (§5). Compared with a Pi 5 / Pi 500 (VideoCore VII at 910 MHz) we have roughly half the GPU, which is exactly why the Pi 5 reports behind the engine choice do not transfer.

## 2. The central architectural decision: a pure simulation layer

Gameplay does **not** live in the Godot scene tree and does **not** use Godot's physics engine. It lives in a plain-GDScript, deterministic, fixed-timestep simulation that takes input and produces state.

```
                 ┌──────────────────────────────────────┐
   devices  ───► │ input/    device -> InputFrame        │
   bots     ───► │           (dir, lay, action) per slot │
                 └───────────────┬──────────────────────┘
                                 │  InputFrame[] per tick
                 ┌───────────────▼──────────────────────┐
                 │ sim/      MatchState, Arena, Bombs,   │  60 Hz fixed step
                 │           Blasts, Pickups, Respawn,   │  no Node, no wall-clock,
                 │           RoundClock, Scoring, Rules  │  no delta-time reads
                 │           step(state, inputs) -> ev[] │
                 └───────────────┬──────────────────────┘
                                 │  SimEvent[] (BombPlaced, Exploded, PlayerDied…)
                 ┌───────────────▼──────────────────────┐
                 │ view/     sprites, tween, particles,  │  reads state, never writes
                 │ audio/    SFX, music ducking          │
                 │ ui/       HUD, menus, lobby           │
                 └──────────────────────────────────────┘
```

Why this shape, given it is more upfront work than dropping `CharacterBody2D` nodes in a scene:

- **Testability.** The entire rule set becomes unit-testable in a headless process with no rendering. "Does a radius-3 blast stop at the second crate?" is a five-line test, not a manual playtest.
- **Determinism buys us replays for free.** Seed + input log = the exact round again. That is our bug-reporting mechanism ("attach the replay") and our regression suite (golden replays that must produce identical end states).
- **Bots and humans are interchangeable.** A bot is a function that returns an `InputFrame`. It cannot cheat, because it has no other way to affect the world.
- **It keeps online multiplayer possible** without a rewrite. Deterministic lockstep or rollback both require exactly this separation. We are not building netcode for 1.0, but we are not architecturally excluding it either.
- **It is faster on the Pi.** A grid of integers stepped 60 times a second costs almost nothing, versus a physics world with dozens of bodies and area callbacks.

Determinism rules the sim layer must obey, enforced by code review:
- Fixed 60 Hz step, driven from `_physics_process`; the sim never reads `delta`.
- All randomness from one seeded PRNG owned by `MatchState`, consumed in a fixed order.
- No floats where an integer will do. Positions are fixed-point (sub-tile units, 1 tile = 256 units) rather than `float`.
- No iteration over unordered collections. Entities live in arrays with stable indices.

## 3. Collision and movement

Custom, grid-based, no physics engine:

- A player is a point (their centre) plus a radius for corner assist; collision is tested against the tile grid, not against other bodies.
- Movement resolves one axis at a time, applies lane snapping, then applies corner assist.
- Bomb solidity uses a per-player "standing on my own bomb" exemption flag that clears the first tick the player's centre leaves that tile.
- Blast resolution is a flood along four rays, computed once at detonation and stored as a tile list, not re-evaluated per frame. **Each flame tile carries the owning player index**, propagated through chain detonations, because that is what kill credit and the suicide penalty are derived from.

## 3a. Round clock, respawn, and scoring

All of this is sim state, ticked at 60 Hz, and therefore replayable and testable like everything else.

- The round clock is an **integer tick counter** counting down from 120 s × 60, never a float accumulation of `delta`. It is the sole round-ending condition.
- Respawn is a per-player countdown; on expiry the sim scores every candidate respawn tile by distance to the nearest living player, live bomb, and flame, and takes the best. Ties break by tile index so the choice stays deterministic.
- Spawn protection is a tick counter on the player, cleared early by a bomb drop.
- Kill credit reads the owner off the flame tile that killed the player: someone else's, `+1` to them; your own, `−1` to you.
- Crate regeneration runs on its own tick counter and draws candidate tiles from the seeded PRNG in a fixed order. Its exclusion rules (not adjacent to a living player, never sealing a player in) are a filter applied before the draw, so the number of PRNG calls does not depend on how many candidates were rejected — otherwise determinism quietly breaks.

Nothing here can deadlock a round: there is no last-player-standing check, no overtime, and no stalemate detection to get wrong. The clock runs out and the round ends.

## 4. Input

This is the highest-risk subsystem for our targets, so it gets a dedicated layer.

**Discovery and binding**
- Godot's joypad layer sits on SDL, including the community controller mapping database, so an F310 reports as a standard gamepad on both Windows (XInput) and Linux (`xpad`) with no per-device code from us.
- Players bind in the lobby by **pressing A on the pad they want** (`joy_connection_changed` + first-press capture). A device is bound to exactly one player slot; a slot may also be a keyboard layout or a bot.
- Hot-plug: unplugging a bound pad **pauses the match** and shows "Player 2, reconnect your controller". Rebinding on reconnect matches by device GUID first, then falls back to press-to-claim.

**Reading**
- The D-pad is the primary input; the left stick is converted to four directions with a **0.5 magnitude threshold and hysteresis at 0.35** so diagonal jitter cannot cause corridor stutter.
- Buttons: A = drop bomb, B = detonate (Remote) / toss (Toss), Start = pause, Back = leave.
- Keyboard support for two players on one board (WASD + Space, Arrows + Right Ctrl). On a Pi 400 this is **not a fallback** — see below — so it gets the same care as gamepad input, not debug-quality treatment. It is also how automated tests and solo debugging work.

**Logitech F310 specifics** (documented so the setup guide is right the first time)
- Set the back switch to **X** (XInput) on both Windows and Linux. In X mode the device enumerates as "Logitech Gamepad F310", triggers are analog axes, and the centre Logitech button is usable. Linux binds it via the in-tree `xpad` driver.
- In D (DirectInput) mode on Linux it appears as a "Logitech RumblePad 2"-class device, and **multiple identical pads need the USB HID quirk** `usbhid.quirks=0x046d:0xc219:0x40` to enumerate correctly. We support D mode but the docs will tell people to use X.
- Four pads should go through a **powered USB hub**. Under-powered ports are the single most common cause of "the fourth controller does not work" and of pads dropping out mid-session, and the Pi 400 runs off a 5 V / 3 A supply that we should not be asking to feed four gamepads.

**Pi 400 port budget** — this shapes what we tell users, so it belongs in the design rather than in a support thread later. The Pi 400 has **three USB ports** (2 × USB 3.0, 1 × USB 2.0) and a **keyboard built into the case**. That gives two supported four-player setups:

| Setup | Hardware needed |
|---|---|
| 4 gamepads | A powered USB hub — mandatory, there is no fourth port |
| **3 gamepads + 1 keyboard player** | **Nothing extra** |

The second one matters more than it looks. It is the only way to get four players onto a stock Pi 400 with nothing in the box but the machine and three pads, so we treat it as a first-class configuration: the lobby offers the built-in keyboard as a joinable slot alongside the pads, and the keyboard control scheme gets balanced and playtested rather than being tolerated.

- Rumble is nice-to-have, not required; if it misbehaves on Linux we ship with it off by default.

## 5. Rendering and the Pi 400 performance budget

The VideoCore VI in a Pi 400 is a weak GPU — 500 MHz, roughly half a Pi 5's — and Godot 4 on this class of hardware is not automatically fine: there are field reports of simple Godot 4 tilemap games running at single-digit frame rates on Pi 4-family boards. In the case I looked at, the dominant cost was **`PointLight2D` — removing the 2D lights took that project from 3 FPS to 20**. That is the difference between a budget and a hope, so the rules below are constraints, not preferences.

- **No 2D lights. At all.** No `PointLight2D`, no `DirectionalLight2D`, no `LightOccluder2D`, no `CanvasModulate`-driven lighting. A blast flash is an additive sprite and a palette swap. This is the single most important line in this document for hitting the frame target.
- Base viewport **640 × 360**, `stretch/mode = canvas_items` with **integer scaling**, nearest-neighbour filtering, no mipmaps. It divides evenly into both 720p (×2) and 1080p (×3), so the same build is pixel-exact on either display.
  Rendering the whole game at 640 × 360 and upscaling once is a large, cheap win on this hardware: fragment work scales with the internal resolution, so the Pi is shading a fraction of the pixels a native-resolution game would.
- **Cap the output resolution at 1080p, and default to 720p on the Pi.** The Pi 400's micro-HDMI outputs go up to 4Kp60, so a user who plugs it into a 4K TV gets a 4K desktop and our final upscale blit suddenly covers 8.3 million pixels instead of 0.9 million — nine times the fragment work, on a GPU that has none to spare, for zero visual gain given a 640 × 360 source. The game sets its own fullscreen video mode rather than inheriting the desktop's, and the setup guide says to run the desktop at 1080p. This is the most likely way for a user to experience terrible performance on otherwise fine hardware.
- **Renderer: Compatibility (OpenGL ES 3) for the shipped Pi build.** Vulkan on VideoCore VI is immature, and the Forward+ renderer falls back to Mobile anyway on this GPU. `--rendering-driver opengl3` can force it if a build ever comes up in the wrong mode.
- One texture atlas for the tileset, one per character sheet. Target: **under 20 draw calls per frame**.
- The arena is a static `TileMapLayer` redrawn only when a crate is destroyed or regenerates — never per frame.
- Particles are `CPUParticles2D` with hard caps, or hand-rolled sprite animations. No `GPUParticles2D` on the Pi path.
- No screen-space shaders, no MSAA, no HDR.
- V-sync on, fixed 60 FPS physics tick, `low_processor_mode` off.
- Audio: preload every SFX as WAV in memory (the whole set is a couple of MB), keep the mixer buffer small, and cap simultaneous voices at 16 with priority given to explosions.
- **We measure on real hardware from Milestone 0, and the thing we measure is the worst case**, not a hello-world scene: four players, maximum blast radii, a full chain reaction, and a crate-regeneration wave, all at once. A Pi 400 stays plugged in as the permanent perf reference — one specific machine, so the number means something.
- Assets are loaded from **microSD**, which is slow. Keep the shipped `.pck` small, preload everything at startup behind the title screen, and never load during a round.

Export note carried from the ADR: enable **both** `Import S3TC BPTC` and `Import ETC2 ASTC` in Project Settings → Rendering → Textures, or arm64 builds fail at load with "No loader found for resource".

## 6. Data-driven tuning

Every number in the game design doc marked **(tune)** lives in a Godot `Resource` (`.tres`), not in code:

- `data/balance/default.tres` — speeds, fuse time, blast timing, caps, round length, respawn delay, spawn protection, kit-loss fraction, crate regeneration interval.
- `data/balance/powerups.tres` — drop rate and weight table.
- `data/arenas/*.tres` — grid size, crate density, spawn and respawn tiles, tileset reference.

The sim is written against whatever grid size the arena resource specifies — 25 × 15 is a value, not an assumption baked into the code. Two of the open design questions (arena size, kit loss on death) are answered by editing a `.tres` and playing, which is the point.

Balance changes then become small, reviewable diffs that a designer can make without touching GDScript, and the sim can be instantiated in tests with a synthetic balance resource.

## 7. Proposed repository layout

```
hen-grenade/
├── .godot-version              # pinned engine version, read by CI
├── project.godot
├── docs/                       # this folder
├── src/
│   ├── sim/                    # pure logic: match_state, arena, bombs, blasts, rules
│   ├── input/                  # device manager, slot binding, InputFrame
│   ├── bots/                   # bot controllers, produce InputFrame
│   ├── view/                   # arena renderer, entity views, effects
│   ├── ui/                     # lobby, HUD, pause, scoreboard, options
│   ├── audio/                  # sfx bank, music director
│   └── app/                    # bootstrap, scene routing, settings persistence
├── data/                       # .tres balance + arena definitions
├── assets/                     # art, audio sources, fonts (with LICENSE per pack)
├── tests/
│   ├── unit/                   # GUT tests over src/sim
│   └── replays/                # golden replay files + determinism harness
└── tools/                      # export scripts, Pi deploy script
```

## 8. Testing strategy

- **Unit tests (GUT)** on `src/sim` — the rule set, blast propagation, chain reactions, kill credit through chains, the suicide penalty, power-up application and kit loss on death, respawn tile selection, crate-regeneration exclusion rules, and round scoring. These are the tests that matter and they run headless in seconds.
- **Golden replay tests** — a stored seed + input log must produce a byte-identical end state. This catches accidental non-determinism the moment it is introduced, which is otherwise a nightmare to debug.
- **Bot soak test** — four bots, 200 rounds, headless, assert no crashes, no player ever stuck unable to respawn, no crate sealing a player in, and a sane score distribution. Also our balance smoke signal.
- **Manual hardware pass** per milestone on the reference Pi 400 and on Windows: four F310s through a powered hub, the three-pads-plus-built-in-keyboard configuration, hot-plug, and worst-case frame time.
- CI (GitHub Actions): headless Godot runs unit + replay tests on every push; tagged commits produce Windows x86_64 and Linux arm64 artifacts.

## 9. Distribution

- **Windows:** a zip containing `HenGrenade.exe` + `.pck`. No installer for 1.0.
- **Raspberry Pi:** a `.tar.gz` with the arm64 binary, `.pck`, a `.desktop` entry, and an optional `install-kiosk.sh` that sets up autostart into the game on boot — a Pi 400's most likely job here is being a dedicated party box wired to a TV, and it has a keyboard attached for the setup, which makes kiosk mode safe to offer without stranding anyone.
- Version stamped into the build and shown in the corner of the main menu, so bug reports are actionable.

## 10. What we are deliberately not building yet

Online play, a map editor, mod support, a replay viewer UI (the format exists; the UI does not), and cosmetics. The architecture leaves room for the first two; the rest are out of scope until the couch game is fun.
