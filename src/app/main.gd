extends Node2D
## Bootstrap / scene router. The project's main scene; routes to the dev scenes.
## M0 has no real menu — press a key to enter the sandbox, F2 for stress.
## See docs/milestone-0-brief.md §5.

const SANDBOX: String = "res://src/dev/sandbox.tscn"
const STRESS: String = "res://src/dev/stress.tscn"

func _ready() -> void:
	_add_label("HEN GRENADE", Vector2(C.VIEW_W / 2.0 - 70, C.VIEW_H / 2.0 - 16), 16, Color(0.95, 0.95, 0.9))
	_add_label("M0 — hardware spike", Vector2(C.VIEW_W / 2.0 - 96, C.VIEW_H / 2.0 + 4), 8, Color(0.7, 0.8, 0.7))
	_add_label("press SPACE/F1 sandbox  F2 stress", Vector2(C.VIEW_W / 2.0 - 110, C.VIEW_H / 2.0 + 18), 8, Color(0.6, 0.7, 0.6))
	# Auto-advance to the sandbox after a brief title beat.
	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(self) and get_tree().current_scene == self:
		get_tree().change_scene_to_file(SANDBOX)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE, KEY_ENTER, KEY_F1:
				get_tree().change_scene_to_file(SANDBOX)
			KEY_F2:
				get_tree().change_scene_to_file(STRESS)

func _add_label(text: String, pos: Vector2, size: int, color: Color) -> void:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	add_child(lbl)
