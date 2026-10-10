extends RefCounted
## Procedural surface textures for the battle renderer: concrete, brick,
## corrugated metal, steel plates, alien flesh, rubble, earth, and ground
## types, plus sky clouds and soft effect sprites. All grey-ish "detail"
## maps: the renderer multiplies them by the zone's colours and light.
## Built once per run (about half a second) and cached.

const TS := 128               ## texture size; one tile = 1 world unit (walls) or 2 (ground)

static var _cache := {}


static func get_all() -> Dictionary:
	if _cache.is_empty():
		_build()
	return _cache


static func _build() -> void:
	var t0 := Time.get_ticks_msec()
	_cache["concrete"] = _tex(_concrete(1))
	_cache["brick"] = _tex(_brick(2))
	_cache["metal"] = _tex(_corrugated(3))
	_cache["plates"] = _tex(_plates(4))
	_cache["flesh"] = _tex(_flesh(5))
	_cache["rubble"] = _tex(_rubble(6))
	_cache["earth"] = _tex(_earth(7))
	for k in ["concrete", "brick", "metal", "plates", "flesh", "rubble", "earth"]:
		_cache[k + "_base"] = _tex(_grime((_cache[k] as ImageTexture).get_image()))
	_cache["g_gravel"] = _tex(_gravel(11))
	_cache["g_asphalt"] = _tex(_asphalt(12))
	_cache["g_snow"] = _tex(_snow(13))
	_cache["g_grass"] = _tex(_grass(14))
	_cache["g_dust"] = _tex(_dust(15))
	_cache["g_slabs"] = _tex(_slabs(16))
	_cache["g_creep"] = _tex(_creep(17))
	_cache["clouds"] = _tex(_clouds(21))
	_cache["glow"] = _tex(_glow())
	_cache["puff"] = _tex(_puff(22))
	_cache["fire"] = _tex(_fire(23))
	_cache["glass"] = _tex(_glass(24))
	print("surfaces built in %d ms" % (Time.get_ticks_msec() - t0))


static func _tex(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# =============================================================================
# Helpers
# =============================================================================

static func _noise(seed_v: int, freq: float, octaves := 4, kind := FastNoiseLite.TYPE_SIMPLEX_SMOOTH, w := TS, h := TS) -> PackedFloat32Array:
	## Seamless (tileable) noise in 0..1, row-major.
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.noise_type = kind
	n.frequency = freq
	n.fractal_octaves = octaves
	var img := n.get_seamless_image(w, h, false, false, 0.15)
	var out := PackedFloat32Array()
	out.resize(w * h)
	var data := img.get_data()
	var step := data.size() / (w * h)
	for i in w * h:
		out[i] = data[i * step] / 255.0
	return out


static func _cells(seed_v: int, freq: float, ret := FastNoiseLite.RETURN_DISTANCE2_SUB, w := TS, h := TS) -> PackedFloat32Array:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	n.cellular_return_type = ret
	var img := n.get_seamless_image(w, h, false, false, 0.15)
	var out := PackedFloat32Array()
	out.resize(w * h)
	var data := img.get_data()
	var step := data.size() / (w * h)
	for i in w * h:
		out[i] = data[i * step] / 255.0
	return out


static func _img_from(lum: PackedFloat32Array, tint_r: PackedFloat32Array, tint_g: PackedFloat32Array, tint_b: PackedFloat32Array, w := TS, h := TS, alpha := PackedFloat32Array()) -> Image:
	var data := PackedByteArray()
	data.resize(w * h * 4)
	for i in w * h:
		var l := lum[i]
		data[i * 4] = int(clampf(l * (tint_r[i] if not tint_r.is_empty() else 1.0), 0.0, 1.0) * 255.0)
		data[i * 4 + 1] = int(clampf(l * (tint_g[i] if not tint_g.is_empty() else 1.0), 0.0, 1.0) * 255.0)
		data[i * 4 + 2] = int(clampf(l * (tint_b[i] if not tint_b.is_empty() else 1.0), 0.0, 1.0) * 255.0)
		data[i * 4 + 3] = 255 if alpha.is_empty() else int(clampf(alpha[i], 0.0, 1.0) * 255.0)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)


static func _crack_lines(lum: PackedFloat32Array, seed_v: int, count: int, dark: float, w := TS, h := TS) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for c in count:
		var p := Vector2(rng.randf() * w, rng.randf() * h)
		var dir := Vector2.from_angle(rng.randf() * TAU)
		for s in rng.randi_range(20, 60):
			dir = dir.rotated(rng.randf_range(-0.5, 0.5))
			p += dir
			var x := posmod(int(p.x), w)
			var y := posmod(int(p.y), h)
			lum[y * w + x] *= dark


# =============================================================================
# Walls
# =============================================================================

static func _concrete(s: int) -> Image:
	var big := _noise(s, 0.02, 3)
	var fine := _noise(s + 1, 0.12, 2)
	var streak := _noise(s + 2, 0.06, 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	var lum := PackedFloat32Array()
	lum.resize(TS * TS)
	var tr := PackedFloat32Array()
	var tg := PackedFloat32Array()
	var tb := PackedFloat32Array()
	tr.resize(TS * TS)
	tg.resize(TS * TS)
	tb.resize(TS * TS)
	for y in TS:
		for x in TS:
			var i := y * TS + x
			var v := 0.78 + (big[i] - 0.5) * 0.25 + (fine[i] - 0.5) * 0.12
			# Rain streaks running down from the slab joints.
			var st: float = streak[(y / 6) * TS + x]
			var drip := clampf((st - 0.55) * 3.0, 0.0, 1.0) * (1.0 - float(y) / TS * 0.6)
			v -= drip * 0.18
			# Slab joint every metre (top of the tile) and a formwork line.
			if y < 2:
				v *= 0.55
			elif y == 64:
				v *= 0.88
			# Bolt holes from the formwork.
			if (x % 32 == 16) and (y % 64 == 30):
				v *= 0.5
			lum[i] = v
			tr[i] = 1.0
			tg[i] = 0.98
			tb[i] = 0.95 - drip * 0.05
	_crack_lines(lum, s + 3, 3, 0.6)
	return _img_from(lum, tr, tg, tb)


static func _brick(s: int) -> Image:
	var fine := _noise(s, 0.15, 2)
	var big := _noise(s + 1, 0.03, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var brick_v := PackedFloat32Array()
	for i in 64:
		brick_v.append(rng.randf_range(0.75, 1.05))
	var lum := PackedFloat32Array()
	lum.resize(TS * TS)
	var tr := PackedFloat32Array()
	var tg := PackedFloat32Array()
	var tb := PackedFloat32Array()
	tr.resize(TS * TS)
	tg.resize(TS * TS)
	tb.resize(TS * TS)
	var bh := 16     # 8 courses per metre
	var bw := 32
	for y in TS:
		var row := y / bh
		var off := (bw / 2) if row % 2 == 1 else 0
		for x in TS:
			var i := y * TS + x
			var bx := posmod(x + off, TS)
			var in_mortar := (y % bh) < 2 or (bx % bw) < 2
			var bid := row * 4 + bx / bw
			var v: float
			if in_mortar:
				v = 0.86 + (fine[i] - 0.5) * 0.1
				tr[i] = 0.95
				tg[i] = 0.95
				tb[i] = 0.92
			else:
				v = 0.72 * brick_v[bid % 64] + (fine[i] - 0.5) * 0.18
				tr[i] = 1.0
				tg[i] = 0.84
				tb[i] = 0.76
			v *= 0.85 + big[i] * 0.3
			lum[i] = v
	return _img_from(lum, tr, tg, tb)


static func _corrugated(s: int) -> Image:
	var rust := _noise(s, 0.035, 4)
	var fine := _noise(s + 1, 0.2, 2)
	var lum := PackedFloat32Array()
	lum.resize(TS * TS)
	var tr := PackedFloat32Array()
	var tg := PackedFloat32Array()
	var tb := PackedFloat32Array()
	tr.resize(TS * TS)
	tg.resize(TS * TS)
	tb.resize(TS * TS)
	for y in TS:
		for x in TS:
			var i := y * TS + x
			var rib := 0.5 + 0.5 * sin(float(x) / TS * TAU * 8.0)
			var v := 0.62 + rib * 0.3 + (fine[i] - 0.5) * 0.08
			# Rust bleeding down from the top and from the ribs.
			var r := clampf((rust[i] - 0.45) * 2.5 + (1.0 - float(y) / TS) * 0.25 * rust[(y / 4) * TS + x], 0.0, 1.0)
			v *= 1.0 - r * 0.25
			lum[i] = v
			tr[i] = 1.0 + r * 0.1
			tg[i] = 1.0 - r * 0.35
			tb[i] = 1.0 - r * 0.6
			if y < 3:
				lum[i] *= 0.6
	return _img_from(lum, tr, tg, tb)


static func _plates(s: int) -> Image:
	var wear := _noise(s, 0.05, 4)
	var fine := _noise(s + 1, 0.25, 2)
	var lum := PackedFloat32Array()
	lum.resize(TS * TS)
	for y in TS:
		for x in TS:
			var i := y * TS + x
			var v := 0.78 + (wear[i] - 0.5) * 0.22 + (fine[i] - 0.5) * 0.08
			var px := x % 64
			var py := y % 64
			if px < 2 or py < 2:
				v *= 0.5
			elif px < 4 or py < 4:
				v *= 1.12
			# Rivets near the seams.
			for c in [Vector2(8, 8), Vector2(56, 8), Vector2(8, 56), Vector2(56, 56)]:
				var d := Vector2(px, py).distance_to(c)
				if d < 2.5:
					v = 0.95 - d * 0.12
			lum[i] = v
	return _img_from(lum, PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array())


static func _flesh(s: int) -> Image:
	var veins := _cells(s, 0.05, FastNoiseLite.RETURN_DISTANCE2_SUB)
	var blob := _noise(s + 1, 0.04, 4)
	var fine := _noise(s + 2, 0.18, 2)
	var lum := PackedFloat32Array()
	lum.resize(TS * TS)
	var tr := PackedFloat32Array()
	var tg := PackedFloat32Array()
	var tb := PackedFloat32Array()
	tr.resize(TS * TS)
	tg.resize(TS * TS)
	tb.resize(TS * TS)
	for i in TS * TS:
		var vein := clampf(1.0 - veins[i] * 6.0, 0.0, 1.0)
		var v := 0.7 + (blob[i] - 0.5) * 0.4 + (fine[i] - 0.5) * 0.12
		v = lerpf(v, 0.45, vein * 0.8)
		lum[i] = v
		tr[i] = 1.0 - vein * 0.2
		tg[i] = 1.0 - vein * 0.4 + blob[i] * 0.15
		tb[i] = 1.0 + vein * 0.15
	return _img_from(lum, tr, tg, tb)


static func _rubble(s: int) -> Image:
	var c := _cells(s, 0.06, FastNoiseLite.RETURN_CELL_VALUE)
	var e := _cells(s, 0.06, FastNoiseLite.RETURN_DISTANCE2_SUB)
	var fine := _noise(s + 1, 0.2, 2)
	var lum := PackedFloat32Array()
	lum.resize(TS * TS)
	for i in TS * TS:
		var v := 0.6 + c[i] * 0.35 + (fine[i] - 0.5) * 0.15
		if e[i] < 0.06:
			v *= 0.5
		lum[i] = v
	return _img_from(lum, PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array())


static func _earth(s: int) -> Image:
	var big := _noise(s, 0.03, 4)
	var fine := _noise(s + 1, 0.18, 3)
	var lum := PackedFloat32Array()
	lum.resize(TS * TS)
	for y in TS:
		for x in TS:
			var i := y * TS + x
			# Layered strata, wavy.
			var strata := 0.5 + 0.5 * sin((float(y) + big[i] * 30.0) / TS * TAU * 5.0)
			lum[i] = 0.62 + strata * 0.16 + (fine[i] - 0.5) * 0.2
	return _img_from(lum, PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array())


static func _grime(src: Image) -> Image:
	## The bottom half-metre of a wall: dirt, damp and soot creeping up.
	## (128 x 64 px = 1 x 0.5 world units; row 0 is the top.)
	var n := _noise(91, 0.08, 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, TS, TS)
	var out := Image.create_empty(TS, TS / 2, false, Image.FORMAT_RGBA8)
	for y in TS / 2:
		var k := float(y) / (TS / 2 - 1)    # 0 top .. 1 floor
		for x in TS:
			var c := src.get_pixel(x, (TS / 2 + y) % TS)
			var dirt := clampf(k * k * 1.1 + (n[y * TS + x] - 0.5) * 0.6 * k, 0.0, 0.85)
			c = c.lerp(Color(c.r * 0.45, c.g * 0.4, c.b * 0.35), dirt)
			out.set_pixel(x, y, c)
	return out


# =============================================================================
# Ground (one tile = 2 x 2 world units)
# =============================================================================

static func _gravel(s: int) -> Image:
	var c := _cells(s, 0.12, FastNoiseLite.RETURN_CELL_VALUE)
	var e := _cells(s, 0.12, FastNoiseLite.RETURN_DISTANCE2_SUB)
	var big := _noise(s + 1, 0.025, 4)
	var lum := PackedFloat32Array()
	lum.resize(TS * TS)
	for i in TS * TS:
		var v := 0.65 + c[i] * 0.2 + (big[i] - 0.5) * 0.3
		if e[i] < 0.05:
			v *= 0.7
		lum[i] = v
	return _img_from(lum, PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array())


static func _asphalt(s: int) -> Image:
	var fine := _noise(s, 0.35, 2)
	var patch := _noise(s + 1, 0.02, 4)
	var puddle := _noise(s + 2, 0.015, 3)
	var lum := PackedFloat32Array()
	lum.resize(TS * TS)
	var tb := PackedFloat32Array()
	var tg := PackedFloat32Array()
	var tr := PackedFloat32Array()
	tr.resize(TS * TS)
	tg.resize(TS * TS)
	tb.resize(TS * TS)
	for i in TS * TS:
		var v := 0.62 + (fine[i] - 0.5) * 0.25 + (patch[i] - 0.5) * 0.25
		var wet := clampf((puddle[i] - 0.62) * 8.0, 0.0, 1.0)
		v = lerpf(v, 0.95, wet * 0.6)       # puddles catch the sky
		lum[i] = v
		tr[i] = 1.0 - wet * 0.15
		tg[i] = 1.0 - wet * 0.05
		tb[i] = 1.0 + wet * 0.1
	_crack_lines(lum, s + 3, 6, 0.55)
	return _img_from(lum, tr, tg, tb)


static func _snow(s: int) -> Image:
	var big := _noise(s, 0.025, 4)
	var fine := _noise(s + 1, 0.3, 2)
	var lum := PackedFloat32Array()
	lum.resize(TS * TS)
	var tb := PackedFloat32Array()
	var tg := PackedFloat32Array()
	var tr := PackedFloat32Array()
	tr.resize(TS * TS)
	tg.resize(TS * TS)
	tb.resize(TS * TS)
	for i in TS * TS:
		var v := 0.86 + (big[i] - 0.5) * 0.16 + (fine[i] - 0.5) * 0.05
		lum[i] = v
		tr[i] = 0.97
		tg[i] = 0.99
		tb[i] = 1.03
	return _img_from(lum, tr, tg, tb)


static func _grass(s: int) -> Image:
	var blades := _noise(s, 0.45, 2)
	var mud := _noise(s + 1, 0.03, 4)
	var lum := PackedFloat32Array()
	lum.resize(TS * TS)
	var tr := PackedFloat32Array()
	var tg := PackedFloat32Array()
	var tb := PackedFloat32Array()
	tr.resize(TS * TS)
	tg.resize(TS * TS)
	tb.resize(TS * TS)
	for i in TS * TS:
		var m := clampf((mud[i] - 0.55) * 4.0, 0.0, 1.0)
		var v := 0.6 + (blades[i] - 0.5) * 0.45
		v = lerpf(v, 0.55 + (blades[i] - 0.5) * 0.1, m)
		lum[i] = v
		tr[i] = 0.9 + m * 0.25
		tg[i] = 1.08 - m * 0.2
		tb[i] = 0.85
	return _img_from(lum, tr, tg, tb)


static func _dust(s: int) -> Image:
	var big := _noise(s, 0.02, 4)
	var fine := _noise(s + 1, 0.25, 2)
	var c := _cells(s + 2, 0.08, FastNoiseLite.RETURN_CELL_VALUE)
	var lum := PackedFloat32Array()
	lum.resize(TS * TS)
	for y in TS:
		for x in TS:
			var i := y * TS + x
			var ripple := 0.5 + 0.5 * sin((float(x) * 0.7 + float(y) + big[i] * 40.0) / TS * TAU * 6.0)
			var v := 0.75 + (big[i] - 0.5) * 0.22 + ripple * 0.06 + (fine[i] - 0.5) * 0.1
			if c[i] > 0.93:
				v *= 0.8     # loose stones
			lum[i] = v
	return _img_from(lum, PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array())


static func _slabs(s: int) -> Image:
	var stain := _noise(s, 0.03, 4)
	var fine := _noise(s + 1, 0.3, 2)
	var lum := PackedFloat32Array()
	lum.resize(TS * TS)
	for y in TS:
		for x in TS:
			var i := y * TS + x
			var v := 0.75 + (stain[i] - 0.5) * 0.3 + (fine[i] - 0.5) * 0.1
			if x % 64 < 2 or y % 64 < 2:
				v *= 0.55
			lum[i] = v
	_crack_lines(lum, s + 2, 4, 0.6)
	return _img_from(lum, PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array())


static func _creep(s: int) -> Image:
	var veins := _cells(s, 0.04, FastNoiseLite.RETURN_DISTANCE2_SUB)
	var big := _noise(s + 1, 0.03, 4)
	var fine := _noise(s + 2, 0.25, 2)
	var lum := PackedFloat32Array()
	lum.resize(TS * TS)
	var tr := PackedFloat32Array()
	var tg := PackedFloat32Array()
	var tb := PackedFloat32Array()
	tr.resize(TS * TS)
	tg.resize(TS * TS)
	tb.resize(TS * TS)
	for i in TS * TS:
		var vein := clampf(1.0 - veins[i] * 7.0, 0.0, 1.0) * clampf((big[i] - 0.3) * 3.0, 0.0, 1.0)
		var v := 0.62 + (big[i] - 0.5) * 0.25 + (fine[i] - 0.5) * 0.12
		v = lerpf(v, 0.85, vein * 0.7)
		lum[i] = v
		tr[i] = 1.0 + vein * 0.2
		tg[i] = 1.0 - vein * 0.35
		tb[i] = 1.0 + vein * 0.3
	return _img_from(lum, tr, tg, tb)


# =============================================================================
# Sky and effects
# =============================================================================

static func _clouds(s: int) -> Image:
	## A 512 x 128 seamless band of cloud for the sky panorama.
	var w := 512
	var h := 128
	var n := _noise(s, 0.012, 5, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, w, h)
	var lum := PackedFloat32Array()
	var a := PackedFloat32Array()
	lum.resize(w * h)
	a.resize(w * h)
	for y in h:
		var fade := sin(float(y) / h * PI)
		for x in w:
			var i := y * w + x
			var c := clampf((n[i] - 0.48) * 3.0, 0.0, 1.0) * fade
			a[i] = c * 0.9
			lum[i] = 0.75 + n[i] * 0.3 - (float(y) / h) * 0.2
	return _img_from(lum, PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(), w, h, a)


static func _glow() -> Image:
	var s := 64
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(s, s) * 0.5) / (s * 0.5)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 2.2)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return img


static func _puff(s: int) -> Image:
	var n := _noise(s, 0.08, 4, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 64, 64)
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(32, 32)) / 32.0
			var a := clampf((1.0 - d) * 1.6 - (1.0 - n[y * 64 + x]) * 0.9, 0.0, 1.0)
			var l := 0.7 + n[y * 64 + x] * 0.3
			img.set_pixel(x, y, Color(l, l, l, a))
	return img


static func _fire(s: int) -> Image:
	var n := _noise(s, 0.1, 4, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 64, 64)
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(32, 32)) / 32.0
			var heat := clampf((1.0 - d) * 1.5 - (1.0 - n[y * 64 + x]) * 0.6, 0.0, 1.0)
			var c := Color(1.0, 0.25, 0.02).lerp(Color(1.0, 0.65, 0.15), clampf(heat * 1.6, 0.0, 1.0)).lerp(Color(1.0, 0.97, 0.85), clampf((heat - 0.6) * 2.5, 0.0, 1.0))
			c.a = clampf(heat * 1.8, 0.0, 1.0)
			img.set_pixel(x, y, c)
	return img


static func _glass(s: int) -> Image:
	## Grime, dust and smudges on the cockpit canopy (256 x 144, stretched).
	var w := 256
	var h := 144
	var n := _noise(s, 0.03, 5, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, w, h)
	var specks := _noise(s + 1, 0.5, 1, FastNoiseLite.TYPE_VALUE, w, h)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var i := y * w + x
			var edge := maxf(absf(float(x) / w - 0.5), absf(float(y) / h - 0.5)) * 2.0
			var a := clampf((n[i] - 0.55) * 0.5, 0.0, 0.18) + pow(edge, 4.0) * 0.12
			if specks[i] > 0.93:
				a += 0.25
			img.set_pixel(x, y, Color(0.8, 0.82, 0.78, a))
	return img
