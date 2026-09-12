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

const MATCH: String = "res://src/app/match_scene.tscn"
const SANDBOX: String = "res://src/dev/sandbox.tscn"
const STRESS: String = "res://src/dev/stress.tscn"

## How long the title card sits before the game starts itself.
const TITLE_SECONDS: float = 1.2

func _ready() -> void:
	if _smoke_requested():
		_run_smoke()
		return
	_add_label("HEN GRENADE", Vector2(C.VIEW_W / 2.0 - 70, C.VIEW_H / 2.0 - 24), 16, Color(0.95, 0.95, 0.9))
	_add_label("M1 — core simulation", Vector2(C.VIEW_W / 2.0 - 96, C.VIEW_H / 2.0 - 4), 8, Color(0.7, 0.8, 0.7))
	_add_label("P1: WASD + Space    P2: arrows + Right Ctrl", Vector2(C.VIEW_W / 2.0 - 128, C.VIEW_H / 2.0 + 12), 8, Color(0.7, 0.75, 0.7))
	_add_label("SPACE play   F2 stress   F3 sandbox", Vector2(C.VIEW_W / 2.0 - 110, C.VIEW_H / 2.0 + 30), 8, Color(0.6, 0.7, 0.6))
	await get_tree().create_timer(TITLE_SECONDS).timeout
	if is_instance_valid(self) and get_tree().current_scene == self:
		get_tree().change_scene_to_file(MATCH)

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE, KEY_ENTER, KEY_F4:
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

## Scenes visited by the smoke check, in order.
const SMOKE_SCENES: Array[String] = [MATCH, SANDBOX, STRESS]
const SMOKE_TICKS: int = 40

func _smoke_requested() -> bool:
	return OS.get_cmdline_user_args().has("--smoke")

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
		add_child(instance)
		# Give the scene real frames: _ready has run, but _physics_process,
		# _process and _draw have not, and those are where M0's bugs lived.
		for _i in range(SMOKE_TICKS):
			await get_tree().physics_frame
		if instance.has_method("smoke_step"):
			instance.call("smoke_step", SMOKE_TICKS)
		if instance.has_method("smoke_finish_round"):
			instance.call("smoke_finish_round")
		print("  OK    %s" % path)
		instance.queue_free()
		await get_tree().process_frame
	print("== scene smoke: %d failure(s) ==" % failures)
	get_tree().quit(0 if failures == 0 else 1)
