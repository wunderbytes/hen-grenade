class_name MenuCursor
## Vertical selection over N items, with wrap and no auto-repeat.
## See docs/milestone-2-brief.md §8.
##
## Pure and Node-free so it can be tested headless. Small enough that writing it
## twice would be the real cost — the pause menu needs it now and M4's options
## screen will need it again.
##
## No auto-repeat is a choice, not an omission: these menus are three items long
## and every one of them is read by four people at once on a shared screen. A
## held D-pad that scrolls is how you end up quitting to the lobby by accident.

var index: int = 0
var count: int = 0

var _prev_dir: InputFrame.Dir = InputFrame.Dir.NONE

func _init(p_count: int = 1, p_index: int = 0) -> void:
	count = maxi(1, p_count)
	index = clampi(p_index, 0, count - 1)

## Feed the aggregated menu direction once per frame. Returns true if the
## selection moved, so a caller can play a tick sound without tracking state.
func update(dir: InputFrame.Dir) -> bool:
	var moved: bool = false
	if dir != _prev_dir:
		if dir == InputFrame.Dir.UP:
			index = (index - 1 + count) % count
			moved = true
		elif dir == InputFrame.Dir.DOWN:
			index = (index + 1) % count
			moved = true
	_prev_dir = dir
	return moved

## Forgets the held direction, so re-opening a menu with the stick still pushed
## does not immediately move the new selection.
func reset(p_index: int = 0) -> void:
	index = clampi(p_index, 0, count - 1)
	_prev_dir = InputFrame.Dir.NONE
