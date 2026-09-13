extends TestCase
## Kick, Toss, Remote and the four Dud variants.
## See docs/milestone-3-brief.md §4 and docs/game-design.md §6.

var state: MatchState

func before_each() -> void:
	# Drops off: an ability test must not become a test about what fell out of a
	# crate, and several of these break crates on purpose.
	state = SimFixture.open_state(SimFixture.balance(), 2, 12345, SimFixture.no_drops())

func _solo(tile: Vector2i) -> PlayerState:
	var p: PlayerState = SimFixture.place(state, 0, tile)
	SimFixture.park_others(state, 0)
	return p

# --- Kick --------------------------------------------------------------------

func test_without_kick_a_bomb_stops_you() -> void:
	var p: PlayerState = _solo(Vector2i(5, 5))
	SimFixture.add_bomb(state, Vector2i(6, 5), 1, 500, 1)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 30)
	assert_eq(p.tile(), Vector2i(5, 5), "walked through a bomb")
	assert_eq(state.bombs[0].tile, Vector2i(6, 5), "the bomb moved without Kick")

func test_kick_starts_the_bomb_sliding() -> void:
	var p: PlayerState = _solo(Vector2i(5, 5))
	p.has_kick = true
	var b: Bomb = SimFixture.add_bomb(state, Vector2i(6, 5), 1, 500, 1)
	var events: Array[SimEvent] = SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 1)

	assert_true(b.is_sliding(), "the bomb did not start sliding")
	assert_eq(b.slide_dir, Vector2i(1, 0), "slid the wrong way")
	assert_eq(b.tile, Vector2i(6, 5), "the bomb moved on the tick it was kicked")
	var kicked: SimEvent = SimFixture.first_of(events, SimEvent.Kind.BOMB_KICKED)
	assert_not_null(kicked, "no BOMB_KICKED event")
	assert_eq(kicked.to_tile, Vector2i(7, 5), "the event should name the next tile")

	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), state.balance.kick_ticks_per_tile - 1)
	assert_eq(b.tile, Vector2i(7, 5), "the bomb did not advance a tile on schedule")

func test_a_sliding_bomb_stops_at_a_hard_block() -> void:
	var p: PlayerState = _solo(Vector2i(5, 5))
	p.has_kick = true
	state.arena.set_at(Vector2i(9, 5), Arena.Tile.HARD)
	var b: Bomb = SimFixture.add_bomb(state, Vector2i(6, 5), 1, 500, 1)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 60)
	assert_eq(b.tile, Vector2i(8, 5), "the bomb did not stop against the block")
	assert_false(b.is_sliding(), "the bomb is still sliding into a wall")

func test_a_sliding_bomb_stops_at_a_crate_without_breaking_it() -> void:
	var p: PlayerState = _solo(Vector2i(5, 5))
	p.has_kick = true
	state.arena.set_at(Vector2i(8, 5), Arena.Tile.CRATE)
	var b: Bomb = SimFixture.add_bomb(state, Vector2i(6, 5), 1, 500, 1)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 60)
	assert_eq(b.tile, Vector2i(7, 5), "the bomb did not stop against the crate")
	assert_eq(state.arena.at(Vector2i(8, 5)), Arena.Tile.CRATE, "a sliding bomb should not break a crate")

func test_a_sliding_bomb_stops_at_another_bomb() -> void:
	var p: PlayerState = _solo(Vector2i(5, 5))
	p.has_kick = true
	var b: Bomb = SimFixture.add_bomb(state, Vector2i(6, 5), 1, 500, 1)
	SimFixture.add_bomb(state, Vector2i(9, 5), 1, 500, 1)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 60)
	assert_eq(b.tile, Vector2i(8, 5), "the bomb did not stop against the other bomb")

func test_kicking_into_a_wall_is_not_a_kick() -> void:
	var p: PlayerState = _solo(Vector2i(5, 5))
	p.has_kick = true
	state.arena.set_at(Vector2i(7, 5), Arena.Tile.HARD)
	var b: Bomb = SimFixture.add_bomb(state, Vector2i(6, 5), 1, 500, 1)
	var events: Array[SimEvent] = SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 10)
	assert_false(b.is_sliding(), "a bomb with nowhere to go started sliding")
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.BOMB_KICKED), 0, "a failed kick emitted an event")

func test_a_sliding_bomb_passes_under_a_player() -> void:
	# Nothing in this game collides with a player (game design §5.1), and a bomb
	# that stopped on one would need a rule about which players count.
	var p: PlayerState = _solo(Vector2i(5, 5))
	p.has_kick = true
	SimFixture.place(state, 1, Vector2i(8, 5))
	state.players[1].spawn_protect_ticks = 600      # keep them out of the death path
	var b: Bomb = SimFixture.add_bomb(state, Vector2i(6, 5), 0, 500, 1)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 3 * state.balance.kick_ticks_per_tile)
	assert_eq(b.tile, Vector2i(9, 5), "the bomb stopped on a player")

func test_a_bomb_kicked_into_fire_goes_off_and_credits_the_flame() -> void:
	var p: PlayerState = _solo(Vector2i(5, 5))
	p.has_kick = true
	SimFixture.add_flame(state, Vector2i(7, 5), 1, 600)
	SimFixture.add_bomb(state, Vector2i(6, 5), 0, 500, 1)
	var events: Array[SimEvent] = SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), state.balance.kick_ticks_per_tile)
	assert_eq(state.bombs.size(), 0, "the bomb did not detonate in the fire")
	var boom: SimEvent = SimFixture.first_of(events, SimEvent.Kind.BOMB_EXPLODED)
	assert_not_null(boom, "no BOMB_EXPLODED event")
	assert_eq(boom.player, 0, "the bomb still belongs to its owner")
	assert_eq(boom.other, 1, "the chain should be credited to the flame's owner")

func test_stepping_off_your_own_bomb_is_not_a_kick() -> void:
	var p: PlayerState = _solo(Vector2i(5, 5))
	p.has_kick = true
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	assert_eq(state.bombs.size(), 1, "setup: a bomb should have been placed")
	var b: Bomb = state.bombs[0]
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 20)
	assert_false(b.is_sliding(), "the player kicked the bomb they were standing on")
	assert_eq(b.tile, Vector2i(5, 5), "the bomb moved")

# --- Toss --------------------------------------------------------------------

## Drops a bomb and then presses B, leaving the player on the bomb's tile.
func _toss_from(tile: Vector2i, dir: InputFrame.Dir) -> Array[SimEvent]:
	var p: PlayerState = _solo(tile)
	p.ability = Powerup.Kind.TOSS
	SimFixture.run_ticks(state, SimFixture.frames_for(0, dir, true), 1)
	return SimFixture.run_ticks(state, [SimFixture.frame(dir, false, true), InputFrame.new(), InputFrame.new(), InputFrame.new()] as Array[InputFrame], 1)

func test_toss_lobs_the_bomb_two_tiles_over_a_wall() -> void:
	state.arena.set_at(Vector2i(6, 5), Arena.Tile.HARD)
	var events: Array[SimEvent] = _toss_from(Vector2i(5, 5), InputFrame.Dir.RIGHT)
	assert_eq(state.bombs.size(), 1, "the bomb vanished")
	assert_eq(state.bombs[0].tile, Vector2i(7, 5), "the bomb did not clear the wall")
	var tossed: SimEvent = SimFixture.first_of(events, SimEvent.Kind.BOMB_TOSSED)
	assert_not_null(tossed, "no BOMB_TOSSED event")
	assert_eq(tossed.tile, Vector2i(5, 5), "event origin")
	assert_eq(tossed.to_tile, Vector2i(7, 5), "event destination")

func test_a_blocked_landing_falls_back_toward_the_thrower() -> void:
	# Never forward: overshooting into the next corridor because the intended
	# tile was occupied would be genuinely unpredictable (brief §4.2).
	state.arena.set_at(Vector2i(7, 5), Arena.Tile.HARD)
	_toss_from(Vector2i(5, 5), InputFrame.Dir.RIGHT)
	assert_eq(state.bombs[0].tile, Vector2i(6, 5), "the toss did not fall back to the nearer tile")

func test_a_toss_with_nowhere_to_land_does_nothing() -> void:
	state.arena.set_at(Vector2i(6, 5), Arena.Tile.HARD)
	state.arena.set_at(Vector2i(7, 5), Arena.Tile.HARD)
	var events: Array[SimEvent] = _toss_from(Vector2i(5, 5), InputFrame.Dir.RIGHT)
	assert_eq(state.bombs[0].tile, Vector2i(5, 5), "the bomb moved with nowhere to go")
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.BOMB_TOSSED), 0, "a failed toss emitted an event")

func test_toss_with_nothing_underfoot_does_nothing() -> void:
	var p: PlayerState = _solo(Vector2i(5, 5))
	p.ability = Powerup.Kind.TOSS
	var events: Array[SimEvent] = SimFixture.run_ticks(state, [SimFixture.frame(InputFrame.Dir.RIGHT, false, true), InputFrame.new(), InputFrame.new(), InputFrame.new()] as Array[InputFrame], 5)
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.BOMB_TOSSED), 0, "tossed a bomb that did not exist")

func test_a_tossed_bomb_keeps_its_fuse_owner_and_radius() -> void:
	var p: PlayerState = _solo(Vector2i(5, 5))
	p.ability = Powerup.Kind.TOSS
	p.blast_radius = 3
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT, true), 1)
	var fuse_before: int = state.bombs[0].fuse_ticks
	SimFixture.run_ticks(state, [SimFixture.frame(InputFrame.Dir.RIGHT, false, true), InputFrame.new(), InputFrame.new(), InputFrame.new()] as Array[InputFrame], 1)
	var b: Bomb = state.bombs[0]
	assert_eq(b.tile, Vector2i(7, 5), "setup: the bomb should have been tossed")
	assert_eq(b.owner, 0, "the toss changed the owner")
	assert_eq(b.radius, 3, "the toss re-rolled the radius")
	assert_eq(b.fuse_ticks, fuse_before - 1, "the toss reset the fuse")

func test_a_held_action_button_tosses_once() -> void:
	var p: PlayerState = _solo(Vector2i(5, 5))
	p.ability = Powerup.Kind.TOSS
	p.bomb_capacity = 4
	# Bomb and action held together: place, toss, and then nothing more until the
	# button is released, exactly like the bomb button.
	var held: Array[InputFrame] = [SimFixture.frame(InputFrame.Dir.NONE, true, true), InputFrame.new(), InputFrame.new(), InputFrame.new()] as Array[InputFrame]
	var events: Array[SimEvent] = SimFixture.run_ticks(state, held, 20)
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.BOMB_TOSSED), 1, "a held button tossed more than once")

# --- Remote ------------------------------------------------------------------

func test_a_remote_bomb_never_fuses() -> void:
	var p: PlayerState = _solo(Vector2i(5, 5))
	p.ability = Powerup.Kind.REMOTE
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	assert_eq(state.bombs.size(), 1, "setup: a bomb should have been placed")
	SimFixture.run_idle(state, state.balance.bomb_fuse_ticks * 2)
	assert_eq(state.bombs.size(), 1, "a Remote bomb went off on its own")
	assert_eq(state.bombs[0].fuse_ticks, state.balance.bomb_fuse_ticks, "a Remote bomb's fuse aged")

func test_the_button_detonates_every_bomb_that_player_owns() -> void:
	var p: PlayerState = _solo(Vector2i(1, 1))
	p.ability = Powerup.Kind.REMOTE
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 500, 1)
	SimFixture.add_bomb(state, Vector2i(9, 9), 0, 500, 1)
	var theirs: Bomb = SimFixture.add_bomb(state, Vector2i(12, 3), 1, 500, 1)
	SimFixture.run_ticks(state, [SimFixture.frame(InputFrame.Dir.NONE, false, true), InputFrame.new(), InputFrame.new(), InputFrame.new()] as Array[InputFrame], 1)

	assert_eq(state.bombs.size(), 1, "the wrong number of bombs survived")
	assert_eq(state.bombs[0], theirs, "somebody else's bomb was detonated")
	assert_eq(p.bombs_active, 0, "the owner's bomb budget was not released")

func test_remote_kills_are_credited_to_the_player_who_pressed() -> void:
	var p: PlayerState = _solo(Vector2i(1, 1))
	p.ability = Powerup.Kind.REMOTE
	var victim: PlayerState = SimFixture.place(state, 1, Vector2i(5, 5))
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 500, 1)
	SimFixture.run_ticks(state, [SimFixture.frame(InputFrame.Dir.NONE, false, true), InputFrame.new(), InputFrame.new(), InputFrame.new()] as Array[InputFrame], 1)
	assert_false(victim.alive, "the victim survived a remote detonation")
	assert_eq(p.score, 1, "the presser was not credited")

func test_dying_arms_the_bombs_remote_left_behind() -> void:
	# The alternative is permanent solid blocks owned by nobody (brief §4.3).
	var p: PlayerState = _solo(Vector2i(5, 5))
	p.ability = Powerup.Kind.REMOTE
	p.bomb_capacity = 2
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	var b: Bomb = state.bombs[0]
	assert_true(b.remote, "setup: the bomb should be fuse-less")

	# Die two tiles away, so the death is not the bomb's own tile catching fire.
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 30)
	assert_eq(p.tile(), Vector2i(7, 5), "setup: the player should have walked clear")
	SimFixture.add_flame(state, Vector2i(7, 5), 1, 30)
	SimFixture.run_idle(state, 1)
	assert_false(p.alive, "setup: the player should have died")
	assert_false(b.remote, "the orphaned bomb kept waiting for a button nobody has")
	assert_eq(p.ability, Powerup.Kind.NONE, "the ability survived death")
	SimFixture.run_idle(state, state.balance.bomb_fuse_ticks + 2)
	assert_eq(state.bombs.size(), 0, "the re-armed bomb never went off")

# --- Curses ------------------------------------------------------------------

func _curse(p: PlayerState, variant: int, ticks: int = 600) -> void:
	p.curse = variant
	p.curse_ticks = ticks

func test_reversed_inverts_the_direction() -> void:
	var p: PlayerState = _solo(Vector2i(5, 5))
	_curse(p, Powerup.Curse.REVERSED)
	var before: int = p.pos.x
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 5)
	assert_lt(p.pos.x, before, "pressing right did not move the player left")
	assert_eq(p.facing, InputFrame.Dir.LEFT, "facing should follow the reversed direction")

func test_bomb_spam_drops_without_a_press() -> void:
	var p: PlayerState = _solo(Vector2i(5, 5))
	_curse(p, Powerup.Curse.BOMB_SPAM)
	SimFixture.run_idle(state, 1)
	assert_eq(state.bombs.size(), 1, "the curse did not force a bomb out")
	assert_eq(p.bombs_active, 1, "the forced bomb was not counted")

func test_tiny_blast_shrinks_new_bombs_without_touching_the_kit() -> void:
	var p: PlayerState = _solo(Vector2i(5, 5))
	p.blast_radius = 5
	_curse(p, Powerup.Curse.TINY_BLAST)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	assert_eq(state.bombs[0].radius, 1, "the curse did not shrink the blast")
	assert_eq(p.blast_radius, 5, "the curse wrote to the loadout")

func test_fast_pins_the_speed_without_touching_the_kit() -> void:
	var p: PlayerState = _solo(Vector2i(5, 5))
	_curse(p, Powerup.Curse.FAST)
	var before: int = p.pos.x
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 1)
	assert_eq(p.pos.x - before, state.balance.max_speed_units, "the curse did not pin the speed to the cap")
	assert_eq(p.speed_units, state.balance.move_speed_units, "the curse wrote to the loadout")

func test_a_curse_expires_on_the_exact_tick() -> void:
	# Appendix A.14: off-by-one is the default outcome for tick counters, so this
	# asserts the tick rather than "eventually".
	var p: PlayerState = _solo(Vector2i(5, 5))
	_curse(p, Powerup.Curse.REVERSED, 5)
	SimFixture.run_idle(state, 4)
	assert_true(p.has_curse(), "the curse ended early")
	var events: Array[SimEvent] = SimFixture.run_idle(state, 1)
	assert_false(p.has_curse(), "the curse outlived its counter")
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.CURSE_EXPIRED), 1, "no CURSE_EXPIRED event")

func test_a_second_dud_replaces_the_first() -> void:
	var p: PlayerState = _solo(Vector2i(5, 5))
	_curse(p, Powerup.Curse.REVERSED, 5)
	SimFixture.add_pickup(state, Vector2i(5, 5), Powerup.Kind.DUD, Powerup.Curse.FAST)
	SimFixture.run_idle(state, 1)
	assert_eq(p.curse, Powerup.Curse.FAST, "the new curse did not replace the old one")
	assert_eq(p.curse_ticks, state.balance.curse_ticks - 1, "the clock was not refreshed")

func test_death_clears_a_curse() -> void:
	# Death already costs half your kit; carrying an 8-second curse through a
	# respawn on top of that compounds two punishments (brief §1).
	var p: PlayerState = _solo(Vector2i(5, 5))
	_curse(p, Powerup.Curse.FAST)
	SimFixture.add_flame(state, Vector2i(5, 5), 1, 30)
	SimFixture.run_idle(state, 1)
	assert_false(p.alive, "setup: the player should have died")
	assert_false(p.has_curse(), "the curse survived death")
	assert_eq(p.curse_ticks, 0, "the curse clock survived death")

func test_a_dud_pickup_applies_its_carried_variant() -> void:
	var p: PlayerState = _solo(Vector2i(5, 5))
	SimFixture.add_pickup(state, Vector2i(5, 5), Powerup.Kind.DUD, Powerup.Curse.BOMB_SPAM)
	var events: Array[SimEvent] = SimFixture.run_idle(state, 1)
	assert_eq(p.curse, Powerup.Curse.BOMB_SPAM, "the pickup's variant was not applied")
	var applied: SimEvent = SimFixture.first_of(events, SimEvent.Kind.CURSE_APPLIED)
	assert_not_null(applied, "no CURSE_APPLIED event")
	assert_eq(applied.value, Powerup.Curse.BOMB_SPAM, "the event should name the variant")
