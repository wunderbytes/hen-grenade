extends TestCase
## Cosmetic catalog, wrap, tint, and slot reset. See docs/milestone-3.6-brief.md.
##
## Looks are view-only. This suite must not touch MatchState.
## Preload rather than class_name: `--script` may run before `--import` registers
## the global (technical design A.1 / A.2).

const Art: GDScript = preload("res://src/view/character_art.gd")

func test_wrap_index_cycles_both_ways() -> void:
	assert_eq(Art.wrap_index(0, 4), 0)
	assert_eq(Art.wrap_index(4, 4), 0)
	assert_eq(Art.wrap_index(-1, 4), 3)
	assert_eq(Art.wrap_index(5, 4), 1)
	assert_eq(Art.wrap_index(0, 0), 0, "empty modulus is a no-op, not a crash")

func test_option_names_are_mechanical() -> void:
	assert_eq(Art.option_name(Art.Layer.HEAD, 0), "NONE")
	assert_eq(Art.option_name(Art.Layer.HEAD, 1), "CAP")
	assert_eq(Art.option_name(Art.Layer.CLOTHES, 0), "TUNIC")
	assert_eq(Art.option_name(Art.Layer.SHOES, 3), "PACK")
	assert_eq(Art.option_name(Art.Layer.HEAD, 4), "NONE", "names wrap with the index")

func test_layer_and_option_cycle_on_a_slot() -> void:
	var slot: PlayerSlot = PlayerSlot.new(0)
	slot.cycle_option(1)
	assert_eq(slot.hat, 1, "default layer is HEAD")
	slot.cycle_layer(1)
	assert_eq(slot.customize_layer, Art.Layer.CLOTHES)
	slot.cycle_option(1)
	assert_eq(slot.clothes, 1)
	assert_eq(slot.hat, 1, "cycling clothes must not move the hat")
	slot.cycle_layer(-1)
	slot.cycle_option(-2)
	assert_eq(slot.hat, 3, "left from CAP wraps to BALL")
	slot.cycle_layer(-1)
	assert_eq(slot.customize_layer, Art.Layer.SHOES, "up from HEAD wraps to SHOES")

func test_clear_resets_the_outfit() -> void:
	var slot: PlayerSlot = PlayerSlot.new(1)
	slot.hat = 2
	slot.clothes = 3
	slot.shoes = 1
	slot.customize_layer = Art.Layer.SHOES
	slot.clear()
	assert_eq(slot.hat, 0)
	assert_eq(slot.clothes, 0)
	assert_eq(slot.shoes, 0)
	assert_eq(slot.customize_layer, 0)

func test_bot_look_is_derived_from_slot_index() -> void:
	var a: PlayerSlot = PlayerSlot.new(0)
	var b: PlayerSlot = PlayerSlot.new(1)
	a.apply_bot_look()
	b.apply_bot_look()
	assert_ne(a.hat, b.hat)
	assert_eq(a.hat, 0)
	assert_eq(b.hat, 1)

func test_shade_stays_on_the_slot_hue() -> void:
	for i in range(C.PLAYER_COLORS.size()):
		var base: Color = C.PLAYER_COLORS[i]
		var dark: Color = Art.shade(base, 0.62)
		var light: Color = Art.shade(base, 1.15)
		assert_ne(dark, base)
		for j in range(C.PLAYER_COLORS.size()):
			if i == j:
				continue
			assert_ne(dark, C.PLAYER_COLORS[j], "P%d dark overlay must not equal P%d" % [i + 1, j + 1])
			assert_ne(light, C.PLAYER_COLORS[j], "P%d light overlay must not equal P%d" % [i + 1, j + 1])
		assert_true(dark.r <= base.r + 0.001 and dark.g <= base.g + 0.001 and dark.b <= base.b + 0.001)
