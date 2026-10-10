extends RefCounted
## Paints the alien and prop sprites in code, so the game needs no image files.
## Every texture is 64x64 with the creature standing on the bottom edge.

const S := 64


static func build_all() -> Dictionary:
	return {
		"crawler": [_crawler(0), _crawler(1)],
		"spitter": [_spitter(0), _spitter(1)],
		"brute": [_brute(0), _brute(1)],
		"hive": [_hive(0), _hive(1)],
		"rock": [_rock()],
		"crystal": [_crystal()],
		"mech_front": [_mech(false)],
		"mech_back": [_mech(true)],
		"cache": [_cache(0), _cache(1)],
		"survivor": [_survivor(0), _survivor(1)],
		"item_fuel": [_canister()],
		"item_data": [_datacore(0), _datacore(1)],
		"item_supply": [_cache(0), _cache(1)],
		"beacon_off": [_beacon(false)],
		"beacon_on": [_beacon(true)],
		"dropship": [_dropship(0), _dropship(1)],
	}


# --- Creatures -------------------------------------------------------------

static func _crawler(frame: int) -> ImageTexture:
	var img := _blank()
	var body := Color(0.32, 0.68, 0.24)
	var leg := Color(0.18, 0.38, 0.14)
	var o := 4 if frame == 1 else -4
	for i in 3:
		var bx := 20 + i * 6
		_line(img, Vector2(bx, 46), Vector2(bx - 12 + (o if i % 2 == 0 else -o), 63), 3, leg)
		_line(img, Vector2(64 - bx, 46), Vector2(64 - bx + 12 + (-o if i % 2 == 0 else o), 63), 3, leg)
	_ellipse(img, 32, 46, 21, 11, body)
	_ellipse(img, 32, 41, 10, 7, body.lightened(0.15))
	# Mandibles
	_line(img, Vector2(27, 46), Vector2(23, 53 + (1 if frame else 0)), 2, Color(0.85, 0.82, 0.6))
	_line(img, Vector2(37, 46), Vector2(41, 53 + (1 if frame else 0)), 2, Color(0.85, 0.82, 0.6))
	_dot(img, 27, 40, 2.4, Color(1, 0.15, 0.1))
	_dot(img, 37, 40, 2.4, Color(1, 0.15, 0.1))
	_dot(img, 32, 37, 1.6, Color(1, 0.4, 0.2))
	_outline(img, Color(0.05, 0.1, 0.03))
	return ImageTexture.create_from_image(img)


static func _spitter(frame: int) -> ImageTexture:
	var img := _blank()
	var body := Color(0.55, 0.6, 0.22)
	var leg := Color(0.3, 0.32, 0.1)
	var o := 3 if frame == 1 else -3
	_line(img, Vector2(26, 48), Vector2(20 + o, 63), 4, leg)
	_line(img, Vector2(38, 48), Vector2(44 - o, 63), 4, leg)
	_ellipse(img, 32, 42, 12, 15, body)
	var sac_r := 14.0 if frame == 0 else 16.0
	_ellipse(img, 32, 20, sac_r, sac_r - 1.0, Color(0.75, 0.95, 0.25))
	_ellipse(img, 29, 16, 5, 4, Color(0.95, 1.0, 0.7))
	_ellipse(img, 32, 45, 5, 4, Color(0.12, 0.05, 0.05))
	_dot(img, 26, 36, 2.0, Color(1, 0.2, 0.1))
	_dot(img, 38, 36, 2.0, Color(1, 0.2, 0.1))
	_outline(img, Color(0.08, 0.1, 0.02))
	return ImageTexture.create_from_image(img)


static func _brute(frame: int) -> ImageTexture:
	var img := _blank()
	var body := Color(0.45, 0.22, 0.55)
	var dark := Color(0.25, 0.1, 0.3)
	var o := 2 if frame == 1 else -2
	_ellipse(img, 22, 56, 7, 8, dark)
	_ellipse(img, 42, 56, 7, 8, dark)
	_ellipse(img, 9, 38 + o, 7, 15, body.darkened(0.1))
	_ellipse(img, 55, 38 - o, 7, 15, body.darkened(0.1))
	_ellipse(img, 32, 35, 21, 20, body)
	_ellipse(img, 32, 26, 13, 9, body.lightened(0.15))
	for i in 3:
		_line(img, Vector2(6 + i * 3, 50 + o), Vector2(3 + i * 4, 58 + o), 2, Color(0.95, 0.9, 0.8))
		_line(img, Vector2(52 + i * 3, 50 - o), Vector2(55 + i * 4, 58 - o), 2, Color(0.95, 0.9, 0.8))
	_ellipse(img, 32, 40, 10, 5, Color(0.1, 0.02, 0.05))
	for i in 5:
		_dot(img, 25 + i * 3.5, 37, 1.1, Color(1, 1, 0.9))
	_dot(img, 26, 25, 2.2, Color(1, 0.9, 0.1))
	_dot(img, 38, 25, 2.2, Color(1, 0.9, 0.1))
	_dot(img, 32, 22, 2.0, Color(1, 0.9, 0.1))
	_outline(img, Color(0.08, 0.02, 0.1))
	return ImageTexture.create_from_image(img)


static func _hive(frame: int) -> ImageTexture:
	var img := _blank()
	var flesh := Color(0.42, 0.12, 0.32)
	_ellipse(img, 32, 50, 31, 14, flesh.darkened(0.25))
	_ellipse(img, 32, 32, 20, 22, flesh)
	_ellipse(img, 32, 16, 11, 11, flesh.lightened(0.1))
	var glow := Color(1.0, 0.55, 0.1) if frame == 0 else Color(1.0, 0.85, 0.3)
	var spots := [Vector2(24, 30), Vector2(40, 34), Vector2(32, 44), Vector2(18, 48), Vector2(46, 50), Vector2(32, 16)]
	for s in spots:
		_dot(img, s.x, s.y, 3.6 if frame == 0 else 4.2, glow.darkened(0.3))
		_dot(img, s.x, s.y, 2.0, glow)
	for i in 4:
		var x := 10 + i * 14
		_line(img, Vector2(x, 62), Vector2(32 + (x - 32) * 0.4, 26), 1, Color(0.7, 0.2, 0.45))
	_outline(img, Color(0.1, 0.02, 0.06))
	return ImageTexture.create_from_image(img)


# --- Your mech, parked ------------------------------------------------------

static func _mech(back: bool) -> ImageTexture:
	var img := _blank()
	var hull := Color(0.46, 0.5, 0.44)
	var dark := Color(0.26, 0.28, 0.26)
	# Legs and feet
	_box(img, 19, 40, 27, 59, dark)
	_box(img, 37, 40, 45, 59, dark)
	_box(img, 15, 58, 30, 63, hull.darkened(0.3))
	_box(img, 34, 58, 49, 63, hull.darkened(0.3))
	# Arms with autocannons
	_box(img, 4, 16, 14, 38, hull.darkened(0.1))
	_box(img, 50, 16, 60, 38, hull.darkened(0.1))
	_box(img, 6, 38, 11, 48, Color(0.15, 0.15, 0.16))
	_box(img, 53, 38, 58, 48, Color(0.15, 0.15, 0.16))
	# Torso
	_box(img, 14, 12, 50, 42, hull)
	_box(img, 20, 6, 44, 13, hull.lightened(0.1))
	if back:
		# Hatch, ladder rungs and exhaust vents: climb in here.
		_box(img, 23, 15, 41, 33, Color(0.3, 0.32, 0.3))
		_box(img, 25, 17, 39, 31, Color(0.38, 0.4, 0.37))
		_box(img, 30, 23, 34, 25, Color(0.85, 0.7, 0.2))
		for r in 4:
			_box(img, 27, 34 + r * 3, 37, 34 + r * 3, Color(0.75, 0.75, 0.7))
		_box(img, 16, 16, 20, 24, Color(0.12, 0.12, 0.12))
		_box(img, 44, 16, 48, 24, Color(0.12, 0.12, 0.12))
	else:
		# Cockpit glass and hazard stripes
		_box(img, 22, 16, 42, 25, Color(0.35, 0.75, 0.95))
		_box(img, 24, 17, 31, 19, Color(0.8, 0.95, 1.0))
		for i in 4:
			_box(img, 16 + i * 9, 36, 20 + i * 9, 40, Color(0.85, 0.7, 0.15))
	_outline(img, Color(0.06, 0.07, 0.06))
	return ImageTexture.create_from_image(img)


static func _cache(frame: int) -> ImageTexture:
	var img := _blank()
	var wood := Color(0.45, 0.33, 0.18)
	_box(img, 14, 38, 50, 63, wood)
	_box(img, 14, 38, 50, 42, wood.lightened(0.2))
	for i in 3:
		_box(img, 18 + i * 11, 46, 23 + i * 11, 58, Color(0.85, 0.7, 0.15))
	var glow := Color(0.4, 1.0, 0.6) if frame == 0 else Color(0.75, 1.0, 0.8)
	_dot(img, 32, 33, 4.0 if frame == 0 else 5.0, glow)
	_outline(img, Color(0.08, 0.06, 0.03))
	return ImageTexture.create_from_image(img)


static func _survivor(frame: int) -> ImageTexture:
	## A person waving for help.
	var img := _blank()
	var coat := Color(0.75, 0.35, 0.2)
	_box(img, 27, 44, 30, 63, Color(0.2, 0.22, 0.3))
	_box(img, 33, 44, 36, 63, Color(0.2, 0.22, 0.3))
	_box(img, 25, 26, 38, 46, coat)
	_dot(img, 31.5, 20, 5.5, Color(0.9, 0.75, 0.62))
	_box(img, 26, 13, 37, 16, Color(0.3, 0.2, 0.15))
	# One arm waving
	if frame == 0:
		_line(img, Vector2(37, 28), Vector2(46, 14), 3, coat)
	else:
		_line(img, Vector2(37, 28), Vector2(48, 20), 3, coat)
	_line(img, Vector2(26, 28), Vector2(22, 42), 3, coat)
	_outline(img, Color(0.08, 0.06, 0.05))
	return ImageTexture.create_from_image(img)


static func _canister() -> ImageTexture:
	var img := _blank()
	_box(img, 22, 30, 42, 63, Color(0.8, 0.2, 0.15))
	_box(img, 26, 25, 34, 30, Color(0.3, 0.3, 0.3))
	_box(img, 24, 42, 40, 48, Color(0.95, 0.85, 0.2))
	_outline(img, Color(0.1, 0.03, 0.02))
	return ImageTexture.create_from_image(img)


static func _datacore(frame: int) -> ImageTexture:
	var img := _blank()
	_box(img, 20, 40, 44, 63, Color(0.18, 0.2, 0.24))
	_box(img, 24, 44, 40, 48, Color(0.3, 0.9, 1.0) if frame == 0 else Color(0.6, 1.0, 1.0))
	_box(img, 24, 52, 30, 55, Color(1.0, 0.5, 0.2))
	_dot(img, 32, 34, 3.0 + frame, Color(0.4, 0.9, 1.0))
	_outline(img, Color(0.02, 0.05, 0.08))
	return ImageTexture.create_from_image(img)


static func _beacon(on: bool) -> ImageTexture:
	var img := _blank()
	var steel := Color(0.55, 0.58, 0.6)
	_line(img, Vector2(24, 63), Vector2(31, 6), 2, steel)
	_line(img, Vector2(40, 63), Vector2(33, 6), 2, steel)
	for i in 5:
		var y := 58 - i * 11
		_line(img, Vector2(25 + i * 1.3, y), Vector2(39 - i * 1.3, y - 8), 1, steel)
	_dot(img, 32, 6, 4.0, Color(0.3, 1.0, 0.5) if on else Color(0.9, 0.2, 0.15))
	_outline(img, Color(0.08, 0.08, 0.1))
	return ImageTexture.create_from_image(img)


static func _dropship(frame: int) -> ImageTexture:
	## The Gannet seen from below and in front.
	var img := _blank()
	var hull := Color(0.42, 0.47, 0.45)
	_box(img, 14, 26, 50, 42, hull)
	_box(img, 4, 22, 60, 26, hull.darkened(0.3))
	_box(img, 22, 42, 42, 46, hull.darkened(0.2))
	_box(img, 26, 30, 38, 35, Color(0.5, 0.85, 1.0))
	# Engines with flame
	for x in [8, 52]:
		_box(img, x - 4, 18, x + 4, 30, Color(0.25, 0.27, 0.28))
		var fl := 8 if frame == 0 else 12
		_box(img, x - 3, 30, x + 3, 30 + fl, Color(1.0, 0.65, 0.2))
		_box(img, x - 1, 30, x + 1, 30 + fl - 2, Color(1.0, 0.95, 0.7))
	_box(img, 30, 46, 34, 52, Color(0.2, 0.2, 0.2))
	_outline(img, Color(0.05, 0.06, 0.06))
	return ImageTexture.create_from_image(img)


static func _box(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var shade := 1.08 if y < y0 + 2 else (0.85 if x > x1 - 2 else 1.0)
			_put(img, x, y, Color(c.r * shade, c.g * shade, c.b * shade, 1.0))


# --- Props -----------------------------------------------------------------

static func _rock() -> ImageTexture:
	var img := _blank()
	_ellipse(img, 30, 54, 22, 10, Color(0.42, 0.38, 0.34))
	_ellipse(img, 42, 57, 12, 7, Color(0.36, 0.32, 0.3))
	_ellipse(img, 22, 50, 9, 6, Color(0.5, 0.46, 0.4))
	_outline(img, Color(0.1, 0.09, 0.08))
	return ImageTexture.create_from_image(img)


static func _crystal() -> ImageTexture:
	var img := _blank()
	var c := Color(0.3, 0.9, 0.95)
	_line(img, Vector2(32, 63), Vector2(30, 22), 5, c)
	_line(img, Vector2(26, 63), Vector2(16, 36), 4, c.darkened(0.2))
	_line(img, Vector2(38, 63), Vector2(48, 40), 4, c.darkened(0.1))
	_line(img, Vector2(31, 60), Vector2(30, 26), 1, Color(0.9, 1, 1))
	_outline(img, Color(0.02, 0.15, 0.2))
	return ImageTexture.create_from_image(img)


# --- Pixel helpers ---------------------------------------------------------

static func _blank() -> Image:
	return Image.create_empty(S, S, false, Image.FORMAT_RGBA8)


static func _put(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < S and y < S:
		img.set_pixel(x, y, c)


static func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in range(int(cy - ry), int(cy + ry) + 1):
		for x in range(int(cx - rx), int(cx + rx) + 1):
			var nx := (x - cx) / rx
			var ny := (y - cy) / ry
			if nx * nx + ny * ny <= 1.0:
				# Light from the upper left for a rounded look.
				var shade := 1.15 - 0.25 * (nx + ny) * 0.5 - 0.25 * (nx * nx + ny * ny)
				_put(img, x, y, Color(c.r * shade, c.g * shade, c.b * shade, 1.0))


static func _dot(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	for y in range(int(cy - r), int(cy + r) + 1):
		for x in range(int(cx - r), int(cx + r) + 1):
			if Vector2(x - cx, y - cy).length() <= r:
				_put(img, x, y, c)


static func _line(img: Image, a: Vector2, b: Vector2, thick: float, c: Color) -> void:
	var steps := int(a.distance_to(b)) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		_dot(img, p.x, p.y, thick * 0.5, c)


static func _outline(img: Image, c: Color) -> void:
	var src := img.duplicate() as Image
	for y in S:
		for x in S:
			if src.get_pixel(x, y).a > 0.5:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and ny >= 0 and nx < S and ny < S and src.get_pixel(nx, ny).a > 0.5:
					img.set_pixel(x, y, c)
					break
