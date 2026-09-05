extends SceneTree
## Minimal headless test runner. Invoked as a custom main loop:
##   godot --headless --path <project> --script res://tests/run_tests.gd
## It loads every TestCase under tests/unit/, runs its test_* methods, prints a
## summary, and exits non-zero on any failure. Replaced by GUT in M1.
## See docs/milestone-0-brief.md §9.

const TEST_SCRIPTS: Array[String] = [
	"res://tests/unit/test_input_frame.gd",
]

func _init() -> void:
	var total_failures: int = 0
	for path in TEST_SCRIPTS:
		var script: GDScript = load(path) as GDScript
		if script == null:
			printerr("  FAIL  could not load %s" % path)
			total_failures += 1
			continue
		var instance: Object = script.new()
		if not (instance is TestCase):
			printerr("  FAIL  %s does not extend TestCase" % path)
			total_failures += 1
			continue
		var failures: Array[String] = (instance as TestCase).run_all()
		if failures.is_empty():
			print("  PASS  %s" % path)
		else:
			for fmsg in failures:
				printerr("  FAIL  %s" % fmsg)
			total_failures += failures.size()
	print("\n==== test run: %d suite(s), %d failure(s) ====" % [TEST_SCRIPTS.size(), total_failures])
	quit(0 if total_failures == 0 else 1)
