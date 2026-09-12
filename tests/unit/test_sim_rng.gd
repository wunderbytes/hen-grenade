extends TestCase
## Pins SimRng's contract: reproducible from a seed, one state advance per draw,
## and a sequence that belongs to our source rather than to the engine's.
## See docs/milestone-1-brief.md §2.

func test_same_seed_same_sequence() -> void:
	var a: SimRng = SimRng.new(4242)
	var b: SimRng = SimRng.new(4242)
	for i in range(64):
		assert_eq(a.next_u32(), b.next_u32(), "draw %d diverged for identical seeds" % i)

func test_different_seed_different_sequence() -> void:
	var a: SimRng = SimRng.new(1)
	var b: SimRng = SimRng.new(2)
	var same: int = 0
	for _i in range(64):
		if a.next_u32() == b.next_u32():
			same += 1
	# The warm-up in seed_from exists precisely so that seeds 1 and 2 do not
	# produce correlated openings; if this ever trips, the warm-up went away.
	assert_lt(same, 4, "seeds 1 and 2 produced suspiciously similar sequences")

func test_state_is_never_zero() -> void:
	# xorshift is absorbing at zero: once there, every future draw is zero.
	var r: SimRng = SimRng.new(0)
	assert_ne(r.state, 0, "seeding with 0 must escape the zero state")
	for i in range(256):
		assert_ne(r.next_u32(), 0, "draw %d returned 0" % i)

func test_next_below_bounds() -> void:
	var r: SimRng = SimRng.new(7)
	for _i in range(2000):
		assert_in_range(r.next_below(1000), 0, 999, "next_below(1000) out of range")
	assert_eq(r.next_below(1), 0, "next_below(1) is always 0")
	assert_eq(r.next_below(0), 0, "next_below(0) is defined as 0")

func test_next_below_draws_exactly_once() -> void:
	# The crate generator's determinism depends on the draw count being
	# independent of the values drawn — so no rejection sampling, ever.
	var r: SimRng = SimRng.new(99)
	var probe: SimRng = SimRng.new(99)
	for _i in range(100):
		r.next_below(1000)
		probe.next_u32()
	assert_eq(r.state, probe.state, "next_below consumed more than one draw")

func test_next_range_bounds() -> void:
	var r: SimRng = SimRng.new(11)
	for _i in range(500):
		assert_in_range(r.next_range(5, 9), 5, 9, "next_range(5,9) out of range")
	assert_eq(r.next_range(3, 3), 3, "degenerate range returns its bound")
	assert_eq(r.next_range(8, 2), 8, "inverted range returns lo")

func test_clone_is_independent() -> void:
	var a: SimRng = SimRng.new(555)
	a.next_u32()
	var b: SimRng = a.clone()
	assert_eq(a.state, b.state, "clone starts from the same state")
	for i in range(16):
		assert_eq(a.next_u32(), b.next_u32(), "clone diverged at draw %d" % i)
	b.next_u32()
	assert_ne(a.state, b.state, "advancing the clone must not advance the original")

## A regression pin on the actual numbers. Reproducibility within one run is not
## enough: if the algorithm itself is ever "tidied up", every committed golden
## replay silently becomes wrong, and this is the test that says so first.
func test_sequence_is_pinned() -> void:
	var r: SimRng = SimRng.new(12345)
	var h: int = SimHash.start()
	for _i in range(256):
		h = SimHash.mix_int(h, r.next_u32())
	assert_eq(SimHash.to_hex(h), "04d41e10", "the RNG sequence for seed 12345 changed")
