# Milestone 3 — Build Brief

Everything needed to implement M3 without coming back to ask. Read [the roadmap](roadmap.md) for why M3 exists, [game design §6](game-design.md) for the economy it builds, and [technical design §3a and §6](technical-design.md) for the determinism and tuning rules it has to obey. This is the executable version, in the same spirit as the [M0](milestone-0-brief.md), [M1](milestone-1-brief.md) and [M2](milestone-2-brief.md) briefs.

**M3 is the first milestone that changes the rules since M1, and the first whose exit criterion is an opinion.** M1 built a correct two-minute round and M2 built a way for four people to start one. Neither of them asked whether the game is any good, and neither of them could: a deathmatch with one bomb, radius 1 and no reason to fight over the middle of the arena is not the game in the design document. M3 adds the economy — drops, abilities, curses, kit loss, crate regeneration — and the match structure around it, and then it gets played by four people who say whether it works.

Unlike M2, **M3 touches `src/sim/` extensively**, and that has one immediate consequence: the golden replay will stop reproducing, on purpose, and has to be regenerated deliberately once (§9). Every other sim test must stay green through the change, and if one of them goes red the change is wrong until proven otherwise.

The three open design questions M3 exists to answer are named in the roadmap: whether the 23 × 13 interior plays too large, how much a death should cost, and whether crate regeneration feels fair or feels like interference. Every number behind all three is a field in a `.tres` by the end of this milestone, because the answer to each is "play it and move the number".

---

## 1. Scope

**In scope**

1. **Pickups and the full power-up table** — drops from destroyed crates, the weight table in its own resource, caps, and destruction by a later blast.
2. **Kick, Toss, Remote** — the three ability power-ups, all three on the one action button the design gives us.
3. **The Dud curse** and its four variants.
4. **Kit loss on death** — halve the stacking upgrades, lose the abilities, scatter the remainder as pickups around the body.
5. **Crate regeneration** — timed waves, the exclusion rules, the crate cap, and the never-seal-a-player-in guarantee.
6. **Match flow** — best-of-3 with a decider, draw handling, a kills/deaths scoreboard between rounds, and a winner screen.
7. **All new tuning in resources** — `Balance` grows, `data/balance/powerups.tres` appears, `data/balance/match.tres` appears.
8. **Tests** for every rule above, and a regenerated golden replay that actually exercises the new ones.
9. **The stress scene keeps being the worst case** — it now has to include a pickup field, because pickups are a new per-frame draw.

**Out of scope — do not build these**

Art, audio, animation, the telegraphing pass, an options screen, remapping, settings persistence (**M4**); real bots (**M5**); the balance pass that follows from the playtest (**M6** — M3 produces the numbers and the playtest opinion, not the final values).

Four borderline calls, resolved:

- **The scoreboard is an overlay, not a scene.** M2's completion notes said best-of-3 "wants an owner above the round" that survives a scene change. It turns out it does not: `MatchScene` already plays round after round without a scene change, and the only transitions that leave it — quit to lobby, and the lobby's own start — are exactly the transitions that *should* end a match. So the match record lives in `MatchScene` as a plain tested object and **no new autoload is added**. Fewer moving parts, and one less thing that cannot be unit-tested.
- **Toss and Remote are mutually exclusive.** There is one action button (`InputFrame.action`), and hanging both "throw the bomb I am standing on" and "detonate everything I own" off it needs either a tap-versus-hold discrimination in a twitch game or an arbitrary priority rule. Instead, picking one up clears the other: B is your ability button and you have exactly one ability. It also makes taking a Toss while holding Remote a real decision rather than a free upgrade. §4.3.
- **A curse dies with you.** Death already costs half your kit; carrying an 8-second curse through a respawn on top of that compounds two punishments, and the Fast curse in particular becomes a death spiral. Dying clears it. §4.4.
- **No pending-crate state for the regeneration telegraph.** Game design §6.2 asks for "a short telegraphed landing animation". The sim places the crate and emits `CRATE_SPAWNED`; the view animates the landing from the event. A true pre-warning (a crate that is announced on tick N and lands on tick N+20) is presentation state, it would be the only two-phase entity in the simulation, and M4 can add it to the view without the sim learning about it. §5.

---

## 2. What the simulation grows

The determinism contract from [M1 brief §2](milestone-1-brief.md) is unchanged and every rule below obeys it: no `delta`, no floats, no `Dictionary` iteration, one seeded PRNG consumed in a fixed order. Two additions worth stating, because M3 is where they get tested properly:

**Rule A — PRNG draws per crate destruction are a constant.** Destroying a crate consumes **exactly three draws**: the drop roll, the kind roll, and the curse-variant roll, whether or not anything drops and whether or not the thing that dropped is a Dud. A conditional draw would make the sequence depend on the outcome of earlier draws, which is reproducible but miserable to reason about — and it is the shape of bug that survives a green golden replay until the day someone changes a weight. There is a test that asserts the draw count directly.

**Rule B — pickup scatter and respawn selection consume no draws at all.** Both are deterministic searches over an ordered candidate list, exactly like respawn tile selection in M1. The only new consumer of the PRNG in M3 is crate regeneration (§5), and that one draws from a list filtered *before* the draw, per technical design §3a.

### 2.1 New state

| Where | Field | Why |
|---|---|---|
| `MatchState` | `powerups: PowerupTable` | the weight table, so the sim never hardcodes a drop rate |
| `MatchState` | `pickup_kind: PackedByteArray` | one byte per cell, `Powerup.Kind`, 0 = nothing |
| `MatchState` | `pickup_data: PackedByteArray` | the curse variant for a Dud, 0 otherwise |
| `MatchState` | `regen_ticks_left: int` | counts down to the next crate wave |
| `PlayerState` | `speed_steps: int` | how many Speed Ups are in the kit, kept alongside `speed_units` |
| `PlayerState` | `has_kick: bool` | Kick has no button, so it is just a flag |
| `PlayerState` | `ability: int` | `Powerup.Kind.NONE`, `TOSS` or `REMOTE` — one at a time |
| `PlayerState` | `curse: int`, `curse_ticks: int` | the active Dud variant and its countdown |
| `PlayerState` | `prev_action: bool` | rising-edge detection for B, exactly like `prev_bomb` |
| `Bomb` | `remote: bool` | placed by a Remote holder: no fuse, waits for the button |
| `Bomb` | `slide_dir: Vector2i`, `slide_ticks: int` | a kicked bomb in motion |

**Pickups are two flat byte grids, not a list of objects** — the same decision as flames and for the same reasons: one pickup per tile falls out of the representation instead of needing a rule, "what is on this tile" is O(1), and a kit-loss scatter allocates nothing.

**`speed_steps` is deliberately redundant with `speed_units`.** Movement reads units; kit loss needs to halve *steps*. Deriving steps back out of units is exact only while the value is below the cap — at the cap the last step is clamped short, and `(speed_units - base) / step` then quietly rounds a player's kit down. Storing both makes kit loss exact and costs one integer in the fingerprint.

### 2.2 The new tick order

```
tick += 1
_age_flames                     flames laid last tick get their full lifetime
_tick_curses                    expire before actions, so the last cursed tick is a real one
for each active player:
    _player_actions             curse rewrites the frame, bomb, move, kick, ability, collect
_tick_bombs                     remote fires, fuses, chains, slides
_resolve_deaths                 kill credit, kit loss, scatter
_tick_respawns
_tick_spawn_protection
_tick_crate_regen               a wave lands here, after everything has moved
_tick_clock
```

Only two lines are new (`_tick_curses`, `_tick_crate_regen`) and neither moves an existing one. The order inside `_player_actions` does change and the reasons matter:

```
1. rewrite the frame for a curse      (reversed dir, forced bomb)
2. edge-detect bomb and action        (both tracked even while dead)
3. place a bomb                       before movement, so it lands where you pressed
4. move                               kick fires from inside movement
5. use the ability                    after movement: a toss goes where you now face
6. collect a pickup                   after movement, so walking onto one takes it this tick
7. release the own-bomb exemption
```

---

## 3. Power-ups and pickups

### 3.1 The table

`PowerupTable` is a `Resource` at `data/balance/powerups.tres`, named in technical design §6 and finally real. It holds the drop rate and one weight per kind:

| Kind | Effect | Weight | Cap |
|---|---|---|---|
| `BOMB` | +1 concurrent bomb | 26 | `max_bomb_capacity` (8) |
| `BLAST` | +1 blast radius | 26 | `max_blast_radius` (8) |
| `SPEED` | +1 speed step | 16 | `max_speed_units` (26 ≈ 6.1 t/s) |
| `KICK` | walk into a bomb to slide it | 12 | on/off |
| `TOSS` | B lobs your bomb two tiles | 7 | on/off, clears Remote |
| `REMOTE` | B detonates all of yours | 5 | on/off, clears Toss |
| `JACKPOT` | blast radius jumps to max | 2 | — |
| `DUD` | an 8 s curse, one of four | 6 | — |

Weights total 100, which is a convenience and not a constraint — the pick is `rng.next_below(total)` walked against the accumulated weights in enum order, so any positive integers work. `drop_permille` is 300: roughly three crates in ten leave something behind.

**A power-up already at its cap is still consumed.** Walking over an Extra Bomb with eight bombs takes the pickup and gives nothing, rather than leaving it on the floor for a player who can use it. Leaving it would be kinder and is the wrong call: a pickup nobody can pick up is a permanently blocked tile that looks like a mistake, and "the pile in the corner is mine because I am maxed out" is a rule nobody would guess.

### 3.2 Drops and destruction

A crate destroyed by a blast rolls for a drop (§2 Rule A). The pickup lands on the tile the crate occupied — which is now floor and, importantly, **on fire**, because the blast that broke the crate lit that tile. So a drop is not destroyed by the flame that revealed it: destruction is checked when a flame is *laid*, not per tick, and the drop is written after the flame. A drop is destroyed by the **next** blast that reaches it, which is the "grab it now" tension game design §6 asks for.

`_lay_flame` destroys any pickup on the tile it lights and emits `PICKUP_DESTROYED`. Refreshing a flame that is already burning does not re-destroy anything, because there is nothing left.

### 3.3 Collection

A player collects the pickup on the tile their centre occupies, after movement. Dead players collect nothing. A pickup under a player at the moment it spawns (a scatter landing under someone, a drop under someone standing in a blast they survived) is collected on the next tick, which is the correct and only consistent answer.

---

## 4. The three abilities and the curse

### 4.1 Kick

No button: walking into a bomb slides it.

- Fires from inside `_move`, on the tick the way ahead is blocked **by a bomb** and the player has Kick. Blocked by a wall or a crate is not a kick, and a bomb the player is exempt from — their own, still under their feet — is not a kick either, because they are standing on it rather than walking into it.
- A sliding bomb is **still tile-quantised**: it advances one whole tile every `kick_ticks_per_tile` ticks (6, about 10 tiles/s). Everything in the simulation that touches bombs — solidity, `bomb_index_at`, blast rays, chain detonation — indexes them by tile, and giving a bomb a sub-tile position would mean revisiting all of it for one power-up. The cost is that the slide is visibly steppy in programmer art; the view has `slide_dir` and `slide_ticks` and can interpolate in M4 without the sim changing.
- It stops when the next tile is solid or holds another bomb.
- **It passes under players.** Nothing in this game collides with a player (game design §5.1) and a bomb that stops on one would need a rule about which players count — the dead, the protected, the one who kicked it. A bomb sliding under someone is a threat they can walk away from, which is the interesting version anyway.
- **A bomb that slides onto a burning tile detonates immediately**, credited to the flame's owner. Without this, kicking a bomb into a fire does nothing, which nobody would predict from "a bomb caught in a blast detonates".
- Kicking a bomb releases the kicker's own-bomb exemption on it, because the bomb is no longer the one they are standing on.

### 4.2 Toss

- Fires on the **rising edge of B**, not on a hold-and-release. Game design §6 says "hold and release", which is the classic behaviour because there the hold charges the distance; here the distance is fixed at two tiles, so a hold buys a wait and no decision. Recorded as a deviation to raise at the playtest — if two tiles always being two tiles feels flat, a charged throw is the obvious next thing to try, and it is a change to this one function.
- It lobs **the bomb under the player's feet** — the one they are exempt from. With nothing underfoot, B does nothing.
- The bomb lands `toss_tiles` (2) tiles away in the direction the player faces, **over anything in between**: that is the point of the ability. If the target tile is not free (solid, or another bomb), it walks *back* toward the thrower and lands on the first free tile it finds. Never forward — a toss that overshoots into the next corridor because the intended tile was occupied would be genuinely unpredictable.
- The bomb keeps its fuse and its owner. Its radius was fixed when it was dropped ([`Bomb.radius`](../src/sim/bomb.gd)), so tossing does not re-roll it.
- **The flight is instantaneous in the simulation.** A `BOMB_TOSSED` event carries the from- and to-tiles and the view draws the arc. An airborne bomb would be the only entity in the game that is neither solid nor chainable nor on a tile, for 12 ticks, and the rules do not need to know about it.

### 4.3 Remote

- A bomb placed by a Remote holder has `remote = true` and **no fuse**. It sits until its owner presses B, at which point every one of their live bombs detonates, each as its own chain root, in bomb-array order.
- Remote firing happens at the **top of the bomb phase**, from a request flag set during the player's actions, so that all detonation in the game happens in one place and the "deaths resolve after blasts" ordering is untouched.
- **Losing Remote arms everything you left behind.** A player who dies holding Remote loses the ability (§4.5) — and their fuse-less bombs get a normal fuse on the spot. The alternative is permanent solid blocks in the middle of the arena owned by nobody, which is how a two-minute round silts up into a maze.
- Remote is the design's skill pick and the easiest way to blow yourself up. Nothing in the rules protects you from your own button; the suicide penalty is the whole feedback mechanism.

### 4.4 The Dud

An 8-second curse (`curse_ticks`, 480), one of four variants, drawn at crate-destruction time (§2 Rule A) and carried on the pickup:

| Variant | Rule |
|---|---|
| `REVERSED` | the frame's direction is inverted before anything reads it |
| `BOMB_SPAM` | a bomb placement is attempted every tick, not on the edge |
| `TINY_BLAST` | the effective blast radius is 1, applied when a bomb is dropped |
| `FAST` | the effective speed is `max_speed_units`, whatever the kit says |

All four are **effective-value overrides, never writes to the kit**: `TINY_BLAST` does not reduce `blast_radius` and `FAST` does not raise `speed_units`, so an expiring curse restores exactly what the player had and a cursed player's kit loss on death is unaffected. A second Dud replaces the first and refreshes the timer. A curse is cleared by death (§1).

`REVERSED` lives in the simulation rather than in the input layer deliberately: the input layer is four device implementations and a replay, and a curse that rewrote input upstream of `Replay.record()` would be invisible in the log — replays would show a player walking calmly into a fire for no reason.

### 4.5 Kit loss on death

The most important balance dial in the game (game design §6.1), and therefore one number: `kit_loss_permille`, default 500.

```
kept_extra = extra * (1000 - kit_loss_permille) / 1000     # integer division
```

- **Stacking upgrades** — bombs, blast, speed steps — keep `kept_extra` of whatever was above the starting loadout. At 500 permille that is exactly "halved, rounded down": five extra bombs keeps two and drops three.
- **Abilities** — Kick and the Toss/Remote slot — are lost entirely.
- **The curse** is cleared and scatters nothing. Dropping a Dud where you died would be a gift to whoever killed you, in the shape of a trap.
- Everything lost **scatters as pickups** on free tiles around the body, in a fixed order (bombs, then blast, then speed, then Kick, then the ability), onto candidate tiles ordered by Manhattan distance from the death tile and then by tile index. No PRNG (§2 Rule B).
- A candidate tile must be floor, with no bomb, no pickup, and **no flame**. That last one matters: the death tile is on fire by definition, and scattering into the blast that just killed you would evaporate the whole kit before anyone could see it. Items with nowhere to land inside `scatter_radius` (4) are lost.

The result is the dynamic §6.1 is after: the spot where someone died is a contested pile, and the player who died has a reason to run back toward it rather than away.

---

## 5. Crate regeneration

Every `crate_regen_ticks` (1200, 20 s) a wave of up to `crate_regen_wave` (6) crates lands. This exists because a two-minute round with four players and growing blast radii strips the arena bare in about a minute, and a bare arena is one where nobody can rebuild after a death — the exact opposite of what kit loss is for.

**Candidate filtering happens before any draw**, per technical design §3a, so the number of PRNG calls cannot depend on how many candidates were rejected. A tile is a candidate if it is floor, and has no bomb, no flame, no pickup, no player standing on it, and **no living player orthogonally adjacent**. That last rule is what stops a crate landing in someone's face.

Then, up to `crate_regen_wave` times:

1. stop if the arena is already at the crate cap;
2. draw one index from the candidate list, remove it, and place a crate;
3. **run the seal probe.** Flood-fill from every living player's tile across non-solid tiles, counting up to `min_escape_tiles` (3). If any living player can now reach fewer than that, the crate is taken back off the board and the wave moves on — it is **not** retried, because a retry would consume a second draw for one candidate and make the draw count depend on the rejection.

The cap is `crate_cap_permille` (450) of the eligible interior — interior tiles that are not lattice pillars, 233 of them on a 25 × 15 grid, so 104 crates. The arena *starts* above that at ~70%, which means regeneration does nothing until the round has genuinely thinned out. That is the intended shape: it is a floor under the arena's crate supply, not a tide.

**A `CRATE_SPAWNED` event carries each landing** and the view updates that one tilemap cell, the same single-cell path `CRATE_DESTROYED` already uses. The arena is still never redrawn per frame.

Game design §6.2 names a fallback if this feels like interference: drop a lone power-up on a free tile every 15 s instead. Do not build both. The playtest decides, and the decision is a `crate_regen_ticks` of 0 plus twenty lines if it goes the other way.

---

## 6. Match flow

### 6.1 The record

`MatchRecord` (`src/app/match_record.gd`) is a plain `RefCounted` with no `Node` and no autoload, so it is unit-testable, and it owns the whole best-of-3 question:

```
record_round(winner_slot)      # -1 for a draw
rounds_played() -> int
is_over() -> bool
winner() -> int                # -1 while unfinished, and -1 for a drawn match
```

- First to `round_wins_to_take_match` (2) takes the match.
- **A drawn round advances nothing.** Nobody gets a win, the round counts as played, and the match continues. Draw, draw, win, win is a legal four-round match.
- Which is why there is a **decider**: game design §5.3 says a level match plays one. Rounds keep coming until somebody reaches two wins, capped at `max_rounds` (7) so a pathological sequence of draws cannot run forever. At the cap the match goes to the unique highest win count, then to the unique highest total round score, and is otherwise recorded as a drawn match — which is an honest outcome for four people who genuinely could not be separated in seven rounds.

### 6.2 Phases

`MatchScene`'s phase machine grows two states and loses one. `ROUND_OVER` — M2's "banner and wait" — becomes `SCOREBOARD`, and `MATCH_OVER` appears behind it:

```
   ┌─────────┐  pad lost  ┌───────────┐        ┌──────────┐
   │ RUNNING │───────────►│ RECONNECT │        │  PAUSED  │
   │         │◄───────────│           │        │          │
   └────┬────┘  rebound   └───────────┘        └──────────┘
        │ clock hits 0:00        ▲ any phase below can raise it
        ▼
   ┌────────────┐  4 s or CONFIRM   ┌──────────────┐
   │ SCOREBOARD │──────────────────►│  next round  │
   │  kills /   │                   └──────────────┘
   │  deaths /  │  match is over    ┌──────────────┐
   │  the tally │──────────────────►│  MATCH_OVER  │
   └────────────┘                   └──┬────────┬──┘
                                       │        └─ BACK ──► lobby
                                       └─ CONFIRM ──► new match, same roster
```

- The scoreboard **auto-advances** after `scoreboard_ticks` (240, 4 s) and is skippable with CONFIRM, per game design §3. Four people on a sofa should not have to agree to press a button between rounds.
- **A lost pad raises the reconnect notice from the scoreboard too**, not just from a running round. `MatchState.active_slots` is rebuilt from the roster at the start of every round, so a seat still reserved when the next round begins would silently drop that player out of the match. The notice returns to whichever phase raised it, which is what M2's `_resume_phase` already does.
- "Restart round" on the pause menu restarts the round **without recording it**. It is a do-over, not a result.
- Quitting to the lobby abandons the match, which is why the record does not have to survive a scene change (§1).

### 6.3 What the player sees

The scoreboard and the winner screen are modes of M2's overlay, which is generalised for it — M2's completion notes nominated `pause_overlay.gd` for exactly this. It becomes `src/ui/round_overlay.gd`: one panel, sized to its content, with a title, up to eight coloured body lines, and a footer. The pause menu and the reconnect notice are unchanged in behaviour and now share the sizing.

The round seed goes on the scoreboard, because game design §4 promises it ("a good layout can be replayed") and this is the only screen that can show it.

HUD cards grow to carry what the player now actually has: score, kills/deaths, bombs, blast, speed, the ability, the curse and its countdown, and the round-win tally. All of it inside the existing single `Label` per card — a card is one draw call whatever is written on it, and [Appendix A.11](technical-design.md) is clear about what a second text pass costs.

---

## 7. Tuning resources

Every number above is a field, none of them is a literal in a rule. Three resources:

**`data/balance/default.tres`** (`Balance`) gains the simulation's numbers: `speed_step_units`, `max_bomb_capacity`, `max_blast_radius`, `curse_ticks`, `kit_loss_permille`, `scatter_radius`, `kick_ticks_per_tile`, `toss_tiles`, `crate_regen_ticks`, `crate_regen_wave`, `crate_cap_permille`, `min_escape_tiles`. All of them join `Balance.fingerprint()`, so a replay recorded against different tuning is a loud mismatch rather than a desync.

**`data/balance/powerups.tres`** (`PowerupTable`) — drop rate and the eight weights. It has its own fingerprint, and the replay stores `Balance` and `PowerupTable` mixed together as one **rules fingerprint**: a re-weighted table changes what a recorded round produces just as surely as a retuned fuse does.

**`data/balance/match.tres`** (`MatchRules`) — `round_wins_to_take_match`, `max_rounds`, `scoreboard_ticks`.

Match rules are a **separate resource on purpose.** They are read above the simulation and the simulation never sees them, so they must not be in the fingerprint — changing how long the scoreboard sits should not invalidate every committed replay. Putting them in `Balance` would mean fields deliberately excluded from that resource's own fingerprint, which is a trap for whoever adds the next one.

`speed_step_units` is 3, not 2.56. The design's +0.6 t/s is 2.56 units/tick and the simulation has no fractions, so a step is 3 units (0.70 t/s) and four of them reach the 6.0 t/s cap. Same quantisation the base speed already took in M1 (3.5 → 3.516 t/s), written down in the same place.

---

## 8. Tests

Every rule in §3–§6 is testable headless and is tested there. New suites:

**`tests/unit/test_powerups.gd`**
- each kind applies its effect, and each respects its cap;
- a capped power-up is still consumed;
- Jackpot goes straight to `max_blast_radius`;
- Toss clears Remote and Remote clears Toss;
- a pickup is collected on the tick the player's centre enters its tile, and a dead player collects nothing;
- a blast destroys a pickup and emits `PICKUP_DESTROYED`;
- **a drop survives the flame that revealed it** and dies to the next blast;
- **exactly three PRNG draws per destroyed crate**, asserted by stepping the RNG state — the one test that pins Rule A.

**`tests/unit/test_abilities.gd`**
- Kick: a player without it is stopped by a bomb; with it the bomb slides; it stops at a wall, at a crate, and at another bomb; it passes under a player; it detonates on a burning tile; walking off your own bomb is not a kick.
- Toss: lands two tiles away over a wall; falls back toward the thrower when the target is occupied; does nothing with nothing underfoot; keeps its fuse, owner and radius.
- Remote: a remote bomb never fuses; B detonates all of that player's bombs and none of anyone else's; chain credit still belongs to the player who pressed; dying re-arms the orphans with a normal fuse.
- Curses: each of the four does its one thing; a curse expires on the exact tick; a second Dud replaces the first; death clears it; `TINY_BLAST` and `FAST` do not write to the kit.

**`tests/unit/test_kit_loss.gd`**
- halving rounds down, per stat, from the starting loadout rather than from zero;
- abilities are lost whole;
- the lost items appear as pickups, in the documented order, on the nearest free tiles;
- **nothing scatters onto a flame**;
- a player who died with the starting loadout scatters nothing;
- the scatter consumes no PRNG draws;
- a fully enclosed death spot loses the kit rather than placing pickups in walls.

**`tests/unit/test_crate_regen.gd`**
- a wave lands on the exact tick and refills the timer;
- never on a player, bomb, flame or pickup tile, and never orthogonally adjacent to a living player;
- **the seal probe**: a candidate that would leave a player with fewer than `min_escape_tiles` is rejected and the board is left as it was;
- the cap holds, and a full arena regenerates nothing;
- `crate_regen_ticks = 0` disables it entirely;
- the draw count for a wave does not depend on how many candidates were filtered out.

**`tests/unit/test_match_record.gd`**
- first to two takes it; a 2–0 match ends after two rounds;
- a drawn round gives nobody a win and does not end the match;
- a level match plays a decider;
- `max_rounds` terminates a pathological match, and the tie-breaks resolve in the documented order;
- `winner()` is -1 while the match is unfinished.

Existing suites must stay green **unmodified**, with one exception: `test_replay.gd`'s golden assertions read the regenerated fingerprint file, and the assertion that compares the recorded rules fingerprint has to learn about the power-up table. Any other existing test that needs editing to pass is a signal that M3 broke a rule M1 pinned — look there first.

**What stays untested.** The view, the overlay and the phase machine, for the same reasons as in M2: `Node`, `Input` and autoloads are unreachable from a `--script` process. The phase machine's self-check in `smoke_phases()` grows to cover the scoreboard and match-over transitions, because that self-check is the only verification it gets.

---

## 9. The golden replay

M3 changes the rules, so the golden replay **will** fail, and that is the system working. The procedure, once:

1. Run the suite. Expect `test_replay`'s two golden assertions to fail and **nothing else**. If something else fails, fix it before going near the generator.
2. Read the failure. The rules fingerprint mismatch is expected (new balance fields, a new resource in the mix); the state fingerprint mismatch is expected (pickups exist now).
3. Extend the generator so the new round is worth pinning: the recorded input must press `action`, and the round must be long enough for a crate wave to land. The old log presses only direction and bomb, so it would pin the new sim while exercising none of the new rules.
4. Regenerate with `tools/make_golden_replay.gd`, which self-checks the round trip before it writes.
5. Commit the new `.hgr` and `.fingerprint.txt` **in the same commit as the rule change**, with the reason in the message. A golden file regenerated in its own commit is indistinguishable from a golden file regenerated to hide something.

The generator's assertions in `test_replay.gd` get one more: the recorded round must contain at least one pickup collection, so a future regeneration cannot quietly go back to pinning a round with no economy in it.

---

## 10. Exit criteria

1. **A full best-of-3 match plays start to finish with four people on real hardware**, on Windows and on the reference Pi 400: lobby, round, scoreboard, round, scoreboard, winner screen, rematch.
2. **And it is fun.** This is the first honest go/no-go on the design and it is not a code criterion. The three questions to come back with answers to are the roadmap's: does the 23 × 13 interior play too large, does a death cost the right amount, and does crate regeneration feel fair or feel like interference.
3. Every power-up in the table appears in play, works, and is readable enough to tell apart in programmer art — including which one you just picked up.
4. **The sim suite is green, and the regenerated golden replay reproduces both its fingerprint and its trace digest.**
5. Scene smoke green, including the scoreboard and match-over overlays and the extended phase self-check.
6. **The stress scene still holds 60 FPS on the Pi 400** with the M3 additions in it — a pickup field, a regeneration wave, and four kit scatters on screen at once. M0's number was measured without pickups; a new per-frame draw means the worst case has to be re-measured, and the row goes in [m0-pi400.md](measurements/m0-pi400.md).
7. No new tuning number is a literal in a `.gd` file under `src/sim/`.

---

## 11. Suggested order of work

1. `Powerup` (kinds, curses), `PowerupTable`, `data/balance/powerups.tres`; `Balance` and `MatchRules` grow their fields.
2. Pickup grids on `MatchState`, drops on crate destruction, destruction by flame, collection, caps. `test_powerups.gd`, including the draw-count pin.
3. Kick, then Toss, then Remote — each with its slice of `test_abilities.gd` before the next one starts. Kick is the one that touches movement, so it goes first while movement is fresh.
4. Curses, and the effective-value helpers they run through.
5. Kit loss and the scatter. `test_kit_loss.gd`.
6. Crate regeneration and the seal probe. `test_crate_regen.gd`.
7. `MatchRecord` and `test_match_record.gd` — pure, so it can be written any time and is a good break from the sim.
8. The overlay generalisation, the phases, the HUD, the views (pickups, sliding bombs, spawned crates).
9. Regenerate the golden replay (§9). Full headless pass: import, suite, smoke.
10. The stress scene's pickup field, then the hardware pass and the playtest.
