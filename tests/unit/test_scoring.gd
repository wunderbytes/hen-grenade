extends TestCase
## Death, kill credit, the suicide penalty, the round clock and the winner.
## See docs/milestone-1-brief.md §6.3 and §6.4, and docs/game-design.md §5.3.

var state: MatchState

func before_each() -> void:
	var b: Balance = SimFixture.balance()
	b.flame_ticks = 30
	b.respawn_ticks = 500      # keep the dead dead, so a test sees one death
	state = SimFixture.open_state(b, 3)

func test_killing_another_player_scores_one() -> void:
	SimFixture.place(state, 0, Vector2i(1, 1))
	SimFixture.place(state, 1, Vector2i(7, 5))
	SimFixture.place(state, 2, Vector2i(1, 13))
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 2)
	var events: Array[SimEvent] = SimFixture.run_idle(state, 2)

	assert_false(state.players[1].alive, "the victim survived a flame on their tile")
	assert_eq(state.players[0].score, 1, "killer's score")
	assert_eq(state.players[0].kills, 1, "killer's kill count")
	assert_eq(state.players[0].deaths, 0, "killer should not be charged a death")
	assert_eq(state.players[1].deaths, 1, "victim's death count")
	assert_eq(state.players[1].score, 0, "the victim's score should not change")

	var died: SimEvent = SimFixture.first_of(events, SimEvent.Kind.PLAYER_DIED)
	assert_not_null(died, "no PLAYER_DIED event")
	assert_eq(died.player, 1, "event victim")
	assert_eq(died.other, 0, "event killer")

func test_dying_to_your_own_bomb_costs_a_point() -> void:
	# With a 1.5 s respawn, blowing yourself up is otherwise nearly free, and
	# self-preservation has to stay a real consideration (game design §5.3).
	SimFixture.place(state, 0, Vector2i(5, 5))
	SimFixture.place(state, 1, Vector2i(1, 1))
	SimFixture.place(state, 2, Vector2i(1, 13))
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 1)
	var events: Array[SimEvent] = SimFixture.run_idle(state, 2)

	assert_false(state.players[0].alive, "the player survived their own blast")
	assert_eq(state.players[0].score, -1, "the suicide penalty was not applied")
	assert_eq(state.players[0].kills, 0, "a suicide is not a kill")
	assert_eq(state.players[0].deaths, 1, "a suicide is still a death")
	var died: SimEvent = SimFixture.first_of(events, SimEvent.Kind.PLAYER_DIED)
	assert_eq(died.other, died.player, "a suicide should report the victim as their own killer")

func test_a_chain_credits_the_player_who_started_it() -> void:
	# Player 0 sets off player 1's bomb, and player 1's blast is what reaches
	# player 2. The kill is player 0's.
	SimFixture.place(state, 0, Vector2i(1, 1))
	SimFixture.place(state, 1, Vector2i(1, 13))
	SimFixture.place(state, 2, Vector2i(8, 5))
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 2)
	SimFixture.add_bomb(state, Vector2i(7, 5), 1, 500, 1)
	SimFixture.run_idle(state, 2)

	assert_false(state.players[2].alive, "the victim survived the chained blast")
	assert_eq(state.players[0].score, 1, "the chain starter was not credited")
	assert_eq(state.players[0].kills, 1, "the chain starter's kill count")
	assert_eq(state.players[1].score, 0, "the owner of the chained bomb was wrongly credited")
	assert_eq(state.players[1].kills, 0, "the owner of the chained bomb was wrongly credited")

func test_your_own_bomb_used_against_you_is_not_a_suicide() -> void:
	# The other half of the propagation rule: player 1's bomb kills player 1,
	# but because player 0 set it off, it is player 0's kill and player 1 takes
	# no score penalty.
	SimFixture.place(state, 0, Vector2i(1, 1))
	SimFixture.place(state, 1, Vector2i(8, 5))
	SimFixture.place(state, 2, Vector2i(1, 13))
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 2)
	SimFixture.add_bomb(state, Vector2i(7, 5), 1, 500, 1)
	SimFixture.run_idle(state, 2)

	assert_false(state.players[1].alive, "the victim survived")
	assert_eq(state.players[0].score, 1, "the chain starter should get the kill")
	assert_eq(state.players[1].score, 0, "the victim should not take the suicide penalty")
	assert_eq(state.players[1].deaths, 1, "the victim's death count")

func test_spawn_protection_prevents_death() -> void:
	SimFixture.place(state, 0, Vector2i(1, 1))
	var victim: PlayerState = SimFixture.place(state, 1, Vector2i(5, 5))
	SimFixture.place(state, 2, Vector2i(1, 13))
	victim.spawn_protect_ticks = 60
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 1)
	SimFixture.run_idle(state, 2)
	assert_true(victim.alive, "spawn protection did not save the player")
	assert_eq(state.players[0].score, 0, "a protected player must not score for the bomber")

func test_protection_expiring_over_a_flame_is_fatal() -> void:
	# Protection is a countdown, not a one-shot immunity: standing in fire when
	# it lapses still kills you.
	var b: Balance = SimFixture.balance()
	b.flame_ticks = 60
	b.respawn_ticks = 500
	state = SimFixture.open_state(b, 2)
	SimFixture.place(state, 0, Vector2i(1, 1))
	var victim: PlayerState = SimFixture.place(state, 1, Vector2i(5, 5))
	victim.spawn_protect_ticks = 5
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 1)
	SimFixture.run_idle(state, 3)
	assert_true(victim.alive, "died while still protected")
	SimFixture.run_idle(state, 10)
	assert_false(victim.alive, "survived a flame after protection lapsed")

func test_only_the_players_centre_tile_is_lethal() -> void:
	# Collision and death both use the centre point. A player standing on the
	# tile next to a flame is safe, however overlapping the sprites look.
	SimFixture.place(state, 0, Vector2i(1, 1))
	var survivor: PlayerState = SimFixture.place(state, 1, Vector2i(7, 5))
	SimFixture.place(state, 2, Vector2i(1, 13))
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 1)
	SimFixture.run_idle(state, 2)
	assert_true(survivor.alive, "died to a flame two tiles away")

# --- Round clock and winner -------------------------------------------------

func test_the_clock_ends_the_round() -> void:
	var b: Balance = SimFixture.balance()
	b.round_ticks = 5
	state = SimFixture.open_state(b, 2)
	var events: Array[SimEvent] = SimFixture.run_idle(state, 4)
	assert_false(state.finished, "the round ended early")
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.ROUND_ENDED), 0, "premature ROUND_ENDED")

	events = SimFixture.run_idle(state, 1)
	assert_true(state.finished, "the clock did not end the round")
	assert_eq(state.round_ticks_left, 0, "clock did not reach zero")
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.ROUND_ENDED), 1, "no ROUND_ENDED event")

func test_a_finished_round_is_inert() -> void:
	var b: Balance = SimFixture.balance()
	b.round_ticks = 2
	state = SimFixture.open_state(b, 2)
	SimFixture.place(state, 0, Vector2i(5, 5))
	SimFixture.run_idle(state, 2)
	assert_true(state.finished, "setup: round should be over")
	var before: String = state.fingerprint()
	var events: Array[SimEvent] = SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT, true), 30)
	assert_eq(state.fingerprint(), before, "the simulation kept running after the round ended")
	assert_true(events.is_empty(), "a finished round emitted events")

func test_winner_is_the_highest_score() -> void:
	state.players[0].score = 3
	state.players[1].score = 5
	state.players[2].score = 1
	assert_eq(state.winner(), 1, "wrong winner")

func test_an_equal_top_score_is_a_draw() -> void:
	state.players[0].score = 4
	state.players[1].score = 4
	state.players[2].score = 1
	assert_eq(state.winner(), -1, "an equal top score should be a draw")

func test_a_tie_below_the_top_is_not_a_draw() -> void:
	state.players[0].score = 7
	state.players[1].score = 2
	state.players[2].score = 2
	assert_eq(state.winner(), 0, "a tie for second should not affect the winner")

func test_negative_scores_can_win() -> void:
	# Everyone can be in the hole: four players who only ever blew themselves up
	# still have to produce a winner.
	state.players[0].score = -1
	state.players[1].score = -3
	state.players[2].score = -2
	assert_eq(state.winner(), 0, "the least-bad score should win")

func test_inactive_slots_are_ignored_by_the_winner() -> void:
	state.players[0].score = 2
	state.players[1].score = 1
	state.players[2].score = 1
	state.players[3].score = 99      # inactive
	assert_eq(state.winner(), 0, "an inactive slot was counted")
