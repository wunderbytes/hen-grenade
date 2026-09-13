extends Node2D
## The panel the match scene puts over a stopped round, in four modes: the pause
## menu, the lost-controller notice, the between-rounds scoreboard, and the
## winner screen. See docs/milestone-3-brief.md §6.3 and docs/milestone-2-brief.md §6.
##
## M2 shipped this as `pause_overlay.gd` with two modes and a fixed three-line
## body, and its completion notes nominated it for exactly this generalisation.
## One panel, sized to its content, because to a player all four modes are the
## same thing: the round has stopped and something wants an answer.
##
## It owns none of the decisions. The match scene says which mode is showing and
## what is selected; this file draws what it is handed and decides nothing.
##
## Text is Labels rather than draw_string (technical-design.md Appendix A.6), and
## the panel is drawn in two passes — every fill, then every outline — because
## Godot's 2D renderer batches consecutive same-kind primitives (A.12).

## Enough for a title, four player rows, a blank and a tally on the scoreboard.
const MAX_LINES: int = 8
const LINE_H: int = 13

const PANEL_W: int = 300
const PANEL_TOP_PAD: int = 34
const PANEL_BOTTOM_PAD: int = 30
const MIN_PANEL_H: int = 96

const DIM_COLOR := Color(0.02, 0.02, 0.04, 0.72)
const PANEL_COLOR := Color(0.09, 0.10, 0.13, 0.96)
const EDGE_COLOR := Color(0.55, 0.60, 0.62)
const SELECTED_COLOR := Color(1.0, 0.95, 0.6)
const DIM_TEXT_COLOR := Color(0.72, 0.76, 0.74)
const FOOTER_COLOR := Color(0.55, 0.62, 0.55)

var _panel := Rect2(170, 108, PANEL_W, MIN_PANEL_H)
var _title: Label = null
var _lines: Array[Label] = []
var _footer: Label = null

func _ready() -> void:
	visible = false
	_title = _make_label(10, Color(0.95, 0.95, 0.9))
	for _i in range(MAX_LINES):
		_lines.append(_make_label(8, DIM_TEXT_COLOR))
	_footer = _make_label(8, FOOTER_COLOR)
	_layout(0)

# --- Modes -------------------------------------------------------------------

## `options` are the menu rows; `selected` is which one is highlighted.
func show_menu(options: Array[String], selected: int) -> void:
	var lines: PackedStringArray = PackedStringArray()
	var colors: Array[Color] = []
	for i in range(options.size()):
		var chosen: bool = i == selected
		lines.append(("> " if chosen else "  ") + options[i])
		colors.append(SELECTED_COLOR if chosen else DIM_TEXT_COLOR)
	_show("PAUSED", lines, colors, "A / SPACE choose      ESC / B resume")

## Named players, because "controller disconnected" is useless information to
## four people on a sofa — the only question is whose.
func show_reconnect(slot_indices: Array[int]) -> void:
	var lines: PackedStringArray = PackedStringArray()
	var colors: Array[Color] = []
	for slot in slot_indices:
		lines.append("Player %d — plug it back in" % (slot + 1))
		colors.append(C.PLAYER_COLORS[slot])
	# Identical pads share a GUID and cannot be told apart, so the ambiguous case
	# needs a press. Saying so always is simpler than explaining it conditionally.
	_show("CONTROLLER LOST", lines, colors, "press A when it is back   ·   B to quit to lobby")

## Between rounds: who did what this round, and where the match stands.
##
## The seed is on here because game design §4 promises it — "a good layout can be
## replayed" — and this is the only screen with room to say it.
func show_scoreboard(state: MatchState, record: MatchRecord, seconds_left: int) -> void:
	if state.mode != null and state.mode.is_hen():
		_show_hen_scoreboard(state, record, seconds_left)
		return
	var title: String = "ROUND %d — " % record.rounds_played()
	var round_winner: int = record.round_winners[record.rounds_played() - 1] if record.rounds_played() > 0 else -1
	title += "DRAW" if round_winner < 0 else "PLAYER %d" % (round_winner + 1)

	var lines: PackedStringArray = PackedStringArray()
	var colors: Array[Color] = []
	for p in state.players:
		if not p.active:
			continue
		lines.append("P%d  %-3d pts   %dk / %dd   match %s" % [
			p.index + 1, p.score, p.kills, p.deaths, record.pips(p.index)
		])
		colors.append(C.PLAYER_COLORS[p.index])
	lines.append("")
	colors.append(DIM_TEXT_COLOR)
	lines.append("seed %d" % state.rng_seed)
	colors.append(DIM_TEXT_COLOR)
	_show(title, lines, colors, "next round in %d …   A to skip" % maxi(0, seconds_left))

func _show_hen_scoreboard(state: MatchState, record: MatchRecord, seconds_left: int) -> void:
	var title: String = "%s  seed %d" % [state.mode.display_name, state.rng_seed]
	var lines: PackedStringArray = PackedStringArray()
	var colors: Array[Color] = []
	for p in state.players:
		if not p.active:
			continue
		lines.append("P%d   %ds   %dk / %dd" % [
			p.index + 1, p.hen_ticks / C.TICK_HZ, p.kills, p.deaths
		])
		colors.append(C.PLAYER_COLORS[p.index])
	_show(title, lines, colors, "A to skip   ·   %ds" % maxi(0, seconds_left))

## The winner screen. `record.winner()` is -1 for a match nobody could win, which
## after seven rounds is an honest outcome rather than an error.
func show_match_result(record: MatchRecord, state: MatchState = null) -> void:
	var winner: int = record.winner()
	var lines: PackedStringArray = PackedStringArray()
	var colors: Array[Color] = []
	var hen: bool = state != null and state.mode != null and state.mode.is_hen()
	for slot in range(C.MAX_PLAYERS):
		if record.active[slot] == 0:
			continue
		if hen:
			var ticks: int = record.total_score[slot]
			lines.append("P%d   %ds" % [slot + 1, ticks / C.TICK_HZ])
		else:
			lines.append("P%d   %d round win(s)   %d pts" % [slot + 1, record.wins_of(slot), record.total_score[slot]])
		colors.append(C.PLAYER_COLORS[slot])
	var title: String = "MATCH DRAWN" if winner < 0 else "PLAYER %d WINS THE MATCH" % (winner + 1)
	_show(title, lines, colors, "A rematch   ·   B quit to lobby")

func hide_overlay() -> void:
	visible = false

# --- Layout and drawing ------------------------------------------------------

func _show(title: String, lines: PackedStringArray, colors: Array[Color], footer: String) -> void:
	_title.text = title
	var shown: int = mini(lines.size(), MAX_LINES)
	for i in range(MAX_LINES):
		if i < shown:
			_lines[i].text = lines[i]
			_lines[i].add_theme_color_override("font_color", colors[i] if i < colors.size() else DIM_TEXT_COLOR)
			_lines[i].visible = true
		else:
			_lines[i].visible = false
	_footer.text = footer
	_layout(shown)
	visible = true
	queue_redraw()

## Sizes the panel to the number of rows and re-places the Labels. The panel is
## centred on the viewport rather than at a fixed origin, so a two-line notice
## and a six-line scoreboard both sit in the middle of the screen.
func _layout(line_count: int) -> void:
	var h: int = maxi(MIN_PANEL_H, PANEL_TOP_PAD + line_count * LINE_H + PANEL_BOTTOM_PAD)
	_panel = Rect2(
		(C.VIEW_W - PANEL_W) / 2.0, (C.VIEW_H - h) / 2.0,
		PANEL_W, h
	)
	_title.position = _panel.position + Vector2(14, 10)
	for i in range(_lines.size()):
		_lines[i].position = _panel.position + Vector2(20, PANEL_TOP_PAD + i * LINE_H)
	_footer.position = _panel.position + Vector2(14, h - 22)

func _draw() -> void:
	# Fills first, then edges: two passes, not per-shape interleaving.
	draw_rect(Rect2(0, 0, C.VIEW_W, C.VIEW_H), DIM_COLOR, true)
	draw_rect(_panel, PANEL_COLOR, true)
	draw_rect(_panel, EDGE_COLOR, false, 1.0)

# --- Smoke support -----------------------------------------------------------

## Reports any text that has been laid out off the panel, and a panel laid out
## off the screen. Called by the match scene's smoke check once per mode.
##
## This exists because the alternative is looking at it, and looking at it is not
## available: `--headless --write-movie` segfaults in 4.7.2 (Appendix A.17), so
## the screenshot trick M2 used to catch an overlay that never drew cannot be
## used on an overlay that draws in the wrong place. A panel that grows with its
## content is exactly the thing that silently runs off a 640 x 360 screen, and a
## scoreboard row is the longest string in the game.
func geometry_problems(mode: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var view: Rect2 = Rect2(0, 0, C.VIEW_W, C.VIEW_H)
	if not view.encloses(_panel):
		out.append("%s: the panel is off the screen (%s)" % [mode, str(_panel)])
	# 5 px of slack on each side: the panel outline is 1 px and text sitting on it
	# is a layout bug even though it is technically inside.
	var inner: Rect2 = _panel.grow(-5.0)
	for probe in _probes():
		var label: Label = probe as Label
		var box: Rect2 = Rect2(label.position, label.get_minimum_size())
		if not inner.encloses(box):
			out.append("%s: \"%s\" does not fit the panel (%s vs %s)" % [
				mode, label.text, str(box), str(inner)
			])
	return out

## The Labels currently showing something.
func _probes() -> Array[Node]:
	var out: Array[Node] = [_title, _footer]
	for label in _lines:
		if label.visible and label.text != "":
			out.append(label)
	return out

func _make_label(size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.vertical_alignment = 0    # integer, not the enum (Appendix A.7)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label
