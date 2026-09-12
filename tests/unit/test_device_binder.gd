extends TestCase
## Slot assignment: joins, leaves, bots, and hot-plug reconnect.
## See docs/milestone-2-brief.md §8.
##
## This is the suite that would have caught the bugs M0 shipped. All of this
## logic used to live inline in the `DeviceManager` autoload, where a `--script`
## test process cannot reach it at all (technical-design.md Appendix A.2), so
## none of it was covered — including the four-identical-F310s case, which is
## the one the reference hardware actually produces.
##
## Nothing here touches `Input`. Constructing a GamepadSource does not read a
## device; only `poll()` does, and no test polls.

const F310_GUID: String = "030000006d0400001dc2000014400000"
const F310_NAME: String = "Logitech Gamepad F310"
const OTHER_GUID: String = "03000000ffff0000ffff000000000000"

var binder: DeviceBinder = null

func before_each() -> void:
	binder = DeviceBinder.new(C.MAX_PLAYERS)

# --- Joining -----------------------------------------------------------------

func test_pads_join_in_slot_order() -> void:
	for i in range(C.MAX_PLAYERS):
		assert_eq(_join(i), i, "pad %d should take slot %d" % [i, i])
	assert_eq(binder.occupied_count(), 4)

func test_fifth_pad_is_refused_and_changes_nothing() -> void:
	for i in range(C.MAX_PLAYERS):
		_join(i)
	assert_eq(_join(99), -1, "a fifth pad has nowhere to sit")
	assert_eq(binder.occupied_count(), 4)
	assert_eq(binder.slots[3].pad_device, 3, "the last seat must not be stolen")

func test_one_pad_cannot_hold_two_seats() -> void:
	assert_eq(_join(0), 0)
	assert_eq(_join(0), -1, "the same device pressing A again is not a second player")
	assert_eq(binder.occupied_count(), 1)

func test_keyboard_layouts_are_one_seat_each() -> void:
	assert_eq(binder.join_keyboard(KeyboardSource.Layout.WASD), 0)
	assert_eq(binder.join_keyboard(KeyboardSource.Layout.ARROWS), 1)
	assert_eq(binder.join_keyboard(KeyboardSource.Layout.WASD), -1, "one layout is one seat")
	assert_eq(binder.occupied_count(), 2)
	assert_true(binder.keyboard_claimed(KeyboardSource.Layout.WASD))

func test_slot_kinds_and_sources_match_the_device() -> void:
	_join(0)
	binder.join_keyboard(KeyboardSource.Layout.ARROWS)
	binder.add_bot()
	assert_eq(binder.slots[0].kind, PlayerSlot.Kind.PAD)
	assert_eq(binder.slots[1].kind, PlayerSlot.Kind.KEYBOARD)
	assert_eq(binder.slots[2].kind, PlayerSlot.Kind.BOT)
	assert_eq(binder.slots[3].kind, PlayerSlot.Kind.EMPTY)
	assert_true(binder.slots[0].source is GamepadSource)
	assert_true(binder.slots[1].source is KeyboardSource)
	assert_true(binder.slots[2].source is BotSource)
	assert_null(binder.slots[3].source)
	assert_true(binder.slots[0].is_human(), "a pad is a human")
	assert_false(binder.slots[2].is_human(), "a bot is not")

# --- Leaving -----------------------------------------------------------------

func test_leaving_frees_the_seat_for_the_next_join() -> void:
	_join(0)
	_join(1)
	assert_true(binder.leave(0))
	assert_eq(binder.slots[0].kind, PlayerSlot.Kind.EMPTY)
	assert_eq(binder.occupied_count(), 1)
	assert_eq(_join(7), 0, "the freed seat is the first free seat")

func test_leaving_an_empty_seat_does_nothing() -> void:
	assert_false(binder.leave(2))
	assert_false(binder.leave(-1), "out of range must not crash or claim")
	assert_false(binder.leave(99))

func test_a_left_pad_can_rejoin() -> void:
	_join(3)
	binder.leave(0)
	assert_eq(_join(3), 0, "the same device may sit down again")

# --- Bots --------------------------------------------------------------------

func test_bots_fill_forward_and_drop_backward() -> void:
	binder.join_keyboard(KeyboardSource.Layout.WASD)
	assert_eq(binder.add_bot(), 1)
	assert_eq(binder.add_bot(), 2)
	assert_eq(binder.remove_last_bot(), 2, "X drops the last bot, so Y Y X is predictable")
	assert_eq(binder.slots[1].kind, PlayerSlot.Kind.BOT, "the first bot stays")
	assert_eq(binder.occupied_count(), 2)

func test_dropping_a_bot_never_takes_a_human_seat() -> void:
	_join(0)
	binder.join_keyboard(KeyboardSource.Layout.WASD)
	assert_eq(binder.remove_last_bot(), -1, "no bots to drop")
	assert_eq(binder.occupied_count(), 2, "the humans are still seated")

func test_bots_are_seeded_per_slot() -> void:
	# Not a determinism requirement (replays log frames, not reasons) but a
	# debuggability one: P3's placeholder must not shadow P4's.
	var a: BotSource = BotSource.for_slot(2)
	var b: BotSource = BotSource.for_slot(3)
	assert_ne(a.poll(1).dir, InputFrame.Dir.NONE, "a placeholder that stands still looks broken")
	var same: int = 0
	for tick in range(1, 200):
		if a.poll(tick).dir == b.poll(tick).dir:
			same += 1
	assert_lt(same, 190, "two bot slots should not walk in lockstep")

# --- Hot-plug: disconnect ----------------------------------------------------

func test_disconnect_reserves_the_seat() -> void:
	_join(0)
	_join(1)
	assert_eq(binder.device_removed(0), 0)
	var slot: PlayerSlot = binder.slots[0]
	assert_false(slot.is_occupied(), "a reserved seat does not play")
	assert_true(slot.is_awaiting_reconnect(), "and it is not empty either")
	assert_eq(slot.kind, PlayerSlot.Kind.PAD, "the seat remembers what it is holding")
	assert_eq(slot.pad_device, -1, "the device index is gone and Godot will reuse it")
	assert_eq(slot.pad_guid, F310_GUID, "the GUID is what a reconnect matches on")
	assert_eq(binder.occupied_count(), 1)
	assert_eq(binder.disconnected_slots(), [0] as Array[int])

func test_a_reserved_seat_is_not_offered_to_a_new_player() -> void:
	_join(0)
	_join(1)
	binder.device_removed(0)
	assert_eq(_join(5, OTHER_GUID), 2, "a joining pad skips the held seat")
	assert_true(binder.slots[0].is_awaiting_reconnect())

func test_removing_an_unbound_device_does_nothing() -> void:
	_join(0)
	assert_eq(binder.device_removed(3), -1)
	assert_eq(binder.occupied_count(), 1)

func test_a_reused_device_index_does_not_resurrect_a_stale_binding() -> void:
	# Godot's device index is a slot in its own table and gets reused. If the
	# binder matched on it, a stranger's pad would inherit P1's seat.
	_join(0)
	binder.device_removed(0)
	assert_eq(binder.slot_of_pad(0), -1, "nothing may match the vanished index")
	assert_eq(binder.device_added(0, OTHER_GUID, "Some Other Pad"), -1, "a different pad is not a reconnect")
	assert_true(binder.slots[0].is_awaiting_reconnect(), "P1 keeps waiting")

# --- Hot-plug: reconnect -----------------------------------------------------

func test_unambiguous_guid_rebinds_itself() -> void:
	_join(0)
	_join(1, OTHER_GUID)
	binder.device_removed(0)
	assert_eq(binder.device_added(6, F310_GUID, F310_NAME), 0, "one seat waiting: just give it back")
	var slot: PlayerSlot = binder.slots[0]
	assert_true(slot.is_occupied())
	assert_eq(slot.pad_device, 6, "and it holds the *new* device index")
	assert_true(binder.disconnected_slots().is_empty())
	assert_true(slot.source is GamepadSource, "a rebound seat gets a working source")

func test_identical_pads_are_not_guessed_at() -> void:
	# Four F310s share one GUID, which is exactly the reference hardware. There
	# is no way to tell two of them apart, so the binder must not pretend.
	_join(0)
	_join(1)
	binder.device_removed(0)
	binder.device_removed(1)
	assert_eq(binder.device_added(4, F310_GUID, F310_NAME), -1, "ambiguous: do not auto-bind")
	assert_eq(binder.disconnected_slots(), [0, 1] as Array[int], "both seats still waiting")

func test_press_to_claim_resolves_identical_pads_in_slot_order() -> void:
	_join(0)
	_join(1)
	binder.device_removed(0)
	binder.device_removed(1)
	assert_eq(binder.claim_awaiting(4, F310_GUID, F310_NAME), 0, "lowest waiting seat first")
	assert_eq(binder.claim_awaiting(5, F310_GUID, F310_NAME), 1)
	assert_true(binder.disconnected_slots().is_empty())
	assert_eq(binder.slots[0].pad_device, 4)
	assert_eq(binder.slots[1].pad_device, 5)

func test_claiming_with_nothing_waiting_is_refused() -> void:
	_join(0)
	assert_eq(binder.claim_awaiting(9, OTHER_GUID, "x"), -1, "press-to-claim is not a join")
	assert_eq(binder.occupied_count(), 1)

func test_a_seated_pad_cannot_claim_a_reserved_seat() -> void:
	_join(0)
	_join(1)
	binder.device_removed(1)
	assert_eq(binder.claim_awaiting(0, F310_GUID, F310_NAME), -1, "device 0 is already playing")
	assert_true(binder.slots[1].is_awaiting_reconnect())

func test_leaving_a_reserved_seat_drops_its_reservation() -> void:
	_join(0)
	binder.device_removed(0)
	binder.leave(0)
	assert_eq(binder.device_added(8, F310_GUID, F310_NAME), -1, "nothing is waiting any more")
	assert_eq(binder.slots[0].kind, PlayerSlot.Kind.EMPTY)

func test_release_awaiting_frees_only_the_reserved_seats() -> void:
	_join(0)
	_join(1, OTHER_GUID)
	binder.add_bot()
	binder.device_removed(0)
	assert_eq(binder.release_awaiting(), [0] as Array[int])
	assert_eq(binder.slots[0].kind, PlayerSlot.Kind.EMPTY)
	assert_true(binder.slots[1].is_occupied(), "the connected pad is untouched")
	assert_eq(binder.slots[2].kind, PlayerSlot.Kind.BOT, "and so is the bot")
	assert_true(binder.release_awaiting().is_empty(), "second call has nothing to do")

# --- Start conditions --------------------------------------------------------

func test_can_start_needs_two_players() -> void:
	assert_false(binder.can_start(), "an empty lobby cannot start")
	_join(0)
	assert_false(binder.can_start(), "a one-player round has nothing in it")
	binder.add_bot()
	assert_true(binder.can_start(), "a human and a bot is a game")

func test_a_reserved_seat_blocks_the_start() -> void:
	_join(0)
	_join(1)
	_join(2)
	binder.device_removed(2)
	assert_false(binder.can_start(), "starting would give that player a card and no body")

func test_active_flags_are_index_aligned_with_the_slots() -> void:
	_join(0)
	binder.add_bot()
	var flags: Array[bool] = binder.active_flags()
	assert_eq(flags.size(), C.MAX_PLAYERS)
	assert_eq(flags, [true, true, false, false] as Array[bool])
	binder.device_removed(0)
	assert_eq(binder.active_flags(), [false, true, false, false] as Array[bool],
		"a waiting seat is not active")

func test_clear_all_empties_the_roster() -> void:
	_join(0)
	binder.add_bot()
	binder.device_removed(0)
	binder.clear_all()
	assert_eq(binder.occupied_count(), 0)
	assert_true(binder.disconnected_slots().is_empty())
	assert_eq(binder.first_free_slot(), 0)

# --- Card text ---------------------------------------------------------------

func test_card_text_tells_a_player_what_is_in_the_seat() -> void:
	assert_eq(binder.slots[0].card_lines()[0], "press A")
	_join(0)
	assert_eq(binder.slots[0].card_lines()[0], "PAD 0")
	assert_eq(binder.slots[0].card_lines()[1], "F310", "the long vendor name does not fit a 140 px card")
	binder.device_removed(0)
	assert_eq(binder.slots[0].card_lines()[1], "reconnect!")

# --- Helpers -----------------------------------------------------------------

func _join(device_id: int, guid: String = F310_GUID) -> int:
	return binder.join_pad(device_id, guid, F310_NAME)
