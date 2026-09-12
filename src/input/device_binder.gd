class_name DeviceBinder
## Decides which device drives which player slot: joins, leaves, bots, and the
## whole hot-plug reconnect dance. See docs/milestone-2-brief.md §2.1.
##
## **This class touches no hardware and no scene tree.** It is a plain
## RefCounted with no Node, no autoload and no `Input` call, which is the point:
## the flakiest logic in this project is not the simulation (pinned by a golden
## replay) but what happens when four identical F310s share one GUID and the
## third falls out of a hub mid-round. In M0 that logic lived inline in the
## `DeviceManager` autoload, and autoloads are unreachable from a `--script`
## test process (technical-design.md Appendix A.2), so it was untested. Now it
## is here and it has a suite.
##
## Constructing a GamepadSource or KeyboardSource touches no device — only
## `poll()` does — so this class can build real sources and a test can assert on
## the resulting roster without ever reading hardware.
##
## The binder decides *what should happen if a pad with this GUID appears*.
## DeviceManager decides *that a pad with this GUID just appeared*. Keeping those
## two apart is what makes half of this testable.

var slots: Array[PlayerSlot] = []

## guid -> Array[int]: slots whose pad vanished, waiting for a pad with this GUID
## to come back. Kept as a side table rather than read off the slots because a
## slot only knows its own GUID, and "how many seats want this GUID" is the
## question that decides auto-rebind versus press-to-claim.
##
## Never iterated: every ordered answer is derived from `slots` instead, and the
## arrays inside are kept in ascending slot order.
var _awaiting: Dictionary = {}

func _init(slot_count: int = C.MAX_PLAYERS) -> void:
	for i in range(slot_count):
		slots.append(PlayerSlot.new(i))

# --- Joining -----------------------------------------------------------------

## Press-A-to-join for a pad that holds no seat. Returns the slot index, or -1
## if the lobby is full or this pad already has a seat.
func join_pad(device_id: int, guid: String, pad_name: String) -> int:
	if slot_of_pad(device_id) >= 0:
		return -1
	var i: int = first_free_slot()
	if i < 0:
		return -1
	_bind_pad(i, device_id, guid, pad_name)
	return i

## Claims a slot for one of the keyboard layouts. A layout is one seat: two
## players share the board, they do not share a layout.
func join_keyboard(layout: int) -> int:
	if keyboard_claimed(layout):
		return -1
	var i: int = first_free_slot()
	if i < 0:
		return -1
	var slot: PlayerSlot = slots[i]
	slot.clear()
	slot.kind = PlayerSlot.Kind.KEYBOARD
	slot.kb_layout = layout
	slot.source = KeyboardSource.new(layout as KeyboardSource.Layout)
	slot.connected = true
	return i

## Bots take the first free slot, so `Y` `Y` fills 3 then 4 with no cursor.
func add_bot() -> int:
	var i: int = first_free_slot()
	if i < 0:
		return -1
	var slot: PlayerSlot = slots[i]
	slot.clear()
	slot.kind = PlayerSlot.Kind.BOT
	slot.source = BotSource.for_slot(i)
	slot.connected = true
	return i

## Drops the **last** bot, never a human's seat, so `Y` `Y` `X` is predictable.
func remove_last_bot() -> int:
	for i in range(slots.size() - 1, -1, -1):
		if slots[i].kind == PlayerSlot.Kind.BOT:
			leave(i)
			return i
	return -1

## Frees a seat completely, including any reservation it held.
func leave(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= slots.size():
		return false
	var slot: PlayerSlot = slots[slot_index]
	if slot.kind == PlayerSlot.Kind.EMPTY:
		return false
	_forget_reservation(slot_index, slot.pad_guid)
	slot.clear()
	return true

func clear_all() -> void:
	for slot in slots:
		slot.clear()
	_awaiting.clear()

# --- Hot-plug ----------------------------------------------------------------

## A pad appeared. Returns the slot it was silently rebound to, or -1.
##
## Only the unambiguous case rebinds itself: exactly one seat waiting for this
## GUID, which is the common "one pad fell out of the hub" case. Two seats
## waiting for the same GUID is what four identical F310s produce and there is no
## way to tell them apart, so we do not guess — the caller falls back to
## press-to-claim (§4 of the brief).
func device_added(device_id: int, guid: String, pad_name: String) -> int:
	var waiting: Array = _awaiting.get(guid, [])
	if waiting.size() != 1:
		return -1
	var slot_index: int = int(waiting[0])
	_forget_reservation(slot_index, guid)
	_bind_pad(slot_index, device_id, guid, pad_name)
	return slot_index

## A pad vanished. Reserves its seat and returns the slot index, or -1 if that
## pad held no seat. The seat stays `kind == PAD` but goes `connected = false`,
## which is what `is_awaiting_reconnect()` reports and what pauses a round.
func device_removed(device_id: int) -> int:
	var slot_index: int = slot_of_pad(device_id)
	if slot_index < 0:
		return -1
	var slot: PlayerSlot = slots[slot_index]
	slot.connected = false
	slot.source = null
	# The device index is gone and Godot will reuse it for some other pad.
	slot.pad_device = -1
	_reserve(slot_index, slot.pad_guid)
	return slot_index

## Press-to-claim for a reserved seat: the ambiguous-GUID path, and the only
## binding allowed while a round is running. Takes the lowest-numbered waiting
## seat for this GUID. Returns the slot index, or -1 if nothing was waiting.
func claim_awaiting(device_id: int, guid: String, pad_name: String) -> int:
	var waiting: Array = _awaiting.get(guid, [])
	if waiting.is_empty():
		return -1
	if slot_of_pad(device_id) >= 0:
		return -1
	var slot_index: int = int(waiting[0])
	_forget_reservation(slot_index, guid)
	_bind_pad(slot_index, device_id, guid, pad_name)
	return slot_index

## Frees every reserved seat and returns which ones it freed. Called on entering
## the lobby: a pad on the floor with no round in progress is just a pad on the
## floor, and a roster must never arrive at the lobby holding a ghost.
func release_awaiting() -> Array[int]:
	var freed: Array[int] = []
	for slot in slots:
		if slot.is_awaiting_reconnect():
			freed.append(slot.index)
	for i in freed:
		leave(i)
	return freed

# --- Queries -----------------------------------------------------------------

func slot_of_pad(device_id: int) -> int:
	if device_id < 0:
		return -1
	for slot in slots:
		if slot.kind == PlayerSlot.Kind.PAD and slot.connected and slot.pad_device == device_id:
			return slot.index
	return -1

func keyboard_claimed(layout: int) -> bool:
	for slot in slots:
		if slot.kind == PlayerSlot.Kind.KEYBOARD and slot.kb_layout == layout:
			return true
	return false

func first_free_slot() -> int:
	for slot in slots:
		if slot.kind == PlayerSlot.Kind.EMPTY:
			return slot.index
	return -1

func occupied_count() -> int:
	var n: int = 0
	for slot in slots:
		if slot.is_occupied():
			n += 1
	return n

## In slot order, not reservation order, so the notice always names players in
## the order they sit on screen.
func disconnected_slots() -> Array[int]:
	var out: Array[int] = []
	for slot in slots:
		if slot.is_awaiting_reconnect():
			out.append(slot.index)
	return out

func can_start() -> bool:
	return occupied_count() >= C.MIN_PLAYERS and disconnected_slots().is_empty()

## One bool per slot, for MatchState.create(). Index-aligned with `slots`.
func active_flags() -> Array[bool]:
	var out: Array[bool] = []
	for slot in slots:
		out.append(slot.is_occupied())
	return out

# --- Internals ---------------------------------------------------------------

func _bind_pad(slot_index: int, device_id: int, guid: String, pad_name: String) -> void:
	var slot: PlayerSlot = slots[slot_index]
	slot.clear()
	slot.kind = PlayerSlot.Kind.PAD
	slot.pad_device = device_id
	slot.pad_guid = guid
	slot.pad_name = pad_name
	slot.source = GamepadSource.new(device_id, pad_name)
	slot.connected = true

func _reserve(slot_index: int, guid: String) -> void:
	if not _awaiting.has(guid):
		_awaiting[guid] = [] as Array[int]
	var waiting: Array = _awaiting[guid]
	if not waiting.has(slot_index):
		waiting.append(slot_index)
		waiting.sort()   # lowest-numbered waiting seat claims first

func _forget_reservation(slot_index: int, guid: String) -> void:
	if guid == "" or not _awaiting.has(guid):
		return
	var waiting: Array = _awaiting[guid]
	var at: int = waiting.find(slot_index)
	if at >= 0:
		waiting.remove_at(at)
	if waiting.is_empty():
		_awaiting.erase(guid)
