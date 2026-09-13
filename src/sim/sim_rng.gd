class_name SimRng
## The simulation's only source of randomness: xorshift32, masked to 32 bits.
## See docs/milestone-1-brief.md §2 and docs/technical-design.md §2.
##
## Hand-rolled rather than using RandomNumberGenerator so the sequence is pinned
## to this file. Godot's PRNG is deterministic for a given engine version, but a
## point release changing its internals would invalidate every golden replay for
## reasons that have nothing to do with our code.
##
## MatchState owns exactly one of these and every draw goes through it, in a
## fixed order. Cloning one (for a bot's what-if search in M5) must use clone(),
## never a shared reference.

const MASK: int = 0xFFFFFFFF

## The full generator state. Exposed because MatchState.fingerprint() hashes it:
## two states that agree on the board but disagree on the RNG have diverged.
var state: int = 1

func _init(p_seed: int = 1) -> void:
	seed_from(p_seed)

func seed_from(p_seed: int) -> void:
	state = p_seed & MASK
	# xorshift dies at zero; any non-zero constant will do to escape it.
	if state == 0:
		state = 0x9E3779B9
	# Warm-up. xorshift32's first few outputs from a small state are visibly
	# correlated, which would make seeds 1, 2 and 3 generate similar arenas.
	for _i in range(4):
		next_u32()

func clone() -> SimRng:
	var copy: SimRng = SimRng.new()
	copy.state = state
	return copy

## Next raw 32-bit value. Always exactly one state advance per call — the whole
## determinism story depends on the draw count being predictable.
func next_u32() -> int:
	var x: int = state
	x ^= (x << 13) & MASK
	x ^= x >> 17
	x ^= (x << 5) & MASK
	state = x & MASK
	return state

## Integer in [0, n). Uses a plain modulo, and that is deliberate: rejection
## sampling would make the number of draws depend on the values drawn, which is
## exactly the property the crate generator must not have.
##
## The resulting bias is on the order of n / 2^32 — for n = 1000 that is one part
## in four million, which is not a fairness concern for crate placement.
func next_below(n: int) -> int:
	if n <= 1:
		return 0
	return next_u32() % n

## Index into a list of `n` items, **always spending exactly one draw** — which
## is the difference from next_below(), whose n <= 1 short-circuit spends none.
##
## Use this wherever the *number* of draws is part of the determinism contract
## rather than just the values: the power-up table's weighted pick, and the crate
## regeneration wave. Both can legitimately face a one-entry list — a table tuned
## to a single power-up, or an arena down to its last candidate tile — and a draw
## that quietly does not happen would shift every subsequent value.
func next_index(n: int) -> int:
	var raw: int = next_u32()
	return 0 if n <= 1 else raw % n

## Integer in [lo, hi], inclusive.
func next_range(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + next_below(hi - lo + 1)

func next_bool() -> bool:
	return (next_u32() & 1) == 1
