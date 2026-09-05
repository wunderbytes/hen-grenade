class_name KeyboardSource
extends InputSource
## Reads the built-in keyboard directly. On a Pi 400 this is a real player slot,
## not a debug affordance, so it gets the same care as gamepad input.
## See docs/milestone-0-brief.md §5.4 and docs/technical-design.md §4.
##
## Two layouts are supported so two players can share one board:
##   Layout.WASD   - W/A/S/D move, Space = bomb, Q = action
##   Layout.ARROWS - Arrow keys move, Right Ctrl = bomb, Slash = action
##
## Like GamepadSource this bypasses the InputMap and polls physical keys
## directly, so multiple keyboard slots never alias into a single player.

enum Layout { WASD = 0, ARROWS = 1 }

var layout: Layout = Layout.WASD

func _init(p_layout: Layout = Layout.WASD) -> void:
	layout = p_layout

func poll(_tick: int) -> InputFrame:
	var frame: InputFrame = InputFrame.new()
	match layout:
		Layout.WASD:
			frame.dir = _read_wasd()
			frame.bomb = Input.is_key_pressed(KEY_SPACE)
			frame.action = Input.is_key_pressed(KEY_Q)
		Layout.ARROWS:
			frame.dir = _read_arrows()
			# Right Ctrl is the brief's stated bomb key for the arrows layout.
			# KEY_CTRL fires for either ctrl; the WASD layout never reads it, so
			# there is no cross-player aliasing on a shared board.
			frame.bomb = Input.is_key_pressed(KEY_CTRL)
			frame.action = Input.is_key_pressed(KEY_SLASH)
	return frame

func label() -> String:
	match layout:
		Layout.WASD:
			return "Keyboard (WASD)"
		Layout.ARROWS:
			return "Keyboard (Arrows)"
	return "Keyboard"

func _read_wasd() -> InputFrame.Dir:
	if Input.is_key_pressed(KEY_W):
		return InputFrame.Dir.UP
	if Input.is_key_pressed(KEY_S):
		return InputFrame.Dir.DOWN
	if Input.is_key_pressed(KEY_A):
		return InputFrame.Dir.LEFT
	if Input.is_key_pressed(KEY_D):
		return InputFrame.Dir.RIGHT
	return InputFrame.Dir.NONE

func _read_arrows() -> InputFrame.Dir:
	if Input.is_key_pressed(KEY_UP):
		return InputFrame.Dir.UP
	if Input.is_key_pressed(KEY_DOWN):
		return InputFrame.Dir.DOWN
	if Input.is_key_pressed(KEY_LEFT):
		return InputFrame.Dir.LEFT
	if Input.is_key_pressed(KEY_RIGHT):
		return InputFrame.Dir.RIGHT
	return InputFrame.Dir.NONE
