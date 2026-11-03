class_name DigitAtlas
extends Node
## Bakes the digits 0-9 (white with a dark outline) into one small texture
## once at startup, so damage numbers are same-texture quads that batch into
## one draw call instead of laying out text every frame. Tint per number with
## the modulate colour. Until baked, callers fall back to draw_string.

const FONT_SIZE := 28
const OUTLINE := 6

var texture: Texture2D
var baked := false
var cell := Vector2(24, 40)
var advance := 18.0  # distance between digit centres at scale 1


func bake() -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	advance = w + 1.0
	cell = Vector2(ceilf(w) + OUTLINE * 2 + 2, FONT_SIZE + OUTLINE * 2)
	var vp := SubViewport.new()
	vp.size = Vector2i(int(cell.x) * 10, int(cell.y))
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := Control.new()
	painter.size = Vector2(vp.size)
	painter.draw.connect(func() -> void:
		for d in 10:
			var base := Vector2(d * cell.x + (cell.x - w) / 2.0, OUTLINE + FONT_SIZE * 0.8)
			painter.draw_string_outline(font, base, str(d), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, OUTLINE, Color(0.05, 0.02, 0.1, 0.9))
			painter.draw_string(font, base, str(d), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color.WHITE))
	vp.add_child(painter)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img != null and not img.is_empty():
		texture = ImageTexture.create_from_image(img)
		baked = true
	vp.queue_free()


## Draws a non-negative integer centred at `c`; `height` in pixels.
func draw_number(ci: CanvasItem, value: int, c: Vector2, height: float, col: Color) -> void:
	var s := str(value)
	var k := height / cell.y
	var step := advance * k
	var x := c.x - step * (s.length() - 1) / 2.0
	var size := cell * k
	for ch in s:
		var d := ch.unicode_at(0) - 48
		ci.draw_texture_rect_region(texture, Rect2(Vector2(x, c.y) - size / 2.0, size), Rect2(d * cell.x, 0, cell.x, cell.y), col)
		x += step
