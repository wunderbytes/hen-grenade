extends SceneTree
## Regenerates the committed golden replay and prints the pinned hashes.
##
##   godot --headless --path . --script res://tools/make_golden_replay.gd
##
## Run this **only** after an intentional rule change, and expect the diff to
## show a new fingerprint. If the fingerprint moves when you did not mean to
## change behaviour, that is the bug the golden test exists to catch — find it
## rather than regenerating over it.
##
## It also prints the SimRng sequence pin used by tests/unit/test_sim_rng.gd, so
## both committed constants have one obvious place to come from.
##
## Per technical-design.md Appendix A.4, the work happens in _init(): a GDScript
## override of SceneTree._iteration is silently ignored, so there is no frame
## loop to hook.

const REPLAY_PATH: String = "res://tests/replays/golden_01.hgr"
const FINGERPRINT_PATH: String = "res://tests/replays/golden_01.fingerprint.txt"

## 30 seconds of four-player input. Long enough for crates to break, bombs to
## chain and players to die and come back several times over; short enough that
## the test runs in well under a second.
const TICKS: int = 1800
const INPUT_SEED: int = 0xBEEF
const MATCH_SEED: int = 20260912

func _init() -> void:
	print("== golden replay generator ==")
	_print_rng_pin()
	_generate()
	quit(0)

func _print_rng_pin() -> void:
	var rng: SimRng = SimRng.new(12345)
	var h: int = SimHash.start()
	for _i in range(256):
		h = SimHash.mix_int(h, rng.next_u32())
	print("SimRng pin (seed 12345, 256 draws): %s" % SimHash.to_hex(h))

func _generate() -> void:
	var balance: Balance = Balance.new()
	var arena_def: ArenaDef = ArenaDef.new()
	var active: Array[bool] = [true, true, true, true]
	var state: MatchState = MatchState.create(balance, arena_def, MATCH_SEED, active)

	var replay: Replay = Replay.for_state(state)
	var input_rng: SimRng = SimRng.new(INPUT_SEED)
	var held: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	var bomb_cooldown: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])

	for _tick in range(TICKS):
		var frames: Array[InputFrame] = []
		for slot in range(C.MAX_PLAYERS):
			# Change direction occasionally rather than every tick, so players
			# actually travel instead of vibrating on one tile.
			if input_rng.next_below(12) == 0:
				held[slot] = input_rng.next_range(0, 4)
			var bomb: bool = false
			if bomb_cooldown[slot] > 0:
				bomb_cooldown[slot] -= 1
			elif input_rng.next_below(25) == 0:
				bomb = true
				bomb_cooldown[slot] = 20
			var f: InputFrame = InputFrame.new()
			f.dir = held[slot] as InputFrame.Dir
			f.bomb = bomb
			frames.append(f)
		replay.record(frames)
		Sim.step(state, frames)

	var fingerprint: String = state.fingerprint()
	var err: Error = replay.save(REPLAY_PATH)
	if err != OK:
		printerr("could not write %s (error %d)" % [REPLAY_PATH, err])
		quit(1)
		return

	# Replay our own log back to obtain the trace digest exactly the way the
	# test will compute it. This also self-checks the round trip: if the saved
	# log does not reproduce the state we just simulated, say so here rather
	# than committing a golden file that can never pass.
	var check: MatchState = replay.run(balance)
	if check.fingerprint() != fingerprint:
		printerr("replaying the saved log did not reproduce the recorded state — not writing a golden file")
		quit(1)
		return

	var f: FileAccess = FileAccess.open(FINGERPRINT_PATH, FileAccess.WRITE)
	if f == null:
		printerr("could not write %s" % FINGERPRINT_PATH)
		quit(1)
		return
	f.store_line(fingerprint)
	f.store_line(replay.trace_digest)
	f.close()
	print("trace digest        : %s" % replay.trace_digest)

	print("ticks               : %d" % state.tick)
	print("match seed          : %d" % MATCH_SEED)
	print("balance fingerprint : %s" % SimHash.to_hex(replay.balance_fingerprint))
	print("crates remaining    : %d" % state.arena.count_of(Arena.Tile.CRATE))
	var scores: PackedStringArray = PackedStringArray()
	for p in state.players:
		scores.append("P%d %d (%dk/%dd)" % [p.index + 1, p.score, p.kills, p.deaths])
	print("scores              : %s" % ", ".join(scores))
	print("state fingerprint   : %s" % fingerprint)
	print("wrote %s and %s" % [REPLAY_PATH, FINGERPRINT_PATH])
