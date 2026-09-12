# Milestone 0 — Build Brief

Everything needed to implement M0 without coming back to ask. Read [the roadmap](roadmap.md) for why M0 exists and [the technical design](technical-design.md) for the reasoning behind the constraints; this document is the executable version.

**M0 answers one question: can a Raspberry Pi 400 run this game at 60 FPS in Godot?** Every deliverable below either produces that answer or builds the skeleton we keep afterwards. If the answer turns out to be no, we change engine (see [ADR 0001](decisions/0001-engine-choice.md)) and almost nothing here is wasted, because the layout, conventions, and input model survive a port.

---

## 1. Scope

**In scope**

1. Godot project skeleton with pinned engine version, repo layout, `.gitignore`, and project settings.
2. A **sandbox scene**: the real 25 × 15 grid at the real resolution, four coloured squares driven by four real input devices.
3. A **stress scene**: a deliberate, repeatable worst case for measurement.
4. A **metrics overlay** good enough to make decisions from.
5. The **input layer** — device discovery, slot binding, hot-plug, keyboard slots. This is the one subsystem built for keeps in M0.
6. **Exports** for Windows x86_64 and Linux arm32, plus a deploy script for the Pi.
7. **CI** that runs headless and builds both artifacts.
8. A **written measurement report** committed to the repo.

**Out of scope — do not build these**

Bombs, blasts, crates as gameplay, power-ups, respawn, scoring, the round clock, menus, the lobby UI, audio, bots, and art. Movement in the sandbox is "move a square around the grid" and nothing more; it does not need lane snapping or corner assist. Resist the urge to start M1 early — a half-built simulation makes the performance number harder to interpret, which defeats the point of the milestone.

---

## 2. Environment

| Thing | Value |
|---|---|
| Engine | **Godot 4.7.2-stable**, standard (non-.NET) build |
| Language | GDScript, statically typed |
| Dev OS | Windows 11 x86_64 |
| Target | Raspberry Pi 400, Raspberry Pi OS **32-bit (armhf)** → Godot `arm32` export |
| Test hardware | 1 × Pi 400, 4 × Logitech F310, 1 × powered USB hub, micro-HDMI cable, a TV or monitor |

Pin the version in a `.godot-version` file at the repo root containing exactly `4.7.2-stable`. CI reads this file rather than hardcoding a version in the workflow, so upgrading is a one-line change.

---

## 3. Project settings

These are the settings the whole project depends on. Set them in the editor, then verify the resulting `project.godot`. Property paths are stable across Godot 4.x but confirm each one exists rather than pasting blindly.

```ini
[application]
config/name="Hen Grenade"
run/main_scene="res://src/app/main.tscn"
run/low_processor_mode=false
run/max_fps=0                      ; uncapped; vsync does the limiting

[display]
window/size/viewport_width=640
window/size/viewport_height=360
window/size/window_width_override=1280
window/size/window_height_override=720
window/size/resizable=true
window/stretch/mode="viewport"     ; NOT canvas_items - see technical design §5
window/stretch/aspect="keep"
window/stretch/scale_mode="integer"
window/vsync/vsync_mode=1          ; enabled

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/canvas_textures/default_texture_filter=0        ; nearest
textures/vram_compression/import_s3tc_bptc=true
textures/vram_compression/import_etc2_astc=true
2d/snap/snap_2d_transforms_to_pixel=true
2d/snap/snap_2d_vertices_to_pixel=true
anti_aliasing/quality/msaa_2d=0

[physics]
common/physics_ticks_per_second=60
common/physics_jitter_fix=0.0      ; must be 0 for a deterministic fixed step
common/max_physics_steps_per_frame=4
```

Notes on the non-obvious ones:

- **`stretch/mode="viewport"`** is the single most consequential setting in the file. See the technical design for why `canvas_items` would forfeit the entire Pi performance argument.
- **`physics_jitter_fix=0.0`** — the default (0.5) lets Godot stretch physics steps to smooth rendering, which introduces variability into a loop that must be exactly 1/60 s. Turn it off now, before any simulation code exists.
- **`max_physics_steps_per_frame=4`** bounds the catch-up spiral if a frame runs long: the game slows down rather than freezing.
- **Both VRAM compression flags on** — without them, ARM builds fail at load with `No loader found for resource`. This is the known Pi export trap; M0 is where we prove we have avoided it. Note the matching *export-preset* half of the trap: the Linux arm32 preset needs `texture_format/etc2_astc=true`, which Godot does not default to.

---

## 4. Constants

Put these in `src/app/constants.gd` as a single source of truth. Nothing should hardcode a magic number that exists here.

```gdscript
class_name C

# Grid
const GRID_W: int = 25
const GRID_H: int = 15
const TILE_PX: int = 20

# Viewport
const VIEW_W: int = 640
const VIEW_H: int = 360
const ARENA_PX_W: int = GRID_W * TILE_PX          # 500
const ARENA_PX_H: int = GRID_H * TILE_PX          # 300
const ARENA_ORIGIN := Vector2i(70, 30)            # centred in the viewport
const HUD_PANEL_W: int = 70                       # each side margin

# Simulation
const TICK_HZ: int = 60
const UNITS_PER_TILE: int = 256                   # fixed-point sub-tile units
const MAX_PLAYERS: int = 4
```

**Fixed-point positions.** Positions are integers in units where one tile is 256. Speeds must therefore be expressed as **integer units per tick**, not tiles per second: the design's 3.5 tiles/s becomes `3.5 * 256 / 60 ≈ 14.93`, which quantises to **15 units/tick (3.516 tiles/s)**. That quantisation is fine, but it means the balance resource stores units-per-tick and the design doc's tiles-per-second figures are the human-readable form. Establish this in M0 even though M0 has no real movement rules yet, because retrofitting fixed-point later is miserable.

---

## 5. Skeleton architecture

M0 creates the directory structure from the technical design and populates only the parts it needs. Everything else stays an empty directory with a `.gitkeep`.

```
src/
├── app/
│   ├── main.tscn / main.gd        # bootstrap, scene routing
│   ├── constants.gd
│   └── metrics_overlay.tscn/.gd
├── input/
│   ├── input_frame.gd             # the value type
│   ├── input_source.gd            # abstract: poll(tick) -> InputFrame
│   ├── gamepad_source.gd
│   ├── keyboard_source.gd
│   ├── device_manager.gd          # autoload; discovery, hot-plug, binding
│   └── player_slot.gd
├── sim/        (.gitkeep)         # M1
├── bots/       (.gitkeep)         # M5
├── view/       (.gitkeep)         # M4
├── ui/         (.gitkeep)         # M2
├── audio/      (.gitkeep)         # M4
└── dev/
    ├── sandbox.tscn/.gd           # throwaway
    └── stress.tscn/.gd            # throwaway, but keep it forever as a benchmark
```

The `dev/` scenes are allowed to be scrappy. Everything in `input/` and `app/` is production code and should be written as such.

### 5.1 `InputFrame` — the contract everything else hangs off

One player's intent for one tick. Deliberately tiny and packable, because this is what replay logs are made of and what bots will emit in M5.

```gdscript
class_name InputFrame

enum Dir { NONE = 0, UP = 1, RIGHT = 2, DOWN = 3, LEFT = 4 }

var dir: Dir = Dir.NONE
var bomb: bool = false      # A
var action: bool = false    # B - detonate / toss

# Packs into one byte: bits 0-2 direction, bit 3 bomb, bit 4 action.
func pack() -> int: ...
static func unpack(b: int) -> InputFrame: ...
```

One byte per player per tick means a full two-minute four-player round logs to about 29 KB. That is what makes "attach the replay to the bug report" practical.

**Only four directions, never diagonals.** The game is grid-based; resolving to a cardinal direction at the input boundary means no downstream code ever has to think about it.

### 5.2 `InputSource` — one interface, four eventual implementations

```gdscript
class_name InputSource

func poll(tick: int) -> InputFrame:
    push_error("abstract")
    return InputFrame.new()
```

M0 implements `GamepadSource` and `KeyboardSource`. M5 adds `BotSource` and M1's replay harness adds `ReplaySource`, both without touching anything else. This is the seam that makes bots un-cheatable and replays free, so get it right now.

### 5.3 Read devices directly — do not use the `InputMap` for gameplay

This is the part of Godot local multiplayer that most projects get wrong, so it is worth being explicit.

Godot's `InputMap` actions aggregate across all connected devices: if two pads are plugged in, `Input.is_action_pressed("move_left")` is true when *either* player pushes left. Working around it with four parallel action sets (`p1_left`, `p2_left`, …) means 24 actions, a device-index-to-action-set mapping that must be rebuilt on every hot-plug, and a remapping UI that has to rewrite the `InputMap` at runtime. It gets ugly fast.

Instead, `GamepadSource` polls its own device index directly:

```gdscript
Input.is_joy_button_pressed(device_id, JOY_BUTTON_A)
Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X)
```

Reserve the `InputMap` for menu navigation only, where "any device can press this" is exactly the behaviour you want.

Stick-to-direction conversion lives here: magnitude threshold **0.5** to engage, **0.35** to release (hysteresis), D-pad takes priority over the stick when both are active.

### 5.4 `DeviceManager` (autoload)

Owns everything about physical devices so nothing else has to.

- Enumerate with `Input.get_connected_joypads()`; identify with `Input.get_joy_guid(id)` and `Input.get_joy_name(id)`.
- Subscribe to `Input.joy_connection_changed(device, connected)` for hot-plug.
- Bind a device to a player slot on first A press; one device, one slot.
- On disconnect, emit a signal the game reacts to by pausing; on reconnect, **match by GUID first**, falling back to press-to-claim. Device *indices* are not stable across replug — the GUID is what you key on.
- Expose the built-in keyboard as one or two joinable slots, indistinguishable to callers from a pad. On a Pi 400 this is a real player, not a debug affordance.

Two F310s of the same model report the same GUID. Disambiguate by pairing GUID with the device index that was bound, and when two candidates match, fall back to press-to-claim. M0 must test this specific case — four identical pads is our exact use case.

### 5.5 The fixed-step loop

Drive everything from `_physics_process`, which Godot already runs at exactly 60 Hz given the settings above.

```gdscript
func _physics_process(_delta: float) -> void:
    tick += 1
    var frames: Array[InputFrame] = device_manager.poll_all(tick)
    # M1: sim.step(state, frames)
    # M0: move the coloured squares
```

**Never read `_delta` inside anything that will become simulation code.** If a frame runs long and Godot executes two physics steps, both receive the same polled input — which is correct and stays deterministic, because replays log what was fed to the sim rather than what the hardware did.

---

## 6. The two scenes

### 6.1 Sandbox (`src/dev/sandbox.tscn`)

The "is anything alive" scene. A 25 × 15 `TileMapLayer` at 20 px with a placeholder tileset (three colours: floor, hard block, crate), the classic pillar lattice at even/even interior coordinates, and up to four coloured 16 × 16 squares moving freely on the grid, one per bound input slot. Collide with walls, nothing else. Show which device drives which square.

### 6.2 Stress scene (`src/dev/stress.tscn`)

**This is the deliverable that decides the project**, so it must be repeatable, deterministic, and pessimistic. Not a hello-world. Composition:

- Full 25 × 15 grid with every legal interior tile occupied by a crate sprite (~160 crates) — worst-case tilemap draw.
- Four squares moving on fixed scripted paths, so runs are comparable.
- **32 simultaneous explosion sprites** with additive blending and alpha overdraw, on a 2-second loop. Overdraw is what kills tile-based GPUs, so overshoot the real game's worst case rather than matching it.
- **A crate-regeneration wave** of 12 crates animating in, every 5 seconds, forcing tilemap re-draws mid-measurement.
- Two `CPUParticles2D` bursts at the design's intended cap.
- A full HUD mock in the side panels: text, numbers, icons updating every frame.

Toggles bound to keys, because you want to bisect the cost, not just read a single number: vsync on/off (`DisplayServer.window_set_vsync_mode`), particles on/off, explosion sprites on/off, HUD on/off, output resolution cycling 720p → 1080p → 4K.

Keep this scene in the repo permanently. It becomes the regression benchmark for every later milestone.

### 6.3 Metrics overlay

```
FPS 60.0   frame 8.4 ms   p99 11.2 ms
draw calls 14   objects 412
video mem 24 MB   static mem 61 MB
```

Read via `Performance.get_monitor()`: `TIME_FPS`, `TIME_PROCESS`, `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`, `RENDER_VIDEO_MEM_USED`, `MEMORY_STATIC`. Track a rolling p99 of frame time over the last 600 frames — the average will read 60 FPS while the game visibly hitches, and the p99 is what tells you the truth.

---

## 7. Measurement protocol

Do it the same way every time or the numbers are not comparable.

1. Pi 400, mains power, wired display, nothing else running, desktop at the resolution under test.
2. Launch the exported binary (**never** a debug build or the editor).
3. Stress scene, **vsync off**, 60-second run, record average / p99 frame time and draw calls. Vsync off is the point: with it on everything reads 60 FPS and you cannot see whether you have 3 ms of headroom or 0.1 ms.
4. Repeat at 720p, 1080p and 4K output.
5. Repeat with vsync on to confirm a stable, hitch-free 60.
6. Record CPU temperature at start and end. The Pi 400 should not throttle, and this is where we verify that rather than assume it.

Write results to `docs/measurements/m0-pi400.md`: date, OS version, Godot version, commit hash, and the table. Commit it. Every later milestone re-runs this scene and appends a row, so performance regressions are visible as they happen instead of at the end.

### Exit criteria

| Check | Pass condition |
|---|---|
| Stress scene, 720p, vsync off, Pi 400 | **p99 frame time ≤ 16.6 ms** (i.e. real headroom at 60 FPS) |
| Stress scene, 720p, vsync on, Pi 400 | Steady 60 FPS, no visible hitching over 60 s |
| Draw calls | ≤ 20 |
| Four F310s on the Pi via powered hub | All four squares move independently |
| Three pads + built-in keyboard on the Pi | Four players, no hub |
| Hot-plug | Unplug and replug a bound pad; it rebinds to the same slot |
| Four identical pads | Correctly disambiguated despite matching GUIDs |
| Exports | Windows x86_64 and Linux arm32 both run from CI artifacts |
| arm32 texture loading | No `No loader found for resource` errors |

**If the frame-time criterion fails**, stop and report before writing any gameplay. Bisect with the scene toggles first — if a single feature (particles, overdraw, HUD text) dominates, the budget may just need tightening. If the baseline itself is too slow, that is the ADR 0001 trigger and the answer is LÖVE, not optimisation heroics.

---

## 8. Export and deployment

Commit `export_presets.cfg` with two presets:

| Preset | Platform | Arch | Output |
|---|---|---|---|
| `Windows Desktop` | Windows Desktop | x86_64 | `build/windows/HenGrenade.exe` |
| `Linux arm32` | Linux | arm32 | `build/linux-arm32/HenGrenade.arm32` |

Export templates for 4.7.2 must be installed; the official `.tpz` includes Linux arm32, so no cross-compilation toolchain is needed.

`tools/deploy-pi.sh` — rsync the arm32 binary and `.pck` to the Pi, `chmod +x`, and optionally launch. Launch with `--rendering-driver opengl3` explicitly during M0 so there is no ambiguity about which renderer produced a number.

---

## 9. CI

GitHub Actions, one workflow.

**On every push:** read `.godot-version`, fetch that Godot headless binary and export templates, run `godot --headless --import` (required before any export — without it, resource imports are missing and the export silently produces a broken build), then run the GUT test suite. M0 has almost nothing to test; add a trivial passing test so the harness itself is proven working, because debugging CI later while also debugging real test failures is no fun.

**On tags:** additionally export both presets and attach the artifacts to the release.

Cache the Godot binary and export templates by version — they are ~120 MB and re-downloading them on every push wastes minutes.

CI cannot validate performance. It proves the project builds, imports, exports for both targets, and passes tests. The performance answer only ever comes from the physical Pi 400.

---

## 10. Conventions

- **Static typing everywhere.** `func f(x: int) -> void`, typed members, typed arrays. GDScript is dynamically typed by default; the discipline is ours to impose, and the simulation layer in M1 depends on it.
- `snake_case` files and functions, `PascalCase` classes via `class_name`, `SCREAMING_CASE` constants.
- No `get_node()` string paths in anything under `src/sim` or `src/input`. Those layers must stay runnable headless with no scene tree.
- Scenes stay in text format (Godot's default) so diffs are reviewable.
- `.gitignore`: `.godot/`, `build/`, `*.tmp`. Do **not** ignore `export_presets.cfg` — it is part of the build definition.
- Commit messages reference the milestone: `M0: add device manager hot-plug handling`.

---

## 11. Suggested order of work

Ordered so that the risky, project-defining answers arrive as early as possible.

1. Repo skeleton, `.godot-version`, `.gitignore`, project settings, constants. *(Nothing runs yet.)*
2. Metrics overlay. Build it first — you want measurements from the very first thing you put on screen.
3. Stress scene with placeholder rectangles. **Export to arm32 and run it on the Pi 400 now.** This is the moment of truth and there is no reason to delay it behind input work.
4. Run the full measurement protocol, write `docs/measurements/m0-pi400.md`. **Decision point:** continue, or trigger the ADR.
5. `InputFrame`, `InputSource`, `GamepadSource`, `KeyboardSource`.
6. `DeviceManager` with hot-plug and GUID binding.
7. Sandbox scene wiring input to four squares.
8. Hardware pass: four pads via hub, three pads plus keyboard, hot-plug, identical-GUID disambiguation.
9. Export presets, deploy script.
10. CI workflow.
11. Re-run measurements on the final build and update the report.

Steps 1–4 are the milestone's real purpose. If step 4 fails, steps 5–11 are still worth finishing — the input layer and the measurement protocol carry over to whatever engine we choose instead.
