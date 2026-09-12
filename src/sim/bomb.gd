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

func _init(p_tile: Vector2i = Vector2i.ZERO, p_owner: int = -1, p_fuse: int = 0, p_radius: int = 1) -> void:
	tile = p_tile
	owner = p_owner
	fuse_ticks = p_fuse
	radius = p_radius

func mix_into(h: int) -> int:
	var acc: int = SimHash.mix_vec(h, tile)
	acc = SimHash.mix_int(acc, owner)
	acc = SimHash.mix_int(acc, fuse_ticks)
	acc = SimHash.mix_int(acc, radius)
	acc = SimHash.mix_bool(acc, exploded)
	return acc
