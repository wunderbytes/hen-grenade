class_name MatchState
## The whole simulation state for one round. See docs/milestone-1-brief.md §4.
##
## Everything the rules read or write lives here, and nothing else does. That is
## what makes `Sim.step(state, inputs)` a pure function of its arguments, which
## in turn is what makes replays, unit tests and (later) bots possible.
##
## Constructed with MatchState.create(). No Node, no autoload, no scene tree.

## Sentinel in `flame_owner` for "no flame here". 0xFF because the array is
## bytes and slot indices are 0..3.
const NO_OWNER: int = 0xFF

var balance: Balance = null
var arena_def: ArenaDef = null
## Drop rate and weights (M3). Never null: create() substitutes the defaults, so
## no rule has to guard against a round assembled without a table.
var powerups: PowerupTable = null
var arena: Arena = null

## The single seeded PRNG. Every draw in the simulation goes through this one,
## in a fixed order (determinism contract, M1 brief §2).
var rng: SimRng = null
## The seed this round was generated from. Shown on the scoreboard and stored in
## replays, so a good layout can be played again (game design §4).
var rng_seed: int = 0

var tick: int = 0
var round_ticks_left: int = 0
## Set when the clock reaches zero. A finished round is inert: step() returns
## immediately, so a view can keep drawing the final frame without the rules
## continuing to run underneath it.
var finished: bool = false

var players: Array[PlayerState] = []
var bombs: Array[Bomb] = []

## Flames as two parallel flat grids indexed y * w + x, rather than a list of
## flame objects. No iteration order to get wrong, and no per-flame allocation
## on a tick where a big chain lights forty tiles at once.
var flame_ttl: PackedInt32Array = PackedInt32Array()
var flame_owner: PackedByteArray = PackedByteArray()

## Pickups as two more parallel flat grids, for the same reasons as flames: one
## pickup per tile falls out of the representation instead of needing a rule,
## "what is on this tile" is O(1), and a kit-loss scatter allocates nothing.
## `pickup_kind` holds a Powerup.Kind (0 == nothing); `pickup_data` holds the
## Powerup.Curse variant for a Dud and 0 for everything else.
var pickup_kind: PackedByteArray = PackedByteArray()
var pickup_data: PackedByteArray = PackedByteArray()

## Ticks until the next crate-regeneration wave. Its own counter, drawn from the
## same PRNG in a fixed order (technical design §3a).
var regen_ticks_left: int = 0

## Builds a round. `active_slots` is one bool per player slot; inactive slots
## keep their array position (so indices stay stable everywhere) but are skipped
## by every rule.
##
## `p_powerups` is optional so the sim tests and the golden replay generator can
## keep saying `create(balance, def, seed, active)`; a null table becomes the
## shipped defaults, never a round with no economy in it.
static func create(p_balance: Balance, p_arena_def: ArenaDef, p_seed: int, active_slots: Array[bool], p_powerups: PowerupTable = null) -> MatchState:
	var state: MatchState = MatchState.new()
	state.balance = p_balance
	state.arena_def = p_arena_def
	state.powerups = p_powerups if p_powerups != null else PowerupTable.new()
	state.rng_seed = p_seed
	state.rng = SimRng.new(p_seed)
	state.arena = Arena.generate(p_arena_def, state.rng)
	state.round_ticks_left = p_balance.round_ticks
	state.regen_ticks_left = p_balance.crate_regen_ticks

	var cells: int = state.arena.w * state.arena.h
	state.flame_ttl.resize(cells)
	state.flame_ttl.fill(0)
	state.flame_owner.resize(cells)
	state.flame_owner.fill(NO_OWNER)
	state.pickup_kind.resize(cells)
	state.pickup_kind.fill(Powerup.Kind.NONE)
	state.pickup_data.resize(cells)
	state.pickup_data.fill(0)

	for i in range(C.MAX_PLAYERS):
		var p: PlayerState = PlayerState.new(i)
		p.active = i < active_slots.size() and active_slots[i]
		p.speed_units = p_balance.move_speed_units
		p.speed_steps = 0
		p.bomb_capacity = p_balance.start_bomb_capacity
		p.blast_radius = p_balance.start_blast_radius
		p.ability = Powerup.Kind.NONE
		p.curse = Powerup.Curse.NONE
		if p.active:
			var spawn: Vector2i = p_arena_def.spawn_tiles[i % p_arena_def.spawn_tiles.size()]
			p.pos = Sim.tile_centre(spawn)
			p.alive = true
			# No spawn protection at round start: everyone starts in a cleared
			# corner with no bombs on the board, so there is nothing to protect
			# against and a blinking player would only be noise.
			p.spawn_protect_ticks = 0
		state.players.append(p)

	return state

# --- Queries ----------------------------------------------------------------

func flame_ttl_at(t: Vector2i) -> int:
	if not arena.in_bounds(t):
		return 0
	return flame_ttl[arena.index(t)]

## Slot index of the flame owner on `t`, or -1 if there is no flame.
func flame_owner_at(t: Vector2i) -> int:
	if not arena.in_bounds(t):
		return -1
	var i: int = arena.index(t)
	if flame_ttl[i] <= 0:
		return -1
	var owner: int = flame_owner[i]
	return -1 if owner == NO_OWNER else owner

# --- Pickups ----------------------------------------------------------------

## The Powerup.Kind on `t`, or NONE. Out of bounds reads as NONE, so no caller
## has to bounds-check before asking.
func pickup_at(t: Vector2i) -> int:
	if not arena.in_bounds(t):
		return Powerup.Kind.NONE
	return pickup_kind[arena.index(t)]

## The Powerup.Curse carried by the pickup on `t`; 0 for anything but a Dud.
func pickup_curse_at(t: Vector2i) -> int:
	if not arena.in_bounds(t):
		return Powerup.Curse.NONE
	return pickup_data[arena.index(t)]

func has_pickup_at(t: Vector2i) -> bool:
	return pickup_at(t) != Powerup.Kind.NONE

## Writes a pickup, overwriting anything already there. Every caller in Sim
## checks the tile is free first — one pickup per tile is the representation's
## guarantee and not a rule anyone has to remember.
func set_pickup(t: Vector2i, kind: int, curse: int = 0) -> void:
	if not arena.in_bounds(t):
		return
	var i: int = arena.index(t)
	pickup_kind[i] = kind
	pickup_data[i] = curse

func clear_pickup(t: Vector2i) -> void:
	set_pickup(t, Powerup.Kind.NONE, 0)

func pickup_count() -> int:
	var n: int = 0
	for i in range(pickup_kind.size()):
		if pickup_kind[i] != Powerup.Kind.NONE:
			n += 1
	return n

## Ceiling on total crates, from `crate_cap_permille` of the eligible interior.
func crate_cap() -> int:
	return arena.eligible_interior_count() * balance.crate_cap_permille / 1000

## Index into `bombs` of the live bomb on `t`, or -1. Linear, and that is fine:
## there are at most 32 bombs on the board and a scan of a small array beats a
## Dictionary the sim would then have to avoid iterating.
func bomb_index_at(t: Vector2i) -> int:
	for i in range(bombs.size()):
		var b: Bomb = bombs[i]
		if not b.exploded and b.tile == t:
			return i
	return -1

## The single source of truth for solidity, per M1 brief §5. HARD and CRATE
## always block; a bomb blocks unless it is this player's own-bomb exemption;
## flames never block.
func is_blocked_for(t: Vector2i, player_index: int) -> bool:
	if arena.is_solid(t):
		return true
	if bomb_index_at(t) < 0:
		return false
	if player_index >= 0 and player_index < players.size():
		return players[player_index].bomb_exempt_tile != t
	return true

func living_count() -> int:
	var n: int = 0
	for p in players:
		if p.active and p.alive:
			n += 1
	return n

func active_count() -> int:
	var n: int = 0
	for p in players:
		if p.active:
			n += 1
	return n

## Winning slot index, or -1 for a draw. Highest score takes the round; an equal
## top score is a draw and nobody takes it (game design §5.3).
func winner() -> int:
	var best: int = 0
	var best_slot: int = -1
	var tied: bool = false
	for p in players:
		if not p.active:
			continue
		if best_slot == -1 or p.score > best:
			best = p.score
			best_slot = p.index
			tied = false
		elif p.score == best:
			tied = true
	return -1 if tied else best_slot

func seconds_left() -> int:
	# Ceiling, so a clock showing 0:00 means the round is actually over.
	return (round_ticks_left + C.TICK_HZ - 1) / C.TICK_HZ

# --- Fingerprint ------------------------------------------------------------

## A 32-bit hash of the entire state, as hex. Two simulations that agree on this
## have not diverged; the golden replay test is built on it.
##
## Covers the RNG state as well as the board, deliberately: two states that look
## identical but have consumed a different number of draws *have* diverged, they
## just have not shown it yet.
func fingerprint() -> String:
	var h: int = SimHash.start()
	h = SimHash.mix_int(h, tick)
	h = SimHash.mix_int(h, round_ticks_left)
	h = SimHash.mix_int(h, regen_ticks_left)
	h = SimHash.mix_bool(h, finished)
	h = SimHash.mix_int(h, rng_seed)
	h = SimHash.mix_int(h, rng.state)
	h = SimHash.mix_int(h, arena.w)
	h = SimHash.mix_int(h, arena.h)
	h = SimHash.mix_bytes(h, arena.tiles)
	h = SimHash.mix_ints(h, flame_ttl)
	h = SimHash.mix_bytes(h, flame_owner)
	h = SimHash.mix_bytes(h, pickup_kind)
	h = SimHash.mix_bytes(h, pickup_data)
	h = SimHash.mix_int(h, players.size())
	for p in players:
		h = p.mix_into(h)
	h = SimHash.mix_int(h, bombs.size())
	for b in bombs:
		h = b.mix_into(h)
	return SimHash.to_hex(h)
