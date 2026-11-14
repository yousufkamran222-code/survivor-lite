class_name BakedLayer
extends Control
## A HUD layer drawn into an offscreen texture only when it changes, then
## shown as a single quad every frame. The HUD's top panel interleaves text,
## shapes and arcs, so drawn live it cost ~60-90 draw calls a frame (each kind
## switch breaks the GPU batch), which is expensive on WebGL and cheap phones.
##
## Quality: the texture is rendered at the screen's real pixel density (the
## window's stretch scale), with font oversampling to match, so text and
## edges stay as sharp as drawing them directly.

var region := Rect2()  # the HUD area this layer covers (HUD coordinates)
var painter_fn: Callable  # func(ci: CanvasItem): draws in HUD coordinates
var _sv: SubViewport
var _painter: Control
var _scale := 0.0
var _size := Vector2.ZERO
var _dirty := true


func setup(r: Rect2, fn: Callable) -> void:
	region = r
	painter_fn = fn
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sv = SubViewport.new()
	_sv.transparent_bg = true
	_sv.disable_3d = true
	_sv.gui_disable_input = true
	_sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_sv.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_painter = Control.new()
	_painter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_painter.draw.connect(func() -> void: painter_fn.call(_painter))
	_sv.add_child(_painter)
	add_child(_sv)
	# The viewport's pixels are already alpha-premultiplied.
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	material = m


## Redraw the texture this frame.
func refresh() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	# Canvas-items stretch draws at the screen's density; viewport stretch
	# (Settings → Graphics: Fast) draws everything at the design size.
	var root := get_tree().root
	var s := 1.0 if root.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT else maxf(1.0, root.get_final_transform().get_scale().x)
	if s != _scale or region.size != _size:
		_scale = s
		_size = region.size
		_sv.size = Vector2i(maxi(1, ceili(region.size.x * s)), maxi(1, ceili(region.size.y * s)))
		_sv.oversampling_override = s
		_painter.scale = Vector2(s, s)
		_painter.position = -region.position * s
		_painter.size = region.end
		_dirty = true
	if _dirty and visible:
		_dirty = false
		_painter.queue_redraw()
		_sv.render_target_update_mode = SubViewport.UPDATE_ONCE
		queue_redraw()


func _draw() -> void:
	draw_texture_rect(_sv.get_texture(), Rect2(region.position, Vector2(_sv.size) / _scale), false)
