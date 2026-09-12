extends TestCase
## Chain reactions and flame ownership through them.
## See docs/milestone-1-brief.md §6.2.
##
## The ownership rule under test is the one that resolved a contradiction
## between game design §5.2 and technical design §3: **ownership propagates from
## whoever started the chain.** Set off someone else's bomb and the kills are
## yours.

var state: MatchState

func before_each() -> void:
	var b: Balance = SimFixture.balance()
	b.flame_ticks = 30
	state = SimFixture.open_state(b, 2)
	SimFixture.place(state, 0, Vector2i(1, 1))
	SimFixture.place(state, 1, Vector2i(1, 3))

func test_a_bomb_in_a_blast_detonates_on_the_same_tick() -> void:
	# Trigger has a 1-tick fuse; the victim has a long one and should still go
	# off in the same step.
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 2)
	SimFixture.add_bomb(state, Vector2i(7, 5), 1, 500, 1)
	var events: Array[SimEvent] = SimFixture.run_idle(state, 2)
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.BOMB_EXPLODED), 2, "the chain did not propagate on the same tick")
	assert_eq(state.bombs.size(), 0, "a chained bomb was left on the board")

func test_ownership_propagates_from_the_chain_starter() -> void:
	# Player 0 sets off player 1's bomb. Every flame in the chain — including
	# the ones player 1's bomb produced — belongs to player 0.
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 2)
	SimFixture.add_bomb(state, Vector2i(7, 5), 1, 500, 1)
	SimFixture.run_idle(state, 2)
	assert_eq(state.flame_owner_at(Vector2i(5, 5)), 0, "trigger tile owner")
	assert_eq(state.flame_owner_at(Vector2i(7, 5)), 0, "the chained bomb's own tile should be credited to the starter")
	assert_eq(state.flame_owner_at(Vector2i(8, 5)), 0, "flame beyond the chained bomb should be credited to the starter")
	assert_eq(state.flame_owner_at(Vector2i(7, 4)), 0, "the chained bomb's side flame should be credited to the starter")

func test_a_bomb_on_its_own_fuse_owns_its_blast() -> void:
	SimFixture.add_bomb(state, Vector2i(9, 9), 1, 1, 1)
	SimFixture.run_idle(state, 2)
	assert_eq(state.flame_owner_at(Vector2i(9, 9)), 1, "an uncoached bomb should own its own flames")

func test_chained_bomb_uses_its_own_radius() -> void:
	# Ownership propagates; reach does not. A chained bomb still explodes with
	# the radius it was dropped with.
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 1)
	SimFixture.add_bomb(state, Vector2i(6, 5), 1, 500, 3)
	SimFixture.run_idle(state, 2)
	assert_gt(state.flame_ttl_at(Vector2i(9, 5)), 0, "the chained bomb did not use its own radius 3")
	assert_eq(state.flame_ttl_at(Vector2i(10, 5)), 0, "the chained bomb exceeded its radius")

func test_a_crate_shields_a_bomb_behind_it() -> void:
	state.arena.set_at(Vector2i(6, 5), Arena.Tile.CRATE)
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 4)
	SimFixture.add_bomb(state, Vector2i(7, 5), 1, 500, 1)
	var events: Array[SimEvent] = SimFixture.run_idle(state, 2)
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.BOMB_EXPLODED), 1, "the blast reached through a crate")
	assert_eq(state.bombs.size(), 1, "the shielded bomb should still be on the board")
	assert_eq(state.bombs[0].tile, Vector2i(7, 5), "the wrong bomb survived")

func test_a_hard_block_shields_a_bomb_behind_it() -> void:
	state.arena.set_at(Vector2i(6, 5), Arena.Tile.HARD)
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 4)
	SimFixture.add_bomb(state, Vector2i(7, 5), 1, 500, 1)
	SimFixture.run_idle(state, 2)
	assert_eq(state.bombs.size(), 1, "a hard block did not shield the bomb behind it")

func test_a_long_chain_resolves_completely_in_one_tick() -> void:
	# Six bombs in a line, each within the previous one's reach.
	for i in range(6):
		SimFixture.add_bomb(state, Vector2i(5 + i, 5), i % 2, 1 if i == 0 else 500, 1)
	var events: Array[SimEvent] = SimFixture.run_idle(state, 2)
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.BOMB_EXPLODED), 6, "the chain stopped short")
	assert_eq(state.bombs.size(), 0, "bombs left over after the chain")
	for i in range(6):
		assert_eq(state.flame_owner_at(Vector2i(5 + i, 5)), 0, "tile %d not credited to the chain starter" % i)

func test_no_bomb_detonates_twice() -> void:
	# A ring of bombs that all reach each other. Each must fire exactly once, or
	# bomb budgets go negative and the event log lies to the view.
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 1)
	SimFixture.add_bomb(state, Vector2i(6, 5), 0, 500, 1)
	SimFixture.add_bomb(state, Vector2i(5, 6), 0, 500, 1)
	SimFixture.add_bomb(state, Vector2i(6, 6), 0, 500, 1)
	state.players[0].bomb_capacity = 4
	var events: Array[SimEvent] = SimFixture.run_idle(state, 2)
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.BOMB_EXPLODED), 4, "bombs detonated more or less than once each")
	assert_eq(state.players[0].bombs_active, 0, "bomb budget was not restored exactly")

func test_chain_returns_each_bomb_to_its_own_owners_budget() -> void:
	# A chained bomb frees its *owner's* budget, not the chain starter's, even
	# though the flames are credited to the starter.
	state.players[0].bomb_capacity = 2
	state.players[1].bomb_capacity = 2
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 2)
	SimFixture.add_bomb(state, Vector2i(7, 5), 1, 500, 1)
	assert_eq(state.players[0].bombs_active, 1, "setup: player 0 budget")
	assert_eq(state.players[1].bombs_active, 1, "setup: player 1 budget")
	SimFixture.run_idle(state, 2)
	assert_eq(state.players[0].bombs_active, 0, "player 0's bomb was not returned")
	assert_eq(state.players[1].bombs_active, 0, "player 1's chained bomb was not returned to player 1")

func test_a_dead_players_bomb_still_explodes() -> void:
	# A bomb outlives its owner. This matters for kill credit: a dead player's
	# bomb can still score for them.
	SimFixture.add_bomb(state, Vector2i(9, 9), 0, 3, 1)
	state.players[0].alive = false
	state.players[0].respawn_ticks = 999
	var events: Array[SimEvent] = SimFixture.run_idle(state, 4)
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.BOMB_EXPLODED), 1, "a dead player's bomb did not go off")
	assert_eq(state.flame_owner_at(Vector2i(9, 9)), 0, "the dead owner lost their flame ownership")
