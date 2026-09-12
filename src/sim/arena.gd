class_name Arena
## The tile grid and its generation. See docs/milestone-1-brief.md §4.1 and
## docs/game-design.md §4.
##
## Tiles live in a flat PackedByteArray indexed y * w + x. Flat because there is
## no iteration order to get wrong (determinism contract, M1 brief §2) and
## because a packed array of bytes is the cheapest thing the Pi has to touch
## when the view syncs.

enum Tile { FLOOR = 0, HARD = 1, CRATE = 2 }

var w: int = 0
var h: int = 0
var tiles: PackedByteArray = PackedByteArray()

func _init(p_w: int = C.GRID_W, p_h: int = C.GRID_H) -> void:
	w = p_w
	h = p_h
	tiles.resize(w * h)
	tiles.fill(Tile.FLOOR)

# --- Queries ----------------------------------------------------------------

func index(t: Vector2i) -> int:
	return t.y * w + t.x

func in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < w and t.y < h

## Tile type, or HARD for anything off the grid — out of bounds behaves as an
## indestructible wall so no caller has to bounds-check before asking.
func at(t: Vector2i) -> int:
	if not in_bounds(t):
		return Tile.HARD
	return tiles[index(t)]

func set_at(t: Vector2i, value: int) -> void:
	if in_bounds(t):
		tiles[index(t)] = value

## Solid to movement and to blast rays. Bombs are not part of the arena — bomb
## solidity has a per-player exemption and therefore lives on MatchState.
func is_solid(t: Vector2i) -> bool:
	var tile: int = at(t)
	return tile == Tile.HARD or tile == Tile.CRATE

func count_of(value: int) -> int:
	var n: int = 0
	for i in range(tiles.size()):
		if tiles[i] == value:
			n += 1
	return n

## The classic Bomberman lattice: interior tiles with both coordinates even.
func is_lattice_pillar(t: Vector2i) -> bool:
	if t.x <= 0 or t.y <= 0 or t.x >= w - 1 or t.y >= h - 1:
		return false
	return t.x % 2 == 0 and t.y % 2 == 0

func is_border(t: Vector2i) -> bool:
	return t.x == 0 or t.y == 0 or t.x == w - 1 or t.y == h - 1

func duplicate_arena() -> Arena:
	var copy: Arena = Arena.new(w, h)
	copy.tiles = tiles.duplicate()
	return copy

# --- Generation -------------------------------------------------------------

## Builds an arena from a definition and a seeded PRNG.
##
## The order of operations matters and is fixed:
##   1. border + pillar lattice
##   2. one crate draw per eligible quadrant tile, in y-then-x order, mirrored
##   3. spawn clearances
##   4. respawn tiles cleared
##
## Steps 3 and 4 run *after* the draw rather than as a filter before it, so
## clearance geometry can never shift the PRNG sequence. Change the spawn
## layout and the crates stay exactly where they were.
static func generate(def: ArenaDef, rng: SimRng) -> Arena:
	var arena: Arena = Arena.new(def.grid_w, def.grid_h)

	for y in range(arena.h):
		for x in range(arena.w):
			var t: Vector2i = Vector2i(x, y)
			if arena.is_border(t) or arena.is_lattice_pillar(t):
				arena.set_at(t, Tile.HARD)

	# One quadrant, mirrored four ways, so no corner is luckier than another
	# (game design §4). For a 25 x 15 grid the quadrant is x in [1,12],
	# y in [1,7]; the centre column and centre row mirror onto themselves, so
	# there is no double-write and no seam down the middle.
	var qx_max: int = (arena.w - 1) / 2
	var qy_max: int = (arena.h - 1) / 2
	for y in range(1, qy_max + 1):
		for x in range(1, qx_max + 1):
			var t: Vector2i = Vector2i(x, y)
			if arena.at(t) != Tile.FLOOR:
				continue      # a pillar: not eligible, and draws no number
			var place: bool = rng.next_below(1000) < def.crate_permille
			if not place:
				continue
			for m in arena.mirrors_of(t):
				if arena.at(m) == Tile.FLOOR:
					arena.set_at(m, Tile.CRATE)

	for spawn in def.spawn_tiles:
		arena._clear_spawn_clearance(spawn)
	for respawn in def.respawn_tiles:
		if arena.at(respawn) == Tile.CRATE:
			arena.set_at(respawn, Tile.FLOOR)

	return arena

## The up-to-four mirror images of a tile. Duplicates are possible on the centre
## row/column and are harmless: writing a crate twice is idempotent.
func mirrors_of(t: Vector2i) -> Array[Vector2i]:
	var mx: int = w - 1 - t.x
	var my: int = h - 1 - t.y
	return [
		Vector2i(t.x, t.y),
		Vector2i(mx, t.y),
		Vector2i(t.x, my),
		Vector2i(mx, my),
	]

## A spawn tile and its orthogonal neighbours are cleared of crates, so a player
## always has somewhere to run at round start. Pillars and the border are left
## alone — the lattice guarantees an odd/odd spawn has two open directions.
func _clear_spawn_clearance(spawn: Vector2i) -> void:
	var cells: Array[Vector2i] = [
		spawn,
		spawn + Vector2i(0, -1),
		spawn + Vector2i(1, 0),
		spawn + Vector2i(0, 1),
		spawn + Vector2i(-1, 0),
	]
	for cell in cells:
		if at(cell) == Tile.CRATE:
			set_at(cell, Tile.FLOOR)
