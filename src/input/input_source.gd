class_name InputSource
## Abstract base for anything that can produce an InputFrame per tick.
## Implementations: GamepadSource, KeyboardSource (M0); BotSource (M5);
## ReplaySource (M1). This seam is what makes bots un-cheatable and replays
## free, so it is established in M0.
## See docs/milestone-0-brief.md §5.2.

func poll(_tick: int) -> InputFrame:
	push_error("InputSource.poll is abstract; override in a subclass")
	return InputFrame.new()

## Returns a short human-readable label for which device drives this source,
## e.g. "Pad 2 (Logitech Gamepad F310)" or "Keyboard (WASD)". Used by the
## sandbox to show which device drives which square.
func label() -> String:
	return "abstract"
