class_name CharacterArt
## Programmer-art hunter layers: hat, clothes, shoes. Lobby preview and
## EntityView share this painter so a retune here cannot leave the card
## describing a different figure. See docs/milestone-3.6-brief.md.
##
## Body fill is always C.PLAYER_COLORS[slot]. Overlays are shades of that hue
## plus a black outline and a cream accent — never a second player colour.

enum Layer { HEAD = 0, CLOTHES = 1, SHOES = 2 }

const LAYER_COUNT: int = PlayerSlot.LOOK_LAYERS
const BODY_HALF: float = 7.0
const ACCENT := Color8(245, 242, 230)
## Darker than clothing (0.62) so boots still read on overalls.
const SHOE_MUL: float = 0.38

const HEAD_NAMES: PackedStringArray = ["NONE", "CAP", "CONE", "BALL", "EARS", "MOHAWK", "PROP", "BOW", "ANTENNA"]
const CLOTHES_NAMES: PackedStringArray = ["TUNIC", "VEST", "OVERALLS", "SASH", "SKIRT", "PLEATS", "TUTU"]
const SHOES_NAMES: PackedStringArray = ["NONE", "BOOTS", "SNEAKERS", "PACK"]

static func wrap_index(value: int, count: int) -> int:
	return PlayerSlot.wrap_look(value, count)

static func option_count(layer: int) -> int:
	return PlayerSlot.look_count(wrap_index(layer, LAYER_COUNT))

static func option_name(layer: int, option: int) -> String:
	var i: int = wrap_index(option, option_count(layer))
	match wrap_index(layer, LAYER_COUNT):
		Layer.HEAD:
			return HEAD_NAMES[i]
		Layer.CLOTHES:
			return CLOTHES_NAMES[i]
		Layer.SHOES:
			return SHOES_NAMES[i]
	return "?"

## Darken or lighten without leaving the slot's hue. mul < 1 is darker.
static func shade(base: Color, mul: float) -> Color:
	return Color(
		clampf(base.r * mul, 0.0, 1.0),
		clampf(base.g * mul, 0.0, 1.0),
		clampf(base.b * mul, 0.0, 1.0),
		base.a
	)

static func body_color(slot: int) -> Color:
	if slot < 0 or slot >= C.PLAYER_COLORS.size():
		return Color.WHITE
	return C.PLAYER_COLORS[slot]

static func draw_hunter(
		item: CanvasItem,
		centre: Vector2,
		slot: int,
		hat: int,
		clothes: int,
		shoes: int,
		scale: float = 1.0,
		highlight_layer: int = -1,
		facing: int = InputFrame.Dir.DOWN
	) -> void:
	var centres := PackedVector2Array([centre])
	var slots := PackedInt32Array([slot])
	var hats := PackedInt32Array([hat])
	var clothes_ids := PackedInt32Array([clothes])
	var shoes_ids := PackedInt32Array([shoes])
	var layers := PackedInt32Array([highlight_layer])
	var facings := PackedInt32Array([facing])
	draw_hunters(item, centres, slots, hats, clothes_ids, shoes_ids, scale, layers, facings)

## Batched by primitive kind (technical design A.12): bodies, clothing rects,
## clothing polygons, shoe rects, cap rects, balls, cones, highlights, then outlines.
static func draw_hunters(
		item: CanvasItem,
		centres: PackedVector2Array,
		slot_indices: PackedInt32Array,
		hats: PackedInt32Array,
		clothes_ids: PackedInt32Array,
		shoes_ids: PackedInt32Array,
		scale: float = 1.0,
		highlight_layers: PackedInt32Array = PackedInt32Array(),
		facings: PackedInt32Array = PackedInt32Array()
	) -> void:
	var n: int = centres.size()
	if n == 0:
		return
	var half: float = BODY_HALF * scale
	var bodies: Array[Rect2] = []
	var cloth_rects: Array[Rect2] = []
	var cloth_cols: Array[Color] = []
	var cloth_polys: Array[PackedVector2Array] = []
	var cloth_poly_cols: Array[Color] = []
	var shoe_rects: Array[Rect2] = []
	var shoe_cols: Array[Color] = []
	var cap_rects: Array[Rect2] = []
	var cap_cols: Array[Color] = []
	var balls: Array[Vector2] = []
	var ball_r: Array[float] = []
	var ball_cols: Array[Color] = []
	var cones: Array[PackedVector2Array] = []
	var cone_cols: Array[Color] = []
	var ticks: Array[Rect2] = []

	for i in range(n):
		var c: Vector2 = centres[i]
		var slot: int = slot_indices[i] if i < slot_indices.size() else 0
		var base: Color = body_color(slot)
		var dark: Color = shade(base, 0.62)
		var mid: Color = shade(base, 0.78)
		var ink: Color = shade(base, SHOE_MUL)
		var face: int = facings[i] if i < facings.size() else InputFrame.Dir.DOWN
		var body := Rect2(c.x - half, c.y - half, half * 2.0, half * 2.0)
		bodies.append(body)

		match wrap_index(clothes_ids[i] if i < clothes_ids.size() else 0, option_count(Layer.CLOTHES)):
			1:  # VEST
				cloth_rects.append(Rect2(c.x - half + scale, c.y - half * 0.15, half * 2.0 - 2.0 * scale, half * 0.7))
				cloth_cols.append(dark)
			2:  # OVERALLS
				cloth_rects.append(Rect2(c.x - half, c.y, half * 2.0, half))
				cloth_cols.append(dark)
				cloth_rects.append(Rect2(c.x - half + scale, c.y - half, 2.0 * scale, half + scale))
				cloth_cols.append(mid)
				cloth_rects.append(Rect2(c.x + half - 3.0 * scale, c.y - half, 2.0 * scale, half + scale))
				cloth_cols.append(mid)
			3:  # SASH — three rects, stay in the rect batch
				var step: float = half * 0.45
				for k in range(3):
					var ox: float = -half * 0.55 + float(k) * step
					var oy: float = -half * 0.35 + float(k) * step * 0.7
					cloth_rects.append(Rect2(c.x + ox, c.y + oy, 3.0 * scale, 3.0 * scale))
					cloth_cols.append(dark)
			4:  # SKIRT — A-line, hem past the outline
				cloth_polys.append(PackedVector2Array([
					c + Vector2(-half * 0.2, half * 0.35),
					c + Vector2(half * 0.2, half * 0.35),
					c + Vector2(half + 3.5 * scale, half + 2.0 * scale),
					c + Vector2(-half - 3.5 * scale, half + 2.0 * scale),
				]))
				cloth_poly_cols.append(ACCENT)
				cloth_polys.append(PackedVector2Array([
					c + Vector2(-half * 0.45, half * 0.05),
					c + Vector2(half * 0.45, half * 0.05),
					c + Vector2(half + 2.5 * scale, half + 0.4 * scale),
					c + Vector2(-half - 2.5 * scale, half + 0.4 * scale),
				]))
				cloth_poly_cols.append(dark)
			5:  # PLEATS
				var pw: float = 3.5 * scale
				var top: float = c.y + 0.5 * scale
				var ph: float = half * 0.95
				cloth_rects.append(Rect2(c.x - half - 2.0 * scale, top, pw, ph))
				cloth_cols.append(dark)
				cloth_rects.append(Rect2(c.x - pw * 0.5, top, pw, ph + scale))
				cloth_cols.append(mid)
				cloth_rects.append(Rect2(c.x + half + 2.0 * scale - pw, top, pw, ph))
				cloth_cols.append(dark)
				cloth_rects.append(Rect2(c.x - half - 2.0 * scale, top, half * 2.0 + 4.0 * scale, 2.0 * scale))
				cloth_cols.append(ink)
			6:  # TUTU — short and wide
				cloth_polys.append(PackedVector2Array([
					c + Vector2(-half * 0.35, half * 0.15),
					c + Vector2(half * 0.35, half * 0.15),
					c + Vector2(half + 4.5 * scale, half * 0.85),
					c + Vector2(-half - 4.5 * scale, half * 0.85),
				]))
				cloth_poly_cols.append(ACCENT)
				cloth_polys.append(PackedVector2Array([
					c + Vector2(-half * 0.5, half * 0.02),
					c + Vector2(half * 0.5, half * 0.02),
					c + Vector2(half + 3.5 * scale, half * 0.62),
					c + Vector2(-half - 3.5 * scale, half * 0.62),
				]))
				cloth_poly_cols.append(dark)

		# Feet and the pack sit outside the body. The outline is painted last, so a
		# shoe that only filled the bottom edge vanished under it, and a
		# downward-facing pack used to land in the hat band.
		match wrap_index(shoes_ids[i] if i < shoes_ids.size() else 0, option_count(Layer.SHOES)):
			1:  # BOOTS
				var boot_l := Rect2(c.x - half - scale, c.y + half - 3.0 * scale, 6.0 * scale, 5.0 * scale)
				var boot_r := Rect2(c.x + half - 5.0 * scale, c.y + half - 3.0 * scale, 6.0 * scale, 5.0 * scale)
				shoe_rects.append(boot_l)
				shoe_cols.append(ink)
				shoe_rects.append(boot_r)
				shoe_cols.append(ink)
				shoe_rects.append(Rect2(boot_l.position.x, boot_l.position.y + boot_l.size.y - 1.5 * scale, boot_l.size.x, 1.5 * scale))
				shoe_cols.append(ACCENT)
				shoe_rects.append(Rect2(boot_r.position.x, boot_r.position.y + boot_r.size.y - 1.5 * scale, boot_r.size.x, 1.5 * scale))
				shoe_cols.append(ACCENT)
			2:  # SNEAKERS
				var sn_l := Rect2(c.x - half - 1.5 * scale, c.y + half - scale, 6.5 * scale, 4.0 * scale)
				var sn_r := Rect2(c.x + half - 5.0 * scale, c.y + half - scale, 6.5 * scale, 4.0 * scale)
				shoe_rects.append(sn_l)
				shoe_cols.append(ACCENT)
				shoe_rects.append(sn_r)
				shoe_cols.append(ACCENT)
				shoe_rects.append(Rect2(sn_l.position.x, sn_l.position.y + 2.2 * scale, sn_l.size.x, 1.8 * scale))
				shoe_cols.append(ink)
				shoe_rects.append(Rect2(sn_r.position.x, sn_r.position.y + 2.2 * scale, sn_r.size.x, 1.8 * scale))
				shoe_cols.append(ink)
			3:  # PACK — beside the body, opposite the face, never under the hat
				var pack := Rect2(c.x - half - 4.0 * scale, c.y + scale, 4.0 * scale, 6.0 * scale)
				match face:
					InputFrame.Dir.LEFT:
						pack = Rect2(c.x + half, c.y + scale, 4.0 * scale, 6.0 * scale)
					InputFrame.Dir.RIGHT:
						pack = Rect2(c.x - half - 4.0 * scale, c.y + scale, 4.0 * scale, 6.0 * scale)
					InputFrame.Dir.UP:
						pack = Rect2(c.x + scale, c.y + half, 5.0 * scale, 4.0 * scale)
					InputFrame.Dir.DOWN:
						pack = Rect2(c.x - half - 4.0 * scale, c.y + scale, 4.0 * scale, 6.0 * scale)
				shoe_rects.append(pack)
				shoe_cols.append(ink)
				shoe_rects.append(Rect2(pack.position.x + scale, pack.position.y + 2.0 * scale, 2.0 * scale, 2.0 * scale))
				shoe_cols.append(ACCENT)

		match wrap_index(hats[i] if i < hats.size() else 0, option_count(Layer.HEAD)):
			1:  # CAP
				cap_rects.append(Rect2(c.x - half - scale, c.y - half - 3.0 * scale, half * 2.0 + 2.0 * scale, 3.0 * scale))
				cap_cols.append(mid)
				cap_rects.append(Rect2(c.x - 2.0 * scale, c.y - half - 2.0 * scale, half + scale, 2.0 * scale))
				cap_cols.append(ACCENT)
			2:  # CONE
				cones.append(PackedVector2Array([
					c + Vector2(0, -half - 7.0 * scale),
					c + Vector2(4.0 * scale, -half + scale),
					c + Vector2(-4.0 * scale, -half + scale),
				]))
				cone_cols.append(mid)
			3:  # BALL
				balls.append(c + Vector2(0, -half - 2.0 * scale))
				ball_r.append(3.0 * scale)
				ball_cols.append(mid)
			4:  # EARS
				cones.append(PackedVector2Array([
					c + Vector2(-half + 2.0 * scale, -half + scale),
					c + Vector2(-half - scale, -half - 6.0 * scale),
					c + Vector2(-half + 5.0 * scale, -half + scale),
				]))
				cone_cols.append(mid)
				cones.append(PackedVector2Array([
					c + Vector2(half - 2.0 * scale, -half + scale),
					c + Vector2(half + scale, -half - 6.0 * scale),
					c + Vector2(half - 5.0 * scale, -half + scale),
				]))
				cone_cols.append(mid)
				cones.append(PackedVector2Array([
					c + Vector2(-half + 2.5 * scale, -half + 0.5 * scale),
					c + Vector2(-half + 0.5 * scale, -half - 3.5 * scale),
					c + Vector2(-half + 4.0 * scale, -half + 0.5 * scale),
				]))
				cone_cols.append(ACCENT)
				cones.append(PackedVector2Array([
					c + Vector2(half - 2.5 * scale, -half + 0.5 * scale),
					c + Vector2(half - 0.5 * scale, -half - 3.5 * scale),
					c + Vector2(half - 4.0 * scale, -half + 0.5 * scale),
				]))
				cone_cols.append(ACCENT)
			5:  # MOHAWK
				cap_rects.append(Rect2(c.x - 2.0 * scale, c.y - half - 7.0 * scale, 3.0 * scale, 8.0 * scale))
				cap_cols.append(dark)
				cap_rects.append(Rect2(c.x + 0.5 * scale, c.y - half - 5.0 * scale, 2.0 * scale, 5.0 * scale))
				cap_cols.append(mid)
			6:  # PROP — propeller beanie
				cap_rects.append(Rect2(c.x - scale, c.y - half - 4.0 * scale, 2.0 * scale, 4.0 * scale))
				cap_cols.append(mid)
				cap_rects.append(Rect2(c.x - 6.0 * scale, c.y - half - 5.5 * scale, 12.0 * scale, 2.0 * scale))
				cap_cols.append(dark)
				balls.append(c + Vector2(0, -half - 4.5 * scale))
				ball_r.append(1.6 * scale)
				ball_cols.append(ACCENT)
			7:  # BOW
				var bow_y: float = -half - scale
				cones.append(PackedVector2Array([
					c + Vector2(-scale, bow_y),
					c + Vector2(-6.0 * scale, bow_y - 3.0 * scale),
					c + Vector2(-6.0 * scale, bow_y + 3.0 * scale),
				]))
				cone_cols.append(mid)
				cones.append(PackedVector2Array([
					c + Vector2(scale, bow_y),
					c + Vector2(6.0 * scale, bow_y - 3.0 * scale),
					c + Vector2(6.0 * scale, bow_y + 3.0 * scale),
				]))
				cone_cols.append(mid)
				cap_rects.append(Rect2(c.x - 1.5 * scale, c.y + bow_y - 1.5 * scale, 3.0 * scale, 3.0 * scale))
				cap_cols.append(ACCENT)
			8:  # ANTENNA
				cap_rects.append(Rect2(c.x - 0.5 * scale, c.y - half - 6.0 * scale, scale, 6.0 * scale))
				cap_cols.append(dark)
				balls.append(c + Vector2(0, -half - 6.5 * scale))
				ball_r.append(1.8 * scale)
				ball_cols.append(ACCENT)

		var hi: int = highlight_layers[i] if i < highlight_layers.size() else -1
		if hi == Layer.HEAD:
			ticks.append(Rect2(c.x - 2.0 * scale, c.y - half - 12.0 * scale, 4.0 * scale, 2.0 * scale))
		elif hi == Layer.CLOTHES:
			ticks.append(Rect2(c.x - half - 8.0 * scale, c.y - 2.0 * scale, 3.0 * scale, 3.0 * scale))
		elif hi == Layer.SHOES:
			ticks.append(Rect2(c.x - 2.0 * scale, c.y + half + 5.0 * scale, 4.0 * scale, 2.0 * scale))

	for i in range(n):
		item.draw_rect(bodies[i], body_color(slot_indices[i] if i < slot_indices.size() else 0), true)
	for i in range(cloth_rects.size()):
		item.draw_rect(cloth_rects[i], cloth_cols[i], true)
	for i in range(cloth_polys.size()):
		item.draw_colored_polygon(cloth_polys[i], cloth_poly_cols[i])
	for i in range(shoe_rects.size()):
		item.draw_rect(shoe_rects[i], shoe_cols[i], true)
	for i in range(cap_rects.size()):
		item.draw_rect(cap_rects[i], cap_cols[i], true)
	for i in range(balls.size()):
		item.draw_circle(balls[i], ball_r[i], ball_cols[i])
	for i in range(cones.size()):
		item.draw_colored_polygon(cones[i], cone_cols[i])
	for t in ticks:
		item.draw_rect(t, ACCENT, true)
	for r in bodies:
		item.draw_rect(r, Color.BLACK, false, 1.0)
