extends Node2D
## Hosts one round: owns the MatchState, drives the fixed step, feeds the views,
## and records the replay. See docs/milestone-1-brief.md §9.
##
## This is the only file in M1 that touches both the simulation and the scene
## tree, and it is deliberately thin. Everything it does is plumbing: poll,
## step, record, draw. No rule lives here — if a behaviour question can be
## answered by reading this file, it is in the wrong place.

const BALANCE_PATH: String = "res://data/balance/default.tres"
const ARENA_DEF_PATH: String = "res://data/arenas/default.tres"
const REPLAY_DIR: String = "user://replays"

const TITLE_SCENE: String = "res://src/app/main.tscn"
const STRESS_SCENE: String = "res://src/dev/stress.tscn"
const SANDBOX_SCENE: String = "res://src/dev/sandbox.tscn"

var state: MatchState = null
var replay: Replay = null

## Ticks fed to the simulation this round. Distinct from state.tick only in that
## this also counts the polls, which is what the replay log is indexed by.
var _tick: int = 0
var _round_over: bool = false

var _arena_view: TileMapLayer
var _entities: Node2D
var _hud: Node2D
var _metrics: Node = null

func _ready() -> void:
	_arena_view = get_node("ArenaLayer")
	_entities = get_node("Entities")
	_hud = get_node("Hud")
	_arena_view.setup()
	_entities.position = Vector2(C.ARENA_ORIGIN)
	# The overlay is a measurement tool, and it is not free: every Label it
	# draws is a draw call it then reports. It stays off in the game scene and
	# on in the dev scenes, so the number you read here is the game's.
	_metrics = load("res://src/app/metrics_overlay.tscn").instantiate()
	_metrics.visible = false
	add_child(_metrics)
	start_round(_fresh_seed())

## Begins a round. The seed is chosen here, outside the simulation, and then
## never touched again: everything downstream of it is deterministic, which is
## what makes "the seed on the scoreboard replays the layout" true.
func start_round(seed_value: int) -> void:
	# No lobby until M2, so make the game playable straight from launch by
	# claiming the keyboard layouts if nothing has joined. Bound pads win.
	DeviceManager.ensure_keyboard_slots(2)

	var balance: Balance = _load_balance()
	var arena_def: ArenaDef = _load_arena_def()
	var active: Array[bool] = []
	for i in range(C.MAX_PLAYERS):
		active.append(DeviceManager.slots[i].is_occupied())

	state = MatchState.create(balance, arena_def, seed_value, active)
	replay = Replay.for_state(state)
	_tick = 0
	_round_over = false

	_arena_view.sync(state.arena)
	_entities.state = state
	_entities.queue_redraw()
	_hud.hide_result()
	_hud.sync(state)

func _physics_process(_delta: float) -> void:
	if _round_over:
		return
	_tick += 1
	# Never read _delta here or anywhere downstream. If a frame runs long and
	# Godot takes two physics steps, both get the same polled input — which is
	# correct and stays deterministic, because the replay logs what the sim was
	# told rather than what the hardware did.
	var frames: Array[InputFrame] = DeviceManager.poll_all(_tick)
	replay.record(frames)
	var events: Array[SimEvent] = Sim.step(state, frames)
	_apply_events(events)
	_entities.queue_redraw()
	_hud.sync(state)

## The view's only reaction to the simulation besides reading state. Kept to the
## events that change something the view caches — everything else is redrawn
## from state every frame anyway.
func _apply_events(events: Array[SimEvent]) -> void:
	for e in events:
		match e.kind:
			SimEvent.Kind.CRATE_DESTROYED:
				_arena_view.clear_crate(e.tile)
			SimEvent.Kind.ROUND_ENDED:
				_end_round()

func _end_round() -> void:
	_round_over = true
	_hud.show_result(state)
	_save_replay()

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_R:
			if _round_over:
				start_round(_fresh_seed())
		KEY_F1:
			get_tree().change_scene_to_file(TITLE_SCENE)
		KEY_F2:
			get_tree().change_scene_to_file(STRESS_SCENE)
		KEY_F3:
			get_tree().change_scene_to_file(SANDBOX_SCENE)
		KEY_F5:
			if _metrics != null:
				_metrics.visible = not _metrics.visible

# --- Smoke support ----------------------------------------------------------

## Steps the simulation without waiting on scene-tree frames, for the CI smoke
## check. Uses blank input rather than polling devices, so it does not depend on
## whatever happens to be plugged in on a build agent.
func smoke_step(ticks: int) -> void:
	var frames: Array[InputFrame] = []
	for _i in range(C.MAX_PLAYERS):
		frames.append(InputFrame.new())
	for _i in range(ticks):
		if _round_over:
			return
		_tick += 1
		replay.record(frames)
		_apply_events(Sim.step(state, frames))
		_hud.sync(state)

## Runs the round out to the clock, exercising the paths a 40-tick smoke never
## reaches: the round-end banner, the winner calculation and the replay write.
## A full 7200-tick round costs a fraction of a second with no rendering, which
## is a cheap way to find out that the last two seconds of a match crash.
func smoke_finish_round() -> void:
	smoke_step(state.balance.round_ticks + 10)
	if not _round_over:
		printerr("  WARN  match scene did not reach the end of its round")

# --- Loading ----------------------------------------------------------------

## Falls back to code defaults if the resource is missing or has been replaced
## by something else. A broken balance file should not be an unexplained crash
## at round start.
func _load_balance() -> Balance:
	var res: Resource = load(BALANCE_PATH)
	if res is Balance:
		return res as Balance
	push_warning("%s is missing or not a Balance; using built-in defaults" % BALANCE_PATH)
	return Balance.new()

func _load_arena_def() -> ArenaDef:
	var res: Resource = load(ARENA_DEF_PATH)
	if res is ArenaDef:
		return res as ArenaDef
	push_warning("%s is missing or not an ArenaDef; using built-in defaults" % ARENA_DEF_PATH)
	return ArenaDef.new()

func _fresh_seed() -> int:
	# Outside the simulation, so a wall-clock read is fine here and only here.
	return int(Time.get_unix_time_from_system()) ^ (Time.get_ticks_usec() & 0xFFFF)

func _save_replay() -> void:
	if replay == null or replay.tick_count() == 0:
		return
	var path: String = "%s/round_%d.%s" % [REPLAY_DIR, state.rng_seed, Replay.EXTENSION]
	var err: Error = replay.save(path)
	if err == OK:
		print("replay saved: %s (seed %d, %d ticks)" % [path, state.rng_seed, replay.tick_count()])
	else:
		push_warning("could not save replay to %s (error %d)" % [path, err])
