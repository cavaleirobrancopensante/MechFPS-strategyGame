extends RefCounted
## A tiny 3D model renderer for sprites. Creatures, survivors, the mech and
## crates are built from rounded shapes (ellipsoids) and boxes, lit like
## real objects, and rendered from 8 directions with walk frames. The battle
## shows whichever view matches the angle you see them from, so they turn,
## show their sides and backs, and feel solid instead of cardboard.
##
## Model space: x right, y up (ground at 0), z toward the viewer (front).

const DIRS := 8
const LIGHT := Vector3(-0.45, 0.7, 0.55)

## Built once per app run and shared by every battle.
static var _cache := {}


static func build_all() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var out := {}
	out["crawler"] = _view_set(1.0, 64, 4, func(ph): return _crawler(ph))
	out["spitter"] = _view_set(1.25, 64, 2, func(ph): return _spitter(ph))
	out["brute"] = _view_set(1.95, 96, 4, func(ph): return _brute(ph))
	out["hive"] = _view_set(2.2, 96, 2, func(ph): return _hive(ph, 1.0, Color(0.48, 0.14, 0.36)))
	out["mother"] = _view_set(3.9, 128, 2, func(ph): return _hive(ph, 1.75, Color(0.55, 0.12, 0.2)))
	out["survivor"] = _view_set(0.9, 48, 2, func(ph): return _survivor(ph))
	out["mech"] = _view_set(2.3, 96, 1, func(ph): return _mech())
	out["cache"] = _view_set(0.65, 48, 2, func(ph): return _crate(ph))
	out["item_supply"] = out["cache"]
	out["item_fuel"] = _view_set(0.65, 48, 1, func(ph): return _canister())
	out["item_data"] = _view_set(0.65, 48, 2, func(ph): return _datacore(ph))
	out["beacon_off"] = _view_set(2.6, 96, 1, func(ph): return _beacon(false))
	out["beacon_on"] = _view_set(2.6, 96, 1, func(ph): return _beacon(true))
	_cache = out
	return out


static func _view_set(box: float, size: int, frames: int, model: Callable) -> Dictionary:
	## {"L": world size of the square image, "dirs": [dir][frame] textures}
	var dirs: Array = []
	var parts_per_frame: Array = []
	for f in frames:
		parts_per_frame.append(model.call(float(f) / frames))
	for d in DIRS:
		var fr: Array = []
		for f in frames:
			fr.append(ImageTexture.create_from_image(_render(parts_per_frame[f], TAU * d / DIRS, size, box)))
		dirs.append(fr)
	return {"L": box, "dirs": dirs}


# =============================================================================
# Primitives
# =============================================================================

static func _ell(c: Vector3, r: Vector3, col: Color, rot := Vector3.ZERO, gloss := 0.15, emit := false) -> Dictionary:
	return {"t": 0, "c": c, "b": Basis.from_euler(rot) * Basis.from_scale(r), "col": col, "gloss": gloss, "emit": emit}


static func _ball(c: Vector3, r: float, col: Color, emit := false) -> Dictionary:
	return _ell(c, Vector3(r, r, r), col, Vector3.ZERO, 0.3, emit)


static func _seg(a: Vector3, b: Vector3, thick: float, col: Color, gloss := 0.1) -> Dictionary:
	## A limb: an ellipsoid stretched between two points.
	var axis := b - a
	var length := axis.length()
	var y := axis / maxf(length, 0.0001)
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	var basis := Basis(x * thick, y * (length * 0.5 + thick * 0.5), z * thick)
	return {"t": 0, "c": (a + b) * 0.5, "b": basis, "col": col, "gloss": gloss, "emit": false}


static func _box(c: Vector3, half: Vector3, col: Color, yaw := 0.0, gloss := 0.1, emit := false) -> Dictionary:
	return {"t": 1, "c": c, "b": Basis(Vector3.UP, yaw) * Basis.from_scale(half), "col": col, "gloss": gloss, "emit": emit}


# =============================================================================
# Rasteriser
# =============================================================================

static func _render(parts: Array, yaw: float, size: int, box: float) -> Image:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var depth := PackedFloat32Array()
	depth.resize(size * size)
	depth.fill(1e9)
	var rot := Basis(Vector3.UP, yaw)
	var light := LIGHT.normalized()
	var half_v := (light + Vector3(0, 0, 1)).normalized()
	var px := float(size) / box
	for p: Dictionary in parts:
		var c: Vector3 = rot * (p["c"] as Vector3)
		var b: Basis = rot * (p["b"] as Basis)
		var a := b.inverse()
		# Screen-space bounds of the shape.
		var ex: float
		var ey: float
		if p["t"] == 0:
			ex = sqrt(b.x.x * b.x.x + b.y.x * b.y.x + b.z.x * b.z.x)
			ey = sqrt(b.x.y * b.x.y + b.y.y * b.y.y + b.z.y * b.z.y)
		else:
			ex = absf(b.x.x) + absf(b.y.x) + absf(b.z.x)
			ey = absf(b.x.y) + absf(b.y.y) + absf(b.z.y)
		var i0 := maxi(0, int(floor((c.x - ex + box * 0.5) * px)))
		var i1 := mini(size - 1, int(ceil((c.x + ex + box * 0.5) * px)))
		var j0 := maxi(0, int(floor((box - (c.y + ey)) * px)))
		var j1 := mini(size - 1, int(ceil((box - (c.y - ey)) * px)))
		var qd := -a.z               # ray direction (0,0,-1) in unit space
		var qa := qd.dot(qd)
		var col: Color = p["col"]
		var gloss: float = p["gloss"]
		var emit: bool = p["emit"]
		for j in range(j0, j1 + 1):
			var wy := box - (j + 0.5) / px
			for i in range(i0, i1 + 1):
				var wx := (i + 0.5) / px - box * 0.5
				var q0 := a * (Vector3(wx, wy, 10.0) - c)
				var t := 0.0
				var n_local: Vector3
				if p["t"] == 0:
					var bb := 2.0 * q0.dot(qd)
					var cc := q0.dot(q0) - 1.0
					var disc := bb * bb - 4.0 * qa * cc
					if disc < 0.0:
						continue
					t = (-bb - sqrt(disc)) / (2.0 * qa)
					n_local = q0 + qd * t
				else:
					var tmin := -1e9
					var tmax := 1e9
					var axis := 0
					var sgn := 1.0
					var miss := false
					for k in 3:
						var o: float = q0[k]
						var d: float = qd[k]
						if absf(d) < 1e-6:
							if absf(o) > 1.0:
								miss = true
								break
							continue
						var t1 := (-1.0 - o) / d
						var t2 := (1.0 - o) / d
						var tn := minf(t1, t2)
						if tn > tmin:
							tmin = tn
							axis = k
							sgn = -signf(d)
						tmax = minf(tmax, maxf(t1, t2))
					if miss or tmin > tmax:
						continue
					t = tmin
					n_local = Vector3.ZERO
					n_local[axis] = sgn
				var di := j * size + i
				if t >= depth[di]:
					continue
				depth[di] = t
				if emit:
					img.set_pixel(i, j, col)
					continue
				var n := (a.transposed() * n_local).normalized()
				var lam := maxf(0.0, n.dot(light))
				var spec := pow(maxf(0.0, n.dot(half_v)), 24.0) * gloss
				var rim := pow(1.0 - maxf(0.0, n.z), 3.0) * 0.12
				var k2 := 0.36 + 0.72 * lam
				img.set_pixel(i, j, Color(minf(1.0, col.r * k2 + spec + rim * 0.4), minf(1.0, col.g * k2 + spec + rim * 0.5), minf(1.0, col.b * k2 + spec + rim * 0.7), 1.0))
	_outline(img, size)
	return img


static func _outline(img: Image, size: int) -> void:
	var src := img.duplicate() as Image
	var oc := Color(0.04, 0.04, 0.05, 1.0)
	for y in size:
		for x in size:
			if src.get_pixel(x, y).a > 0.5:
				continue
			if (x > 0 and src.get_pixel(x - 1, y).a > 0.5) or (x < size - 1 and src.get_pixel(x + 1, y).a > 0.5) \
					or (y > 0 and src.get_pixel(x, y - 1).a > 0.5) or (y < size - 1 and src.get_pixel(x, y + 1).a > 0.5):
				img.set_pixel(x, y, oc)


# =============================================================================
# Models
# =============================================================================

static func _crawler(ph: float) -> Array:
	var green := Color(0.33, 0.66, 0.24)
	var dark := Color(0.16, 0.3, 0.12)
	var bone := Color(0.88, 0.85, 0.65)
	var sw := sin(ph * TAU)
	var parts: Array = [
		_ell(Vector3(0, 0.34, -0.03), Vector3(0.3, 0.15, 0.38), green, Vector3.ZERO, 0.35),
		_ell(Vector3(0, 0.43, -0.1), Vector3(0.21, 0.08, 0.27), green.lightened(0.15), Vector3.ZERO, 0.4),
		_ell(Vector3(0, 0.35, 0.36), Vector3(0.15, 0.12, 0.13), green.lightened(0.1), Vector3.ZERO, 0.35),
		_ball(Vector3(-0.06, 0.4, 0.47), 0.035, Color(1, 0.15, 0.1), true),
		_ball(Vector3(0.06, 0.4, 0.47), 0.035, Color(1, 0.15, 0.1), true),
		_ball(Vector3(0, 0.44, 0.46), 0.028, Color(1, 0.45, 0.2), true),
		_seg(Vector3(-0.07, 0.3, 0.45), Vector3(-0.03, 0.2, 0.6), 0.022, bone, 0.4),
		_seg(Vector3(0.07, 0.3, 0.45), Vector3(0.03, 0.2, 0.6), 0.022, bone, 0.4),
	]
	for side in [-1.0, 1.0]:
		for k in 3:
			var z := -0.25 + k * 0.25
			var s: float = sw if (k + (1 if side > 0 else 0)) % 2 == 0 else -sw
			var hip := Vector3(side * 0.22, 0.33, z)
			var knee := Vector3(side * 0.46, 0.46, z + s * 0.08)
			var foot := Vector3(side * 0.56, 0.02 + maxf(0.0, s) * 0.07, z + s * 0.16)
			parts.append(_seg(hip, knee, 0.035, dark))
			parts.append(_seg(knee, foot, 0.03, dark))
	return parts


static func _spitter(ph: float) -> Array:
	var olive := Color(0.55, 0.6, 0.22)
	var leg := Color(0.3, 0.32, 0.12)
	var sw := sin(ph * TAU)
	var pulse := 1.0 + 0.07 * sin(ph * TAU)
	var parts: Array = [
		_ell(Vector3(0, 0.62, 0), Vector3(0.2, 0.28, 0.18), olive, Vector3.ZERO, 0.25),
		_ell(Vector3(0, 1.0, -0.06), Vector3(0.26, 0.23, 0.24) * pulse, Color(0.72, 0.95, 0.28), Vector3.ZERO, 0.9),
		_ell(Vector3(0, 0.68, 0.17), Vector3(0.08, 0.06, 0.04), Color(0.12, 0.04, 0.04)),
		_ball(Vector3(-0.08, 0.8, 0.15), 0.035, Color(1, 0.2, 0.1), true),
		_ball(Vector3(0.08, 0.8, 0.15), 0.035, Color(1, 0.2, 0.1), true),
		_seg(Vector3(-0.18, 0.72, 0.05), Vector3(-0.27, 0.5, 0.16), 0.035, olive.darkened(0.2)),
		_seg(Vector3(0.18, 0.72, 0.05), Vector3(0.27, 0.5, 0.16), 0.035, olive.darkened(0.2)),
	]
	for side in [-1.0, 1.0]:
		var s: float = sw * side
		var hip := Vector3(side * 0.11, 0.45, 0)
		var knee := Vector3(side * 0.18, 0.25, 0.06 + s * 0.08)
		var foot := Vector3(side * 0.15, 0.03, s * 0.13)
		parts.append(_seg(hip, knee, 0.06, leg))
		parts.append(_seg(knee, foot, 0.05, leg))
		parts.append(_ell(foot + Vector3(0, 0, 0.05), Vector3(0.06, 0.03, 0.09), leg))
	return parts


static func _brute(ph: float) -> Array:
	var purple := Color(0.46, 0.22, 0.56)
	var dark := Color(0.26, 0.1, 0.32)
	var bone := Color(0.95, 0.9, 0.8)
	var sw := sin(ph * TAU)
	var parts: Array = [
		_ell(Vector3(0, 0.98, -0.05), Vector3(0.55, 0.45, 0.42), purple, Vector3.ZERO, 0.25),
		_ell(Vector3(0, 0.86, 0.2), Vector3(0.38, 0.3, 0.25), purple.lightened(0.12)),
		_ell(Vector3(0, 1.33, 0.28), Vector3(0.24, 0.2, 0.22), purple.lightened(0.05), Vector3.ZERO, 0.3),
		_ell(Vector3(0, 1.2, 0.43), Vector3(0.16, 0.07, 0.08), Color(0.12, 0.02, 0.06)),
		_ball(Vector3(-0.09, 1.4, 0.46), 0.04, Color(1, 0.9, 0.15), true),
		_ball(Vector3(0.09, 1.4, 0.46), 0.04, Color(1, 0.9, 0.15), true),
		_ball(Vector3(0, 1.46, 0.45), 0.035, Color(1, 0.9, 0.15), true),
	]
	for i in 4:
		parts.append(_ell(Vector3(-0.1 + i * 0.065, 1.22, 0.49), Vector3(0.018, 0.03, 0.015), bone))
	for i in 3:
		parts.append(_seg(Vector3(0, 1.3 - i * 0.2, -0.32 - i * 0.04), Vector3(0, 1.48 - i * 0.22, -0.52 - i * 0.04), 0.05, bone, 0.3))
	for side in [-1.0, 1.0]:
		var s: float = sw * side
		var hip := Vector3(side * 0.26, 0.6, 0)
		var knee := Vector3(side * 0.33, 0.32, 0.1 + s * 0.1)
		var foot := Vector3(side * 0.3, 0.05, s * 0.16)
		parts.append(_seg(hip, knee, 0.11, dark))
		parts.append(_seg(knee, foot, 0.1, dark))
		parts.append(_ell(foot + Vector3(0, 0, 0.06), Vector3(0.11, 0.05, 0.14), dark))
		var shoulder := Vector3(side * 0.55, 1.18, 0)
		var elbow := Vector3(side * 0.78, 0.82, 0.12 - s * 0.12)
		var hand := Vector3(side * 0.74, 0.46, 0.3 + s * 0.12)
		parts.append(_seg(shoulder, elbow, 0.15, purple.darkened(0.1)))
		parts.append(_seg(elbow, hand, 0.13, purple.darkened(0.1)))
		for c in 3:
			parts.append(_seg(hand, hand + Vector3(side * 0.04 * (c - 1), -0.18, 0.12), 0.025, bone, 0.4))
	return parts


static func _hive(ph: float, scale: float, flesh: Color) -> Array:
	var pulse := 1.0 + 0.04 * sin(ph * TAU)
	var parts: Array = [
		_ell(Vector3(0, 0.3, 0) * scale, Vector3(1.0, 0.35, 1.0) * scale, flesh.darkened(0.25), Vector3.ZERO, 0.3),
		_ell(Vector3(0, 0.85, 0) * scale, Vector3(0.62, 0.62, 0.62) * scale * pulse, flesh, Vector3.ZERO, 0.45),
		_ell(Vector3(0.05, 1.45, 0.02) * scale, Vector3(0.36, 0.36, 0.36) * scale * pulse, flesh.lightened(0.1), Vector3.ZERO, 0.45),
	]
	var glow := Color(1.0, 0.55, 0.1) if ph < 0.5 else Color(1.0, 0.85, 0.35)
	var spots := [[0.3, 0.75], [1.6, 0.95], [2.8, 0.7], [4.1, 0.9], [5.3, 0.8], [0.9, 1.4], [3.5, 1.45]]
	for sp in spots:
		var a: float = sp[0]
		var y: float = sp[1]
		var r := 0.6 if y < 1.2 else 0.34
		var cy := 0.85 if y < 1.2 else 1.45
		var dy := (y - cy) / r
		var ring := sqrt(maxf(0.0, 1.0 - dy * dy)) * r
		var p := Vector3(cos(a) * ring, y, sin(a) * ring) * scale
		parts.append(_ball(p, 0.09 * scale * (1.1 if ph >= 0.5 else 1.0), glow, true))
	for i in 5:
		var a2 := i * 1.25 + 0.4
		parts.append(_seg(Vector3(cos(a2) * 0.95, 0.15, sin(a2) * 0.95) * scale, Vector3(cos(a2) * 0.45, 1.1, sin(a2) * 0.45) * scale, 0.04 * scale, flesh.lightened(0.25), 0.5))
	return parts


static func _survivor(ph: float) -> Array:
	var coat := Color(0.78, 0.38, 0.2)
	var trousers := Color(0.2, 0.22, 0.32)
	var skin := Color(0.9, 0.74, 0.6)
	var parts: Array = [
		_seg(Vector3(-0.05, 0.42, 0), Vector3(-0.06, 0.03, 0.02), 0.035, trousers),
		_seg(Vector3(0.05, 0.42, 0), Vector3(0.06, 0.03, -0.02), 0.035, trousers),
		_ell(Vector3(0, 0.56, 0), Vector3(0.11, 0.16, 0.08), coat, Vector3.ZERO, 0.15),
		_ell(Vector3(0, 0.78, 0.01), Vector3(0.065, 0.075, 0.065), skin, Vector3.ZERO, 0.2),
		_ell(Vector3(0, 0.82, -0.01), Vector3(0.07, 0.045, 0.07), Color(0.3, 0.2, 0.14)),
		_seg(Vector3(-0.11, 0.65, 0), Vector3(-0.14, 0.43, 0.03), 0.028, coat),
	]
	var hand := Vector3(0.2, 0.88, 0.03) if ph < 0.5 else Vector3(0.26, 0.8, 0.05)
	parts.append(_seg(Vector3(0.11, 0.65, 0), hand, 0.028, coat))
	parts.append(_ball(hand, 0.03, skin))
	return parts


static func _mech() -> Array:
	var hull := Color(0.47, 0.51, 0.45)
	var dark := Color(0.25, 0.27, 0.25)
	var gun := Color(0.16, 0.16, 0.17)
	var parts: Array = []
	for side in [-1.0, 1.0]:
		parts.append(_box(Vector3(side * 0.3, 0.06, 0.06), Vector3(0.16, 0.06, 0.25), dark))
		parts.append(_box(Vector3(side * 0.28, 0.46, 0), Vector3(0.11, 0.36, 0.12), dark))
		parts.append(_ell(Vector3(side * 0.28, 0.62, 0.11), Vector3(0.1, 0.1, 0.06), hull, Vector3.ZERO, 0.3))
		parts.append(_box(Vector3(side * 0.6, 1.3, 0.02), Vector3(0.12, 0.26, 0.17), hull.darkened(0.08), 0.0, 0.2))
		parts.append(_box(Vector3(side * 0.6, 1.06, 0.3), Vector3(0.05, 0.05, 0.25), gun, 0.0, 0.4))
		parts.append(_box(Vector3(side * 0.6, 1.06, 0.56), Vector3(0.065, 0.065, 0.03), gun.lightened(0.1)))
		parts.append(_box(Vector3(side * 0.3, 1.25, -0.38), Vector3(0.06, 0.12, 0.04), Color(0.12, 0.12, 0.12)))
	parts.append(_box(Vector3(0, 0.86, 0), Vector3(0.36, 0.1, 0.22), dark))
	parts.append(_box(Vector3(0, 1.3, 0), Vector3(0.46, 0.36, 0.36), hull, 0.0, 0.25))
	parts.append(_box(Vector3(0, 1.72, -0.02), Vector3(0.3, 0.08, 0.26), hull.lightened(0.08), 0.0, 0.25))
	parts.append(_box(Vector3(0, 1.43, 0.36), Vector3(0.25, 0.1, 0.02), Color(0.4, 0.8, 1.0), 0.0, 0.9))
	parts.append(_box(Vector3(0, 1.04, 0.36), Vector3(0.38, 0.03, 0.01), Color(0.9, 0.75, 0.15)))
	parts.append(_box(Vector3(0.3, 1.84, -0.06), Vector3(0.14, 0.1, 0.18), hull.darkened(0.2)))
	# Back: hatch, handle and ladder rungs — this is where you climb in.
	parts.append(_box(Vector3(0, 1.33, -0.37), Vector3(0.2, 0.2, 0.015), hull.darkened(0.25)))
	parts.append(_box(Vector3(0, 1.3, -0.39), Vector3(0.06, 0.02, 0.01), Color(0.95, 0.75, 0.2)))
	for r in 4:
		parts.append(_box(Vector3(0, 0.92 + r * 0.06 - 0.06, -0.38), Vector3(0.1, 0.008, 0.01), Color(0.75, 0.75, 0.7)))
	return parts


static func _crate(ph: float) -> Array:
	var wood := Color(0.5, 0.36, 0.2)
	var parts: Array = [
		_box(Vector3(0, 0.17, 0), Vector3(0.24, 0.16, 0.17), wood),
		_box(Vector3(0, 0.345, 0), Vector3(0.255, 0.02, 0.185), wood.lightened(0.2)),
		_ball(Vector3(0, 0.39, 0), 0.04 if ph < 0.5 else 0.05, Color(0.4, 1.0, 0.6), true),
	]
	for i in 3:
		parts.append(_box(Vector3(-0.15 + i * 0.15, 0.17, 0.172), Vector3(0.035, 0.12, 0.004), Color(0.9, 0.75, 0.15)))
		parts.append(_box(Vector3(-0.15 + i * 0.15, 0.17, -0.172), Vector3(0.035, 0.12, 0.004), Color(0.9, 0.75, 0.15)))
	return parts


static func _canister() -> Array:
	return [
		_box(Vector3(0, 0.25, 0), Vector3(0.12, 0.24, 0.08), Color(0.8, 0.18, 0.14), 0.0, 0.6),
		_box(Vector3(0, 0.3, 0), Vector3(0.125, 0.04, 0.085), Color(0.95, 0.85, 0.2)),
		_box(Vector3(0.05, 0.52, 0), Vector3(0.035, 0.035, 0.03), Color(0.35, 0.35, 0.35), 0.0, 0.5),
		_box(Vector3(-0.04, 0.53, 0), Vector3(0.06, 0.015, 0.02), Color(0.25, 0.25, 0.25)),
	]


static func _datacore(ph: float) -> Array:
	var on := Color(0.35, 0.9, 1.0) if ph < 0.5 else Color(0.7, 1.0, 1.0)
	return [
		_box(Vector3(0, 0.14, 0), Vector3(0.2, 0.14, 0.14), Color(0.2, 0.22, 0.26), 0.0, 0.5),
		_box(Vector3(0, 0.18, 0.142), Vector3(0.14, 0.02, 0.004), on, 0.0, 0.0, true),
		_box(Vector3(0, 0.18, -0.142), Vector3(0.14, 0.02, 0.004), on, 0.0, 0.0, true),
		_box(Vector3(-0.1, 0.08, 0.142), Vector3(0.03, 0.02, 0.004), Color(1.0, 0.5, 0.2), 0.0, 0.0, true),
		_ball(Vector3(0, 0.32, 0), 0.04, on, true),
	]


static func _beacon(lit: bool) -> Array:
	var steel := Color(0.6, 0.62, 0.65)
	var top := Vector3(0, 2.3, 0)
	var parts: Array = []
	var corners := [Vector3(-0.28, 0, -0.28), Vector3(0.28, 0, -0.28), Vector3(0.28, 0, 0.28), Vector3(-0.28, 0, 0.28)]
	for c: Vector3 in corners:
		parts.append(_seg(c, top + c * 0.2, 0.028, steel, 0.4))
	for h in [0.5, 1.0, 1.5, 1.95]:
		var k: float = 1.0 - h / 2.3 * 0.8
		for i in 4:
			var a: Vector3 = corners[i] * k + Vector3(0, h, 0)
			var b: Vector3 = corners[(i + 1) % 4] * k + Vector3(0, h, 0)
			parts.append(_seg(a, b, 0.018, steel))
	parts.append(_box(Vector3(0, 2.25, 0.08), Vector3(0.16, 0.12, 0.02), steel.darkened(0.2), 0.0, 0.5))
	parts.append(_ball(Vector3(0, 2.46, 0), 0.09, Color(0.3, 1.0, 0.5) if lit else Color(0.95, 0.2, 0.15), true))
	return parts
