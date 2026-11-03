class_name IconAtlas
extends Node
## Bakes IconArt vector icons into one texture once at startup (a one-shot
## SubViewport render), so places drawn every frame (the HUD's owned-upgrade
## strip) use same-texture quads that batch into a single draw call instead of
## dozens of circles/polygons/arcs. Until the bake finishes
## and callers fall back to IconArt.draw (`baked` is false until then).

const CELL := 64
const COLS := 8

var texture: Texture2D
var baked := false
var _rects := {}  # "key|evolved" -> Rect2 in the texture
var _entries: Array = []  # [key, color, evolved]


static func entry_key(key: String, evolved: bool) -> String:
	return key + ("|e" if evolved else "")


## entries: Array of [icon key, Color, evolved bool].
func bake(entries: Array) -> void:
	_entries = entries
	var rows := ceili(float(entries.size()) / COLS)
	var vp := SubViewport.new()
	vp.size = Vector2i(COLS * CELL, maxi(rows, 1) * CELL)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	var painter := Control.new()
	painter.size = Vector2(vp.size)
	painter.draw.connect(func() -> void:
		for i in _entries.size():
			var e: Array = _entries[i]
			var c := Vector2((i % COLS) * CELL + CELL / 2.0, (i / COLS) * CELL + CELL / 2.0)
			IconArt.draw(painter, e[0], c, CELL, e[1], e[2]))
	vp.add_child(painter)
	add_child(vp)
	for i in entries.size():
		var e: Array = entries[i]
		_rects[entry_key(e[0], e[2])] = Rect2((i % COLS) * CELL, (i / COLS) * CELL, CELL, CELL)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img != null and not img.is_empty():
		texture = ImageTexture.create_from_image(img)
		baked = true
	vp.queue_free()


func has_icon(key: String, evolved: bool) -> bool:
	return baked and _rects.has(entry_key(key, evolved))


## Draws a baked icon centred at `c`, `px` wide.
func draw_icon(ci: CanvasItem, key: String, c: Vector2, px: float, evolved: bool = false) -> void:
	var r: Rect2 = _rects[entry_key(key, evolved)]
	ci.draw_texture_rect_region(texture, Rect2(c - Vector2(px, px) / 2.0, Vector2(px, px)), r)
