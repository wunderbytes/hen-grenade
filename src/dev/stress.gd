extends Node2D
## M0 stress scene — the deliberate, repeatable worst case that decides whether
## the Pi 400 can hold 60 FPS. Keep this scene in the repo permanently: it
## becomes the regression benchmark for every later milestone.
## See docs/milestone-0-brief.md §6.2 and §7.
##
## Composition:
##   - Full 25x15 grid, every legal interior tile a crate (worst-case tilemap draw)
##   - 4 squares on fixed scripted paths (deterministic, comparable runs)
##   - 32 additive-blended explosion sprites with alpha overdraw, 2s loop
##   - A 12-crate regeneration wave every 5s (forces tilemap redraws)
##   - 2 CPUParticles2D bursts at the intended cap
##   - A full HUD mock in the side panels, updating every frame
##
## Toggles (bisect the cost, don't read a single number):
##   V  vsync on/off          P  particles on/off
##   E  explosions on/off     H  HUD on/off
##   R  cycle output resolution 720p -> 1080p -> 4K
##   F1 sandbox scene         F2 this scene

const EXPLOSION_COUNT: int = 32
const REGEN_WAVE_SIZE: int = 12
const REGEN_PERIOD_S: float = 5.0
const PARTICLE_CAP: int = 64

var _grid: TileMapLayer
var _tick: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _interior_tiles: Array[Vector2i] = []
var _regen_timer: float = 0.0
var _regen_pending: Array[Vector2i] = []
var _regen_restore_at: float = -1.0

var _explosions: Array[Sprite2D] = []
var _explosion_tex: Texture2D
var _particles: Array[CPUParticles2D] = []
var _hud: Control
var _hud_labels: Array[Label] = []
var _squares: Array[Dictionary] = []

var _explosions_on: bool = true
var _particles_on: bool = true
var _hud_on: bool = true
var _res_index: int = 0
const _RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3840, 2160)]

func _ready() -> void:
	_rng.seed = 0xC0FFEE
	_grid = get_node("GridLayer")
	_grid.tile_set = PlaceholderTileset.build([
		Color8(40, 44, 52),    # floor
		Color8(170, 176, 188),  # hard
		Color8(150, 100, 60),   # crate
	])
	_grid.position = Vector2(C.ARENA_ORIGIN)
	_build_arena()
	_build_explosions()
	_build_particles()
	_build_hud()
	_build_squares()
	_add_hint()
	add_child(load("res://src/app/metrics_overlay.tscn").instantiate())

func _add_hint() -> void:
	var lbl: Label = Label.new()
	lbl.text = "STRESS  [V vsync][P particles][E expl][H hud][R res]"
	lbl.position = Vector2(4, 4)
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
	add_child(lbl)

# --- Arena -------------------------------------------------------------------

func _build_arena() -> void:
	for x in range(C.GRID_W):
		for y in range(C.GRID_H):
			var cell: Vector2i = Vector2i(x, y)
			if _is_wall(cell):
				_grid.set_cell(cell, 0, Vector2i(PlaceholderTileset.HARD, 0))
			else:
				_grid.set_cell(cell, 0, Vector2i(PlaceholderTileset.CRATE, 0))
				_interior_tiles.append(cell)

func _is_wall(cell: Vector2i) -> bool:
	if cell.x == 0 or cell.x == C.GRID_W - 1 or cell.y == 0 or cell.y == C.GRID_H - 1:
		return true
	if cell.x % 2 == 0 and cell.y % 2 == 0:
		return true
	return false

# --- Scripted squares (deterministic Lissajous paths) -----------------------

func _build_squares() -> void:
	for i in range(C.MAX_PLAYERS):
		_squares.append({
			"phase": i * (PI / 2.0),
			"fx": 1.0 + i * 0.13,
			"fy": 1.0 + i * 0.21,
		})

func _square_pos(i: int, t: float) -> Vector2:
	# Arena-local pixel coordinates, sweeping the whole playfield.
	var cx: float = C.ARENA_PX_W / 2.0
	var cy: float = C.ARENA_PX_H / 2.0
	var ax: float = cx - C.TILE_PX
	var ay: float = cy - C.TILE_PX
	var s: Dictionary = _squares[i]
	return Vector2(cx + ax * sin(s["fx"] * t + s["phase"]), cy + ay * sin(s["fy"] * t))

# --- Explosions (additive, overdraw) ----------------------------------------

func _build_explosions() -> void:
	_explosion_tex = _make_soft_circle(40)
	for i in range(EXPLOSION_COUNT):
		var sp: Sprite2D = Sprite2D.new()
		sp.texture = _explosion_tex
		sp.modulate = Color(1.0, 0.55, 0.15, 0.9)
		var mat: CanvasItemMaterial = CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		sp.material = mat
		# Cluster them so they overdraw heavily.
		var cluster: int = i % 4
		var base: Vector2 = Vector2(80.0 + cluster * 110.0, 60.0 + (i / 4) * 26.0)
		sp.position = Vector2(C.ARENA_ORIGIN) + base
		sp.scale = Vector2(1.5, 1.5)
		add_child(sp)
		_explosions.append(sp)

func _make_soft_circle(size: int) -> ImageTexture:
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c: float = (size - 1) / 2.0
	for x in range(size):
		for y in range(size):
			var d: float = Vector2(x - c, y - c).length() / c
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)

# --- Particles --------------------------------------------------------------

func _build_particles() -> void:
	for i in range(2):
		var cp: CPUParticles2D = CPUParticles2D.new()
		cp.position = Vector2(C.ARENA_ORIGIN) + Vector2(160.0 + i * 180.0, 150.0)
		cp.amount = PARTICLE_CAP
		cp.lifetime = 0.8
		cp.explosiveness = 1.0
		cp.one_shot = false
		cp.emitting = true
		cp.direction = Vector2(0, -1)
		cp.spread = 35.0
		cp.initial_velocity_min = 40.0
		cp.initial_velocity_max = 120.0
		cp.scale_amount_min = 2.0
		cp.scale_amount_max = 4.0
		cp.color = Color(1.0, 0.8, 0.3)
		cp.gravity = Vector2(0, 120)
		add_child(cp)
		_particles.append(cp)

# --- HUD mock ---------------------------------------------------------------

func _build_hud() -> void:
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	# Left panel: P1, P2. Right panel: P3, P4.
	for i in range(C.MAX_PLAYERS):
		var lbl: Label = Label.new()
		lbl.add_theme_font_size_override("font_size", 8)
		var left: bool = i < 2
		var col: int = 0 if left else 1
		var row: int = i % 2
		lbl.position = Vector2(4 if left else C.VIEW_W - 66, 40 + row * 90)
		lbl.vertical_alignment = 0  # Control.VERTICAL_ALIGNMENT_TOP (top)
		_hud.add_child(lbl)
		_hud_labels.append(lbl)
	# Clock label centred at top.
	var clock: Label = Label.new()
	clock.name = "Clock"
	clock.add_theme_font_size_override("font_size", 16)
	clock.position = Vector2(C.VIEW_W / 2.0 - 24, 4)
	_hud.add_child(clock)
	_hud_labels.append(clock)  # index 4

func _update_hud() -> void:
	for i in range(C.MAX_PLAYERS):
		var lbl: Label = _hud_labels[i]
		var score: int = (_tick / 13 + i * 7) % 99
		var bombs: int = 1 + (_tick / 60) % 8
		var blast: int = 1 + (_tick / 90) % 8
		var speed: int = 3 + (_tick / 120) % 4
		var respawn: int = (_tick / 60) % 2
		var color_hex: String = "#%02x%02x%02x" % [int(C.PLAYER_COLORS[i].r * 255), int(C.PLAYER_COLORS[i].g * 255), int(C.PLAYER_COLORS[i].b * 255)]
		lbl.text = "P%d\n%s\nscore %d\nbombs %d\nblast %d\nspeed %d\nresp %d" % [i + 1, color_hex, score, bombs, blast, speed, respawn]
		var clock: Label = _hud_labels[4]
		var secs: int = 120 - (_tick / 60)
		clock.text = "%d:%02d" % [secs / 60, secs % 60]

# --- Fixed-step loop --------------------------------------------------------

func _physics_process(delta: float) -> void:
	_tick += 1
	var t: float = _tick / 60.0
	_update_explosions(t)
	_update_regen(delta)
	if _hud_on:
		_update_hud()
	queue_redraw()

func _process(_delta: float) -> void:
	# Scripted squares are drawn in _draw; positions update here for smoothness.
	queue_redraw()

func _update_explosions(t: float) -> void:
	# 2-second loop: scale and alpha pulse, with heavy overdraw from overlap.
	var phase: float = fmod(t, 2.0) / 2.0
	for i in range(EXPLOSION_COUNT):
		var sp: Sprite2D = _explosions[i]
		if not _explosions_on:
			sp.visible = false
			continue
		sp.visible = true
		var s: float = 1.2 + 0.9 * sin(phase * TAU + i)
		sp.scale = Vector2(s, s)
		sp.modulate.a = 0.6 + 0.4 * sin(phase * TAU + i * 0.7)

func _update_regen(delta: float) -> void:
	_regen_timer += delta
	if _regen_timer >= REGEN_PERIOD_S:
		_regen_timer = 0.0
		# Pick REGEN_WAVE_SIZE interior tiles deterministically and clear them.
		_regen_pending.clear()
		for _i in range(REGEN_WAVE_SIZE):
			var idx: int = _rng.randi_range(0, _interior_tiles.size() - 1)
			var cell: Vector2i = _interior_tiles[idx]
			_grid.set_cell(cell, 0, Vector2i(PlaceholderTileset.FLOOR, 0))
			_regen_pending.append(cell)
		_regen_restore_at = 0.4
	if _regen_restore_at > 0.0:
		_regen_restore_at -= delta
		if _regen_restore_at <= 0.0:
			for cell in _regen_pending:
				_grid.set_cell(cell, 0, Vector2i(PlaceholderTileset.CRATE, 0))
			_regen_pending.clear()

# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	var t: float = _tick / 60.0
	for i in range(C.MAX_PLAYERS):
		var p: Vector2 = Vector2(C.ARENA_ORIGIN) + _square_pos(i, t)
		var color: Color = C.PLAYER_COLORS[i]
		draw_rect(Rect2(p.x - 8, p.y - 8, 16, 16), color, true)
		draw_rect(Rect2(p.x - 8, p.y - 8, 16, 16), Color.BLACK, false, 1.0)

# --- Toggles ----------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_V: _toggle_vsync()
			KEY_P: _toggle_particles()
			KEY_E: _toggle_explosions()
			KEY_H: _toggle_hud()
			KEY_R: _cycle_resolution()
			KEY_F1: get_tree().change_scene_to_file("res://src/dev/sandbox.tscn")
			KEY_F2: pass  # already here

func _toggle_vsync() -> void:
	var mode: int = DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED if mode != DisplayServer.VSYNC_DISABLED else DisplayServer.VSYNC_ENABLED)
	print("[stress] vsync -> ", DisplayServer.window_get_vsync_mode())

func _toggle_particles() -> void:
	_particles_on = not _particles_on
	for cp in _particles:
		cp.emitting = _particles_on
		cp.visible = _particles_on
	print("[stress] particles -> ", _particles_on)

func _toggle_explosions() -> void:
	_explosions_on = not _explosions_on
	print("[stress] explosions -> ", _explosions_on)

func _toggle_hud() -> void:
	_hud_on = not _hud_on
	_hud.visible = _hud_on
	print("[stress] hud -> ", _hud_on)

func _cycle_resolution() -> void:
	_res_index = (_res_index + 1) % _RESOLUTIONS.size()
	var res: Vector2i = _RESOLUTIONS[_res_index]
	DisplayServer.window_set_size(res)
	print("[stress] resolution -> ", res)
