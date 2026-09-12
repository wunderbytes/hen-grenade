extends Node2D
## The pause menu and the lost-controller notice, drawn over a frozen round.
## See docs/milestone-2-brief.md §6.
##
## Two modes sharing one panel, because they are the same thing to a player: the
## round has stopped and something wants an answer. The match scene owns which
## mode is showing and what the selection is; this file owns none of that and
## decides nothing — it draws what it is handed.
##
## Text is Labels rather than draw_string (technical-design.md Appendix A.6), and
## the panel is drawn in two passes — every fill, then every outline — because
## Godot's 2D renderer batches consecutive same-kind primitives (A.12).

const PANEL := Rect2(190, 108, 260, 144)
const BODY_LINES: int = 3
const LINE_H: int = 18

const DIM_COLOR := Color(0.02, 0.02, 0.04, 0.72)
const PANEL_COLOR := Color(0.09, 0.10, 0.13, 0.96)
const EDGE_COLOR := Color(0.55, 0.60, 0.62)
const SELECTED_COLOR := Color(1.0, 0.95, 0.6)
const DIM_TEXT_COLOR := Color(0.72, 0.76, 0.74)

var _title: Label = null
var _lines: Array[Label] = []
var _footer: Label = null

func _ready() -> void:
	visible = false
	_title = _make_label(PANEL.position + Vector2(16, 12), 10, Color(0.95, 0.95, 0.9))
	for i in range(BODY_LINES):
		_lines.append(_make_label(PANEL.position + Vector2(22, 44 + i * LINE_H), 8, DIM_TEXT_COLOR))
	_footer = _make_label(PANEL.position + Vector2(16, PANEL.size.y - 26), 8, Color(0.55, 0.62, 0.55))

# --- Modes -------------------------------------------------------------------

## `options` are the menu rows; `selected` is which one is highlighted.
func show_menu(options: Array[String], selected: int) -> void:
	_title.text = "PAUSED"
	for i in range(BODY_LINES):
		if i < options.size():
			var chosen: bool = i == selected
			_lines[i].text = ("> " if chosen else "  ") + options[i]
			_lines[i].add_theme_color_override("font_color", SELECTED_COLOR if chosen else DIM_TEXT_COLOR)
			_lines[i].visible = true
		else:
			_lines[i].visible = false
	_footer.text = "A / SPACE choose      ESC / B resume"
	visible = true
	queue_redraw()

## Named players, because "controller disconnected" is useless information to
## four people on a sofa — the only question is whose.
func show_reconnect(slot_indices: Array[int]) -> void:
	_title.text = "CONTROLLER LOST"
	for i in range(BODY_LINES):
		if i < slot_indices.size():
			var slot: int = slot_indices[i]
			_lines[i].text = "Player %d — plug it back in" % (slot + 1)
			_lines[i].add_theme_color_override("font_color", C.PLAYER_COLORS[slot])
			_lines[i].visible = true
		else:
			_lines[i].visible = false
	# Identical pads share a GUID and cannot be told apart, so the ambiguous case
	# needs a press. Saying so always is simpler than explaining it conditionally.
	_footer.text = "press A when it is back   ·   B to quit to lobby"
	visible = true
	queue_redraw()

func hide_overlay() -> void:
	visible = false

# --- Drawing -----------------------------------------------------------------

func _draw() -> void:
	# Fills first, then edges: two passes, not per-shape interleaving.
	draw_rect(Rect2(0, 0, C.VIEW_W, C.VIEW_H), DIM_COLOR, true)
	draw_rect(PANEL, PANEL_COLOR, true)
	draw_rect(PANEL, EDGE_COLOR, false, 1.0)

func _make_label(pos: Vector2, size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.position = pos
	label.vertical_alignment = 0    # integer, not the enum (Appendix A.7)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label
