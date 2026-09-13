class_name Powerup
## The power-up vocabulary: what can drop, and what a Dud does to you.
## See docs/milestone-3-brief.md §3 and §4.4, and docs/game-design.md §6.
##
## Enums and pure helpers only. The weights live in PowerupTable (a Resource, so
## a designer can retune them), the effects live in Sim, and the colours live in
## the view. This file is the shared names all three agree on.

## What a pickup is. NONE is the "nothing on this tile" value in
## MatchState.pickup_kind, which is why it has to be 0 and why the grid can be a
## PackedByteArray.
##
## The order is part of the determinism contract: PowerupTable walks the weights
## in this order to resolve a draw, so inserting a kind in the middle changes
## what every existing seed produces.
enum Kind {
	NONE = 0,
	BOMB = 1,
	BLAST = 2,
	SPEED = 3,
	KICK = 4,
	TOSS = 5,
	REMOTE = 6,
	JACKPOT = 7,
	DUD = 8,
}

## The four Dud variants (game design §6). Drawn when the crate is destroyed, not
## when the pickup is collected, so that a crate destruction always costs the
## same number of PRNG draws (brief §2, Rule A).
enum Curse {
	NONE = 0,
	REVERSED = 1,        # the frame's direction is inverted
	BOMB_SPAM = 2,       # a bomb is attempted every tick, not on the edge
	TINY_BLAST = 3,      # effective blast radius 1
	FAST = 4,            # effective speed pinned to the cap
}

## How many real variants there are, for the draw in PowerupTable.
const CURSE_COUNT: int = 4

## Toss and Remote are mutually exclusive and share one slot on the player,
## because there is one action button (brief §1, §4.3).
static func is_ability(kind: int) -> bool:
	return kind == Kind.TOSS or kind == Kind.REMOTE

## Bombs, blast and speed: the ones that stack and are therefore the ones kit
## loss halves rather than removes (game design §6.1).
static func is_stacking(kind: int) -> bool:
	return kind == Kind.BOMB or kind == Kind.BLAST or kind == Kind.SPEED

## Short enough for a 140 px HUD card at an 8 px font.
static func short_name(kind: int) -> String:
	match kind:
		Kind.BOMB: return "BOMB"
		Kind.BLAST: return "BLAST"
		Kind.SPEED: return "SPEED"
		Kind.KICK: return "KICK"
		Kind.TOSS: return "TOSS"
		Kind.REMOTE: return "REMOTE"
		Kind.JACKPOT: return "JACKPOT"
		Kind.DUD: return "DUD"
	return "-"

static func curse_name(curse: int) -> String:
	match curse:
		Curse.REVERSED: return "REVERSED"
		Curse.BOMB_SPAM: return "SPAM"
		Curse.TINY_BLAST: return "TINY"
		Curse.FAST: return "GLUED"
	return "-"
