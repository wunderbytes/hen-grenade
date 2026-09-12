extends TestCase
## Vertical menu selection. See docs/milestone-2-brief.md §8.

const UP := InputFrame.Dir.UP
const DOWN := InputFrame.Dir.DOWN
const NONE := InputFrame.Dir.NONE

var cursor: MenuCursor = null

func before_each() -> void:
	cursor = MenuCursor.new(3)

func test_starts_at_the_top() -> void:
	assert_eq(cursor.index, 0)
	assert_eq(cursor.count, 3)

func test_down_and_up_move_one_step() -> void:
	assert_true(cursor.update(DOWN), "a fresh press moves")
	assert_eq(cursor.index, 1)
	cursor.update(NONE)
	cursor.update(UP)
	assert_eq(cursor.index, 0)

func test_a_held_direction_does_not_repeat() -> void:
	# Three items read by four people on a shared screen: a stick that scrolls is
	# how you quit to the lobby by accident.
	cursor.update(DOWN)
	for _i in range(30):
		assert_false(cursor.update(DOWN), "holding is not pressing")
	assert_eq(cursor.index, 1)

func test_release_and_press_again_moves_again() -> void:
	cursor.update(DOWN)
	cursor.update(NONE)
	assert_true(cursor.update(DOWN))
	assert_eq(cursor.index, 2)

func test_reversing_without_releasing_still_moves() -> void:
	cursor.update(DOWN)
	assert_true(cursor.update(UP), "a different direction is a new intention")
	assert_eq(cursor.index, 0)

func test_wraps_both_ways() -> void:
	cursor.update(UP)
	assert_eq(cursor.index, 2, "up from the top lands on the bottom")
	cursor.update(NONE)
	cursor.update(DOWN)
	assert_eq(cursor.index, 0, "and back round")

func test_horizontal_input_is_ignored() -> void:
	assert_false(cursor.update(InputFrame.Dir.LEFT))
	assert_false(cursor.update(InputFrame.Dir.RIGHT))
	assert_eq(cursor.index, 0)

func test_reset_forgets_the_held_direction() -> void:
	# Re-opening a menu with the stick still pushed must not move the new
	# selection on its first frame.
	cursor.update(DOWN)
	cursor.reset(0)
	assert_eq(cursor.index, 0)
	assert_true(cursor.update(DOWN), "a still-held direction reads as a press after a reset")
	assert_eq(cursor.index, 1)

func test_single_item_menu_cannot_move_anywhere() -> void:
	var one: MenuCursor = MenuCursor.new(1)
	one.update(DOWN)
	assert_eq(one.index, 0)
	one.update(NONE)
	one.update(UP)
	assert_eq(one.index, 0)

func test_index_is_clamped_to_the_item_count() -> void:
	assert_eq(MenuCursor.new(3, 9).index, 2)
	assert_eq(MenuCursor.new(3, -4).index, 0)
	assert_eq(MenuCursor.new(0).count, 1, "a zero-item menu would be a modulo by zero")
