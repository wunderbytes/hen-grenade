extends Node
## Owns everything about physical input devices so nothing else has to.
## Autoloaded as `DeviceManager`. See docs/milestone-0-brief.md §5.4 and
## docs/technical-design.md §4.
##
## Responsibilities:
## - Enumerate joypads and identify them by GUID + name.
## - Hot-plug via Input.joy_connection_changed.
## - Bind a device to a player slot on first A press; one device, one slot.
## - On disconnect, mark the slot disconnected and emit slot_unbound (the game
##   pauses). On reconnect, match by GUID first; if two identical pads share a
##   GUID, fall back to press-to-claim.
## - Expose the built-in keyboard as one or two joinable slots, indistinguishable
##   to callers from a pad.
##
## This layer reads devices directly (no InputMap) and produces InputFrames per
## tick. It is the only place that knows about hardware.

const _MAX_PLAYERS: int = C.MAX_PLAYERS

signal slot_bound(slot_index: int, label: String)        # a slot became occupied
signal slot_unbound(slot_index: int)                     # bound pad disconnected
signal slot_reconnected(slot_index: int)                # disconnected pad rebound

var slots: Array[PlayerSlot] = []

# device_id (int) -> Dictionary { guid: String, name: String, bound_slot: int }
var _pads: Dictionary = {}
# device_id -> bool (previous-frame A state, for edge detection)
var _pad_a_prev: Dictionary = {}

# guid -> Array[int] of slot indices waiting for a pad with this GUID to reconnect.
# Used for GUID-first reconnect matching.
var _pending_reconnect: Dictionary = {}

# Keyboard sources available to claim a slot. Created once at startup.
var _keyboard_sources: Array[KeyboardSource] = []
var _kb_claimed: Array[bool] = []   # parallel to _keyboard_sources
var _kb_join_prev: Array[bool] = [] # edge detection for the keyboard join keys

func _ready() -> void:
	for i in range(_MAX_PLAYERS):
		slots.append(PlayerSlot.new(i))
	# Two keyboard layouts so two players can share one board.
	_keyboard_sources.append(KeyboardSource.new(KeyboardSource.Layout.WASD))
	_keyboard_sources.append(KeyboardSource.new(KeyboardSource.Layout.ARROWS))
	_kb_claimed.resize(_keyboard_sources.size())
	_kb_claimed.fill(false)
	_kb_join_prev.resize(_keyboard_sources.size())
	_kb_join_prev.fill(false)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_enumerate_pads()

# --- Public API --------------------------------------------------------------

## Returns one InputFrame per slot (size == MAX_PLAYERS). Unoccupied or
## disconnected slots yield a default (empty) InputFrame. Index == slot index.
func poll_all(tick: int) -> Array[InputFrame]:
	_detect_joins()
	var frames: Array[InputFrame] = []
	frames.resize(_MAX_PLAYERS)
	for i in range(_MAX_PLAYERS):
		frames[i] = slots[i].poll(tick)
	return frames

func slot_label(i: int) -> String:
	if i < 0 or i >= slots.size():
		return "?"
	return slots[i].label()

func occupied_count() -> int:
	var n: int = 0
	for s in slots:
		if s.is_occupied():
			n += 1
	return n

# --- Enumeration / hot-plug --------------------------------------------------

func _enumerate_pads() -> void:
	for id in Input.get_connected_joypads():
		_register_pad(int(id))

func _register_pad(device_id: int) -> void:
	if _pads.has(device_id):
		return
	var guid: String = Input.get_joy_guid(device_id)
	var name: String = Input.get_joy_name(device_id)
	_pads[device_id] = { "guid": guid, "name": name, "bound_slot": -1 }
	_pad_a_prev[device_id] = false
	# GUID-first reconnect: if a slot is waiting for this GUID and it is the
	# only one, rebind automatically. If two identical pads are both waiting,
	# leave it for press-to-claim.
	if _pending_reconnect.has(guid) and _pending_reconnect[guid].size() == 1:
		var slot_idx: int = _pending_reconnect[guid][0]
		_pending_reconnect[guid].clear()
		_pending_reconnect.erase(guid)
		_bind_pad_to_slot(device_id, slot_idx, true)
	elif _pending_reconnect.has(guid) and _pending_reconnect[guid].size() > 1:
		# Ambiguous: two identical pads waiting. Leave unbound; press-to-claim
		# will resolve which slot each pad takes.
		pass

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		_register_pad(device)
	else:
		_handle_disconnect(device)

func _handle_disconnect(device_id: int) -> void:
	if not _pads.has(device_id):
		return
	var entry: Dictionary = _pads[device_id]
	var slot_idx: int = int(entry["bound_slot"])
	var guid: String = String(entry["guid"])
	if slot_idx >= 0 and slot_idx < slots.size():
		# Reserve the slot for the player; mark disconnected so the game pauses.
		slots[slot_idx].connected = false
		if not _pending_reconnect.has(guid):
			_pending_reconnect[guid] = []
		(_pending_reconnect[guid] as Array).append(slot_idx)
		slot_unbound.emit(slot_idx)
	_pads.erase(device_id)
	_pad_a_prev.erase(device_id)

# --- Binding ----------------------------------------------------------------

func _bind_pad_to_slot(device_id: int, slot_idx: int, is_reconnect: bool) -> void:
	var entry: Dictionary = _pads[device_id]
	var name: String = String(entry["name"])
	var src: GamepadSource = GamepadSource.new(device_id, name)
	slots[slot_idx].source = src
	slots[slot_idx].connected = true
	entry["bound_slot"] = slot_idx
	if is_reconnect:
		slot_reconnected.emit(slot_idx)
	else:
		slot_bound.emit(slot_idx, src.label())

func _free_slot_count() -> int:
	var n: int = 0
	for s in slots:
		if s.source == null:
			n += 1
	return n

func _first_free_slot() -> int:
	for i in range(_MAX_PLAYERS):
		if slots[i].source == null:
			return i
	return -1

## Claim a slot for a keyboard layout. Returns the slot index, or -1 if none free.
func _claim_keyboard_slot(kb_index: int) -> int:
	if _kb_claimed[kb_index]:
		return -1
	var slot_idx: int = _first_free_slot()
	if slot_idx < 0:
		return -1
	var src: KeyboardSource = _keyboard_sources[kb_index]
	slots[slot_idx].source = src
	slots[slot_idx].connected = true
	_kb_claimed[kb_index] = true
	slot_bound.emit(slot_idx, src.label())
	return slot_idx

func _keyboard_join_key(kb_index: int) -> int:
	# The bomb key doubles as the "press to join" key for keyboard slots.
	match _keyboard_sources[kb_index].layout:
		KeyboardSource.Layout.WASD:
			return KEY_SPACE
		KeyboardSource.Layout.ARROWS:
			return KEY_CTRL
	return KEY_SPACE

# --- Join detection (runs once per physics tick, before polling) ------------

func _detect_joins() -> void:
	# Pads: edge-detect A press on every connected, unbound pad.
	for device_id in _pads.keys():
		var entry: Dictionary = _pads[device_id]
		if int(entry["bound_slot"]) >= 0:
			_pad_a_prev[device_id] = false
			continue
		var pressed: bool = Input.is_joy_button_pressed(int(device_id), JOY_BUTTON_A)
		var was_pressed: bool = bool(_pad_a_prev.get(device_id, false))
		_pad_a_prev[device_id] = pressed
		if pressed and not was_pressed:
			_try_bind_pad(int(device_id), String(entry["guid"]))
	# Keyboard: edge-detect the join key on each unclaimed layout.
	for kb_index in range(_keyboard_sources.size()):
		if _kb_claimed[kb_index]:
			_kb_join_prev[kb_index] = true
			continue
		var pressed: bool = Input.is_key_pressed(_keyboard_join_key(kb_index))
		var was_pressed: bool = _kb_join_prev[kb_index]
		_kb_join_prev[kb_index] = pressed
		if pressed and not was_pressed:
			_claim_keyboard_slot(kb_index)

func _try_bind_pad(device_id: int, guid: String) -> void:
	# If this GUID has pending reconnects (ambiguous identical-pad case), bind
	# to the first waiting slot. Otherwise bind to the first free slot.
	if _pending_reconnect.has(guid) and _pending_reconnect[guid].size() > 0:
		var slot_idx: int = _pending_reconnect[guid][0]
		_pending_reconnect[guid].remove_at(0)
		if _pending_reconnect[guid].is_empty():
			_pending_reconnect.erase(guid)
		_bind_pad_to_slot(device_id, slot_idx, true)
		return
	var slot_idx: int = _first_free_slot()
	if slot_idx < 0:
		return
	_bind_pad_to_slot(device_id, slot_idx, false)
