extends Node2D
## Bootstrap / scene router. The project's main scene.
## See docs/milestone-0-brief.md §5 and docs/milestone-1-brief.md §11.
##
## Also hosts the CI smoke check (`--smoke`). That lives here rather than in a
## standalone script because of two M0 lessons (technical-design.md Appendix A):
## running a scene via `--script` leaves autoloads unregistered (A.2), and
## passing a scene path to the editor binary opens the editor rather than
## running the game (A.3). Booting the real main scene with a user argument is
## the only way to exercise scenes the way a player would.

const LOBBY: String = "res://src/ui/lobby_scene.tscn"
const MATCH: String = "res://src/app/match_scene.tscn"
const SANDBOX: String = "res://src/dev/sandbox.tscn"
const STRESS: String = "res://src/dev/stress.tscn"

## How long the title card sits before the game starts itself.
const TITLE_SECONDS: float = 1.2

func _ready() -> void:
	if _smoke_requested():
		_run_smoke()
		return
	if _measure_requested():
		_run_measure()
		return
	_add_label("HEN GRENADE", Vector2(C.VIEW_W / 2.0 - 70, C.VIEW_H / 2.0 - 24), 16, Color(0.95, 0.95, 0.9))
	_add_label("M3.6 — Customize", Vector2(C.VIEW_W / 2.0 - 70, C.VIEW_H / 2.0 - 4), 8, Color(0.7, 0.8, 0.7))
	_add_label("pads join with A · keyboard with Space / Right Ctrl", Vector2(C.VIEW_W / 2.0 - 148, C.VIEW_H / 2.0 + 12), 8, Color(0.7, 0.75, 0.7))
	_add_label("SPACE lobby   F2 stress   F3 sandbox", Vector2(C.VIEW_W / 2.0 - 112, C.VIEW_H / 2.0 + 30), 8, Color(0.6, 0.7, 0.6))
	await get_tree().create_timer(TITLE_SECONDS).timeout
	if is_instance_valid(self) and get_tree().current_scene == self:
		get_tree().change_scene_to_file(LOBBY)

## The title card is a beat, not a menu: everything here leads to the lobby,
## which is the game's real root screen. `F4` still jumps straight into a round
## for development, where the match scene's dev roster stands in for a lobby.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE, KEY_ENTER:
			get_tree().change_scene_to_file(LOBBY)
		KEY_F4:
			get_tree().change_scene_to_file(MATCH)
		KEY_F2:
			get_tree().change_scene_to_file(STRESS)
		KEY_F3:
			get_tree().change_scene_to_file(SANDBOX)

func _add_label(text: String, pos: Vector2, size: int, color: Color) -> void:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.vertical_alignment = 0
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	add_child(lbl)

# --- Smoke check ------------------------------------------------------------

## Scenes visited by the smoke check, in order. The lobby is in here because it
## is a scene with a `_draw` and per-frame input reads, which is precisely the
## shape of thing Appendix A.1 says `--import` will not check.
const SMOKE_SCENES: Array[String] = [MATCH, LOBBY, SANDBOX, STRESS]
const SMOKE_TICKS: int = 40

func _smoke_requested() -> bool:
	return OS.get_cmdline_user_args().has("--smoke")

func _measure_requested() -> bool:
	return OS.get_cmdline_user_args().has("--measure")

## Prints the draw-call and frame-time counters for a live round, so the budget
## in technical design §5 can be checked without a person squinting at the F5
## overlay and reading numbers off a photograph.
##
## **This one cannot run headless.** `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` comes from
## the rendering driver, and the dummy driver reports zero — so a headless run of
## this would print a budget of nothing and look like a pass. It refuses instead
## (Appendix A.18). Run it windowed:
##
##   godot --path . --fixed-fps 60 --quit-after 420 -- --measure
func _run_measure() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("--measure needs a real renderer; the dummy driver reports zero draw calls")
		get_tree().quit(1)
		return
	print("== draw call measurement ==  budget 20 (technical design §5)")
	print("driver: %s" % DisplayServer.get_name())
	# The real round *and* the stress scene, because the number that matters is
	# the worst case and the game's own quiet frame is not it.
	for path in [MATCH, STRESS]:
		await _measure_scene(path)
	get_tree().quit(0)

func _measure_scene(path: String) -> void:
	var scene: Node = (load(path) as PackedScene).instantiate()
	add_child(scene)
	# Let it get going, so the numbers include bombs, flames and pickups rather
	# than an empty arena on its first frame.
	for _i in range(MEASURE_WARMUP):
		await get_tree().process_frame
	var worst_calls: int = 0
	var worst_objects: int = 0
	var worst_ms: float = 0.0
	for _i in range(MEASURE_FRAMES):
		await get_tree().process_frame
		worst_calls = maxi(worst_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		worst_objects = maxi(worst_objects, int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
		worst_ms = maxf(worst_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	print("%-40s draw calls %3d   objects %4d   worst frame %.2f ms" % [path, worst_calls, worst_objects, worst_ms])
	scene.queue_free()
	await get_tree().process_frame

const MEASURE_WARMUP: int = 120
const MEASURE_FRAMES: int = 240

## Instantiates every scene, steps it, and quits. This is the step M0's
## Appendix A.1 says is missing: `--import` registers class names but does not
## fully compile scene-attached scripts, so a type error in a scene script only
## surfaces when the scene is actually loaded.
##
## The exit code covers construction and stepping; CI additionally fails the job
## if `SCRIPT ERROR` appears on stderr, which is how a runtime error inside a
## _process or _draw gets caught.
func _run_smoke() -> void:
	print("== scene smoke ==")
	var failures: int = 0
	for path in SMOKE_SCENES:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			printerr("  FAIL  could not load %s" % path)
			failures += 1
			continue
		var instance: Node = packed.instantiate()
		if instance == null:
			printerr("  FAIL  could not instantiate %s" % path)
			failures += 1
			continue
		# A scene whose root script fails to parse still instantiates — you get
		# the node with nothing attached to it. M2 hit exactly that and the smoke
		# cheerfully reported OK, so the exit code was lying while the `SCRIPT
		# ERROR` grep in CI was the only thing failing the job. Every scene in
		# the list has a root script; a missing one means it did not compile.
		if instance.get_script() == null:
			printerr("  FAIL  %s instantiated with no root script (it did not compile)" % path)
			failures += 1
			instance.queue_free()
			continue
		add_child(instance)
		# Give the scene real frames: _ready has run, but _physics_process,
		# _process and _draw have not, and those are where M0's bugs lived.
		for _i in range(SMOKE_TICKS):
			await get_tree().physics_frame
		if instance.has_method("smoke_select_mode"):
			instance.call("smoke_select_mode", Session.MODE_HEN)
			await get_tree().process_frame
			await get_tree().process_frame
			instance.call("smoke_select_mode", Session.MODE_DEATHMATCH)
			await get_tree().process_frame
			await get_tree().process_frame
		if instance.has_method("smoke_step"):
			instance.call("smoke_step", SMOKE_TICKS)
		# The overlay's four modes each have a `_draw` and a pile of Labels that
		# no other smoke path reaches, and the scoreboard and the winner screen
		# build their text out of a live MatchState and MatchRecord — exactly the
		# shape of thing that fails on a null nobody thought about. Each one
		# needs a real frame on screen, because `_draw` runs on a frame and
		# nowhere else.
		for method in [
				"smoke_overlay_menu", "smoke_overlay_reconnect",
				"smoke_overlay_scoreboard", "smoke_overlay_match_result",
				"smoke_overlay_hen_scoreboard", "smoke_overlay_hide",
			]:
			if instance.has_method(method):
				instance.call(method)
				# Two process frames, not one: `queue_redraw()` inside the call
				# above is serviced at the *end* of the frame we are already
				# part-way through, so a single await can slip past the redraw
				# and the overlay is never actually drawn. Verified by capturing
				# the smoke run with `--write-movie`, where the pause menu was
				# missing from every frame until the second await.
				await get_tree().physics_frame
				await get_tree().process_frame
				await get_tree().process_frame
		# A scene may also self-check state it owns and hand back what went wrong.
		# The match scene's phase machine is the case that needs it: it depends on
		# the DeviceManager autoload, so it cannot be reached from a `--script`
		# test process at all (Appendix A.2), and this is the only place it runs.
		var problems: int = 0
		if instance.has_method("smoke_phases"):
			for problem in instance.call("smoke_phases"):
				printerr("  FAIL  %s: %s" % [path, problem])
				problems += 1
		failures += problems
		if instance.has_method("smoke_finish_round"):
			instance.call("smoke_finish_round")
		if problems == 0:
			print("  OK    %s" % path)
		instance.queue_free()
		await get_tree().process_frame
	print("== scene smoke: %d failure(s) ==" % failures)
	get_tree().quit(0 if failures == 0 else 1)
