extends Node
## The adapter between physical hardware and the roster. Autoloaded as
## `DeviceManager`. See docs/milestone-2-brief.md §3 and §4, and
## docs/technical-design.md §4.
##
## It does four things and delegates every decision:
##   1. Enumerates joypads and follows them through `joy_connection_changed`.
##   2. Edge-detects buttons — join, leave, and the menu layer — once per
##      physics frame.
##   3. Asks `DeviceBinder` what the roster should become.
##   4. Polls the bound sources into one InputFrame per slot, per tick.
##
## Every "what should happen" question lives in `DeviceBinder`, which is pure and
## has a test suite. This file is the "it just happened" half: it is an autoload
## that reads `Input`, and both of those are unreachable from a `--script` test
## process (technical-design.md Appendix A.2), which is exactly why it is thin
## enough to read in one sitting. Its verification is the scene smoke and the
## hardware pass.
##
## Being an autoload also buys the menu layer its one guarantee: autoloads are
## added to the tree before the current scene, so this node's `_physics_process`
## has always computed the frame's button edges before any menu reads them.

## Menu-level buttons, which the simulation never sees. Deliberately not part of
## `InputFrame`: that is the replay format and what bots emit, and a pause the
## sim could observe would be a determinism bug waiting to happen.
enum Menu { CONFIRM = 0, BACK = 1, START = 2, ADD_BOT = 3, REMOVE_BOT = 4 }

const MENU_COUNT: int = 5

## Keyboard seats, in the order they are offered.
const KB_LAYOUTS: Array[int] = [KeyboardSource.Layout.WASD, KeyboardSource.Layout.ARROWS]

signal slot_bound(slot_index: int, label: String)   # a seat was taken
signal slot_left(slot_index: int)                   # a seat was given up or freed
signal slot_disconnected(slot_index: int)           # bound pad vanished mid-match
signal slot_reconnected(slot_index: int)            # reserved seat got its pad back
signal roster_changed()                             # any of the above; for redraws

## True only where joining and leaving are meaningful: the lobby and the input
## sandbox. A pad pressing A mid-round must not take a seat, because
## `MatchState.active_slots` was frozen when the round started — the new player
## would get a card in the HUD and no body in the arena.
##
## Reconnecting a *reserved* seat is allowed regardless (§4 of the brief): a
## reconnect is not a join.
var join_enabled: bool = false

var binder: DeviceBinder = null

# device_id -> { guid: String, name: String }. Cached at connect time because
# Input.get_joy_guid() has nothing to say about a pad that is already gone.
var _pads: Dictionary = {}
## Sorted device ids, so two players pressing A on the same frame claim seats in
## a stable order rather than in whatever order a Dictionary feels like.
var _pad_ids: Array[int] = []
var _pad_a_prev: Dictionary = {}          # device_id -> bool

var _kb_join_prev: Array[bool] = []       # per KB_LAYOUTS entry
var _slot_leave_prev: Array[bool] = []    # per slot

var _menu_now: Array[bool] = []
var _menu_prev: Array[bool] = []
var _menu_dir: InputFrame.Dir = InputFrame.Dir.NONE

func _ready() -> void:
	binder = DeviceBinder.new(C.MAX_PLAYERS)
	_kb_join_prev.resize(KB_LAYOUTS.size())
	_kb_join_prev.fill(false)
	_slot_leave_prev.resize(C.MAX_PLAYERS)
	_slot_leave_prev.fill(false)
	_menu_now.resize(MENU_COUNT)
	_menu_now.fill(false)
	_menu_prev.resize(MENU_COUNT)
	_menu_prev.fill(false)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	for id in Input.get_connected_joypads():
		_register_pad(int(id))

## All edge detection happens here, in one place, once per frame.
##
## Button state is tracked whether or not the action is currently allowed.
## Pressing Space on the title screen advances to the lobby; a lobby that only
## started watching that key on arrival would read the still-held key as a fresh
## press and auto-join the WASD seat. Track always, act only when enabled.
func _physics_process(_delta: float) -> void:
	_update_menu()
	_update_pad_joins()
	_update_keyboard_joins()
	_update_leaves()

# --- Public API --------------------------------------------------------------

## Convenience passthrough: `DeviceManager.slots[i]` reads better at call sites
## than `DeviceManager.binder.slots[i]`, and the binder is the owner either way.
var slots: Array[PlayerSlot]:
	get:
		return binder.slots

## One InputFrame per slot (size == MAX_PLAYERS), index == slot index. Empty,
## disconnected and bot-less slots yield a default frame. Pure polling: no
## binding decision happens here, so calling it twice in a frame cannot change
## the roster.
func poll_all(tick: int) -> Array[InputFrame]:
	var frames: Array[InputFrame] = []
	frames.resize(C.MAX_PLAYERS)
	for i in range(C.MAX_PLAYERS):
		frames[i] = binder.slots[i].poll(tick)
	return frames

## Joining and leaving are live, and any seat still reserved from a match that
## was quit while paused is released — a roster must never arrive at the lobby
## holding a ghost.
func enter_lobby() -> void:
	join_enabled = true
	var freed: Array[int] = binder.release_awaiting()
	for i in freed:
		slot_left.emit(i)
	if not freed.is_empty():
		roster_changed.emit()

## The roster is frozen for the duration of a round. Reconnects still work.
func enter_match() -> void:
	join_enabled = false

func occupied_count() -> int:
	return binder.occupied_count()

func can_start() -> bool:
	return binder.can_start()

func disconnected_slots() -> Array[int]:
	return binder.disconnected_slots()

func active_flags() -> Array[bool]:
	return binder.active_flags()

func slot_label(i: int) -> String:
	if i < 0 or i >= binder.slots.size():
		return "?"
	return binder.slots[i].label()

func add_bot() -> int:
	var i: int = binder.add_bot()
	if i >= 0:
		slot_bound.emit(i, binder.slots[i].source.label())
		roster_changed.emit()
	return i

func remove_last_bot() -> int:
	var i: int = binder.remove_last_bot()
	if i >= 0:
		slot_left.emit(i)
		roster_changed.emit()
	return i

## Two keyboard seats and two placeholder bots, but only if nobody has joined.
##
## This is the dev-and-CI path, not a gameplay path: it keeps `F4`
## straight-to-match working and gives the CI scene smoke a four-player round
## with two non-human sources in it instead of an empty arena. M1 called the
## equivalent from `start_round()`, which is the thing the lobby exists to
## replace; it is never called from a round now.
func ensure_dev_roster() -> void:
	if binder.occupied_count() > 0:
		return
	for layout in KB_LAYOUTS:
		binder.join_keyboard(layout)
	binder.add_bot()
	binder.add_bot()
	# Said out loud, because a stand-in roster must never be mistaken for one
	# four people actually sat down in.
	print("dev roster: two keyboard seats + two placeholder bots (no lobby roster)")
	roster_changed.emit()

# --- Menu input --------------------------------------------------------------

## True on the frame `action` was pressed. Menus read hardware, not slots: any
## connected pad can confirm a rematch, including one that never joined. That is
## a deliberate difference from gameplay input, where an unbound device can do
## nothing at all.
func menu_pressed(action: Menu) -> bool:
	return _menu_now[action] and not _menu_prev[action]

## Aggregated menu navigation direction across every connected device.
func menu_dir() -> InputFrame.Dir:
	return _menu_dir

func _update_menu() -> void:
	for i in range(MENU_COUNT):
		_menu_prev[i] = _menu_now[i]
		_menu_now[i] = false
	_set_menu(Menu.CONFIRM, Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER))
	_set_menu(Menu.BACK, Input.is_key_pressed(KEY_BACKSPACE))
	# Enter as well as Escape, because START is "begin the match" in the lobby and
	# "pause" in a round, and Escape is only the obvious key for the second of
	# those. Enter is deliberately both START and CONFIRM: the pause menu checks
	# CONFIRM first so Enter there chooses the highlighted item, and the lobby
	# never reads CONFIRM, so Space can stay the WASD seat's join key without
	# Enter-means-start also firing on it.
	_set_menu(Menu.START, Input.is_key_pressed(KEY_ESCAPE) or Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER))
	_set_menu(Menu.ADD_BOT, Input.is_key_pressed(KEY_B))
	_set_menu(Menu.REMOVE_BOT, Input.is_key_pressed(KEY_N))
	for device_id in _pad_ids:
		_set_menu(Menu.CONFIRM, Input.is_joy_button_pressed(device_id, JOY_BUTTON_A))
		_set_menu(Menu.BACK, Input.is_joy_button_pressed(device_id, JOY_BUTTON_B) or Input.is_joy_button_pressed(device_id, JOY_BUTTON_BACK))
		_set_menu(Menu.START, Input.is_joy_button_pressed(device_id, JOY_BUTTON_START))
		_set_menu(Menu.ADD_BOT, Input.is_joy_button_pressed(device_id, JOY_BUTTON_Y))
		_set_menu(Menu.REMOVE_BOT, Input.is_joy_button_pressed(device_id, JOY_BUTTON_X))
	_menu_dir = _read_menu_dir()

func _set_menu(action: Menu, pressed: bool) -> void:
	if pressed:
		_menu_now[action] = true

func _read_menu_dir() -> InputFrame.Dir:
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		return InputFrame.Dir.UP
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		return InputFrame.Dir.DOWN
	for device_id in _pad_ids:
		if Input.is_joy_button_pressed(device_id, JOY_BUTTON_DPAD_UP):
			return InputFrame.Dir.UP
		if Input.is_joy_button_pressed(device_id, JOY_BUTTON_DPAD_DOWN):
			return InputFrame.Dir.DOWN
		var y: float = Input.get_joy_axis(device_id, JOY_AXIS_LEFT_Y)
		if y <= -GamepadSource.ENGAGE_THRESHOLD:
			return InputFrame.Dir.UP
		if y >= GamepadSource.ENGAGE_THRESHOLD:
			return InputFrame.Dir.DOWN
	return InputFrame.Dir.NONE

# --- Enumeration and hot-plug -----------------------------------------------

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		_register_pad(device)
	else:
		_handle_disconnect(device)

func _register_pad(device_id: int) -> void:
	if _pads.has(device_id):
		return
	var guid: String = Input.get_joy_guid(device_id)
	var pad_name: String = Input.get_joy_name(device_id)
	_pads[device_id] = { "guid": guid, "name": pad_name }
	_pad_ids.append(device_id)
	_pad_ids.sort()
	_pad_a_prev[device_id] = Input.is_joy_button_pressed(device_id, JOY_BUTTON_A)
	# GUID-first reconnect. Only the unambiguous case rebinds itself; identical
	# pads sharing a GUID fall through to press-to-claim in _update_pad_joins().
	var slot_index: int = binder.device_added(device_id, guid, pad_name)
	if slot_index >= 0:
		_seed_leave_edge(slot_index)
		slot_reconnected.emit(slot_index)
		roster_changed.emit()

func _handle_disconnect(device_id: int) -> void:
	var slot_index: int = binder.device_removed(device_id)
	_forget_pad(device_id)
	if slot_index < 0:
		return
	# Two policies, one mechanism (brief §4). In the lobby a pad on the floor is
	# just a pad on the floor and the seat is freed for someone else. In a match
	# the seat is held and the round pauses.
	if join_enabled:
		binder.leave(slot_index)
		slot_left.emit(slot_index)
	else:
		slot_disconnected.emit(slot_index)
	roster_changed.emit()

func _forget_pad(device_id: int) -> void:
	_pads.erase(device_id)
	_pad_a_prev.erase(device_id)
	var at: int = _pad_ids.find(device_id)
	if at >= 0:
		_pad_ids.remove_at(at)

# --- Join and leave detection ------------------------------------------------

func _update_pad_joins() -> void:
	for device_id in _pad_ids:
		var pressed: bool = Input.is_joy_button_pressed(device_id, JOY_BUTTON_A)
		var was: bool = bool(_pad_a_prev.get(device_id, false))
		_pad_a_prev[device_id] = pressed
		if binder.slot_of_pad(device_id) >= 0:
			continue
		if not pressed or was:
			continue
		var entry: Dictionary = _pads[device_id]
		var guid: String = String(entry["guid"])
		var pad_name: String = String(entry["name"])
		# A reserved seat first: press-to-claim is how identical pads resolve
		# which is which, and it is allowed even mid-match.
		var slot_index: int = binder.claim_awaiting(device_id, guid, pad_name)
		if slot_index >= 0:
			_seed_leave_edge(slot_index)
			slot_reconnected.emit(slot_index)
			roster_changed.emit()
			continue
		if not join_enabled:
			continue
		slot_index = binder.join_pad(device_id, guid, pad_name)
		if slot_index >= 0:
			_seed_leave_edge(slot_index)
			slot_bound.emit(slot_index, binder.slots[slot_index].source.label())
			roster_changed.emit()

func _update_keyboard_joins() -> void:
	for i in range(KB_LAYOUTS.size()):
		var layout: int = KB_LAYOUTS[i]
		var pressed: bool = Input.is_key_pressed(_kb_join_key(layout))
		var was: bool = _kb_join_prev[i]
		_kb_join_prev[i] = pressed
		if not join_enabled or not pressed or was:
			continue
		if binder.keyboard_claimed(layout):
			continue
		var slot_index: int = binder.join_keyboard(layout)
		if slot_index >= 0:
			_seed_leave_edge(slot_index)
			slot_bound.emit(slot_index, binder.slots[slot_index].source.label())
			roster_changed.emit()

## Leave with your action button — B on a pad, the layout's action key on the
## keyboard. Only live where joining is: B is the action button in a round, and
## a player pressing it mid-round must not lose their seat.
func _update_leaves() -> void:
	for i in range(C.MAX_PLAYERS):
		var slot: PlayerSlot = binder.slots[i]
		var pressed: bool = _slot_leave_pressed(slot)
		var was: bool = _slot_leave_prev[i]
		_slot_leave_prev[i] = pressed
		if not join_enabled or not pressed or was:
			continue
		if binder.leave(i):
			slot_left.emit(i)
			roster_changed.emit()

## Called the moment a seat becomes occupied. Without it, a player holding B
## while pressing A would join and leave on the same frame: the leave check runs
## after the join check in this same `_physics_process`, and it would read a
## key that was already down as a fresh press. Same "track always, act on edges"
## rule as everywhere else here, applied at the moment tracking starts.
func _seed_leave_edge(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < _slot_leave_prev.size():
		_slot_leave_prev[slot_index] = _slot_leave_pressed(binder.slots[slot_index])

func _slot_leave_pressed(slot: PlayerSlot) -> bool:
	match slot.kind:
		PlayerSlot.Kind.PAD:
			return slot.connected and Input.is_joy_button_pressed(slot.pad_device, JOY_BUTTON_B)
		PlayerSlot.Kind.KEYBOARD:
			return Input.is_key_pressed(_kb_leave_key(slot.kb_layout))
	# Bots do not leave of their own accord; X drops them.
	return false

## The bomb key doubles as the join key, so the rule is uniform across devices:
## join with your bomb button, leave with your action button.
func _kb_join_key(layout: int) -> int:
	return KEY_SPACE if layout == KeyboardSource.Layout.WASD else KEY_CTRL

func _kb_leave_key(layout: int) -> int:
	return KEY_Q if layout == KeyboardSource.Layout.WASD else KEY_SLASH
