class_name Egg
## One egg the Hen has laid. An obstacle for everyone except the Hen. A blast
## removes it and leaves a slippery tile; if it is left alone it hatches into a
## Chicken and keeps its slot in the brood until that chicken is blown up.

var tile: Vector2i = Vector2i.ZERO
## Ticks left before this becomes a chicken. Aged like a bomb fuse: a value of N
## sits on the board for N ticks and hatches on the tick after that.
var hatch_ticks: int = 0

func _init(p_tile: Vector2i = Vector2i.ZERO, p_hatch: int = 0) -> void:
	tile = p_tile
	hatch_ticks = p_hatch

func mix_into(h: int) -> int:
	var acc: int = SimHash.mix_vec(h, tile)
	return SimHash.mix_int(acc, hatch_ticks)
