extends TileMapLayer
## Draws the arena grid. See docs/milestone-1-brief.md §9.
##
## The whole point of this class is what it does *not* do: the tilemap is
## rebuilt on sync() and then only ever touched one cell at a time, when a crate
## is destroyed. It is never redrawn per frame (technical design §5), because a
## 375-cell tilemap redraw every frame is exactly the kind of cost a VideoCore
## VI cannot absorb.

## Programmer-art palette. Chosen for contrast rather than beauty: the floor has
## to read as clearly not-a-wall at a glance from across a living room, which is
## the readability pillar in its cheapest possible form.
const FLOOR_COLOR: Color = Color8(40, 44, 52)
const HARD_COLOR: Color = Color8(170, 176, 188)
const CRATE_COLOR: Color = Color8(150, 100, 60)

func setup() -> void:
	tile_set = PlaceholderTileset.build([FLOOR_COLOR, HARD_COLOR, CRATE_COLOR])
	position = Vector2(C.ARENA_ORIGIN)

## Full rebuild. Called once per round, not per frame.
func sync(arena: Arena) -> void:
	for y in range(arena.h):
		for x in range(arena.w):
			var t: Vector2i = Vector2i(x, y)
			set_cell(t, 0, Vector2i(_atlas_for(arena.at(t)), 0))

## Single-cell update in response to a CRATE_DESTROYED event.
func clear_crate(tile: Vector2i) -> void:
	set_cell(tile, 0, Vector2i(PlaceholderTileset.FLOOR, 0))

func _atlas_for(tile_type: int) -> int:
	match tile_type:
		Arena.Tile.HARD: return PlaceholderTileset.HARD
		Arena.Tile.CRATE: return PlaceholderTileset.CRATE
	return PlaceholderTileset.FLOOR
