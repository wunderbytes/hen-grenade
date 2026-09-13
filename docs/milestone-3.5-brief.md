# Milestone 3.5 — Build Brief

Everything needed to implement the **Hen Grenade** game mode without coming back to ask. Read [the roadmap](roadmap.md) for why this sits between M3 and M4, [game design §7](game-design.md) for the mode it builds, and [technical design §3a and §6](technical-design.md) for the determinism and tuning rules it has to obey. Same spirit as the [M0](milestone-0-brief.md)–[M3](milestone-3-brief.md) briefs.

**M3.5 is a rules milestone, not a presentation milestone.** It adds a second way to play on top of a sim that already knows deathmatch, and it has to leave that deathmatch untouched: existing unit tests stay green unmodified, and the committed golden *state* fingerprints and traces must not move. M4 is still where the game gets a face. Programmer art is enough to tell the Hen from everyone else.

The working title of the project and the name of this mode are the same on purpose. Deathmatch remains the default you get if nobody touches the lobby control. Hen Grenade is the namesake: one token, one hunted player, five minutes, most time-as-Hen wins.

Unlike M2, **M3.5 touches `src/sim/`**, so the determinism contract is in play. Unlike M3, the deathmatch rule set itself does not change. If `test_chains` or `golden_01`'s state hash goes red, the change is wrong until proven otherwise.

---

## 1. Scope

**In scope**

1. **A `GameMode` resource** the simulation sees — identity, round length, crate-density scale, crate-cap override, Hen speed, scoring rule — fingerprinted into the replay.
2. **Lobby mode select** — two modes, cycled from any pad, shown before START. Deathmatch is the default.
3. **Hen Grenade rules in the sim** — half crate density, 5:00 clock, one Hen token, becoming / dying as the Hen, time-as-Hen scoring.
4. **Views and HUD** that make the Hen, the token, and the running totals readable in programmer art.
5. **Match flow for a single 5:00 round** — no best-of-3 in this mode; the scoreboard then the winner screen.
6. **Tests** for every Hen rule, plus a golden replay that actually collects the token. Deathmatch goldens keep their state hashes.

**Out of scope — do not build these**

Art, audio, animation, the telegraphing pass, an options screen (**M4**); real bots that hunt the Hen (**M5** — the placeholder still wanders); a third mode, team play, health bars, or a shrinking arena. Do not introduce an HP system to honour "the Hen has 1 health": everyone already dies in one hit.

Four borderline calls, resolved:

- **Hen Grenade is one 5:00 round, not a best-of-3 of five-minute rounds.** The user-facing sentence is "one game lasts 5 minutes." Three of those plus scoreboards is a quarter of an hour, which fights the couch-first pillar. `MatchRules` for this mode is first-to-1, `max_rounds` 1. Rematch from the winner screen starts a fresh 5:00 with the same roster. Deathmatch keeps best-of-3.
- **The token is not a `Powerup.Kind`.** Putting it in the drop table means a crate can spawn a second Hen, or a zero-weight kind that every crate still has to know about. It is a unique piece of match state (`hen_slot` + `hen_token_tile`), collected like a pickup, never rolled as a drop, **never destroyed by a blast**. A mode that can lose its only objective to a stray flame is a mode that stalls.
- **No hit-point system.** "The Hen has 1 health" is the same one-hit death everyone already has. The sentence is here so nobody adds a health bar "for the Hen" and then has to explain why hunters have one too.
- **Deathmatch `MatchState.create()` spends no extra PRNG draws.** Token placement is a Hen-mode-only draw, after generation. If deathmatch create() also draws "just in case", every committed golden state hash moves and the milestone has failed its first job.

---

## 2. What a Hen Grenade round is

Two to four players, same arena, same bombs, same economy. The differences, and only these:

| | Deathmatch (M1–M3) | Hen Grenade |
|---|---|---|
| Clock | 2:00 | **5:00** |
| Crates at generation | arena `crate_permille` (currently 600) | **half** that permille |
| Objective | most kill-score | **most seconds spent as the Hen** |
| Match | best of 3 | **one round** |
| Unique object | none | one **Hen token** |

### 2.1 The token and the Hen

At round start, after the arena is generated and the players are standing on their spawn tiles, **one Hen token** is placed on a random empty floor cell (see §4.2). Nobody is the Hen yet.

Walking onto the token **collects it**: that player becomes the Hen. There is never more than one Hen. The token leaves the floor.

The Hen is the hunted player:

- **Cannot place a bomb.** A is ignored. A `BOMB_SPAM` curse still *attempts* a placement every tick and still fails.
- **Cannot Toss or Remote.** B is ignored. Kick still works if they have it — shoving a bomb out of a corridor is the only self-defence that is not running, and it is not "placing a bomb".
- **Speed is a fixed override**, `hen_speed_units`, default **8** (half of the quantised 15-unit base, 7.5 rounded up). Same shape as the FAST curse: an effective value, never a write to `speed_units` / `speed_steps`. A FAST curse does not make the Hen fast; the Hen override wins. REVERSED still applies.
- **Dies in one hit**, like everyone else. No extra health, no extra spawn protection from collecting the token. Existing spawn protection, if any, still runs.

While they are the living Hen, the simulation counts ticks. Those ticks are the round score.

### 2.2 When the Hen dies

Death is the normal death path, with one insertion **before kit loss**:

1. The Hen token is dropped (see §4.4).
2. `hen_slot` clears. Time-as-Hen stops on this tick — the death tick does not count.
3. Kit loss, scatter, respawn countdown proceed exactly as in deathmatch.
4. The player respawns as a **normal hunter**, not as the Hen. They can collect the token again like anyone else.

Kill credit is unchanged (killer `+1` / suicide `−1`, deaths tally). It is flavour on the scoreboard. **It does not decide the round.**

### 2.3 Winning

At 0:00 the unique highest `hen_ticks` wins. An equal top total is a draw, same as deathmatch. Display is integer seconds (`hen_ticks / 60`); comparison is in ticks, so a 59-tick lead is a win even if both cards show the same second.

A player who never touched the token has 0. That is a legal outcome, including "nobody ever collected it, everyone is on 0, the round is a draw".

---

## 3. `GameMode` as data

A new `Resource` at `src/sim/game_mode.gd`, two files:

- `data/balance/modes/deathmatch.tres` — the default, what F4 and the tests already play.
- `data/balance/modes/hen.tres` — this milestone.

| Field | Deathmatch | Hen | Why it is on the mode, not `Balance` |
|---|---|---|---|
| `id` | `DEATHMATCH` | `HEN` | what the rules branch on |
| `display_name` | `"DEATHMATCH"` | `"HEN GRENADE"` | lobby chip, HUD |
| `round_ticks` | `0` (inherit `Balance.round_ticks`) | `18000` (5:00) | a 5:00 deathmatch is not a thing we want a designer to do by editing the shared fuse file |
| `crate_scale_permille` | `1000` | `500` | half the *current* arena density, so retuning the arena retunes both modes |
| `crate_cap_permille` | `0` (inherit `Balance`) | `250` (tune) | see §4.1 — the deathmatch cap of 450 is above a half-density start, so inheriting it would grow the maze back |
| `hen_speed_units` | unused | `8` | 0.5 × base 15, quantised |
| `scoring` | `KILLS` | `HEN_TICKS` | what `MatchState.winner()` reads |
| `match_rules_path` | `data/balance/match.tres` | `data/balance/match_hen.tres` | first-to-1 vs first-to-2 lives *above* the sim, same reason `MatchRules` is not in `Balance` |

`round_ticks = 0` and `crate_cap_permille = 0` mean inherit. That keeps the deathmatch resource from duplicating numbers that already live on `Balance`, which would be two sources of truth for the same 2:00 clock.

**`GameMode.fingerprint()` mixes every field except `display_name` and `match_rules_path`.** Names and scoreboard duration must not invalidate a replay. The path to `MatchRules` is above the sim by construction.

`Replay.rules_fingerprint_of` grows a third mix: `Balance`, `PowerupTable`, `GameMode`. Magic stays `HGR1`. An M3 deathmatch replay reports a rules mismatch, which is correct — the mix changed. Its *state* fingerprint, replayed under the deathmatch `GameMode`, must still match. That is the regression that proves FFA did not move.

`MatchState.create(..., p_mode: GameMode = null)` substitutes the deathmatch defaults when `p_mode` is null, so every existing test keeps calling `create(balance, def, seed, active)` and keeps meaning what it meant.

Lobby selection is a static on a tiny `Session` helper (`src/app/session.gd`): no new autoload. The lobby writes it, `MatchScene` reads it, tests set it. Quitting to the lobby keeps the last choice, which is what a rematch-from-the-lobby-after-B should feel like.

---

## 4. Simulation rules

The determinism contract is unchanged: no `delta`, no floats, no `Dictionary` iteration, one seeded PRNG consumed in a fixed order.

**Rule C — Hen mode adds exactly one PRNG consumer, and only in Hen mode.** Initial token placement is one `rng.next_index(candidates.size())` on a list filtered *before* the draw, same shape as crate regeneration (technical design §3a). Token *drop on death* consumes **no** draws: it is an ordered search, same as kit-loss scatter (M3 Rule B). Deathmatch create() does not call any of this.

### 4.1 Arena: half density, a lower regen floor

`Arena.generate` already draws once per eligible quadrant tile and keeps the crate when `next_below(1000) < crate_permille`. The draw *count* does not depend on the threshold. Hen mode passes `def.crate_permille * mode.crate_scale_permille / 1000` into generation (integer division) **without mutating the `ArenaDef` resource**. A 600 permille arena becomes 300. Replay header `crate_permille` stores that **effective** value, so a hen-mode `.hgr` is self-describing.

Crate regeneration stays on. At half density the arena *starts* around 30%, which is **below** the deathmatch cap of 45%, so inheriting that cap would land waves from the opening seconds and grow the hunt back into a maze. Hen mode's cap is `250` (tune): a floor under a hunted-open board, not a tide back toward deathmatch. If the playtest says the late game is too empty, raise the cap; if it says crates are in the way, drop it to 0 via the existing `crate_regen_ticks = 0` kill-switch on `Balance` (shared) or accept a mode-specific regen interval later. Do not build a second regen system.

### 4.2 Initial token placement

After players exist, build the candidate list in tile-index order:

A tile is a candidate if it is floor, not a lattice pillar, has no player standing on it, and (vacuously at t=0) no bomb, flame, or pickup.

Then exactly one `next_index` into that list. Place `hen_token_tile` there, `hen_slot = -1`.

Zero candidates is pathological (a 100% crate fill with no floor left). Place nothing and leave `hen_token_tile = (-1, -1)`; the round is then a five-minute deathmatch with a hen-ticks score of 0–0. There is a test that the candidate filter does not include spawn tiles the players occupy and does not include crates.

### 4.3 Collection

Same moment as power-up collection: after that player's movement, centre tile vs `hen_token_tile`. Dead players collect nothing. Slot order is the tie-break if two centres land on it in one tick — player 0 wins, because that is already the tick order. On collect:

- `hen_slot = p.index`
- `hen_token_tile = (-1, -1)`
- emit `HEN_COLLECTED`
- do **not** clear kit, curses, or spawn protection
- **re-arm any Remote bombs this player currently owns** with a normal fuse, same helper death-of-a-Remote-holder already uses. Otherwise a hunter who picks up the token with fuse-less bombs on the board can never detonate them and has just walled the arena off.

Becoming the Hen does not drop their kit and does not stop them collecting power-ups. Speed-ups sit in the kit and do nothing until they stop being the Hen. Bombs and blast they collect also wait. That is the comeback: survive, drop the token, respawn with whatever you hoovered.

### 4.4 Drop on death

When `_resolve_deaths` kills the player whose index is `hen_slot`:

1. Emit `HEN_DROPPED`.
2. Place the token on the nearest tile that is floor, with no bomb and no pickup, **preferring no flame**, ordered by Manhattan distance from the death tile then by tile index, inside `scatter_radius` (the same 4 as kit loss). If every candidate is on fire, place on the nearest floor anyway — the token survives fire (§1). If there is no floor in range at all, place on the death tile.
3. `hen_slot = -1`.
4. Continue with kit loss as today.

The token is **not** a pickup grid entry, so kit scatter cannot land on top of it: treat `hen_token_tile` as occupied when scattering and when regenerating crates, the same way an existing pickup is occupied.

### 4.5 Movement and actions

Effective speed, already the choke-point for the FAST curse:

```
if p.index == state.hen_slot and p.alive:
    speed = mode.hen_speed_units
elif cursed FAST:
    speed = max_speed_units
else:
    speed = p.speed_units
```

Bomb placement, Toss, and Remote request are skipped when `p.index == state.hen_slot`. Kick is not. Own-bomb exemption still clears normally, so a player who *was* standing on a bomb they placed as a hunter, then collected the token while still on it, can walk off it and cannot step back.

### 4.6 Scoring ticks

New step, after deaths and before respawns:

```
if hen_slot >= 0 and players[hen_slot].alive:
    players[hen_slot].hen_ticks += 1
```

Alive-after-deaths is the definition of "was the Hen this tick." A collect-and-die on the same tick (walk onto token, then `_resolve_deaths` from a flame already on that tile) is: collection happens during `_player_actions`, death happens after bombs. They were the Hen for the blast. They die, drop the token, and the increment sees `hen_slot == -1`. **Collecting onto a burning tile is not a free second.** There is a test for that.

`PlayerState.score` in this mode is a *display* copy of `hen_ticks / C.TICK_HZ`, updated when hen_ticks grows, so `MatchState.winner()` can keep reading `score` for `KILLS` mode and read `hen_ticks` (or the same `score` field, overwritten) for `HEN_TICKS` mode.

Cleaner, and what this brief requires: **`winner()` branches on `mode.scoring`.** `KILLS` is today's unique-highest-`score`. `HEN_TICKS` is unique-highest-`hen_ticks`. Do not reuse `score` for seconds — a suicide `−1` in hen mode would corrupt the objective. Kill score still updates on `PlayerState.score` as today; the HUD just does not lead with it.

### 4.7 New state

| Where | Field | Why |
|---|---|---|
| `MatchState` | `mode: GameMode` | never null; create() defaults to deathmatch |
| `MatchState` | `hen_slot: int` | `-1` or `0..3`. At most one. |
| `MatchState` | `hen_token_tile: Vector2i` | `(-1, -1)` while held or absent |
| `PlayerState` | `hen_ticks: int` | objective, fingerprinted |
| `SimEvent.Kind` | `HEN_COLLECTED`, `HEN_DROPPED` | view / SFX later. `player` is who took / lost it; `tile` is where the token is / was |

`hen_slot` and `hen_token_tile` are mutually exclusive in the legal states: held ⇒ tile is `(-1,-1)`; on the floor ⇒ slot is `-1`; neither (pathological empty start) ⇒ both empty. There is an invariant test.

Both fields mix into `MatchState.fingerprint()`. `hen_ticks` mixes into `PlayerState.mix_into`.

### 4.8 Tick order

```
tick += 1
_age_flames
_tick_curses
for each active player:
    _player_actions          collect power-ups AND the token here
_tick_bombs
_resolve_deaths              hen drop, then kit loss
_tick_hen                    increment if still the living Hen     ← new
_tick_respawns
_tick_spawn_protection
_tick_crate_regen            token tile is not a candidate
_tick_clock
```

`_tick_hen` sits after deaths so the death tick does not pay, and before respawns so a body coming back this tick cannot be the Hen (they dropped).

---

## 5. Match flow and lobby

### 5.1 Lobby

M2 said "no mode select." That sentence is retired.

Two chips under the title, above the four seat cards: `DEATHMATCH` and `HEN GRENADE`. The selected chip is filled in the player's-read colour (the cream the title already uses); the other is dim.

**LB / RB on any connected pad cycles**, including a pad that has not joined — same policy as rematch CONFIRM (technical design §4). Keyboard: `[` previous, `]` next. Help line grows one clause. **Y / X / START / join / leave are untouched.**

Do not use D-pad left/right: on a sofa someone will nudge a stick while joining. Do not use Back/Select: Back is leave. Do not use Y: Y is add bot.

`Session.mode_id` updates immediately; START launches `MatchScene`, which loads the matching `GameMode` and `MatchRules`.

### 5.2 Single-round match

`data/balance/match_hen.tres`: `round_wins_to_take_match = 1`, `max_rounds = 1`, `scoreboard_ticks` the same 240. After the 5:00 clock, the scoreboard shows hen-seconds (and kills/deaths as a second line), then `MatchRecord.is_over()` is true, then the winner screen. CONFIRM rematch, BACK lobby, as today.

Pause "Restart round" still does not record a result.

### 5.3 What the player sees

**The Hen is a different silhouette**, not a different palette. Slot colour stays on the outline so P2-as-Hen is still blue. Programmer art: a slightly larger oval body plus a three-point comb, drawn in a dedicated pass after the hunter rects (Appendix A.12: one extra pass, not one extra call per hen — there is one hen). Hunters stay the current rounded rect. Shape, not hue, is what colourblind-safe requires (game design §8).

**The token** is not in the power-up legend. It is a gold disc with a small chevron, drawn in its own pass under flames. It does not blink; it does not share a hue with Jackpot.

**HUD cards** in this mode lead with hen-seconds (`47s`) instead of `pts`. The living Hen's header reads `P2 HEN`. Kit lines stay; they still matter for after the drop. The clock string becomes `4:12  HEN P2` when someone holds it, `4:12  TOKEN` when it is on the floor, using the existing clock `Label` — a second Label is a draw call (Appendix A.11).

**Urgent clock** remains the last 10 seconds.

Scoreboard title: `HEN GRENADE  seed xxxxxxxx`. Rows: `P1   94s   3k / 5d`. Overlay `geometry_problems` grows a hen-mode pass with the longest plausible row.

---

## 6. What does not change

- Blast math, chains, kill credit, kit loss, curses, Kick / Toss / Remote for **hunters**, crate-regen algorithm (only the cap number), pause, reconnect, replay file layout, input encoding.
- Deathmatch lobby path, F4-straight-to-match (still deathmatch unless `Session` says otherwise), stress scene (still a deathmatch worst case; the token is one sprite and does not move the budget).
- Bots. The placeholder wanders into bombs with or without a token. M5 is where "path to the token / hunt the Hen / flee as the Hen" belongs; add a note there, do not grow `BotSource` now.

---

## 7. Tests

Every rule in §2–§4 is testable headless.

**`tests/unit/test_hen_mode.gd`** (new)

- create() in deathmatch: `hen_slot == -1`, `hen_token_tile == (-1,-1)`, `hen_ticks` all 0, **PRNG draw count equals today's create()** (pin this; it is Rule C).
- create() in hen: exactly one extra `next_index`, token on a legal candidate, never under a player, never on a crate or pillar.
- walking onto the token becomes the Hen, emits `HEN_COLLECTED`, tile clears.
- two players entering the tile on the same tick: lower slot index wins.
- the Hen cannot place a bomb; a hunter still can.
- the Hen cannot Toss or Remote; Kick still slides a bomb.
- the Hen's `speed_units` is unchanged after a second of movement; distance travelled matches `hen_speed_units`, not the kit, not FAST.
- FAST + Hen uses `hen_speed_units`.
- death drops the token, clears `hen_slot`, kit loss still runs, player respawns as a hunter.
- token drop prefers a non-flame floor and consumes no draws.
- a blast on the token tile does **not** destroy it.
- `hen_ticks` increments only while the living Hen, not on the death tick, not while dead, not after the round clock has hit 0 (finished rounds do not step).
- collect-on-fire-then-die: zero hen_ticks from that collect.
- leftover Remote bombs re-arm on collect.
- `winner()` uses `hen_ticks`, ignores a huge kill `score`.
- equal `hen_ticks` is a draw.
- crate generation draw count is independent of `crate_scale_permille`; a 500-scale arena is observably thinner than 1000-scale on the same seed.
- crate regen in hen mode respects the 250 cap and still refuses the token's tile.

**`tests/unit/test_match_record.gd`** — one addition: `from_rules` with the hen `MatchRules` ends after a single recorded round.

**`tests/unit/test_menu_cursor.gd`** — do not drag mode-cycling in unless it shares the cursor. It should not; cycling is a lobby edge on `DeviceManager`, tested in `test_device_binder` only if the binder learns about it. Prefer: lobby cycles `Session` directly from menu edges, binder stays mode-ignorant. Then a tiny `test_session.gd` for wraparound `DEATHMATCH ↔ HEN`.

Existing suites stay green **unmodified**. The one allowed edit is `test_replay.gd` / the committed **rules** hash, because `GameMode` joins the mix. **If a state hash or trace digest moves, stop and fix the sim, do not regenerate.**

**Golden `golden_03` (Hen).** A committed hen-mode round whose input log collects the token, spends time as Hen, dies as Hen, and has a second player collect it. Assert those events the way `golden_02` asserts a crate wave. Do not pin hen rules with a deathmatch log.

Generator: `tools/make_golden_replay.gd` grows a `--mode hen` path (or a second entry point). Same self-check-before-write.

---

## 8. Tuning resources

| File | What |
|---|---|
| `data/balance/modes/deathmatch.tres` | inherit-everything, `KILLS` |
| `data/balance/modes/hen.tres` | 18000 ticks, scale 500, cap 250, speed 8, `HEN_TICKS` |
| `data/balance/match_hen.tres` | first to 1, max 1 round |
| `data/balance/default.tres` | **unchanged** — deathmatch numbers stay here |

No new tuning number is a literal in a `.gd` file under `src/sim/`. `8`, `18000`, `500`, `250` live on the hen resource.

---

## 9. Exit criteria

1. From the lobby, two people can pick **HEN GRENADE**, play a 5:00 round, see a hen-seconds scoreboard, and rematch, on keyboard, without touching deathmatch settings.
2. The same path exists for deathmatch as it does today: default chip, 2:00, best-of-3, kill score. A stranger who never cycles modes gets the M3 game.
3. The Hen is identifiable at a glance in programmer art *without* relying on hue alone; the token is identifiable against Jackpot.
4. **Sim suite green. Deathmatch golden state hashes and traces identical to M3. New `golden_03` reproduces.**
5. Scene smoke covers the lobby with each chip selected, a shortened hen round (test balance `round_ticks`, not 18000, in the smoke), scoreboard geometry in hen-mode strings, and the existing deathmatch smoke.
6. No HP system, no second token, no best-of-3 of five-minute rounds.
7. Stress-scene draw calls do not grow by more than **one pass** (the token, or the hen silhouette — batch them). Re-run `-- --measure` and append the row if the number moves.

---

## 10. Suggested order of work

1. `GameMode` resource, two `.tres`, `match_hen.tres`, `Session`. `MatchState.create` accepts a mode and inherits deathmatch. Fingerprint mix. **Run the existing suite — it must be green before any Hen rule exists.**
2. Effective crate scale + `round_ticks` override. Tests that density and clock differ and that deathmatch create() draw count is unchanged.
3. Token placement, collection, drop, blast-immunity. `test_hen_mode.gd` through §4.4.
4. Hen constraints: no bomb, no Toss/Remote, speed override, Remote re-arm. Scoring ticks and `winner()`.
5. Lobby chips and menu edges. MatchScene loads mode + matching `MatchRules`. Overlay/HUD/entity view.
6. `golden_03`. Update deathmatch **rules** hashes only if the mix changed and the state hashes did not.
7. Smoke, `-- --measure`, hardware pass if a Pi is on the desk — this milestone does not wait on the M3 playtest, but it must not make that playtest impossible: deathmatch is still the default.

---

## 11. Open playtest questions (do not pre-solve in code)

These are why the numbers are `(tune)`:

1. Is **0.5× speed** too slow to be fun, or too fast to hunt?
2. Is **5:00** a slog once people know the mode, or the right length for a token that can sit uncollected?
3. Is **half density** open enough to hunt and still crate-y enough to hide?
4. Does the **250 crate cap** keep a late-game hunt, or should regen be off?
5. Is **Kick-as-Hen** a clever escape or a cheap stalemate?

Write the answers down in the M3.5 completion notes after someone has played. Do not retune from the chair.
