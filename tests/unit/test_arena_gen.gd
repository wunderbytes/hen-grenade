extends TestCase
## Arena generation: the lattice, four-way mirror symmetry, spawn clearances,
## and seed reproducibility. See docs/milestone-1-brief.md §4.1 and
## docs/game-design.md §4.

var def: ArenaDef
var arena: Arena

func before_each() -> void:
	def = ArenaDef.new()
	arena = Arena.generate(def, SimRng.new(2024))

func test_border_is_indestructible() -> void:
	for x in range(arena.w):
		assert_eq(arena.at(Vector2i(x, 0)), Arena.Tile.HARD, "top border at x=%d" % x)
		assert_eq(arena.at(Vector2i(x, arena.h - 1)), Arena.Tile.HARD, "bottom border at x=%d" % x)
	for y in range(arena.h):
		assert_eq(arena.at(Vector2i(0, y)), Arena.Tile.HARD, "left border at y=%d" % y)
		assert_eq(arena.at(Vector2i(arena.w - 1, y)), Arena.Tile.HARD, "right border at y=%d" % y)

func test_pillar_lattice() -> void:
	# Every interior tile with both coordinates even is a pillar, and no other
	# interior tile is. This lattice is what makes blast lines readable.
	for y in range(1, arena.h - 1):
		for x in range(1, arena.w - 1):
			var t: Vector2i = Vector2i(x, y)
			if x % 2 == 0 and y % 2 == 0:
				assert_eq(arena.at(t), Arena.Tile.HARD, "expected a pillar at %s" % t)
			else:
				assert_ne(arena.at(t), Arena.Tile.HARD, "unexpected hard block at %s" % t)

func test_interior_is_odd_by_odd() -> void:
	# The lattice only mirrors correctly with an odd interior in both axes; this
	# is why the arena is 25 x 15 and not the originally briefed 25 x 16.
	assert_eq((arena.w - 2) % 2, 1, "interior width must be odd")
	assert_eq((arena.h - 2) % 2, 1, "interior height must be odd")

func test_four_way_mirror_symmetry() -> void:
	for y in range(arena.h):
		for x in range(arena.w):
			var t: Vector2i = Vector2i(x, y)
			var mx: Vector2i = Vector2i(arena.w - 1 - x, y)
			var my: Vector2i = Vector2i(x, arena.h - 1 - y)
			var mxy: Vector2i = Vector2i(arena.w - 1 - x, arena.h - 1 - y)
			assert_eq(arena.at(t), arena.at(mx), "horizontal mirror broken at %s" % t)
			assert_eq(arena.at(t), arena.at(my), "vertical mirror broken at %s" % t)
			assert_eq(arena.at(t), arena.at(mxy), "diagonal mirror broken at %s" % t)

func test_spawn_clearances_are_free() -> void:
	for spawn in def.spawn_tiles:
		assert_eq(arena.at(spawn), Arena.Tile.FLOOR, "spawn %s is not free" % spawn)
		var open_neighbours: int = 0
		for d in Sim.DIRS:
			var n: Vector2i = spawn + d
			assert_ne(arena.at(n), Arena.Tile.CRATE, "crate beside spawn %s at %s" % [spawn, n])
			if arena.at(n) == Arena.Tile.FLOOR:
				open_neighbours += 1
		# An odd/odd corner spawn always has two open directions in the lattice;
		# fewer would mean a player could start walled in.
		assert_ge(open_neighbours, 2, "spawn %s has only %d ways out" % [spawn, open_neighbours])

func test_respawn_tiles_are_free_and_never_pillars() -> void:
	for t in def.respawn_tiles:
		assert_false(arena.is_lattice_pillar(t), "respawn tile %s is a pillar" % t)
		assert_eq(arena.at(t), Arena.Tile.FLOOR, "respawn tile %s is not free" % t)

func test_respawn_tiles_are_in_index_order() -> void:
	# Respawn tie-breaking is documented as "by tile index", which is only true
	# of the designated list if the list itself is in index order.
	var previous: int = -1
	for t in def.respawn_tiles:
		var index: int = t.y * def.grid_w + t.x
		assert_gt(index, previous, "respawn tile %s is out of index order" % t)
		previous = index

func test_same_seed_same_arena() -> void:
	var a: Arena = Arena.generate(def, SimRng.new(777))
	var b: Arena = Arena.generate(def, SimRng.new(777))
	assert_eq(a.tiles, b.tiles, "same seed produced different arenas")

func test_different_seed_different_arena() -> void:
	var a: Arena = Arena.generate(def, SimRng.new(777))
	var b: Arena = Arena.generate(def, SimRng.new(778))
	assert_ne(a.tiles, b.tiles, "different seeds produced identical arenas")

func test_crate_density_tracks_permille() -> void:
	var empty_def: ArenaDef = ArenaDef.new()
	empty_def.crate_permille = 0
	assert_eq(Arena.generate(empty_def, SimRng.new(5)).count_of(Arena.Tile.CRATE), 0, "0 permille should place no crates")

	var full_def: ArenaDef = ArenaDef.new()
	full_def.crate_permille = 1000
	var full: Arena = Arena.generate(full_def, SimRng.new(5))
	# Everything eligible becomes a crate except the cleared spawn and respawn
	# tiles, so "full" is the eligible count minus those clearances.
	assert_gt(full.count_of(Arena.Tile.CRATE), 200, "1000 permille should fill the interior")

	var normal: Arena = Arena.generate(def, SimRng.new(5))
	var crates: int = normal.count_of(Arena.Tile.CRATE)
	var eligible: int = full.count_of(Arena.Tile.CRATE)
	# Loose bounds: this is a sanity check on the density knob, not a test of
	# the PRNG's uniformity.
	assert_in_range(crates, eligible * 55 / 100, eligible * 85 / 100, "crate count %d is not ~70%% of %d" % [crates, eligible])

func test_draw_count_is_independent_of_density() -> void:
	# The generator must draw once per eligible tile regardless of what it
	# places. If it ever short-circuits, arenas stop being reproducible across
	# a density change and — worse — any later per-tile filter silently breaks
	# determinism the same way.
	var sparse_def: ArenaDef = ArenaDef.new()
	sparse_def.crate_permille = 0
	var dense_def: ArenaDef = ArenaDef.new()
	dense_def.crate_permille = 1000

	var sparse_rng: SimRng = SimRng.new(31337)
	var dense_rng: SimRng = SimRng.new(31337)
	Arena.generate(sparse_def, sparse_rng)
	Arena.generate(dense_def, dense_rng)
	assert_eq(sparse_rng.state, dense_rng.state, "density changed how many numbers were drawn")

func test_generation_respects_grid_size_from_the_resource() -> void:
	# The sim is written against whatever the resource says; 25 x 15 is a value,
	# not an assumption (technical design §6).
	var small: ArenaDef = ArenaDef.new()
	small.grid_w = 13
	small.grid_h = 11
	small.crate_permille = 500
	small.spawn_tiles = [Vector2i(1, 1), Vector2i(11, 1), Vector2i(1, 9), Vector2i(11, 9)]
	small.respawn_tiles = [Vector2i(1, 1), Vector2i(11, 1), Vector2i(1, 9), Vector2i(11, 9)]
	var a: Arena = Arena.generate(small, SimRng.new(3))
	assert_eq(a.w, 13, "grid width")
	assert_eq(a.h, 11, "grid height")
	assert_eq(a.tiles.size(), 13 * 11, "tile count")
	assert_eq(a.at(Vector2i(2, 2)), Arena.Tile.HARD, "lattice still applies on a smaller grid")
	for y in range(a.h):
		for x in range(a.w):
			assert_eq(a.at(Vector2i(x, y)), a.at(Vector2i(a.w - 1 - x, a.h - 1 - y)), "mirror broken at %d,%d" % [x, y])
