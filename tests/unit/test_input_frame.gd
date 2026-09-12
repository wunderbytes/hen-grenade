extends TestCase
## Trivial M0 tests that prove the harness works and pin the InputFrame contract
## (the one piece of real logic shipped in M0). See docs/milestone-0-brief.md §9.

func test_constants_sanity() -> void:
	assert_eq(C.GRID_W, 25, "grid width")
	assert_eq(C.GRID_H, 15, "grid height")
	assert_eq(C.TILE_PX, 20, "tile px")
	assert_eq(C.ARENA_PX_W, 500, "arena px width")
	assert_eq(C.ARENA_PX_H, 300, "arena px height")
	assert_eq(C.ARENA_ORIGIN, Vector2i(70, 30), "arena origin")
	assert_eq(C.TICK_HZ, 60, "tick hz")
	assert_eq(C.UNITS_PER_TILE, 256, "units per tile")
	assert_eq(C.HALF_TILE, 128, "half tile")
	assert_eq(C.MAX_PLAYERS, 4, "max players")

func test_input_frame_default() -> void:
	var f: InputFrame = InputFrame.new()
	assert_eq(f.dir, InputFrame.Dir.NONE, "default dir")
	assert_false(f.bomb, "default bomb")
	assert_false(f.action, "default action")

func test_input_frame_pack_roundtrip() -> void:
	for d in [InputFrame.Dir.NONE, InputFrame.Dir.UP, InputFrame.Dir.RIGHT, InputFrame.Dir.DOWN, InputFrame.Dir.LEFT]:
		for bomb in [false, true]:
			for action in [false, true]:
				var f: InputFrame = InputFrame.new()
				f.dir = d
				f.bomb = bomb
				f.action = action
				var packed: int = f.pack()
				var g: InputFrame = InputFrame.unpack(packed)
				assert_eq(g.dir, d, "dir roundtrip %d" % d)
				assert_eq(g.bomb, bomb, "bomb roundtrip")
				assert_eq(g.action, action, "action roundtrip")

func test_input_frame_pack_layout() -> void:
	# bits 0-2 direction, bit 3 bomb, bit 4 action.
	var f: InputFrame = InputFrame.new()
	f.dir = InputFrame.Dir.LEFT   # 4
	f.bomb = true                  # bit 3 -> 8
	f.action = true                # bit 4 -> 16
	assert_eq(f.pack(), 4 | 8 | 16, "packed layout")
