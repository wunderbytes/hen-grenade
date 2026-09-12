extends TestCase
## Replay record/playback and the golden determinism test.
## See docs/milestone-1-brief.md §8.

const GOLDEN_REPLAY: String = "res://tests/replays/golden_01.hgr"
const GOLDEN_FINGERPRINT: String = "res://tests/replays/golden_01.fingerprint.txt"
const TEMP_REPLAY: String = "user://test_roundtrip.hgr"

func test_record_and_read_back_frames() -> void:
	var replay: Replay = Replay.new()
	replay.player_count = 2
	var a: Array[InputFrame] = SimFixture.blank_frames()
	a[0] = SimFixture.frame(InputFrame.Dir.LEFT, true, true)
	a[1] = SimFixture.frame(InputFrame.Dir.DOWN)
	var b: Array[InputFrame] = SimFixture.blank_frames()
	b[0] = SimFixture.frame(InputFrame.Dir.UP)
	replay.record(a)
	replay.record(b)

	assert_eq(replay.tick_count(), 2, "tick count")
	# Ticks are 1-based, matching the simulation's own numbering.
	var read: InputFrame = replay.frame_for(1, 0)
	assert_eq(read.dir, InputFrame.Dir.LEFT, "tick 1 slot 0 dir")
	assert_true(read.bomb, "tick 1 slot 0 bomb")
	assert_true(read.action, "tick 1 slot 0 action")
	assert_eq(replay.frame_for(1, 1).dir, InputFrame.Dir.DOWN, "tick 1 slot 1 dir")
	assert_eq(replay.frame_for(2, 0).dir, InputFrame.Dir.UP, "tick 2 slot 0 dir")
	assert_eq(replay.frame_for(2, 1).dir, InputFrame.Dir.NONE, "tick 2 slot 1 should be empty")

func test_out_of_range_reads_are_empty_not_errors() -> void:
	# A replay can be run longer than it was recorded without the caller having
	# to special-case the end of the log.
	var replay: Replay = Replay.new()
	replay.record(SimFixture.blank_frames())
	assert_eq(replay.frame_for(0, 0).dir, InputFrame.Dir.NONE, "tick 0 is not a valid tick")
	assert_eq(replay.frame_for(99, 0).dir, InputFrame.Dir.NONE, "past the end of the log")
	assert_eq(replay.frame_for(1, 99).dir, InputFrame.Dir.NONE, "past the last slot")

func test_save_and_load_round_trip() -> void:
	var original: Replay = Replay.new()
	original.rng_seed = 987654
	original.balance_fingerprint = 0xDEADBEEF
	original.grid_w = 25
	original.grid_h = 15
	original.crate_permille = 650
	original.player_count = 3
	for i in range(50):
		var frames: Array[InputFrame] = SimFixture.blank_frames()
		frames[i % 3] = SimFixture.frame(((i % 4) + 1) as InputFrame.Dir, i % 7 == 0)
		original.record(frames)

	assert_eq(original.save(TEMP_REPLAY), OK, "save failed")
	var loaded: Replay = Replay.load_from(TEMP_REPLAY)
	assert_not_null(loaded, "load returned null")
	if loaded == null:
		return
	assert_eq(loaded.rng_seed, original.rng_seed, "seed")
	assert_eq(loaded.balance_fingerprint, original.balance_fingerprint, "balance fingerprint")
	assert_eq(loaded.grid_w, original.grid_w, "grid width")
	assert_eq(loaded.grid_h, original.grid_h, "grid height")
	assert_eq(loaded.crate_permille, original.crate_permille, "crate permille")
	assert_eq(loaded.player_count, original.player_count, "player count")
	assert_eq(loaded.tick_count(), original.tick_count(), "tick count")
	assert_eq(loaded.rows, original.rows, "input log")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_REPLAY))

func test_replay_source_drives_input_through_the_m0_seam() -> void:
	var replay: Replay = Replay.new()
	replay.player_count = 1
	replay.record(SimFixture.frames_for(0, InputFrame.Dir.RIGHT))
	replay.record(SimFixture.frames_for(0, InputFrame.Dir.RIGHT, true))

	var source: ReplaySource = ReplaySource.new(replay, 0)
	assert_eq(source.poll(1).dir, InputFrame.Dir.RIGHT, "tick 1")
	assert_false(source.poll(1).bomb, "tick 1 bomb")
	assert_true(source.poll(2).bomb, "tick 2 bomb")
	assert_false(source.exhausted(2), "log should still have tick 2")
	assert_true(source.exhausted(3), "log should be exhausted past its end")

func test_the_same_seed_and_inputs_produce_the_same_state() -> void:
	# The core determinism claim, tested without touching the filesystem.
	var seed_value: int = 5150
	var fingerprints: Array[String] = []
	for _run in range(2):
		var state: MatchState = MatchState.create(Balance.new(), ArenaDef.new(), seed_value, [true, true, false, false])
		var rng: SimRng = SimRng.new(4242)
		for _tick in range(400):
			var frames: Array[InputFrame] = SimFixture.blank_frames()
			for slot in range(2):
				frames[slot] = SimFixture.frame(rng.next_range(0, 4) as InputFrame.Dir, rng.next_below(20) == 0)
			Sim.step(state, frames)
		fingerprints.append(state.fingerprint())
	assert_eq(fingerprints[0], fingerprints[1], "identical seed and inputs diverged")

func test_a_different_seed_produces_a_different_state() -> void:
	var first: MatchState = MatchState.create(Balance.new(), ArenaDef.new(), 1, [true, true, false, false])
	var second: MatchState = MatchState.create(Balance.new(), ArenaDef.new(), 2, [true, true, false, false])
	assert_ne(first.fingerprint(), second.fingerprint(), "different seeds produced the same state")

## The regression guard. If this fails and you did not intend to change the
## rules, something became non-deterministic — which is exactly the bug class
## that is otherwise a nightmare to find. Regenerate deliberately with
## tools/make_golden_replay.gd, never reflexively.
func test_golden_replay_reproduces_its_committed_fingerprint() -> void:
	var replay: Replay = Replay.load_from(GOLDEN_REPLAY)
	assert_not_null(replay, "could not load %s" % GOLDEN_REPLAY)
	if replay == null:
		return

	var expected: PackedStringArray = _read_lines(GOLDEN_FINGERPRINT)
	assert_eq(expected.size(), 2, "%s should hold a final fingerprint and a trace digest" % GOLDEN_FINGERPRINT)
	if expected.size() != 2:
		return

	var balance: Balance = Balance.new()
	assert_eq(replay.balance_fingerprint, balance.fingerprint(),
		"the golden replay was recorded against different balance — regenerate it")

	var state: MatchState = replay.run(balance)
	assert_eq(state.tick, replay.tick_count(), "replay did not run to completion")
	assert_eq(state.fingerprint(), expected[0], "the golden replay no longer reproduces its recorded end state")
	# The trace catches divergence the end state cannot see — a chain-ownership
	# change, say, that leaves the final board identical once the fires are out.
	assert_eq(replay.trace_digest, expected[1], "the golden replay diverged part-way through the round")

func test_golden_replay_is_a_round_worth_testing() -> void:
	# A golden replay of four players standing still would pass forever while
	# proving nothing, so assert the recorded round actually did something.
	var replay: Replay = Replay.load_from(GOLDEN_REPLAY)
	assert_not_null(replay, "could not load %s" % GOLDEN_REPLAY)
	if replay == null:
		return
	assert_gt(replay.tick_count(), 600, "the golden replay is too short to be interesting")
	assert_eq(replay.player_count, 4, "the golden replay should exercise all four slots")

	var state: MatchState = replay.run(Balance.new())
	var deaths: int = 0
	for p in state.players:
		deaths += p.deaths
	assert_gt(deaths, 0, "nobody died in the golden replay — it is not exercising the rules")
	var crates_left: int = state.arena.count_of(Arena.Tile.CRATE)
	assert_lt(crates_left, 233, "no crates were destroyed in the golden replay")

func _read_lines(path: String) -> PackedStringArray:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedStringArray()
	var text: String = f.get_as_text()
	f.close()
	var out: PackedStringArray = PackedStringArray()
	for line in text.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed != "":
			out.append(trimmed)
	return out
