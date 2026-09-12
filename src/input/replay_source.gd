class_name ReplaySource
extends InputSource
## Plays one slot's recorded input back as if it were a device.
## See docs/milestone-0-brief.md §5.2 and docs/milestone-1-brief.md §8.
##
## The third implementation of the InputSource seam, and the one that proves the
## seam was worth establishing in M0: a recorded round drives the game through
## exactly the same path a gamepad does, and nothing downstream knows the
## difference. M5's BotSource is the fourth, and it will not need any changes
## here either.

var replay: Replay = null
var slot: int = -1

func _init(p_replay: Replay = null, p_slot: int = -1) -> void:
	replay = p_replay
	slot = p_slot

func poll(tick: int) -> InputFrame:
	if replay == null:
		return InputFrame.new()
	return replay.frame_for(tick, slot)

func label() -> String:
	return "Replay (slot %d)" % slot

## True once the log has run out. The host scene uses this to stop rather than
## feed the sim empty frames forever.
func exhausted(tick: int) -> bool:
	return replay == null or tick > replay.tick_count()
