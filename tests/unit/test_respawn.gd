extends TestCase
## The death -> respawn cycle: countdown length, tile selection, tie-breaking,
## spawn protection, and the guarantee that it cannot deadlock.
## See docs/milestone-1-brief.md §6.3 and docs/technical-design.md §3a.

var state: MatchState

func before_each() -> void:
	var b: Balance = SimFixture.balance()
	b.flame_ticks = 10
	b.respawn_ticks = 5
	b.spawn_protect_ticks = 8
	state = SimFixture.open_state(b, 2)

## Steps one tick at a time and returns the tick number the first event of
## `kind` arrived on, or -1.
func _tick_of_first(kind: SimEvent.Kind, max_ticks: int) -> int:
	for _i in range(max_ticks):
		var events: Array[SimEvent] = Sim.step(state, SimFixture.blank_frames())
		if SimFixture.first_of(events, kind) != null:
			return state.tick
	return -1

func test_respawn_arrives_exactly_respawn_ticks_after_death() -> void:
	SimFixture.place(state, 0, Vector2i(1, 1))
	SimFixture.place(state, 1, Vector2i(5, 5))
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 1)

	var death_tick: int = _tick_of_first(SimEvent.Kind.PLAYER_DIED, 30)
	assert_eq(death_tick, 2, "the bomb did not go off when expected")
	var respawn_tick: int = _tick_of_first(SimEvent.Kind.PLAYER_RESPAWNED, 30)
	assert_eq(respawn_tick, death_tick + 5, "respawn was not exactly respawn_ticks after death")
	assert_true(state.players[1].alive, "the player did not come back")

func test_respawn_grants_spawn_protection() -> void:
	SimFixture.place(state, 0, Vector2i(1, 1))
	var victim: PlayerState = SimFixture.place(state, 1, Vector2i(5, 5))
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 1)
	var events: Array[SimEvent] = SimFixture.run_idle(state, 10)

	assert_true(victim.alive, "the player did not come back")
	assert_gt(victim.spawn_protect_ticks, 0, "no spawn protection was granted")
	var e: SimEvent = SimFixture.first_of(events, SimEvent.Kind.PLAYER_RESPAWNED)
	assert_eq(e.value, 8, "the event should report the protection granted")

func test_respawn_clears_death_bookkeeping() -> void:
	SimFixture.place(state, 0, Vector2i(1, 1))
	var victim: PlayerState = SimFixture.place(state, 1, Vector2i(5, 5))
	victim.bomb_exempt_tile = Vector2i(5, 5)
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 1)
	SimFixture.run_idle(state, 10)
	assert_false(victim.has_bomb_exemption(), "a stale bomb exemption survived the respawn")
	assert_eq(victim.respawn_ticks, 0, "respawn counter was not cleared")

func test_respawn_lands_on_a_designated_tile() -> void:
	SimFixture.place(state, 0, Vector2i(1, 1))
	var victim: PlayerState = SimFixture.place(state, 1, Vector2i(5, 5))
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 1)
	SimFixture.run_idle(state, 10)
	assert_true(state.arena_def.respawn_tiles.has(victim.tile()), "respawned somewhere undesignated: %s" % victim.tile())
	assert_eq(victim.pos, Sim.tile_centre(victim.tile()), "did not respawn on a tile centre")

func test_respawn_maximises_distance_from_danger() -> void:
	# Player 1 is dead and the only threat is player 0 in the top-left corner,
	# so the far corner is the right answer.
	var threat: Vector2i = Vector2i(1, 1)
	SimFixture.place(state, 0, threat)
	var victim: PlayerState = SimFixture.place(state, 1, Vector2i(5, 5))
	victim.alive = false
	victim.respawn_ticks = 1
	SimFixture.run_idle(state, 3)
	assert_true(victim.alive, "did not respawn")
	assert_eq(victim.tile(), Vector2i(23, 13), "did not pick the furthest designated tile")

func test_respawn_avoids_live_bombs() -> void:
	SimFixture.place(state, 0, Vector2i(22, 12))
	var victim: PlayerState = SimFixture.place(state, 1, Vector2i(5, 5))
	victim.alive = false
	victim.respawn_ticks = 1
	# A bomb sitting on the otherwise-best tile must take it out of the running.
	SimFixture.add_bomb(state, Vector2i(1, 1), 0, 500, 1)
	SimFixture.run_idle(state, 3)
	assert_true(victim.alive, "did not respawn")
	assert_ne(victim.tile(), Vector2i(1, 1), "respawned onto a live bomb")

func test_respawn_ties_break_by_tile_index() -> void:
	# A single threat dead centre leaves the four corners tied at distance 17.
	# The rule is "lowest tile index wins", which is (1,1).
	SimFixture.place(state, 0, Vector2i(12, 7))
	var victim: PlayerState = SimFixture.place(state, 1, Vector2i(5, 5))
	victim.alive = false
	victim.respawn_ticks = 1
	SimFixture.run_idle(state, 3)
	assert_eq(victim.tile(), Vector2i(1, 1), "tie was not broken by the lowest tile index")

func test_respawn_is_deterministic_for_the_same_situation() -> void:
	var picks: Array[Vector2i] = []
	for _run in range(3):
		var b: Balance = SimFixture.balance()
		b.respawn_ticks = 1
		var s: MatchState = SimFixture.open_state(b, 2)
		SimFixture.place(s, 0, Vector2i(9, 3))
		var victim: PlayerState = SimFixture.place(s, 1, Vector2i(5, 5))
		victim.alive = false
		victim.respawn_ticks = 1
		SimFixture.run_ticks(s, SimFixture.blank_frames(), 3)
		picks.append(victim.tile())
	assert_eq(picks[0], picks[1], "respawn choice varied between identical runs")
	assert_eq(picks[1], picks[2], "respawn choice varied between identical runs")

func test_respawn_waits_rather_than_deadlocking_when_everything_is_on_fire() -> void:
	# A screen entirely on fire has no legal respawn tile. The countdown holds
	# at zero and retries; because flames expire, this cannot deadlock.
	SimFixture.place(state, 0, Vector2i(1, 1))
	var victim: PlayerState = SimFixture.place(state, 1, Vector2i(5, 5))
	victim.alive = false
	victim.respawn_ticks = 1
	state.flame_ttl.fill(4)

	SimFixture.run_idle(state, 2)
	assert_false(victim.alive, "respawned into a wall of fire")
	assert_eq(victim.respawn_ticks, 0, "the countdown should be waiting at zero")

	SimFixture.run_idle(state, 6)
	assert_true(victim.alive, "never recovered once the flames went out")

func test_respawn_falls_back_when_every_designated_tile_is_taken() -> void:
	# Cover the fallback scan: fire on all nine designated tiles but nowhere
	# else. The player should still come back, just not on a designated tile.
	SimFixture.place(state, 0, Vector2i(1, 1))
	var victim: PlayerState = SimFixture.place(state, 1, Vector2i(5, 5))
	victim.alive = false
	victim.respawn_ticks = 1
	for t in state.arena_def.respawn_tiles:
		state.flame_ttl[state.arena.index(t)] = 30

	SimFixture.run_idle(state, 3)
	assert_true(victim.alive, "the fallback scan did not find a tile")
	assert_false(state.arena_def.respawn_tiles.has(victim.tile()), "respawned onto a burning designated tile")
	assert_eq(state.flame_ttl_at(victim.tile()), 0, "respawned into fire")
