extends TestCase
## Movement: fixed-point advance, lane snapping, the centre stop, the
## one-directional clamp, corner assist, and the own-bomb pass-off.
## See docs/milestone-1-brief.md §5.

var state: MatchState
var p: PlayerState

func before_each() -> void:
	state = SimFixture.open_state()
	p = SimFixture.place(state, 0, Vector2i(5, 5))
	SimFixture.park_others(state, 0)

func _centre(t: Vector2i) -> Vector2i:
	return Sim.tile_centre(t)

# --- Basic advance ----------------------------------------------------------

func test_no_direction_does_not_move() -> void:
	var before: Vector2i = p.pos
	SimFixture.run_idle(state, 30)
	assert_eq(p.pos, before, "an idle player drifted")

func test_advances_at_speed_units_per_tick() -> void:
	var before: Vector2i = p.pos
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 10)
	assert_eq(p.pos.x - before.x, 10 * p.speed_units, "did not advance exactly speed * ticks")
	assert_eq(p.pos.y, before.y, "drifted off its lane while moving horizontally")

func test_facing_follows_input_and_survives_release() -> void:
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.UP), 1)
	assert_eq(p.facing, InputFrame.Dir.UP, "facing did not follow input")
	SimFixture.run_idle(state, 5)
	assert_eq(p.facing, InputFrame.Dir.UP, "facing was reset by releasing the stick")

# --- Lane snapping ----------------------------------------------------------

func test_lane_snapping_pulls_perpendicular_to_centre() -> void:
	p.pos = Vector2i(p.pos.x, p.pos.y + 60)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 4)
	assert_eq(p.pos.y, _centre(Vector2i(5, 5)).y, "lane snapping did not converge on the lane centre")

func test_lane_snapping_does_not_overshoot() -> void:
	# Offset by less than one tick of movement: it must land exactly on the
	# centre, not oscillate around it.
	p.pos = Vector2i(p.pos.x, p.pos.y + 7)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 1)
	assert_eq(p.pos.y, _centre(Vector2i(5, 5)).y, "overshot the lane centre")

# --- Collision --------------------------------------------------------------

func test_stops_with_centre_on_the_last_free_tile() -> void:
	state.arena.set_at(Vector2i(1, 5), Arena.Tile.HARD)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.LEFT), 200)
	assert_eq(p.tile(), Vector2i(2, 5), "did not stop on the last free tile")
	assert_eq(p.pos, _centre(Vector2i(2, 5)), "did not come to rest on the tile centre")

func test_border_wall_stops_movement() -> void:
	SimFixture.place(state, 0, Vector2i(1, 5))
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.LEFT), 60)
	assert_eq(p.pos, _centre(Vector2i(1, 5)), "walked into the border wall")

func test_crates_block_movement() -> void:
	state.arena.set_at(Vector2i(7, 5), Arena.Tile.CRATE)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 200)
	assert_eq(p.pos, _centre(Vector2i(6, 5)), "a crate did not stop the player")

func test_clamp_never_pushes_backwards() -> void:
	# A player standing past the tile centre with a wall ahead must simply stop.
	# The naive "clamp to the tile centre" implementation yanks them backwards,
	# which is what corner assist exists to make unnecessary.
	state.arena.set_at(Vector2i(6, 5), Arena.Tile.HARD)
	p.pos = Vector2i(_centre(Vector2i(5, 5)).x + 100, _centre(Vector2i(5, 5)).y)
	var before: int = p.pos.x
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 30)
	assert_eq(p.pos.x, before, "the stop clamp dragged the player backwards")

# --- Corner assist ----------------------------------------------------------

func test_corner_assist_slides_into_an_open_lane() -> void:
	# Pressing UP just short of a junction, leaning right, with the way up
	# blocked here but open one tile over: the player should slide right and
	# then continue up, rather than stopping dead.
	state.arena.set_at(Vector2i(5, 4), Arena.Tile.HARD)
	p.pos = Vector2i(_centre(Vector2i(5, 5)).x + 100, _centre(Vector2i(5, 5)).y)
	var start_y: int = p.pos.y

	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.UP), 1)
	assert_eq(p.pos.x, _centre(Vector2i(5, 5)).x + 100 + p.speed_units, "did not slide toward the opening")
	assert_eq(p.pos.y, start_y, "advanced on the blocked axis while sliding")

	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.UP), 30)
	assert_eq(p.tile().x, 6, "did not end up in the adjacent lane")
	assert_lt(p.tile().y, 5, "did not get through the corner")

func test_corner_assist_declines_a_dead_end() -> void:
	# Same lean, but the adjacent lane is blocked in the direction of travel.
	# Sliding there would shove the player somewhere they never asked to go.
	state.arena.set_at(Vector2i(5, 4), Arena.Tile.HARD)
	state.arena.set_at(Vector2i(6, 4), Arena.Tile.HARD)
	p.pos = Vector2i(_centre(Vector2i(5, 5)).x + 100, _centre(Vector2i(5, 5)).y)

	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.UP), 30)
	assert_eq(p.pos.y, _centre(Vector2i(5, 5)).y, "moved up through a blocked tile")
	assert_eq(p.pos.x, _centre(Vector2i(5, 5)).x, "lane snapping should have recentred the player")

func test_corner_assist_declines_a_blocked_adjacent_lane() -> void:
	state.arena.set_at(Vector2i(5, 4), Arena.Tile.HARD)
	state.arena.set_at(Vector2i(6, 5), Arena.Tile.HARD)
	p.pos = Vector2i(_centre(Vector2i(5, 5)).x + 100, _centre(Vector2i(5, 5)).y)

	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.UP), 30)
	assert_eq(p.tile(), Vector2i(5, 5), "slid into a wall")

func test_corner_assist_needs_a_lean() -> void:
	# Dead centre in the lane with the way ahead blocked is not a corner case,
	# it is just a wall. The player stops.
	state.arena.set_at(Vector2i(5, 4), Arena.Tile.HARD)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.UP), 30)
	assert_eq(p.pos, _centre(Vector2i(5, 5)), "drifted sideways with no lean to work from")

func test_corner_assist_ignores_a_lean_that_is_too_small() -> void:
	# corner_assist_units is 77, so the trigger is |offset| >= 128 - 77 = 51.
	state.arena.set_at(Vector2i(5, 4), Arena.Tile.HARD)
	p.pos = Vector2i(_centre(Vector2i(5, 5)).x + 40, _centre(Vector2i(5, 5)).y)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.UP), 1)
	assert_lt(p.pos.x, _centre(Vector2i(5, 5)).x + 40, "a 40-unit lean should snap back, not slide out")

# --- Own-bomb pass-off ------------------------------------------------------

func test_can_step_off_own_bomb_but_not_back_on() -> void:
	# Drop a bomb, walk off it, then try to walk back: the exemption is released
	# the first tick the centre leaves the tile, so the bomb is now solid.
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	assert_eq(state.bombs.size(), 1, "no bomb was placed")
	assert_eq(p.bomb_exempt_tile, Vector2i(5, 5), "the placer did not get the pass-off exemption")

	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 10)
	assert_eq(p.tile(), Vector2i(6, 5), "did not walk off the bomb")
	assert_false(p.has_bomb_exemption(), "the exemption survived leaving the tile")

	# Now solid. The player stops where they are rather than being shoved to the
	# tile centre — the one-directional clamp never moves anyone backwards, so
	# just-stepped-off means slightly overlapping the bomb, exactly as the genre
	# looks.
	var after_stepping_off: Vector2i = p.pos
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.LEFT), 30)
	assert_eq(p.tile(), Vector2i(6, 5), "walked back onto its own bomb")
	assert_eq(p.pos, after_stepping_off, "was pushed while blocked by its own bomb")

func test_another_players_bomb_is_solid_immediately() -> void:
	SimFixture.place(state, 1, Vector2i(7, 5))
	SimFixture.add_bomb(state, Vector2i(6, 5), 1, 150, 1)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 30)
	assert_eq(p.pos, _centre(Vector2i(5, 5)), "walked into another player's bomb")

func test_shared_tile_grants_the_exemption_to_both_players() -> void:
	# Players do not collide, so two of them can be on one tile when a bomb
	# lands. "Solid to everyone except the player still standing on it" means
	# both get to walk off it.
	SimFixture.place(state, 1, Vector2i(5, 5))
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	assert_eq(state.players[0].bomb_exempt_tile, Vector2i(5, 5), "placer has no exemption")
	assert_eq(state.players[1].bomb_exempt_tile, Vector2i(5, 5), "the other player on the tile has no exemption")
