class_name Chicken
## A hatched egg. Runs at hunter base speed, retargets at each normal-floor
## tile centre, and kills hunters it shares a tile with. The Hen is immune.
## A blast removes it and does not leave ice. While it is on slippery tiles it
## keeps the direction it entered with, same rule as a player.

var pos: Vector2i = Vector2i.ZERO
## Committed step, ZERO when it has nowhere to go. Not an input; retargeting
## writes it.
var dir: Vector2i = Vector2i.ZERO

func _init(p_pos: Vector2i = Vector2i.ZERO) -> void:
	pos = p_pos

func tile() -> Vector2i:
	return Vector2i(pos.x / C.UNITS_PER_TILE, pos.y / C.UNITS_PER_TILE)

func mix_into(h: int) -> int:
	var acc: int = SimHash.mix_vec(h, pos)
	return SimHash.mix_vec(acc, dir)
