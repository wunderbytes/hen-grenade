extends TestCase
## Blast geometry: the plus shape, radius, hard blocks, exactly one crate per
## direction, and flame lifetime. See docs/milestone-1-brief.md §6.2.

var state: MatchState

func before_each() -> void:
	var b: Balance = SimFixture.balance()
	b.bomb_fuse_ticks = 1
	state = SimFixture.open_state(b, 1)
	# Park the only player out of the way: these are tests about geometry.
	SimFixture.place(state, 0, Vector2i(1, 1))

## Detonates a bomb at `tile` with `radius` on the next tick and returns events.
func _blow(tile: Vector2i, radius: int, owner: int = 0) -> Array[SimEvent]:
	SimFixture.add_bomb(state, tile, owner, 1, radius)
	return SimFixture.run_idle(state, 2)

func test_radius_one_is_a_plus_of_five_tiles() -> void:
	var events: Array[SimEvent] = _blow(Vector2i(5, 5), 1)
	var expected: Array[String] = SimFixture.tile_keys([
		Vector2i(5, 5), Vector2i(5, 4), Vector2i(6, 5), Vector2i(5, 6), Vector2i(4, 5),
	])
	assert_eq(SimFixture.lit_tiles(events), expected, "radius 1 blast is not a five-tile plus")

func test_radius_three_reaches_three_tiles_each_way() -> void:
	var events: Array[SimEvent] = _blow(Vector2i(8, 7), 3)
	var tiles: Array[Vector2i] = [Vector2i(8, 7)]
	for step in range(1, 4):
		tiles.append(Vector2i(8, 7 - step))
		tiles.append(Vector2i(8 + step, 7))
		tiles.append(Vector2i(8, 7 + step))
		tiles.append(Vector2i(8 - step, 7))
	assert_eq(SimFixture.lit_tiles(events), SimFixture.tile_keys(tiles), "radius 3 blast has the wrong reach")

func test_blast_never_leaves_a_flame_on_a_hard_block() -> void:
	state.arena.set_at(Vector2i(7, 5), Arena.Tile.HARD)
	var events: Array[SimEvent] = _blow(Vector2i(5, 5), 4)
	var lit: Array[String] = SimFixture.lit_tiles(events)
	assert_true(lit.has("6,5"), "the ray should reach the tile before the block")
	assert_false(lit.has("7,5"), "a flame was placed on the hard block itself")
	assert_false(lit.has("8,5"), "the ray passed through a hard block")

func test_border_wall_stops_the_ray() -> void:
	var events: Array[SimEvent] = _blow(Vector2i(1, 1), 5)
	var lit: Array[String] = SimFixture.lit_tiles(events)
	assert_false(lit.has("0,1"), "a flame was placed on the border")
	assert_false(lit.has("1,0"), "a flame was placed on the border")
	assert_true(lit.has("2,1"), "the ray should still travel inward")

func test_destroys_exactly_one_crate_per_direction() -> void:
	state.arena.set_at(Vector2i(6, 5), Arena.Tile.CRATE)
	state.arena.set_at(Vector2i(7, 5), Arena.Tile.CRATE)
	var events: Array[SimEvent] = _blow(Vector2i(5, 5), 4)

	assert_eq(state.arena.at(Vector2i(6, 5)), Arena.Tile.FLOOR, "the first crate survived")
	assert_eq(state.arena.at(Vector2i(7, 5)), Arena.Tile.CRATE, "the second crate was destroyed too")
	var destroyed: Array[SimEvent] = SimFixture.events_of(events, SimEvent.Kind.CRATE_DESTROYED)
	assert_eq(destroyed.size(), 1, "wrong number of CRATE_DESTROYED events")
	assert_eq(destroyed[0].tile, Vector2i(6, 5), "wrong crate reported")

func test_a_destroyed_crate_tile_catches_fire() -> void:
	state.arena.set_at(Vector2i(6, 5), Arena.Tile.CRATE)
	var events: Array[SimEvent] = _blow(Vector2i(5, 5), 2)
	assert_true(SimFixture.lit_tiles(events).has("6,5"), "the destroyed crate's tile has no flame")
	assert_false(SimFixture.lit_tiles(events).has("7,5"), "the ray continued past the crate")

func test_crates_are_destroyed_in_all_four_directions() -> void:
	for d in Sim.DIRS:
		state.arena.set_at(Vector2i(8, 7) + d, Arena.Tile.CRATE)
	var events: Array[SimEvent] = _blow(Vector2i(8, 7), 3)
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.CRATE_DESTROYED), 4, "not every direction broke its crate")
	for d in Sim.DIRS:
		assert_eq(state.arena.at(Vector2i(8, 7) + d), Arena.Tile.FLOOR, "crate at %s survived" % [Vector2i(8, 7) + d])

func test_flame_lasts_exactly_its_tick_count() -> void:
	var b: Balance = SimFixture.balance()
	b.bomb_fuse_ticks = 1
	b.flame_ticks = 10
	state = SimFixture.open_state(b, 1)
	SimFixture.place(state, 0, Vector2i(1, 1))
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 1)

	# The bomb goes off on tick 2, so the flame is lit on tick 2 and must burn
	# through tick 11, leaving the board on tick 12.
	SimFixture.run_idle(state, 2)
	assert_eq(state.flame_ttl_at(Vector2i(5, 5)), 10, "flame did not start with its full lifetime")
	SimFixture.run_idle(state, 9)
	assert_eq(state.tick, 11, "test drove the wrong number of ticks")
	assert_gt(state.flame_ttl_at(Vector2i(5, 5)), 0, "flame went out early")
	SimFixture.run_idle(state, 1)
	assert_eq(state.flame_ttl_at(Vector2i(5, 5)), 0, "flame outstayed its lifetime")
	assert_eq(state.flame_owner_at(Vector2i(5, 5)), -1, "flame owner was not cleared")

func test_overlapping_blasts_refresh_the_flame_and_transfer_ownership() -> void:
	# The most recent blast owns the tile: the fire you just made is yours.
	var b: Balance = SimFixture.balance()
	b.bomb_fuse_ticks = 1
	b.flame_ticks = 20
	state = SimFixture.open_state(b, 2)
	SimFixture.place(state, 0, Vector2i(1, 1))
	SimFixture.place(state, 1, Vector2i(1, 3))

	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 1)
	SimFixture.run_idle(state, 2)
	assert_eq(state.flame_owner_at(Vector2i(6, 5)), 0, "first blast should own the tile")
	SimFixture.run_idle(state, 5)
	assert_eq(state.flame_ttl_at(Vector2i(6, 5)), 15, "flame should have aged five ticks")

	SimFixture.add_bomb(state, Vector2i(7, 5), 1, 1, 1)
	SimFixture.run_idle(state, 2)
	assert_eq(state.flame_owner_at(Vector2i(6, 5)), 1, "the newer blast did not take ownership")
	assert_eq(state.flame_ttl_at(Vector2i(6, 5)), 20, "the lifetime was not refreshed")

func test_flame_lit_events_fire_once_per_lighting() -> void:
	var b: Balance = SimFixture.balance()
	b.bomb_fuse_ticks = 1
	b.flame_ticks = 20
	state = SimFixture.open_state(b, 1)
	SimFixture.place(state, 0, Vector2i(1, 1))
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 1, 1)
	var first: Array[SimEvent] = SimFixture.run_idle(state, 2)
	assert_eq(SimFixture.count_of(first, SimEvent.Kind.FLAME_LIT), 5, "wrong number of FLAME_LIT events")

	# A second blast overlapping a still-burning tile refreshes it but must not
	# re-announce it, or the view would restart the animation mid-burn.
	SimFixture.add_bomb(state, Vector2i(6, 5), 0, 1, 1)
	var second: Array[SimEvent] = SimFixture.run_idle(state, 2)
	var lit: Array[String] = SimFixture.lit_tiles(second)
	assert_false(lit.has("5,5"), "re-announced a tile that was already on fire")
	assert_false(lit.has("6,5"), "re-announced a tile that was already on fire")
	assert_true(lit.has("7,5"), "the new blast's fresh tiles were not announced")
