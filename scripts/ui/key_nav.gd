class_name KeyNav
extends Control
## Keyboard menus (CrazyGames Phase S6, every build): arrow keys or WASD move a
## glowing ring between the buttons of the topmost open screen or popup,
## Enter/Space presses, Backspace (and Esc where it's free) goes back.
## The ring appears on the first key press (that press only shows it) and
## hides on mouse or touch, so touch players never see it.
## It keeps its own "current" button instead of Godot focus, so a button
## clicked earlier can never be pressed by Space in a run, and a popup keeps
## the keys to itself: only buttons inside the topmost registered scope
## (UiKit.overlay roots, shop/Lab popups, the cheat menu) are reachable.
## Main adds one to the UI and says on which screens it is active.

static var scopes: Array = []  # Controls registered as key scopes

var enabled_fn := Callable()  # -> bool: keyboard menus active on this screen
var back_fn := Callable()  # Back when the scope has no nav_back of its own
var esc_back := true  # Esc also goes back (not on CrazyGames: Esc leaves fullscreen)
var accent := Color("#ffd166")
var kb := false  # keyboard mode: the ring shows
var cur: Control = null
var _scope: Control = null
var _rect := Rect2()  # the ring, sliding toward the current button
var _pop := 1.0  # 0 → 1 spring-in after each move
var _nudge := Vector2.ZERO  # no button that way: a small push
var _t := 0.0
var _pressed: Array = []  # recently pressed buttons {text, pos}, to return to them
var _sb := StyleBoxFlat.new()
var _glow := StyleBoxFlat.new()


## A full-screen node whose buttons form one key scope (topmost visible wins).
## `back` runs on Backspace/Esc while it is on top.
static func register(scope: Control, back: Callable = Callable()) -> void:
	if back.is_valid():
		scope.set_meta("nav_back", back)
	scopes = scopes.filter(func(s: Variant) -> bool: return is_instance_valid(s))
	scopes.append(scope)


## The button the ring starts on when its screen opens.
static func first(c: Control) -> Control:
	c.set_meta("nav_first", true)
	return c


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in [_sb, _glow]:
		s.draw_center = false
		s.set_corner_radius_all(22)
		s.anti_aliasing = true
	_sb.set_border_width_all(4)
	_glow.set_border_width_all(10)


# ------------------------------------------------------------------ input

func _input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		if kb and (e as InputEventMouseMotion).relative.length() > 3.0:
			_set_kb(false)
		return
	if e is InputEventMouseButton or e is InputEventScreenTouch:
		if kb:
			_set_kb(false)
		return
	if not (e is InputEventKey) or not e.pressed or not enabled_fn.is_valid() or not enabled_fn.call():
		return
	var k: int = (e as InputEventKey).physical_keycode
	var dir := Vector2.ZERO
	match k:
		KEY_UP, KEY_W:
			dir = Vector2.UP
		KEY_DOWN, KEY_S:
			dir = Vector2.DOWN
		KEY_LEFT, KEY_A:
			dir = Vector2.LEFT
		KEY_RIGHT, KEY_D:
			dir = Vector2.RIGHT
	var accept := k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	var back := k == KEY_BACKSPACE or (k == KEY_ESCAPE and esc_back)
	var tab := k == KEY_TAB
	if dir == Vector2.ZERO and not accept and not back and not tab:
		return
	get_viewport().set_input_as_handled()
	if back:
		if not e.echo:
			_back()
		return
	var scope := _top_scope()
	if scope == null:
		return
	var cands := candidates(scope)
	if not kb or not cands.has(cur):
		_set_kb(true)
		var f := _pick_first(scope, cands)
		if f != null and f == cur:
			_pop = 0.0
			_bump(cur)
			_scroll_to(cur)
		else:
			_select(f, false)
		_scope = scope
		return  # the first key only shows where you are
	if accept:
		if not e.echo:
			_press(cur)
		return
	if tab:
		var i := cands.find(cur)
		_select(cands[posmod(i + (-1 if (e as InputEventKey).shift_pressed else 1), cands.size())])
		return
	if cur is Range and dir.x != 0.0:
		var r := cur as Range
		r.value += dir.x * (r.step if r.step > 0.0 else (r.max_value - r.min_value) / 20.0)
		Sfx.play("click", 0.0, 0.9 + 0.3 * (r.value - r.min_value) / maxf(r.max_value - r.min_value, 0.001))
		return
	var rects: Array = []
	for c: Control in cands:
		rects.append(_grect(c))
	var n := pick(_grect(cur), rects, dir)
	if n >= 0 and cands[n] != cur:
		_select(cands[n])
	else:
		_nudge = dir * 10.0


func _back() -> void:
	var scope := _top_scope()
	if scope != null and scope.has_meta("nav_back"):
		var cb: Callable = scope.get_meta("nav_back")
		if cb.is_valid():
			Sfx.play("click", 0.0, 0.8)
			cb.call()
			return
	if back_fn.is_valid():
		back_fn.call()


func _press(c: Control) -> void:
	if not (c is BaseButton) or (c as BaseButton).disabled:
		return
	_pressed.push_front({"text": _text(c), "pos": _grect(c).get_center()})
	_pressed.resize(mini(_pressed.size(), 8))
	c.pivot_offset = c.size / 2.0
	var tw := c.create_tween()  # the same squash and spring as a tap
	tw.tween_property(c, "scale", Vector2(0.93, 0.9), 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2(1.05, 1.05), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", _bump_scale(c), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var b := c as BaseButton
	if b.toggle_mode:
		b.button_pressed = not b.button_pressed
	b.pressed.emit()


# --------------------------------------------------------------- choosing

## Index of the best rect to move to from `from` in direction `dir`, or -1.
## Prefers rects straight ahead (overlapping across the move), then the
## nearest; a rect must lie past the current one's centre in that direction.
static func pick(from: Rect2, rects: Array, dir: Vector2) -> int:
	var c := from.get_center()
	var side := Vector2(-dir.y, dir.x)
	var best := -1
	var best_s := INF
	for i in rects.size():
		var r: Rect2 = rects[i]
		var d := r.get_center() - c
		var along := d.dot(dir)
		if along <= 4.0:
			continue
		# Gap across the move: 0 when the two rects overlap side by side.
		var gap := 0.0
		if dir.x != 0.0:
			gap = maxf(0.0, maxf(from.position.y - r.end.y, r.position.y - from.end.y))
		else:
			gap = maxf(0.0, maxf(from.position.x - r.end.x, r.position.x - from.end.x))
		var edge := maxf(0.0, along - (absf(dir.x) * (from.size.x + r.size.x) + absf(dir.y) * (from.size.y + r.size.y)) / 2.0)
		var s := edge + gap * 3.0 + absf(d.dot(side)) * 0.15 + (0.0 if gap == 0.0 else 400.0)
		if s < best_s:
			best_s = s
			best = i
	return best


## Buttons (and sliders) in `scope` that can be reached now, in tree order.
static func candidates(scope: Control) -> Array:
	var out: Array = []
	_collect(scope, scope, out)
	return out


static func _collect(n: Node, scope: Control, out: Array) -> void:
	for ch in n.get_children():
		if not (ch is Control):
			continue
		var c := ch as Control
		if not c.visible or (c != scope and scopes.has(c)):
			continue  # hidden, or a scope of its own (a popup is reached only when it's on top)
		if (c is BaseButton and not (c as BaseButton).disabled) or c is Range and c is Slider:
			if c.mouse_filter != Control.MOUSE_FILTER_IGNORE and c.size.x > 4.0 and not c.has_meta("nav_skip"):
				out.append(c)
				continue
		_collect(c, scope, out)


func _top_scope() -> Control:
	var top: Control = null
	for s in scopes:
		if not is_instance_valid(s) or not (s as Control).is_visible_in_tree():
			continue
		if top == null or (s as Node).is_greater_than(top):
			top = s
	return top


func _pick_first(scope: Control, cands: Array) -> Control:
	if cands.is_empty():
		return null
	if cands.has(cur):
		return cur
	for p in _pressed:  # back on a screen: the button you used to leave it
		var best: Control = null
		var bd := INF
		for c: Control in cands:
			var d := _grect(c).get_center().distance_squared_to(p.pos)
			var same: bool = _text(c) == p.text if p.text != "" else d < 40.0 * 40.0  # icon tiles: same spot
			if same:
				if d < bd:
					bd = d
					best = c
		if best != null:
			return best
	for c: Control in cands:
		if c.has_meta("nav_first"):
			return c
	return cands[0]


func _select(c: Control, sound: bool = true) -> void:
	if c == cur:
		return
	if is_instance_valid(cur):
		_unbump(cur)
	cur = c
	if c == null:
		return
	_pop = 0.0
	if not kb:
		return
	_bump(c)
	if sound:
		Sfx.play("click", 0.0, 0.72)
	_scroll_to(c)


func _set_kb(on: bool) -> void:
	kb = on
	if not on and is_instance_valid(cur):
		_unbump(cur)
	if on:
		_rect = Rect2()
	queue_redraw()


# ------------------------------------------------------------- feedback

func _bump_scale(c: Control) -> Vector2:
	if not kb or c != cur or c.has_meta("nav_no_bump"):
		return Vector2.ONE
	return Vector2.ONE * (1.0 + clampf(12.0 / maxf(maxf(c.size.x, c.size.y), 1.0), 0.02, 0.07))


func _bump(c: Control) -> void:
	c.pivot_offset = c.size / 2.0
	var tw := c.create_tween().set_parallel(true)
	if not c.has_meta("nav_no_bump"):
		tw.tween_property(c, "scale", _bump_scale(c), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "self_modulate", Color(1.15, 1.15, 1.15), 0.1)


func _unbump(c: Control) -> void:
	var tw := c.create_tween().set_parallel(true)
	if not c.has_meta("nav_no_bump"):
		tw.tween_property(c, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "self_modulate", Color.WHITE, 0.12)


## Keeps the current button inside its scrolling list (a smooth scroll).
func _scroll_to(c: Control) -> void:
	var p := c.get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	if p == null:
		return
	var sc := p as ScrollContainer
	var view := sc.get_global_rect()
	var r := _grect(c)
	var margin := 40.0
	var dy := 0.0
	if r.position.y < view.position.y + margin:
		dy = r.position.y - view.position.y - margin
	elif r.end.y > view.end.y - margin:
		dy = r.end.y - view.end.y + margin
	if absf(dy) < 1.0:
		return
	var to := clampi(sc.scroll_vertical + int(dy / maxf(sc.get_global_transform().get_scale().y, 0.01)), 0, int(sc.get_v_scroll_bar().max_value))
	sc.create_tween().tween_property(sc, "scroll_vertical", to, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if get_index() != get_parent().get_child_count() - 1:
		move_to_front.call_deferred()  # stay above overlays opened later
	if not kb:
		return
	if not enabled_fn.is_valid() or not enabled_fn.call():
		_set_kb(false)
		return
	_t += delta
	var scope := _top_scope()
	if scope != _scope:
		_scope = scope
		if scope != null:
			_select(_pick_first(scope, candidates(scope)))
	elif scope != null and (not is_instance_valid(cur) or not cur.is_visible_in_tree() or (cur is BaseButton and (cur as BaseButton).disabled)):
		cur = null  # its screen was rebuilt: pick again on the new one
		_select(_pick_first(scope, candidates(scope)))
	if not is_instance_valid(cur):
		queue_redraw()
		return
	var target := _grect(cur)
	if _rect.size == Vector2.ZERO:
		_rect = target
	var k := 1.0 - exp(-20.0 * delta)
	_rect = Rect2(_rect.position.lerp(target.position, k), _rect.size.lerp(target.size, k))
	_pop = minf(_pop + delta / 0.22, 1.0)
	_nudge = _nudge.lerp(Vector2.ZERO, 1.0 - exp(-14.0 * delta))
	queue_redraw()


func _draw() -> void:
	if not kb or not is_instance_valid(cur) or _rect.size == Vector2.ZERO:
		return
	draw_set_transform_matrix(get_global_transform().affine_inverse())
	var e := 1.0 - pow(1.0 - _pop, 3.0)  # ease out
	var grow := 6.0 + (1.0 - e) * 14.0
	var r := Rect2(_rect.position + _nudge, _rect.size).grow(grow)
	var radius := int(clampf(minf(r.size.x, r.size.y) * 0.3, 10.0, 30.0))
	var pulse := 0.85 + 0.15 * sin(_t * 6.0)
	_glow.set_corner_radius_all(radius + 4)
	_glow.border_color = Color(accent, 0.45 * pulse * e)
	draw_style_box(_glow, r.grow(5.0))
	_sb.set_corner_radius_all(radius)
	_sb.border_color = Color(Color.WHITE, pulse * e)  # white core: shows on gold buttons too
	draw_style_box(_sb, r)


# ---------------------------------------------------------------- helpers

static func _grect(c: Control) -> Rect2:
	return c.get_global_transform() * Rect2(Vector2.ZERO, c.size)


static func _text(c: Control) -> String:
	return (c as Button).text if c is Button else ""
