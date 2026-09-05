class_name TestCase
## Minimal test-case base. M0 uses a tiny self-contained harness instead of GUT
## to avoid vendoring a third-party addon before there is anything real to test.
## GUT should replace this in M1 when the simulation layer needs real coverage.
## See docs/milestone-0-brief.md §9.

var failures: Array[String] = []
var _current_test: String = ""

func run_all() -> Array[String]:
	var methods: Array[String] = []
	for m in get_method_list():
		var mname: String = String(m["name"])
		if mname.begins_with("test_"):
			methods.append(mname)
	methods.sort()
	for m in methods:
		_current_test = m
		call(m)
	return failures

func assert_true(cond: bool, msg: String = "expected true") -> void:
	if not cond:
		_fail(msg)

func assert_false(cond: bool, msg: String = "expected false") -> void:
	if cond:
		_fail(msg)

func assert_eq(a: Variant, b: Variant, msg: String = "") -> void:
	if a != b:
		_fail("%s — got %s, expected %s" % [msg if msg != "" else "not equal", str(a), str(b)])

func _fail(msg: String) -> void:
	failures.append("%s::%s: %s" % [get_class(), _current_test, msg])
