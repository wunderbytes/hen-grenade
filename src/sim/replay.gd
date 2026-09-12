class_name Replay
## A recorded round: a seed plus an input log. See docs/milestone-1-brief.md §8.
##
## Determinism is what makes this work. Seed + inputs = the same round, exactly,
## which gives us three things for the price of one:
##   - "attach the replay" as a bug-reporting mechanism;
##   - golden regression tests that catch accidental non-determinism the moment
##     it is introduced;
##   - the raw material for a replay viewer, if M6+ ever wants one.
##
## At C.MAX_PLAYERS bytes per tick a full two-minute round is about 29 KB, which
## is what makes attaching one to a bug report realistic.
##
## File format (little-endian, as Godot's FileAccess writes):
##   "HGR1"  4 bytes magic
##   u32     seed
##   u32     balance fingerprint
##   u16     grid_w
##   u16     grid_h
##   u16     crate_permille
##   u8      player_count
##   u32     tick_count
##   tick_count * C.MAX_PLAYERS bytes, slot-major within each tick

const MAGIC: String = "HGR1"
const EXTENSION: String = "hgr"

var rng_seed: int = 0
## Balance.fingerprint() at record time. Playing a replay back against retuned
## balance is a loud mismatch rather than a desync nobody can explain.
var balance_fingerprint: int = 0
var grid_w: int = C.GRID_W
var grid_h: int = C.GRID_H
var crate_permille: int = 700
var player_count: int = 0

## Packed InputFrames, C.MAX_PLAYERS bytes per tick.
var rows: PackedByteArray = PackedByteArray()

static func for_state(state: MatchState) -> Replay:
	var r: Replay = Replay.new()
	r.rng_seed = state.rng_seed
	r.balance_fingerprint = state.balance.fingerprint()
	r.grid_w = state.arena_def.grid_w
	r.grid_h = state.arena_def.grid_h
	r.crate_permille = state.arena_def.crate_permille
	r.player_count = state.active_count()
	return r

func tick_count() -> int:
	return rows.size() / C.MAX_PLAYERS

## Appends one tick of input. Call once per Sim.step, with the same frames that
## were fed to the sim — what the hardware did is irrelevant, what the sim was
## told is what has to be reproducible.
func record(frames: Array[InputFrame]) -> void:
	for i in range(C.MAX_PLAYERS):
		rows.append(frames[i].pack() if i < frames.size() else 0)

## Input for a 1-based sim tick. Ticks past the end of the log return an empty
## frame, so a replay can be run longer than it was recorded without special
## casing at the call site.
func frame_for(tick: int, slot: int) -> InputFrame:
	if tick < 1 or slot < 0 or slot >= C.MAX_PLAYERS:
		return InputFrame.new()
	var offset: int = (tick - 1) * C.MAX_PLAYERS + slot
	if offset < 0 or offset >= rows.size():
		return InputFrame.new()
	return InputFrame.unpack(rows[offset])

## All four frames for a 1-based sim tick, ready to hand to Sim.step.
func frames_for(tick: int) -> Array[InputFrame]:
	var out: Array[InputFrame] = []
	for slot in range(C.MAX_PLAYERS):
		out.append(frame_for(tick, slot))
	return out

## Rebuilds the ArenaDef this replay was recorded against. Spawn and respawn
## tiles come from the defaults rather than the file: they are layout policy,
## not per-round data, and baking them in would make every replay stale the
## moment the respawn set is tuned.
func arena_def() -> ArenaDef:
	var def: ArenaDef = ArenaDef.new()
	def.grid_w = grid_w
	def.grid_h = grid_h
	def.crate_permille = crate_permille
	return def

# --- Persistence ------------------------------------------------------------

func save(path: String) -> Error:
	var dir: String = path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		var err: Error = DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			return err
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(MAGIC.to_ascii_buffer())
	f.store_32(rng_seed)
	f.store_32(balance_fingerprint)
	f.store_16(grid_w)
	f.store_16(grid_h)
	f.store_16(crate_permille)
	f.store_8(player_count)
	f.store_32(tick_count())
	f.store_buffer(rows)
	f.close()
	return OK

## Loads a replay, or returns null on a missing file, bad magic, or a truncated
## log. Null rather than a half-populated Replay: a partially read input log
## would desync in a way that looks like a rules bug.
static func load_from(path: String) -> Replay:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Replay.load_from: cannot open %s" % path)
		return null
	var magic: String = f.get_buffer(4).get_string_from_ascii()
	if magic != MAGIC:
		push_error("Replay.load_from: %s is not a replay (magic %s)" % [path, magic])
		f.close()
		return null
	var r: Replay = Replay.new()
	r.rng_seed = f.get_32()
	r.balance_fingerprint = f.get_32()
	r.grid_w = f.get_16()
	r.grid_h = f.get_16()
	r.crate_permille = f.get_16()
	r.player_count = f.get_8()
	var ticks: int = f.get_32()
	r.rows = f.get_buffer(ticks * C.MAX_PLAYERS)
	f.close()
	if r.rows.size() != ticks * C.MAX_PLAYERS:
		push_error("Replay.load_from: %s is truncated (wanted %d input bytes, got %d)" % [path, ticks * C.MAX_PLAYERS, r.rows.size()])
		return null
	return r

## How often run() samples the state into its trace digest. 60 ticks is one
## second of play — frequent enough that a divergence cannot hide for long,
## cheap enough that hashing does not dominate the test.
const TRACE_INTERVAL: int = 60

## The rolling digest of the last run(), sampled every TRACE_INTERVAL ticks.
##
## Worth having in addition to the final fingerprint, because an end-state hash
## is blind to anything transient: a flame that burnt out, a bomb that has since
## exploded, a score that was later cancelled out. A rule change that alters
## chain ownership mid-round can leave an identical final state, and this is
## what notices.
var trace_digest: String = ""

func fresh_state(balance: Balance) -> MatchState:
	var active: Array[bool] = []
	for i in range(C.MAX_PLAYERS):
		active.append(i < player_count)
	return MatchState.create(balance, arena_def(), rng_seed, active)

## Replays this log against a fresh MatchState and returns the final state,
## leaving `trace_digest` set. The determinism harness: the caller compares both
## the final fingerprint and the trace against committed values.
func run(balance: Balance) -> MatchState:
	var state: MatchState = fresh_state(balance)
	var trace: int = SimHash.start()
	var total: int = tick_count()
	for t in range(1, total + 1):
		Sim.step(state, frames_for(t))
		if t % TRACE_INTERVAL == 0:
			trace = _mix_text(trace, state.fingerprint())
	trace = _mix_text(trace, state.fingerprint())
	trace_digest = SimHash.to_hex(trace)
	return state

static func _mix_text(h: int, text: String) -> int:
	return SimHash.mix_bytes(h, text.to_ascii_buffer())
