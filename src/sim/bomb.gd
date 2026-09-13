class_name Bomb
## One live bomb. See docs/milestone-1-brief.md §6.1.

var tile: Vector2i = Vector2i.ZERO
## Slot index of the player who dropped it. Kept separate from the flame owner:
## a chained bomb's flames are credited to whoever started the chain, but the
## bomb itself still counts against *this* player's concurrent-bomb budget.
var owner: int = -1
var fuse_ticks: int = 0
## Captured from the owner's blast_radius at drop time, deliberately: picking up
## a Bigger Blast later must not retroactively enlarge a fuse-burning bomb.
var radius: int = 1
## Set the tick it goes off. Exploded bombs are reaped at the end of the bomb
## phase rather than removed mid-chain, so indices stay stable while a chain
## is still walking the array.
var exploded: bool = false

## Placed by a Remote holder: it has no fuse and waits for the button. `fuse_ticks`
## is left alone rather than sentinelled, so losing Remote can simply clear this
## flag and the bomb arms itself with whatever fuse it is given (M3 brief §4.3).
var remote: bool = false

## A kicked bomb in motion. ZERO when still. The bomb stays **tile-quantised**
## and advances a whole tile every `kick_ticks_per_tile` ticks, because every
## rule that touches a bomb indexes it by tile; `slide_ticks` counts down to the
## next step and is what the view would interpolate from (M3 brief §4.1).
var slide_dir: Vector2i = Vector2i.ZERO
var slide_ticks: int = 0

func _init(p_tile: Vector2i = Vector2i.ZERO, p_owner: int = -1, p_fuse: int = 0, p_radius: int = 1) -> void:
	tile = p_tile
	owner = p_owner
	fuse_ticks = p_fuse
	radius = p_radius

func is_sliding() -> bool:
	return slide_dir != Vector2i.ZERO

func stop_sliding() -> void:
	slide_dir = Vector2i.ZERO
	slide_ticks = 0

func mix_into(h: int) -> int:
	var acc: int = SimHash.mix_vec(h, tile)
	acc = SimHash.mix_int(acc, owner)
	acc = SimHash.mix_int(acc, fuse_ticks)
	acc = SimHash.mix_int(acc, radius)
	acc = SimHash.mix_bool(acc, exploded)
	acc = SimHash.mix_bool(acc, remote)
	acc = SimHash.mix_vec(acc, slide_dir)
	acc = SimHash.mix_int(acc, slide_ticks)
	return acc
