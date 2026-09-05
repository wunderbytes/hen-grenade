extends CanvasLayer
## On-screen metrics overlay good enough to make performance decisions from.
## See docs/milestone-0-brief.md §6.3.
##
## Reads Performance monitors and keeps a rolling p99 of frame time over the
## last 600 frames. The average FPS will read 60.0 while the game visibly
## hitches; the p99 frame time is what tells the truth.

const HISTORY_SIZE: int = 600

var _label: Label
var _frame_times: Array[float] = []
var _p99: float = 0.0
var _enabled: bool = true

func _ready() -> void:
	layer = 100
	_label = Label.new()
	_label.name = "MetricsLabel"
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_color", Color(0.9, 0.95, 0.8, 0.95))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.position = Vector2(4, 4)
	_label.vertical_alignment = 0  # top
	add_child(_label)

func _physics_process(_delta: float) -> void:
	if not _enabled:
		return
	# Record the *previous* frame's process time as the frame time proxy.
	# TIME_PROCESS is the time spent in process + physics in seconds.
	var frame_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_frame_times.append(frame_ms)
	if _frame_times.size() > HISTORY_SIZE:
		_frame_times.pop_front()
	_p99 = _compute_p99()

func _process(_delta: float) -> void:
	if not _enabled or not is_instance_valid(_label):
		return
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var frame_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objects: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var video_mem_mb: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0)
	var static_mem_mb: float = Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)
	_label.text = "FPS %.1f   frame %.1f ms   p99 %.1f ms\ndraw calls %d   objects %d\nvideo mem %.0f MB   static mem %.0f MB" % [fps, frame_ms, _p99, draw_calls, objects, video_mem_mb, static_mem_mb]

func _compute_p99() -> float:
	if _frame_times.is_empty():
		return 0.0
	var sorted: Array[float] = _frame_times.duplicate()
	sorted.sort()
	# p99 index: 99th percentile of the sorted window.
	var idx: int = clampi(int(ceil(sorted.size() * 0.99)) - 1, 0, sorted.size() - 1)
	return sorted[idx]

func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if _label:
		_label.visible = enabled

func is_enabled() -> bool:
	return _enabled
