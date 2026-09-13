extends SceneTree
## Regenerates the committed golden replays and prints the pinned hashes.
##
##   godot --headless --path . --script res://tools/make_golden_replay.gd
##
## Run this **only** after an intentional rule change, and expect the diff to
## show new fingerprints. If a fingerprint moves when you did not mean to change
## behaviour, that is the bug the golden test exists to catch — find it rather
## than regenerating over it.
##
## It also prints the SimRng sequence pin used by tests/unit/test_sim_rng.gd, so
## both committed constants have one obvious place to come from.
##
## Per technical-design.md Appendix A.4, the work happens in _init(): a GDScript
## override of SceneTree._iteration is silently ignored, so there is no frame
## loop to hook.

## Sixty seconds of four-player input per replay. Long enough for crates to
## break, bombs to chain, players to die and come back a dozen times over, and
## power-ups to drop and be collected. Short enough that the tests still run in
## well under a second.
const TICKS: int = 3600
const INPUT_SEED: int = 0xBEEF

## **Two replays, and the second one exists for a specific reason.**
##
## The arena ships at ~70% crates and the regeneration cap is 45%, so no wave can
## land until the players have destroyed about sixty crates. This generator's
## input is a random walk — four players who never aim, never upgrade, and score
## nothing but suicides — and it does not get there inside a minute. A golden
## replay that pins the new rules while exercising none of them looks like
## coverage and is worth nothing.
##
## So `golden_01` is the representative round at the shipped density, and
## `golden_02` is the same generator on a thinner arena that starts *below* the
## cap, which makes crate regeneration — the only PRNG consumer M3 added — fire
## from its first checkpoint. Crate density is stored in the replay file and
## rebuilt from it, so a replay recorded at another density is a first-class
## replay and not a fudge.
const SPECS: Array[Dictionary] = [
	{ "name": "golden_01", "seed": 20260912, "crate_permille": 700 },
	{ "name": "golden_02", "seed": 20260913, "crate_permille": 380 },
]

const REPLAY_DIR: String = "res://tests/replays"

func _init() -> void:
	print("== golden replay generator ==")
	_print_rng_pin()
	for spec in SPECS:
		if not _generate(spec):
			quit(1)
			return
	quit(0)

func _print_rng_pin() -> void:
	var rng: SimRng = SimRng.new(12345)
	var h: int = SimHash.start()
	for _i in range(256):
		h = SimHash.mix_int(h, rng.next_u32())
	print("SimRng pin (seed 12345, 256 draws): %s" % SimHash.to_hex(h))

func _generate(spec: Dictionary) -> bool:
	var name: String = String(spec["name"])
	var balance: Balance = Balance.new()
	var arena_def: ArenaDef = ArenaDef.new()
	arena_def.crate_permille = int(spec["crate_permille"])
	var powerups: PowerupTable = PowerupTable.new()
	var active: Array[bool] = [true, true, true, true]
	var match_seed: int = int(spec["seed"])
	var state: MatchState = MatchState.create(balance, arena_def, match_seed, active, powerups)

	var replay: Replay = Replay.for_state(state)
	var input_rng: SimRng = SimRng.new(INPUT_SEED)
	var held: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	var bomb_cooldown: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	var action_cooldown: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	var counts: Dictionary = {
		"dropped": 0, "taken": 0, "regen": 0, "kicked": 0, "tossed": 0, "cursed": 0,
	}

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
			elif input_rng.next_below(18) == 0:
				bomb = true
				bomb_cooldown[slot] = 16
			# M3: the action button, so Toss and Remote are in the recorded round
			# rather than merely possible.
			var action: bool = false
			if action_cooldown[slot] > 0:
				action_cooldown[slot] -= 1
			elif input_rng.next_below(40) == 0:
				action = true
				action_cooldown[slot] = 24
			var f: InputFrame = InputFrame.new()
			f.dir = held[slot] as InputFrame.Dir
			f.bomb = bomb
			f.action = action
			frames.append(f)
		replay.record(frames)
		for e in Sim.step(state, frames):
			match e.kind:
				SimEvent.Kind.PICKUP_SPAWNED: counts["dropped"] += 1
				SimEvent.Kind.PICKUP_TAKEN: counts["taken"] += 1
				SimEvent.Kind.CRATE_SPAWNED: counts["regen"] += 1
				SimEvent.Kind.BOMB_KICKED: counts["kicked"] += 1
				SimEvent.Kind.BOMB_TOSSED: counts["tossed"] += 1
				SimEvent.Kind.CURSE_APPLIED: counts["cursed"] += 1

	var fingerprint: String = state.fingerprint()
	var replay_path: String = "%s/%s.hgr" % [REPLAY_DIR, name]
	var fingerprint_path: String = "%s/%s.fingerprint.txt" % [REPLAY_DIR, name]
	var err: Error = replay.save(replay_path)
	if err != OK:
		printerr("could not write %s (error %d)" % [replay_path, err])
		return false

	# Replay our own log back to obtain the trace digest exactly the way the
	# test will compute it. This also self-checks the round trip: if the saved
	# log does not reproduce the state we just simulated, say so here rather
	# than committing a golden file that can never pass.
	var check: MatchState = replay.run(balance, powerups)
	if check.fingerprint() != fingerprint:
		printerr("replaying the saved log did not reproduce the recorded state — not writing a golden file")
		return false

	var f: FileAccess = FileAccess.open(fingerprint_path, FileAccess.WRITE)
	if f == null:
		printerr("could not write %s" % fingerprint_path)
		return false
	f.store_line(fingerprint)
	f.store_line(replay.trace_digest)
	f.close()

	print("\n-- %s --" % name)
	print("ticks               : %d" % state.tick)
	print("match seed          : %d" % match_seed)
	print("crate density       : %d permille" % arena_def.crate_permille)
	print("rules fingerprint   : %s" % SimHash.to_hex(replay.rules_fingerprint))
	print("crates remaining    : %d (cap %d)" % [state.arena.count_of(Arena.Tile.CRATE), state.crate_cap()])
	# The M3 economy, so it is obvious from the generator's own output whether the
	# round being pinned actually exercises the rules it is pinning.
	print("pickups dropped     : %d" % counts["dropped"])
	print("pickups collected   : %d" % counts["taken"])
	print("crates regenerated  : %d" % counts["regen"])
	print("bombs kicked        : %d" % counts["kicked"])
	print("bombs tossed        : %d" % counts["tossed"])
	print("curses applied      : %d" % counts["cursed"])
	print("pickups on the floor: %d" % state.pickup_count())
	var scores: PackedStringArray = PackedStringArray()
	for p in state.players:
		scores.append("P%d %d (%dk/%dd)" % [p.index + 1, p.score, p.kills, p.deaths])
	print("scores              : %s" % ", ".join(scores))
	print("trace digest        : %s" % replay.trace_digest)
	print("state fingerprint   : %s" % fingerprint)
	print("wrote %s and %s" % [replay_path, fingerprint_path])
	return true
