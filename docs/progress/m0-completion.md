# Milestone 0 — Completion Notes

> Status: **code complete; hardware measurement deferred.** Every M0 deliverable that does not require the reference Pi 400 is implemented and headless-verified. The remaining items (the actual frame-time measurement and the four-controller input pass) are hardware-gated and documented in [m0-pi400.md](measurements/m0-pi400.md).

- **Date:** 2026-09-05
- **Implementer:** agent on Windows 11, Godot 4.7.2 editor (project pins `4.7.2-stable`; see [ADR 0001](decisions/0001-engine-choice.md))
- **Brief:** [milestone-0-brief.md](milestone-0-brief.md)

## Implemented (all in-scope M0 deliverables)

1. **Project skeleton** — `.godot-version` (`4.7.2-stable`), `.gitignore`, `project.godot` (every required setting: `viewport` stretch, integer scale, `gl_compatibility`, both VRAM-compression flags, `physics_jitter_fix=0.0`, 60 Hz tick), `icon.svg`, `src/app/constants.gd` (`C.*`), empty milestone dirs with `.gitkeep`.
2. **Metrics overlay** (`src/app/metrics_overlay.*`) — FPS, frame ms, **rolling p99 over 600 frames**, draw calls, objects, video mem, static mem.
3. **Stress scene** (`src/dev/stress.*`) — full 25×15 grid with every legal interior tile a crate (~233, more pessimistic than the brief's ~160), 4 squares on deterministic Lissajous paths, 32 additive-blended explosion sprites with overdraw on a 2 s loop, 12-crate regen wave every 5 s, 2 `CPUParticles2D` bursts, full HUD mock updating every frame, bisect toggles (V/P/E/H/R). Kept permanently as the regression benchmark.
4. **Input layer** (production code):
   - `InputFrame` — one-byte pack/unpack, four cardinal directions only.
   - `InputSource` → `GamepadSource` (polls its own device index, stick hysteresis 0.5/0.35, D-pad priority) and `KeyboardSource` (WASD + Arrows layouts).
   - `DeviceManager` autoload — discovery, hot-plug via `joy_connection_changed`, press-A-to-join, GUID-first reconnect, identical-pad disambiguation falling back to press-to-claim, keyboard as joinable slots.
   - `PlayerSlot`.
5. **Sandbox** (`src/dev/sandbox.*`) — real 25×15 `TileMapLayer` with pillar lattice, four coloured 16×16 squares driven by bound slots, wall collision, per-slot device labels; F2 → stress, F1 → title.
6. **Main** (`src/app/main.*`) — bootstrap/router (auto-advances to sandbox after 1.2 s; F1 sandbox, F2 stress).
7. **Exports & deploy** — `export_presets.cfg` (Windows x86_64, Linux arm64), `tools/deploy-pi.sh` (rsync + `--rendering-driver opengl3` launch).
8. **CI** (`.github/workflows/ci.yml`) — reads `.godot-version`, caches Godot by version, `--headless --import`, runs the test suite on every push, exports both artifacts on tags.
9. **Tests** — minimal self-contained headless harness (`tests/run_tests.gd` via `--script`, `tests/test_case.gd`, `tests/unit/test_input_frame.gd`) pinning the `InputFrame` contract.
10. **Measurement report** — `docs/measurements/m0-pi400.md` with the full protocol and exit-criteria table, ready to fill in on the Pi 400.

## Verification performed

- `godot --headless --import --quit` → **clean** (all scripts compile, all scenes/resources load).
- Test suite (`--script res://tests/run_tests.gd`) → `1 suite(s), 0 failure(s)`, exit 0.
- Throwaway `SceneTree` probe ran the stress scene for 120 frames → **0 runtime errors** (validated `TileMapLayer`, `ImageTexture`, `CPUParticles2D`, `Sprite2D`, HUD, regen wave, explosion updates). The probe also surfaced real bugs the import step missed (see [technical-design.md](technical-design.md) Appendix A.1, A.5, A.7), all fixed.

## Deviations from the brief

- **Test harness:** a tiny self-contained `--script` runner is used instead of GUT. The brief explicitly permits this ("M0 has almost nothing to test; add a trivial passing test so the harness itself is proven working"). GUT should replace it in M1 when the simulation layer needs real coverage.
- **`.uid` files are committed.** Godot 4.4+ writes a `<script>.uid` beside every GDScript; these are stable resource identifiers and are part of the repo. The brief's `.gitignore` list predates this and does not mention them. See [technical-design.md](technical-design.md) Appendix A.9.

## Deferred (require physical hardware)

These are the hardware-gated M0 exit criteria and cannot be completed without the reference Pi 400 + four F310s:

- The 720p / 1080p / 4K frame-time measurement on the Pi 400 (the actual go/no-go answer — the whole point of M0).
- The four-F310s-via-powered-hub, three-pads-plus-built-in-keyboard, hot-plug, and identical-GUID disambiguation hardware pass.
- Running the exported arm64 binary on the Pi (verifies no `No loader found for resource` errors).

Everything needed to *produce* those answers is in place; only the physical run remains.
