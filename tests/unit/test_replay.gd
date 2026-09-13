extends TestCase
## Replay record/playback and the golden determinism test.
## See docs/milestone-1-brief.md §8.

const GOLDEN_DIR: String = "res://tests/replays"
## Both committed rounds, and they are not interchangeable: 01 is the shipped
## crate density, 02 starts thin enough for crate regeneration to fire.
const GOLDEN_NAMES: Array[String] = ["golden_01", "golden_02"]
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
	original.rules_fingerprint = 0xDEADBEEF
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
	assert_eq(loaded.rules_fingerprint, original.rules_fingerprint, "rules fingerprint")
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

## The regression guard, over **both** committed replays. If this fails and you
## did not intend to change the rules, something became non-deterministic —
## exactly the bug class that is otherwise a nightmare to find. Regenerate
## deliberately with tools/make_golden_replay.gd, never reflexively.
##
## There are two files because one round could not cover everything: `golden_01`
## is the representative arena and `golden_02` starts thin enough that crate
## regeneration actually fires. See the header of the generator.
func test_golden_replays_reproduce_their_committed_fingerprints() -> void:
	for name in GOLDEN_NAMES:
		var replay: Replay = _golden(name)
		if replay == null:
			continue
		var expected: PackedStringArray = _read_lines(_fingerprint_path(name))
		assert_eq(expected.size(), 2, "%s should hold a final fingerprint and a trace digest" % name)
		if expected.size() != 2:
			continue

		var balance: Balance = Balance.new()
		var powerups: PowerupTable = PowerupTable.new()
		assert_eq(replay.rules_fingerprint, Replay.rules_fingerprint_of(balance, powerups, GameMode.deathmatch()),
			"%s was recorded against different rules — regenerate it" % name)

		var state: MatchState = replay.run(balance, powerups)
		assert_eq(state.tick, replay.tick_count(), "%s did not run to completion" % name)
		assert_eq(state.fingerprint(), expected[0], "%s no longer reproduces its recorded end state" % name)
		# The trace catches divergence the end state cannot see — a chain-ownership
		# change, say, that leaves the final board identical once the fires are out.
		assert_eq(replay.trace_digest, expected[1], "%s diverged part-way through the round" % name)

func test_golden_replays_are_rounds_worth_testing() -> void:
	# A golden replay of four players standing still would pass forever while
	# proving nothing, so assert the recorded rounds actually did something.
	for name in GOLDEN_NAMES:
		var replay: Replay = _golden(name)
		if replay == null:
			continue
		assert_gt(replay.tick_count(), 600, "%s is too short to be interesting" % name)
		assert_eq(replay.player_count, 4, "%s should exercise all four slots" % name)

		var state: MatchState = replay.run(Balance.new())
		var deaths: int = 0
		for p in state.players:
			deaths += p.deaths
		assert_gt(deaths, 0, "nobody died in %s — it is not exercising the rules" % name)
		assert_lt(state.arena.count_of(Arena.Tile.CRATE), 233, "no crates were destroyed in %s" % name)

func test_the_golden_replays_exercise_the_m3_economy() -> void:
	# A golden replay that pins the new rules while exercising none of them would
	# be worse than useless, because it would look like coverage. Stepped by hand
	# rather than through run(), because the proof is in the events and run()
	# throws those away.
	var dropped: int = 0
	var taken: int = 0
	var regen: int = 0
	for name in GOLDEN_NAMES:
		var replay: Replay = _golden(name)
		if replay == null:
			continue
		var state: MatchState = replay.fresh_state(Balance.new())
		for t in range(1, replay.tick_count() + 1):
			for e in Sim.step(state, replay.frames_for(t)):
				match e.kind:
					SimEvent.Kind.PICKUP_SPAWNED: dropped += 1
					SimEvent.Kind.PICKUP_TAKEN: taken += 1
					SimEvent.Kind.CRATE_SPAWNED: regen += 1
	assert_gt(dropped, 0, "no power-up ever dropped — regenerate the golden replays")
	assert_gt(taken, 0, "nobody collected a power-up — regenerate the golden replays")
	assert_gt(regen, 0, "no crate regeneration wave landed — the only PRNG consumer M3 added is unpinned")

func test_golden_03_is_a_hen_round_that_passes_the_token() -> void:
	var replay: Replay = _golden("golden_03")
	if replay == null:
		return
	var expected: PackedStringArray = _read_lines(_fingerprint_path("golden_03"))
	assert_eq(expected.size(), 2, "golden_03 should hold a final fingerprint and a trace digest")
	if expected.size() != 2:
		return
	var balance: Balance = Balance.new()
	var powerups: PowerupTable = PowerupTable.new()
	var hen: GameMode = GameMode.hen()
	assert_eq(replay.rules_fingerprint, Replay.rules_fingerprint_of(balance, powerups, hen),
		"golden_03 was recorded against different rules — regenerate it")
	var state: MatchState = replay.run(balance, powerups, hen)
	assert_eq(state.fingerprint(), expected[0], "golden_03 no longer reproduces its recorded end state")
	assert_eq(replay.trace_digest, expected[1], "golden_03 diverged part-way through the round")

	var collected: int = 0
	var dropped: int = 0
	var holders: Array[int] = []
	state = replay.fresh_state(balance, powerups, hen)
	for t in range(1, replay.tick_count() + 1):
		for e in Sim.step(state, replay.frames_for(t)):
			match e.kind:
				SimEvent.Kind.HEN_COLLECTED:
					collected += 1
					if not holders.has(e.player):
						holders.append(e.player)
				SimEvent.Kind.HEN_DROPPED:
					dropped += 1
	assert_ge(collected, 2, "golden_03 never passed the token to a second player")
	assert_ge(dropped, 1, "golden_03 never died as the Hen")
	assert_ge(holders.size(), 2, "only one player ever collected the token")

func _golden(name: String) -> Replay:
	var replay: Replay = Replay.load_from("%s/%s.hgr" % [GOLDEN_DIR, name])
	assert_not_null(replay, "could not load %s" % name)
	return replay

func _fingerprint_path(name: String) -> String:
	return "%s/%s.fingerprint.txt" % [GOLDEN_DIR, name]

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
