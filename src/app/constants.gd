class_name C
## Single source of truth for every magic number the project depends on.
## Nothing under src/ should hardcode a value that lives here.
## See docs/milestone-0-brief.md §4.

# --- Grid ---------------------------------------------------------------------
const GRID_W: int = 25
const GRID_H: int = 15
const TILE_PX: int = 20

# --- Viewport -----------------------------------------------------------------
const VIEW_W: int = 640
const VIEW_H: int = 360
const ARENA_PX_W: int = GRID_W * TILE_PX          # 500
const ARENA_PX_H: int = GRID_H * TILE_PX          # 300
## Arena top-left in viewport pixels, centred horizontally with side HUD margins
## and a top/bottom band for the round clock.
const ARENA_ORIGIN := Vector2i(70, 30)
const HUD_PANEL_W: int = 70                       # width of each side margin

# --- Simulation --------------------------------------------------------------
const TICK_HZ: int = 60
## Fixed-point sub-tile units: one tile == 256 units.
## Speeds are stored as integer units-per-tick, not tiles-per-second.
## The design's 3.5 t/s becomes 3.5 * 256 / 60 ~= 14.93 -> 15 units/tick (3.516 t/s).
const UNITS_PER_TILE: int = 256
## Half a tile, in sub-tile units. The offset from a tile's top-left corner to
## its centre, and the distance from a centre to a tile boundary.
const HALF_TILE: int = UNITS_PER_TILE / 2
const MAX_PLAYERS: int = 4

# --- Player colours (programmer art) -----------------------------------------
const PLAYER_COLORS: Array[Color] = [
	Color8(232, 65, 65),    # P1 red
	Color8(60, 120, 232),   # P2 blue
	Color8(232, 200, 60),   # P3 yellow
	Color8(70, 200, 90),    # P4 green
]
