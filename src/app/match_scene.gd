extends Node2D
## Hosts one round: owns the MatchState, drives the fixed step, feeds the views,
## records the replay, and owns the round lifecycle.
## See docs/milestone-1-brief.md §9 and docs/milestone-2-brief.md §6.
##
## Still the only file that touches both the simulation and the scene tree, and
## still deliberately thin: poll, step, record, draw. No rule lives here — if a
## behaviour question can be answered by reading this file, it is in the wrong
## place.
##
## M2 added the phase machine. M1 had an implicit two states, playing or
## finished, which cannot express "stopped because P3's pad fell out of the hub".

const BALANCE_PATH: String = "res://data/balance/default.tres"
const ARENA_DEF_PATH: String = "res://data/arenas/default.tres"
const REPLAY_DIR: String = "user://replays"

const LOBBY_SCENE: String = "res://src/ui/lobby_scene.tscn"
const TITLE_SCENE: String = "res://src/app/main.tscn"
const STRESS_SCENE: String = "res://src/dev/stress.tscn"
const SANDBOX_SCENE: String = "res://src/dev/sandbox.tscn"

enum Phase { RUNNING = 0, PAUSED = 1, RECONNECT = 2, ROUND_OVER = 3 }

const PAUSE_OPTIONS: Array[String] = ["Resume", "Restart round", "Quit to lobby"]
const OPT_RESUME: int = 0
const OPT_RESTART: int = 1
const OPT_LOBBY: int = 2

var state: MatchState = null
var replay: Replay = null

## Ticks fed to the simulation this round. Distinct from state.tick only in that
## this also counts the polls, which is what the replay log is indexed by.
var _tick: int = 0
var _phase: Phase = Phase.RUNNING
## Where a reconnect returns to. A pad lost while the pause menu was open should
## put the menu back, not drop the player into a live round.
var _resume_phase: Phase = Phase.RUNNING
var _cursor: MenuCursor = null
## Which slots the notice is currently naming, so it is only rebuilt on change.
var _notified_slots: Array[int] = []

var _arena_view: TileMapLayer
var _entities: Node2D
var _hud: Node2D
var _pause: Node2D
var _metrics: Node = null

func _ready() -> void:
	_arena_view = get_node("ArenaLayer")
	_entities = get_node("Entities")
	_hud = get_node("Hud")
	_pause = get_node("Pause")
	_arena_view.setup()
	_entities.position = Vector2(C.ARENA_ORIGIN)
	_cursor = MenuCursor.new(PAUSE_OPTIONS.size())
	# The overlay is a measurement tool, and it is not free: every Label it
	# draws is a draw call it then reports. It stays off in the game scene and
	# on in the dev scenes, so the number you read here is the game's.
	_metrics = load("res://src/app/metrics_overlay.tscn").instantiate()
	_metrics.visible = false
	add_child(_metrics)

	# The roster is now decided in the lobby and frozen for the round. The dev
	# roster below only fires when there is no roster at all, which means either
	# F4-straight-to-match or the CI smoke.
	DeviceManager.enter_match()
	DeviceManager.ensure_dev_roster()
	start_round(_fresh_seed())

## Begins a round. The seed is chosen here, outside the simulation, and then
## never touched again: everything downstream of it is deterministic, which is
## what makes "the seed on the scoreboard replays the layout" true.
func start_round(seed_value: int) -> void:
	var balance: Balance = _load_balance()
	var arena_def: ArenaDef = _load_arena_def()

	state = MatchState.create(balance, arena_def, seed_value, DeviceManager.active_flags())
	replay = Replay.for_state(state)
	_tick = 0
	_set_phase(Phase.RUNNING)
	_resume_phase = Phase.RUNNING

	_arena_view.sync(state.arena)
	_entities.state = state
	_entities.queue_redraw()
	_hud.hide_result()
	_hud.sync(state)

func _physics_process(_delta: float) -> void:
	match _phase:
		Phase.RUNNING:
			_tick_running()
		Phase.PAUSED:
			_tick_paused()
		Phase.RECONNECT:
			_tick_reconnect()
		Phase.ROUND_OVER:
			_tick_round_over()

# --- Phases ------------------------------------------------------------------

func _tick_running() -> void:
	# A lost pad outranks everything, including a pause the player is about to
	# ask for on the same frame.
	if not DeviceManager.disconnected_slots().is_empty():
		_enter_reconnect(Phase.RUNNING)
		return
	if DeviceManager.menu_pressed(DeviceManager.Menu.START):
		_enter_pause()
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

## Pausing does not slow the simulation or skip ticks — it stops calling it. The
## sim has no idea a pause exists, which is the only way it stays deterministic,
## and because `record()` is called from the same place as `step()`, a paused
## round records nothing rather than recording a gap.
func _tick_paused() -> void:
	if not DeviceManager.disconnected_slots().is_empty():
		_enter_reconnect(Phase.PAUSED)
		return
	if _cursor.update(DeviceManager.menu_dir()):
		_pause.show_menu(PAUSE_OPTIONS, _cursor.index)
	# CONFIRM before START, because Enter is both: here it should choose the
	# highlighted item, and in the lobby the same key begins the match.
	if DeviceManager.menu_pressed(DeviceManager.Menu.CONFIRM):
		_activate(_cursor.index)
		return
	# BACK closes the menu rather than quitting the round. Four people with pads
	# and B as the in-round action button makes a stray press likely, and
	# abandoning everyone's round on one is too much to hang off a reflex —
	# quitting is the explicit third item. The reconnect notice is the exception,
	# because there is no menu there to back out of.
	if DeviceManager.menu_pressed(DeviceManager.Menu.START) or DeviceManager.menu_pressed(DeviceManager.Menu.BACK):
		_resume()

func _tick_reconnect() -> void:
	var waiting: Array[int] = DeviceManager.disconnected_slots()
	if waiting.is_empty():
		if _resume_phase == Phase.PAUSED:
			_enter_pause()
		else:
			_resume()
		return
	if waiting != _notified_slots:
		_notified_slots = waiting
		_pause.show_reconnect(waiting)
	# Always an exit. A party game that can be soft-locked by a loose USB plug is
	# worse than one with no hot-plug handling at all.
	if DeviceManager.menu_pressed(DeviceManager.Menu.BACK):
		_quit_to_lobby()

func _tick_round_over() -> void:
	if DeviceManager.menu_pressed(DeviceManager.Menu.CONFIRM):
		start_round(_fresh_seed())
		return
	if DeviceManager.menu_pressed(DeviceManager.Menu.BACK):
		_quit_to_lobby()

# --- Transitions -------------------------------------------------------------

func _set_phase(p: Phase) -> void:
	_phase = p
	if p == Phase.RUNNING:
		_pause.hide_overlay()

func _enter_pause() -> void:
	_set_phase(Phase.PAUSED)
	_resume_phase = Phase.PAUSED
	_cursor.reset(OPT_RESUME)
	_pause.show_menu(PAUSE_OPTIONS, _cursor.index)

func _enter_reconnect(return_to: Phase) -> void:
	_resume_phase = return_to
	_set_phase(Phase.RECONNECT)
	_notified_slots = DeviceManager.disconnected_slots()
	_pause.show_reconnect(_notified_slots)

func _resume() -> void:
	_resume_phase = Phase.RUNNING
	_set_phase(Phase.RUNNING)

func _activate(option: int) -> void:
	match option:
		OPT_RESUME:
			_resume()
		OPT_RESTART:
			# Abandons this round's replay deliberately: a replay is written at a
			# clean round end, and a half-round log whose last input is "someone
			# pressed Start" is a file nobody will be glad to have.
			start_round(_fresh_seed())
		OPT_LOBBY:
			_quit_to_lobby()

func _quit_to_lobby() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)

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
	_set_phase(Phase.ROUND_OVER)
	_hud.show_result(state)
	_save_replay()

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_R:
			if _phase == Phase.ROUND_OVER:
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
		if _phase == Phase.ROUND_OVER:
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
	if _phase != Phase.ROUND_OVER:
		printerr("  WARN  match scene did not reach the end of its round")

## The overlay in each of its two modes, driven by the smoke loop so that each
## one gets a real frame to draw in. Widget-only: it deliberately does not touch
## the phase machine, because a RECONNECT phase with nothing disconnected would
## exit itself on the next tick and the notice would never be drawn.
func smoke_overlay_menu() -> void:
	_pause.show_menu(PAUSE_OPTIONS, 1)

func smoke_overlay_reconnect() -> void:
	_pause.show_reconnect([1, 2] as Array[int])

func smoke_overlay_hide() -> void:
	_pause.hide_overlay()

## Walks the phase machine by calling its transitions directly and reports what
## did not happen. This is the only verification the phase machine gets: it hangs
## off the DeviceManager autoload, and autoloads do not exist in the `--script`
## process the unit tests run in (Appendix A.2).
func smoke_phases() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var initial_seed: int = state.rng_seed

	_enter_pause()
	if _phase != Phase.PAUSED:
		problems.append("START did not pause")
	# A paused round must not advance. Both counters, because `_tick` is what the
	# replay is indexed by and `state.tick` is what the rules ran on.
	var tick_before: int = _tick
	var sim_tick_before: int = state.tick
	for _i in range(3):
		_physics_process(1.0 / C.TICK_HZ)
	if _tick != tick_before or state.tick != sim_tick_before:
		problems.append("the simulation advanced while paused")

	_enter_reconnect(Phase.PAUSED)
	if _phase != Phase.RECONNECT:
		problems.append("a lost pad did not raise the reconnect notice")
	# Nothing is actually unplugged in a smoke run, so the notice clears itself
	# on the next tick — and must hand back to the pause menu it interrupted.
	_physics_process(1.0 / C.TICK_HZ)
	if _phase != Phase.PAUSED:
		problems.append("a reconnect did not return to the pause menu")

	_activate(OPT_RESUME)
	if _phase != Phase.RUNNING:
		problems.append("Resume did not resume")

	_enter_pause()
	_activate(OPT_RESTART)
	if _phase != Phase.RUNNING:
		problems.append("Restart round did not resume the round")
	if state.rng_seed == initial_seed:
		problems.append("Restart round reused the seed")
	if state.tick != 0:
		problems.append("Restart round did not reset the clock")

	_end_round()
	if _phase != Phase.ROUND_OVER:
		problems.append("the round did not end")
	var ended_seed: int = state.rng_seed
	_tick_round_over()          # nothing pressed: must stay put
	if _phase != Phase.ROUND_OVER or state.rng_seed != ended_seed:
		problems.append("the round-over screen advanced on its own")
	start_round(_fresh_seed())  # the rematch path
	if _phase != Phase.RUNNING:
		problems.append("a rematch did not start a round")
	return problems

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
