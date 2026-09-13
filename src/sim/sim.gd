class_name Sim
## The rule set. One static entry point: step(state, inputs) -> events.
## See docs/milestone-1-brief.md §5 and §6, docs/milestone-3-brief.md §2-§5, and
## docs/technical-design.md §2-§3a.
##
## Determinism contract, enforced by code review (M1 brief §2):
##   - no `delta` and no wall clock; exactly one tick per step() call
##   - no floats; positions are fixed-point Vector2i in sub-tile units
##   - all randomness from state.rng, consumed in a fixed order
##   - no Dictionary iteration, no Node, no autoload
##   - the intra-tick order below is fixed and changing it changes the game
##
## M3 adds two rules about the PRNG that are worth stating where they can be
## read next to the code (M3 brief §2):
##   - **Destroying a crate costs exactly three draws** — the drop roll, the kind
##     roll and the curse-variant roll — whether or not anything drops. A
##     conditional draw would make the sequence depend on the outcome of earlier
##     draws, which is the kind of thing that survives a green golden replay
##     right up until someone retunes a weight.
##   - **Kit scatter and respawn selection consume no draws at all.** Both are
##     ordered searches, so a round's PRNG sequence does not depend on how many
##     people died in it. Crate regeneration is the only new consumer.

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

## The Reversed curse, and nothing else, needs this.
static func opposite_dir(d: InputFrame.Dir) -> InputFrame.Dir:
	match d:
		InputFrame.Dir.UP: return InputFrame.Dir.DOWN
		InputFrame.Dir.DOWN: return InputFrame.Dir.UP
		InputFrame.Dir.LEFT: return InputFrame.Dir.RIGHT
		InputFrame.Dir.RIGHT: return InputFrame.Dir.LEFT
	return InputFrame.Dir.NONE

## Centre of a tile in sub-tile units.
static func tile_centre(t: Vector2i) -> Vector2i:
	return Vector2i(t.x * C.UNITS_PER_TILE + C.HALF_TILE, t.y * C.UNITS_PER_TILE + C.HALF_TILE)

static func tile_of(pos: Vector2i) -> Vector2i:
	return Vector2i(pos.x / C.UNITS_PER_TILE, pos.y / C.UNITS_PER_TILE)

# --- Effective values -------------------------------------------------------
#
# Curses are overrides read at the point of use, never writes to the loadout.
# That is what makes an expiring curse restore exactly what the player had, and
# what keeps a cursed player's kit loss on death honest (M3 brief §4.4).

static func _speed_of(state: MatchState, p: PlayerState) -> int:
	if p.has_curse() and p.curse == Powerup.Curse.FAST:
		return state.balance.max_speed_units
	return p.speed_units

static func _radius_of(state: MatchState, p: PlayerState) -> int:
	if p.has_curse() and p.curse == Powerup.Curse.TINY_BLAST:
		return 1
	return p.blast_radius

## Movement speed for a number of Speed Ups, clamped to the cap. The one place
## the step size and the cap meet.
static func _speed_for_steps(state: MatchState, steps: int) -> int:
	return mini(
		state.balance.max_speed_units,
		state.balance.move_speed_units + maxi(0, steps) * state.balance.speed_step_units
	)

# --- The tick ---------------------------------------------------------------

## Advances the simulation exactly one tick and returns what happened.
##
## The order is fixed and the reasons are worth keeping in view:
##   - flames age *before* blasts are laid, so a flame created this tick lives
##     its full lifetime and can kill on the tick it appears;
##   - bombs are placed *before* movement, so a bomb lands on the tile the
##     player was standing on when they pressed the button;
##   - deaths resolve *after* blasts, for the same reason flames age first;
##   - a crate wave lands *after* everything has moved, so its "not next to a
##     living player" rule is judged against where people actually are.
static func step(state: MatchState, inputs: Array[InputFrame]) -> Array[SimEvent]:
	var events: Array[SimEvent] = []
	if state.finished:
		return events

	state.tick += 1
	_age_flames(state)

	# Remote detonation is requested during a player's actions and served at the
	# top of the bomb phase, so that every detonation in the game happens in one
	# place. A local rather than player state: it never outlives the tick.
	var remote_fire: PackedByteArray = PackedByteArray()
	remote_fire.resize(C.MAX_PLAYERS)
	remote_fire.fill(0)

	for i in range(state.players.size()):
		var p: PlayerState = state.players[i]
		if not p.active:
			continue
		var frame: InputFrame = inputs[i] if i < inputs.size() else InputFrame.new()
		_player_actions(state, p, frame, events, remote_fire)

	_tick_bombs(state, events, remote_fire)
	_resolve_deaths(state, events)
	_tick_respawns(state, events)
	_tick_spawn_protection(state)
	_tick_curses(state, events)
	_tick_crate_regen(state, events)
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
##
## A flame also **burns off any pickup on the tile** (M3 brief §3.2), which is
## the "grab it now" tension in game design §6. A crate's own drop is written
## after the chain finishes, so a drop is never destroyed by the blast that
## revealed it — only by the next one.
static func _lay_flame(state: MatchState, t: Vector2i, owner: int, events: Array[SimEvent]) -> void:
	if not state.arena.in_bounds(t):
		return
	var i: int = state.arena.index(t)
	var was: int = state.flame_ttl[i]
	state.flame_ttl[i] = maxi(was, state.balance.flame_ticks)
	state.flame_owner[i] = owner
	if was <= 0:
		events.append(SimEvent.flame_lit(t, owner, state.balance.flame_ticks))
	var pickup: int = state.pickup_kind[i]
	if pickup != Powerup.Kind.NONE:
		state.pickup_kind[i] = Powerup.Kind.NONE
		state.pickup_data[i] = 0
		events.append(SimEvent.pickup_destroyed(t, owner, pickup))

# --- Player actions ---------------------------------------------------------

## One player's tick. The order inside here matters as much as the order of the
## phases (M3 brief §2.2): a curse rewrites the frame before anything reads it,
## a bomb is placed before movement, and an ability fires and a pickup is
## collected after it — so a toss goes where the player now faces, and walking
## onto a pickup takes it on the same tick.
static func _player_actions(state: MatchState, p: PlayerState, frame: InputFrame, events: Array[SimEvent], remote_fire: PackedByteArray) -> void:
	var dir: InputFrame.Dir = frame.dir
	if p.has_curse() and p.curse == Powerup.Curse.REVERSED:
		dir = opposite_dir(dir)

	# Edge-detect both buttons even while dead, so holding one through a respawn
	# does not fire it the instant the player reappears.
	var bomb_edge: bool = frame.bomb and not p.prev_bomb
	p.prev_bomb = frame.bomb
	var action_edge: bool = frame.action and not p.prev_action
	p.prev_action = frame.action
	if not p.alive:
		return

	# Forced constant bomb-dropping ignores the edge entirely, which is the whole
	# unpleasantness of the curse.
	if p.has_curse() and p.curse == Powerup.Curse.BOMB_SPAM:
		bomb_edge = true

	if bomb_edge:
		_try_place_bomb(state, p, events)
	_move(state, p, dir, events)
	if action_edge:
		_use_ability(state, p, events, remote_fire)
	_collect_pickup(state, p, events)
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
	var bomb: Bomb = Bomb.new(t, p.index, state.balance.bomb_fuse_ticks, _radius_of(state, p))
	# A Remote holder's bombs have no fuse and wait for the button. The fuse is
	# still stored rather than sentinelled, so losing Remote can simply arm them
	# (M3 brief §4.3).
	bomb.remote = p.ability == Powerup.Kind.REMOTE
	state.bombs.append(bomb)
	p.bombs_active += 1
	# "Solid to everyone except the player still standing on it" — normally just
	# the placer, but two players can share a tile since players do not collide.
	for other in state.players:
		if other.active and other.alive and other.tile() == t:
			other.bomb_exempt_tile = t
	# Dropping a bomb ends spawn protection immediately, so it cannot be used as
	# an offensive shield (game design §5.3).
	p.spawn_protect_ticks = 0
	events.append(SimEvent.bomb_placed(t, p.index, bomb.radius))

# --- Movement ---------------------------------------------------------------

## Moves one player one tick. See M1 brief §5 for the reasoning; the short
## version is that collision is point-vs-tile with a **centre stop**, the stop
## clamp is **one-directional** so it can never yank a player backwards, and
## corner assist exists to handle a direction change near a junction.
##
## `dir` is passed in rather than read off the frame because a curse may have
## rewritten it (M3 brief §4.4).
static func _move(state: MatchState, p: PlayerState, dir: InputFrame.Dir, events: Array[SimEvent]) -> void:
	if dir == InputFrame.Dir.NONE:
		return
	p.facing = dir

	var d: Vector2i = dir_vec(dir)
	var cur: Vector2i = p.tile()
	var ahead: Vector2i = cur + d
	var horiz: bool = d.x != 0
	var blocked: bool = state.is_blocked_for(ahead, p.index)
	var speed: int = _speed_of(state, p)
	var centre: Vector2i = tile_centre(cur)

	# Kick fires from here, because "walking into a bomb" is a movement event and
	# there is no button to hang it off. The player is still blocked this tick —
	# the bomb has not stepped yet — so they push it and then follow it.
	if blocked and p.has_kick and not state.arena.is_solid(ahead):
		_try_kick(state, p, ahead, d, events)

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

# --- Kick -------------------------------------------------------------------

## Starts a bomb sliding, if there is a bomb on `tile` that is free to move.
##
## A bomb the player is exempt from — their own, still under their feet — never
## reaches here, because `is_blocked_for` returns false for it and the caller
## only asks when blocked. That is the difference between walking into a bomb and
## standing on one.
static func _try_kick(state: MatchState, p: PlayerState, tile: Vector2i, d: Vector2i, events: Array[SimEvent]) -> bool:
	var bi: int = state.bomb_index_at(tile)
	if bi < 0:
		return false
	var b: Bomb = state.bombs[bi]
	if b.exploded or b.is_sliding():
		return false
	if not _can_hold_bomb(state, tile + d):
		return false           # nowhere to go: this is a wall, not a kick
	b.slide_dir = d
	b.slide_ticks = state.balance.kick_ticks_per_tile
	# Whoever was standing on it is not standing on it any more.
	for other in state.players:
		if other.bomb_exempt_tile == tile:
			other.clear_bomb_exemption()
	events.append(SimEvent.bomb_kicked(tile, tile + d, p.index))
	return true

## Advances every sliding bomb. A bomb steps one **whole tile** at a time (M3
## brief §4.1): everything that touches a bomb indexes it by tile, so giving one
## a sub-tile position would mean revisiting solidity, chains and blast rays for
## the sake of one power-up. The view has `slide_dir` and `slide_ticks` and can
## interpolate without the rules changing.
static func _slide_bombs(state: MatchState, events: Array[SimEvent]) -> void:
	for i in range(state.bombs.size()):
		var b: Bomb = state.bombs[i]
		if b.exploded or not b.is_sliding():
			continue
		b.slide_ticks -= 1
		if b.slide_ticks > 0:
			continue
		var next: Vector2i = b.tile + b.slide_dir
		if not _can_hold_bomb(state, next):
			b.stop_sliding()
			continue
		b.tile = next
		b.slide_ticks = state.balance.kick_ticks_per_tile
		# A bomb kicked into fire goes off, credited to the flame's owner —
		# without this, kicking a bomb into a blast does nothing, which nobody
		# would predict from "a bomb caught in a blast detonates".
		var owner: int = state.flame_owner_at(next)
		if owner >= 0:
			_detonate_chain(state, i, events, owner)

## Can a bomb occupy this tile? Solid tiles and other bombs say no; flames and
## pickups do not — a bomb can land on either, and both are dealt with
## elsewhere. Bombs pass **under players** deliberately (M3 brief §4.1).
static func _can_hold_bomb(state: MatchState, t: Vector2i) -> bool:
	if not state.arena.in_bounds(t):
		return false
	if state.arena.at(t) != Arena.Tile.FLOOR:
		return false
	return state.bomb_index_at(t) < 0

# --- Abilities --------------------------------------------------------------

## The action button, which does exactly one thing because a player has exactly
## one ability (M3 brief §4.3). Kick is not here: it has no button.
static func _use_ability(state: MatchState, p: PlayerState, events: Array[SimEvent], remote_fire: PackedByteArray) -> void:
	match p.ability:
		Powerup.Kind.REMOTE:
			remote_fire[p.index] = 1
		Powerup.Kind.TOSS:
			_try_toss(state, p, events)

## Lobs the bomb under the player's feet `toss_tiles` away, over anything in
## between — that is the entire point of the ability.
##
## If the target tile cannot hold a bomb the throw walks **back** toward the
## thrower for the first tile that can. Never forward: a toss that overshoots
## into the next corridor because the intended tile was occupied would be
## genuinely unpredictable, and unpredictable is the one thing this game's
## readability pillar will not tolerate.
static func _try_toss(state: MatchState, p: PlayerState, events: Array[SimEvent]) -> void:
	if not p.has_bomb_exemption():
		return                      # nothing underfoot
	var from: Vector2i = p.bomb_exempt_tile
	var bi: int = state.bomb_index_at(from)
	if bi < 0:
		p.clear_bomb_exemption()    # stale exemption; the bomb has gone
		return
	var d: Vector2i = dir_vec(p.facing)
	if d == Vector2i.ZERO:
		return
	var dest: Vector2i = Vector2i(-1, -1)
	var steps: int = maxi(1, state.balance.toss_tiles)
	while steps >= 1:
		var candidate: Vector2i = from + d * steps
		if _can_hold_bomb(state, candidate):
			dest = candidate
			break
		steps -= 1
	if dest.x < 0:
		return
	var b: Bomb = state.bombs[bi]
	b.tile = dest
	b.stop_sliding()
	# Nobody is standing on it any more, including the thrower.
	for other in state.players:
		if other.bomb_exempt_tile == from:
			other.clear_bomb_exemption()
	# The flight is instantaneous here; the arc is the view's business, and an
	# airborne bomb would be the only entity in the game that is neither solid
	# nor chainable nor on a tile.
	events.append(SimEvent.bomb_tossed(from, dest, p.index))

## Serves the tick's Remote requests. **Every** bomb the player owns goes off,
## not just the fuse-less ones — "press B to detonate all of yours" is the
## design's wording and the simpler rule to hold in your head while playing.
static func _fire_remote(state: MatchState, events: Array[SimEvent], remote_fire: PackedByteArray) -> void:
	for slot in range(remote_fire.size()):
		if remote_fire[slot] == 0:
			continue
		for i in range(state.bombs.size()):
			var b: Bomb = state.bombs[i]
			if b.exploded or b.owner != slot:
				continue
			_detonate_chain(state, i, events)

## Gives a player's fuse-less bombs a fuse. Called whenever Remote leaves them —
## by death or by picking up a Toss — because the alternative is permanent solid
## blocks in the middle of the arena owned by nobody, which is how a two-minute
## round silts up into a maze (M3 brief §4.3).
static func _arm_orphaned_bombs(state: MatchState, slot: int) -> void:
	for b in state.bombs:
		if b.exploded or not b.remote or b.owner != slot:
			continue
		b.remote = false
		b.fuse_ticks = state.balance.bomb_fuse_ticks

# --- Pickups ----------------------------------------------------------------

## Rolls a destroyed crate's drop. **Exactly three draws, always** (see the note
## at the top of this file): the drop roll, the kind, and the curse variant. The
## last two are spent even when the first says "nothing", which is what keeps the
## sequence independent of its own outcomes.
static func _roll_crate_drop(state: MatchState, t: Vector2i, events: Array[SimEvent]) -> void:
	var roll: int = state.rng.next_below(1000)
	var kind: int = state.powerups.pick(state.rng)
	var curse: int = state.rng.next_below(Powerup.CURSE_COUNT) + 1

	if roll >= state.powerups.drop_permille:
		return
	if kind == Powerup.Kind.NONE:
		return
	if state.has_pickup_at(t) or state.arena.at(t) != Arena.Tile.FLOOR:
		return
	if kind != Powerup.Kind.DUD:
		curse = Powerup.Curse.NONE
	state.set_pickup(t, kind, curse)
	events.append(SimEvent.pickup_spawned(t, kind, curse, -1))

## Takes whatever is on the player's centre tile. Runs after movement, so
## walking onto a pickup collects it on the same tick.
static func _collect_pickup(state: MatchState, p: PlayerState, events: Array[SimEvent]) -> void:
	var t: Vector2i = p.tile()
	var kind: int = state.pickup_at(t)
	if kind == Powerup.Kind.NONE:
		return
	var curse: int = state.pickup_curse_at(t)
	state.clear_pickup(t)
	events.append(SimEvent.pickup_taken(t, p.index, kind, curse))
	_apply_pickup(state, p, kind, curse, t, events)

## Applies one power-up. **A power-up already at its cap is still consumed**
## (M3 brief §3.1): leaving it on the floor would be kinder and is the wrong
## call, because a pickup nobody can pick up is a permanently blocked tile that
## looks like a mistake.
static func _apply_pickup(state: MatchState, p: PlayerState, kind: int, curse: int, t: Vector2i, events: Array[SimEvent]) -> void:
	match kind:
		Powerup.Kind.BOMB:
			p.bomb_capacity = mini(state.balance.max_bomb_capacity, p.bomb_capacity + 1)
		Powerup.Kind.BLAST:
			p.blast_radius = mini(state.balance.max_blast_radius, p.blast_radius + 1)
		Powerup.Kind.SPEED:
			if p.speed_units < state.balance.max_speed_units:
				p.speed_steps += 1
				p.speed_units = _speed_for_steps(state, p.speed_steps)
		Powerup.Kind.KICK:
			p.has_kick = true
		Powerup.Kind.TOSS:
			_set_ability(state, p, Powerup.Kind.TOSS)
		Powerup.Kind.REMOTE:
			_set_ability(state, p, Powerup.Kind.REMOTE)
		Powerup.Kind.JACKPOT:
			p.blast_radius = state.balance.max_blast_radius
		Powerup.Kind.DUD:
			p.curse = curse if curse != Powerup.Curse.NONE else Powerup.Curse.REVERSED
			# A second Dud replaces the first and refreshes the clock.
			p.curse_ticks = state.balance.curse_ticks
			events.append(SimEvent.curse_applied(t, p.index, p.curse, p.curse_ticks))

## Toss and Remote share one slot, so taking one gives up the other. Dropping
## Remote arms whatever it was holding on the board.
static func _set_ability(state: MatchState, p: PlayerState, kind: int) -> void:
	if p.ability == kind:
		return
	if p.ability == Powerup.Kind.REMOTE:
		_arm_orphaned_bombs(state, p.index)
	p.ability = kind

# --- Curses -----------------------------------------------------------------

## Ages every curse, alongside the other countdowns. A curse of N ticks is gone
## exactly N ticks after the tick it was picked up on — the pickup tick spends
## one, the same convention spawn protection has used since M1.
static func _tick_curses(state: MatchState, events: Array[SimEvent]) -> void:
	for p in state.players:
		if p.curse_ticks <= 0:
			continue
		p.curse_ticks -= 1
		if p.curse_ticks > 0:
			continue
		var was: int = p.curse
		p.curse = Powerup.Curse.NONE
		events.append(SimEvent.curse_expired(p.index, was))

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
static func _tick_bombs(state: MatchState, events: Array[SimEvent], remote_fire: PackedByteArray) -> void:
	_fire_remote(state, events, remote_fire)
	_detonate_burning(state, events)
	for i in range(state.bombs.size()):
		var b: Bomb = state.bombs[i]
		if b.exploded or b.remote:
			continue
		if b.fuse_ticks <= 0:
			_detonate_chain(state, i, events)
	_slide_bombs(state, events)
	for b in state.bombs:
		# A Remote bomb does not age, so losing Remote hands it a full fuse
		# rather than an expired one.
		if not b.exploded and not b.remote:
			b.fuse_ticks -= 1
	_reap_bombs(state)

## A bomb sitting in live fire goes off, credited to the flame's owner. In M1
## this could not arise — a ray that lights a tile also chains the bomb on it —
## so this only ever fires for a bomb that *arrived* on a burning tile: tossed
## there, or dropped there by a spawn-protected player standing in a blast.
static func _detonate_burning(state: MatchState, events: Array[SimEvent]) -> void:
	for i in range(state.bombs.size()):
		var b: Bomb = state.bombs[i]
		if b.exploded:
			continue
		var owner: int = state.flame_owner_at(b.tile)
		if owner >= 0:
			_detonate_chain(state, i, events, owner)

## Resolves one detonation and every bomb it sets off, breadth-first over a
## queue of bomb indices. Iterative rather than recursive so a forty-bomb chain
## cannot blow the stack, and so the order is obvious rather than emergent.
##
## Flame ownership propagates from **whoever started the chain**: set off
## someone else's bomb and the kills are yours (M1 brief §6.2; game design §5.2
## was amended to match). `forced_owner` is for the one case where the starter is
## not a bomb's owner at all — a bomb that slid into somebody else's fire.
##
## **Crate drops are rolled after the whole chain has resolved**, not as each
## crate breaks. Otherwise a second ray of the same chain reaching the same tile
## would burn off the drop the first one just made, and a single explosion would
## eat its own reward.
static func _detonate_chain(state: MatchState, root: int, events: Array[SimEvent], forced_owner: int = MatchState.NO_OWNER) -> void:
	var chain_owner: int = state.bombs[root].owner if forced_owner == MatchState.NO_OWNER else forced_owner
	var broken: Array[Vector2i] = []
	var queue: PackedInt32Array = PackedInt32Array([root])
	var qi: int = 0
	while qi < queue.size():
		var bi: int = queue[qi]
		qi += 1
		var b: Bomb = state.bombs[bi]
		if b.exploded:
			continue
		b.exploded = true
		b.stop_sliding()
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
					broken.append(t)
					break                      # exactly one crate per direction
				_lay_flame(state, t, chain_owner, events)
				var other: int = state.bomb_index_at(t)
				if other >= 0 and not state.bombs[other].exploded and not queue.has(other):
					queue.append(other)

	for t in broken:
		_roll_crate_drop(state, t, events)

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
		_lose_kit(state, p, t, events)

## Kit loss on death (game design §6.1, M3 brief §4.5). The most important
## balance dial in the game, and therefore one number: `kit_loss_permille`.
##
## Stacking upgrades keep a fraction of whatever was **above the starting
## loadout** — halving from zero rather than from the start would take a player's
## base bomb away. Abilities go whole. The curse goes and scatters nothing:
## dropping a Dud where you died would be a gift to whoever killed you, in the
## shape of a trap.
static func _lose_kit(state: MatchState, p: PlayerState, died_at: Vector2i, events: Array[SimEvent]) -> void:
	var keep_permille: int = clampi(1000 - state.balance.kit_loss_permille, 0, 1000)
	var lost: Array[int] = []

	var extra_bombs: int = maxi(0, p.bomb_capacity - state.balance.start_bomb_capacity)
	var keep_bombs: int = extra_bombs * keep_permille / 1000
	for _i in range(extra_bombs - keep_bombs):
		lost.append(Powerup.Kind.BOMB)
	p.bomb_capacity = state.balance.start_bomb_capacity + keep_bombs

	var extra_blast: int = maxi(0, p.blast_radius - state.balance.start_blast_radius)
	var keep_blast: int = extra_blast * keep_permille / 1000
	for _i in range(extra_blast - keep_blast):
		lost.append(Powerup.Kind.BLAST)
	p.blast_radius = state.balance.start_blast_radius + keep_blast

	var steps: int = maxi(0, p.speed_steps)
	var keep_steps: int = steps * keep_permille / 1000
	for _i in range(steps - keep_steps):
		lost.append(Powerup.Kind.SPEED)
	p.speed_steps = keep_steps
	p.speed_units = _speed_for_steps(state, keep_steps)

	if p.has_kick:
		p.has_kick = false
		lost.append(Powerup.Kind.KICK)
	if Powerup.is_ability(p.ability):
		var was: int = p.ability
		p.ability = Powerup.Kind.NONE
		if was == Powerup.Kind.REMOTE:
			_arm_orphaned_bombs(state, p.index)
		lost.append(was)
	if p.curse != Powerup.Curse.NONE:
		p.curse = Powerup.Curse.NONE
		p.curse_ticks = 0

	_scatter(state, died_at, lost, p.index, events)

## Scatters lost items onto free tiles around the body, nearest first. **No PRNG
## at all** — candidates are ordered by Manhattan distance and then by tile
## index, so a round's random sequence does not depend on how many people died
## in it.
##
## A candidate must have no flame on it, which matters more than it sounds: the
## death tile is on fire by definition, and scattering into the blast that just
## killed you would evaporate the whole kit before anyone could see it. Items
## with nowhere to land inside `scatter_radius` are lost.
static func _scatter(state: MatchState, from: Vector2i, lost: Array[int], from_player: int, events: Array[SimEvent]) -> void:
	if lost.is_empty():
		return
	var candidates: Array[Vector2i] = _scatter_candidates(state, from)
	var next: int = 0
	for kind in lost:
		while next < candidates.size() and not _can_hold_pickup(state, candidates[next]):
			next += 1
		if next >= candidates.size():
			return
		var t: Vector2i = candidates[next]
		next += 1
		state.set_pickup(t, kind, Powerup.Curse.NONE)
		events.append(SimEvent.pickup_spawned(t, kind, Powerup.Curse.NONE, from_player))

## Tiles around `from`, ordered by Manhattan distance and then by tile index.
## Includes `from` itself, which the flame filter will normally reject.
static func _scatter_candidates(state: MatchState, from: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in range(0, maxi(0, state.balance.scatter_radius) + 1):
		# y ascending, then x ascending, which is tile-index order within a ring.
		for dy in range(-r, r + 1):
			var dx: int = r - absi(dy)
			if dx == 0:
				out.append(from + Vector2i(0, dy))
			else:
				out.append(from + Vector2i(-dx, dy))
				out.append(from + Vector2i(dx, dy))
	return out

## Can a pickup sit here? Floor, and nothing else already on it — including no
## flame, for the reason in `_scatter`.
static func _can_hold_pickup(state: MatchState, t: Vector2i) -> bool:
	if not state.arena.in_bounds(t):
		return false
	if state.arena.at(t) != Arena.Tile.FLOOR:
		return false
	if state.has_pickup_at(t):
		return false
	if state.flame_ttl_at(t) > 0:
		return false
	return state.bomb_index_at(t) < 0

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

# --- Crate regeneration -----------------------------------------------------

## A wave of crates every `crate_regen_ticks` (game design §6.2, M3 brief §5).
## This exists because a two-minute round with four players and growing blast
## radii strips the arena bare in about a minute, and a bare arena is one where
## nobody can rebuild after a death — the exact opposite of what kit loss is for.
##
## `crate_regen_ticks = 0` switches it off, which is both a test affordance and
## the fallback the design names if regeneration plays as interference.
static func _tick_crate_regen(state: MatchState, events: Array[SimEvent]) -> void:
	if state.balance.crate_regen_ticks <= 0:
		return
	if state.regen_ticks_left > 0:
		state.regen_ticks_left -= 1
	if state.regen_ticks_left > 0:
		return
	state.regen_ticks_left = state.balance.crate_regen_ticks
	_regen_wave(state, events)

## One wave. **Candidates are filtered before any draw** (technical design §3a),
## so the number of PRNG calls cannot depend on how many tiles were rejected —
## which is the difference between a reproducible round and a desync nobody can
## explain.
static func _regen_wave(state: MatchState, events: Array[SimEvent]) -> void:
	var cap: int = state.crate_cap()
	var count: int = state.arena.count_of(Arena.Tile.CRATE)
	if count >= cap:
		return                 # nothing to do, and no reason to scan the grid
	var candidates: Array[Vector2i] = _regen_candidates(state)
	for _i in range(state.balance.crate_regen_wave):
		if count >= cap or candidates.is_empty():
			return
		# next_index, not next_below: the last free tile in a filling arena is a
		# one-entry list, and a draw that quietly does not happen there would
		# shift every value after it.
		var pick: int = state.rng.next_index(candidates.size())
		var t: Vector2i = candidates[pick]
		candidates.remove_at(pick)
		state.arena.set_at(t, Arena.Tile.CRATE)
		# The never-seal-a-player-in guarantee. A rejected tile is **not**
		# retried: a retry would spend a second draw on one candidate and make the
		# draw count depend on the rejection, which is the thing §3a forbids.
		if _seals_a_player(state, t):
			state.arena.set_at(t, Arena.Tile.FLOOR)
			continue
		count += 1
		events.append(SimEvent.crate_spawned(t))

## Every tile a crate could legally land on, in index order. The exclusions are
## game design §6.2's, and the adjacency rule is the one that stops a crate
## landing in somebody's face.
static func _regen_candidates(state: MatchState) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(1, state.arena.h - 1):
		for x in range(1, state.arena.w - 1):
			var t: Vector2i = Vector2i(x, y)
			if state.arena.at(t) != Arena.Tile.FLOOR:
				continue
			if state.flame_ttl_at(t) > 0:
				continue
			if state.bomb_index_at(t) >= 0:
				continue
			if state.has_pickup_at(t):
				continue
			if _near_living_player(state, t):
				continue
			out.append(t)
	return out

## On, or orthogonally next to, a living player.
static func _near_living_player(state: MatchState, t: Vector2i) -> bool:
	for p in state.players:
		if not p.active or not p.alive:
			continue
		var pt: Vector2i = p.tile()
		if absi(pt.x - t.x) + absi(pt.y - t.y) <= 1:
			return true
	return false

## Would the board as it now stands leave a living player with fewer than
## `min_escape_tiles` to move around in?
static func _seals_a_player(state: MatchState, _placed: Vector2i) -> bool:
	var limit: int = maxi(1, state.balance.min_escape_tiles)
	for p in state.players:
		if not p.active or not p.alive:
			continue
		if _reachable_free(state, p.tile(), limit) < limit:
			return true
	return false

## Counts free tiles reachable from `from`, stopping at `limit`. Bombs are not
## obstacles here: they are temporary, and a player boxed in by a bomb they are
## standing next to is a normal and survivable situation.
static func _reachable_free(state: MatchState, from: Vector2i, limit: int) -> int:
	if state.arena.is_solid(from):
		return 0
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(state.arena.w * state.arena.h)
	seen.fill(0)
	var queue: Array[Vector2i] = [from]
	seen[state.arena.index(from)] = 1
	var found: int = 0
	var qi: int = 0
	while qi < queue.size():
		var t: Vector2i = queue[qi]
		qi += 1
		found += 1
		if found >= limit:
			return found
		for d in DIRS:
			var nt: Vector2i = t + d
			if not state.arena.in_bounds(nt):
				continue
			var idx: int = state.arena.index(nt)
			if seen[idx] != 0:
				continue
			seen[idx] = 1
			if state.arena.is_solid(nt):
				continue
			queue.append(nt)
	return found

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
