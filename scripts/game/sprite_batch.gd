class_name SpriteBatch
extends Node2D
## Draws many copies of one texture cheaply: every sprite is a textured rect
## from the same texture, which the Compatibility renderer merges into very
## few draw calls (far cheaper than draw_circle per shape). Per-sprite colour
## tints the white texture. Rotation is approximated by picking one of
## `directions` pre-rotated frames laid out horizontally in the texture.
## (MultiMesh was tried first but did not render in the WebGL build.)
## Each frame: begin(), add(...) per sprite, commit().

var tex: Texture2D
var directions := 1
var _frame_w := 0.0
var _frame_h := 0.0
var _pos := PackedVector2Array()
var _size := PackedFloat32Array()
var _col := PackedColorArray()
var _dir := PackedInt32Array()
var _asp := PackedFloat32Array()  # width/height stretch (1 = square); see add()
var _n := 0
var _cap := 0


func setup(texture: Texture2D, capacity: int, dirs: int = 1) -> void:
	tex = texture
	directions = dirs
	_frame_w = texture.get_width() / float(dirs)
	_frame_h = texture.get_height()
	_cap = capacity
	_pos.resize(capacity)
	_size.resize(capacity)
	_col.resize(capacity)
	_dir.resize(capacity)
	_asp.resize(capacity)


func begin() -> void:
	_n = 0


## size = on-screen width in pixels; rot = radians (frame 0 faces +x);
## aspect > 1 stretches the sprite wide and squashes it short (area kept),
## < 1 the other way (hit squash: axis-aligned, so it stays one rect).
func add(pos: Vector2, size: float, c: Color, rot: float = 0.0, aspect: float = 1.0) -> void:
	if _n >= _cap:
		return
	_pos[_n] = pos
	_size[_n] = size
	_col[_n] = c
	_asp[_n] = aspect
	if directions > 1:
		_dir[_n] = posmod(roundi(rot / TAU * directions), directions)
	else:
		_dir[_n] = 0
	_n += 1


func commit() -> void:
	queue_redraw()


func count() -> int:
	return _n


## CPU ms spent recording sprite draws since the view last read it (all
## batches together; added to the view's cost in the benchmark/readout).
static var draw_ms := 0.0


func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_sprites()
	draw_ms += (Time.get_ticks_usec() - t0) / 1000.0


func _draw_sprites() -> void:
	for i in _n:
		var s := _size[i]
		var a := _asp[i]
		if a == 1.0:
			draw_texture_rect_region(tex, Rect2(_pos[i].x - s * 0.5, _pos[i].y - s * 0.5, s, s),
				Rect2(_dir[i] * _frame_w, 0.0, _frame_w, _frame_h), _col[i])
			continue
		var w := s * a
		var h := s / a
		draw_texture_rect_region(tex, Rect2(_pos[i].x - w * 0.5, _pos[i].y - h * 0.5, w, h),
			Rect2(_dir[i] * _frame_w, 0.0, _frame_w, _frame_h), _col[i])
