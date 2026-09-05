class_name GamepadSource
extends InputSource
## Reads a single gamepad device directly by index, bypassing the InputMap.
## See docs/milestone-0-brief.md §5.3 and docs/technical-design.md §4.
##
## The InputMap aggregates across all devices, which is wrong for local
## multiplayer. We poll our own device index instead:
##   Input.is_joy_button_pressed(device_id, JOY_BUTTON_A)
##   Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X)
##
## Stick-to-direction conversion: magnitude threshold 0.5 to engage, 0.35 to
## release (hysteresis), D-pad takes priority over the stick when both active.

const ENGAGE_THRESHOLD: float = 0.5
const RELEASE_THRESHOLD: float = 0.35

var device_id: int = -1
var device_name: String = ""
var _last_dir: InputFrame.Dir = InputFrame.Dir.NONE

func _init(p_device_id: int = -1, p_device_name: String = "") -> void:
	device_id = p_device_id
	device_name = p_device_name

func poll(_tick: int) -> InputFrame:
	var frame: InputFrame = InputFrame.new()
	if device_id < 0 or not Input.is_joy_known(device_id):
		return frame

	# D-pad takes priority over the analog stick when both are active.
	var dir: InputFrame.Dir = _read_dpad()
	if dir == InputFrame.Dir.NONE:
		dir = _read_stick()

	frame.dir = dir
	_last_dir = dir
	frame.bomb = Input.is_joy_button_pressed(device_id, JOY_BUTTON_A)
	frame.action = Input.is_joy_button_pressed(device_id, JOY_BUTTON_B)
	return frame

func label() -> String:
	return "Pad %d (%s)" % [device_id, device_name if device_name != "" else "unknown"]

func _read_dpad() -> InputFrame.Dir:
	if Input.is_joy_button_pressed(device_id, JOY_BUTTON_DPAD_UP):
		return InputFrame.Dir.UP
	if Input.is_joy_button_pressed(device_id, JOY_BUTTON_DPAD_DOWN):
		return InputFrame.Dir.DOWN
	if Input.is_joy_button_pressed(device_id, JOY_BUTTON_DPAD_LEFT):
		return InputFrame.Dir.LEFT
	if Input.is_joy_button_pressed(device_id, JOY_BUTTON_DPAD_RIGHT):
		return InputFrame.Dir.RIGHT
	return InputFrame.Dir.NONE

func _read_stick() -> InputFrame.Dir:
	var x: float = Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X)
	var y: float = Input.get_joy_axis(device_id, JOY_AXIS_LEFT_Y)
	# Dead-zone the raw axis a little so a resting stick never engages.
	if absf(x) < 0.1 and absf(y) < 0.1:
		return _hysteresis(0.0, 0.0)
	return _hysteresis(x, y)

func _hysteresis(x: float, y: float) -> InputFrame.Dir:
	# Pick the dominant axis, then apply engage/release thresholds based on the
	# magnitude along that axis relative to the last engaged direction.
	var ax: float = absf(x)
	var ay: float = absf(y)
	if ax < 0.05 and ay < 0.05:
		return InputFrame.Dir.NONE

	var threshold: float = ENGAGE_THRESHOLD
	# If we are already engaged along an axis, use the lower release threshold
	# to avoid jitter at the boundary.
	match _last_dir:
		InputFrame.Dir.LEFT, InputFrame.Dir.RIGHT:
			if ax >= RELEASE_THRESHOLD:
				threshold = RELEASE_THRESHOLD
		InputFrame.Dir.UP, InputFrame.Dir.DOWN:
			if ay >= RELEASE_THRESHOLD:
				threshold = RELEASE_THRESHOLD

	if ax >= ay:
		if ax >= threshold:
			return InputFrame.Dir.LEFT if x < 0.0 else InputFrame.Dir.RIGHT
	else:
		if ay >= threshold:
			return InputFrame.Dir.UP if y < 0.0 else InputFrame.Dir.DOWN
	return InputFrame.Dir.NONE
