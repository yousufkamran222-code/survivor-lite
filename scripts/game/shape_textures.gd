class_name ShapeTextures
extends RefCounted
## Small white shape textures generated at startup (tinted per sprite by
## SpriteBatch colours). Anti-aliased by computing coverage per pixel.

## Fraction of the texture half-width covered by the outer (outline) edge.
const BLOB_OUTER := 0.94
const BLOB_BODY := 0.80


static func _aa(edge: float, d: float, px: float) -> float:
	return clampf((edge - d) / px + 0.5, 0.0, 1.0)


## Enemy body atlas: `dirs` frames side by side, each a white disc with a grey
## outline and two dark eyes, frame k looking toward angle k * TAU / dirs.
static func blob(size: int = 64, dirs: int = 16) -> ImageTexture:
	var img := Image.create(size * dirs, size, false, Image.FORMAT_RGBA8)
	var h := size / 2.0
	var px := 1.0 / h
	var body := BLOB_BODY
	var eye_r := 0.2 * body
	for k in dirs:
		var ang := TAU * k / dirs
		var eyes := [Vector2(0.35 * body, 0.32 * body).rotated(ang), Vector2(0.35 * body, -0.32 * body).rotated(ang)]
		for y in size:
			for x in size:
				var p := Vector2((x + 0.5 - h) / h, (y + 0.5 - h) / h)
				var d := p.length()
				var a := _aa(BLOB_OUTER, d, px)
				if a <= 0.0:
					img.set_pixel(k * size + x, y, Color(0, 0, 0, 0))
					continue
				var c := Color(0.55, 0.55, 0.55).lerp(Color.WHITE, _aa(body, d, px))
				for e: Vector2 in eyes:
					c = c.lerp(Color(0.08, 0.05, 0.12), _aa(eye_r, p.distance_to(e), px))
				c.a = a
				img.set_pixel(k * size + x, y, c)
	return ImageTexture.create_from_image(img)


## Ally cell: bright rim, faint body and a solid nucleus. Deliberately unlike
## the enemy blob (no eyes) so friend and foe never get confused.
static func ally_cell(size: int = 64) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var h := size / 2.0
	var px := 1.0 / h
	for y in size:
		for x in size:
			var d := Vector2((x + 0.5 - h) / h, (y + 0.5 - h) / h).length()
			var outer := _aa(0.94, d, px)
			if outer <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var rim := 1.0 - _aa(0.74, d, px)
			var nucleus := _aa(0.36, d, px)
			var a := maxf(maxf(rim, nucleus), 0.28) * outer
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## Plain anti-aliased disc (bullets, shots, particles).
static func disc(size: int = 32) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var h := size / 2.0
	for y in size:
		for x in size:
			var d := Vector2((x + 0.5 - h) / h, (y + 0.5 - h) / h).length()
			img.set_pixel(x, y, Color(1, 1, 1, _aa(1.0, d, 1.0 / h)))
	return ImageTexture.create_from_image(img)


## Diamond (XP gems).
static func diamond(size: int = 32) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var h := size / 2.0
	for y in size:
		for x in size:
			var p := Vector2((x + 0.5 - h) / h, (y + 0.5 - h) / h)
			var d := absf(p.x) / 0.8 + absf(p.y)
			img.set_pixel(x, y, Color(1, 1, 1, _aa(1.0, d, 1.5 / h)))
	return ImageTexture.create_from_image(img)
