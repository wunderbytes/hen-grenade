class_name SimEvent
## Something the simulation did this tick, for the view and (from M4) audio to
## react to. See docs/milestone-1-brief.md §7.
##
## A flat value type rather than a class hierarchy: the view switches on `kind`,
## replays never store events, and five fields cover every case in M1 without
## anyone having to cast. Field meaning depends on `kind` and is documented on
## each constructor below.
##
## Events are **not** part of the determinism contract — the fingerprint covers
## state, not the event log. They are emitted in the tick order of M1 brief §6,
## so they are stable in practice, but a golden replay passing says nothing
## about them.

enum Kind {
	BOMB_PLACED,
	BOMB_EXPLODED,
	CRATE_DESTROYED,
	FLAME_LIT,
	PLAYER_DIED,
	PLAYER_RESPAWNED,
	ROUND_ENDED,
	# --- M3 ---
	CRATE_SPAWNED,
	PICKUP_SPAWNED,
	PICKUP_TAKEN,
	PICKUP_DESTROYED,
	BOMB_KICKED,
	BOMB_TOSSED,
	CURSE_APPLIED,
	CURSE_EXPIRED,
}

var kind: Kind = Kind.FLAME_LIT
var tile: Vector2i = Vector2i.ZERO
## The subject: who placed / died / respawned, or the flame owner.
var player: int = -1
## The counterparty: the killer, or the chain starter. -1 when not applicable.
var other: int = -1
## Generic payload; see each constructor.
var value: int = 0
## Where a bomb went, for the two M3 events that move one. (-1, -1) otherwise.
## A sixth field rather than an encoded tile index, because the alternative is a
## view that has to know the grid width to read an event.
var to_tile: Vector2i = Vector2i(-1, -1)

static func _make(p_kind: Kind, p_tile: Vector2i, p_player: int, p_other: int, p_value: int) -> SimEvent:
	var e: SimEvent = SimEvent.new()
	e.kind = p_kind
	e.tile = p_tile
	e.player = p_player
	e.other = p_other
	e.value = p_value
	return e

## `player` dropped a bomb on `tile`; `value` is its blast radius.
static func bomb_placed(tile: Vector2i, player: int, radius: int) -> SimEvent:
	return _make(Kind.BOMB_PLACED, tile, player, -1, radius)

## A bomb owned by `player` went off on `tile`; `other` is the chain starter
## (== player when it went off on its own fuse); `value` is its radius.
static func bomb_exploded(tile: Vector2i, player: int, chain_owner: int, radius: int) -> SimEvent:
	return _make(Kind.BOMB_EXPLODED, tile, player, chain_owner, radius)

## A crate on `tile` was destroyed by a blast owned by `player`.
static func crate_destroyed(tile: Vector2i, player: int) -> SimEvent:
	return _make(Kind.CRATE_DESTROYED, tile, player, -1, 0)

## A flame owned by `player` appeared on `tile` (only on the tick it lights,
## not on refresh); `value` is its lifetime in ticks.
static func flame_lit(tile: Vector2i, player: int, ttl: int) -> SimEvent:
	return _make(Kind.FLAME_LIT, tile, player, -1, ttl)

## `player` died on `tile`, killed by the flame owner `other`. A suicide has
## `other == player`.
static func player_died(tile: Vector2i, player: int, killer: int) -> SimEvent:
	return _make(Kind.PLAYER_DIED, tile, player, killer, 0)

## `player` came back on `tile` with `value` ticks of spawn protection.
static func player_respawned(tile: Vector2i, player: int, protect_ticks: int) -> SimEvent:
	return _make(Kind.PLAYER_RESPAWNED, tile, player, -1, protect_ticks)

## The clock hit zero. `player` is the winning slot, or -1 for a draw.
static func round_ended(winner: int) -> SimEvent:
	return _make(Kind.ROUND_ENDED, Vector2i.ZERO, winner, -1, 0)

# --- M3 ---------------------------------------------------------------------

## A regeneration wave landed a crate on `tile` (M3 brief §5). The view updates
## that one tilemap cell, exactly as it does for CRATE_DESTROYED.
static func crate_spawned(tile: Vector2i) -> SimEvent:
	return _make(Kind.CRATE_SPAWNED, tile, -1, -1, 0)

## A pickup of `value` (Powerup.Kind) appeared on `tile`. `player` is who lost it
## in a kit scatter, or -1 for a crate drop; `other` is the Powerup.Curse variant
## for a Dud and 0 otherwise.
static func pickup_spawned(tile: Vector2i, kind_value: int, curse: int, from_player: int) -> SimEvent:
	return _make(Kind.PICKUP_SPAWNED, tile, from_player, curse, kind_value)

## `player` walked onto the pickup of `value` (Powerup.Kind) on `tile`; `other`
## is the curse variant for a Dud.
static func pickup_taken(tile: Vector2i, player: int, kind_value: int, curse: int) -> SimEvent:
	return _make(Kind.PICKUP_TAKEN, tile, player, curse, kind_value)

## A blast owned by `player` burnt the pickup of `value` off `tile`.
static func pickup_destroyed(tile: Vector2i, player: int, kind_value: int) -> SimEvent:
	return _make(Kind.PICKUP_DESTROYED, tile, player, -1, kind_value)

## `player` kicked the bomb on `tile`; `to_tile` is the tile it will step to next.
static func bomb_kicked(tile: Vector2i, to: Vector2i, player: int) -> SimEvent:
	var e: SimEvent = _make(Kind.BOMB_KICKED, tile, player, -1, 0)
	e.to_tile = to
	return e

## `player` lobbed a bomb from `tile` to `to_tile`. The flight is instantaneous
## in the simulation; the arc is the view's business (M3 brief §4.2).
static func bomb_tossed(tile: Vector2i, to: Vector2i, player: int) -> SimEvent:
	var e: SimEvent = _make(Kind.BOMB_TOSSED, tile, player, -1, 0)
	e.to_tile = to
	return e

## `player` picked up a Dud: `value` is the Powerup.Curse variant and `other` its
## duration in ticks.
static func curse_applied(tile: Vector2i, player: int, curse: int, ticks: int) -> SimEvent:
	return _make(Kind.CURSE_APPLIED, tile, player, ticks, curse)

## `player`'s curse ran out. `value` is the variant that ended.
static func curse_expired(player: int, curse: int) -> SimEvent:
	return _make(Kind.CURSE_EXPIRED, Vector2i.ZERO, player, -1, curse)

func _to_string() -> String:
	return "SimEvent(%s tile=%s player=%d other=%d value=%d)" % [Kind.keys()[kind], str(tile), player, other, value]
