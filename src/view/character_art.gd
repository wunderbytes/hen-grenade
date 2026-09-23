class_name CharacterArt
## Programmer-art hunter layers: hat, clothes, shoes. Lobby preview and
## EntityView share this painter so a retune here cannot leave the card
## describing a different figure. See docs/milestone-3.6-brief.md.
##
## Body fill is always C.PLAYER_COLORS[slot]. Overlays are shades of that hue
## plus a black outline and a cream accent — never a second player colour.

enum Layer { HEAD = 0, CLOTHES = 1, SHOES = 2 }

const LAYER_COUNT: int = PlayerSlot.LOOK_LAYERS
const OPTION_COUNT: int = PlayerSlot.LOOK_OPTIONS
const BODY_HALF: float = 7.0
const ACCENT := Color8(245, 242, 230)

const HEAD_NAMES: PackedStringArray = ["NONE", "CAP", "CONE", "BALL"]
const CLOTHES_NAMES: PackedStringArray = ["TUNIC", "VEST", "OVERALLS", "SASH"]
const SHOES_NAMES: PackedStringArray = ["NONE", "BOOTS", "SNEAKERS", "PACK"]

static func wrap_index(value: int, count: int) -> int:
	return PlayerSlot.wrap_look(value, count)

static func option_name(layer: int, option: int) -> String:
	var i: int = wrap_index(option, OPTION_COUNT)
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
## shoe rects, cap rects, packs, balls, cones, highlights, then outlines.
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
		var face: int = facings[i] if i < facings.size() else InputFrame.Dir.DOWN
		var body := Rect2(c.x - half, c.y - half, half * 2.0, half * 2.0)
		bodies.append(body)

		match wrap_index(clothes_ids[i] if i < clothes_ids.size() else 0, OPTION_COUNT):
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

		match wrap_index(shoes_ids[i] if i < shoes_ids.size() else 0, OPTION_COUNT):
			1:  # BOOTS
				shoe_rects.append(Rect2(c.x - half, c.y + half - 4.0 * scale, 5.0 * scale, 4.0 * scale))
				shoe_cols.append(dark)
				shoe_rects.append(Rect2(c.x + half - 5.0 * scale, c.y + half - 4.0 * scale, 5.0 * scale, 4.0 * scale))
				shoe_cols.append(dark)
			2:  # SNEAKERS
				shoe_rects.append(Rect2(c.x - half, c.y + half - 2.0 * scale, 5.0 * scale, 2.0 * scale))
				shoe_cols.append(ACCENT)
				shoe_rects.append(Rect2(c.x + half - 5.0 * scale, c.y + half - 2.0 * scale, 5.0 * scale, 2.0 * scale))
				shoe_cols.append(ACCENT)
			3:  # PACK — opposite facing
				var pack := Rect2(c.x - half - 3.0 * scale, c.y - 3.0 * scale, 3.0 * scale, 6.0 * scale)
				match face:
					InputFrame.Dir.LEFT:
						pack = Rect2(c.x + half, c.y - 3.0 * scale, 3.0 * scale, 6.0 * scale)
					InputFrame.Dir.RIGHT:
						pack = Rect2(c.x - half - 3.0 * scale, c.y - 3.0 * scale, 3.0 * scale, 6.0 * scale)
					InputFrame.Dir.UP:
						pack = Rect2(c.x - 3.0 * scale, c.y + half, 6.0 * scale, 3.0 * scale)
					InputFrame.Dir.DOWN:
						pack = Rect2(c.x - 3.0 * scale, c.y - half - 3.0 * scale, 6.0 * scale, 3.0 * scale)
				shoe_rects.append(pack)
				shoe_cols.append(dark)

		match wrap_index(hats[i] if i < hats.size() else 0, OPTION_COUNT):
			1:  # CAP
				cap_rects.append(Rect2(c.x - half - scale, c.y - half - 3.0 * scale, half * 2.0 + 2.0 * scale, 3.0 * scale))
				cap_cols.append(mid)
				cap_rects.append(Rect2(c.x - 2.0 * scale, c.y - half - 2.0 * scale, half + scale, 2.0 * scale))
				cap_cols.append(ACCENT)
			2:  # CONE
				var cone := PackedVector2Array([
					c + Vector2(0, -half - 7.0 * scale),
					c + Vector2(4.0 * scale, -half + scale),
					c + Vector2(-4.0 * scale, -half + scale),
				])
				cones.append(cone)
				cone_cols.append(mid)
			3:  # BALL
				balls.append(c + Vector2(0, -half - 2.0 * scale))
				ball_r.append(3.0 * scale)
				ball_cols.append(mid)

		var hi: int = highlight_layers[i] if i < highlight_layers.size() else -1
		if hi == Layer.HEAD:
			ticks.append(Rect2(c.x - 2.0 * scale, c.y - half - 10.0 * scale, 4.0 * scale, 2.0 * scale))
		elif hi == Layer.CLOTHES:
			ticks.append(Rect2(c.x - half - 5.0 * scale, c.y - 2.0 * scale, 3.0 * scale, 3.0 * scale))
		elif hi == Layer.SHOES:
			ticks.append(Rect2(c.x - 2.0 * scale, c.y + half + 2.0 * scale, 4.0 * scale, 2.0 * scale))

	for i in range(n):
		item.draw_rect(bodies[i], body_color(slot_indices[i] if i < slot_indices.size() else 0), true)
	for i in range(cloth_rects.size()):
		item.draw_rect(cloth_rects[i], cloth_cols[i], true)
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
