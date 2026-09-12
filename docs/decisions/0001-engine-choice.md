# ADR 0001 — Engine choice: Godot 4.7 (GDScript)

- **Status:** Accepted
- **Date:** 2026-09-05

## Context

We are building a Bomberman-style local-multiplayer game that must run on:

- **Windows** (x86_64) — also the primary development machine.
- **Raspberry Pi 400** (BCM2711, VideoCore VI @ 500 MHz, 4 GB), running the **32-bit** Raspberry Pi OS — the "couch console" target, and the exact hardware we design against. The shipped Linux binary is therefore Godot's `arm32` export.

Hard requirements that drive the decision:

1. One codebase, two very different targets, including a **weak, mobile-class GPU** (Broadcom VideoCore VI, OpenGL ES 3.1 via Mesa V3D) — roughly half the graphics performance of a Pi 5.
2. **Four USB gamepads** (Logitech F310 class) working simultaneously, with hot-plug, on both OSes.
3. 60 FPS at 720p on the Pi for a simple 2D tile game.
4. Small team, no engine programmers to spare — time should go into gameplay, not into porting.

## Options considered

| Option | Pi story | Gamepads | 2D tooling | Risk |
|---|---|---|---|---|
| **Godot 4.7 (GDScript)** | Official Linux **arm32 and arm64** export templates; Pi 5 reported running 4.7.x well; Compatibility (GLES3) renderer for export | SDL-backed, `gamecontrollerdb` built in, hot-plug events, per-device indices | Excellent: scenes, TileMapLayer, animation, UI, audio, particles | **Pi 400 GPU headroom — the real risk, see below**; engine is heavier than needed |
| **LÖVE (Lua) 11.5** | Runs great on Pi, `apt install love`, tiny footprint | SDL2 `love.joystick` / gamepad API, very solid | Code-only, no editor; UI/menus hand-rolled | 12.0 still unreleased after years; we'd write a lot of framework ourselves |
| **Python + pygame-ce** | Runs on Pi | SDL2-backed, fine | Code-only | Slowest runtime; Python packaging for two OSes is a chore |
| **C++/SDL3 or Rust/Bevy** | SDL3 fine; Bevy/wgpu wants Vulkan, weak on Pi | Best-in-class (SDL3) / good | Nothing pre-built | Highest effort by a wide margin; Bevy on Pi is a research project |
| **Web (TS + canvas) in a kiosk browser** | Runs, but Gamepad API in a Pi browser adds input latency and a browser dependency | Gamepad API, no rumble reliability | Good | Input latency and fullscreen/kiosk fragility on Pi |

## Decision

**Godot 4.7.x, GDScript, 2D, Compatibility (OpenGL ES 3.0/3.1) renderer for exports.**

Reasons, in priority order:

1. **It is the only option that ships official ARM Linux export templates — arm32 *and* arm64 — alongside Windows x86_64 from a single project.** One export dialog, two artifacts, no cross-compilation toolchain of our own. We ship the `arm32` one, because the reference Pi 400 runs the 32-bit Raspberry Pi OS.
2. **Controller support is the feature we cannot afford to get wrong**, and Godot wraps SDL's gamepad layer including the community mapping database, device hot-plug signals (`Input.joy_connection_changed`), and stable per-device IDs. Everything we need for "press A to join" lobbies exists out of the box — including treating the Pi 400's built-in keyboard as just another joinable player slot, which matters because the machine only has three USB ports.
3. **A tile-grid 2D game rendered at 640 × 360 should sit well below the Pi 400's ceiling in the Compatibility renderer** — but this is the weakest leg of the decision and it is worth being precise about why. The positive reports of Godot 4.7 running well on Raspberry Pi hardware are **Pi 5 reports, and they do not transfer**: the Pi 400 has a VideoCore VI at 500 MHz against the Pi 5's VideoCore VII at 910 MHz, so we are designing for roughly half the GPU that evidence was gathered on. Meanwhile the public reports from Pi 4-family boards (same GPU as ours) include a simple Godot 4 tilemap platformer at 2–5 FPS; in that case the dominant cost was `PointLight2D`, and removing the 2D lights alone took it to 20 FPS.

   So the conclusion we draw is not "Godot is fine on a Pi 400" — we do not actually know that yet — it is "Godot on a Pi 400 should be fine *if we respect a specific, narrow budget*". That budget is written down as hard constraints in the technical design (no 2D lights at all, 640 × 360 internal resolution, output capped at 1080p, Compatibility renderer, capped draw calls) and it is verified against a worst-case scene on real hardware in Milestone 0, before any gameplay is written.
4. **The editor pays for itself** on the parts that are boring to hand-roll: menus, HUD layout, sprite animation, audio buses, input remapping UI, localization if we ever want it.
5. **Escape hatch exists**: performance-critical code can move to C# or GDExtension later without leaving the project. We do not expect to need it.

Notes attached to the decision:

- Pin the exact patch version (**4.7.2-stable**, released 2026-08-18) in `.godot-version` and CI. Do not float.
- **The editor never has to run on the Pi 400.** Develop and export on Windows/desktop Linux; the Pi only ever receives an exported arm32 binary plus `.pck`. This matters more with a Pi 400 than it would with a Pi 5 — the editor on 4 GB and a VideoCore VI would be a miserable way to work, and we never have to find out.
- Use the **Compatibility** renderer for the shipped build. Vulkan on VideoCore is immature and Forward+ falls back to Mobile on this GPU anyway. (If in-editor performance on an ARM dev box is ever a problem, Mobile is better *there* — but ship Compatibility.)
- Enable both `Import S3TC BPTC` and `Import ETC2 ASTC` in project rendering settings so exported textures load on both desktop GL and GLES targets. This is a known footgun when exporting to Pi.
- Godot's own physics engine is **not** used for gameplay (see `docs/technical-design.md`); we run a custom deterministic grid simulation. This decision is about tooling, platform reach, and input — not about using the engine's simulation.

## Consequences

- GDScript is dynamically typed; we mitigate with `@export`ed typed fields, static typing hints everywhere (`func f(x: int) -> void`), and unit tests on the simulation layer (GUT, runnable headless in CI).
- Godot's binary `.tscn`/`.tres` churn can make diffs noisy; we keep scenes text-format (default) and keep tuning data in small `.tres` resources so balance changes are reviewable.
- We accept a ~70 MB export template dependency and a ~40 MB shipped binary. Irrelevant for our distribution model.

## Revisit if

- **A Pi 400 cannot hold 60 FPS at 720p in the Milestone 0 stress scene**, after the budget in the technical design has been applied → reconsider LÖVE, which is dramatically lighter on this hardware. Telling users to buy a Pi 500 is *not* an acceptable resolution: the Pi 400 is the stated target.
- We decide the game must run in a browser → revisit (Godot's web export exists but is a poor fit for gamepad-heavy couch play).
