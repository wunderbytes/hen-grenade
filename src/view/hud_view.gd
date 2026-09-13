extends Node2D
## The side panels and the round clock.
## See docs/milestone-1-brief.md §9, docs/milestone-3-brief.md §6.3, and
## docs/game-design.md §8.
##
## The 640 x 360 viewport is 500 px of arena plus a 70 px margin down each side
## and a 30 px band top and bottom — the margins are where the HUD lives, which
## is the whole reason the arena is 25 x 15 (game design §4).
##
## Everything is a Label rather than draw_string: per technical-design.md
## Appendix A.6, Node2D has no theme-font accessor in 4.7 and Label is the
## version-robust way to put text on screen.
##
## **One Label per card, however much is written on it.** M3 roughly doubled what
## a card carries — the design asks for score, bombs, blast, speed, abilities and
## the respawn countdown, and best-of-3 adds a round tally — and all of it goes
## into the one multi-line Label a card already had. A Label costs the same
## whether it holds two lines or nine; a *second* Label would cost another draw
## call, and Appendix A.11 is clear about what that is worth.
##
## The round-end banner is gone from here: M3's scoreboard and winner screen are
## modes of `round_overlay.gd`, which is the file that owns stopped rounds.

const FONT_SIZE: int = 8
const CLOCK_FONT_SIZE: int = 14
## Slots 0 and 2 live in the left margin, 1 and 3 in the right.
const LEFT_SLOTS: Array[int] = [0, 2]
const RIGHT_SLOTS: Array[int] = [1, 3]
## The clock turns red and the design asks for an audible tick under this.
const URGENT_SECONDS: int = 10

var _cards: Array[Label] = []
var _clock: Label = null
var _hint: Label = null

func _ready() -> void:
	_cards.resize(C.MAX_PLAYERS)
	# Player cards and the hint sit on the flat HUD margin, never over the
	# arena, so they do not need a drop shadow — and a shadow is not free: it is
	# a second text pass per Label, which on a seven-Label HUD was most of a
	# 32-draw-call bill against a 20-call budget (technical design §5).
	for i in range(LEFT_SLOTS.size()):
		var slot: int = LEFT_SLOTS[i]
		_cards[slot] = _make_label(Vector2(3, 34 + i * 150), FONT_SIZE, C.PLAYER_COLORS[slot], false)
	for i in range(RIGHT_SLOTS.size()):
		var slot: int = RIGHT_SLOTS[i]
		_cards[slot] = _make_label(Vector2(C.VIEW_W - C.HUD_PANEL_W + 3, 34 + i * 150), FONT_SIZE, C.PLAYER_COLORS[slot], false)

	# The clock does sit over busy pixels, so it keeps its shadow.
	_clock = _make_label(Vector2(C.VIEW_W / 2.0 - 22, 6), CLOCK_FONT_SIZE, Color(0.95, 0.95, 0.9), true)
	_hint = _make_label(Vector2(4, C.VIEW_H - 12), FONT_SIZE, Color(0.55, 0.62, 0.55), false)
	_hint.text = "ESC pause  F1 title  F3 sandbox  F5 metrics"

## `record` may be null — the dev scenes and an early frame have a round without
## a match around it — in which case the tally line is simply left off.
func sync(state: MatchState, record: MatchRecord = null) -> void:
	_clock.text = _format_clock(state.seconds_left())
	var urgent: bool = state.seconds_left() <= URGENT_SECONDS
	_clock.add_theme_color_override("font_color", Color(1, 0.35, 0.3) if urgent else Color(0.95, 0.95, 0.9))

	for slot in range(C.MAX_PLAYERS):
		_cards[slot].text = _card_text(state, slot, record)

## What a player now actually has, in the order they need it: who they are, how
## they are doing, what they are carrying, and what is about to happen to them.
func _card_text(state: MatchState, slot: int, record: MatchRecord) -> String:
	var p: PlayerState = state.players[slot]
	var header: String = "P%d" % (slot + 1)
	if record != null:
		header += " " + record.pips(slot)
	if not p.active:
		return "%s\n—" % header

	var lines: PackedStringArray = PackedStringArray()
	lines.append(header)
	lines.append("%d pts" % p.score)
	lines.append("%dk / %dd" % [p.kills, p.deaths])
	lines.append("bomb %d" % p.bomb_capacity)
	lines.append("blast %d" % p.blast_radius)
	if p.speed_steps > 0:
		lines.append("speed +%d" % p.speed_steps)

	# Abilities, only when there is one to show. An empty slot is worth nothing
	# on a 70 px panel and a line of dashes reads as a bug.
	var kit: PackedStringArray = PackedStringArray()
	if p.has_kick:
		kit.append(Powerup.short_name(Powerup.Kind.KICK))
	if Powerup.is_ability(p.ability):
		kit.append(Powerup.short_name(p.ability))
	if not kit.is_empty():
		lines.append(" ".join(kit))

	# A curse and how long is left of it: the player needs to know when their
	# controls come back, not merely that something is wrong.
	if p.has_curse():
		lines.append("%s %d" % [Powerup.curse_name(p.curse), (p.curse_ticks + C.TICK_HZ - 1) / C.TICK_HZ])

	if not p.alive:
		# Ceiling, so the last visible number is 1 rather than 0.
		lines.append("back in %d" % ((p.respawn_ticks + C.TICK_HZ - 1) / C.TICK_HZ + 1))
	elif p.spawn_protect_ticks > 0:
		lines.append("SAFE")
	return "\n".join(lines)

func _format_clock(seconds: int) -> String:
	return "%d:%02d" % [seconds / 60, seconds % 60]

func _make_label(pos: Vector2, size: int, color: Color, shadow: bool) -> Label:
	var label: Label = Label.new()
	label.position = pos
	# Integer, not the named enum: Control.VALIGN_TOP is Godot 3 and
	# VERTICAL_ALIGNMENT_TOP does not exist in 4.7 either (Appendix A.7).
	label.vertical_alignment = 0
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if shadow:
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)
	return label
