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

## Spawn protection blinks at this period, in ticks. 8 on / 8 off is fast enough
## to read as "protected" without being a strobe.
const BLINK_PERIOD: int = 16

var state: MatchState = null

## Drawn in **passes grouped by primitive type**, not entity by entity.
##
## This is not premature tidiness. Godot's 2D renderer batches consecutive
## same-kind primitives, and interleaving them — circle, circle, rect, circle —
## breaks the batch every time, which turned a screen with five bombs and a
## chain reaction into 47 draw calls against a documented budget of 20. Grouping
## the passes costs nothing and keeps a full arena of fire inside the budget.
##
## The pass order is also the painter order: flames below bombs below players,
## which is what you want anyway — a player must never be hidden by their own
## explosion.
func _draw() -> void:
	if state == null:
		return
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
	for p in shown:
		draw_rect(_body_rect(p), _player_color(p.index), true)
	for p in shown:
		draw_rect(_body_rect(p), Color.BLACK, false, 1.0)
	for p in shown:
		# Facing pip. Not decoration: with four identical squares on screen it is
		# the only cue for which way a player is about to run.
		var centre: Vector2 = _pos_px(p.pos)
		var pip: Vector2 = centre + Vector2(Sim.dir_vec(p.facing)) * (PLAYER_HALF - 2.0)
		draw_rect(Rect2(pip.x - 2.0, pip.y - 2.0, 4.0, 4.0), Color(1, 1, 1, 0.9), true)

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
