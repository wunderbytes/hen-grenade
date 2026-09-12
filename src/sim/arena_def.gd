class_name ArenaDef
extends Resource
## Arena shape and layout parameters. See docs/milestone-1-brief.md §3.2.
##
## The simulation is written against whatever grid size this resource specifies:
## 25 x 15 is a value, not an assumption baked into the code. "Does the 23 x 13
## interior play too large?" (game design §10, open question 2) is answered by
## editing this file and playing, which is the entire point of §6 of the
## technical design.

@export var grid_w: int = C.GRID_W
@export var grid_h: int = C.GRID_H

## Crate density over the eligible interior, in permille. 700 = ~70%.
## Permille rather than a float so the generator compares integers — see the
## determinism contract, M1 brief §2.
@export var crate_permille: int = 700

## Round-start positions, one per player slot, in slot order. Each of these and
## its orthogonal neighbours is force-cleared of crates (the classic L).
@export var spawn_tiles: Array[Vector2i] = [
	Vector2i(1, 1),
	Vector2i(23, 1),
	Vector2i(1, 13),
	Vector2i(23, 13),
]

## Designated respawn tiles. Corner spawns alone are not enough when players die
## every few seconds (game design §5.3), so this is nine tiles spread across the
## arena: four corners, four edge midpoints, and the centre.
##
## Two properties are deliberate. **No tile has both coordinates even**, so none
## of them can land on a pillar. And the set is **symmetric under both mirror
## axes**, so respawning is exactly as fair as the mirrored layout.
##
## Listed in tile-index order (y * w + x) because respawn tie-breaking is by
## tile index, and a list in a different order would make the tie-break rule
## true in the fallback path but not in this one.
@export var respawn_tiles: Array[Vector2i] = [
	Vector2i(1, 1), Vector2i(12, 1), Vector2i(23, 1),
	Vector2i(1, 7), Vector2i(12, 7), Vector2i(23, 7),
	Vector2i(1, 13), Vector2i(12, 13), Vector2i(23, 13),
]

func fingerprint() -> int:
	var h: int = SimHash.start()
	h = SimHash.mix_int(h, grid_w)
	h = SimHash.mix_int(h, grid_h)
	h = SimHash.mix_int(h, crate_permille)
	for t in spawn_tiles:
		h = SimHash.mix_vec(h, t)
	for t in respawn_tiles:
		h = SimHash.mix_vec(h, t)
	return h
