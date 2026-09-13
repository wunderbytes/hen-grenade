extends TestCase
## Best-of-3, draws, and the decider.
## See docs/milestone-3-brief.md §6.1 and docs/game-design.md §5.3.

var record: MatchRecord

func before_each() -> void:
	record = MatchRecord.new(2, 7)
	record.set_active([true, true, false, false])

func _win(slot: int) -> void:
	record.record_round(slot)

func _draw() -> void:
	record.record_round(-1)

# --- The basic shape ----------------------------------------------------------

func test_a_new_record_is_not_over_and_has_no_winner() -> void:
	assert_false(record.is_over(), "a match is over before it has started")
	assert_eq(record.winner(), -1, "an unplayed match has a winner")
	assert_eq(record.rounds_played(), 0, "rounds played")
	assert_eq(record.current_round(), 1, "the first round should be round 1")

func test_first_to_two_takes_the_match() -> void:
	_win(0)
	assert_false(record.is_over(), "one win ended the match")
	assert_eq(record.winner(), -1, "a leader is not a winner")
	_win(0)
	assert_true(record.is_over(), "two wins did not end the match")
	assert_eq(record.winner(), 0, "the wrong winner")
	assert_eq(record.rounds_played(), 2, "a 2-0 match should be two rounds long")

func test_a_round_win_goes_to_exactly_one_slot() -> void:
	_win(1)
	assert_eq(record.wins_of(1), 1, "the winner's tally")
	assert_eq(record.wins_of(0), 0, "somebody else's tally moved")
	assert_eq(record.round_winners[0], 1, "the round log")

func test_the_round_counter_advances() -> void:
	_win(0)
	_draw()
	assert_eq(record.current_round(), 3, "the next round number")

# --- Draws --------------------------------------------------------------------

func test_a_drawn_round_gives_nobody_a_win() -> void:
	_draw()
	assert_eq(record.wins_of(0), 0, "a draw was scored as a win")
	assert_eq(record.wins_of(1), 0, "a draw was scored as a win")
	assert_eq(record.rounds_played(), 1, "a draw should still count as a round played")
	assert_eq(record.draws(), 1, "the draw was not recorded")
	assert_false(record.is_over(), "a draw ended the match")

func test_draw_draw_win_win_is_a_legal_four_round_match() -> void:
	_draw()
	_draw()
	_win(1)
	assert_false(record.is_over(), "the match ended on one win")
	_win(1)
	assert_true(record.is_over(), "the match did not end on the second win")
	assert_eq(record.winner(), 1, "the wrong winner")
	assert_eq(record.rounds_played(), 4, "rounds played")

func test_a_level_match_plays_a_decider() -> void:
	# game design §5.3: "if the match itself ends level, play a decider".
	_win(0)
	_win(1)
	_draw()
	assert_eq(record.rounds_played(), 3, "setup: three rounds played")
	assert_false(record.is_over(), "a level best-of-3 refused to play a decider")
	_win(0)
	assert_true(record.is_over(), "the decider did not settle it")
	assert_eq(record.winner(), 0, "the decider's winner")

# --- The ceiling --------------------------------------------------------------

func test_the_round_ceiling_ends_a_pathological_match() -> void:
	# Without a ceiling a run of draws plays forever, and deciders are rounds.
	for _i in range(7):
		_draw()
	assert_true(record.is_over(), "seven draws did not reach the ceiling")
	assert_eq(record.winner(), -1, "seven draws produced a winner")

func test_at_the_ceiling_the_highest_win_count_takes_it() -> void:
	var r: MatchRecord = MatchRecord.new(3, 4)
	r.set_active([true, true, true, false])
	r.record_round(0)
	r.record_round(1)
	r.record_round(1)      # 1 leads 2-1 but needs 3
	r.record_round(-1)
	assert_true(r.is_over(), "the ceiling did not end the match")
	assert_eq(r.winner(), 1, "the highest win count did not take it")

func test_at_the_ceiling_a_level_win_count_goes_to_total_score() -> void:
	var r: MatchRecord = MatchRecord.new(3, 2)
	r.set_active([true, true, false, false])
	r.record_round(0, PackedInt32Array([5, 1, 0, 0]))
	r.record_round(1, PackedInt32Array([0, 2, 0, 0]))
	assert_true(r.is_over(), "the ceiling did not end the match")
	assert_eq(r.wins_of(0), r.wins_of(1), "setup: the win counts should be level")
	assert_eq(r.winner(), 0, "the higher total score did not break the tie")

func test_a_genuinely_inseparable_match_is_a_draw() -> void:
	var r: MatchRecord = MatchRecord.new(3, 2)
	r.set_active([true, true, false, false])
	r.record_round(0, PackedInt32Array([3, 1, 0, 0]))
	r.record_round(1, PackedInt32Array([1, 3, 0, 0]))
	assert_true(r.is_over(), "the ceiling did not end the match")
	assert_eq(r.winner(), -1, "an inseparable match produced a winner")

func test_empty_slots_cannot_win_on_the_score_tie_break() -> void:
	# Two players both in the hole, and two slots sitting on zero. Without the
	# roster the last tie-break would hand the match to a seat nobody is in.
	var r: MatchRecord = MatchRecord.new(3, 2)
	r.set_active([true, true, false, false])
	r.record_round(0, PackedInt32Array([-1, -3, 0, 0]))
	r.record_round(1, PackedInt32Array([-1, -1, 0, 0]))
	assert_eq(r.wins_of(0), r.wins_of(1), "setup: the win counts should be level")
	assert_eq(r.winner(), 0, "an empty slot won the match on score")

# --- Score carry and display --------------------------------------------------

func test_round_scores_accumulate() -> void:
	record.record_round(0, PackedInt32Array([3, 1, 0, 0]))
	record.record_round(1, PackedInt32Array([2, 4, 0, 0]))
	assert_eq(record.total_score[0], 5, "slot 0 total")
	assert_eq(record.total_score[1], 5, "slot 1 total")

func test_a_round_can_be_filed_straight_from_a_finished_state() -> void:
	var state: MatchState = SimFixture.open_state(SimFixture.balance(), 2)
	state.players[0].score = 4
	state.players[1].score = 2
	record.record_round_from(state)
	assert_eq(record.wins_of(0), 1, "the round winner was not read off the state")
	assert_eq(record.total_score[0], 4, "the round score was not carried")
	assert_eq(record.total_score[1], 2, "the round score was not carried")

func test_pips_show_progress_toward_the_target() -> void:
	assert_eq(record.pips(0), "..", "no wins")
	_win(0)
	assert_eq(record.pips(0), "*.", "one win")
	_win(0)
	assert_eq(record.pips(0), "**", "two wins")

func test_rules_resources_drive_the_record() -> void:
	var rules: MatchRules = MatchRules.new()
	rules.round_wins_to_take_match = 3
	rules.max_rounds = 5
	var r: MatchRecord = MatchRecord.from_rules(rules)
	assert_eq(r.target_wins, 3, "target wins came from somewhere else")
	assert_eq(r.max_rounds, 5, "max rounds came from somewhere else")
	# A missing resource must not be a crash at round end.
	var fallback: MatchRecord = MatchRecord.from_rules(null)
	assert_eq(fallback.target_wins, 2, "the fallback lost its default")

func test_out_of_range_slots_are_harmless() -> void:
	record.record_round(9)
	assert_eq(record.rounds_played(), 1, "the round was not recorded")
	assert_eq(record.wins_of(9), 0, "an impossible slot has wins")
	assert_eq(record.wins_of(-1), 0, "a negative slot has wins")
	assert_false(record.is_over(), "an impossible winner ended the match")
