# Milestone 1 — Build Brief

Everything needed to implement M1 without coming back to ask. Read [the roadmap](roadmap.md) for why M1 exists and [the technical design](technical-design.md) §2–§3a for the reasoning behind the architecture; this document is the executable version, in the same spirit as the [M0 brief](milestone-0-brief.md).

**M1 builds the rule set.** By the end of it the game is playable — two keyboard players, a full two-minute round, bombs, chains, deaths, respawns, and a score — and, more importantly, the rules are **unit-testable headless** and **replayable byte-for-byte**. Presentation is deliberately programmer art: coloured rectangles. Nothing in M1 is about how the game looks.

M0 answered the hardware question (pass, see [m0-pi400.md](measurements/m0-pi400.md)). M1 answers a different one: **is the simulation layer actually as testable and deterministic as the technical design claims?** If it is not, we find out now, while the sim is 1 500 lines instead of 6 000.

---

## 1. Scope

**In scope**

1. **`src/sim/` — the pure simulation layer.** No `Node`, no autoload, no scene tree, no `delta`, no wall clock. `Sim.step(state, inputs) -> Array[SimEvent]`.
2. **Data-driven tuning** — `Balance` and `ArenaDef` as `Resource` classes with `.tres` instances under `data/`.
3. **Arena generation** — seeded, quadrant-mirrored, pillar lattice, crate density, spawn clearances, designated respawn tiles.
4. **Movement** — fixed-point positions, lane snapping, corner assist, grid collision, own-bomb pass-off.
5. **Bombs and blasts** — placement, fuse, plus-shaped blast, hard-block and crate interaction, chain reactions, flame lifetime, flame ownership.
6. **Death, respawn, scoring, clock** — one-hit kills, kill credit, suicide penalty, respawn tile selection, spawn protection, the integer round clock.
7. **Replay record + playback** — a compact binary format, a `ReplaySource`, and a state fingerprint.
8. **A real test suite** over the sim, plus a **golden replay** determinism test, green headless in CI.
9. **`src/view/` — programmer-art rendering** and a playable match scene: arena tilemap, entity rectangles, HUD, round-end panel.
10. **CI: a scene-smoke step**, because M0 taught us that `--import` does not compile scene scripts (Appendix A.1).

**Out of scope — do not build these**

Power-ups and the power-up table, kit loss on death, crate regeneration (all **M3**); the lobby, press-A-to-join UI, pause menu, match/best-of-3 scoring (**M2/M3**); bots (**M5**); real art, audio, particles, telegraphing polish, menus (**M4**).

Two borderline calls, resolved:

- **Crate regeneration is M3, not M1**, even though a bare arena in the back half of a round is exactly what §6.2 of the game design warns about. M1's job is to make the rules correct and testable; regeneration is a balance feature with fiddly exclusion rules and it belongs with the rest of the economy.
- **The round ends and stays ended.** No rematch flow, no best-of-3, no scoreboard screen. The round-end panel says who won and offers a restart key. That is enough to satisfy the exit criteria and not one feature more.

---

## 2. The determinism contract

This is the milestone where the contract stops being aspirational. Every rule below is enforceable by reading a diff, and the golden replay test is what catches violations nobody noticed.

1. **No `delta`, anywhere under `src/sim/`.** The sim advances exactly one tick per `step()` call. `_physics_process` decides *when* to call it; the sim never asks what time it is.
2. **No floats where an integer will do.** Positions are `Vector2i` in sub-tile units (1 tile = `C.UNITS_PER_TILE` = 256). Speeds are integer **units per tick**. Crate density is **permille**, not a float, so the generator never compares floats.
3. **One PRNG, consumed in a fixed order**, owned by `MatchState`. `SimRng` is hand-rolled (xorshift32, masked to 32 bits) rather than `RandomNumberGenerator`, so the sequence is pinned to our source and cannot shift under an engine upgrade.
4. **No iteration over unordered collections.** Players and bombs live in arrays with stable indices. Flames live in flat `PackedInt32Array` / `PackedByteArray` grids indexed by `y * w + x`. There is not a single `Dictionary` iteration in the sim.
5. **No `Node`, no `get_node()`, no autoload reference** under `src/sim/`. The whole layer must construct and run in a `--script` process with no scene tree — which is also why M0's Appendix A.2 (autoloads absent in `--script` mode) does not bite the test suite.
6. **Fixed intra-tick order**, specified in §6 and not to be reordered casually. Most determinism bugs in games of this shape are really ordering bugs.

---

## 3. Data resources

Per technical design §6, every number marked **(tune)** in the game design lives in a `Resource`, not in code.

### 3.1 `Balance` — `data/balance/default.tres`

Stored in the sim's native units, with the design document's human-readable figure in a comment. The quantisation is real and is the reason the resource stores ticks and units:

| Field | Value | Design figure |
|---|---|---|
| `move_speed_units` | 15 | 3.5 t/s → 3.516 t/s |
| `max_speed_units` | 26 | 6.0 t/s cap (M3 uses it) |
| `bomb_fuse_ticks` | 150 | 2.5 s |
| `flame_ticks` | 24 | 0.4 s |
| `start_blast_radius` | 1 | |
| `start_bomb_capacity` | 1 | |
| `round_ticks` | 7200 | 2:00 |
| `respawn_ticks` | 90 | 1.5 s |
| `spawn_protect_ticks` | 120 | 2 s |
| `corner_assist_units` | 77 | 6 px (6 × 256 / 20 = 76.8) |

`Balance.fingerprint()` returns a 32-bit hash of every field. A replay stores it; playback against a different balance is a loud mismatch rather than a mystifying desync.

### 3.2 `ArenaDef` — `data/arenas/default.tres`

Grid size, crate density, spawn tiles, respawn tiles. `25 × 15`, `crate_permille = 700`, the four corner spawns, and **nine designated respawn tiles**: the four corners, the four edge midpoints, and the centre. All nine are chosen so that no coordinate pair is even/even (never a pillar) and the set is symmetric under both mirror axes, so respawning is as fair as the layout.

---

## 4. Sim data model

```
src/sim/
├── sim_rng.gd        SimRng      xorshift32, masked; next_u32/next_below/state
├── balance.gd        Balance     Resource, the tunables above
├── arena_def.gd      ArenaDef    Resource, grid + density + spawn/respawn tiles
├── arena.gd          Arena       tile grid, generation, queries
├── player_state.gd   PlayerState one player's sim state
├── bomb.gd           Bomb        tile, owner, fuse, radius, exploded
├── sim_event.gd      SimEvent    kind + tile + player + other + value
├── match_state.gd    MatchState  everything; fingerprint(); duplicate-free
├── sim.gd            Sim         static step(state, inputs) -> Array[SimEvent]
└── replay.gd         Replay      record/save/load + ReplaySource
```

`Arena.tiles` is a `PackedByteArray` of `Arena.Tile { FLOOR, HARD, CRATE }`, indexed `y * w + x`. Flames are two parallel flat arrays on `MatchState`: `flame_ttl: PackedInt32Array` and `flame_owner: PackedByteArray` (`0xFF` = none). Keeping flames out of an object list is both a determinism win (no iteration order to get wrong) and a Pi win (no allocation per flame tile).

`PlayerState` carries: `pos: Vector2i` (centre, sub-tile units), `facing`, `alive`, `respawn_ticks`, `spawn_protect_ticks`, `score`, `kills`, `deaths`, `bomb_capacity`, `blast_radius`, `speed_units`, `bombs_active`, `bomb_exempt_tile` (the own-bomb pass-off, `(-1,-1)` for none), and `prev_bomb` (for edge detection).

### 4.1 Arena generation

1. Fill `FLOOR`; set the one-tile border to `HARD`; set `HARD` at every interior tile where **both coordinates are even** — the classic lattice, and the reason the interior is 23 × 13 odd-by-odd (game design §4).
2. **Generate one quadrant and mirror it four ways.** For a 25 × 15 grid the quadrant is `x ∈ [1, 12]`, `y ∈ [1, 7]`, and the mirror is `x' = w - 1 - x`, `y' = h - 1 - y`. The centre column (`x = 12`) and centre row (`y = 7`) map onto themselves, so there is no double-write and no seam.
3. Iterate the quadrant in fixed `y`-then-`x` order. For each `FLOOR` tile, draw once from the PRNG and place a crate if `rng.next_below(1000) < crate_permille`. **One draw per eligible tile, always, in the same order** — the number of PRNG calls must not depend on what got placed.
4. Clear spawn clearances: each of the four spawn tiles and its orthogonal neighbours are forced to `FLOOR` (the classic L).
5. Clear every designated respawn tile to `FLOOR`.

Steps 4 and 5 run **after** the draw, not as a filter before it, so clearance geometry cannot shift the PRNG sequence.

---

## 5. Movement

The most feel-sensitive code in the milestone, and the part most likely to be retuned after a playtest. Written to be tunable without being rewritten.

Positions are the player's **centre** in sub-tile units. Tile `(tx, ty)`'s centre is `(tx * 256 + 128, ty * 256 + 128)`. `Sim` reads a cardinal direction from the `InputFrame`; there are no diagonals by construction (M0 §5.1).

**Collision is point-vs-tile with a centre stop.** A player advancing toward a blocked tile stops with their centre **on the centre of the tile they currently occupy**. That is what makes the genre feel right: you come to rest in the middle of the last free square, not halfway into a wall. Because the fastest legal speed (26 units/tick) is an order of magnitude below a tile (256 units), a player can never cross more than one tile boundary per tick, so there is no tunnelling to handle.

Per tick, for each living player, in slot-index order:

1. Read `dir`. If `NONE`, no movement; `facing` is unchanged.
2. Set `facing = dir`. Let `d` be the unit step, `axis` the axis of travel, `perp` the other one.
3. **Corner assist** — if the tile ahead (`cur + d`) is blocked, and the player's `perp` offset from their lane centre is *already leaning* toward one side by at least `128 - corner_assist_units` (i.e. the adjacent lane is within `corner_assist_units` of being entered), and that adjacent lane is both walkable **and** open in the direction of travel, then slide `perp`-wards at full speed this tick and do not advance on `axis`. Next tick the player is in the open lane and moves normally.
4. Otherwise **advance on `axis`** by `speed_units`, clamped so that the centre does not pass the current tile's centre when `cur + d` is blocked. The clamp is **one-directional**: it can stop forward motion but never pushes a player backwards.
5. **Lane snapping** — move the `perp` coordinate toward the current lane centre by up to `speed_units`. On a clear corridor this converges in a couple of ticks, which is what "you always walk down the middle of a corridor" means in practice.
6. Update the own-bomb exemption: if the player's centre tile is no longer `bomb_exempt_tile`, clear it. Pass-off is one-way — step off your own bomb and it becomes solid to you like everyone else.

Why corner assist is written around a **direction change** rather than around running into a wall: with lane snapping active a player is essentially always on a lane centre, so "drifted a few pixels off-lane" barely happens. The case that *does* happen, constantly, is pressing UP while still short of a junction's centre — and the naive implementation answers that by yanking the player back to the previous tile centre and stopping. Step 3 is what turns that into a slide through the corner. Step 4's one-directional clamp is what makes sure it never becomes a yank in the first place.

`corner_assist_units` is marked **(tune)** in the design and this is the parameter a playtest will move.

**Solidity**, in one place (`MatchState.is_blocked_for(tile, player_index)`): `HARD` and `CRATE` always block; a tile holding a bomb blocks **unless** it is that player's `bomb_exempt_tile`; everything else is free. Flames never block.

---

## 6. The tick

Fixed order. Changing it changes the game, and probably breaks the golden replay — which is the point.

```
Sim.step(state, inputs) -> Array[SimEvent]:
  0. if state.finished: return []             # a finished round is inert
  1. state.tick += 1
  2. age flames        (ttl -= 1; clear owner at 0)
  3. for each player in slot order:
       place a bomb if the A edge fired and the loadout allows it
       move (§5)
  4. tick fuses in bomb-array order; every bomb reaching 0 detonates,
     resolving its chain fully before the next bomb is considered
  5. deaths: each living, unprotected player standing on a flame dies
  6. respawns: countdown; on expiry choose a tile and place the player
  7. spawn protection: countdown
  8. round clock: round_ticks_left -= 1; at 0, emit ROUND_ENDED, finished = true
```

**Flames age before blasts are laid** (2 before 4) so a flame created this tick lives its full `flame_ticks` and can kill on the very tick it appears. **Deaths resolve after blasts** (5 after 4) for the same reason. **Bombs are placed before movement** (inside 3) so a bomb lands on the tile the player was standing on when they pressed the button, not the one they were sliding into.

### 6.1 Bomb placement

On the rising edge of `bomb` (tracked per player via `prev_bomb`): the player must be alive, have `bombs_active < bomb_capacity`, and their centre tile must not already hold a bomb. The bomb captures the player's **current** `blast_radius` at drop time — picking up a radius power-up later does not retroactively enlarge a fuse-burning bomb. Every player whose centre is on that tile (normally just the placer) gets `bomb_exempt_tile` set to it, which is the literal reading of "solid to everyone except the player still standing on it". Dropping a bomb **clears spawn protection immediately**, so it cannot be used as an offensive shield (game design §5.3).

### 6.2 Blast and chain resolution

A detonation is a breadth-first walk over a queue of bomb indices, so the chain is deterministic without recursion:

- The origin tile always gets a flame.
- Four rays in fixed order **UP, RIGHT, DOWN, LEFT**, each up to the bomb's captured `radius`. Per step: `HARD` stops the ray with no flame on the block; `CRATE` becomes `FLOOR`, gets a flame, and stops the ray — **exactly one crate per direction**; otherwise the tile gets a flame and the ray continues. A bomb found on a flamed tile is appended to the queue and detonates in the same tick.
- A bomb is only ever queued once and only detonates once.

**Flame ownership, and a contradiction in the design docs.** Game design §5.2 says a flame remembers "which player's bomb produced it, including through chains"; technical design §3 says the owner is "propagated through chain detonations". Those are different rules when B's bomb sets off A's bomb. **Decided: ownership propagates from whoever started the chain.** Set off someone else's bomb and the kills are yours; your own bomb being used against you is not your suicide. This is the standard reading of the genre and the more interesting rule, and the game design doc has been amended to match rather than left ambiguous.

Where two independent blasts light the same tile, **the most recent writer owns it** — the fire you just made is yours — and the tile's `ttl` is refreshed to the longer of the two. Within a single chain this is moot, since every flame in the chain shares one owner.

### 6.3 Death, credit, respawn

A living player with `spawn_protect_ticks == 0` whose **centre tile** carries a flame dies. Kill credit reads the owner off that flame tile (technical design §3a):

| Flame owner | Effect |
|---|---|
| Another player | that player `score += 1`, `kills += 1`; victim `deaths += 1` |
| The victim themselves | victim `score -= 1`, `deaths += 1` |

On death the player's live bombs keep burning and keep their ownership — a bomb outlives its owner, and a dead player's bomb can still score for them. M1 drops no kit (that is M3).

**Respawn tile selection** — from the designated respawn tiles, keep those that are walkable, bomb-free and flame-free; score each by the **Manhattan distance to the nearest living player, live bomb, or flame** and take the highest, breaking ties by tile index so the choice is deterministic. If no designated tile qualifies, fall back to scanning every free interior tile in index order. If nothing at all qualifies (a screen entirely on fire), the countdown simply stays at zero and retries next tick — flames expire, so this cannot deadlock. Respawning grants `spawn_protect_ticks` of invulnerability.

### 6.4 Round end and the winner

`round_ticks_left` is an integer counting down from `round_ticks`. It is the **sole** round-ending condition: no last-player-standing, no overtime, no stalemate detection (game design §3). Highest score wins; an equal top score is a draw and nobody takes the round. `MatchState.winner()` returns the slot index, or `-1` for a draw.

---

## 7. Events

`SimEvent` is a flat value type — `kind`, `tile`, `player`, `other`, `value` — rather than a class hierarchy, because the view switches on it and replays never store it. Kinds in M1: `BOMB_PLACED`, `BOMB_EXPLODED`, `CRATE_DESTROYED`, `FLAME_LIT`, `PLAYER_DIED`, `PLAYER_RESPAWNED`, `ROUND_ENDED`.

Events are the view's and audio's only input besides the state itself. They are **not** part of the determinism contract — the fingerprint covers state, not the event log — but they are emitted in the tick order above, so they are stable in practice.

---

## 8. Replays

A replay is **a seed plus an input log**. 5 bytes per tick for four players; a full two-minute round is about 36 KB, which is what makes "attach the replay to the bug report" realistic.

```
"HGR1"                      4 bytes magic
u32 seed
u32 balance_fingerprint
u16 grid_w, u16 grid_h, u16 crate_permille
u8  player_count
u32 tick_count
tick_count × MAX_PLAYERS bytes    packed InputFrames, slot-major per tick
```

`ReplaySource extends InputSource` is the fourth implementation of the M0 seam and needs no changes anywhere else — the whole point of §5.2 of that brief. Sim ticks are 1-based, so tick *t* reads log row *t − 1*.

`MatchState.fingerprint()` hashes the entire state — tick, clock, every player field, every bomb, the whole tile grid, both flame arrays, and the RNG state — with FNV-1a masked to 32 bits, and returns it as hex. Hand-rolled for the same reason as the PRNG: pinned to our source, not to an engine class.

**The golden replay test** loads `tests/replays/golden_01.hgr`, runs it to completion, and asserts the final fingerprint matches a committed constant. It is generated by `tools/make_golden_replay.gd`, so regenerating it after an intentional rule change is one command and an obvious diff. When it fails unexpectedly, something became non-deterministic — which is exactly the bug class that is otherwise a nightmare to find.

---

## 9. View layer

Programmer art. Rectangles and `Label`s, no assets, no texture beyond the runtime-generated tileset M0 already built.

```
src/view/
├── placeholder_tileset.gd   moved up from src/dev/ — now production code
├── arena_view.gd            TileMapLayer; full sync + per-crate update
├── entity_view.gd           Node2D _draw for flames, bombs, players
└── hud_view.gd              side panels, round clock, round-end panel
```

- **`ArenaView`** redraws the `TileMapLayer` on `sync()` and then only ever touches the single cell a `CRATE_DESTROYED` event names. The arena is never redrawn per frame (technical design §5).
- **`EntityView`** draws everything else in one `_draw` pass, in painter order flames → bombs → players, so the whole entity layer is a handful of draw calls. Bombs pulse faster as the fuse runs down and flames are drawn additively — the cheap half of the telegraphing requirement, at zero GPU cost. **No 2D lights, ever** (technical design §5).
- **`HudView`** fills the 70 px side margins with two player cards each (score, kills/deaths, bombs, radius, respawn countdown) and puts the round clock in the top band, turning red under ten seconds.
- **`MatchScene`** (`src/app/match_scene.*`) owns the `MatchState`, polls `DeviceManager` in `_physics_process`, calls `Sim.step`, feeds the views, records the replay, and shows the round-end panel. It is the only file in M1 that touches both the sim and the scene tree, and it is deliberately thin.

**Interpolation is not in M1.** The sim runs at 60 Hz and so does the display, so entities are drawn at their tick positions. If M4 ever wants render interpolation it goes in the view and the sim never learns about it.

To satisfy the exit criteria without the M2 lobby, `MatchScene` **auto-claims the two keyboard layouts** if no slot is bound when the round starts, so the game is playable straight from launch. Bound gamepads still take precedence; press-A-to-join stays the real mechanism and lands with the lobby in M2.

---

## 10. Tests

M0 shipped a deliberately tiny `--script` harness instead of GUT. **M1 keeps it and grows it** rather than vendoring GUT: the sim layer is pure GDScript with no Nodes, which is precisely the case the small harness handles well, and ~100 files of third-party addon buys us assertion sugar we can write in 40 lines. The design documents' references to GUT have been amended. `TestCase` gains `before_each`, `assert_ne`, `assert_in_range`, and array/vector asserts; `run_tests.gd` gains suite discovery and per-test reporting.

Coverage, at minimum:

| Suite | What it pins |
|---|---|
| `test_input_frame` | the M0 contract (unchanged) |
| `test_sim_rng` | reproducibility from a seed, range bounds, a pinned first-values sequence |
| `test_arena_gen` | border, lattice, mirror symmetry, spawn clearances, respawn tiles clear, same seed → same arena, different seed → different arena |
| `test_movement` | lane snapping, centre stop at a wall, no backward yank, corner assist slides through, corner assist declines a dead end, own-bomb pass-off one-way |
| `test_bombs` | capacity, no double-drop on a tile, radius captured at drop, fuse timing to the tick, spawn protection cleared by dropping |
| `test_blast` | plus shape, radius, stops at `HARD`, destroys exactly one crate per direction, flame lifetime to the tick |
| `test_chains` | chain detonates same tick, ownership propagates from the trigger, a crate shields a bomb behind it, no double-detonation |
| `test_scoring` | kill credit, suicide penalty, death through a chain credits the chain starter, round clock ends the round, winner and draw |
| `test_respawn` | countdown length, tile choice maximises distance, tie-break by index, spawn protection granted, no deadlock under full-arena fire |
| `test_replay` | pack/unpack round-trip, save/load round-trip, **golden replay fingerprint** |

Tests construct `Balance.new()` with short round lengths rather than loading the `.tres`, so a scoring test does not have to simulate 7 200 ticks.

---

## 11. CI

Three changes to the existing workflow:

1. **Linux export is `arm32`**, not `arm64` — the reference Pi runs the 32-bit OS. Artifacts land in `build/linux-arm32/`.
2. **A scene-smoke step.** M0's Appendix A.1 is explicit that `--import` registers class names but does not fully compile scene-attached scripts, so import passing proves nothing about whether a scene loads. Smoke runs the real game headless (`godot --headless --path .` with a `--smoke` user arg), which per Appendix A.3 is the only reliable way to run scenes without exporting, and per A.2 the only way to have autoloads present. It instantiates the match, sandbox and stress scenes, steps physics ticks on each, and quits non-zero on a script error. CI additionally fails if `SCRIPT ERROR` appears on stderr.
3. **The test suite covers the sim**, and is therefore the step that actually has to pass.

CI still cannot say anything about performance. The Pi 400 remains the only source of that number, and M1 appends its own row to [m0-pi400.md](measurements/m0-pi400.md).

---

## 12. Exit criteria

| Check | Pass condition |
|---|---|
| Two keyboard players, full round | A complete 2:00 round plays correctly: bombs, chains, crates, deaths, respawns, a score, and a winner |
| Sim test suite | Green headless, and it genuinely covers blast propagation, chain reactions, and kill credit |
| Golden replay | Replaying a committed log reproduces the exact final state fingerprint |
| Determinism by construction | No `delta`, no float positions, no `Node`, no autoload and no `Dictionary` iteration anywhere under `src/sim/` |
| Scene smoke | Match, sandbox and stress scenes all load and step clean headless |
| Exports | Windows x86_64 and Linux arm32 still build from CI |
| Pi 400 | The match scene holds 60 FPS; the stress scene has not regressed |

---

## 13. Suggested order of work

Ordered so the sim is provable before anything draws it.

1. `SimRng`, `Balance`, `ArenaDef`, the `.tres` instances. Tests for the RNG.
2. `Arena` + generation. Tests for symmetry, lattice, clearances.
3. `PlayerState`, `Bomb`, `SimEvent`, `MatchState` + `fingerprint()`.
4. `Sim.step` — movement only. Movement tests. *(Still nothing on screen.)*
5. Bombs, blasts, chains, ownership. Blast and chain tests.
6. Death, credit, respawn, clock, winner. Scoring and respawn tests.
7. `Replay`, `ReplaySource`, the golden generator and its test.
8. Harness upgrade, then the view layer and `MatchScene`. **First time anything is visible.**
9. Scene smoke + CI.
10. Play a full round on Windows, then on the Pi 400. Append the perf row.

Steps 1–7 are the milestone. Step 8 is what makes it demonstrable, and it is deliberately last: if the rules are wrong, watching squares move around will not tell you, but a failing test will.
