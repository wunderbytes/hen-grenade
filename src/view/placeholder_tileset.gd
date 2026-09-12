class_name PlaceholderTileset
## Builds a TileSet from solid-colour cells generated at runtime, so the game
## has a real TileMapLayer with no binary assets committed.
##
## Written for the M0 dev scenes and promoted to src/view/ in M1: it is now the
## arena's actual tileset, and it stays that way until M4 replaces it with real
## pixel art. Generating the atlas at runtime also keeps M1 free of any
## VRAM-compressed texture, which is why the arm32 export trap has not bitten
## yet (see docs/measurements/m0-pi400.md).

## Returns a TileSet whose atlas tiles are the given solid colours, one tile per
## colour, each TILE_PX x TILE_PX. Tile atlasses are laid out horizontally.
static func build(tile_colors: Array[Color]) -> TileSet:
	var ts: TileSet = TileSet.new()
	ts.tile_size = Vector2i(C.TILE_PX, C.TILE_PX)
	var atlas: TileSetAtlasSource = TileSetAtlasSource.new()
	var img: Image = Image.create(C.TILE_PX * tile_colors.size(), C.TILE_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in range(tile_colors.size()):
		var color: Color = tile_colors[i]
		for x in range(C.TILE_PX):
			for y in range(C.TILE_PX):
				img.set_pixel(i * C.TILE_PX + x, y, color)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	atlas.texture = tex
	atlas.texture_region_size = Vector2i(C.TILE_PX, C.TILE_PX)
	for i in range(tile_colors.size()):
		atlas.create_tile(Vector2i(i, 0))
	ts.add_source(atlas)
	return ts

## Tile atlas indices used by the dev scenes.
const FLOOR: int = 0
const HARD: int = 1
const CRATE: int = 2
