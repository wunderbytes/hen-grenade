class_name Sim
## The rule set. One static entry point: step(state, inputs) -> events.
## See docs/milestone-1-brief.md §5 and §6, and docs/technical-design.md §2-§3a.
##
## Determinism contract, enforced by code review (M1 brief §2):
##   - no `delta` and no wall clock; exactly one tick per step() call
##   - no floats; positions are fixed-point Vector2i in sub-tile units
##   - all randomness from state.rng, consumed in a fixed order
##   - no Dictionary iteration, no Node, no autoload
##   - the intra-tick order below is fixed and changing it changes the game

## Ray and direction order. Fixed: UP, RIGHT, DOWN, LEFT. Chain resolution walks
## these in order, so this array is part of the determinism contract.
const DIRS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]

# --- Geometry helpers -------------------------------------------------------

static func dir_vec(d: InputFrame.Dir) -> Vector2i:
	match d:
		InputFrame.Dir.UP: return DIRS[0]
		InputFrame.Dir.RIGHT: return DIRS[1]
		InputFrame.Dir.DOWN: return DIRS[2]
		InputFrame.Dir.LEFT: return DIRS[3]
	return Vector2i.ZERO

## Centre of a tile in sub-tile units.
static func tile_centre(t: Vector2i) -> Vector2i:
	return Vector2i(t.x * C.UNITS_PER_TILE + C.HALF_TILE, t.y * C.UNITS_PER_TILE + C.HALF_TILE)

static func tile_of(pos: Vector2i) -> Vector2i:
	return Vector2i(pos.x / C.UNITS_PER_TILE, pos.y / C.UNITS_PER_TILE)

# --- The tick ---------------------------------------------------------------

## Advances the simulation exactly one tick and returns what happened.
##
## The order is fixed and the reasons are worth keeping in view:
##   - flames age *before* blasts are laid, so a flame created this tick lives
##     its full lifetime and can kill on the tick it appears;
##   - bombs are placed *before* movement, so a bomb lands on the tile the
##     player was standing on when they pressed the button;
##   - deaths resolve *after* blasts, for the same reason flames age first.
static func step(state: MatchState, inputs: Array[InputFrame]) -> Array[SimEvent]:
	var events: Array[SimEvent] = []
	if state.finished:
		return events

	state.tick += 1
	_age_flames(state)

	for i in range(state.players.size()):
		var p: PlayerState = state.players[i]
		if not p.active:
			continue
		var frame: InputFrame = inputs[i] if i < inputs.size() else InputFrame.new()
		_player_actions(state, p, frame, events)

	_tick_bombs(state, events)
	_resolve_deaths(state, events)
	_tick_respawns(state, events)
	_tick_spawn_protection(state)
	_tick_clock(state, events)

	return events

# --- Flames -----------------------------------------------------------------

static func _age_flames(state: MatchState) -> void:
	for i in range(state.flame_ttl.size()):
		var ttl: int = state.flame_ttl[i]
		if ttl <= 0:
			continue
		ttl -= 1
		state.flame_ttl[i] = ttl
		if ttl == 0:
			state.flame_owner[i] = MatchState.NO_OWNER

## Lights (or refreshes) a flame. Where two independent blasts reach the same
## tile, **the most recent writer owns it** — the fire you just made is yours —
## and the lifetime is refreshed to the longer of the two. Within a single chain
## this is moot, since every flame in a chain shares one owner.
static func _lay_flame(state: MatchState, t: Vector2i, owner: int, events: Array[SimEvent]) -> void:
	if not state.arena.in_bounds(t):
		return
	var i: int = state.arena.index(t)
	var was: int = state.flame_ttl[i]
	state.flame_ttl[i] = maxi(was, state.balance.flame_ticks)
	state.flame_owner[i] = owner
	if was <= 0:
		events.append(SimEvent.flame_lit(t, owner, state.balance.flame_ticks))

# --- Player actions ---------------------------------------------------------

static func _player_actions(state: MatchState, p: PlayerState, frame: InputFrame, events: Array[SimEvent]) -> void:
	# Edge-detect the bomb button even while dead, so holding A through a
	# respawn does not drop a bomb the instant the player reappears.
	var bomb_edge: bool = frame.bomb and not p.prev_bomb
	p.prev_bomb = frame.bomb
	if not p.alive:
		return
	if bomb_edge:
		_try_place_bomb(state, p, events)
	_move(state, p, frame)
	# The own-bomb exemption is released the first tick the player's centre
	# leaves the tile, which is what makes the pass-off one-way.
	if p.has_bomb_exemption() and p.tile() != p.bomb_exempt_tile:
		p.clear_bomb_exemption()

static func _try_place_bomb(state: MatchState, p: PlayerState, events: Array[SimEvent]) -> void:
	if p.bombs_active >= p.bomb_capacity:
		return
	var t: Vector2i = p.tile()
	if state.bomb_index_at(t) >= 0:
		return
	state.bombs.append(Bomb.new(t, p.index, state.balance.bomb_fuse_ticks, p.blast_radius))
	p.bombs_active += 1
	# "Solid to everyone except the player still standing on it" — normally just
	# the placer, but two players can share a tile since players do not collide.
	for other in state.players:
		if other.active and other.alive and other.tile() == t:
			other.bomb_exempt_tile = t
	# Dropping a bomb ends spawn protection immediately, so it cannot be used as
	# an offensive shield (game design §5.3).
	p.spawn_protect_ticks = 0
	events.append(SimEvent.bomb_placed(t, p.index, p.blast_radius))

# --- Movement ---------------------------------------------------------------

## Moves one player one tick. See M1 brief §5 for the reasoning; the short
## version is that collision is point-vs-tile with a **centre stop**, the stop
## clamp is **one-directional** so it can never yank a player backwards, and
## corner assist exists to handle a direction change near a junction.
static func _move(state: MatchState, p: PlayerState, frame: InputFrame) -> void:
	if frame.dir == InputFrame.Dir.NONE:
		return
	p.facing = frame.dir

	var d: Vector2i = dir_vec(frame.dir)
	var cur: Vector2i = p.tile()
	var horiz: bool = d.x != 0
	var blocked: bool = state.is_blocked_for(cur + d, p.index)
	var speed: int = p.speed_units
	var centre: Vector2i = tile_centre(cur)

	if blocked and _try_corner_assist(state, p, cur, d, horiz, speed):
		return

	if horiz:
		var nx: int = p.pos.x + d.x * speed
		if blocked:
			# Stop with the centre on this tile's centre, but never move back.
			if d.x > 0:
				nx = maxi(mini(nx, centre.x), p.pos.x)
			else:
				nx = mini(maxi(nx, centre.x), p.pos.x)
		p.pos = Vector2i(nx, _toward(p.pos.y, centre.y, speed))
	else:
		var ny: int = p.pos.y + d.y * speed
		if blocked:
			if d.y > 0:
				ny = maxi(mini(ny, centre.y), p.pos.y)
			else:
				ny = mini(maxi(ny, centre.y), p.pos.y)
		p.pos = Vector2i(_toward(p.pos.x, centre.x, speed), ny)

## Corner assist. Fires only when the way ahead is blocked and the player is
## *already leaning* toward an adjacent lane that is open in the direction of
## travel — which in practice means they pressed a new direction just short of a
## junction. Slides them into that lane instead of stopping dead.
##
## Returns true if it handled the tick (the player slid and did not advance).
static func _try_corner_assist(state: MatchState, p: PlayerState, cur: Vector2i, d: Vector2i, horiz: bool, speed: int) -> bool:
	var centre: Vector2i = tile_centre(cur)
	var off: int = (p.pos.y - centre.y) if horiz else (p.pos.x - centre.x)
	if off == 0:
		return false
	# Is the adjacent lane within corner_assist_units of being entered?
	if absi(off) < C.HALF_TILE - state.balance.corner_assist_units:
		return false
	var lean: int = signi(off)
	var perp: Vector2i = Vector2i(0, lean) if horiz else Vector2i(lean, 0)
	var adjacent: Vector2i = cur + perp
	# Only worth sliding if that lane is both enterable and actually open the
	# way the player wants to go. Otherwise this would shove them into a dead
	# end they never asked for.
	if state.is_blocked_for(adjacent, p.index):
		return false
	if state.is_blocked_for(adjacent + d, p.index):
		return false
	if horiz:
		p.pos = Vector2i(p.pos.x, p.pos.y + lean * speed)
	else:
		p.pos = Vector2i(p.pos.x + lean * speed, p.pos.y)
	return true

## Moves `v` toward `target` by at most `step`, without overshooting. This is
## lane snapping: "you always walk down the middle of a corridor".
static func _toward(v: int, target: int, step: int) -> int:
	if v < target:
		return mini(v + step, target)
	if v > target:
		return maxi(v - step, target)
	return v

# --- Bombs and blasts -------------------------------------------------------

## Detonates anything whose fuse has run out, then ages the survivors.
##
## Checking *before* decrementing is what makes a fuse of N mean exactly N
## ticks on the board: a bomb placed earlier this same tick is checked (and
## survives, since its fuse is still N) before it is aged for the first time.
## The other order costs a tick and makes the 2.5 s fuse 2.483 s.
##
## Detonation runs in bomb-array order, and each detonation resolves its whole
## chain before the next bomb is considered. A chain marks the bombs it consumes
## as exploded, so the loop naturally skips them.
static func _tick_bombs(state: MatchState, events: Array[SimEvent]) -> void:
	for i in range(state.bombs.size()):
		var b: Bomb = state.bombs[i]
		if not b.exploded and b.fuse_ticks <= 0:
			_detonate_chain(state, i, events)
	for b in state.bombs:
		if not b.exploded:
			b.fuse_ticks -= 1
	_reap_bombs(state)

## Resolves one detonation and every bomb it sets off, breadth-first over a
## queue of bomb indices. Iterative rather than recursive so a forty-bomb chain
## cannot blow the stack, and so the order is obvious rather than emergent.
##
## Flame ownership propagates from **whoever started the chain**: set off
## someone else's bomb and the kills are yours (M1 brief §6.2; game design §5.2
## was amended to match).
static func _detonate_chain(state: MatchState, root: int, events: Array[SimEvent]) -> void:
	var chain_owner: int = state.bombs[root].owner
	var queue: PackedInt32Array = PackedInt32Array([root])
	var qi: int = 0
	while qi < queue.size():
		var bi: int = queue[qi]
		qi += 1
		var b: Bomb = state.bombs[bi]
		if b.exploded:
			continue
		b.exploded = true
		# The bomb frees its own owner's budget even when someone else set it
		# off, and even if that owner is currently dead.
		if b.owner >= 0 and b.owner < state.players.size():
			var owner_player: PlayerState = state.players[b.owner]
			owner_player.bombs_active = maxi(0, owner_player.bombs_active - 1)
		events.append(SimEvent.bomb_exploded(b.tile, b.owner, chain_owner, b.radius))
		_lay_flame(state, b.tile, chain_owner, events)

		for d in DIRS:
			for step_n in range(1, b.radius + 1):
				var t: Vector2i = b.tile + d * step_n
				var tile_type: int = state.arena.at(t)
				if tile_type == Arena.Tile.HARD:
					break                      # no flame on the block itself
				if tile_type == Arena.Tile.CRATE:
					state.arena.set_at(t, Arena.Tile.FLOOR)
					events.append(SimEvent.crate_destroyed(t, chain_owner))
					_lay_flame(state, t, chain_owner, events)
					break                      # exactly one crate per direction
				_lay_flame(state, t, chain_owner, events)
				var other: int = state.bomb_index_at(t)
				if other >= 0 and not state.bombs[other].exploded and not queue.has(other):
					queue.append(other)

## Drops exploded bombs, preserving the order of the survivors so indices stay
## meaningful from tick to tick.
static func _reap_bombs(state: MatchState) -> void:
	var kept: Array[Bomb] = []
	for b in state.bombs:
		if not b.exploded:
			kept.append(b)
	state.bombs = kept

# --- Death, respawn, clock --------------------------------------------------

static func _resolve_deaths(state: MatchState, events: Array[SimEvent]) -> void:
	for p in state.players:
		if not p.active or not p.alive:
			continue
		if p.spawn_protect_ticks > 0:
			continue
		var t: Vector2i = p.tile()
		var killer: int = state.flame_owner_at(t)
		if killer < 0:
			continue
		p.alive = false
		p.deaths += 1
		p.respawn_ticks = state.balance.respawn_ticks
		p.clear_bomb_exemption()
		# The victim's own live bombs keep burning and keep their ownership: a
		# bomb outlives its owner and can still score for them.
		if killer == p.index:
			p.score -= 1                       # the suicide penalty
		else:
			state.players[killer].score += 1
			state.players[killer].kills += 1
		events.append(SimEvent.player_died(t, p.index, killer))

static func _tick_respawns(state: MatchState, events: Array[SimEvent]) -> void:
	for p in state.players:
		if not p.active or p.alive:
			continue
		if p.respawn_ticks > 0:
			p.respawn_ticks -= 1
			# Always consume a whole tick before the counter is read as expired,
			# so a respawn_ticks of 90 means exactly 90 ticks off the board.
			continue
		var t: Vector2i = _choose_respawn_tile(state, p.index)
		if t.x < 0:
			continue      # nowhere safe this tick; flames expire, so retry
		p.pos = tile_centre(t)
		p.alive = true
		p.spawn_protect_ticks = state.balance.spawn_protect_ticks
		p.clear_bomb_exemption()
		events.append(SimEvent.player_respawned(t, p.index, p.spawn_protect_ticks))

static func _tick_spawn_protection(state: MatchState) -> void:
	for p in state.players:
		if p.spawn_protect_ticks > 0:
			p.spawn_protect_ticks -= 1

static func _tick_clock(state: MatchState, events: Array[SimEvent]) -> void:
	if state.round_ticks_left > 0:
		state.round_ticks_left -= 1
	if state.round_ticks_left <= 0 and not state.finished:
		state.finished = true
		events.append(SimEvent.round_ended(state.winner()))

# --- Respawn tile selection -------------------------------------------------

## Picks the designated respawn tile furthest from danger, per technical design
## §3a. Ties break by tile index, which is why ArenaDef lists respawn tiles in
## index order. Returns (-1, -1) when nothing is usable — the caller retries next
## tick, and since flames expire this cannot deadlock.
static func _choose_respawn_tile(state: MatchState, player_index: int) -> Vector2i:
	var threats: Array[Vector2i] = _gather_threats(state, player_index)
	var best: Vector2i = Vector2i(-1, -1)
	var best_score: int = -1

	for t in state.arena_def.respawn_tiles:
		var s: int = _respawn_score(state, t, threats)
		if s > best_score:
			best_score = s
			best = t
	if best.x >= 0:
		return best

	# Every designated tile is on fire or occupied. Fall back to scanning the
	# whole interior in index order so the choice stays deterministic.
	for y in range(1, state.arena.h - 1):
		for x in range(1, state.arena.w - 1):
			var t: Vector2i = Vector2i(x, y)
			var s: int = _respawn_score(state, t, threats)
			if s > best_score:
				best_score = s
				best = t
	return best

## Manhattan distance to the nearest threat, or -1 if the tile is unusable.
## Gathered once per call rather than per candidate: there are at most a few
## dozen threats and up to 299 candidates in the fallback path.
static func _respawn_score(state: MatchState, t: Vector2i, threats: Array[Vector2i]) -> int:
	if state.arena.at(t) != Arena.Tile.FLOOR:
		return -1
	if state.flame_ttl_at(t) > 0:
		return -1
	if state.bomb_index_at(t) >= 0:
		return -1
	if threats.is_empty():
		return state.arena.w + state.arena.h
	var nearest: int = state.arena.w + state.arena.h
	for threat in threats:
		var dist: int = absi(t.x - threat.x) + absi(t.y - threat.y)
		if dist < nearest:
			nearest = dist
	return nearest

static func _gather_threats(state: MatchState, player_index: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p in state.players:
		if p.active and p.alive and p.index != player_index:
			out.append(p.tile())
	for b in state.bombs:
		if not b.exploded:
			out.append(b.tile)
	var w: int = state.arena.w
	for i in range(state.flame_ttl.size()):
		if state.flame_ttl[i] > 0:
			out.append(Vector2i(i % w, i / w))
	return out
