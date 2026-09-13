class_name PowerupLegend
extends Node2D
## Colour-and-size key for pickups, matching the board art in PickupArt.
##
## Compact mode (in-game HUD) is one justified row spanning `span_w`, and it is
## still a single Label plus two batched rect passes — one extra text draw, not
## eight. The spacing is done by padding that one string with spaces, because
## eight positioned Labels would be eight draw calls against a budget of twenty
## (Appendix A.11).
##
## Roomy mode (lobby) has the room for a heading and a Label per name.

var compact: bool = true
## Width the row is spread across. Only compact mode uses it.
var span_w: float = float(C.VIEW_W)

const FONT_SIZE: int = 8
## Between an icon and the name it belongs to.
const ICON_GAP: float = 3.0
## Padding spaces one entry may spend before giving up.
const MAX_PAD: int = 200
## Never let two entries touch, however narrow the span gets.
const MIN_GAP: float = 6.0

var _names: Label = null
## Compact icon centres, resolved from the padded string so every icon sits
## against its own name rather than at a nominal grid position.
var _compact_icons: PackedFloat32Array = PackedFloat32Array()

func _ready() -> void:
	if compact:
		_names = _make_label(Vector2.ZERO, Color(0.82, 0.86, 0.82))
		_names.text = _build_compact_row()
	else:
		var heading: Label = _make_label(Vector2(0, 0), Color(0.70, 0.80, 0.70))
		heading.text = "power-ups — colour and inner size"
		for i in range(PickupArt.KINDS.size()):
			var name: Label = _make_label(_roomy_name_pos(i), Color(0.86, 0.88, 0.86))
			name.text = Powerup.short_name(PickupArt.KINDS[i])
	queue_redraw()

func _draw() -> void:
	# Shells, then cores, so Godot batches each pass (same as EntityView).
	var centres: Array[Vector2] = []
	for i in range(PickupArt.KINDS.size()):
		centres.append(_icon_centre(i))
	for c in centres:
		draw_rect(Rect2(c.x - PickupArt.HALF, c.y - PickupArt.HALF, PickupArt.HALF * 2.0, PickupArt.HALF * 2.0), PickupArt.SHELL, true)
	for i in range(centres.size()):
		var c: Vector2 = centres[i]
		var kind: int = PickupArt.KINDS[i]
		var inner: float = PickupArt.INNER[kind]
		draw_rect(Rect2(c.x - inner, c.y - inner, inner * 2.0, inner * 2.0), PickupArt.COLORS[kind], true)

## Builds the single compact string and records where each icon lands.
##
## The row is **justified**, not columned: the slack left over after the eight
## icon-and-name pairs is split equally between them, so the first is flush left,
## the last is flush right, and every gap is the same. Equal-width columns look
## wrong here because the names are not equal-width — DUD would leave a hole at
## the end of the row that JACKPOT does not.
func _build_compact_row() -> String:
	var count: int = PickupArt.KINDS.size()
	var gap: float = _even_gap(count)
	var text: String = _layout_row(gap)
	# One correction pass. Space padding quantises every entry's start, so the
	# row ends a dozen pixels short of `span_w`; feeding that error back through
	# the gap puts the last entry on the right edge instead of well inside it.
	# The target is one space short of the span, because the same quantisation
	# that made the first pass fall short can make the corrected one overshoot,
	# and overshooting runs the last name off the screen. A further pass would
	# buy nothing: the residue is one space wide.
	var drift: float = _measure(text) - (span_w - _measure(" "))
	if absf(drift) > 1.0:
		text = _layout_row(maxf(MIN_GAP, gap - drift / float(maxi(1, count - 1))))
	return text

func _layout_row(gap: float) -> String:
	var text: String = ""
	var x: float = 0.0
	_compact_icons.clear()
	for i in range(PickupArt.KINDS.size()):
		# Space padding quantises a start to whole spaces, so a name can sit a
		# pixel or two right of where it was asked for. The icon is then placed
		# from the measured text rather than the intended x, which keeps each
		# pair tight — the mismatch a reader would actually notice.
		var name_x: float = x + PickupArt.HALF * 2.0 + ICON_GAP
		# Bounded: a font that measured a space as zero would otherwise hang the
		# HUD, and a wrong-looking legend beats a frozen game.
		var pad: int = 0
		while _measure(text) < name_x and pad < MAX_PAD:
			text += " "
			pad += 1
		_compact_icons.append(_measure(text) - ICON_GAP - PickupArt.HALF)
		text += Powerup.short_name(PickupArt.KINDS[i])
		x = _measure(text) + gap
	return text

## Slack per gap: what is left of the span once the eight pairs have had their
## pixels, divided between the seven gaps.
func _even_gap(count: int) -> float:
	var content: float = 0.0
	for kind in PickupArt.KINDS:
		content += PickupArt.HALF * 2.0 + ICON_GAP + _measure(Powerup.short_name(kind))
	return maxf(MIN_GAP, (span_w - content) / float(maxi(1, count - 1)))

func _icon_centre(i: int) -> Vector2:
	if compact:
		if i >= _compact_icons.size():
			return Vector2.ZERO
		# Centred on the text line, which is one font size tall.
		return Vector2(_compact_icons[i], PickupArt.HALF)
	return _roomy_icon_pos(i) + Vector2(PickupArt.HALF, PickupArt.HALF)

func _measure(text: String) -> float:
	if _names == null:
		return float(text.length() * 5)
	var font: Font = _names.get_theme_font("font")
	if font == null:
		return float(text.length() * 5)
	return font.get_string_size(text, 0, -1, FONT_SIZE).x

func _roomy_icon_pos(i: int) -> Vector2:
	var col: int = i % 4
	var row: int = i / 4
	return Vector2(col * 148.0, 18.0 + row * 22.0)

func _roomy_name_pos(i: int) -> Vector2:
	return _roomy_icon_pos(i) + Vector2(PickupArt.HALF * 2.0 + 4.0, -2.0)

func _make_label(pos: Vector2, color: Color) -> Label:
	var label: Label = Label.new()
	label.position = pos
	label.vertical_alignment = 0
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label
