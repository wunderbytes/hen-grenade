extends Node2D
## Draws flames, bombs and players. See docs/milestone-1-brief.md §9.
##
## Everything is rectangles and circles in one _draw pass, in painter order
## flames -> bombs -> players, so the entire entity layer costs a handful of
## draw calls. Programmer art until M4.
##
## Read-only: this reads MatchState and never writes to it. The sim does not
## know the view exists, which is what lets the whole rule set be tested with no
## renderer at all.
##
## **No 2D lights, ever** (technical design §5). A blast is a bright rectangle
## and that is the whole effect budget — PointLight2D is the documented reason
## Godot 4 tilemap games hit single-digit frame rates on this GPU.

## Units-to-pixels. One tile is C.UNITS_PER_TILE sub-tile units and C.TILE_PX
## pixels, so this is the only place the two coordinate systems meet.
const PX_PER_UNIT: float = float(C.TILE_PX) / float(C.UNITS_PER_TILE)

const PLAYER_HALF: float = 7.0
const BOMB_RADIUS: float = 6.0
const FLAME_CORE: Color = Color8(255, 236, 150)
const FLAME_EDGE: Color = Color8(255, 128, 40)
const BOMB_COLOR: Color = Color8(24, 24, 28)

## Pickup look is PickupArt, shared with the lobby/HUD legend so a retune here
## cannot leave the key describing a different shape.

## Spawn protection blinks at this period, in ticks. 8 on / 8 off is fast enough
## to read as "protected" without being a strobe.
const BLINK_PERIOD: int = 16
const TOKEN_GOLD := Color8(212, 148, 28)
const TOKEN_CHEVRON := Color8(92, 48, 8)
const HEN_BODY_R: float = 9.0

var state: MatchState = null

## Drawn in **passes grouped by primitive type**, not entity by entity.
##
## This is not premature tidiness. Godot's 2D renderer batches consecutive
## same-kind primitives, and interleaving them — circle, circle, rect, circle —
## breaks the batch every time, which turned a screen with five bombs and a
## chain reaction into 47 draw calls against a documented budget of 20. Grouping
## the passes costs nothing and keeps a full arena of fire inside the budget.
##
## The pass order is also the painter order: pickups below flames below bombs
## below players, which is what you want anyway — a player must never be hidden
## by their own explosion, and a pickup about to burn should be under the fire.
##
## M3's pickups add **two** passes for any number of them, whatever kinds they
## are: one for the shells, one for the cores. That is the whole reason the
## per-kind difference is a colour and a size rather than a different primitive.
func _draw() -> void:
	if state == null:
		return
	_draw_pickups()
	_draw_hen_token()

	var flames: Array[Rect2] = []
	var flame_ages: PackedFloat32Array = PackedFloat32Array()
	_collect_flames(flames, flame_ages)
	for i in range(flames.size()):
		draw_rect(flames[i], Color(FLAME_EDGE, 0.35 + 0.45 * flame_ages[i]), true)
	for i in range(flames.size()):
		draw_rect(flames[i].grow(-4.0), Color(FLAME_CORE, 0.4 + 0.5 * flame_ages[i]), true)

	var live: Array[Bomb] = []
	for b in state.bombs:
		if not b.exploded:
			live.append(b)
	for b in live:
		draw_circle(_tile_px(b.tile), BOMB_RADIUS, BOMB_COLOR)
	for b in live:
		# Telegraphing: pulse faster as the fuse runs out (game design §8). The
		# pulse is derived from the bomb's own fuse, not from wall-clock time,
		# so a paused or replayed game shows exactly the same thing.
		#
		# A Remote bomb has no fuse to run down, so the same expression would
		# freeze it either permanently lit or permanently dark. It gets a steady
		# mark instead, which is also the honest picture: that bomb is not
		# counting, it is waiting.
		if b.remote:
			draw_circle(_tile_px(b.tile), BOMB_RADIUS - 3.0, Color(0.95, 0.9, 0.35))
			continue
		var urgency: float = _urgency(b)
		var period: int = maxi(4, int(round(24.0 - 18.0 * urgency)))
		if (b.fuse_ticks % period) < (period / 2):
			draw_circle(_tile_px(b.tile), BOMB_RADIUS - 2.0, Color(1.0, 0.45 + 0.5 * urgency, 0.2))
	for b in live:
		# A tick of the owner's colour, so you can see whose bomb you are next to.
		var centre: Vector2 = _tile_px(b.tile)
		draw_rect(Rect2(centre.x - 2.0, centre.y - BOMB_RADIUS - 3.0, 4.0, 3.0), _player_color(b.owner), true)

	var shown: Array[PlayerState] = []
	for p in state.players:
		if not p.active or not p.alive:
			continue
		# Blink through spawn protection (game design §5.3). Driven off the tick
		# counter, so it is deterministic and replay-identical.
		if p.spawn_protect_ticks > 0 and (p.spawn_protect_ticks % BLINK_PERIOD) < (BLINK_PERIOD / 2):
			continue
		shown.append(p)
	var hunters: Array[PlayerState] = []
	var hen: PlayerState = null
	for p in shown:
		if p.index == state.hen_slot:
			hen = p
		else:
			hunters.append(p)
	for p in hunters:
		draw_rect(_body_rect(p), _player_color(p.index), true)
	for p in hunters:
		draw_rect(_body_rect(p), Color.BLACK, false, 1.0)
	if hen != null:
		_draw_hen(hen)
	for p in shown:
		# Facing pip. Not decoration: with four identical squares on screen it is
		# the only cue for which way a player is about to run.
		var centre: Vector2 = _pos_px(p.pos)
		var pip: Vector2 = centre + Vector2(Sim.dir_vec(p.facing)) * (PLAYER_HALF - 2.0)
		draw_rect(Rect2(pip.x - 2.0, pip.y - 2.0, 4.0, 4.0), Color(1, 1, 1, 0.9), true)

## Two passes over the pickup grid: every dark shell, then every coloured core.
## Scanning the flat grid rather than a list is the same trade flames make — no
## per-entity allocation, and no iteration order to get wrong.
func _draw_pickups() -> void:
	var arena: Arena = state.arena
	var tiles: Array[Vector2i] = []
	var kinds: PackedInt32Array = PackedInt32Array()
	for i in range(state.pickup_kind.size()):
		var kind: int = state.pickup_kind[i]
		if kind == Powerup.Kind.NONE:
			continue
		tiles.append(Vector2i(i % arena.w, i / arena.w))
		kinds.append(kind)
	if tiles.is_empty():
		return
	for t in tiles:
		var c: Vector2 = _tile_px(t)
		draw_rect(Rect2(c.x - PickupArt.HALF, c.y - PickupArt.HALF, PickupArt.HALF * 2.0, PickupArt.HALF * 2.0), PickupArt.SHELL, true)
	for i in range(tiles.size()):
		var c: Vector2 = _tile_px(tiles[i])
		var half: float = PickupArt.INNER[kinds[i]]
		draw_rect(Rect2(c.x - half, c.y - half, half * 2.0, half * 2.0), PickupArt.COLORS[kinds[i]], true)

## Gold disc plus a chevron — not a pickup, and not Jackpot's white square.
func _draw_hen_token() -> void:
	if not state.has_hen_token_on_floor():
		return
	var c: Vector2 = _tile_px(state.hen_token_tile)
	draw_circle(c, 6.0, TOKEN_GOLD)
	var chevron: PackedVector2Array = PackedVector2Array([
		c + Vector2(0, -4),
		c + Vector2(4, 3),
		c + Vector2(1.5, 3),
		c + Vector2(0, 0.5),
		c + Vector2(-1.5, 3),
		c + Vector2(-4, 3),
	])
	draw_colored_polygon(chevron, TOKEN_CHEVRON)

## Larger oval plus a three-point comb, drawn after the hunter rects so the
## hunter batch stays a rect pass (Appendix A.12). Slot colour stays on the
## outline so P2-as-Hen is still blue.
func _draw_hen(p: PlayerState) -> void:
	var c: Vector2 = _pos_px(p.pos)
	draw_circle(c, HEN_BODY_R, _player_color(p.index))
	var comb: PackedVector2Array = PackedVector2Array([
		c + Vector2(-6, -HEN_BODY_R + 2),
		c + Vector2(-4, -HEN_BODY_R - 5),
		c + Vector2(-2, -HEN_BODY_R + 1),
		c + Vector2(0, -HEN_BODY_R - 6),
		c + Vector2(2, -HEN_BODY_R + 1),
		c + Vector2(4, -HEN_BODY_R - 5),
		c + Vector2(6, -HEN_BODY_R + 2),
	])
	draw_colored_polygon(comb, _player_color(p.index))
	draw_arc(c, HEN_BODY_R, 0.0, TAU, 16, Color.BLACK, 1.0)

func _collect_flames(out_rects: Array[Rect2], out_ages: PackedFloat32Array) -> void:
	var arena: Arena = state.arena
	var full: int = maxi(1, state.balance.flame_ticks)
	for i in range(state.flame_ttl.size()):
		var ttl: int = state.flame_ttl[i]
		if ttl <= 0:
			continue
		var tile: Vector2i = Vector2i(i % arena.w, i / arena.w)
		out_rects.append(Rect2(tile.x * C.TILE_PX, tile.y * C.TILE_PX, C.TILE_PX, C.TILE_PX))
		# Fade out over the flame's life so the danger reads as receding rather
		# than vanishing on one frame.
		out_ages.append(float(ttl) / float(full))

func _urgency(b: Bomb) -> float:
	return 1.0 - clampf(float(b.fuse_ticks) / float(maxi(1, state.balance.bomb_fuse_ticks)), 0.0, 1.0)

func _body_rect(p: PlayerState) -> Rect2:
	var centre: Vector2 = _pos_px(p.pos)
	return Rect2(centre.x - PLAYER_HALF, centre.y - PLAYER_HALF, PLAYER_HALF * 2.0, PLAYER_HALF * 2.0)

func _tile_px(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * C.TILE_PX + C.TILE_PX / 2.0, tile.y * C.TILE_PX + C.TILE_PX / 2.0)

func _pos_px(pos: Vector2i) -> Vector2:
	return Vector2(pos) * PX_PER_UNIT

func _player_color(index: int) -> Color:
	if index < 0 or index >= C.PLAYER_COLORS.size():
		return Color.WHITE
	return C.PLAYER_COLORS[index]
