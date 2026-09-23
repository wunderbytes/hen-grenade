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

## **Three replays, and they are not interchangeable.**
##
## `golden_01` is the representative deathmatch round at the shipped density.
## `golden_02` is the same generator on a thinner arena that starts *below* the
## regen cap, which makes crate regeneration fire. `golden_03` is a Hen Grenade
## round whose input actually collects the token, dies as the Hen, and collects
## it again — the only way to pin those rules.
const SPECS: Array[Dictionary] = [
	{ "name": "golden_01", "seed": 20260912, "crate_permille": 700, "mode": "deathmatch" },
	{ "name": "golden_02", "seed": 20260913, "crate_permille": 380, "mode": "deathmatch" },
	{ "name": "golden_03", "seed": 20260914, "crate_permille": 0, "mode": "hen" },
]

const REPLAY_DIR: String = "res://tests/replays"

func _init() -> void:
	print("== golden replay generator ==")
	_print_rng_pin()
	var only: String = _only_name()
	for spec in SPECS:
		if only != "" and String(spec["name"]) != only:
			continue
		if not _generate(spec):
			quit(1)
			return
	quit(0)

func _only_name() -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--mode" and i + 1 < args.size() and args[i + 1] == "hen":
			return "golden_03"
	return ""

func _print_rng_pin() -> void:
	var rng: SimRng = SimRng.new(12345)
	var h: int = SimHash.start()
	for _i in range(256):
		h = SimHash.mix_int(h, rng.next_u32())
	print("SimRng pin (seed 12345, 256 draws): %s" % SimHash.to_hex(h))

func _mode_of(spec: Dictionary) -> GameMode:
	return GameMode.hen() if String(spec["mode"]) == "hen" else GameMode.deathmatch()

func _generate(spec: Dictionary) -> bool:
	var name: String = String(spec["name"])
	var balance: Balance = Balance.new()
	var arena_def: ArenaDef = ArenaDef.new()
	arena_def.crate_permille = int(spec["crate_permille"])
	var powerups: PowerupTable = PowerupTable.new()
	var mode: GameMode = _mode_of(spec)
	var active: Array[bool] = [true, true, true, true]
	var match_seed: int = int(spec["seed"])
	var state: MatchState = MatchState.create(balance, arena_def, match_seed, active, powerups, mode)

	var replay: Replay = Replay.for_state(state)
	var input_rng: SimRng = SimRng.new(INPUT_SEED)
	var held: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	var bomb_cooldown: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	var action_cooldown: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	var counts: Dictionary = {
		"dropped": 0, "taken": 0, "regen": 0, "kicked": 0, "tossed": 0, "cursed": 0,
		"hen_collected": 0, "hen_dropped": 0, "egg_laid": 0, "egg_hatched": 0,
	}

	for _tick in range(TICKS):
		var frames: Array[InputFrame] = []
		for slot in range(C.MAX_PLAYERS):
			var dir: int = held[slot]
			if mode.is_hen():
				dir = _hen_dir(state, slot, input_rng)
			elif input_rng.next_below(12) == 0:
				held[slot] = input_rng.next_range(0, 4)
				dir = held[slot]
			var bomb: bool = false
			if bomb_cooldown[slot] > 0:
				bomb_cooldown[slot] -= 1
			elif mode.is_hen() and state.hen_slot == slot and input_rng.next_below(24) == 0:
				bomb = true
				bomb_cooldown[slot] = 18
			elif mode.is_hen() and state.hen_slot >= 0 and slot != state.hen_slot:
				bomb = true
				bomb_cooldown[slot] = 12
			elif input_rng.next_below(18) == 0:
				bomb = true
				bomb_cooldown[slot] = 16
			var action: bool = false
			if action_cooldown[slot] > 0:
				action_cooldown[slot] -= 1
			elif input_rng.next_below(40) == 0:
				action = true
				action_cooldown[slot] = 24
			var f: InputFrame = InputFrame.new()
			f.dir = dir as InputFrame.Dir
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
				SimEvent.Kind.HEN_COLLECTED: counts["hen_collected"] += 1
				SimEvent.Kind.HEN_DROPPED: counts["hen_dropped"] += 1
				SimEvent.Kind.EGG_LAID: counts["egg_laid"] += 1
				SimEvent.Kind.EGG_HATCHED: counts["egg_hatched"] += 1

	if mode.is_hen():
		if int(counts["hen_collected"]) < 2 or int(counts["hen_dropped"]) < 1:
			printerr("golden_03 did not pass the token (collected %d, dropped %d) — not writing" % [
				counts["hen_collected"], counts["hen_dropped"]
			])
			return false

	var fingerprint: String = state.fingerprint()
	var replay_path: String = "%s/%s.hgr" % [REPLAY_DIR, name]
	var fingerprint_path: String = "%s/%s.fingerprint.txt" % [REPLAY_DIR, name]
	var err: Error = replay.save(replay_path)
	if err != OK:
		printerr("could not write %s (error %d)" % [replay_path, err])
		return false

	var check: MatchState = replay.run(balance, powerups, mode)
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
	print("mode                : %s" % mode.display_name)
	print("crate density       : %d permille (effective %d)" % [arena_def.crate_permille, state.effective_crate_permille])
	print("rules fingerprint   : %s" % SimHash.to_hex(replay.rules_fingerprint))
	print("crates remaining    : %d (cap %d)" % [state.arena.count_of(Arena.Tile.CRATE), state.crate_cap()])
	print("pickups dropped     : %d" % counts["dropped"])
	print("pickups collected   : %d" % counts["taken"])
	print("crates regenerated  : %d" % counts["regen"])
	print("bombs kicked        : %d" % counts["kicked"])
	print("bombs tossed        : %d" % counts["tossed"])
	print("curses applied      : %d" % counts["cursed"])
	if mode.is_hen():
		print("hen collected       : %d" % counts["hen_collected"])
		print("hen dropped         : %d" % counts["hen_dropped"])
		print("eggs laid           : %d" % counts["egg_laid"])
		print("eggs hatched        : %d" % counts["egg_hatched"])
	print("pickups on the floor: %d" % state.pickup_count())
	var scores: PackedStringArray = PackedStringArray()
	for p in state.players:
		if mode.is_hen():
			scores.append("P%d %ds (%dk/%dd)" % [p.index + 1, p.hen_ticks / C.TICK_HZ, p.kills, p.deaths])
		else:
			scores.append("P%d %d (%dk/%dd)" % [p.index + 1, p.score, p.kills, p.deaths])
	print("scores              : %s" % ", ".join(scores))
	print("trace digest        : %s" % replay.trace_digest)
	print("state fingerprint   : %s" % fingerprint)
	print("wrote %s and %s" % [replay_path, fingerprint_path])
	return true

## Steer toward the token when it is on the floor, hunt the Hen when someone
## holds it, wander otherwise. Deterministic: no extra sim draws, only input_rng
## for wander dither.
func _hen_dir(state: MatchState, slot: int, input_rng: SimRng) -> int:
	var p: PlayerState = state.players[slot]
	if not p.active or not p.alive:
		return InputFrame.Dir.NONE
	var target: Vector2i = Vector2i(-1, -1)
	if state.has_hen_token_on_floor():
		target = state.hen_token_tile
	elif state.hen_slot >= 0 and slot != state.hen_slot:
		target = state.players[state.hen_slot].tile()
	elif state.hen_slot == slot:
		# Prey: walk away from the nearest living hunter.
		target = _flee_tile(state, p)
	if target.x < 0:
		return input_rng.next_range(0, 4)
	return _dir_toward(p.tile(), target, input_rng)

func _flee_tile(state: MatchState, p: PlayerState) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = -1
	for other in state.players:
		if not other.active or not other.alive or other.index == p.index:
			continue
		var d: int = absi(other.tile().x - p.tile().x) + absi(other.tile().y - p.tile().y)
		if best_d < 0 or d < best_d:
			best_d = d
			best = other.tile()
	if best.x < 0:
		return Vector2i(-1, -1)
	return Vector2i(p.tile().x * 2 - best.x, p.tile().y * 2 - best.y)

func _dir_toward(from: Vector2i, to: Vector2i, input_rng: SimRng) -> int:
	var dx: int = to.x - from.x
	var dy: int = to.y - from.y
	if dx == 0 and dy == 0:
		return input_rng.next_range(0, 4)
	if absi(dx) >= absi(dy):
		return InputFrame.Dir.RIGHT if dx > 0 else InputFrame.Dir.LEFT
	return InputFrame.Dir.DOWN if dy > 0 else InputFrame.Dir.UP
