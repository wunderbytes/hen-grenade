# Hen Grenade — Technical Design

Engine choice and its rationale live in [ADR 0001](decisions/0001-engine-choice.md). This document covers how the game is built on top of it.

## 1. Target platforms

| Target | Spec | Notes |
|---|---|---|
| Windows | 10/11, x86_64 | Primary development platform |
| **Raspberry Pi 400**, Raspberry Pi OS **32-bit (armhf / arm32)** | BCM2711 (Cortex-A72 @ 1.8 GHz), VideoCore VI @ 500 MHz, OpenGL ES 3.1, 4 GB LPDDR4, microSD | **The runtime target.** Runtime only — the editor is never installed here. The reference machine runs the 32-bit OS, so the shipped Linux binary is Godot's **`arm32`** export, not `arm64` |
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
- Blast resolution is a flood along four rays, computed once at detonation and stored as a tile list, not re-evaluated per frame. **Each flame tile carries the owning player index**, propagated through chain detonations from the player who *started* the chain, because that is what kill credit and the suicide penalty are derived from. See [game design §5.2](game-design.md) — the two documents disagreed on this until M1 settled it in favour of propagation.

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
- The rule players learn is uniform across devices: **join with your bomb button, leave with your action button** — A / B on a pad, `Space` / `Q` on the WASD seat, `Right Ctrl` / `/` on the arrows seat. Leaving is live only in the lobby, because B is the action button in a round.
- **Joining is gated on the lobby.** A pad pressing A mid-round must not take a seat: `MatchState`'s active-slot list is frozen when the round starts, so a late joiner would get a HUD card and no body. Reconnecting a *reserved* seat is allowed regardless — a reconnect is not a join.
- Hot-plug has **two policies, one mechanism** (decided in M2). A bound pad that disappears **in the lobby** has its seat freed: nobody is mid-round and a pad on the floor is just a pad on the floor. A bound pad that disappears **in a match** has its seat reserved and **pauses the round**, showing "Player 2 — plug it back in". `BACK` from that notice quits to the lobby, because a party game that can be soft-locked by a loose USB plug is worse than one with no hot-plug handling at all.
- Rebinding on reconnect matches by device **GUID** first and only when that is unambiguous. Two seats waiting on the same GUID is what four identical F310s produce, and there is no way to tell them apart, so the notice asks for a press and the seats are claimed in slot order. Matching on Godot's device *index* would be wrong: that index is a slot in the engine's own table and gets reused, so a stale index can hand one player's seat to a different controller.
- **Slot assignment is a pure, tested layer.** All of the above lives in `DeviceBinder` — no `Node`, no autoload, no `Input` — with `DeviceManager` reduced to the hardware adapter around it. That inversion exists because the autoload is unreachable from a `--script` test process (Appendix A.2), so as long as the decisions lived inside it they could not be tested at all.

**Reading**
- The D-pad is the primary input; the left stick is converted to four directions with a **0.5 magnitude threshold and hysteresis at 0.35** so diagonal jitter cannot cause corridor stutter.
- Buttons: A = drop bomb, B = detonate (Remote) / toss (Toss), Start = pause, Back = leave.
- **Menu buttons are a separate layer from gameplay input.** Start, Back, Y and X never enter `InputFrame`: that struct is the replay format and what bots emit, and a pause the simulation could observe would be a determinism bug waiting to happen. Menus also read *hardware* rather than slots, so any connected pad can confirm a rematch, including one that never joined — the opposite of gameplay input, where an unbound device can do nothing at all. All of it is edge-detected once per physics frame in `DeviceManager`, which as an autoload always runs before the current scene, so no two menus can disagree about what a press means.
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
- Base viewport **640 × 360** with **`stretch/mode = viewport`** and **integer scaling**, nearest-neighbour filtering, no mipmaps. It divides evenly into 720p (×2) and 1080p (×3), so the same build is pixel-exact on either display.

  **`viewport`, not `canvas_items`, and the distinction is the whole point.** In `viewport` mode the game is rendered into a real 640 × 360 render target and then blitted up once, so every sprite, every overdrawn flame, and all the alpha blending happen at 230 000 pixels regardless of the display. In `canvas_items` mode Godot renders at the *native* window resolution and merely scales the coordinate system — the pixel-art look is identical, but on a 1080p screen the GPU is shading nine times as many fragments. On a VideoCore VI that difference is likely to be the entire frame budget. The cost of `viewport` mode is that the UI is also confined to 640 × 360 (chunky text, no sub-pixel smoothness), which our art direction wanted anyway.
- **Default to a 1280 × 720 borderless window on the Pi, and cap output at 1080p.** The Pi 400's micro-HDMI goes to 4Kp60, so a user on a 4K TV gets a 4K desktop. `viewport` stretch mode contains most of the damage — only the final blit scales — but that blit is still 8.3 million fragments plus compositing on a GPU with nothing to spare.

  Being honest about the fix: **Godot cannot reliably change the display mode on Linux**, so "the game sets its own video mode" is not something we can promise. What we actually do is (a) render internally at 640 × 360 so scene complexity never scales with output size, (b) default to a borderless 720p window rather than fullscreen on the Pi, and (c) have the kiosk installer set the display mode itself via `xrandr`, or via `video=HDMI-A-1:1920x1080@60` on the kernel command line. The setup guide says to run the desktop at 1080p. M0 measures 720p, 1080p, and 4K output so we know the real shape of this curve instead of guessing.
- **Renderer: Compatibility (OpenGL ES 3) for the shipped Pi build.** Vulkan on VideoCore VI is immature, and the Forward+ renderer falls back to Mobile anyway on this GPU. `--rendering-driver opengl3` can force it if a build ever comes up in the wrong mode.
- One texture atlas for the tileset, one per character sheet. Target: **under 20 draw calls per frame**.
- The arena is a static `TileMapLayer` redrawn only when a crate is destroyed or regenerates — never per frame.
- Particles are `CPUParticles2D` with hard caps, or hand-rolled sprite animations. No `GPUParticles2D` on the Pi path.
- No screen-space shaders, no MSAA, no HDR.
- V-sync on, fixed 60 FPS physics tick, `low_processor_mode` off.
- Audio: preload every SFX as WAV in memory (the whole set is a couple of MB), keep the mixer buffer small, and cap simultaneous voices at 16 with priority given to explosions.
- **We measure on real hardware from Milestone 0, and the thing we measure is the worst case**, not a hello-world scene: four players, maximum blast radii, a full chain reaction, and a crate-regeneration wave, all at once. A Pi 400 stays plugged in as the permanent perf reference — one specific machine, so the number means something.
- Assets are loaded from **microSD**, which is slow. Keep the shipped `.pck` small, preload everything at startup behind the title screen, and never load during a round.

Export note carried from the ADR: enable **both** `Import S3TC BPTC` and `Import ETC2 ASTC` in Project Settings → Rendering → Textures, or ARM builds fail at load with "No loader found for resource". Those two settings govern the *import* side; the Linux arm32 **export preset** additionally needs `texture_format/etc2_astc=true`, which is not the Godot default and is the same trap wearing a different hat.

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

- **Unit tests** on `src/sim` **and on the pure parts of `src/input` and `src/ui`** — the rule set, blast propagation, chain reactions, kill credit through chains, the suicide penalty, power-up application and kit loss on death, respawn tile selection, crate-regeneration exclusion rules, round scoring, and (from M2) slot assignment: joins, leaves, bots, GUID reconnects and the identical-pad case. The line is not "input is untestable" — it is `Input` and `Node` that cannot be reached from a `--script` process, so the logic that matters is kept out of both. These are the tests that matter and they run headless in seconds. They run on a small in-repo harness (`tests/test_case.gd` + `tests/run_tests.gd`) rather than GUT: the sim layer is pure GDScript with no Nodes, which is exactly the case a 100-line runner handles well, and vendoring a third-party addon to get assertion sugar is a poor trade. Decided in M1; see [the M1 brief §10](milestone-1-brief.md).
- **Golden replay tests** — a stored seed + input log must produce a byte-identical end state. This catches accidental non-determinism the moment it is introduced, which is otherwise a nightmare to debug.
- **Bot soak test** — four bots, 200 rounds, headless, assert no crashes, no player ever stuck unable to respawn, no crate sealing a player in, and a sane score distribution. Also our balance smoke signal.
- **Manual hardware pass** per milestone on the reference Pi 400 and on Windows: four F310s through a powered hub, the three-pads-plus-built-in-keyboard configuration, hot-plug, and worst-case frame time.
- CI (GitHub Actions): headless Godot runs unit + replay tests on every push; tagged commits produce Windows x86_64 and Linux arm32 artifacts.

## 9. Distribution

- **Windows:** a zip containing `HenGrenade.exe` + `.pck`. No installer for 1.0.
- **Raspberry Pi:** a `.tar.gz` with the arm32 binary, `.pck`, a `.desktop` entry, and an optional `install-kiosk.sh` that sets up autostart into the game on boot — a Pi 400's most likely job here is being a dedicated party box wired to a TV, and it has a keyboard attached for the setup, which makes kiosk mode safe to offer without stranding anyone.
- Version stamped into the build and shown in the corner of the main menu, so bug reports are actionable.

## 10. What we are deliberately not building yet

Online play, a map editor, mod support, a replay viewer UI (the format exists; the UI does not), and cosmetics. The architecture leaves room for the first two; the rest are out of scope until the couch game is fun.

---

## Appendix A — M0 implementation notes (lessons learned)

These are Godot-specific facts that bit us during M0 and are worth remembering for later milestones. They are implementation realities, not design changes. Numbered so later milestones can append their own.

### A.1 `godot --headless --import` does not fully compile scene scripts

The import step registers class names and imports assets, but it does **not** fully parse every scene-attached GDScript the way a real run does. Type errors and bad enum references in scene scripts (e.g. `Vector2i + Vector2`, `Control.VALIGN_TOP`) only surface when the scene is actually loaded/instantiated. **Implication for CI:** `--import` is a prerequisite, not a verification — it will not catch script bugs on its own. The test/CI pipeline must actually load or run scenes. M1 should add a scene-smoke step to CI (instantiate each scene, step a few physics ticks, assert no errors), not just `--import`.

### A.2 Autoloads are not registered in `--script` mode

Running a custom main loop with `godot --headless --script res://foo.gd` does **not** instantiate project autoloads, so any script referencing an autoload global (e.g. `DeviceManager`) fails to compile in that mode. `class_name` globals **are** available; autoloads are not. Headless test scripts therefore cannot reference autoloads. The sim layer is pure (no autoloads), so M1's sim tests are fine; anything that needs `DeviceManager` must be tested by running the actual game, not via `--script`.

### A.3 Running a scene via the editor binary opens the editor, not the game

`godot --headless --path <project> res://scene.tscn` opens the scene in the headless **editor** (which then waits); it does not run the scene as a game. To run a specific scene headless without exporting: either set it as `run/main_scene` and run `godot --headless --path <project>`, or use `--script` with a `SceneTree` (subject to A.2). For CI artifact verification, prefer exporting and running the export.

### A.4 `SceneTree._iteration` is not overridable from GDScript

A `--script` that `extends SceneTree` and overrides `_iteration` will not have `_iteration` called — the engine drives the C++ `SceneTree::_iteration` directly, so a GDScript override is silently ignored and the loop never quits. A custom main loop can do setup in `_initialize`/`_init` and call `quit()` from there; for per-frame work, drive it manually (call `_physics_process`/`_process` on the scene root from `_initialize`) rather than relying on `_iteration`.

### A.5 GDScript has no implicit cross-type vector arithmetic

`Vector2i + Vector2` is a parse error; cast explicitly (`Vector2(C.ARENA_ORIGIN) + v`). Assignment of `Vector2i` to a `Vector2` property **is** auto-converted, but arithmetic is not. **Coding convention for the whole project:** when mixing `Vector2i` constants (like `C.ARENA_ORIGIN`) with `Vector2` math, wrap the constant in `Vector2(...)`.

### A.6 Theme font access on Node2D

`get_theme_default_font()` is not available on `Node2D` (and was removed in Godot 4.7). For text in `Node2D` scenes, prefer `Label` nodes over `draw_string` with a theme font — it is robust across versions and needs no font-API lookup. If `draw_string` is ever required, `ThemeDB.get_default_theme().get_font(...)` works, but the enum/StringName fragility makes `Label` the safer default.

### A.7 `vertical_alignment` enum names are version-fragile

`Control.VALIGN_TOP` is Godot 3; `Control.VERTICAL_ALIGNMENT_TOP` does not exist in 4.7 either. Set `label.vertical_alignment = 0` (top) as an **integer** — it is stable across versions. Avoid the named enum for this property.

### A.8 Export templates folder uses a dot, not a hyphen

`.godot-version` and the GitHub release tag use `4.7.2-stable` (hyphen), but the export-templates directory Godot looks for is `4.7.2.stable` (dot) — the editor's `--version` string form. CI must convert (`${V/-stable/.stable}`) when placing templates, or the export fails with "no templates found".

### A.9 `.uid` files are committed

Godot 4.4+ writes a `<script>.uid` beside every GDScript; these are stable resource identifiers and should be committed (they are **not** in `.gitignore`). The M0 brief's `.gitignore` list predates this and does not mention them; they are part of the repo.

### A.10 No separate headless download since Godot 4.0

Since Godot 4.0 there is **no** `Godot_v<x>_linux_headless.*.zip` release asset — the standard editor binary (`Godot_v<x>-stable_linux.x86_64.zip`) is run with `--headless` for import, tests, and exports. CI must download the `linux.x86_64.zip` asset (not a `_linux_headless` one, which 404s) and invoke it with `--headless`. The renamed binary is still called `godot_headless` in CI purely as a stable local path name.

### A.11 Label drop shadows are a second text pass, and they cost draw calls

Setting `font_shadow_color` on a `Label` makes Godot draw the text **twice**. On
M1's seven-Label HUD that alone was **28 of 44 draw calls** — against a
documented budget of 20 — while the entire 375-cell arena `TileMapLayer` cost
**one**. Dropping the shadow from the five Labels that sit on the flat HUD
margin (keeping it only on the clock and the round-end banner, which overlap
busy pixels) took the whole frame to **16**. Rule for later milestones: a
shadowed Label is a deliberate expense, not free polish, and the HUD is a more
likely source of draw calls than the arena is.

### A.12 Group `_draw` calls by primitive type, not by entity

Godot's 2D renderer batches consecutive same-kind primitives. Drawing entity by
entity — circle, circle, rect, circle, rect — breaks the batch every time.
Drawing in passes (all flame rects, then all bomb circles, then all player
rects) makes the cost proportional to the number of *passes* rather than the
number of entities: M1's worst case, twenty-eight simultaneous radius-6 bombs
with the arena almost entirely on fire, draws in **9 calls**, fewer than a quiet
frame with the HUD up.

### A.13 `_draw` runs under `--headless`, but a script error there does not fail the process

Verified deliberately in M1 by putting a fault in a `_draw` and running the
smoke check: the dummy display driver **does** call `_draw`, and the error is
reported as `SCRIPT ERROR` on stderr — but the process still exits **0**. So a
headless smoke check must grep stderr; relying on the exit code alone silently
passes exactly the class of bug the check exists to find. The CI step does both.

### A.14 Off-by-one is the default outcome for tick counters

Two counters in the M1 sim were a tick short on the first attempt, in opposite
ways, and both were caught by tests that asserted the exact tick rather than
"eventually". A fuse of N means N ticks only if the detonation check runs
**before** the decrement; a respawn delay of N means N ticks only if the counter
always consumes a whole tick before it is read as expired. Neither is visible in
play — 2.483 s and 2.5 s feel identical — which is precisely why they need
tick-exact tests rather than eyeballing.

### A.15 A scene whose root script fails to parse still instantiates

`PackedScene.instantiate()` on a scene whose script has a **parse error** returns
a perfectly good node with **nothing attached to it**. It does not return `null`
and it does not fail. M2 hit exactly this — a five-argument call to a
four-argument helper in the lobby script — and the scene smoke printed `OK` for
it and exited **0**. The only thing failing the job was the `SCRIPT ERROR` grep
in CI, which was doing all the work while the exit code lied.

Combined with A.13 (a script error in `_draw` does not fail the process either),
the rule is: **a headless check must assert something about what it built, not
merely that building did not throw.** The smoke step now fails any scene whose
root comes back with `get_script() == null`.

### A.16 `queue_redraw()` needs two process frames, not one

A scripted check that wants to *see* something drawn — an overlay, a menu — must
`await get_tree().process_frame` **twice** after calling the code that requests
the redraw. The request is serviced at the end of the frame already in progress,
so a single await can slip past it and the draw never happens. Found by
capturing the smoke run with `--write-movie`: the pause menu was absent from
every captured frame while the reconnect notice, one step later in the same
loop, was present.

Which is the other lesson here: **`--write-movie <file>.png` is a usable
screenshot mechanism for verifying UI**. Godot writes one PNG per rendered frame
with `--fixed-fps`, so pointing it at an existing scripted run costs nothing and
turns "the layout is probably fine" into a picture.
