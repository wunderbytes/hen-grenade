# Milestone 1 — Completion Notes

> Status: **code complete and headless-verified; the hands-on play pass is still owed.** The simulation layer, the replay harness, the programmer-art view and the CI scene smoke are all implemented, and 104 tests plus a golden replay are green. What remains is the part no test can do: two people at a keyboard playing a full two-minute round and saying whether it feels right, and a run on the reference Pi 400.

- **Date:** 2026-09-12
- **Brief:** [milestone-1-brief.md](../milestone-1-brief.md)
- **Previous:** [M0 completion notes](m0-completion.md) — M0 passed on hardware on the same date

## Implemented

1. **`src/sim/` — the pure simulation layer.** No `Node`, no autoload, no scene tree, no `delta`, no float positions, no `Dictionary` iteration.
   - `SimRng` — hand-rolled xorshift32, one state advance per draw, seeded warm-up.
   - `SimHash` — hand-rolled FNV-1a/32 behind every fingerprint.
   - `Balance`, `ArenaDef` — `Resource` classes with `.tres` instances under `data/`.
   - `Arena` — flat `PackedByteArray` grid, seeded quadrant-mirrored generation.
   - `PlayerState`, `Bomb`, `SimEvent`, `MatchState` (with `fingerprint()`).
   - `Sim.step(state, inputs) -> Array[SimEvent]` — movement, bombs, blasts, chains, deaths, respawn, clock.
   - `Replay` — record, save/load, `run()` with a sampled trace digest.
2. **`ReplaySource`** (`src/input/`) — the third implementation of the M0 `InputSource` seam, added without touching anything else, exactly as that brief predicted.
3. **`src/view/` — programmer art.** `ArenaView` (tilemap, synced once per round and then per destroyed crate), `EntityView` (flames, bombs, players in one `_draw`), `HudView` (side panels, clock, round-end banner). `PlaceholderTileset` promoted from `src/dev/`.
4. **`MatchScene`** (`src/app/`) — the only file that touches both the sim and the scene tree. Polls, steps, records, draws, saves the replay on round end, restarts on **R**.
5. **Test harness upgrade** — `before_each`, per-test reporting, more assertions, and directory discovery so a new suite cannot be silently forgotten.
6. **CI** — Linux export is now `arm32`; a **scene smoke** step boots the real game headless and fails on `SCRIPT ERROR`.
7. **`tools/make_golden_replay.gd`** — regenerates the committed golden replay, self-checks the round trip before writing, and prints both pinned hashes.

## Verification performed

| Check | Result |
|---|---|
| `--headless --import --quit` | clean |
| Test suite | **10 suites, 104 tests, 0 failures**, exit 0 |
| Golden replay | 1800 ticks, 4 players, reproduces both its end-state fingerprint and its sampled trace digest |
| Scene smoke | match / sandbox / stress all load, step, and draw clean; the match scene plays a **full 7200-tick round** to its end and writes a replay |
| Exports | Windows x86_64 and Linux arm32 both build locally from the rewritten presets |
| Draw calls, quiet frame | **16** |
| Draw calls, worst case (28 radius-6 bombs, arena ablaze) | **9** |

**The suite was mutation-checked, not just run.** Inverting the chain-ownership rule was confirmed to fail `test_chains` and to exit non-zero, so the green run above means something. That check also exposed a real gap and fixed it: a single end-state fingerprint did **not** notice the inverted rule, because by the last tick the fires were out and the score happened to be unaffected. The golden test now also compares a digest sampled every 60 ticks, which does notice.

## Decisions taken during M1

- **Flame ownership through chains propagates from whoever started the chain.** The game design and technical design documents contradicted each other on this; both have been amended. Set off someone else's bomb and the kills are yours, and having your own bomb used against you is not scored as your suicide.
- **The in-house test harness stays; GUT is not vendored.** Confirmed rather than assumed — the sim is pure GDScript with no Nodes, which is the case a small runner handles well. The design documents' references to GUT have been removed.
- **The Linux arm64 export preset is gone.** The reference Pi 400 runs the 32-bit OS, so `arm32` is the only Linux target in the presets, the docs, CI and `tools/deploy-pi.sh`.
- **Corner assist is written around a direction change, not around running into a wall** — with lane snapping active a player is essentially always on a lane centre, so "drifted off-lane" barely happens, while "pressed UP just short of a junction" happens constantly. See the brief §5.

## Fixed along the way

- **`texture_format/etc2_astc` was `false` on the Linux export preset.** This is the export-preset half of the documented `No loader found for resource` trap; the project-settings half was already correct. It has not bitten yet only because nothing in the project is a VRAM-compressed texture — the tileset is generated at runtime. It would have bitten on the first imported `.png` in M4.
- **Two tick-counter off-by-ones** (fuse length, respawn delay), both caught by tests asserting exact ticks. See technical design Appendix A.14.
- **A 44-draw-call HUD**, against a documented budget of 20. Label drop shadows were 28 of those. Appendix A.11.

## Deferred / still owed

- **The hands-on play pass.** Two keyboard players, a full round, on Windows and then on the reference Pi 400. Everything below the keyboard is tested; the keyboard-to-`InputFrame` link and the actual feel are not, and cannot be.
- **The M1 performance row** in [m0-pi400.md](../measurements/m0-pi400.md), which is still waiting on the M0 numbers being transcribed in the first place.
- **Movement feel.** Speed, corner assist reach and lane snapping are all correct per the brief and all marked (tune). Whether they are *good* is a playtest question, and the brief expects `corner_assist_units` to move.
- **Interpolation.** Entities are drawn at their tick positions. Fine at 60 Hz on a 60 Hz display; if it ever matters, it goes in the view and the sim never learns about it.

## Notes for M2

- `DeviceManager.ensure_keyboard_slots()` exists purely so M1 is playable without a lobby. **M2 should delete the call from `MatchScene.start_round()`** and let press-A-to-join own slot assignment.
- `MatchScene` currently owns round setup, the round-end banner and restart. M2's lobby and pause flow should take round lifecycle over and leave `MatchScene` as the thin sim-to-view bridge it is now.
- Scene routing is F1 title, F2 stress, F3 sandbox, F4 match, F5 metrics overlay, R restart.
