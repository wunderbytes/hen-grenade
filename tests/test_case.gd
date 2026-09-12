class_name TestCase
## Base class for a test suite. See docs/milestone-1-brief.md §10.
##
## This is a deliberately small in-repo harness rather than GUT. The decision
## was revisited in M1 and confirmed: the simulation layer is pure GDScript with
## no Nodes and no autoloads, which is exactly the case a hundred-line runner
## handles well, and vendoring ~100 files of third-party addon to obtain
## assertion sugar we can write in forty lines is a poor trade. See
## docs/technical-design.md §8.
##
## Write a suite as `extends TestCase` with `test_*` methods. They run in sorted
## order, each wrapped in before_each/after_each. A method that fails an
## assertion keeps running — assertions record rather than abort — so one test
## can report several problems at once.

var failures: Array[String] = []
var test_count: int = 0
var passed_count: int = 0

var _current_test: String = ""
var _current_failed: bool = false

# --- Lifecycle --------------------------------------------------------------

## Override to build fresh fixtures. Runs before every test_* method, so no
## test can be polluted by a previous one's state.
func before_each() -> void:
	pass

func after_each() -> void:
	pass

func run_all() -> void:
	for method_name in _test_methods():
		_current_test = method_name
		_current_failed = false
		test_count += 1
		before_each()
		call(method_name)
		after_each()
		if not _current_failed:
			passed_count += 1

func suite_name() -> String:
	var script: Script = get_script() as Script
	if script == null or script.resource_path == "":
		return "TestCase"
	return script.resource_path.get_file().get_basename()

func _test_methods() -> Array[String]:
	var out: Array[String] = []
	for m in get_method_list():
		var mname: String = String(m["name"])
		if mname.begins_with("test_"):
			out.append(mname)
	out.sort()
	return out

# --- Assertions -------------------------------------------------------------

func assert_true(cond: bool, msg: String = "expected true") -> void:
	if not cond:
		_fail(msg)

func assert_false(cond: bool, msg: String = "expected false") -> void:
	if cond:
		_fail(msg)

func assert_eq(a: Variant, b: Variant, msg: String = "") -> void:
	if a != b:
		_fail("%s — got %s, expected %s" % [_label(msg, "not equal"), str(a), str(b)])

func assert_ne(a: Variant, b: Variant, msg: String = "") -> void:
	if a == b:
		_fail("%s — both are %s, expected them to differ" % [_label(msg, "unexpectedly equal"), str(a)])

func assert_gt(a: int, b: int, msg: String = "") -> void:
	if a <= b:
		_fail("%s — got %d, expected > %d" % [_label(msg, "not greater"), a, b])

func assert_ge(a: int, b: int, msg: String = "") -> void:
	if a < b:
		_fail("%s — got %d, expected >= %d" % [_label(msg, "not at least"), a, b])

func assert_lt(a: int, b: int, msg: String = "") -> void:
	if a >= b:
		_fail("%s — got %d, expected < %d" % [_label(msg, "not less"), a, b])

func assert_le(a: int, b: int, msg: String = "") -> void:
	if a > b:
		_fail("%s — got %d, expected <= %d" % [_label(msg, "not at most"), a, b])

func assert_in_range(v: int, lo: int, hi: int, msg: String = "") -> void:
	if v < lo or v > hi:
		_fail("%s — got %d, expected within [%d, %d]" % [_label(msg, "out of range"), v, lo, hi])

func assert_null(v: Variant, msg: String = "") -> void:
	if v != null:
		_fail("%s — got %s, expected null" % [_label(msg, "not null"), str(v)])

func assert_not_null(v: Variant, msg: String = "") -> void:
	if v == null:
		_fail(_label(msg, "unexpectedly null"))

## Records a failure without an assertion, for "we should never get here" paths.
func fail(msg: String) -> void:
	_fail(msg)

func _label(msg: String, fallback: String) -> String:
	return msg if msg != "" else fallback

func _fail(msg: String) -> void:
	_current_failed = true
	failures.append("%s::%s: %s" % [suite_name(), _current_test, msg])
