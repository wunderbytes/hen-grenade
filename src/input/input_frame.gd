class_name InputFrame
## One player's intent for one tick. Deliberately tiny and packable: this is
## what replay logs are made of and what bots will emit in M5.
## See docs/milestone-0-brief.md §5.1.
##
## Only four directions, never diagonals. The game is grid-based; resolving to a
## cardinal direction at the input boundary means no downstream code ever has to
## think about it.

enum Dir { NONE = 0, UP = 1, RIGHT = 2, DOWN = 3, LEFT = 4 }

var dir: Dir = Dir.NONE
var bomb: bool = false      # A button
var action: bool = false    # B button - detonate (Remote) / toss (Toss)

## Packs into one byte: bits 0-2 direction, bit 3 bomb, bit 4 action.
func pack() -> int:
	var packed: int = int(dir) & 0x7
	if bomb:
		packed |= 1 << 3
	if action:
		packed |= 1 << 4
	return packed

## Unpacks a byte produced by pack() into a fresh InputFrame.
static func unpack(b: int) -> InputFrame:
	var frame: InputFrame = InputFrame.new()
	frame.dir = (b & 0x7) as Dir
	frame.bomb = (b & (1 << 3)) != 0
	frame.action = (b & (1 << 4)) != 0
	return frame

func _to_string() -> String:
	return "InputFrame(dir=%d bomb=%d action=%d)" % [dir, int(bomb), int(action)]
