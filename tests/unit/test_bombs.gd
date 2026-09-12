extends TestCase
## Bomb placement: capacity, the rising edge, one bomb per tile, radius capture,
## fuse timing to the tick, and spawn protection ending on a drop.
## See docs/milestone-1-brief.md §6.1.

var state: MatchState
var p: PlayerState

func before_each() -> void:
	state = SimFixture.open_state()
	p = SimFixture.place(state, 0, Vector2i(5, 5))
	SimFixture.park_others(state, 0)

func test_drops_a_bomb_on_the_players_tile() -> void:
	var events: Array[SimEvent] = SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	assert_eq(state.bombs.size(), 1, "no bomb placed")
	assert_eq(state.bombs[0].tile, Vector2i(5, 5), "bomb landed on the wrong tile")
	assert_eq(state.bombs[0].owner, 0, "bomb has the wrong owner")
	assert_eq(p.bombs_active, 1, "bomb budget not consumed")
	var e: SimEvent = SimFixture.first_of(events, SimEvent.Kind.BOMB_PLACED)
	assert_not_null(e, "no BOMB_PLACED event")
	assert_eq(e.tile, Vector2i(5, 5), "event tile")
	assert_eq(e.player, 0, "event player")

func test_holding_the_button_does_not_machine_gun() -> void:
	# Placement is rising-edge only, which is why prev_bomb is part of the
	# simulation state rather than a view-side detail.
	p.bomb_capacity = 8
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 60)
	assert_eq(state.bombs.size(), 1, "holding the bomb button placed more than one bomb")

func test_releasing_and_pressing_again_places_a_second_bomb() -> void:
	p.bomb_capacity = 2
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	SimFixture.run_idle(state, 1)
	# Move off the first tile, or the "one bomb per tile" rule declines it.
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 12)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	assert_eq(state.bombs.size(), 2, "a second press did not place a second bomb")

func test_capacity_is_respected() -> void:
	p.bomb_capacity = 1
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 12)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	assert_eq(state.bombs.size(), 1, "placed a bomb beyond the player's capacity")

func test_one_bomb_per_tile() -> void:
	p.bomb_capacity = 4
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	SimFixture.run_idle(state, 1)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	assert_eq(state.bombs.size(), 1, "stacked two bombs on one tile")

func test_radius_is_captured_at_drop_time() -> void:
	# Picking up a Bigger Blast (M3) must not retroactively enlarge a bomb whose
	# fuse is already burning.
	p.blast_radius = 2
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	p.blast_radius = 6
	assert_eq(state.bombs[0].radius, 2, "bomb radius changed after it was dropped")

func test_fuse_lasts_exactly_its_tick_count() -> void:
	var b: Balance = SimFixture.balance()
	b.bomb_fuse_ticks = 20
	state = SimFixture.open_state(b)
	SimFixture.place(state, 0, Vector2i(5, 5))
	SimFixture.park_others(state, 0)

	# Placed on tick 1, so it must be on the board for the whole of ticks 1..20
	# and go off on tick 21 — exactly `fuse` ticks after it landed.
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	SimFixture.run_idle(state, 19)
	assert_eq(state.tick, 20, "test drove the wrong number of ticks")
	assert_eq(state.bombs.size(), 1, "bomb went off early")
	var events: Array[SimEvent] = SimFixture.run_idle(state, 1)
	assert_eq(state.bombs.size(), 0, "bomb did not go off on its fuse tick")
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.BOMB_EXPLODED), 1, "no explosion event on the fuse tick")

func test_exploding_returns_the_bomb_to_the_budget() -> void:
	var b: Balance = SimFixture.balance()
	b.bomb_fuse_ticks = 5
	state = SimFixture.open_state(b)
	p = SimFixture.place(state, 0, Vector2i(5, 5))
	SimFixture.park_others(state, 0)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	assert_eq(p.bombs_active, 1, "budget not consumed")
	SimFixture.run_idle(state, 10)
	assert_eq(p.bombs_active, 0, "budget not returned after the bomb exploded")

func test_dropping_a_bomb_ends_spawn_protection() -> void:
	# Otherwise spawn protection is an offensive shield (game design §5.3).
	p.spawn_protect_ticks = 120
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	assert_eq(p.spawn_protect_ticks, 0, "spawn protection survived dropping a bomb")

func test_a_dead_player_cannot_place_bombs() -> void:
	p.alive = false
	p.respawn_ticks = 999      # keep them dead for the duration of the test
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 5)
	assert_eq(state.bombs.size(), 0, "a dead player placed a bomb")
	assert_false(p.alive, "the player came back and invalidated the test")

func test_holding_the_button_through_a_respawn_does_not_place() -> void:
	# The bomb edge is tracked even while dead, so coming back to life with A
	# held does not immediately drop a bomb on the respawn tile.
	var b: Balance = SimFixture.balance()
	b.respawn_ticks = 3
	state = SimFixture.open_state(b)
	p = SimFixture.place(state, 0, Vector2i(5, 5))
	SimFixture.park_others(state, 0)
	p.alive = false
	p.respawn_ticks = 3
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 12)
	assert_true(p.alive, "the player never came back")
	assert_eq(state.bombs.size(), 0, "a held button dropped a bomb on respawn")
