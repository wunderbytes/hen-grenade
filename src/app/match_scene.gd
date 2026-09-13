extends Node2D
## Hosts a match: owns the MatchState and the MatchRecord, drives the fixed step,
## feeds the views, records the replay, and owns the round and match lifecycle.
## See docs/milestone-1-brief.md §9, docs/milestone-2-brief.md §6, and
## docs/milestone-3-brief.md §6.
##
## Still the only file that touches both the simulation and the scene tree, and
## still deliberately thin: poll, step, record, draw. No rule lives here — if a
## behaviour question can be answered by reading this file, it is in the wrong
## place. Best-of-3 is the one piece of judgement that lives nearby, and even
## that is delegated to `MatchRecord`, which is pure and tested.
##
## M2 added the phase machine. M3 replaced its ROUND_OVER with SCOREBOARD and
## MATCH_OVER, because "the round ended" and "the match ended" are different
## questions and only one of them has a rematch on it.

const BALANCE_PATH: String = "res://data/balance/default.tres"
const ARENA_DEF_PATH: String = "res://data/arenas/default.tres"
const POWERUPS_PATH: String = "res://data/balance/powerups.tres"
const MATCH_RULES_PATH: String = "res://data/balance/match.tres"
const REPLAY_DIR: String = "user://replays"

const LOBBY_SCENE: String = "res://src/ui/lobby_scene.tscn"
const TITLE_SCENE: String = "res://src/app/main.tscn"
const STRESS_SCENE: String = "res://src/dev/stress.tscn"
const SANDBOX_SCENE: String = "res://src/dev/sandbox.tscn"

enum Phase { RUNNING = 0, PAUSED = 1, RECONNECT = 2, SCOREBOARD = 3, MATCH_OVER = 4 }

const PAUSE_OPTIONS: Array[String] = ["Resume", "Restart round", "Quit to lobby"]
const OPT_RESUME: int = 0
const OPT_RESTART: int = 1
const OPT_LOBBY: int = 2

var state: MatchState = null
var replay: Replay = null
var record: MatchRecord = null

## Ticks fed to the simulation this round. Distinct from state.tick only in that
## this also counts the polls, which is what the replay log is indexed by.
var _tick: int = 0
var _phase: Phase = Phase.RUNNING
## Where a reconnect returns to. A pad lost while the pause menu or the
## scoreboard was up should put that back, not drop the player into a live round.
var _resume_phase: Phase = Phase.RUNNING
var _cursor: MenuCursor = null
## Which slots the notice is currently naming, so it is only rebuilt on change.
var _notified_slots: Array[int] = []
## Counts the scoreboard down. It advances itself, because four people on a sofa
## should not have to agree to press a button between rounds.
var _scoreboard_ticks: int = 0

var _rules: MatchRules = null
var _mode: GameMode = null
var _arena_view: TileMapLayer
var _entities: Node2D
var _hud: Node2D
var _overlay: Node2D
var _metrics: Node = null

func _ready() -> void:
	_arena_view = get_node("ArenaLayer")
	_entities = get_node("Entities")
	_hud = get_node("Hud")
	_overlay = get_node("Overlay")
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
	_mode = Session.load_mode()
	_rules = _load_match_rules()
	start_match()

## Begins a best-of-3. Entering this scene starts a match and leaving it ends
## one, which is why the record does not have to survive a scene change.
func start_match() -> void:
	record = MatchRecord.from_rules(_rules)
	record.set_active(DeviceManager.active_flags())
	start_round(_fresh_seed())

## Begins a round. The seed is chosen here, outside the simulation, and then
## never touched again: everything downstream of it is deterministic, which is
## what makes "the seed on the scoreboard replays the layout" true.
func start_round(seed_value: int) -> void:
	state = MatchState.create(_load_balance(), _load_arena_def(), seed_value, DeviceManager.active_flags(), _load_powerups(), _mode)
	replay = Replay.for_state(state)
	_tick = 0
	_set_phase(Phase.RUNNING)
	_resume_phase = Phase.RUNNING

	_arena_view.sync(state.arena)
	_entities.state = state
	_entities.queue_redraw()
	_hud.sync(state, record)

func _physics_process(_delta: float) -> void:
	match _phase:
		Phase.RUNNING:
			_tick_running()
		Phase.PAUSED:
			_tick_paused()
		Phase.RECONNECT:
			_tick_reconnect()
		Phase.SCOREBOARD:
			_tick_scoreboard()
		Phase.MATCH_OVER:
			_tick_match_over()

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
	_hud.sync(state, record)

## Pausing does not slow the simulation or skip ticks — it stops calling it. The
## sim has no idea a pause exists, which is the only way it stays deterministic,
## and because `record()` is called from the same place as `step()`, a paused
## round records nothing rather than recording a gap.
func _tick_paused() -> void:
	if not DeviceManager.disconnected_slots().is_empty():
		_enter_reconnect(Phase.PAUSED)
		return
	if _cursor.update(DeviceManager.menu_dir()):
		_overlay.show_menu(PAUSE_OPTIONS, _cursor.index)
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
		_reenter(_resume_phase)
		return
	if waiting != _notified_slots:
		_notified_slots = waiting
		_overlay.show_reconnect(waiting)
	# Always an exit. A party game that can be soft-locked by a loose USB plug is
	# worse than one with no hot-plug handling at all.
	if DeviceManager.menu_pressed(DeviceManager.Menu.BACK):
		_quit_to_lobby()

## The between-rounds beat. It advances itself after `scoreboard_ticks` and CONFIRM
## skips it (game design §3).
##
## A lost pad raises the notice from here too, and that is not politeness: the
## next round rebuilds `active_slots` from the roster, so a seat still reserved
## when it starts would silently drop that player out of the match.
func _tick_scoreboard() -> void:
	if not DeviceManager.disconnected_slots().is_empty():
		_enter_reconnect(Phase.SCOREBOARD)
		return
	if _scoreboard_ticks > 0:
		_scoreboard_ticks -= 1
		# Only redraw on a change of the displayed second, not every tick.
		if _scoreboard_ticks % C.TICK_HZ == 0:
			_show_scoreboard()
	if _scoreboard_ticks <= 0 or DeviceManager.menu_pressed(DeviceManager.Menu.CONFIRM):
		_advance_match()

func _tick_match_over() -> void:
	if DeviceManager.menu_pressed(DeviceManager.Menu.CONFIRM):
		start_match()
		return
	if DeviceManager.menu_pressed(DeviceManager.Menu.BACK):
		_quit_to_lobby()

# --- Transitions -------------------------------------------------------------

func _set_phase(p: Phase) -> void:
	_phase = p
	if p == Phase.RUNNING:
		_overlay.hide_overlay()

## Re-enters a phase that was interrupted, putting its overlay back. A phase
## machine with two states that own a panel needs one of these, or a reconnect
## returns to a scoreboard with nothing on the screen.
func _reenter(p: Phase) -> void:
	match p:
		Phase.PAUSED:
			_enter_pause()
		Phase.SCOREBOARD:
			_set_phase(Phase.SCOREBOARD)
			_show_scoreboard()
		_:
			_resume()

func _enter_pause() -> void:
	_set_phase(Phase.PAUSED)
	_resume_phase = Phase.PAUSED
	_cursor.reset(OPT_RESUME)
	_overlay.show_menu(PAUSE_OPTIONS, _cursor.index)

func _enter_reconnect(return_to: Phase) -> void:
	_resume_phase = return_to
	_set_phase(Phase.RECONNECT)
	_notified_slots = DeviceManager.disconnected_slots()
	_overlay.show_reconnect(_notified_slots)

func _resume() -> void:
	_resume_phase = Phase.RUNNING
	_set_phase(Phase.RUNNING)

func _activate(option: int) -> void:
	match option:
		OPT_RESUME:
			_resume()
		OPT_RESTART:
			# A do-over, not a result: the round is not filed with the record.
			# Abandons this round's replay deliberately too — a replay is written
			# at a clean round end, and a half-round log whose last input is
			# "someone pressed Start" is a file nobody will be glad to have.
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
			SimEvent.Kind.CRATE_SPAWNED:
				_arena_view.set_crate(e.tile)
			SimEvent.Kind.ROUND_ENDED:
				_end_round()

## Files the round with the record, writes the replay, and shows the scoreboard.
## The match itself does not end here — the scoreboard decides where to go next,
## so there is exactly one place that asks `record.is_over()`.
func _end_round() -> void:
	record.record_round_from(state)
	_save_replay()
	_scoreboard_ticks = _rules.scoreboard_ticks
	_set_phase(Phase.SCOREBOARD)
	_show_scoreboard()

func _show_scoreboard() -> void:
	_overlay.show_scoreboard(state, record, (_scoreboard_ticks + C.TICK_HZ - 1) / C.TICK_HZ)

func _advance_match() -> void:
	if record.is_over():
		_set_phase(Phase.MATCH_OVER)
		_overlay.show_match_result(record, state)
		return
	start_round(_fresh_seed())

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_R:
			if _phase == Phase.MATCH_OVER:
				start_match()
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
		if _phase != Phase.RUNNING:
			return
		_tick += 1
		replay.record(frames)
		_apply_events(Sim.step(state, frames))
		_hud.sync(state, record)

## Runs the round out to the clock, exercising the paths a 40-tick smoke never
## reaches: the scoreboard, the winner calculation and the replay write.
## A full 7200-tick round costs a fraction of a second with no rendering, which
## is a cheap way to find out that the last two seconds of a match crash.
func smoke_finish_round() -> void:
	smoke_step(state.balance.round_ticks + 10)
	if _phase != Phase.SCOREBOARD:
		printerr("  WARN  match scene did not reach the end of its round")

## The overlay in each of its four modes, driven by the smoke loop so that each
## one gets a real frame to draw in. Widget-only: it deliberately does not touch
## the phase machine, because a RECONNECT phase with nothing disconnected would
## exit itself on the next tick and the notice would never be drawn.
func smoke_overlay_menu() -> void:
	_overlay.show_menu(PAUSE_OPTIONS, 1)

func smoke_overlay_reconnect() -> void:
	_overlay.show_reconnect([1, 2] as Array[int])

func smoke_overlay_scoreboard() -> void:
	_overlay.show_scoreboard(state, record, 4)

func smoke_overlay_match_result() -> void:
	var shown: MatchRecord = MatchRecord.from_rules(_rules)
	shown.set_active(DeviceManager.active_flags())
	shown.record_round(0, PackedInt32Array([4, 2, 1, 0]))
	shown.record_round(0, PackedInt32Array([3, 3, 2, 1]))
	_overlay.show_match_result(shown)

func smoke_overlay_hen_scoreboard() -> void:
	var hen_mode: GameMode = GameMode.hen()
	var hen_state: MatchState = MatchState.create(
		_load_balance(), _load_arena_def(), 1, DeviceManager.active_flags(), _load_powerups(), hen_mode
	)
	for p in hen_state.players:
		p.hen_ticks = 300 * C.TICK_HZ
		p.kills = 12
		p.deaths = 12
		p.score = -3
	var hen_rules: MatchRules = MatchRules.new()
	hen_rules.round_wins_to_take_match = 1
	hen_rules.max_rounds = 1
	var shown: MatchRecord = MatchRecord.from_rules(hen_rules)
	shown.set_active(DeviceManager.active_flags())
	shown.record_round(0, PackedInt32Array([18000, 12000, 6000, 0]))
	_overlay.show_scoreboard(hen_state, shown, 4)

func smoke_overlay_hide() -> void:
	_overlay.hide_overlay()

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
	if record.rounds_played() != 0:
		problems.append("Restart round filed a result with the match record")

	problems.append_array(_smoke_match_flow())
	problems.append_array(_smoke_hen_match_flow())
	problems.append_array(_smoke_overlay_geometry())
	return problems

## Every overlay mode, checked for text that does not fit its panel. The panel
## now sizes itself to its content, which is exactly the kind of thing that runs
## off a 640 x 360 screen without anybody noticing until a photo of a TV arrives.
func _smoke_overlay_geometry() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var record_shown: MatchRecord = MatchRecord.from_rules(_rules)
	record_shown.set_active(DeviceManager.active_flags())
	# A record with a played round, so the scoreboard has a title and a tally.
	record_shown.record_round(0, PackedInt32Array([12, -3, 7, 0]))

	smoke_overlay_menu()
	problems.append_array(_overlay.geometry_problems("pause menu"))
	_overlay.show_reconnect([0, 1, 2, 3] as Array[int])
	problems.append_array(_overlay.geometry_problems("reconnect notice, all four"))
	# Worst case for a scoreboard row: four active players, the longest labels,
	# and a score wide enough to shift the columns.
	_overlay.show_scoreboard(state, record_shown, 4)
	problems.append_array(_overlay.geometry_problems("scoreboard"))
	_overlay.show_match_result(record_shown)
	problems.append_array(_overlay.geometry_problems("winner screen"))
	smoke_overlay_hen_scoreboard()
	problems.append_array(_overlay.geometry_problems("hen scoreboard"))
	_overlay.hide_overlay()
	return problems

## The M3 half: a round ends, the scoreboard appears, it advances itself, and the
## match ends when the record says so rather than when a round does.
func _smoke_match_flow() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()

	_end_round()
	if _phase != Phase.SCOREBOARD:
		problems.append("the end of a round did not raise the scoreboard")
	if record.rounds_played() != 1:
		problems.append("the round was not filed with the match record")
	var rounds_before: int = record.rounds_played()
	_tick_scoreboard()
	if _phase != Phase.SCOREBOARD:
		problems.append("the scoreboard advanced on its own after one tick")

	# A pad lost on the scoreboard must come back to the scoreboard, not to a
	# live round: the next round's roster is read at the moment it starts.
	_enter_reconnect(Phase.SCOREBOARD)
	_physics_process(1.0 / C.TICK_HZ)
	if _phase != Phase.SCOREBOARD:
		problems.append("a reconnect did not return to the scoreboard")

	# Run the countdown out; it must start the next round by itself.
	for _i in range(_rules.scoreboard_ticks + 2):
		if _phase != Phase.SCOREBOARD:
			break
		_tick_scoreboard()
	if _phase != Phase.RUNNING:
		problems.append("the scoreboard did not start the next round by itself")
	if record.rounds_played() != rounds_before:
		problems.append("advancing the scoreboard filed a second result")

	# Take the match, and check the winner screen rather than another round.
	while not record.is_over():
		record.record_round(0)
	_set_phase(Phase.SCOREBOARD)
	_scoreboard_ticks = 0
	_tick_scoreboard()
	if _phase != Phase.MATCH_OVER:
		problems.append("a finished match started another round")
	if record.winner() != 0:
		problems.append("the match winner was not the player who won every round")

	_tick_match_over()          # nothing pressed: must stay put
	if _phase != Phase.MATCH_OVER:
		problems.append("the winner screen advanced on its own")

	start_match()               # the rematch path
	if _phase != Phase.RUNNING:
		problems.append("a rematch did not start a round")
	if record.rounds_played() != 0:
		problems.append("a rematch kept the previous match's record")
	return problems

## A shortened Hen round: one round is the match. Uses a 90-tick clock so smoke
## does not sit through 5:00.
func _smoke_hen_match_flow() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var previous_mode: GameMode = _mode
	var previous_rules: MatchRules = _rules
	_mode = GameMode.hen()
	_mode.round_ticks = 90
	_rules = MatchRules.new()
	_rules.round_wins_to_take_match = 1
	_rules.max_rounds = 1
	_rules.scoreboard_ticks = 12
	start_match()
	if not state.mode.is_hen():
		problems.append("hen smoke did not start in hen mode")
	if state.round_ticks_left != 90:
		problems.append("hen smoke did not use the shortened clock")
	smoke_step(state.round_ticks_left + 5)
	if _phase != Phase.SCOREBOARD:
		problems.append("a hen round did not raise the scoreboard")
	for _i in range(_rules.scoreboard_ticks + 2):
		if _phase != Phase.SCOREBOARD:
			break
		_tick_scoreboard()
	if _phase != Phase.MATCH_OVER:
		problems.append("a finished hen match started another round")
	_mode = previous_mode
	_rules = previous_rules
	start_match()
	return problems

# --- Loading ----------------------------------------------------------------

## Falls back to code defaults if a resource is missing or has been replaced by
## something else. A broken data file should not be an unexplained crash at round
## start — and M3 tripled the number of data files that could be broken.
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

func _load_powerups() -> PowerupTable:
	var res: Resource = load(POWERUPS_PATH)
	if res is PowerupTable:
		return res as PowerupTable
	push_warning("%s is missing or not a PowerupTable; using built-in defaults" % POWERUPS_PATH)
	return PowerupTable.new()

func _load_match_rules() -> MatchRules:
	var path: String = MATCH_RULES_PATH
	if _mode != null and _mode.match_rules_path != "":
		path = _mode.match_rules_path
	var res: Resource = load(path)
	if res is MatchRules:
		return res as MatchRules
	push_warning("%s is missing or not a MatchRules; using built-in defaults" % path)
	if _mode != null and _mode.is_hen():
		var hen_rules: MatchRules = MatchRules.new()
		hen_rules.round_wins_to_take_match = 1
		hen_rules.max_rounds = 1
		return hen_rules
	return MatchRules.new()

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
