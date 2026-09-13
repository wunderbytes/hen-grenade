class_name MatchRecord
## Best-of-3 across rounds. See docs/milestone-3-brief.md §6.1 and
## docs/game-design.md §5.3.
##
## A plain RefCounted with no `Node` and no autoload, so the whole match-scoring
## question is unit-testable headless — the same inversion `DeviceBinder` got in
## M2, and for the same reason.
##
## **It does not need to survive a scene change.** M2's completion notes assumed
## it would, but `MatchScene` plays round after round without one, and the only
## transitions that leave the scene — quit to lobby, and the lobby starting a new
## match — are exactly the transitions that should end a match anyway. So this
## object lives in the match scene and no new autoload was added for it.

## Round wins per slot, index-stable like everything else keyed on a slot.
var round_wins: PackedInt32Array = PackedInt32Array()
## Winner of each round in order, -1 for a draw. The scoreboard reads it and it
## is what `rounds_played()` counts.
var round_winners: PackedInt32Array = PackedInt32Array()
## Total round score per slot, carried across rounds purely as the last
## tie-break at `max_rounds` (§6.1).
var total_score: PackedInt32Array = PackedInt32Array()

var target_wins: int = 2
var max_rounds: int = 7

## Which slots are in this match. Needed because the tie-breaks compare per-slot
## numbers and an empty slot sits on zero: with two players both on a negative
## total score, an unplayed slot would otherwise win the match on the last
## tie-break. Defaults to all four so a test can ignore it.
var active: PackedByteArray = PackedByteArray()

func _init(p_target_wins: int = 2, p_max_rounds: int = 7) -> void:
	target_wins = maxi(1, p_target_wins)
	max_rounds = maxi(1, p_max_rounds)
	round_wins.resize(C.MAX_PLAYERS)
	round_wins.fill(0)
	total_score.resize(C.MAX_PLAYERS)
	total_score.fill(0)
	active.resize(C.MAX_PLAYERS)
	active.fill(1)

## Freezes the roster for the match. Called once, when the match starts.
func set_active(flags: Array[bool]) -> void:
	for i in range(C.MAX_PLAYERS):
		active[i] = 1 if i < flags.size() and flags[i] else 0

## Builds one from a MatchRules resource, or from the code defaults if there is
## none — a missing data file should not be an unexplained crash at round end.
static func from_rules(rules: MatchRules) -> MatchRecord:
	if rules == null:
		return MatchRecord.new()
	return MatchRecord.new(rules.round_wins_to_take_match, rules.max_rounds)

# --- Recording ---------------------------------------------------------------

## Files a finished round. `winner_slot` is -1 for a draw, which **advances
## nothing**: nobody gets a win, the round counts as played, and the match
## continues. Draw, draw, win, win is a legal four-round match.
func record_round(winner_slot: int, scores: PackedInt32Array = PackedInt32Array()) -> void:
	round_winners.append(winner_slot)
	if winner_slot >= 0 and winner_slot < round_wins.size():
		round_wins[winner_slot] += 1
	for i in range(mini(scores.size(), total_score.size())):
		total_score[i] += scores[i]

## Pulls the per-slot round scores straight off a finished round, so the caller
## does not have to assemble an array by hand.
func record_round_from(state: MatchState) -> void:
	var scores: PackedInt32Array = PackedInt32Array()
	scores.resize(C.MAX_PLAYERS)
	for i in range(mini(state.players.size(), C.MAX_PLAYERS)):
		scores[i] = _round_score_of(state, state.players[i])
	record_round(state.winner(), scores)

func _round_score_of(state: MatchState, p: PlayerState) -> int:
	if state.mode != null and state.mode.scoring == GameMode.Scoring.HEN_TICKS:
		return p.hen_ticks
	return p.score

# --- Queries -----------------------------------------------------------------

func rounds_played() -> int:
	return round_winners.size()

func wins_of(slot: int) -> int:
	if slot < 0 or slot >= round_wins.size():
		return 0
	return round_wins[slot]

func draws() -> int:
	var n: int = 0
	for w in round_winners:
		if w < 0:
			n += 1
	return n

## The round about to be played, 1-based, for the HUD and the scoreboard.
func current_round() -> int:
	return rounds_played() + 1

## True once somebody has taken the match, or once the round ceiling is reached.
##
## The ceiling is what makes a decider safe: game design §5.3 says a level match
## plays one, and deciders are rounds, so without an upper bound a pathological
## run of draws would play forever.
func is_over() -> bool:
	return _best_wins() >= target_wins or rounds_played() >= max_rounds

## The match winner, or -1. Also -1 while the match is still being played, so a
## caller must ask `is_over()` first — "nobody has won yet" and "nobody won" are
## the same answer to this question and only the caller knows which it wanted.
##
## At `max_rounds` with nobody on `target_wins`, the tie-breaks run in the
## documented order: the unique highest win count, then the unique highest total
## round score, and otherwise a drawn match — which is an honest outcome for four
## people who genuinely could not be separated in seven rounds.
func winner() -> int:
	var leader: int = _unique_leader(round_wins)
	if leader >= 0 and round_wins[leader] >= target_wins:
		return leader
	if rounds_played() < max_rounds:
		return -1
	if leader >= 0:
		return leader
	return _unique_leader(total_score)

## The round wins as a short string for a HUD card: "..", "*.", "**".
func pips(slot: int) -> String:
	var out: String = ""
	for i in range(target_wins):
		out += "*" if i < wins_of(slot) else "."
	return out

func _best_wins() -> int:
	var best: int = 0
	for w in round_wins:
		best = maxi(best, w)
	return best

## The single highest entry among the active slots, or -1 if the top is shared.
## An empty record returns -1 rather than slot 0: before a round is played there
## is no leader, not a leader on zero.
func _unique_leader(values: PackedInt32Array) -> int:
	if rounds_played() == 0:
		return -1
	var best: int = 0
	var best_slot: int = -1
	var tied: bool = false
	for i in range(values.size()):
		if i < active.size() and active[i] == 0:
			continue
		if best_slot == -1 or values[i] > best:
			best = values[i]
			best_slot = i
			tied = false
		elif values[i] == best:
			tied = true
	return -1 if tied else best_slot
