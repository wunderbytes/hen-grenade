class_name PlayerSlot
## A player slot: an `InputSource` plus the identity of whatever is driving it.
## A slot may hold a gamepad, a keyboard layout, or a bot, and callers treat all
## three identically. See docs/milestone-2-brief.md §2.
##
## This is a plain RefCounted object, not a Node, so it stays usable headless
## with no scene tree — the input layer must not depend on Nodes, and the slot
## logic in DeviceBinder is unit-tested in a --script process where Nodes and
## autoloads do not exist at all (technical-design.md Appendix A.2).
##
## Index is identity: slot 0 is P1, P1 is red, and P1 is `MatchState.players[0]`.
## Nothing anywhere renumbers slots.

enum Kind { EMPTY = 0, PAD = 1, KEYBOARD = 2, BOT = 3 }

var index: int = -1
var kind: Kind = Kind.EMPTY
var source: InputSource = null

## False only for a PAD slot whose pad has vanished. Keyboard and bot slots are
## always connected; there is nothing to unplug.
var connected: bool = false

## Pad identity. `pad_device` is Godot's joypad index and is cleared to -1 while
## the pad is away, because that index is a slot in Godot's own table and gets
## **reused**: matching a returning pad on a stale index would hand this seat to
## a different controller. `pad_guid` is what a reconnect matches on.
var pad_device: int = -1
var pad_guid: String = ""
var pad_name: String = ""

## Which KeyboardSource.Layout claimed this slot, or -1.
var kb_layout: int = -1

func _init(p_index: int = -1) -> void:
	index = p_index

# --- Predicates --------------------------------------------------------------

## Occupied means "this slot plays". It is what the match scene turns into
## MatchState's active_slots and what the lobby counts to decide it can start.
func is_occupied() -> bool:
	return kind != Kind.EMPTY and connected

## A seat being held for someone whose pad fell out. This is what pauses a round.
func is_awaiting_reconnect() -> bool:
	return kind == Kind.PAD and not connected

func is_human() -> bool:
	return kind == Kind.PAD or kind == Kind.KEYBOARD

# --- Mutation ---------------------------------------------------------------

func clear() -> void:
	kind = Kind.EMPTY
	source = null
	connected = false
	pad_device = -1
	pad_guid = ""
	pad_name = ""
	kb_layout = -1

# --- Polling ----------------------------------------------------------------

func poll(tick: int) -> InputFrame:
	if source == null or not connected:
		return InputFrame.new()
	return source.poll(tick)

# --- Text -------------------------------------------------------------------

## Diagnostic label, used by the sandbox legend and the log.
func label() -> String:
	if kind == Kind.EMPTY:
		return "Slot %d (empty)" % index
	if is_awaiting_reconnect():
		return "Slot %d <- %s (disconnected)" % [index, pad_name if pad_name != "" else "pad"]
	return "Slot %d <- %s" % [index, source.label() if source != null else "?"]

## Two short lines for a lobby card: what is in the seat, and a qualifier.
func card_lines() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	match kind:
		Kind.EMPTY:
			out.append("press A")
			out.append("to join")
		Kind.PAD:
			if connected:
				out.append("PAD %d" % pad_device)
				out.append(_short_pad_name())
			else:
				out.append("PAD")
				out.append("reconnect!")
		Kind.KEYBOARD:
			out.append("KEYBOARD")
			out.append("WASD" if kb_layout == KeyboardSource.Layout.WASD else "ARROWS")
		Kind.BOT:
			out.append("BOT")
			out.append("placeholder")
	return out

## Pad names are long ("Logitech Gamepad F310") and the card is 140 px wide at an
## 8 px font. Keep the distinguishing tail, drop the vendor.
func _short_pad_name() -> String:
	if pad_name == "":
		return "unknown"
	var words: PackedStringArray = pad_name.split(" ", false)
	return words[words.size() - 1] if words.size() > 1 else pad_name
