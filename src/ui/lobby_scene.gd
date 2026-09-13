extends Node2D
## The lobby: four seats, join with the device in your hand, start.
## See docs/milestone-2-brief.md §5.
##
## There is no cursor here, and that is the design rather than a shortcut: a
## player's *device* is their cursor, which is the whole reason press-A-to-join
## exists. Nobody navigates to a slot, nobody is "player 1" because they got to
## the keyboard first — you press A and the seat you got is yours.
##
## This scene is the root screen of the game, not a sub-page of the title card
## (the title auto-advances here after a beat), so it has no "back". Leaving is
## quitting, and the only navigation out of it is starting a round.

const MATCH_SCENE: String = "res://src/app/match_scene.tscn"
const TITLE_SCENE: String = "res://src/app/main.tscn"
const STRESS_SCENE: String = "res://src/dev/stress.tscn"
const SANDBOX_SCENE: String = "res://src/dev/sandbox.tscn"

const CARD_W: int = 140
const CARD_H: int = 110
const CARD_GAP: int = 12
const CARD_Y: int = 80
## Centres the row of four: 4 * 140 + 3 * 12 = 596 in a 640-wide viewport.
const CARD_X0: int = (C.VIEW_W - (C.MAX_PLAYERS * CARD_W + (C.MAX_PLAYERS - 1) * CARD_GAP)) / 2

const CHIP_W: int = 132
const CHIP_H: int = 18
const CHIP_GAP: int = 12
const CHIP_Y: int = 38
const CHIP_X0: int = (C.VIEW_W - (2 * CHIP_W + CHIP_GAP)) / 2
const CHIP_ON := Color(0.95, 0.95, 0.9)
const CHIP_OFF := Color(0.38, 0.42, 0.38)
const CHIP_FILL := Color(0.18, 0.19, 0.16, 0.85)
const EMPTY_FILL := Color(0.07, 0.08, 0.10)
const EMPTY_EDGE := Color(0.28, 0.30, 0.32)
const CARD_FILL_ALPHA: float = 0.22

var _cards_header: Array[Label] = []
var _cards_body: Array[Label] = []
var _chip_labels: Array[Label] = []
var _status: Label = null
var _metrics: Node = null

func _ready() -> void:
	# Joining, leaving, and releasing any seat still reserved from a match that
	# was quit while paused.
	DeviceManager.enter_lobby()
	DeviceManager.roster_changed.connect(_on_roster_changed)

	var title: Label = _add_label(Vector2(C.VIEW_W / 2.0 - 70, 10), 16, Color(0.95, 0.95, 0.9), true)
	title.text = "HEN GRENADE"

	_chip_labels.append(_add_label(Vector2(CHIP_X0 + 18, CHIP_Y + 4), 8, CHIP_ON, false))
	_chip_labels.append(_add_label(Vector2(CHIP_X0 + CHIP_W + CHIP_GAP + 14, CHIP_Y + 4), 8, CHIP_OFF, false))
	_chip_labels[0].text = "DEATHMATCH"
	_chip_labels[1].text = "HEN GRENADE"

	for i in range(C.MAX_PLAYERS):
		var origin: Vector2 = _card_rect(i).position
		_cards_header.append(_add_label(origin + Vector2(8, 6), 10, C.PLAYER_COLORS[i], false))
		_cards_body.append(_add_label(origin + Vector2(8, 34), 8, Color(0.86, 0.88, 0.86), false))

	_status = _add_label(Vector2(C.VIEW_W / 2.0 - 80, 196), 10, Color(0.95, 0.95, 0.9), false)

	var pad_help: Label = _add_label(Vector2(24, 222), 8, Color(0.62, 0.70, 0.62), false)
	pad_help.text = "A join    B leave    Y add bot    X drop bot    LB/RB mode    START begin"
	var kb_help: Label = _add_label(Vector2(24, 236), 8, Color(0.52, 0.58, 0.52), false)
	kb_help.text = "keyboard: SPACE / RIGHT CTRL join, Q / slash leave, B / N bots, [ ] mode, ENTER begin"

	var legend: PowerupLegend = PowerupLegend.new()
	legend.compact = false
	legend.position = Vector2(24, 258)
	add_child(legend)

	var dev_help: Label = _add_label(Vector2(24, C.VIEW_H - 14), 8, Color(0.40, 0.46, 0.40), false)
	dev_help.text = "F1 title   F2 stress   F3 sandbox   F5 metrics"

	_metrics = load("res://src/app/metrics_overlay.tscn").instantiate()
	_metrics.visible = false
	add_child(_metrics)

	_refresh()

func _physics_process(_delta: float) -> void:
	# DeviceManager is an autoload, so its _physics_process has already computed
	# this frame's button edges by the time we get here.
	if DeviceManager.menu_pressed(DeviceManager.Menu.ADD_BOT):
		DeviceManager.add_bot()
	if DeviceManager.menu_pressed(DeviceManager.Menu.REMOVE_BOT):
		DeviceManager.remove_last_bot()
	if DeviceManager.menu_pressed(DeviceManager.Menu.PREV_MODE):
		Session.cycle(-1)
		_refresh()
	if DeviceManager.menu_pressed(DeviceManager.Menu.NEXT_MODE):
		Session.cycle(1)
		_refresh()
	# START only: the lobby deliberately never reads CONFIRM, because Space is the
	# WASD seat's join key and a third player sitting down must not also start
	# the match out from under the two already seated.
	if DeviceManager.menu_pressed(DeviceManager.Menu.START) and DeviceManager.can_start():
		get_tree().change_scene_to_file(MATCH_SCENE)

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_F1:
			get_tree().change_scene_to_file(TITLE_SCENE)
		KEY_F2:
			get_tree().change_scene_to_file(STRESS_SCENE)
		KEY_F3:
			get_tree().change_scene_to_file(SANDBOX_SCENE)
		KEY_F5:
			if _metrics != null:
				_metrics.visible = not _metrics.visible

# --- Roster display ----------------------------------------------------------

func _on_roster_changed() -> void:
	_refresh()

func _refresh() -> void:
	for i in range(C.MAX_PLAYERS):
		var slot: PlayerSlot = DeviceManager.slots[i]
		_cards_header[i].text = "P%d" % (i + 1)
		_cards_body[i].text = "\n".join(slot.card_lines())
		_cards_body[i].add_theme_color_override(
			"font_color",
			Color(0.88, 0.90, 0.88) if slot.is_occupied() else Color(0.45, 0.50, 0.45)
		)
	var n: int = DeviceManager.occupied_count()
	if DeviceManager.can_start():
		_status.text = "     START to begin  (%d players)" % n
		_status.add_theme_color_override("font_color", Color(0.75, 0.95, 0.75))
	else:
		_status.text = "   %d of %d minimum players" % [n, C.MIN_PLAYERS]
		_status.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	_refresh_chips()
	queue_redraw()

func _refresh_chips() -> void:
	var hen: bool = Session.is_hen()
	_chip_labels[0].add_theme_color_override("font_color", CHIP_OFF if hen else CHIP_ON)
	_chip_labels[1].add_theme_color_override("font_color", CHIP_ON if hen else CHIP_OFF)

func smoke_select_mode(id: String) -> void:
	Session.mode_id = id
	_refresh()

# --- Drawing -----------------------------------------------------------------

## Fills in one pass, then edges in another. Interleaving them per card would
## break the renderer's batching for the sake of nothing (Appendix A.12).
func _draw() -> void:
	var hen: bool = Session.is_hen()
	draw_rect(_chip_rect(0), CHIP_FILL if not hen else Color(CHIP_FILL, 0.35), true)
	draw_rect(_chip_rect(1), CHIP_FILL if hen else Color(CHIP_FILL, 0.35), true)
	draw_rect(_chip_rect(0), CHIP_ON if not hen else CHIP_OFF, false, 1.0)
	draw_rect(_chip_rect(1), CHIP_ON if hen else CHIP_OFF, false, 1.0)
	for i in range(C.MAX_PLAYERS):
		var slot: PlayerSlot = DeviceManager.slots[i]
		var fill: Color = EMPTY_FILL
		if slot.is_occupied():
			fill = C.PLAYER_COLORS[i]
			fill.a = CARD_FILL_ALPHA
		draw_rect(_card_rect(i), fill, true)
	for i in range(C.MAX_PLAYERS):
		var occupied: bool = DeviceManager.slots[i].is_occupied()
		draw_rect(_card_rect(i), C.PLAYER_COLORS[i] if occupied else EMPTY_EDGE, false, 1.0)

func _chip_rect(i: int) -> Rect2:
	return Rect2(CHIP_X0 + i * (CHIP_W + CHIP_GAP), CHIP_Y, CHIP_W, CHIP_H)

func _card_rect(i: int) -> Rect2:
	return Rect2(CARD_X0 + i * (CARD_W + CARD_GAP), CARD_Y, CARD_W, CARD_H)

func _add_label(pos: Vector2, size: int, color: Color, shadow: bool) -> Label:
	var label: Label = Label.new()
	label.position = pos
	label.vertical_alignment = 0    # integer, not the enum (Appendix A.7)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	# A shadow is a second text pass and therefore a second draw call
	# (Appendix A.11). Only the title, which sits over nothing, earns one.
	if shadow:
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)
	return label
