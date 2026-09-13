extends TestCase
## Crate regeneration: the timer, the exclusion rules, the cap, and the
## never-seal-a-player-in guarantee.
## See docs/milestone-3-brief.md §5 and docs/game-design.md §6.2.
##
## Several tests here reach for `Sim._regen_candidates` and `Sim._seals_a_player`
## directly. That is deliberate: driving the filter through a whole wave and then
## asserting on the board makes the test depend on which tiles the PRNG happened
## to choose, which is a flaky test dressed up as an integration test. The filter
## is where the rules live, so the filter is what gets asserted.

var state: MatchState

## A balance with a short regeneration interval, so a test does not have to
## simulate twenty seconds to see one wave.
func _balance(regen_ticks: int = 10, wave: int = 4) -> Balance:
	var b: Balance = SimFixture.balance()
	b.crate_regen_ticks = regen_ticks
	b.crate_regen_wave = wave
	return b

func before_each() -> void:
	state = SimFixture.open_state(_balance(), 2, 12345, SimFixture.no_drops())
	# Both players parked in one corner, out of the way of the interior.
	SimFixture.place(state, 0, Vector2i(1, 1))
	SimFixture.place(state, 1, Vector2i(1, 3))

# --- The timer ----------------------------------------------------------------

func test_a_wave_lands_on_the_exact_tick() -> void:
	# Appendix A.14 again: assert the tick, not "eventually".
	var events: Array[SimEvent] = SimFixture.run_idle(state, 9)
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.CRATE_SPAWNED), 0, "the wave landed early")
	events = SimFixture.run_idle(state, 1)
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.CRATE_SPAWNED), 4, "the wave did not land on its tick")

func test_the_timer_refills_and_keeps_waving() -> void:
	var events: Array[SimEvent] = SimFixture.run_idle(state, 30)
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.CRATE_SPAWNED), 12, "three waves should have landed in thirty ticks")

func test_a_wave_actually_puts_crates_on_the_board() -> void:
	SimFixture.run_idle(state, 10)
	assert_eq(state.arena.count_of(Arena.Tile.CRATE), 4, "the wave did not change the arena")

func test_a_zero_interval_disables_regeneration() -> void:
	# Which is both a test affordance and the fallback game design §6.2 names.
	state = SimFixture.open_state(_balance(0), 2, 12345, SimFixture.no_drops())
	SimFixture.place(state, 0, Vector2i(1, 1))
	var events: Array[SimEvent] = SimFixture.run_idle(state, 200)
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.CRATE_SPAWNED), 0, "regeneration ran with a zero interval")
	assert_eq(state.arena.count_of(Arena.Tile.CRATE), 0, "crates appeared with a zero interval")

# --- Exclusions ---------------------------------------------------------------

func _candidates() -> Array[String]:
	return SimFixture.tile_keys(Sim._regen_candidates(state))

func test_candidates_exclude_a_living_player_and_their_neighbours() -> void:
	# The rule that stops a crate landing in somebody's face.
	SimFixture.place(state, 0, Vector2i(7, 7))
	var keys: Array[String] = _candidates()
	assert_false(keys.has("7,7"), "a player's own tile is a candidate")
	for d in Sim.DIRS:
		var t: Vector2i = Vector2i(7, 7) + d
		assert_false(keys.has("%d,%d" % [t.x, t.y]), "the tile next to a player at %s is a candidate" % str(t))
	# Two tiles away is fair game, or the rule would clear half the arena.
	assert_true(keys.has("9,7"), "a tile two away from a player was excluded")

func test_candidates_exclude_bombs_flames_pickups_and_crates() -> void:
	SimFixture.add_bomb(state, Vector2i(9, 7), 0, 500, 1)
	SimFixture.add_flame(state, Vector2i(11, 7), 0, 600)
	SimFixture.add_pickup(state, Vector2i(13, 7), Powerup.Kind.BOMB)
	state.arena.set_at(Vector2i(15, 7), Arena.Tile.CRATE)
	var keys: Array[String] = _candidates()
	assert_false(keys.has("9,7"), "a bomb's tile is a candidate")
	assert_false(keys.has("11,7"), "a burning tile is a candidate")
	assert_false(keys.has("13,7"), "a pickup's tile is a candidate")
	assert_false(keys.has("15,7"), "an existing crate's tile is a candidate")
	assert_true(keys.has("17,7"), "setup: a clear tile should be a candidate")

func test_the_border_is_never_a_candidate() -> void:
	var keys: Array[String] = _candidates()
	assert_false(keys.has("0,0"), "the border wall is a candidate")
	assert_false(keys.has("12,0"), "the top wall is a candidate")
	assert_false(keys.has("24,14"), "the bottom-right wall is a candidate")

func test_a_corpse_does_not_reserve_space() -> void:
	# Exclusions are about *living* players: a corpse is not standing anywhere,
	# and a crate landing where someone died is part of the arena moving on.
	var p: PlayerState = SimFixture.place(state, 0, Vector2i(7, 7))
	p.alive = false
	p.respawn_ticks = 500
	var keys: Array[String] = _candidates()
	assert_true(keys.has("7,7"), "a dead player's tile was excluded")

func test_no_crate_ever_lands_on_or_beside_a_living_player() -> void:
	# The end-to-end version: a wave large enough to fill the arena, and nobody
	# gets a crate in the face.
	state = SimFixture.open_state(_balance(1, 400), 2, 999, SimFixture.no_drops())
	SimFixture.place(state, 0, Vector2i(7, 7))
	SimFixture.place(state, 1, Vector2i(13, 5))
	SimFixture.run_idle(state, 50)
	for target in state.players:
		if not target.active:
			continue
		var t: Vector2i = target.tile()
		assert_eq(state.arena.at(t), Arena.Tile.FLOOR, "a crate landed on a player at %s" % str(t))
		for d in Sim.DIRS:
			assert_eq(state.arena.at(t + d), Arena.Tile.FLOOR, "a crate landed next to a player at %s" % str(t + d))

# --- The cap ------------------------------------------------------------------

func test_the_cap_is_a_permille_of_the_eligible_interior() -> void:
	# 23 x 13 interior minus the 11 x 6 pillar lattice.
	assert_eq(state.arena.eligible_interior_count(), 233, "eligible interior count")
	state.balance.crate_cap_permille = 500
	assert_eq(state.crate_cap(), 116, "the cap did not follow the permille")

func test_the_cap_holds() -> void:
	state = SimFixture.open_state(_balance(1, 20), 2, 1234, SimFixture.no_drops())
	SimFixture.place(state, 0, Vector2i(1, 1))
	SimFixture.place(state, 1, Vector2i(1, 3))
	SimFixture.run_idle(state, 300)
	var cap: int = state.crate_cap()
	var count: int = state.arena.count_of(Arena.Tile.CRATE)
	assert_gt(cap, 0, "setup: the cap should be a real number")
	assert_le(count, cap, "regeneration went past the cap")
	assert_ge(count, cap - 2, "regeneration stopped well short of the cap")

func test_an_arena_already_over_the_cap_regenerates_nothing() -> void:
	# Which is the shipped case: the arena starts at ~70% crates and the cap is
	# 45%, so regeneration is a floor under the supply rather than a tide.
	state = SimFixture.generated_state(_balance(1, 6), 2, 5150, SimFixture.no_drops())
	assert_gt(state.arena.count_of(Arena.Tile.CRATE), state.crate_cap(), "setup: a fresh arena should start over the cap")
	var before: int = state.arena.count_of(Arena.Tile.CRATE)
	var events: Array[SimEvent] = SimFixture.run_idle(state, 5)
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.CRATE_SPAWNED), 0, "a full arena regenerated")
	assert_eq(state.arena.count_of(Arena.Tile.CRATE), before, "the crate count moved")

# --- The seal probe -----------------------------------------------------------

## A one-player arena that is solid everywhere except a corridor of `tiles`.
## With the player on the first tile and the second one adjacent to them, the
## only candidate a wave can ever draw is the last tile — so the seal probe is
## the only thing that decides what happens.
func _corridor(b: Balance, tiles: Array[Vector2i]) -> void:
	state = SimFixture.open_state(b, 1, 31337, SimFixture.no_drops())
	for y in range(1, state.arena.h - 1):
		for x in range(1, state.arena.w - 1):
			state.arena.set_at(Vector2i(x, y), Arena.Tile.HARD)
	for t in tiles:
		state.arena.set_at(t, Arena.Tile.FLOOR)
	SimFixture.place(state, 0, tiles[0])

func test_a_crate_that_would_seal_a_player_in_is_refused() -> void:
	_corridor(_balance(1, 4), [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)])
	assert_eq(SimFixture.tile_keys(Sim._regen_candidates(state)), ["7,5"] as Array[String],
		"setup: the corridor should offer exactly one candidate")
	SimFixture.run_idle(state, 1)
	assert_eq(state.arena.at(Vector2i(7, 5)), Arena.Tile.FLOOR,
		"a crate sealed a player into a two-tile pocket")
	assert_ge(Sim._reachable_free(state, Vector2i(5, 5), 99), state.balance.min_escape_tiles,
		"the player can no longer reach min_escape_tiles")

func test_the_same_crate_is_accepted_when_the_pocket_is_big_enough() -> void:
	# The probe is one number, and it is the number that decides.
	var b: Balance = _balance(1, 4)
	b.min_escape_tiles = 2
	_corridor(b, [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)])
	SimFixture.run_idle(state, 1)
	assert_eq(state.arena.at(Vector2i(7, 5)), Arena.Tile.CRATE,
		"a crate that leaves two free tiles was refused")

func test_a_refused_candidate_leaves_the_board_exactly_as_it_was() -> void:
	_corridor(_balance(1, 4), [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)])
	var before: PackedByteArray = state.arena.tiles.duplicate()
	SimFixture.run_idle(state, 1)
	assert_eq(state.arena.tiles, before, "a refused crate left a mark on the arena")

func test_the_probe_counts_free_tiles_not_bombs() -> void:
	# Bombs are temporary, and a player boxed in by a bomb they are standing next
	# to is a normal, survivable situation.
	_corridor(_balance(), [Vector2i(5, 5), Vector2i(6, 5)])
	SimFixture.add_bomb(state, Vector2i(6, 5), 0, 500, 1)
	assert_eq(Sim._reachable_free(state, Vector2i(5, 5), 99), 2, "a bomb was treated as a wall")

func test_a_dead_player_cannot_be_sealed_in() -> void:
	var b: Balance = _balance(1, 4)
	_corridor(b, [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)])
	state.players[0].alive = false
	state.players[0].respawn_ticks = 500
	SimFixture.run_idle(state, 1)
	# Nobody living to seal in, so the crate lands. The corpse will respawn
	# somewhere else entirely — respawn tile selection does not use this pocket.
	assert_eq(state.arena.at(Vector2i(7, 5)), Arena.Tile.CRATE, "the probe blocked a wave for a corpse")

# --- Determinism ---------------------------------------------------------------

func test_a_wave_draws_once_per_crate_it_tries_to_place() -> void:
	# Technical design §3a: candidates are filtered *before* the draw, so the
	# number of PRNG calls cannot depend on how many tiles were rejected.
	state = SimFixture.open_state(_balance(1, 4), 2, 8080, SimFixture.no_drops())
	SimFixture.place(state, 0, Vector2i(1, 1))
	SimFixture.place(state, 1, Vector2i(23, 13))
	var before: SimRng = state.rng.clone()
	SimFixture.run_idle(state, 1)
	for _i in range(4):
		before.next_u32()
	assert_eq(state.rng.state, before.state, "a four-crate wave did not cost exactly four draws")

func test_rejected_candidates_do_not_cost_extra_draws() -> void:
	# The same wave with a pile of excluded tiles added. The draw count must not
	# move, which is the whole reason the filter runs first.
	state = SimFixture.open_state(_balance(1, 4), 2, 8080, SimFixture.no_drops())
	SimFixture.place(state, 0, Vector2i(1, 1))
	SimFixture.place(state, 1, Vector2i(23, 13))
	for x in range(3, 20):
		SimFixture.add_flame(state, Vector2i(x, 7), 0, 600)
		SimFixture.add_pickup(state, Vector2i(x, 9), Powerup.Kind.BOMB)
	var before: SimRng = state.rng.clone()
	SimFixture.run_idle(state, 1)
	for _i in range(4):
		before.next_u32()
	assert_eq(state.rng.state, before.state, "a heavily filtered wave cost a different number of draws")

func test_the_same_seed_regenerates_the_same_crates() -> void:
	var fingerprints: Array[String] = []
	for _run in range(2):
		state = SimFixture.open_state(_balance(5, 6), 3, 606, SimFixture.no_drops())
		SimFixture.place(state, 0, Vector2i(1, 1))
		SimFixture.run_idle(state, 120)
		fingerprints.append(state.fingerprint())
	assert_eq(fingerprints[0], fingerprints[1], "regeneration diverged between two identical runs")
