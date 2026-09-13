extends TestCase
## Kit loss on death and the scatter around the body.
## See docs/milestone-3-brief.md §4.5 and docs/game-design.md §6.1.
##
## Every test here kills a player by lighting a flame under them rather than by
## staging a bomb, because what is being tested is what death costs, not what
## caused it.

var state: MatchState

func before_each() -> void:
	var b: Balance = SimFixture.balance()
	b.respawn_ticks = 500          # keep the dead dead, so the kit stays lost
	state = SimFixture.open_state(b, 2, 12345, SimFixture.no_drops())

## Kills slot 0 where it stands, with slot 1 credited, and returns the events.
func _kill(p: PlayerState) -> Array[SimEvent]:
	SimFixture.add_flame(state, p.tile(), 1, 30)
	var events: Array[SimEvent] = SimFixture.run_idle(state, 1)
	assert_false(p.alive, "setup: the player should have died")
	return events

func _victim(tile: Vector2i) -> PlayerState:
	var p: PlayerState = SimFixture.place(state, 0, tile)
	SimFixture.park_others(state, 0)
	return p

# --- Halving ------------------------------------------------------------------

func test_stacking_upgrades_are_halved_rounding_down() -> void:
	var p: PlayerState = _victim(Vector2i(5, 5))
	p.bomb_capacity = 6           # 5 above the start: keeps 2, loses 3
	p.blast_radius = 4            # 3 above the start: keeps 1, loses 2
	p.speed_steps = 3             # keeps 1, loses 2
	p.speed_units = state.balance.move_speed_units + 3 * state.balance.speed_step_units
	_kill(p)

	assert_eq(p.bomb_capacity, state.balance.start_bomb_capacity + 2, "bombs were not halved")
	assert_eq(p.blast_radius, state.balance.start_blast_radius + 1, "blast was not halved")
	assert_eq(p.speed_steps, 1, "speed steps were not halved")
	assert_eq(p.speed_units, state.balance.move_speed_units + state.balance.speed_step_units, "speed did not follow its steps")

func test_halving_is_measured_from_the_starting_loadout() -> void:
	# Halving the absolute value would take a player's base bomb away and leave
	# them unable to play.
	var p: PlayerState = _victim(Vector2i(5, 5))
	p.bomb_capacity = 2           # exactly one above the start
	p.blast_radius = 1            # nothing above the start
	_kill(p)
	assert_eq(p.bomb_capacity, state.balance.start_bomb_capacity, "one extra bomb should be lost whole")
	assert_eq(p.blast_radius, state.balance.start_blast_radius, "the base blast was taken")
	assert_ge(p.bomb_capacity, 1, "a player was left unable to drop a bomb")

func test_the_starting_loadout_scatters_nothing() -> void:
	var p: PlayerState = _victim(Vector2i(5, 5))
	_kill(p)
	assert_eq(state.pickup_count(), 0, "a player with nothing to lose dropped something")

func test_the_kit_loss_fraction_is_one_number() -> void:
	# game design §6.1 calls this the most important balance dial in the game, so
	# it had better be a single field that actually works.
	var b: Balance = SimFixture.balance()
	b.respawn_ticks = 500
	b.kit_loss_permille = 1000            # lose everything
	state = SimFixture.open_state(b, 2, 12345, SimFixture.no_drops())
	var p: PlayerState = _victim(Vector2i(5, 5))
	p.bomb_capacity = 5
	_kill(p)
	assert_eq(p.bomb_capacity, b.start_bomb_capacity, "a 1000 permille loss kept upgrades")

	b.kit_loss_permille = 0               # lose nothing
	state = SimFixture.open_state(b, 2, 12345, SimFixture.no_drops())
	var q: PlayerState = _victim(Vector2i(5, 5))
	q.bomb_capacity = 5
	_kill(q)
	assert_eq(q.bomb_capacity, 5, "a 0 permille loss still took upgrades")
	assert_eq(state.pickup_count(), 0, "a 0 permille loss still scattered pickups")

# --- Abilities ----------------------------------------------------------------

func test_abilities_are_lost_whole() -> void:
	var p: PlayerState = _victim(Vector2i(5, 5))
	p.has_kick = true
	p.ability = Powerup.Kind.TOSS
	_kill(p)
	assert_false(p.has_kick, "Kick survived death")
	assert_eq(p.ability, Powerup.Kind.NONE, "the ability slot survived death")
	var kinds: Array[int] = SimFixture.pickup_kinds(state)
	assert_true(kinds.has(Powerup.Kind.KICK), "Kick did not scatter")
	assert_true(kinds.has(Powerup.Kind.TOSS), "Toss did not scatter")

func test_a_curse_is_cleared_and_scatters_nothing() -> void:
	# Dropping a Dud where you died would be a gift to whoever killed you, in
	# the shape of a trap.
	var p: PlayerState = _victim(Vector2i(5, 5))
	p.curse = Powerup.Curse.REVERSED
	p.curse_ticks = 300
	_kill(p)
	assert_false(p.has_curse(), "the curse survived death")
	assert_eq(state.pickup_count(), 0, "the curse was scattered as a pickup")

# --- The scatter --------------------------------------------------------------

func test_everything_lost_scatters_as_pickups() -> void:
	var p: PlayerState = _victim(Vector2i(5, 5))
	p.bomb_capacity = 3          # loses 1
	p.blast_radius = 3           # loses 1
	p.speed_steps = 1            # loses 1
	p.has_kick = true            # loses 1
	var events: Array[SimEvent] = _kill(p)

	assert_eq(state.pickup_count(), 4, "the wrong number of pickups was scattered")
	assert_eq(SimFixture.pickup_kinds(state), [
		Powerup.Kind.BOMB, Powerup.Kind.BLAST, Powerup.Kind.SPEED, Powerup.Kind.KICK
	] as Array[int], "the wrong things were scattered")
	# Every one of them is announced, and the event names who lost it.
	var spawned: Array[SimEvent] = SimFixture.events_of(events, SimEvent.Kind.PICKUP_SPAWNED)
	assert_eq(spawned.size(), 4, "the scatter was not announced")
	for e in spawned:
		assert_eq(e.player, 0, "the event should name who lost the item")

func test_nothing_scatters_onto_a_flame() -> void:
	# The death tile is on fire by definition, and scattering into the blast that
	# just killed you would evaporate the whole kit before anyone saw it.
	var p: PlayerState = _victim(Vector2i(5, 5))
	p.bomb_capacity = 3
	_kill(p)
	for t in SimFixture.pickup_tiles(state):
		assert_eq(state.flame_ttl_at(t), 0, "a pickup was scattered into fire at %s" % str(t))
	assert_eq(state.pickup_count(), 1, "the item should still have been placed, just not in the fire")

func test_the_scatter_lands_nearest_first() -> void:
	var p: PlayerState = _victim(Vector2i(5, 5))
	p.bomb_capacity = 3
	_kill(p)
	var tiles: Array[Vector2i] = SimFixture.pickup_tiles(state)
	assert_eq(tiles.size(), 1, "setup: exactly one item should have scattered")
	var d: int = absi(tiles[0].x - 5) + absi(tiles[0].y - 5)
	assert_eq(d, 1, "the item did not land on the nearest free ring")

func test_an_item_with_nowhere_to_land_is_lost() -> void:
	# The only candidate inside a zero radius is the death tile, which is on
	# fire. The upgrade is simply gone, which beats placing it inside a wall.
	var b: Balance = SimFixture.balance()
	b.respawn_ticks = 500
	b.scatter_radius = 0
	state = SimFixture.open_state(b, 2, 12345, SimFixture.no_drops())
	var p: PlayerState = _victim(Vector2i(5, 5))
	p.bomb_capacity = 3
	_kill(p)
	assert_eq(state.pickup_count(), 0, "a pickup was placed with nowhere to place it")
	assert_eq(p.bomb_capacity, 2, "the upgrade should still have been taken off the player")

func test_no_pickup_ever_lands_on_a_solid_tile() -> void:
	var p: PlayerState = _victim(Vector2i(5, 5))
	p.bomb_capacity = 8
	p.blast_radius = 8
	p.speed_steps = 4
	p.has_kick = true
	# A wall of crates and blocks right where the scatter wants to go.
	for d in Sim.DIRS:
		state.arena.set_at(Vector2i(5, 5) + d, Arena.Tile.HARD)
		state.arena.set_at(Vector2i(5, 5) + d * 2, Arena.Tile.CRATE)
	_kill(p)
	assert_gt(state.pickup_count(), 0, "setup: some of the kit should have landed somewhere")
	for t in SimFixture.pickup_tiles(state):
		assert_eq(state.arena.at(t), Arena.Tile.FLOOR, "a pickup landed on a solid tile at %s" % str(t))

func test_the_scatter_consumes_no_random_draws() -> void:
	# Brief §2, Rule B: a round's PRNG sequence must not depend on how many
	# people died in it.
	var p: PlayerState = _victim(Vector2i(5, 5))
	p.bomb_capacity = 8
	p.blast_radius = 8
	p.speed_steps = 4
	p.has_kick = true
	p.ability = Powerup.Kind.REMOTE
	var before: int = state.rng.state
	_kill(p)
	assert_gt(state.pickup_count(), 5, "setup: this should have scattered a pile")
	assert_eq(state.rng.state, before, "the scatter consumed a PRNG draw")

func test_a_scattered_pickup_can_be_picked_back_up() -> void:
	# The whole point of §6.1: the spot where someone died is a contested pile.
	var b: Balance = SimFixture.balance()
	b.respawn_ticks = 500
	state = SimFixture.open_state(b, 2, 12345, SimFixture.no_drops())
	var victim: PlayerState = _victim(Vector2i(5, 5))
	victim.bomb_capacity = 3
	_kill(victim)
	var tiles: Array[Vector2i] = SimFixture.pickup_tiles(state)
	assert_eq(tiles.size(), 1, "setup: one item should be on the floor")

	var thief: PlayerState = state.players[1]
	thief.pos = Sim.tile_centre(tiles[0])
	thief.spawn_protect_ticks = 600      # the tile next door is still on fire
	SimFixture.run_idle(state, 1)
	assert_eq(thief.bomb_capacity, 2, "the scattered bomb was not collected")
	assert_eq(state.pickup_count(), 0, "the pile is still there")
