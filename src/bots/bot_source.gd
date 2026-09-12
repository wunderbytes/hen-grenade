class_name BotSource
extends InputSource
## **A placeholder, not a bot.** See docs/milestone-2-brief.md §7.
##
## M2 needs a bot *slot* so the lobby can honestly offer empty / human / bot and
## so the roster, `active_slots` and HUD paths for a non-human player get
## exercised. It does not need a bot, which is M5 and starts from a danger map,
## not from this file.
##
## So this wanders: pick a direction, hold it for a while, pick again. It never
## drops a bomb, deliberately — a bot that bombed would take kills, take suicide
## penalties, and make a scoreboard look like it meant something.
##
## It is the fourth implementation of the M0 `InputSource` seam, and like
## `ReplaySource` before it, adding it changed nothing else.
##
## Seeded from `SimRng` rather than `randi()`, which is worth a sentence because
## it is *not* a determinism requirement: `Replay` records the InputFrames the
## sim was given, not the reasons for them, so even a bot reading the wall clock
## would replay perfectly. Determinism is a constraint on `src/sim/`, not on
## anything upstream of it. This is seeded because a wanderer that does the same
## thing twice is easier to debug than one that does not.

const MIN_HOLD_TICKS: int = 20
const MAX_HOLD_TICKS: int = 70

var _rng: SimRng = null
var _dir: InputFrame.Dir = InputFrame.Dir.NONE
var _hold_left: int = 0

func _init(seed_value: int = 1) -> void:
	_rng = SimRng.new(seed_value)

## Slot-derived seed, so P3's placeholder does not shadow P4's.
static func for_slot(slot_index: int) -> BotSource:
	return BotSource.new(0x5EED + slot_index * 7919)

func poll(_tick: int) -> InputFrame:
	var frame: InputFrame = InputFrame.new()
	_hold_left -= 1
	if _hold_left <= 0:
		_dir = _pick_dir()
		_hold_left = _rng.next_range(MIN_HOLD_TICKS, MAX_HOLD_TICKS)
	frame.dir = _dir
	return frame

func label() -> String:
	return "Bot (placeholder)"

func _pick_dir() -> InputFrame.Dir:
	# 1..4 == UP, RIGHT, DOWN, LEFT. Never NONE: a placeholder standing still is
	# indistinguishable from a broken one.
	return _rng.next_range(1, 4) as InputFrame.Dir
