class_name DragScroll
extends ScrollContainer
## Vertical list you scroll by dragging anywhere on it (finger or mouse),
## with a little momentum, like a phone list. The plain ScrollContainer only
## drag-scrolls on touch devices and only if no button swallows the press,
## so lists of buttons could only be moved with the thin scroll bar.
## Buttons inside must use MOUSE_FILTER_PASS so presses reach this container,
## and should ignore their press when `was_dragged()` is true.

const DEADZONE := 12.0
const FRICTION := 6.0  # momentum decay per second

var _pressing := false
var _dragging := false
var _last_y := 0.0
var _start_y := 0.0
var _vel := 0.0  # px/s, positive = content moves down


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Keep a slim bar as a "there's more" hint, not as the way to scroll.
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(1, 1, 1, 0.28)
	grab.set_corner_radius_all(3)
	grab.content_margin_left = 3
	grab.content_margin_right = 3
	var bar := get_v_scroll_bar()
	for s in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(s, grab)
	bar.add_theme_stylebox_override("scroll", StyleBoxEmpty.new())
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE


## True if the current/last press moved far enough to count as a scroll.
func was_dragged() -> bool:
	return _dragging


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_pressing = true
			_dragging = false
			_start_y = e.global_position.y
			_last_y = _start_y
			_vel = 0.0
		else:
			_pressing = false
		accept_event()  # handled here, so the built-in touch drag doesn't double up
	elif e is InputEventMouseMotion and _pressing:
		var y: float = e.global_position.y
		if not _dragging and absf(y - _start_y) > DEADZONE:
			_dragging = true
			_last_y = y
		if _dragging:
			var dy := y - _last_y
			_last_y = y
			_scroll_by(-dy)
			var dt := maxf(get_process_delta_time(), 1.0 / 120.0)
			_vel = lerpf(_vel, dy / dt, 0.5)
		accept_event()
	elif e is InputEventScreenDrag or e is InputEventScreenTouch:
		accept_event()  # emulated mouse events above do the work


func _process(delta: float) -> void:
	if _pressing or absf(_vel) < 20.0:
		return
	_scroll_by(-_vel * delta)
	_vel *= exp(-FRICTION * delta)


func _scroll_by(px: float) -> void:
	var bar := get_v_scroll_bar()
	var before := bar.value
	bar.value = clampf(bar.value + px, bar.min_value, maxf(bar.min_value, bar.max_value - bar.page))
	if is_equal_approx(before, bar.value):
		_vel = 0.0
