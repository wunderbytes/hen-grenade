extends TestCase
## Drops, collection, caps, and the PRNG-draw invariant behind all of it.
## See docs/milestone-3-brief.md §3 and docs/game-design.md §6.

var state: MatchState

func before_each() -> void:
	state = SimFixture.open_state(SimFixture.balance(), 2)

# --- Collection and effects --------------------------------------------------

func test_walking_onto_a_pickup_takes_it_on_the_same_tick() -> void:
	var p: PlayerState = SimFixture.place(state, 0, Vector2i(5, 5))
	SimFixture.park_others(state, 0)
	SimFixture.add_pickup(state, Vector2i(6, 5), Powerup.Kind.BOMB)
	# 256 units to cross a tile at 15 units/tick: 18 ticks gets the centre over.
	var events: Array[SimEvent] = SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 18)
	assert_eq(p.tile(), Vector2i(6, 5), "setup: the player should have reached the pickup")
	assert_false(state.has_pickup_at(Vector2i(6, 5)), "the pickup was not taken")
	assert_eq(p.bomb_capacity, 2, "Extra Bomb did not apply")
	var taken: SimEvent = SimFixture.first_of(events, SimEvent.Kind.PICKUP_TAKEN)
	assert_not_null(taken, "no PICKUP_TAKEN event")
	assert_eq(taken.player, 0, "event subject")
	assert_eq(taken.value, Powerup.Kind.BOMB, "event kind")

func test_a_dead_player_collects_nothing() -> void:
	var p: PlayerState = SimFixture.place(state, 0, Vector2i(5, 5))
	p.alive = false
	p.respawn_ticks = 500
	SimFixture.add_pickup(state, Vector2i(5, 5), Powerup.Kind.BOMB)
	SimFixture.run_idle(state, 5)
	assert_true(state.has_pickup_at(Vector2i(5, 5)), "a corpse collected a power-up")
	assert_eq(p.bomb_capacity, 1, "a dead player gained a bomb")

func test_each_kind_does_its_one_thing() -> void:
	var cases: Array = [
		[Powerup.Kind.BOMB, "bomb_capacity", 2],
		[Powerup.Kind.BLAST, "blast_radius", 2],
		[Powerup.Kind.KICK, "has_kick", true],
		[Powerup.Kind.TOSS, "ability", Powerup.Kind.TOSS],
		[Powerup.Kind.REMOTE, "ability", Powerup.Kind.REMOTE],
	]
	for case in cases:
		state = SimFixture.open_state(SimFixture.balance(), 2)
		var p: PlayerState = SimFixture.place(state, 0, Vector2i(5, 5))
		SimFixture.park_others(state, 0)
		SimFixture.add_pickup(state, Vector2i(5, 5), case[0])
		SimFixture.run_idle(state, 1)
		assert_eq(p.get(case[1]), case[2], "%s did not apply" % Powerup.short_name(case[0]))

func test_speed_up_adds_a_step() -> void:
	var p: PlayerState = SimFixture.place(state, 0, Vector2i(5, 5))
	SimFixture.park_others(state, 0)
	SimFixture.add_pickup(state, Vector2i(5, 5), Powerup.Kind.SPEED)
	SimFixture.run_idle(state, 1)
	assert_eq(p.speed_steps, 1, "the step was not counted")
	assert_eq(p.speed_units, state.balance.move_speed_units + state.balance.speed_step_units, "speed did not rise by one step")

func test_jackpot_goes_straight_to_the_cap() -> void:
	var p: PlayerState = SimFixture.place(state, 0, Vector2i(5, 5))
	SimFixture.park_others(state, 0)
	SimFixture.add_pickup(state, Vector2i(5, 5), Powerup.Kind.JACKPOT)
	SimFixture.run_idle(state, 1)
	assert_eq(p.blast_radius, state.balance.max_blast_radius, "Jackpot did not max the radius")

func test_toss_and_remote_replace_each_other() -> void:
	var p: PlayerState = SimFixture.place(state, 0, Vector2i(5, 5))
	SimFixture.park_others(state, 0)
	SimFixture.add_pickup(state, Vector2i(5, 5), Powerup.Kind.REMOTE)
	SimFixture.run_idle(state, 1)
	assert_eq(p.ability, Powerup.Kind.REMOTE, "setup: Remote should be held")
	SimFixture.add_pickup(state, Vector2i(5, 5), Powerup.Kind.TOSS)
	SimFixture.run_idle(state, 1)
	# One action button, one ability slot (brief §4.3).
	assert_eq(p.ability, Powerup.Kind.TOSS, "Toss did not replace Remote")

func test_dropping_remote_for_toss_arms_its_orphaned_bombs() -> void:
	# Otherwise those bombs are permanent solid blocks owned by nobody.
	var p: PlayerState = SimFixture.place(state, 0, Vector2i(5, 5))
	SimFixture.park_others(state, 0)
	p.ability = Powerup.Kind.REMOTE
	p.bomb_capacity = 2
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	assert_eq(state.bombs.size(), 1, "setup: a bomb should have been placed")
	assert_true(state.bombs[0].remote, "setup: a Remote holder's bomb has no fuse")

	SimFixture.add_pickup(state, Vector2i(5, 5), Powerup.Kind.TOSS)
	SimFixture.run_idle(state, 1)
	assert_false(state.bombs[0].remote, "the orphaned bomb was left without a fuse")
	assert_eq(state.bombs[0].fuse_ticks, state.balance.bomb_fuse_ticks - 1,
		"the re-armed bomb should have a full fuse, less this tick's age")

# --- Caps --------------------------------------------------------------------

func test_a_capped_power_up_is_still_consumed() -> void:
	# Leaving it on the floor would be kinder and is the wrong call: a pickup
	# nobody can pick up is a blocked tile that looks like a bug (brief §3.1).
	var p: PlayerState = SimFixture.place(state, 0, Vector2i(5, 5))
	SimFixture.park_others(state, 0)
	p.bomb_capacity = state.balance.max_bomb_capacity
	SimFixture.add_pickup(state, Vector2i(5, 5), Powerup.Kind.BOMB)
	SimFixture.run_idle(state, 1)
	assert_false(state.has_pickup_at(Vector2i(5, 5)), "the capped pickup was left on the floor")
	assert_eq(p.bomb_capacity, state.balance.max_bomb_capacity, "the cap was exceeded")

func test_every_stacking_stat_stops_at_its_cap() -> void:
	var p: PlayerState = SimFixture.place(state, 0, Vector2i(5, 5))
	SimFixture.park_others(state, 0)
	for _i in range(20):
		SimFixture.add_pickup(state, Vector2i(5, 5), Powerup.Kind.BOMB)
		SimFixture.run_idle(state, 1)
		SimFixture.add_pickup(state, Vector2i(5, 5), Powerup.Kind.BLAST)
		SimFixture.run_idle(state, 1)
		SimFixture.add_pickup(state, Vector2i(5, 5), Powerup.Kind.SPEED)
		SimFixture.run_idle(state, 1)
	assert_eq(p.bomb_capacity, state.balance.max_bomb_capacity, "bomb cap")
	assert_eq(p.blast_radius, state.balance.max_blast_radius, "blast cap")
	assert_eq(p.speed_units, state.balance.max_speed_units, "speed cap")

# --- Drops -------------------------------------------------------------------

func test_a_destroyed_crate_can_drop_a_power_up() -> void:
	state = SimFixture.open_state(SimFixture.balance(), 2, 12345, SimFixture.always_drops(Powerup.Kind.BOMB))
	SimFixture.place(state, 0, Vector2i(1, 1))
	SimFixture.park_others(state, 0)
	state.arena.set_at(Vector2i(6, 5), Arena.Tile.CRATE)
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 2)
	var events: Array[SimEvent] = SimFixture.run_idle(state, 2)

	assert_eq(state.arena.at(Vector2i(6, 5)), Arena.Tile.FLOOR, "setup: the crate should be gone")
	assert_eq(state.pickup_at(Vector2i(6, 5)), Powerup.Kind.BOMB, "no drop on the crate's tile")
	var spawned: SimEvent = SimFixture.first_of(events, SimEvent.Kind.PICKUP_SPAWNED)
	assert_not_null(spawned, "no PICKUP_SPAWNED event")
	assert_eq(spawned.player, -1, "a crate drop has no losing player")

func test_a_drop_survives_the_flame_that_revealed_it() -> void:
	# The blast that broke the crate lights that tile, so the drop has to be
	# written after the chain rather than during it (brief §3.2).
	state = SimFixture.open_state(SimFixture.balance(), 2, 12345, SimFixture.always_drops(Powerup.Kind.BLAST))
	SimFixture.place(state, 0, Vector2i(1, 1))
	SimFixture.park_others(state, 0)
	state.arena.set_at(Vector2i(6, 5), Arena.Tile.CRATE)
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 2)
	SimFixture.run_idle(state, 2)
	assert_true(state.flame_ttl_at(Vector2i(6, 5)) > 0, "setup: the crate's tile should be on fire")
	assert_eq(state.pickup_at(Vector2i(6, 5)), Powerup.Kind.BLAST, "the drop was burnt by its own blast")

func test_a_later_blast_destroys_a_pickup() -> void:
	SimFixture.place(state, 0, Vector2i(1, 1))
	SimFixture.park_others(state, 0)
	SimFixture.add_pickup(state, Vector2i(6, 5), Powerup.Kind.SPEED)
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 2)
	var events: Array[SimEvent] = SimFixture.run_idle(state, 2)
	assert_false(state.has_pickup_at(Vector2i(6, 5)), "the pickup survived a blast")
	var gone: SimEvent = SimFixture.first_of(events, SimEvent.Kind.PICKUP_DESTROYED)
	assert_not_null(gone, "no PICKUP_DESTROYED event")
	assert_eq(gone.value, Powerup.Kind.SPEED, "the event should name what was lost")

func test_a_crate_drop_can_be_switched_off_entirely() -> void:
	state = SimFixture.open_state(SimFixture.balance(), 2, 12345, SimFixture.no_drops())
	SimFixture.place(state, 0, Vector2i(1, 1))
	SimFixture.park_others(state, 0)
	state.arena.set_at(Vector2i(6, 5), Arena.Tile.CRATE)
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 2)
	SimFixture.run_idle(state, 2)
	assert_eq(state.pickup_count(), 0, "a zero drop rate still dropped something")

# --- The draw invariant ------------------------------------------------------

func test_destroying_a_crate_costs_exactly_three_draws() -> void:
	# Brief §2, Rule A. A conditional draw would make the PRNG sequence depend on
	# its own outcomes — reproducible, but the shape of bug that survives a green
	# golden replay until the day someone retunes a weight.
	for table in [SimFixture.no_drops(), SimFixture.always_drops(Powerup.Kind.BOMB), SimFixture.always_drops(Powerup.Kind.DUD)]:
		state = SimFixture.open_state(SimFixture.balance(), 2, 999, table)
		SimFixture.place(state, 0, Vector2i(1, 1))
		SimFixture.park_others(state, 0)
		state.arena.set_at(Vector2i(6, 5), Arena.Tile.CRATE)
		SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 2)

		var before: SimRng = state.rng.clone()
		SimFixture.run_idle(state, 2)
		for _i in range(3):
			before.next_u32()
		assert_eq(state.rng.state, before.state,
			"one destroyed crate should advance the PRNG exactly three times")

func test_a_tick_with_no_crate_destroyed_draws_nothing() -> void:
	SimFixture.place(state, 0, Vector2i(5, 5))
	SimFixture.park_others(state, 0)
	var before: int = state.rng.state
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT, true), 60)
	assert_eq(state.rng.state, before, "something consumed a draw on a quiet tick")

func test_two_crates_in_one_blast_cost_six_draws() -> void:
	state = SimFixture.open_state(SimFixture.balance(), 2, 4242, SimFixture.no_drops())
	SimFixture.place(state, 0, Vector2i(1, 1))
	SimFixture.park_others(state, 0)
	state.arena.set_at(Vector2i(6, 5), Arena.Tile.CRATE)
	state.arena.set_at(Vector2i(4, 5), Arena.Tile.CRATE)
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 2)

	var before: SimRng = state.rng.clone()
	SimFixture.run_idle(state, 2)
	for _i in range(6):
		before.next_u32()
	assert_eq(state.rng.state, before.state, "two crates should cost six draws")

# --- The table ---------------------------------------------------------------

func test_the_shipped_table_can_produce_every_kind() -> void:
	# A weight of zero somewhere in the table would silently remove a power-up
	# from the game, and the only place that shows up is a playtest where nobody
	# ever sees a Remote.
	var table: PowerupTable = PowerupTable.new()
	var rng: SimRng = SimRng.new(7)
	var seen: Array[int] = []
	for _i in range(4000):
		var kind: int = table.pick(rng)
		if not seen.has(kind):
			seen.append(kind)
	for kind in range(Powerup.Kind.BOMB, Powerup.Kind.DUD + 1):
		assert_true(seen.has(kind), "%s never came up in 4000 draws" % Powerup.short_name(kind))

func test_the_table_spends_exactly_one_draw_per_pick() -> void:
	var table: PowerupTable = PowerupTable.new()
	var rng: SimRng = SimRng.new(11)
	var mirror: SimRng = SimRng.new(11)
	for _i in range(50):
		table.pick(rng)
		mirror.next_u32()
	assert_eq(rng.state, mirror.state, "a pick did not cost exactly one draw")

func test_an_all_zero_table_still_spends_its_draw() -> void:
	var table: PowerupTable = PowerupTable.new()
	table.weight_bomb = 0
	table.weight_blast = 0
	table.weight_speed = 0
	table.weight_kick = 0
	table.weight_toss = 0
	table.weight_remote = 0
	table.weight_jackpot = 0
	table.weight_dud = 0
	var rng: SimRng = SimRng.new(3)
	var mirror: SimRng = SimRng.new(3)
	assert_eq(table.pick(rng), Powerup.Kind.NONE, "an empty table should pick nothing")
	mirror.next_u32()
	assert_eq(rng.state, mirror.state, "an empty table must still spend the draw")

func test_the_fingerprint_moves_when_the_table_is_retuned() -> void:
	var a: PowerupTable = PowerupTable.new()
	var b: PowerupTable = PowerupTable.new()
	assert_eq(a.fingerprint(), b.fingerprint(), "two default tables should agree")
	b.weight_remote += 1
	assert_ne(a.fingerprint(), b.fingerprint(), "a re-weighted table kept its fingerprint")
