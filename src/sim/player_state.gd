class_name PlayerState
## One player's simulation state. See docs/milestone-1-brief.md §4.
##
## A plain RefCounted, never a Node: this has to construct and run in a headless
## --script process with no scene tree.
##
## `pos` is the player's **centre** in fixed-point sub-tile units where one tile
## is C.UNITS_PER_TILE (256). Tile (tx, ty)'s centre is
## (tx * 256 + 128, ty * 256 + 128). Nothing here is a float.

## Slot index, 0..C.MAX_PLAYERS-1. Also the flame-ownership and kill-credit key.
var index: int = -1
## Is this slot playing this round at all? An unoccupied slot stays inactive and
## is skipped everywhere, but keeps its array position so indices stay stable.
var active: bool = false
var alive: bool = false

var pos: Vector2i = Vector2i.ZERO
var facing: InputFrame.Dir = InputFrame.Dir.DOWN

# --- Loadout (M3 grows these via power-ups) ---------------------------------
var speed_units: int = 15
var bomb_capacity: int = 1
var blast_radius: int = 1
var bombs_active: int = 0

# --- Timers (all integer tick counters, never float accumulations) ----------
var respawn_ticks: int = 0
var spawn_protect_ticks: int = 0

# --- Score ------------------------------------------------------------------
var score: int = 0
var kills: int = 0
var deaths: int = 0

## The own-bomb pass-off from game design §5.2: the tile of a bomb this player
## is currently standing on and may walk off. (-1, -1) for none. Cleared the
## first tick the player's centre leaves that tile, which makes the exemption
## one-way: you can step off your own bomb, never back onto it.
var bomb_exempt_tile: Vector2i = Vector2i(-1, -1)

## Previous tick's bomb button, for rising-edge detection. Part of the state
## because it has to survive across steps and be captured by the fingerprint —
## holding A must not machine-gun bombs, and a replay has to reproduce that.
var prev_bomb: bool = false

func _init(p_index: int = -1) -> void:
	index = p_index

## The tile containing this player's centre. Integer division; positions are
## never negative inside a bordered arena.
func tile() -> Vector2i:
	return Vector2i(pos.x / C.UNITS_PER_TILE, pos.y / C.UNITS_PER_TILE)

func has_bomb_exemption() -> bool:
	return bomb_exempt_tile.x >= 0

func clear_bomb_exemption() -> void:
	bomb_exempt_tile = Vector2i(-1, -1)

func mix_into(h: int) -> int:
	var acc: int = SimHash.mix_int(h, index)
	acc = SimHash.mix_bool(acc, active)
	acc = SimHash.mix_bool(acc, alive)
	acc = SimHash.mix_vec(acc, pos)
	acc = SimHash.mix_int(acc, int(facing))
	acc = SimHash.mix_int(acc, speed_units)
	acc = SimHash.mix_int(acc, bomb_capacity)
	acc = SimHash.mix_int(acc, blast_radius)
	acc = SimHash.mix_int(acc, bombs_active)
	acc = SimHash.mix_int(acc, respawn_ticks)
	acc = SimHash.mix_int(acc, spawn_protect_ticks)
	acc = SimHash.mix_int(acc, score)
	acc = SimHash.mix_int(acc, kills)
	acc = SimHash.mix_int(acc, deaths)
	acc = SimHash.mix_vec(acc, bomb_exempt_tile)
	acc = SimHash.mix_bool(acc, prev_bomb)
	return acc
