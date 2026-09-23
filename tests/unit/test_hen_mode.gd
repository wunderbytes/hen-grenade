extends TestCase
## Hen Grenade rules. See docs/milestone-3.5-brief.md §7.

var state: MatchState
var mode: GameMode

func before_each() -> void:
	mode = GameMode.hen()
	state = SimFixture.open_state(SimFixture.balance(), 2, 12345, SimFixture.no_drops(), mode)

func _hen_state(player_count: int = 2, p_seed: int = 12345) -> MatchState:
	return SimFixture.open_state(SimFixture.balance(), player_count, p_seed, SimFixture.no_drops(), GameMode.hen())

func _claim(slot: int = 0) -> PlayerState:
	var t: Vector2i = state.hen_token_tile
	assert_true(t.x >= 0, "setup: no token on the floor")
	var p: PlayerState = SimFixture.place(state, slot, t)
	SimFixture.run_idle(state, 1)
	return p

# --- Create / Rule C ----------------------------------------------------------

func test_deathmatch_create_does_not_place_a_token_or_spend_an_extra_draw() -> void:
	var def: ArenaDef = SimFixture.arena_def(700)
	var seed_value: int = 5150
	var probe: SimRng = SimRng.new(seed_value)
	Arena.generate(def, probe, def.crate_permille)
	var dm: MatchState = MatchState.create(
		SimFixture.balance(), def, seed_value, [true, true, false, false], SimFixture.no_drops(), GameMode.deathmatch()
	)
	assert_eq(dm.hen_slot, -1, "deathmatch started with a Hen")
	assert_eq(dm.hen_token_tile, Vector2i(-1, -1), "deathmatch placed a token")
	assert_eq(dm.players[0].hen_ticks, 0, "deathmatch hen_ticks")
	assert_eq(dm.rng.state, probe.state, "deathmatch create() spent an extra draw")

func test_hen_create_places_one_token_with_exactly_one_extra_draw() -> void:
	var def: ArenaDef = SimFixture.arena_def(700)
	var seed_value: int = 5150
	var hen_mode: GameMode = GameMode.hen()
	var probe: SimRng = SimRng.new(seed_value)
	Arena.generate(def, probe, hen_mode.effective_crate_permille(def))
	probe.next_index(8)
	var hen: MatchState = MatchState.create(
		SimFixture.balance(), def, seed_value, [true, true, false, false], SimFixture.no_drops(), hen_mode
	)
	assert_eq(hen.rng.state, probe.state, "hen create() must spend exactly one extra next_index")
	assert_eq(hen.hen_slot, -1, "someone started as the Hen")
	assert_true(hen.has_hen_token_on_floor(), "no token")
	var t: Vector2i = hen.hen_token_tile
	assert_eq(hen.arena.at(t), Arena.Tile.FLOOR, "token on a non-floor")
	assert_false(hen.arena.is_lattice_pillar(t), "token on a pillar")
	for p in hen.players:
		if p.active and p.alive:
			assert_ne(p.tile(), t, "token under player %d" % p.index)

func test_hen_and_token_are_mutually_exclusive() -> void:
	assert_eq(state.hen_slot, -1, "held at start")
	assert_true(state.has_hen_token_on_floor(), "token missing at start")
	_claim(0)
	assert_eq(state.hen_slot, 0, "not held after collect")
	assert_false(state.has_hen_token_on_floor(), "token still on the floor")

# --- Collection ---------------------------------------------------------------

func test_walking_onto_the_token_becomes_the_hen() -> void:
	var t: Vector2i = state.hen_token_tile
	var events: Array[SimEvent] = []
	SimFixture.place(state, 0, t)
	events = SimFixture.run_idle(state, 1)
	assert_eq(state.hen_slot, 0, "did not become the Hen")
	assert_eq(state.hen_token_tile, Vector2i(-1, -1), "token did not leave the floor")
	var collected: SimEvent = SimFixture.first_of(events, SimEvent.Kind.HEN_COLLECTED)
	assert_not_null(collected, "no HEN_COLLECTED")
	assert_eq(collected.player, 0, "wrong collector")
	assert_eq(collected.tile, t, "event tile")

func test_lower_slot_wins_a_same_tick_collect() -> void:
	var t: Vector2i = state.hen_token_tile
	SimFixture.place(state, 0, t)
	SimFixture.place(state, 1, t)
	var events: Array[SimEvent] = SimFixture.run_idle(state, 1)
	assert_eq(state.hen_slot, 0, "higher slot won the tie")
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.HEN_COLLECTED), 1, "collected twice")

func test_collect_does_not_clear_kit() -> void:
	var p: PlayerState = state.players[0]
	p.bomb_capacity = 4
	p.has_kick = true
	_claim(0)
	assert_eq(p.bomb_capacity, 4, "kit bombs cleared")
	assert_true(p.has_kick, "kick cleared")

# --- Constraints --------------------------------------------------------------

func test_the_hen_cannot_place_a_bomb_and_a_hunter_can() -> void:
	_claim(0)
	var events: Array[SimEvent] = SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.BOMB_PLACED), 0, "the Hen placed a bomb")
	SimFixture.place(state, 1, Vector2i(8, 5))
	events = SimFixture.run_ticks(state, SimFixture.frames_for(1, InputFrame.Dir.NONE, true), 1)
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.BOMB_PLACED), 1, "a hunter could not place a bomb")

func test_bomb_spam_as_hen_still_fails() -> void:
	var p: PlayerState = _claim(0)
	p.curse = Powerup.Curse.BOMB_SPAM
	p.curse_ticks = 60
	var events: Array[SimEvent] = SimFixture.run_idle(state, 3)
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.BOMB_PLACED), 0, "BOMB_SPAM as Hen placed a bomb")

func test_the_hen_cannot_toss_or_remote_but_can_kick() -> void:
	var p: PlayerState = SimFixture.place(state, 0, Vector2i(5, 5))
	state.hen_token_tile = Vector2i(5, 5)
	p.ability = Powerup.Kind.TOSS
	p.has_kick = true
	SimFixture.add_bomb(state, Vector2i(5, 5), 0, 500, 1)
	p.bomb_exempt_tile = Vector2i(5, 5)
	SimFixture.run_idle(state, 1)
	assert_eq(state.hen_slot, 0, "setup: not the Hen")
	var frames: Array[InputFrame] = SimFixture.blank_frames()
	frames[0] = SimFixture.frame(InputFrame.Dir.NONE, false, true)
	var events: Array[SimEvent] = SimFixture.run_ticks(state, frames, 1)
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.BOMB_TOSSED), 0, "the Hen tossed")

	state = _hen_state()
	p = SimFixture.place(state, 0, Vector2i(5, 5))
	state.hen_token_tile = Vector2i(5, 5)
	p.has_kick = true
	SimFixture.add_bomb(state, Vector2i(6, 5), 1, 500, 1)
	SimFixture.run_idle(state, 1)
	events = SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 1)
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.BOMB_KICKED), 1, "the Hen could not kick")

func test_hen_speed_is_an_override_and_does_not_write_the_kit() -> void:
	var p: PlayerState = _claim(0)
	SimFixture.place(state, 0, Vector2i(5, 5))
	var start: Vector2i = p.pos
	var kit_speed: int = p.speed_units
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 60)
	assert_eq(p.speed_units, kit_speed, "hen speed wrote speed_units")
	assert_eq(p.pos.x - start.x, mode.hen_speed_units * 60, "distance was not hen_speed_units")

func test_fast_curse_does_not_outrun_the_hen_override() -> void:
	var p: PlayerState = _claim(0)
	SimFixture.place(state, 0, Vector2i(5, 5))
	p.curse = Powerup.Curse.FAST
	p.curse_ticks = 600
	var start: Vector2i = p.pos
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 30)
	assert_eq(p.pos.x - start.x, mode.hen_speed_units * 30, "FAST made the Hen fast")

# --- Death / drop / blast -----------------------------------------------------

func test_death_drops_the_token_and_kit_loss_still_runs() -> void:
	var p: PlayerState = _claim(0)
	p.bomb_capacity = 4
	var died_at: Vector2i = p.tile()
	SimFixture.add_flame(state, died_at, 1, 24)
	var rng_before: int = state.rng.state
	var events: Array[SimEvent] = SimFixture.run_idle(state, 1)
	assert_eq(state.hen_slot, -1, "still the Hen after death")
	assert_true(state.has_hen_token_on_floor(), "token was not dropped")
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.HEN_DROPPED), 1, "no HEN_DROPPED")
	assert_eq(p.bomb_capacity, 2, "kit loss did not run")
	assert_eq(state.rng.state, rng_before, "dropping the token spent a draw")
	assert_false(p.alive, "setup: still alive")
	SimFixture.run_idle(state, state.balance.respawn_ticks + 2)
	assert_true(p.alive, "did not respawn")

func test_token_drop_prefers_a_non_flame_floor() -> void:
	var p: PlayerState = _claim(0)
	var died_at: Vector2i = p.tile()
	SimFixture.add_flame(state, died_at, 1, 24)
	SimFixture.run_idle(state, 1)
	var t: Vector2i = state.hen_token_tile
	assert_eq(state.arena.at(t), Arena.Tile.FLOOR, "dropped on a non-floor")
	assert_eq(state.flame_ttl_at(t), 0, "dropped onto fire when a cool floor existed")
	assert_eq(state.bomb_index_at(t), -1, "dropped onto a bomb")

func test_a_blast_does_not_destroy_the_token() -> void:
	var t: Vector2i = state.hen_token_tile
	SimFixture.add_flame(state, t, 0, 24)
	SimFixture.run_idle(state, 5)
	assert_eq(state.hen_token_tile, t, "the blast ate the token")

# --- Scoring ------------------------------------------------------------------

func test_hen_ticks_count_only_while_living_hen() -> void:
	_claim(0)
	SimFixture.run_idle(state, 10)
	assert_eq(state.players[0].hen_ticks, 11, "living Hen ticks")
	SimFixture.add_flame(state, state.players[0].tile(), 1, 24)
	SimFixture.run_idle(state, 1)
	var after_death: int = state.players[0].hen_ticks
	SimFixture.run_idle(state, 20)
	assert_eq(state.players[0].hen_ticks, after_death, "ticks accrued while dead")
	assert_eq(state.players[1].hen_ticks, 0, "a hunter accrued ticks")

func test_collect_on_fire_then_die_pays_nothing() -> void:
	var t: Vector2i = state.hen_token_tile
	SimFixture.place(state, 0, t)
	SimFixture.add_flame(state, t, 1, 24)
	SimFixture.run_idle(state, 1)
	assert_eq(state.hen_slot, -1, "should have died and dropped")
	assert_eq(state.players[0].hen_ticks, 0, "collect-on-fire paid a tick")

func test_finished_rounds_do_not_keep_scoring() -> void:
	_claim(0)
	state.finished = true
	var before: int = state.players[0].hen_ticks
	SimFixture.run_idle(state, 30)
	assert_eq(state.players[0].hen_ticks, before, "a finished round kept scoring")

func test_leftover_remote_bombs_rearm_on_collect() -> void:
	var token: Vector2i = state.hen_token_tile
	var p: PlayerState = SimFixture.place(state, 0, token)
	p.ability = Powerup.Kind.REMOTE
	var b: Bomb = SimFixture.add_bomb(state, Vector2i(9, 5), 0, 150, 1)
	b.remote = true
	SimFixture.run_idle(state, 1)
	assert_eq(state.hen_slot, 0, "setup")
	assert_false(b.remote, "Remote bomb stayed fuse-less")
	assert_eq(b.fuse_ticks, state.balance.bomb_fuse_ticks - 1, "re-arm fuse")

func test_winner_uses_hen_ticks_not_kill_score() -> void:
	state.players[0].hen_ticks = 100
	state.players[1].hen_ticks = 40
	state.players[1].score = 99
	state.players[0].score = 0
	assert_eq(state.winner(), 0, "kill score decided a hen round")

func test_equal_hen_ticks_is_a_draw() -> void:
	state.players[0].hen_ticks = 50
	state.players[1].hen_ticks = 50
	state.players[0].score = 10
	assert_eq(state.winner(), -1, "a hen-ticks tie was not a draw")

# --- Arena density / regen ----------------------------------------------------

func test_crate_scale_does_not_change_draw_count_and_thins_the_board() -> void:
	var def: ArenaDef = SimFixture.arena_def(600)
	var a: SimRng = SimRng.new(99)
	var b: SimRng = SimRng.new(99)
	var thick: Arena = Arena.generate(def, a, 600)
	var thin: Arena = Arena.generate(def, b, 300)
	assert_eq(a.state, b.state, "density changed the draw count")
	assert_gt(thick.count_of(Arena.Tile.CRATE), thin.count_of(Arena.Tile.CRATE), "half density was not thinner")

func test_hen_crate_cap_and_token_tile_are_respected() -> void:
	var hen: MatchState = SimFixture.generated_state(SimFixture.balance(), 2, 7, SimFixture.no_drops(), GameMode.hen())
	assert_eq(hen.mode.crate_cap_permille, 250, "cap number leaked into code")
	assert_eq(hen.crate_cap(), hen.arena.eligible_interior_count() * 250 / 1000, "hen cap")
	if hen.has_hen_token_on_floor():
		var keys: Array[String] = SimFixture.tile_keys(Sim._regen_candidates(hen))
		assert_false(keys.has("%d,%d" % [hen.hen_token_tile.x, hen.hen_token_tile.y]), "token tile is a regen candidate")

# --- Eggs, ice, chickens ------------------------------------------------------

func test_hen_defaults_are_slower_and_hatch_in_eight_seconds() -> void:
	var shipped: GameMode = GameMode.hen()
	assert_eq(shipped.hen_speed_units, 6, "hen speed")
	assert_eq(shipped.egg_hatch_ticks, 8 * C.TICK_HZ, "hatch time")
	assert_eq(state.egg_cap, 2, "cap is the active roster")

func test_the_bomb_button_lays_an_egg_and_the_cap_is_the_roster() -> void:
	_claim(0)
	SimFixture.place(state, 0, Vector2i(5, 5))
	var laid: Array[SimEvent] = SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	assert_eq(state.eggs.size(), 1, "no egg")
	assert_eq(state.eggs[0].tile, state.players[0].tile(), "egg tile")
	assert_eq(SimFixture.count_of(laid, SimEvent.Kind.EGG_LAID), 1, "no EGG_LAID")
	assert_eq(SimFixture.count_of(laid, SimEvent.Kind.BOMB_PLACED), 0, "the Hen placed a bomb")
	# Same tile, still held: one egg, not a stack.
	SimFixture.run_idle(state, 1)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	assert_eq(state.eggs.size(), 1, "stacked an egg")
	var nest: Vector2i = state.eggs[0].tile
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 50)
	SimFixture.run_idle(state, 1)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	assert_eq(state.eggs.size(), 2, "second egg")
	assert_ne(state.eggs[1].tile, nest, "second egg did not move with her")
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 50)
	SimFixture.run_idle(state, 1)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	assert_eq(state.eggs.size(), 2, "laid past the roster cap")

func test_hunters_are_blocked_by_eggs_and_the_hen_walks_over_them() -> void:
	_claim(0)
	var nest: Vector2i = Vector2i(6, 5)
	state.eggs.append(Egg.new(nest, 480))
	SimFixture.place(state, 0, Vector2i(5, 5))
	SimFixture.place(state, 1, Vector2i(5, 7))
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.RIGHT), 40)
	assert_eq(state.players[0].tile(), nest, "the Hen could not cross her egg")
	var hunter: PlayerState = state.players[1]
	SimFixture.place(state, 1, Vector2i(5, 5))
	var held: Vector2i = hunter.pos
	SimFixture.run_ticks(state, SimFixture.frames_for(1, InputFrame.Dir.RIGHT), 40)
	assert_eq(hunter.pos, held, "a hunter walked onto an egg")
	assert_eq(hunter.tile(), Vector2i(5, 5), "hunter tile")

func test_a_blast_stops_on_an_egg_and_leaves_ice_and_a_free_slot() -> void:
	_claim(0)
	var nest: Vector2i = Vector2i(6, 5)
	state.eggs.append(Egg.new(nest, 480))
	SimFixture.place(state, 0, Vector2i(2, 2))
	SimFixture.place(state, 1, Vector2i(2, 3))
	SimFixture.add_bomb(state, Vector2i(5, 5), 1, 1, 4)
	var events: Array[SimEvent] = SimFixture.run_idle(state, 2)
	assert_eq(state.eggs.size(), 0, "egg survived the blast")
	assert_eq(state.arena.at(nest), Arena.Tile.SLIPPERY, "egg tile did not become ice")
	assert_eq(state.flame_ttl_at(nest), state.balance.flame_ticks, "no flame on the egg")
	assert_eq(state.flame_ttl_at(Vector2i(7, 5)), 0, "the ray continued past the egg")
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.EGG_BLOWN), 1, "no EGG_BLOWN")
	# The slot is free again.
	SimFixture.place(state, 0, Vector2i(4, 4))
	state.hen_slot = 0
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	assert_eq(state.eggs.size(), 1, "freed slot did not accept an egg")

func test_an_egg_hatches_after_its_timer_and_keeps_the_slot() -> void:
	mode.egg_hatch_ticks = 5
	_claim(0)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	var laid_at: int = state.tick
	SimFixture.run_idle(state, 4)
	assert_eq(state.tick, laid_at + 4, "timer tick")
	assert_eq(state.eggs.size(), 1, "hatched early")
	assert_eq(state.chickens.size(), 0, "chicken early")
	var events: Array[SimEvent] = SimFixture.run_idle(state, 1)
	assert_eq(state.eggs.size(), 0, "egg remained")
	assert_eq(state.chickens.size(), 1, "no chicken")
	assert_eq(state.brood_count(), 1, "hatching freed a slot")
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.EGG_HATCHED), 1, "no EGG_HATCHED")
	# The chicken still holds its slot. A second bird fills a two-player cap.
	state.chickens.append(Chicken.new(Sim.tile_centre(Vector2i(10, 5))))
	SimFixture.place(state, 0, Vector2i(4, 4))
	SimFixture.run_idle(state, 1)
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	assert_eq(state.eggs.size(), 0, "laid while the brood was full")

func test_chickens_kill_hunters_only_and_the_victim_respawns() -> void:
	_claim(0)
	var hunter: PlayerState = SimFixture.place(state, 1, Vector2i(8, 5))
	var hen: PlayerState = state.players[0]
	var score_before: int = hunter.score
	var hen_score: int = hen.score
	state.chickens.append(Chicken.new(Sim.tile_centre(hunter.tile())))
	state.chickens.append(Chicken.new(Sim.tile_centre(hen.tile())))
	var events: Array[SimEvent] = SimFixture.run_idle(state, 1)
	assert_false(hunter.alive, "hunter survived a chicken")
	assert_true(hen.alive, "the Hen died to her own chicken")
	assert_eq(hunter.deaths, 1, "death not counted")
	assert_eq(hunter.score, score_before, "chicken awarded a score")
	assert_eq(hen.score, hen_score, "hen score moved")
	assert_eq(hen.kills, 0, "hen was credited the kill")
	var died: SimEvent = SimFixture.first_of(events, SimEvent.Kind.PLAYER_DIED)
	assert_not_null(died, "no death event")
	assert_eq(died.other, -1, "a player was credited")
	SimFixture.run_idle(state, state.balance.respawn_ticks + 2)
	assert_true(hunter.alive, "hunter did not respawn")

func test_spawn_protection_blocks_a_chicken() -> void:
	var hunter: PlayerState = SimFixture.place(state, 1, Vector2i(8, 5))
	hunter.spawn_protect_ticks = 30
	state.chickens.append(Chicken.new(Sim.tile_centre(hunter.tile())))
	SimFixture.run_idle(state, 5)
	assert_true(hunter.alive, "spawn protection ignored a chicken")

func test_a_blast_removes_a_chicken_without_leaving_ice() -> void:
	_claim(0)
	var at: Vector2i = Vector2i(6, 5)
	state.chickens.append(Chicken.new(Sim.tile_centre(at)))
	SimFixture.place(state, 0, Vector2i(2, 2))
	SimFixture.place(state, 1, Vector2i(2, 3))
	SimFixture.add_bomb(state, Vector2i(5, 5), 1, 1, 3)
	var events: Array[SimEvent] = SimFixture.run_idle(state, 2)
	assert_eq(state.chickens.size(), 0, "chicken survived")
	assert_eq(state.arena.at(at), Arena.Tile.FLOOR, "chicken left ice")
	assert_eq(state.flame_ttl_at(Vector2i(7, 5)), 0, "the ray continued past the chicken")
	assert_eq(SimFixture.count_of(events, SimEvent.Kind.CHICKEN_BLOWN), 1, "no CHICKEN_BLOWN")
	SimFixture.place(state, 0, Vector2i(4, 4))
	state.hen_slot = 0
	SimFixture.run_ticks(state, SimFixture.frames_for(0, InputFrame.Dir.NONE, true), 1)
	assert_eq(state.eggs.size(), 1, "chicken slot did not free")

func test_ice_carries_you_to_the_next_floor_and_ignores_a_turn() -> void:
	# Hunter speed, so the slide is not the Hen override. Two ice tiles, then floor.
	var hunter: PlayerState = SimFixture.place(state, 1, Vector2i(5, 5))
	SimFixture.place(state, 0, Vector2i(2, 2))
	state.arena.set_at(Vector2i(6, 5), Arena.Tile.SLIPPERY)
	state.arena.set_at(Vector2i(7, 5), Arena.Tile.SLIPPERY)
	SimFixture.run_ticks(state, SimFixture.frames_for(1, InputFrame.Dir.RIGHT), 12)
	assert_eq(hunter.tile(), Vector2i(6, 5), "never entered the ice")
	assert_eq(hunter.ice_dir, Vector2i(1, 0), "entry direction")
	var y: int = hunter.pos.y
	var arrived: bool = false
	for _i in range(80):
		SimFixture.run_ticks(state, SimFixture.frames_for(1, InputFrame.Dir.UP), 1)
		assert_eq(hunter.pos.y, y, "turned while sliding")
		if hunter.pos == Sim.tile_centre(Vector2i(8, 5)):
			arrived = true
			break
	assert_true(arrived, "did not stop on the floor past the ice")
	assert_eq(hunter.ice_dir, Vector2i.ZERO, "slide did not end")
	var parked: Vector2i = hunter.pos
	SimFixture.run_idle(state, 10)
	assert_eq(hunter.pos, parked, "could not stop on the floor")

func test_ice_stops_on_the_slippery_tile_when_the_next_cell_is_blocked() -> void:
	var hunter: PlayerState = SimFixture.place(state, 1, Vector2i(5, 5))
	SimFixture.place(state, 0, Vector2i(2, 2))
	state.arena.set_at(Vector2i(6, 5), Arena.Tile.SLIPPERY)
	state.arena.set_at(Vector2i(7, 5), Arena.Tile.HARD)
	SimFixture.run_ticks(state, SimFixture.frames_for(1, InputFrame.Dir.RIGHT), 40)
	assert_eq(hunter.pos, Sim.tile_centre(Vector2i(6, 5)), "did not stop against the wall")
	assert_eq(hunter.ice_dir, Vector2i.ZERO, "slide stayed locked against the wall")
	SimFixture.run_ticks(state, SimFixture.frames_for(1, InputFrame.Dir.UP), 20)
	assert_eq(hunter.tile().y, 4, "could not leave once the slide had ended")

func test_a_chicken_keeps_its_direction_across_ice() -> void:
	# Only one way off the start tile, then an open side-lane on the ice that a
	# retarget would be free to take.
	state.arena.set_at(Vector2i(4, 5), Arena.Tile.HARD)
	state.arena.set_at(Vector2i(5, 4), Arena.Tile.HARD)
	state.arena.set_at(Vector2i(5, 6), Arena.Tile.HARD)
	state.arena.set_at(Vector2i(6, 5), Arena.Tile.SLIPPERY)
	state.arena.set_at(Vector2i(7, 5), Arena.Tile.SLIPPERY)
	var bird: Chicken = Chicken.new(Sim.tile_centre(Vector2i(5, 5)))
	state.chickens.append(bird)
	var left_row: bool = false
	for _i in range(80):
		SimFixture.run_idle(state, 1)
		if bird.tile().x < 8 and bird.tile().y != 5:
			left_row = true
	assert_false(left_row, "chicken turned off the ice")
	assert_true(bird.tile().x >= 8, "chicken did not cross the ice")
