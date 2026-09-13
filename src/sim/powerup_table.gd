class_name PowerupTable
extends Resource
## The drop rate and the weight table from game design §6, as data.
## See docs/milestone-3-brief.md §3.1 and docs/technical-design.md §6.
##
## Named in the technical design since before M1 and real from M3. Retuning the
## economy is editing this file — which is the point, because "how often should a
## Remote turn up" is a playtest question and not a code question.
##
## Weights are plain positive integers, compared as integers, and they do not
## have to add up to anything: the pick is one draw below the total, walked
## against the accumulated weights in Powerup.Kind order. They happen to total
## 100 so they read as percentages.

## How often a destroyed crate leaves something behind, in permille.
## 300 = ~30% (game design §6). Permille rather than a float so the comparison
## is integer, per the determinism contract.
@export var drop_permille: int = 300

# --- Weights ------------------------------------------------------------------
## The bread and butter: always meaningful, never game-ending on their own.
@export var weight_bomb: int = 26
@export var weight_blast: int = 26
@export var weight_speed: int = 16
## Kick and Toss change how you think about space.
@export var weight_kick: int = 12
@export var weight_toss: int = 7
## Remote is the skill pick — highest ceiling, easiest way to blow yourself up.
@export var weight_remote: int = 5
@export var weight_jackpot: int = 2
## The Dud exists so that hoovering up every drop carries risk.
@export var weight_dud: int = 6

## Weights in Powerup.Kind order, which is the order the pick walks. Built on
## every call rather than cached: a Resource's fields are editable at runtime and
## a stale cache here would be a desync nobody could see.
func weights() -> PackedInt32Array:
	return PackedInt32Array([
		maxi(0, weight_bomb),
		maxi(0, weight_blast),
		maxi(0, weight_speed),
		maxi(0, weight_kick),
		maxi(0, weight_toss),
		maxi(0, weight_remote),
		maxi(0, weight_jackpot),
		maxi(0, weight_dud),
	])

func total_weight() -> int:
	var total: int = 0
	for w in weights():
		total += w
	return total

## Resolves one weighted draw into a Kind. **Consumes exactly one draw**, always,
## which is half of brief §2 Rule A; the caller owns the other two.
##
## Returns NONE only if the table has been tuned to all zeroes, which is a
## legitimate way to switch drops off entirely.
func pick(rng: SimRng) -> int:
	var total: int = total_weight()
	# next_index rather than next_below: a table tuned down to a single power-up
	# has a total of 1, and next_below's short-circuit would spend no draw at all.
	var roll: int = rng.next_index(total)
	if total <= 0:
		return Powerup.Kind.NONE
	var acc: int = 0
	var w: PackedInt32Array = weights()
	for i in range(w.size()):
		acc += w[i]
		if roll < acc:
			return Powerup.Kind.BOMB + i       # Kind is contiguous from BOMB
	return Powerup.Kind.DUD

## Hashed into the replay's rules fingerprint alongside Balance: a re-weighted
## table changes what a recorded round produces just as surely as a retuned fuse
## does (brief §7).
func fingerprint() -> int:
	var h: int = SimHash.start()
	h = SimHash.mix_int(h, drop_permille)
	for w in weights():
		h = SimHash.mix_int(h, w)
	return h
