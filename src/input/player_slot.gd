class_name PlayerSlot
## A player slot bound to exactly one input source. A slot may hold a gamepad,
## a keyboard layout, or (later) a bot. Callers treat all sources identically.
## See docs/milestone-0-brief.md §5.4.
##
## This is a plain RefCounted object, not a Node, so it stays usable headless
## with no scene tree — the input layer must not depend on Nodes.

var index: int = -1
var source: InputSource = null
var connected: bool = false  # false for keyboard slots (always "connected")

func _init(p_index: int = -1) -> void:
	index = p_index

func is_occupied() -> bool:
	return source != null and connected

func poll(tick: int) -> InputFrame:
	if source == null or not connected:
		return InputFrame.new()
	return source.poll(tick)

func label() -> String:
	if source == null:
		return "Slot %d (empty)" % index
	if not connected:
		return "Slot %d (disconnected)" % index
	return "Slot %d <- %s" % [index, source.label()]
