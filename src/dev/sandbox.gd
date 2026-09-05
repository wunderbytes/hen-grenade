extends Node2D
## M0 sandbox: the real 25x15 grid at the real resolution, four coloured squares
## driven by four real input devices. Throwaway — but the input wiring is real.
## See docs/milestone-0-brief.md §6.1.
##
## Movement here is "move a square around the grid" and nothing more: no lane
## snapping, no corner assist. Collide with walls (border + pillar lattice),
## nothing else.

const STEP_SPEED_PX: float = 100.0   # 5 tiles/s, throwaway feel
const SQUARE_HALF: int = 8           # 16x16 squares

var _grid: TileMapLayer
var _tick: int = 0
var _squares: Array[Dictionary] = []
var _legend: Label

func _ready() -> void:
	_grid = get_node("GridLayer")
	_grid.tile_set = PlaceholderTileset.build([
		Color8(40, 44, 52),    # floor  (dark)
		Color8(170, 176, 188),  # hard   (light grey)
		Color8(150, 100, 60),   # crate  (brown) — unused in sandbox layout
	])
	_grid.position = Vector2(C.ARENA_ORIGIN)
	_build_arena()
	_spawn_squares()
	_legend = Label.new()
	_legend.position = Vector2(4, 30)
	_legend.add_theme_font_size_override("font_size", 8)
	_legend.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	_legend.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_legend.add_theme_constant_override("shadow_offset_x", 1)
	_legend.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_legend)
	_add_hint()
	# Bring up the metrics overlay so we measure from the first frame.
	add_child(load("res://src/app/metrics_overlay.tscn").instantiate())

func _add_hint() -> void:
	var lbl: Label = Label.new()
	lbl.text = "SANDBOX  [F2 stress]  [F1 title]"
	lbl.position = Vector2(4, 4)
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
	add_child(lbl)

func _build_arena() -> void:
	for x in range(C.GRID_W):
		for y in range(C.GRID_H):
			var cell: Vector2i = Vector2i(x, y)
			if _is_wall(cell):
				_grid.set_cell(cell, 0, Vector2i(PlaceholderTileset.HARD, 0))
			else:
				_grid.set_cell(cell, 0, Vector2i(PlaceholderTileset.FLOOR, 0))

## Border tiles and the even/even interior pillars are walls.
func _is_wall(cell: Vector2i) -> bool:
	if cell.x == 0 or cell.x == C.GRID_W - 1 or cell.y == 0 or cell.y == C.GRID_H - 1:
		return true
	if cell.x % 2 == 0 and cell.y % 2 == 0:
		return true
	return false

func _spawn_squares() -> void:
	var corners: Array[Vector2i] = [
		Vector2i(1, 1),
		Vector2i(C.GRID_W - 2, 1),
		Vector2i(1, C.GRID_H - 2),
		Vector2i(C.GRID_W - 2, C.GRID_H - 2),
	]
	for i in range(C.MAX_PLAYERS):
		_squares.append({
			"active": false,
			"tile": corners[i],
			"visual": _tile_center(corners[i]),
		})

func _physics_process(_delta: float) -> void:
	_tick += 1
	var frames: Array[InputFrame] = DeviceManager.poll_all(_tick)
	for i in range(C.MAX_PLAYERS):
		_step_square(i, frames[i], _delta)
	_update_legend()
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F2: get_tree().change_scene_to_file("res://src/dev/stress.tscn")
			KEY_F1: get_tree().change_scene_to_file("res://src/app/main.tscn")

func _step_square(i: int, frame: InputFrame, delta: float) -> void:
	var sq: Dictionary = _squares[i]
	var occupied: bool = DeviceManager.slots[i].is_occupied()
	sq["active"] = occupied
	if not occupied:
		return
	var center: Vector2 = _tile_center(sq["tile"])
	# When settled on a tile, accept a new step in the held direction.
	if sq["visual"].distance_to(center) <= STEP_SPEED_PX * delta + 0.5:
		sq["visual"] = center
		if frame.dir != InputFrame.Dir.NONE:
			var next: Vector2i = sq["tile"] + _dir_vec(frame.dir)
			if not _is_wall(next):
				sq["tile"] = next
	# Ease the visual toward the current tile centre.
	var target: Vector2 = _tile_center(sq["tile"])
	var to_target: Vector2 = target - sq["visual"]
	var step: float = STEP_SPEED_PX * delta
	if to_target.length() <= step:
		sq["visual"] = target
	else:
		sq["visual"] += to_target.normalized() * step

func _dir_vec(d: InputFrame.Dir) -> Vector2i:
	match d:
		InputFrame.Dir.UP: return Vector2i(0, -1)
		InputFrame.Dir.DOWN: return Vector2i(0, 1)
		InputFrame.Dir.LEFT: return Vector2i(-1, 0)
		InputFrame.Dir.RIGHT: return Vector2i(1, 0)
	return Vector2i.ZERO

func _tile_center(cell: Vector2i) -> Vector2:
	# Arena-local pixel coordinates (tile centre).
	return Vector2(cell.x * C.TILE_PX + C.TILE_PX / 2.0, cell.y * C.TILE_PX + C.TILE_PX / 2.0)

func _draw() -> void:
	var origin: Vector2 = C.ARENA_ORIGIN
	for i in range(C.MAX_PLAYERS):
		var sq: Dictionary = _squares[i]
		if not bool(sq["active"]):
			continue
		var p: Vector2 = origin + sq["visual"]
		var color: Color = C.PLAYER_COLORS[i]
		draw_rect(Rect2(p.x - SQUARE_HALF, p.y - SQUARE_HALF, SQUARE_HALF * 2, SQUARE_HALF * 2), color, true)
		draw_rect(Rect2(p.x - SQUARE_HALF, p.y - SQUARE_HALF, SQUARE_HALF * 2, SQUARE_HALF * 2), Color.BLACK, false, 1.0)

func _update_legend() -> void:
	var lines: PackedStringArray = PackedStringArray()
	for i in range(C.MAX_PLAYERS):
		var color_hex: String = "#%02x%02x%02x" % [int(C.PLAYER_COLORS[i].r * 255), int(C.PLAYER_COLORS[i].g * 255), int(C.PLAYER_COLORS[i].b * 255)]
		lines.append("P%d %s: %s" % [i + 1, color_hex, DeviceManager.slot_label(i)])
	_legend.text = "\n".join(lines)
