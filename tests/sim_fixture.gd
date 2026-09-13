class_name SimFixture
## Shared builders for the simulation test suites.
##
## Two ideas here. First, tests get a **short round** by default so a scoring
## test does not have to simulate 7200 ticks. Second, most tests get an **empty
## arena** — border walls only, no pillars, no crates — and then place exactly
## the tiles they care about. A blast test asserting "the ray stops at the hard
## block" should fail because the ray is wrong, not because a randomly generated
## crate happened to be in the way.

## Default balance with a short round. Everything else is the shipped value, so
## a test that depends on the real fuse or respawn timing gets it.
static func balance() -> Balance:
	var b: Balance = Balance.new()
	b.round_ticks = 600            # 10 s
	return b

static func arena_def(crate_permille: int = 0) -> ArenaDef:
	var def: ArenaDef = ArenaDef.new()
	def.crate_permille = crate_permille
	return def

## A table that never drops anything, so a test about blast geometry is not
## accidentally a test about power-ups.
static func no_drops() -> PowerupTable:
	var table: PowerupTable = PowerupTable.new()
	table.drop_permille = 0
	return table

## A table that drops `kind` from every crate, and nothing else. Makes a drop
## test about the rule rather than about the seed.
static func always_drops(kind: int) -> PowerupTable:
	var table: PowerupTable = PowerupTable.new()
	table.drop_permille = 1000
	table.weight_bomb = 1 if kind == Powerup.Kind.BOMB else 0
	table.weight_blast = 1 if kind == Powerup.Kind.BLAST else 0
	table.weight_speed = 1 if kind == Powerup.Kind.SPEED else 0
	table.weight_kick = 1 if kind == Powerup.Kind.KICK else 0
	table.weight_toss = 1 if kind == Powerup.Kind.TOSS else 0
	table.weight_remote = 1 if kind == Powerup.Kind.REMOTE else 0
	table.weight_jackpot = 1 if kind == Powerup.Kind.JACKPOT else 0
	table.weight_dud = 1 if kind == Powerup.Kind.DUD else 0
	return table

## A state on a completely empty arena (border only), with `player_count` slots
## active and sitting on their spawn tiles.
static func open_state(p_balance: Balance = null, player_count: int = 2, p_seed: int = 12345, p_powerups: PowerupTable = null, p_mode: GameMode = null) -> MatchState:
	var bal: Balance = p_balance if p_balance != null else balance()
	var active: Array[bool] = []
	for i in range(C.MAX_PLAYERS):
		active.append(i < player_count)
	var state: MatchState = MatchState.create(bal, arena_def(0), p_seed, active, p_powerups, p_mode)
	clear_interior(state.arena)
	return state

## A state on a normally generated arena — crates, pillars and all.
static func generated_state(p_balance: Balance = null, player_count: int = 2, p_seed: int = 12345, p_powerups: PowerupTable = null, p_mode: GameMode = null) -> MatchState:
	var bal: Balance = p_balance if p_balance != null else balance()
	var active: Array[bool] = []
	for i in range(C.MAX_PLAYERS):
		active.append(i < player_count)
	return MatchState.create(bal, arena_def(700), p_seed, active, p_powerups, p_mode)

static func clear_interior(arena: Arena) -> void:
	for y in range(1, arena.h - 1):
		for x in range(1, arena.w - 1):
			arena.set_at(Vector2i(x, y), Arena.Tile.FLOOR)

# --- Placement --------------------------------------------------------------

## Drops a player onto a tile's exact centre, alive and unprotected.
static func place(state: MatchState, index: int, tile: Vector2i) -> PlayerState:
	var p: PlayerState = state.players[index]
	p.active = true
	p.alive = true
	p.pos = Sim.tile_centre(tile)
	p.spawn_protect_ticks = 0
	p.clear_bomb_exemption()
	return p

## Parks every active player in a corner well away from the action, so a test
## about blast geometry is not accidentally a test about who died.
static func park_others(state: MatchState, keep: int) -> void:
	for p in state.players:
		if not p.active or p.index == keep:
			continue
		p.pos = Sim.tile_centre(Vector2i(state.arena.w - 2, state.arena.h - 2))

## Adds a bomb directly, bypassing input. Used by blast and chain tests that
## care about the explosion, not about who pressed what.
static func add_bomb(state: MatchState, tile: Vector2i, owner: int, fuse: int, radius: int) -> Bomb:
	var b: Bomb = Bomb.new(tile, owner, fuse, radius)
	state.bombs.append(b)
	if owner >= 0 and owner < state.players.size():
		state.players[owner].bombs_active += 1
	return b

## Lights a flame directly, for tests about what fire does rather than about
## where it came from.
static func add_flame(state: MatchState, tile: Vector2i, owner: int, ttl: int = 24) -> void:
	var i: int = state.arena.index(tile)
	state.flame_ttl[i] = ttl
	state.flame_owner[i] = owner

## Puts a pickup on a tile directly, so a collection test does not have to break
## a crate and hope.
static func add_pickup(state: MatchState, tile: Vector2i, kind: int, curse: int = 0) -> void:
	state.set_pickup(tile, kind, curse)

## Every tile currently holding a pickup, in index order.
static func pickup_tiles(state: MatchState) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in range(state.pickup_kind.size()):
		if state.pickup_kind[i] != Powerup.Kind.NONE:
			out.append(Vector2i(i % state.arena.w, i / state.arena.w))
	return out

## The Powerup.Kinds on the board, sorted, so a scatter test can compare sets
## without depending on tile order.
static func pickup_kinds(state: MatchState) -> Array[int]:
	var out: Array[int] = []
	for i in range(state.pickup_kind.size()):
		var kind: int = state.pickup_kind[i]
		if kind != Powerup.Kind.NONE:
			out.append(kind)
	out.sort()
	return out

# --- Input ------------------------------------------------------------------

static func frame(dir: InputFrame.Dir = InputFrame.Dir.NONE, bomb: bool = false, action: bool = false) -> InputFrame:
	var f: InputFrame = InputFrame.new()
	f.dir = dir
	f.bomb = bomb
	f.action = action
	return f

static func blank_frames() -> Array[InputFrame]:
	var out: Array[InputFrame] = []
	for _i in range(C.MAX_PLAYERS):
		out.append(InputFrame.new())
	return out

## Frames where only `slot` is doing anything.
static func frames_for(slot: int, dir: InputFrame.Dir = InputFrame.Dir.NONE, bomb: bool = false) -> Array[InputFrame]:
	var out: Array[InputFrame] = blank_frames()
	out[slot] = frame(dir, bomb)
	return out

# --- Running ----------------------------------------------------------------

## Runs `ticks` steps with a constant input set and returns every event.
## Note that a constant set with bomb held drops exactly one bomb, because
## placement is rising-edge triggered — which is itself worth testing.
static func run_ticks(state: MatchState, inputs: Array[InputFrame], ticks: int) -> Array[SimEvent]:
	var all: Array[SimEvent] = []
	for _i in range(ticks):
		all.append_array(Sim.step(state, inputs))
	return all

static func run_idle(state: MatchState, ticks: int) -> Array[SimEvent]:
	return run_ticks(state, blank_frames(), ticks)

# --- Event helpers ----------------------------------------------------------

static func events_of(events: Array[SimEvent], kind: SimEvent.Kind) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e in events:
		if e.kind == kind:
			out.append(e)
	return out

static func count_of(events: Array[SimEvent], kind: SimEvent.Kind) -> int:
	return events_of(events, kind).size()

static func first_of(events: Array[SimEvent], kind: SimEvent.Kind) -> SimEvent:
	for e in events:
		if e.kind == kind:
			return e
	return null

## The set of tiles a blast lit, as a sorted list of "x,y" strings, so a test
## can compare against an expected plus-shape without depending on ray order.
static func lit_tiles(events: Array[SimEvent]) -> Array[String]:
	var out: Array[String] = []
	for e in events_of(events, SimEvent.Kind.FLAME_LIT):
		out.append("%d,%d" % [e.tile.x, e.tile.y])
	out.sort()
	return out

static func tile_keys(tiles: Array[Vector2i]) -> Array[String]:
	var out: Array[String] = []
	for t in tiles:
		out.append("%d,%d" % [t.x, t.y])
	out.sort()
	return out
