extends TestCase
## Lobby mode cycling. See docs/milestone-3.5-brief.md §5.1.

func before_each() -> void:
	Session.reset()

func after_each() -> void:
	Session.reset()

func test_default_is_deathmatch() -> void:
	assert_eq(Session.mode_id, Session.MODE_DEATHMATCH, "default")
	assert_false(Session.is_hen(), "default is hen")

func test_cycle_wraps_between_deathmatch_and_hen() -> void:
	Session.cycle(1)
	assert_eq(Session.mode_id, Session.MODE_HEN, "next from deathmatch")
	Session.cycle(1)
	assert_eq(Session.mode_id, Session.MODE_DEATHMATCH, "wrap forward")
	Session.cycle(-1)
	assert_eq(Session.mode_id, Session.MODE_HEN, "wrap backward")
	Session.cycle(-1)
	assert_eq(Session.mode_id, Session.MODE_DEATHMATCH, "back to default")
