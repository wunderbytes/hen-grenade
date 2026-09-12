extends SceneTree
## Headless test runner. Invoked as a custom main loop:
##   godot --headless --path <project> --script res://tests/run_tests.gd
##
## Discovers every test_*.gd under tests/unit/, runs its test_* methods, prints
## a per-suite summary, and exits non-zero on any failure.
## See docs/milestone-1-brief.md §10.
##
## Two constraints from M0's lessons shape this file (technical-design.md
## Appendix A): the work happens in _init() because a GDScript override of
## SceneTree._iteration is silently ignored (A.4), and nothing here may touch an
## autoload because --script mode does not register them (A.2). The simulation
## layer is pure by design, so that second constraint costs us nothing.

const TEST_DIR: String = "res://tests/unit"

func _init() -> void:
	var paths: Array[String] = _discover_suites(TEST_DIR)
	if paths.is_empty():
		printerr("FAIL  no test suites found under %s" % TEST_DIR)
		quit(1)
		return

	var total_tests: int = 0
	var total_passed: int = 0
	var total_failures: int = 0

	for path in paths:
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

		var suite: TestCase = instance as TestCase
		suite.run_all()
		total_tests += suite.test_count
		total_passed += suite.passed_count
		total_failures += suite.failures.size()

		if suite.failures.is_empty():
			print("  PASS  %-20s %d test(s)" % [suite.suite_name(), suite.test_count])
		else:
			print("  FAIL  %-20s %d/%d test(s) passed" % [suite.suite_name(), suite.passed_count, suite.test_count])
			for message in suite.failures:
				printerr("          %s" % message)

	print("\n==== %d suite(s), %d test(s), %d passed, %d failure(s) ====" % [
		paths.size(), total_tests, total_passed, total_failures
	])
	quit(0 if total_failures == 0 else 1)

## Sorted so the run order is stable. A suite that forgot to get added to a
## hand-maintained list is a test that silently never runs, which is why this
## scans the directory instead — and why an empty result is a hard failure
## rather than a vacuous pass.
func _discover_suites(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		printerr("FAIL  cannot open %s" % dir_path)
		return out
	for file_name in dir.get_files():
		# Godot hands back the pre-import name in some contexts; normalise.
		var name: String = file_name.trim_suffix(".remap")
		if name.begins_with("test_") and name.ends_with(".gd"):
			out.append("%s/%s" % [dir_path, name])
	out.sort()
	return out
