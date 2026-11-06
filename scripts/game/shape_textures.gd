class_name ShapeTextures
extends RefCounted
## Small white shape textures generated at startup (tinted per sprite by
## SpriteBatch colours). Anti-aliased by computing coverage per pixel.

## Fraction of the texture half-width covered by the outer (outline) edge.
const BLOB_OUTER := 0.94
const BLOB_BODY := 0.80


static func _aa(edge: float, d: float, px: float) -> float:
	return clampf((edge - d) / px + 0.5, 0.0, 1.0)


## Enemy body atlas: `dirs` frames side by side, each a shaded white disc
## with a dark outline and two dark eyes, frame k looking toward angle
## k * TAU / dirs. Tinted per germ by SpriteBatch.
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
				# Glossy chunky shading (baked, so it costs nothing per frame):
				# a dark outline ring, a body lit from the top-left, a soft
				# darker underside and a bright highlight. Same light for
				# every eye-direction frame (screen space, not rotated).
				var lit := clampf(0.5 - 0.5 * (p.x * 0.55 + p.y * 0.85) / body, 0.0, 1.0)
				var shade := lerpf(0.66, 1.0, lit)
				var hl := _aa(0.2 * body, p.distance_to(Vector2(-0.34, -0.42) * body), px * 3.0)
				shade = lerpf(shade, 1.0, hl * 0.9)
				var c := Color(0.22, 0.2, 0.26).lerp(Color(shade, shade, shade), _aa(body, d, px))
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


## Soft radial glow (alpha falls off smoothly to the edge): under elites,
## the boss and the player, and the menu's out-of-focus germs.
static func glow(size: int = 64) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var h := size / 2.0
	for y in size:
		for x in size:
			var d := Vector2((x + 0.5 - h) / h, (y + 0.5 - h) / h).length()
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
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


## Thin ring (kill pops), batched like the discs.
static func ring(size: int = 64) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var h := size / 2.0
	var px := 1.0 / h
	for y in size:
		for x in size:
			var d := Vector2((x + 0.5 - h) / h, (y + 0.5 - h) / h).length()
			img.set_pixel(x, y, Color(1, 1, 1, _aa(1.0, d, px) * (1.0 - _aa(0.78, d, px))))
	return ImageTexture.create_from_image(img)


## Goo splat for the floor: a soft blob with a few droplets (deterministic).
static func splat(size: int = 64) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var h := size / 2.0
	var px := 1.0 / h
	var drops := [[Vector2(0.62, -0.3), 0.16], [Vector2(-0.55, 0.45), 0.13], [Vector2(0.15, 0.7), 0.1], [Vector2(-0.4, -0.62), 0.11]]
	for y in size:
		for x in size:
			var p := Vector2((x + 0.5 - h) / h, (y + 0.5 - h) / h)
			var a := _aa(0.5 + 0.05 * sin(atan2(p.y, p.x) * 5.0), p.length(), px)
			for dr in drops:
				a = maxf(a, _aa(dr[1], p.distance_to(dr[0]), px))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## The player cell (tinted by the player colour): a soft outer glow, a bright
## membrane rim, a slightly darker cytoplasm and a few small organelles. The nucleus is drawn separately so it can lead turns.
const CELL_BODY := 0.78  # body radius as a fraction of the texture half-width


static func player_cell(size: int = 128) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var h := size / 2.0
	var px := 1.0 / h
	var body := CELL_BODY
	var organelles := [[Vector2(0.32, 0.36), 0.08], [Vector2(-0.38, 0.22), 0.06], [Vector2(0.12, -0.45), 0.05], [Vector2(-0.2, 0.5), 0.045]]
	for y in size:
		for x in size:
			var p := Vector2((x + 0.5 - h) / h, (y + 0.5 - h) / h)
			var d := p.length()
			var glow := clampf(1.0 - (d - body) / (1.0 - body), 0.0, 1.0)
			var a := maxf(_aa(body, d, px), glow * glow * 0.35)
			# Shade: bright membrane rim, a touch darker inside. Radial only,
			# because the body rotates with the movement direction.
			var rim := clampf((d - body * 0.8) / (body * 0.2), 0.0, 1.0)
			var v := 0.93 + 0.07 * rim
			for o in organelles:
				v = minf(v, lerpf(1.0, 0.8, _aa(o[1], p.distance_to(o[0]), px)))
			if d > body:
				v = 1.0
			img.set_pixel(x, y, Color(v, v, v, a))
	return ImageTexture.create_from_image(img)


## Cosmetic particle shapes (pop styles, weapon styles). All white, tinted
## per sprite like the disc.

## Five-point star.
static func star(size: int = 32) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var h := size / 2.0
	var px := 1.5 / h
	for y in size:
		for x in size:
			var p := Vector2((x + 0.5 - h) / h, (y + 0.5 - h) / h)
			var a := atan2(p.y, p.x) + PI / 2.0
			# Distance to the star's edge: radius swings between the inner
			# and outer points five times around.
			var k := absf(fposmod(a, TAU / 5.0) - TAU / 10.0) / (TAU / 10.0)
			var edge := lerpf(0.42, 0.98, k * k)
			img.set_pixel(x, y, Color(1, 1, 1, _aa(edge, p.length(), px)))
	return ImageTexture.create_from_image(img)


## Rounded square (confetti, pixels).
static func square(size: int = 32) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var h := size / 2.0
	for y in size:
		for x in size:
			var p := Vector2((x + 0.5 - h) / h, (y + 0.5 - h) / h)
			var d := maxf(absf(p.x), absf(p.y))
			img.set_pixel(x, y, Color(1, 1, 1, _aa(0.82, d, 1.5 / h)))
	return ImageTexture.create_from_image(img)


## Heart.
static func heart(size: int = 32) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var h := size / 2.0
	for y in size:
		for x in size:
			var p := Vector2((x + 0.5 - h) / h, (y + 0.5 - h) / h) * 1.25
			p.y = -p.y + 0.15
			# Classic implicit heart: (x² + y² - 1)³ - x²y³ <= 0.
			var q := p.x * p.x + p.y * p.y - 1.0
			var f := q * q * q - p.x * p.x * p.y * p.y * p.y
			img.set_pixel(x, y, Color(1, 1, 1, clampf(0.5 - f * 6.0, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## Coin: a disc with a darker inner ring (reads as gold when tinted).
static func coin(size: int = 32) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var h := size / 2.0
	var px := 1.0 / h
	for y in size:
		for x in size:
			var p := Vector2((x + 0.5 - h) / h, (y + 0.5 - h) / h)
			var d := p.length()
			var band := _aa(0.72, d, px) * (1.0 - _aa(0.58, d, px))
			var v := 1.0 - 0.3 * band
			if p.x < -0.1 and p.y < -0.1 and d < 0.5 and d > 0.25:
				v = 1.0  # small shine
			img.set_pixel(x, y, Color(v, v * 0.97, v * 0.9, _aa(1.0, d, px)))
	return ImageTexture.create_from_image(img)
