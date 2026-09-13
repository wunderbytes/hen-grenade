# Milestone 3 — Completion Notes

> Status: **code complete and headless-verified; the playtest, which is the exit criterion, is still owed.** The economy is in — drops, the full table, caps, Kick, Toss, Remote, the four Dud variants, kit loss and the scatter, crate regeneration with its exclusion rules and the never-seal-in probe, best-of-3 with a scoreboard and a winner screen — and 239 tests plus two golden replays are green with a clean scene smoke. What remains cannot be faked and cannot be tested: four people on a sofa playing a full best-of-3 and saying whether it is fun, and whether the three open design questions now have answers.

- **Date:** 2026-09-13
- **Brief:** [milestone-3-brief.md](../milestone-3-brief.md)
- **Previous:** [M2 completion notes](m2-completion.md)

## Implemented

1. **`Powerup` and `PowerupTable`** (`src/sim/`) — the kind and curse vocabulary, and the drop rate plus eight weights as a `Resource` at `data/balance/powerups.tres`, named in the technical design since before M1 and finally real.
2. **Pickups as two flat byte grids** on `MatchState` (`pickup_kind`, `pickup_data`) — the same representation as flames, for the same reasons: one pickup per tile falls out of the representation, tile lookup is O(1), and a twelve-item kit scatter allocates nothing.
3. **Drops, collection, and destruction.** A destroyed crate rolls for a drop; the drop survives the flame that revealed it and dies to the next one; a capped power-up is still consumed.
4. **Kick** — walking into a bomb slides it, one whole tile every `kick_ticks_per_tile`. It stops at walls, crates and other bombs, passes under players, and detonates on a burning tile.
5. **Toss** — B lobs the bomb underfoot two tiles over anything in between, falling back toward the thrower if the target is occupied, never forward.
6. **Remote** — fuse-less bombs that wait for the button, served at the top of the bomb phase so every detonation in the game still happens in one place. Losing Remote arms whatever it left behind.
7. **The Dud** and its four variants, as effective-value overrides that never write to the loadout.
8. **Kit loss on death** — one tunable (`kit_loss_permille`), measured from the starting loadout, with an ordered PRNG-free scatter that will not place anything into fire.
9. **Crate regeneration** — timed waves, the exclusion filter applied *before* the draw, a bounded flood-fill seal probe, and a crate cap expressed as a permille of the eligible interior.
10. **`MatchRecord`** (`src/app/match_record.gd`) — best-of-3, draws, the decider, the round ceiling and its tie-breaks, as a plain `RefCounted`. **17 tests.**
11. **`MatchRules`** (`data/balance/match.tres`) — a separate resource from `Balance`, because match-flow numbers must not be in the replay fingerprint.
12. **`round_overlay.gd`** — M2's two-mode pause overlay generalised to four modes and a self-sizing panel: pause menu, reconnect notice, scoreboard, winner screen. It also reports its own geometry for the smoke check.
13. **Five phases** in `MatchScene`: `RUNNING`, `PAUSED`, `RECONNECT`, `SCOREBOARD`, `MATCH_OVER`. The scoreboard advances itself and raises the reconnect notice like a running round does.
14. **HUD cards carrying the whole kit** — score, kills/deaths, bombs, blast, speed steps, abilities, the curse and its countdown, the respawn counter and the round-win tally, all in the one `Label` a card already had.
15. **Pickups and Remote bombs in the view**, in two batched passes and a steady mark respectively; `ArenaView.set_crate()` for a landing wave, on the same single-cell path as a destroyed one.
16. **`-- --measure`** in `main.gd` — peak draw calls, objects and worst frame time for the match and stress scenes, which refuses to run headless rather than reporting the dummy driver's zeroes.
17. **The stress scene grew a 56-pickup field** with a `K` toggle, because pickups are a new per-frame draw and M0's number was measured without them.
18. **Two golden replays**, both regenerated, and the generator now presses the action button and reports the economy it recorded.

## Verification performed

| Check | Result |
|---|---|
| `--headless --import --quit` | clean |
| Test suite | **17 suites, 239 tests, 0 failures**, exit 0 |
| New suites | `test_powerups` 20, `test_abilities` 27, `test_kit_loss` 13, `test_crate_regen` 20, `test_match_record` 17 |
| M1/M2 suites unchanged and still green | 141 of the 239, **not one edited to make it pass** |
| Golden replays | `golden_01` (shipped density) and `golden_02` (thin, so regeneration fires) both reproduce their fingerprints and trace digests |
| Scene smoke | match / lobby / sandbox / stress load, step and draw clean; full 7200-tick round; four overlay modes drawn; phase machine and overlay geometry self-checks clean |
| Draw calls, match scene (Windows/OpenGL) | **11**, against a budget of 20 — *down* from M1's 16 |
| Draw calls, stress scene with 56 pickups | **52 with pickups on, 52 with them off** |

**Both new self-checks were mutation-checked, not just run.** Making `_advance_match()` never reach `MATCH_OVER` was confirmed to print `a finished match started another round` *and* `the winner screen advanced on its own`, and exit non-zero. Shrinking the overlay panel to 140 px was confirmed to report the pause menu's and the reconnect notice's footers as not fitting. Without those two checks a green smoke would have said nothing about either the match flow or a panel that now sizes itself.

## Decisions taken during M3

- **Toss and Remote are mutually exclusive; the last one picked up wins.** There is one action button, and the alternatives were a tap-versus-hold discrimination in a twitch game or an arbitrary priority rule. B is your ability button and you have one ability — which also makes taking a Toss while holding Remote a real decision rather than a free upgrade. Game design §6 amended.
- **Toss fires on the press, not on a hold-and-release.** The design said hold-and-release, which is the classic behaviour because there the hold charges distance; here the distance is a fixed two tiles, so a hold buys a wait and no decision. Recorded as a deviation to raise at the playtest.
- **A curse dies with you.** Death already costs half your kit, and the glued-at-max-speed variant carried through a respawn is a death spiral. It also scatters nothing: a Dud dropped where you died is a gift to your killer in the shape of a trap.
- **A capped power-up is still consumed.** Leaving it for someone who can use it is kinder and wrong: a pickup nobody can pick up is a permanently blocked tile that looks like a bug.
- **No new autoload for the match record.** M2's notes assumed best-of-3 needed something that survives a scene change. It does not: `MatchScene` plays round after round without one, and the only transitions that leave it are exactly the ones that should end a match. The record is a pure tested object owned by the scene, and there is one less thing that cannot be unit-tested.
- **`MatchRules` is a separate resource from `Balance`.** Match-flow numbers are read above the simulation, so they must not be in the replay's rules fingerprint — otherwise retuning the scoreboard duration invalidates every committed replay. The alternative was fields deliberately excluded from their own resource's fingerprint, which is a trap for whoever adds the next one.
- **A kicked bomb stays tile-quantised.** Every rule that touches a bomb indexes it by tile; a sub-tile position would mean revisiting solidity, chains and blast rays for one power-up. The bomb carries `slide_dir` and `slide_ticks`, so M4 can interpolate in the view without the rules learning about it.
- **A bomb that arrives on a burning tile detonates**, credited to the flame's owner. M1 could not hit this case; M3 gave bombs two ways to move, so "a bomb caught in a blast detonates" had to keep meaning what it says.
- **Crate drops are rolled after the whole chain resolves**, not as each crate breaks — otherwise a second ray of the same chain reaching the same tile burns off the drop the first one just made, and one explosion eats its own reward.
- **The crate cap is a floor under the supply, not a tide.** 45% of the eligible interior against a ~70% start means regeneration does nothing until the round has genuinely thinned out. A wave arriving while the arena is still a maze would be pure interference, which is exactly what open design question 4 is worried about.
- **Two golden replays, because one round could not cover everything.** The generator's random-walk input does not thin the shipped arena below the regeneration cap inside a minute, so `golden_01` would have pinned the new rules while exercising the one new PRNG consumer not at all. `golden_02` starts thin. A golden replay that exercises nothing it pins looks like coverage and is worth nothing, so `test_replay.gd` now asserts the recorded rounds contain a drop, a collection and a wave.

## Fixed along the way

- **`SimRng.next_below(n)` spends no draw at `n <= 1`**, which is wrong anywhere the draw *count* is the contract — and M3 added two such places. A power-up table tuned down to one kind, or an arena down to its last candidate tile, would have silently shifted every subsequent value. Found by the draw-count test failing on a single-weight fixture table, which is precisely the test that exists to find it. `next_index(n)` is the variant that always spends one; the weighted pick and the regeneration wave use it.
- **`_regen_wave` scanned the whole grid before checking the cap**, every wave, for the entire second half of a round in which it could never place anything. Now it returns first.
- **The crate-regeneration exclusion tests were flaky by construction** on the first pass: they ran a whole wave and asserted on the board, which depends on which tiles the PRNG happened to draw. They now assert on `_regen_candidates` and `_seals_a_player` directly, with one end-to-end check that only asserts an absence. A flaky test dressed up as an integration test is worse than no test.
- **The seal-probe test could not be made deterministic through a wave** either, so the fixture builds a corridor in a solid arena where exactly one candidate exists. The same crate is then asserted refused at `min_escape_tiles = 3` and accepted at 2, which tests the number rather than the coincidence.

## Deferred / still owed

- **The playtest, which is the exit criterion.** Four people, a full best-of-3, on Windows and on the reference Pi 400, with answers to the three questions the roadmap names: does the 23 × 13 interior play too large, does a death cost the right amount, and does crate regeneration feel fair or feel like interference. The table is in [m0-pi400.md](../measurements/m0-pi400.md).
- **The Pi 400 frame-time rows**, still. M3 is the first milestone to add a per-frame draw to the arena, and although it measures at zero additional draw calls on Windows, the p99 on a VideoCore VI is the number that decides anything and it has never been transcribed. The `K` toggle in the stress scene exists so the pickup field can be bisected on the day.
- **The hardware passes owed from M0 and M2** are unchanged and still owed.
- **The regeneration landing telegraph** (game design §6.2) — the sim emits `CRATE_SPAWNED` and the view sets one cell. The animation is M4's, and it belongs in the view.
- **Kicked-bomb interpolation.** A bomb steps a whole tile at ~10 tiles/s, which is visibly steppy in programmer art. `slide_dir` and `slide_ticks` are on the bomb for whoever smooths it in M4.
- **Audio for everything M3 added** — pickup, curse, kick, toss, remote detonation, a crate landing. M4.

## Open, not worth blocking on

- **`--headless --write-movie` segfaults in 4.7.2** (signal 11, before the first frame, with any output path). M2 used it to catch an overlay that never drew; M3 needed it to check an overlay that draws in the *wrong place*, and could not. The replacement — the overlay reporting its own geometry — is better than the screenshot was, because it runs in CI. Recorded as [Appendix A.17](../technical-design.md); not investigated further, because a working alternative exists and the engine bug is not ours.
- **The `1 resources still in use at exit` line from M2 is still there**, still `input_frame.gd`, still not growing, still unexplained. M3 changed nothing about it.

## Notes for M3.5

- **The namesake mode is designed, not implied.** [milestone-3.5-brief.md](../milestone-3.5-brief.md) is the executable spec: a second `GameMode` the sim fingerprints, a lobby cycle that does not steal Y/X/Back, a token that is not a power-up, and a hard rule that deathmatch `create()` spends no extra PRNG draws. Do not start M4 until that brief is either implemented or explicitly dropped.
- Deathmatch goldens from this milestone are the regression for M3.5. If their *state* hashes move, FFA broke; regenerating them to hide that is the failure mode the M3 brief already named.

## Notes for M4

- **The theme gate still stands.** M3.5 does not decide a setting or a final title; it adds a mechanical namesake on programmer art (a comb silhouette and a gold disc). The roadmap makes theme an explicit M4 entry gate and nothing in M0–M3.5 depended on it.
- `round_overlay.gd` is now the shared panel M2's notes asked for, and the options screen is its fifth mode rather than a new file. It already sizes itself, and `geometry_problems()` will check a fifth mode for free. Hen-mode scoreboard strings (`94s`, `HEN GRENADE`) are a sixth geometry pass in M3.5, not a new overlay.
- **Pickups need eight distinguishable sprites, and the readability pillar is the constraint.** The programmer art uses hue plus inner-square size, because hue alone fails the colourblind-safety requirement in game design §8 — whatever replaces it has to keep a shape difference, not just a palette.
- **The effects budget has more room than expected.** 11 draw calls against 20 in a live round, and 56 pickups measured at zero additional calls. The lesson to carry in is the one in Appendix A.12: the cost of a class of entity is the number of *passes* it needs, not the number of instances.
- `EntityView` draws a Remote bomb differently because a fuse-less bomb has no pulse to derive. Any M4 telegraphing pass has to keep that distinction — a bomb that is waiting rather than counting is important information.

## Notes for M5

- **The danger map has more to model than M1 implied.** A bot has to reason about a kicked bomb in motion (`slide_dir`, `slide_ticks`), a Remote bomb that will never go off on its own, and a curse that has inverted its own controls. The last one is the interesting case: a `REVERSED` bot that does not know it is cursed will walk into its own bombs.
- Pickups are a first-class goal now, and `MatchState.pickup_at()` is O(1), so "path to the nearest power-up" and "go for a dropped kit after a kill" are cheap to evaluate.
- **Hen Grenade (M3.5) adds three bot goals the danger map does not cover:** path to the token, hunt the living Hen, and flee as the Hen (no bombs, half speed). They wait for M5; the M2 placeholder will wander into this mode exactly as badly as it wanders into deathmatch.
- `BotSource` is still the M2 placeholder. M5 starts from a danger map, not from that file.
