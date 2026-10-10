extends RefCounted
## Real 3D models for the Baker (1.5): the aliens and their carcasses,
## Brigid seen from outside, the Chest, and every prop and pickup.
## Each builder takes the animation phase (0..1) and returns a Node3D in
## world units (1 unit = 2 m), standing on y = 0 and facing +Z.

var bk                          ## the Baker: owns materials and mesh helpers


func _init(baker) -> void:
	bk = baker


# --- helpers -------------------------------------------------------------------

func m(key: String, col: Color, rough := 0.6, metal := 0.0, kind := "paint") -> StandardMaterial3D:
	return bk._mat(key, col, rough, metal, kind)


func ell(p: Node3D, c: Vector3, r: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	return bk._part(p, bk._sph(1.0), mat, c, rot, r)


func box(p: Node3D, c: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	return bk._part(p, bk._box(size.x, size.y, size.z), mat, c, rot)


func cyl(p: Node3D, c: Vector3, r: float, h: float, mat: Material, rot := Vector3.ZERO, r2 := -1.0) -> MeshInstance3D:
	return bk._part(p, bk._cyl(r, r if r2 < 0.0 else r2, h), mat, c, rot)


func seg(p: Node3D, a: Vector3, b: Vector3, r: float, mat: Material, r_end := -1.0) -> MeshInstance3D:
	## A limb between two points (capsule, or a tapered cylinder).
	var d := b - a
	var length := d.length()
	if length < 0.0001:
		return null
	var y := d / length
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	var mesh: Mesh
	if r_end >= 0.0:
		mesh = bk._cyl(r_end, r, length, 10)
	else:
		mesh = bk._caps(r, length + r * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	p.add_child(mi)
	return mi


func chain(p: Node3D, pts: Array, r0: float, r1: float, mat: Material) -> void:
	## A tapering limb through several points (tentacles, legs).
	for i in pts.size() - 1:
		var k := float(i) / maxf(pts.size() - 2, 1)
		seg(p, pts[i], pts[i + 1], lerpf(r0, r1, k), mat)


static func wave(ph: float, off := 0.0) -> float:
	return sin((ph + off) * TAU)


# =============================================================================
# Aliens
# =============================================================================

func crawler(ph: float, dead := false) -> Node3D:
	## A dog-sized six-legged hunter: plated back, soft pale belly,
	## a cluster of eyes and hooked mandibles.
	var r := Node3D.new()
	var shell := m("cr_shell", Color(0.14, 0.2, 0.1), 0.28, 0.1, "chitin")
	var shell2 := m("cr_shell2", Color(0.26, 0.36, 0.15), 0.3, 0.1, "chitin")
	var belly := m("cr_belly", Color(0.6, 0.52, 0.34), 0.55, 0.0, "flesh")
	var bone := m("cr_bone", Color(0.85, 0.8, 0.64), 0.45, 0.0, "bone")
	var eye := m("cr_eye", Color(1.0, 0.18, 0.08), 0.2, 0.0, "glow") if not dead else m("cr_eyed", Color(0.25, 0.08, 0.05), 0.3)
	var bob := absf(wave(ph)) * 0.025
	var y0 := 0.33 + bob
	ell(r, Vector3(0, y0 - 0.05, -0.05), Vector3(0.2, 0.1, 0.36), belly)
	ell(r, Vector3(0, y0 + 0.02, -0.26), Vector3(0.22, 0.15, 0.24), shell)
	for i in 4:
		ell(r, Vector3(0, y0 + 0.07 - i * 0.005, -0.12 + i * 0.12), Vector3(0.21 - i * 0.015, 0.1, 0.1), shell2 if i % 2 == 1 else shell, Vector3(-0.2, 0, 0))
	for i in 4:
		seg(r, Vector3(0, y0 + 0.14, -0.2 + i * 0.12), Vector3(0, y0 + 0.24 - i * 0.02, -0.25 + i * 0.12), 0.018, bone, 0.002)
	# Head
	ell(r, Vector3(0, y0 + 0.02, 0.36), Vector3(0.13, 0.1, 0.13), shell)
	ell(r, Vector3(0, y0 - 0.03, 0.44), Vector3(0.09, 0.05, 0.07), belly)
	for e in [Vector3(-0.06, 0.07, 0.44), Vector3(0.06, 0.07, 0.44), Vector3(-0.035, 0.1, 0.46), Vector3(0.035, 0.1, 0.46), Vector3(0, 0.05, 0.48)]:
		ell(r, Vector3(e.x, y0 + e.y - 0.02, e.z), Vector3(0.022, 0.022, 0.022), eye)
	for sx in [-1.0, 1.0]:
		var jaw_open := 0.03 + absf(wave(ph, 0.25)) * 0.03
		chain(r, [Vector3(sx * 0.07, y0 - 0.02, 0.45), Vector3(sx * (0.08 + jaw_open), y0 - 0.06, 0.55), Vector3(sx * 0.03, y0 - 0.09, 0.62)], 0.022, 0.008, bone)
	# Six legs, tripod gait.
	for side in [-1.0, 1.0]:
		for k in 3:
			var z := -0.22 + k * 0.22
			var phase = 0.0 if (k + (1 if side > 0 else 0)) % 2 == 0 else 0.5
			var sw = wave(ph, phase)
			var lift = maxf(0.0, wave(ph, phase + 0.25)) * 0.08
			var hip = Vector3(side * 0.16, y0, z)
			var knee = Vector3(side * 0.42, y0 + 0.2, z + sw * 0.07)
			var ankle = Vector3(side * 0.56, 0.12 + lift, z + sw * 0.13)
			var foot = Vector3(side * 0.6, 0.0 + lift, z + sw * 0.15)
			seg(r, hip, knee, 0.035, shell)
			seg(r, knee, ankle, 0.028, shell2)
			seg(r, ankle, foot, 0.016, bone, 0.004)
			ell(r, knee, Vector3(0.04, 0.04, 0.04), shell)
	return r


func spitter(ph: float, dead := false) -> Node3D:
	## Long-legged and upright, carrying a swollen sac of glowing acid on its
	## back. It arches its neck to spit.
	var r := Node3D.new()
	var hide := m("sp_hide", Color(0.42, 0.45, 0.2), 0.45, 0.0, "chitin")
	var dark := m("sp_dark", Color(0.2, 0.22, 0.1), 0.4, 0.05, "chitin")
	var flesh := m("sp_flesh", Color(0.6, 0.5, 0.35), 0.5, 0.0, "flesh")
	var sac := m("sp_sac", Color(0.32, 0.6, 0.12), 0.15, 0.0, "glow") if not dead else m("sp_sacd", Color(0.3, 0.4, 0.15), 0.3, 0.0, "flesh")
	var eye := m("sp_eye", Color(1.0, 0.3, 0.1), 0.2, 0.0, "glow") if not dead else m("sp_eyed", Color(0.2, 0.1, 0.05), 0.3)
	var pulse := 1.0 + 0.06 * wave(ph)
	var hip_y := 0.58
	# Legs: digitigrade (knee forward, ankle back).
	for side in [-1.0, 1.0]:
		var sw = wave(ph, 0.0 if side < 0 else 0.5)
		var lift = maxf(0.0, wave(ph, (0.0 if side < 0 else 0.5) + 0.25)) * 0.06
		var hip = Vector3(side * 0.1, hip_y, -0.02)
		var knee = Vector3(side * 0.14, 0.38, 0.12 + sw * 0.08)
		var ankle = Vector3(side * 0.13, 0.16 + lift, -0.1 + sw * 0.12)
		var toe = Vector3(side * 0.13, 0.0 + lift, 0.04 + sw * 0.14)
		seg(r, hip, knee, 0.055, hide)
		seg(r, knee, ankle, 0.04, dark)
		seg(r, ankle, toe, 0.03, dark)
		for t in [-0.04, 0.0, 0.04]:
			seg(r, toe, toe + Vector3(t, -0.0, 0.07), 0.012, flesh, 0.003)
	# Body leaning forward, the acid sac above.
	ell(r, Vector3(0, hip_y + 0.12, 0.02), Vector3(0.17, 0.22, 0.15), hide, Vector3(0.3, 0, 0))
	ell(r, Vector3(0, hip_y + 0.05, 0.1), Vector3(0.12, 0.14, 0.08), flesh)
	ell(r, Vector3(0, hip_y + 0.42, -0.08), Vector3(0.24, 0.22, 0.24) * pulse, sac)
	for i in 5:
		var a := TAU * i / 5.0
		seg(r, Vector3(0, hip_y + 0.22, -0.08), Vector3(cos(a) * 0.2, hip_y + 0.45 + sin(a) * 0.1, -0.08 + sin(a) * 0.15), 0.014, dark)
	# Neck and head
	chain(r, [Vector3(0, hip_y + 0.24, 0.1), Vector3(0, hip_y + 0.36, 0.2), Vector3(0, hip_y + 0.38, 0.3)], 0.06, 0.045, hide)
	ell(r, Vector3(0, hip_y + 0.36, 0.36), Vector3(0.09, 0.08, 0.12), dark)
	ell(r, Vector3(0, hip_y + 0.3, 0.42), Vector3(0.06, 0.035, 0.07), flesh)
	ell(r, Vector3(-0.045, hip_y + 0.4, 0.42), Vector3(0.018, 0.018, 0.018), eye)
	ell(r, Vector3(0.045, hip_y + 0.4, 0.42), Vector3(0.018, 0.018, 0.018), eye)
	# Little grasping arms
	for side in [-1.0, 1.0]:
		chain(r, [Vector3(side * 0.13, hip_y + 0.2, 0.1), Vector3(side * 0.18, hip_y + 0.05, 0.18), Vector3(side * 0.12, hip_y - 0.02, 0.24)], 0.025, 0.012, hide)
	return r


func brute(ph: float, dead := false) -> Node3D:
	## A gorilla-shaped battering ram: armoured shoulders and back, a small
	## head slung low, enormous knuckle-walking arms.
	var r := Node3D.new()
	var skin := m("br_skin", Color(0.32, 0.17, 0.4), 0.5, 0.0, "flesh")
	var plate := m("br_plate", Color(0.62, 0.56, 0.5), 0.45, 0.05, "bone")
	var dark := m("br_dark", Color(0.18, 0.08, 0.22), 0.4, 0.0, "chitin")
	var eye := m("br_eye", Color(1.0, 0.85, 0.15), 0.2, 0.0, "glow") if not dead else m("br_eyed", Color(0.25, 0.2, 0.05), 0.3)
	var mouth := m("br_mouth", Color(0.25, 0.03, 0.05), 0.3, 0.0, "flesh")
	var s := wave(ph)
	var bob := absf(s) * 0.04
	var cy := 1.0 + bob
	# Body
	ell(r, Vector3(0, cy, -0.12), Vector3(0.5, 0.45, 0.42), skin)
	ell(r, Vector3(0, cy - 0.1, 0.18), Vector3(0.38, 0.32, 0.26), skin)
	ell(r, Vector3(0, cy - 0.32, -0.25), Vector3(0.3, 0.22, 0.25), skin)
	# Armour plates on back and shoulders
	for i in 4:
		ell(r, Vector3(0, cy + 0.32 - i * 0.04, -0.3 + i * 0.16), Vector3(0.36 - i * 0.03, 0.1, 0.16), plate, Vector3(-0.35 + i * 0.12, 0, 0))
	for side in [-1.0, 1.0]:
		ell(r, Vector3(side * 0.48, cy + 0.2, 0.0), Vector3(0.26, 0.16, 0.26), plate, Vector3(0, 0, side * 0.4))
		for k in 3:
			seg(r, Vector3(side * (0.45 + k * 0.05), cy + 0.3, -0.05 + k * 0.08), Vector3(side * (0.55 + k * 0.08), cy + 0.5, -0.1 + k * 0.08), 0.035, plate, 0.004)
	# Head: low, wide jaw, three eyes
	ell(r, Vector3(0, cy + 0.12, 0.42), Vector3(0.2, 0.17, 0.18), dark)
	ell(r, Vector3(0, cy + 0.02, 0.5), Vector3(0.17, 0.08, 0.12), mouth)
	for t in [-0.07, -0.025, 0.025, 0.07]:
		seg(r, Vector3(t, cy + 0.07, 0.58), Vector3(t, cy - 0.02, 0.6), 0.012, plate, 0.002)
	for e in [Vector3(-0.08, 0.2, 0.56), Vector3(0.08, 0.2, 0.56), Vector3(0, 0.25, 0.57)]:
		ell(r, Vector3(e.x, cy + e.y, e.z), Vector3(0.028, 0.028, 0.028), eye)
	# Arms: knuckle-walking
	for side in [-1.0, 1.0]:
		var sw = s * side
		var sh = Vector3(side * 0.56, cy + 0.12, 0.05)
		var el = Vector3(side * 0.82, cy - 0.3, 0.15 - sw * 0.12)
		var fist = Vector3(side * 0.72, 0.13, 0.36 + sw * 0.18)
		seg(r, sh, el, 0.17, skin)
		seg(r, el, fist, 0.15, skin)
		ell(r, el + (fist - el) * 0.35, Vector3(0.17, 0.2, 0.17), plate, Vector3(0, 0, side * 0.3))
		ell(r, fist, Vector3(0.17, 0.13, 0.18), dark)
		for c in 3:
			seg(r, fist + Vector3(side * 0.05 * (c - 1), -0.05, 0.1), fist + Vector3(side * 0.07 * (c - 1), -0.12, 0.22), 0.025, plate, 0.004)
	# Legs: short and thick
	for side in [-1.0, 1.0]:
		var sw2 = -s * side
		var hip = Vector3(side * 0.26, cy - 0.4, -0.2)
		var knee = Vector3(side * 0.32, 0.36, -0.05 + sw2 * 0.1)
		var foot = Vector3(side * 0.3, 0.06, -0.08 + sw2 * 0.16)
		seg(r, hip, knee, 0.13, skin)
		seg(r, knee, foot, 0.11, dark)
		ell(r, foot + Vector3(0, -0.02, 0.06), Vector3(0.12, 0.06, 0.16), dark)
	return r


func flyer(ph: float, dead := false) -> Node3D:
	## A wasp the size of a dog: banded abdomen with a stinger, glassy
	## veined wings beating in a blur, legs dangling.
	var r := Node3D.new()
	var shell := m("fl_shell", Color(0.5, 0.26, 0.1), 0.25, 0.1, "chitin")
	var band := m("fl_band", Color(0.85, 0.65, 0.12), 0.3, 0.1, "chitin")
	var dark := m("fl_dark", Color(0.12, 0.08, 0.05), 0.35, 0.1, "chitin")
	var wing := m("fl_wing", Color(0.82, 0.9, 0.95, 0.38), 0.1, 0.0, "alpha")
	var eye := m("fl_eye", Color(0.3, 1.0, 0.9), 0.15, 0.0, "glow") if not dead else m("fl_eyed", Color(0.1, 0.2, 0.2), 0.3)
	var y0 := 0.72
	ell(r, Vector3(0, y0, 0.05), Vector3(0.15, 0.14, 0.19), shell)
	for i in 4:
		ell(r, Vector3(0, y0 - 0.06 - i * 0.05, -0.18 - i * 0.09), Vector3(0.13 - i * 0.02, 0.12 - i * 0.015, 0.08), band if i % 2 == 0 else dark, Vector3(-0.55, 0, 0))
	seg(r, Vector3(0, y0 - 0.26, -0.47), Vector3(0, y0 - 0.38, -0.53), 0.02, dark, 0.002)
	ell(r, Vector3(0, y0 + 0.04, 0.3), Vector3(0.11, 0.1, 0.1), shell)
	ell(r, Vector3(-0.07, y0 + 0.07, 0.36), Vector3(0.05, 0.06, 0.04), eye)
	ell(r, Vector3(0.07, y0 + 0.07, 0.36), Vector3(0.05, 0.06, 0.04), eye)
	for sx in [-1.0, 1.0]:
		chain(r, [Vector3(sx * 0.04, y0 - 0.02, 0.38), Vector3(sx * 0.06, y0 - 0.09, 0.44), Vector3(sx * 0.02, y0 - 0.12, 0.46)], 0.014, 0.005, dark)
		chain(r, [Vector3(sx * 0.05, y0 + 0.12, 0.36), Vector3(sx * 0.12, y0 + 0.25, 0.42), Vector3(sx * 0.18, y0 + 0.3, 0.5)], 0.008, 0.003, dark)
	var beat := wave(ph) * (0.0 if dead else 1.0)
	for sx in [-1.0, 1.0]:
		for k in 2:
			var flap := beat * 0.9 * (1.0 if k == 0 else -0.7) + (0.4 if dead else 0.0)
			var w := Node3D.new()
			w.position = Vector3(sx * 0.1, y0 + 0.1, 0.1 - k * 0.12)
			w.rotation = Vector3(0, sx * (0.25 + k * 0.2), sx * flap)
			r.add_child(w)
			ell(w, Vector3(sx * 0.32, 0, 0), Vector3(0.32, 0.008, 0.11 - k * 0.025), wing)
			seg(w, Vector3(0, 0, 0.0), Vector3(sx * 0.6, 0, -0.02), 0.006, dark)
		for k in 3:
			chain(r, [Vector3(sx * 0.08, y0 - 0.08, 0.1 - k * 0.08), Vector3(sx * 0.2, y0 - 0.2, 0.12 - k * 0.1), Vector3(sx * 0.16, y0 - 0.4, 0.16 - k * 0.12)], 0.014, 0.006, dark)
	return r


func burrower(ph: float, dead := false) -> Node3D:
	## An armoured digger: overlapping arched plates like a woodlouse, a bony
	## plough of a snout and two shovel claws.
	var r := Node3D.new()
	var plate := m("bu_plate", Color(0.42, 0.33, 0.24), 0.4, 0.05, "chitin")
	var plate2 := m("bu_plate2", Color(0.32, 0.25, 0.18), 0.45, 0.05, "chitin")
	var belly := m("bu_belly", Color(0.7, 0.55, 0.42), 0.55, 0.0, "flesh")
	var bone := m("bu_bone", Color(0.88, 0.84, 0.72), 0.45, 0.0, "bone")
	var dirt := m("bu_dirt", Color(0.35, 0.26, 0.18), 0.95, 0.0, "earth")
	var eye := m("bu_eye", Color(1.0, 0.5, 0.1), 0.2, 0.0, "glow") if not dead else m("bu_eyed", Color(0.2, 0.1, 0.05), 0.3)
	var s := wave(ph)
	for i in 7:
		var z := 0.5 - i * 0.17
		var y := 0.42 + 0.12 * sin(float(i) / 6.0 * PI) - i * 0.01
		var rr := 0.4 - absf(i - 2.0) * 0.04
		ell(r, Vector3(0, y, z), Vector3(rr, rr * 0.75, 0.13), plate if i % 2 == 0 else plate2, Vector3(0.15, 0, 0))
	ell(r, Vector3(0, 0.26, 0.0), Vector3(0.3, 0.14, 0.62), belly)
	ell(r, Vector3(0, 0.12, -0.2), Vector3(0.25, 0.06, 0.4), dirt)
	# Head and plough-snout
	ell(r, Vector3(0, 0.38, 0.66), Vector3(0.2, 0.17, 0.2), plate2, Vector3(0.3, 0, 0))
	seg(r, Vector3(0, 0.4, 0.78), Vector3(0, 0.2, 1.0), 0.07, bone, 0.01)
	for k in 3:
		cyl(r, Vector3(0, 0.38 - k * 0.06, 0.82 + k * 0.05), 0.075 - k * 0.012, 0.02, bone, Vector3(0.9, 0, 0))
	ell(r, Vector3(-0.1, 0.5, 0.75), Vector3(0.025, 0.025, 0.025), eye)
	ell(r, Vector3(0.1, 0.5, 0.75), Vector3(0.025, 0.025, 0.025), eye)
	for side in [-1.0, 1.0]:
		var sw = s * side
		var sh = Vector3(side * 0.28, 0.4, 0.48)
		var hand = Vector3(side * 0.46, 0.1 + maxf(0.0, sw) * 0.12, 0.74 + sw * 0.12)
		seg(r, sh, hand, 0.08, plate2)
		ell(r, hand + Vector3(0, 0, 0.06), Vector3(0.15, 0.04, 0.14), bone, Vector3(0.35, 0, side * 0.2))
		for c in 3:
			seg(r, hand + Vector3(side * 0.05 * (c - 1), -0.02, 0.1), hand + Vector3(side * 0.07 * (c - 1), -0.08, 0.24), 0.022, bone, 0.004)
		for k in 2:
			var z2 = 0.12 - k * 0.32
			var ss = s if k == 0 else -s
			chain(r, [Vector3(side * 0.24, 0.3, z2), Vector3(side * 0.42, 0.2, z2 + ss * 0.08), Vector3(side * 0.4, 0.02, z2 + ss * 0.12)], 0.045, 0.02, plate2)
	return r


func hive(ph: float, scale := 1.0, mother := false, dead := false) -> Node3D:
	## A nest grown out of the ground: fleshy sacs on a root-mound, glowing
	## pustules, bone spikes. The Brood Mother rises from a bigger one.
	var r := Node3D.new()
	var flesh := m("hv_flesh" + ("m" if mother else ""), Color(0.45, 0.12, 0.33) if not mother else Color(0.5, 0.1, 0.18), 0.35, 0.0, "flesh")
	var flesh2 := m("hv_flesh2", Color(0.3, 0.06, 0.22), 0.4, 0.0, "flesh")
	var bone := m("hv_bone", Color(0.82, 0.76, 0.66), 0.5, 0.0, "bone")
	var glow := m("hv_glow", Color(1.0, 0.55, 0.12), 0.2, 0.0, "glow") if not dead else m("hv_glowd", Color(0.3, 0.15, 0.05), 0.4)
	var root_m := m("hv_root", Color(0.25, 0.12, 0.16), 0.6, 0.0, "earth")
	var pulse := 1.0 + (0.05 * wave(ph) if not dead else -0.15)
	var k := scale
	ell(r, Vector3(0, 0.12, 0) * k, Vector3(1.0, 0.3, 1.0) * k, root_m)
	for i in 8:
		var a := TAU * i / 8.0 + 0.3
		chain(r, [Vector3(cos(a) * 0.6, 0.18, sin(a) * 0.6) * k, Vector3(cos(a) * 0.95, 0.06, sin(a) * 0.95) * k, Vector3(cos(a) * 1.05, 0.0, sin(a) * 1.05) * k], 0.07 * k, 0.02 * k, root_m)
	var sacs := [[Vector3(0, 0.7, 0), 0.55], [Vector3(0.35, 0.45, 0.25), 0.36], [Vector3(-0.38, 0.5, -0.1), 0.38], [Vector3(0.1, 0.4, -0.42), 0.32], [Vector3(0.05, 1.18, 0.05), 0.33]]
	for sc in sacs:
		var c: Vector3 = sc[0]
		var rr: float = sc[1]
		ell(r, c * k * Vector3(1, 1 if not dead else 0.6, 1), Vector3(rr, rr * (1.05 if not dead else 0.6), rr) * k * pulse, flesh)
	for i in 9:
		var a2 := TAU * i / 9.0
		var c2 := Vector3(cos(a2) * 0.42, 0.55 + sin(i * 1.7) * 0.25, sin(a2) * 0.42) * k
		ell(r, c2, Vector3(0.07, 0.07, 0.07) * k, glow)
	for i in 6:
		var a3 := TAU * i / 6.0 + 0.5
		seg(r, Vector3(cos(a3) * 0.4, 0.5, sin(a3) * 0.4) * k, Vector3(cos(a3) * 0.75, 0.95, sin(a3) * 0.75) * k, 0.05 * k, bone, 0.005 * k)
	for i in 4:
		var a4 := TAU * i / 4.0
		chain(r, [Vector3(cos(a4) * 0.2, 0.9, sin(a4) * 0.2) * k, Vector3(cos(a4) * 0.32, 1.05, sin(a4) * 0.32) * k, Vector3(cos(a4) * 0.22, 1.2, sin(a4) * 0.22) * k], 0.05 * k, 0.03 * k, flesh2)
	if mother:
		# The Brood Mother: a crowned body with eyes and reaching tentacles.
		var by := 1.55 * k
		ell(r, Vector3(0, by, 0), Vector3(0.48, 0.5, 0.44) * k * pulse, flesh)
		ell(r, Vector3(0, by + 0.42 * k, 0.12 * k), Vector3(0.3, 0.26, 0.28) * k, flesh2)
		for e in [Vector3(-0.12, 0.5, 0.36), Vector3(0.12, 0.5, 0.36), Vector3(0, 0.6, 0.36), Vector3(-0.2, 0.38, 0.34), Vector3(0.2, 0.38, 0.34)]:
			ell(r, Vector3(e.x, e.y + 1.55, e.z) * k, Vector3(0.05, 0.05, 0.05) * k, glow)
		for i in 7:
			var a5 := PI * (0.15 + i * 0.12)
			seg(r, Vector3(cos(a5) * 0.28, 2.1, -0.05 + sin(a5) * 0.02) * k, Vector3(cos(a5) * 0.5, 2.55 + sin(i) * 0.08, -0.15) * k, 0.045 * k, bone, 0.004 * k)
		for i in 6:
			var a6 := TAU * i / 6.0
			var sw = wave(ph, i * 0.17) * 0.25 * (0.0 if dead else 1.0)
			var p0 := Vector3(cos(a6) * 0.35, by - 0.2 * k, sin(a6) * 0.35 + 0.1)
			var pts := [p0 * Vector3(1, 1, 1)]
			for s2 in 4:
				var t := float(s2 + 1) / 4.0
				pts.append(Vector3(cos(a6 + sw) * (0.35 + t * 0.7), by - 0.2 * k - t * 0.9 * k + sin(t * PI) * 0.35 * k, sin(a6 + sw) * (0.35 + t * 0.7) + 0.15) * Vector3(k, 1, k))
			chain(r, pts, 0.08 * k, 0.025 * k, flesh2)
	return r


func mound(ph: float) -> Node3D:
	## Churned earth heaving over something digging toward you.
	var r := Node3D.new()
	var dirt := m("md_dirt", Color(0.36, 0.27, 0.19), 0.95, 0.0, "earth")
	var dirt2 := m("md_dirt2", Color(0.27, 0.2, 0.14), 0.95, 0.0, "earth")
	var rock := m("md_rock", Color(0.45, 0.43, 0.4), 0.8, 0.0, "earth")
	var heave := 1.0 + 0.08 * wave(ph)
	ell(r, Vector3(0, 0.0, 0), Vector3(0.55, 0.26 * heave, 0.62), dirt)
	ell(r, Vector3(0.08, 0.12, 0.12), Vector3(0.3, 0.17 * heave, 0.3), dirt2)
	for i in 9:
		var a := i * 1.37 + ph * 1.5
		var rr := 0.28 + 0.2 * float(i % 3) / 2.0
		ell(r, Vector3(cos(a) * rr, 0.12 + 0.05 * sin(ph * TAU + i), sin(a) * rr), Vector3(0.07, 0.05, 0.06) * (1.0 + float(i % 2) * 0.5), rock if i % 3 == 0 else dirt2, Vector3(0, a, 0.4))
	return r


# =============================================================================
# Brigid and the Chest
# =============================================================================

func mech(ph: float) -> Node3D:
	## Brigid, parked: a two-legged walker with reverse-jointed legs, a
	## cockpit pod with a canopy, rotary autocannon arms and a rocket pod.
	var r := Node3D.new()
	var paint := m("me_paint", Color(0.32, 0.36, 0.3), 0.6, 0.35, "paint")
	var paint2 := m("me_paint2", Color(0.24, 0.27, 0.23), 0.6, 0.35, "paint")
	var dark := m("me_dark", Color(0.1, 0.1, 0.11), 0.45, 0.7, "metal")
	var steel := m("me_steel", Color(0.55, 0.56, 0.57), 0.3, 0.9, "metal")
	var glass := m("me_glass", Color(0.25, 0.45, 0.55), 0.05, 0.4, "glass")
	var hazard := m("me_haz", Color(0.8, 0.6, 0.1), 0.6, 0.2, "paint")
	var light := m("me_light", Color(1.0, 0.9, 0.6), 0.2, 0.0, "glow")
	var hip_y := 1.0
	# Legs: thigh forward-down, shin back, foot with toes; hydraulics.
	for side in [-1.0, 1.0]:
		var hip = Vector3(side * 0.28, hip_y, -0.05)
		var knee = Vector3(side * 0.34, 0.6, 0.25)
		var ankle = Vector3(side * 0.32, 0.18, -0.15)
		seg(r, hip, knee, 0.11, paint)
		seg(r, knee, ankle, 0.08, paint2)
		ell(r, knee, Vector3(0.12, 0.12, 0.12), dark)
		seg(r, hip + Vector3(0, -0.05, -0.08), ankle + Vector3(0, 0.1, -0.06), 0.03, steel)
		box(r, ankle + Vector3(0, -0.12, 0.08), Vector3(0.22, 0.08, 0.36), dark)
		for t in [-0.07, 0.07]:
			box(r, ankle + Vector3(t, -0.14, 0.3), Vector3(0.07, 0.05, 0.14), paint2)
		box(r, ankle + Vector3(0, -0.14, -0.14), Vector3(0.1, 0.05, 0.12), paint2)
	# Pelvis and torso
	box(r, Vector3(0, hip_y + 0.05, -0.05), Vector3(0.62, 0.22, 0.42), dark)
	box(r, Vector3(0, hip_y + 0.42, -0.02), Vector3(0.78, 0.5, 0.66), paint)
	box(r, Vector3(0, hip_y + 0.7, -0.08), Vector3(0.7, 0.1, 0.56), paint2)
	box(r, Vector3(0, hip_y + 0.3, 0.33), Vector3(0.5, 0.18, 0.04), hazard)
	# Cockpit canopy at the front
	ell(r, Vector3(0, hip_y + 0.55, 0.3), Vector3(0.26, 0.17, 0.12), glass)
	box(r, Vector3(0, hip_y + 0.68, 0.28), Vector3(0.6, 0.05, 0.14), paint2)
	ell(r, Vector3(0.28, hip_y + 0.6, 0.34), Vector3(0.03, 0.03, 0.02), light)
	ell(r, Vector3(-0.28, hip_y + 0.6, 0.34), Vector3(0.03, 0.03, 0.02), light)
	# Rear hatch the pilot climbs out of
	box(r, Vector3(0, hip_y + 0.45, -0.36), Vector3(0.4, 0.34, 0.04), paint2)
	box(r, Vector3(0, hip_y + 0.3, -0.39), Vector3(0.3, 0.03, 0.03), steel)
	# Antenna
	seg(r, Vector3(0.25, hip_y + 0.75, -0.25), Vector3(0.3, hip_y + 1.2, -0.3), 0.008, steel)
	# Arms: rotary autocannons
	for side in [-1.0, 1.0]:
		var sh = Vector3(side * 0.5, hip_y + 0.5, 0.0)
		box(r, sh, Vector3(0.18, 0.26, 0.26), dark)
		box(r, sh + Vector3(side * 0.12, -0.08, 0.2), Vector3(0.2, 0.22, 0.6), paint)
		cyl(r, sh + Vector3(side * 0.12, -0.08, 0.6), 0.09, 0.3, dark, Vector3(PI * 0.5, 0, 0))
		for i in 6:
			var a := TAU * i / 6.0
			cyl(r, sh + Vector3(side * 0.12 + cos(a) * 0.04, -0.08 + sin(a) * 0.04, 0.85), 0.016, 0.3, steel, Vector3(PI * 0.5, 0, 0))
	# Shoulder rocket pod
	box(r, Vector3(-0.3, hip_y + 0.85, 0.0), Vector3(0.3, 0.22, 0.4), paint2)
	for i in 6:
		cyl(r, Vector3(-0.38 + (i % 3) * 0.08, hip_y + 0.8 + (i / 3) * 0.09, 0.2), 0.03, 0.02, dark, Vector3(PI * 0.5, 0, 0))
	return r


func chest(ph: float, suit: bool) -> Node3D:
	## The Chest: a hazard-striped cargo box on four stubby legs, with
	## harness straps on the roof and the hazmat suit hanging on the side.
	var r := Node3D.new()
	var body := m("ch_body", Color(0.82, 0.5, 0.12), 0.6, 0.3, "paint")
	var dark := m("ch_dark", Color(0.14, 0.14, 0.15), 0.5, 0.6, "metal")
	var steel := m("ch_steel", Color(0.55, 0.56, 0.57), 0.3, 0.9, "metal")
	var black := m("ch_black", Color(0.06, 0.06, 0.06), 0.6, 0.2, "paint")
	var strap := m("ch_strap", Color(0.18, 0.28, 0.5), 0.9, 0.0, "cloth")
	var green := m("ch_led", Color(0.3, 1.0, 0.4), 0.2, 0.0, "glow")
	var red := m("ch_led2", Color(1.0, 0.25, 0.15), 0.2, 0.0, "glow")
	var s := wave(ph)
	box(r, Vector3(0, 0.95, 0), Vector3(0.84, 0.64, 1.1), body)
	box(r, Vector3(0, 1.29, 0), Vector3(0.88, 0.06, 1.14), dark)
	box(r, Vector3(0, 0.6, 0), Vector3(0.8, 0.08, 1.06), dark)
	for k in 6:
		box(r, Vector3(0.425, 0.95, -0.45 + k * 0.18), Vector3(0.01, 0.6, 0.08), black if k % 2 == 0 else m("ch_yel", Color(0.95, 0.8, 0.15), 0.6, 0.2, "paint"))
	# Door outline and handle at the back, LEDs at the front
	box(r, Vector3(0, 0.95, -0.555), Vector3(0.6, 0.5, 0.01), dark)
	box(r, Vector3(0.2, 0.95, -0.565), Vector3(0.04, 0.16, 0.02), steel)
	ell(r, Vector3(-0.25, 1.15, 0.56), Vector3(0.04, 0.04, 0.02), green)
	ell(r, Vector3(0.25, 1.15, 0.56), Vector3(0.04, 0.04, 0.02), red)
	box(r, Vector3(0, 0.8, 0.555), Vector3(0.5, 0.1, 0.01), black)
	for k in 3:
		box(r, Vector3(0, 1.335, -0.35 + k * 0.35), Vector3(0.92, 0.025, 0.05), strap)
	# Legs
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var sw = s * sx * sz
			var hip = Vector3(sx * 0.36, 0.7, sz * 0.42)
			var knee = Vector3(sx * 0.56, 0.44, sz * 0.5 + sw * 0.08)
			var foot = Vector3(sx * 0.5, 0.04 + maxf(0.0, sw) * 0.08, sz * 0.52 + sw * 0.14)
			seg(r, hip, knee, 0.07, dark)
			seg(r, knee, foot, 0.06, steel)
			ell(r, knee, Vector3(0.08, 0.08, 0.08), dark)
			ell(r, foot, Vector3(0.11, 0.04, 0.13), black)
	if suit:
		var y := m("ch_suit", Color(0.93, 0.78, 0.12), 0.55, 0.0, "rubber")
		ell(r, Vector3(-0.5, 0.95, 0.05), Vector3(0.09, 0.24, 0.15), y)
		ell(r, Vector3(-0.51, 1.22, 0.05), Vector3(0.1, 0.1, 0.1), y)
		ell(r, Vector3(-0.57, 1.22, 0.05), Vector3(0.03, 0.06, 0.07), m("ch_visor", Color(0.12, 0.2, 0.24), 0.08, 0.3, "glass"))
		seg(r, Vector3(-0.5, 0.75, 0.0), Vector3(-0.5, 0.5, -0.02), 0.05, y)
		seg(r, Vector3(-0.5, 0.75, 0.1), Vector3(-0.5, 0.5, 0.12), 0.05, y)
		seg(r, Vector3(-0.47, 1.33, 0.05), Vector3(-0.5, 1.3, 0.05), 0.012, steel)
	return r


# =============================================================================
# Props and pickups
# =============================================================================

func crate(ph: float) -> Node3D:
	var r := Node3D.new()
	var olive := m("cr_olive", Color(0.3, 0.34, 0.22), 0.7, 0.2, "paint")
	var dark := m("cr_dk", Color(0.12, 0.12, 0.12), 0.5, 0.6, "metal")
	var glow := m("cr_glow", Color(1.0, 0.8, 0.3).lerp(Color(1.0, 1.0, 0.7), ph), 0.2, 0.0, "glow")
	box(r, Vector3(0, 0.15, 0), Vector3(0.5, 0.3, 0.32), olive)
	box(r, Vector3(0, 0.31, 0), Vector3(0.52, 0.04, 0.34), dark)
	for x in [-0.22, 0.22]:
		box(r, Vector3(x, 0.15, 0), Vector3(0.04, 0.31, 0.33), dark)
	box(r, Vector3(0, 0.2, 0.165), Vector3(0.16, 0.05, 0.01), glow)
	box(r, Vector3(0, 0.33, 0), Vector3(0.12, 0.02, 0.05), dark)
	return r


func canister(_ph: float) -> Node3D:
	var r := Node3D.new()
	var red := m("cn_red", Color(0.7, 0.15, 0.1), 0.45, 0.4, "paint")
	var dark := m("cn_dark", Color(0.15, 0.15, 0.15), 0.5, 0.5, "metal")
	box(r, Vector3(0, 0.2, 0), Vector3(0.3, 0.4, 0.14), red)
	box(r, Vector3(0, 0.2, 0.072), Vector3(0.22, 0.3, 0.005), m("cn_red2", Color(0.6, 0.12, 0.08), 0.5, 0.4, "paint"))
	seg(r, Vector3(-0.08, 0.44, 0), Vector3(0.06, 0.44, 0), 0.02, dark)
	cyl(r, Vector3(0.1, 0.43, 0), 0.03, 0.06, dark)
	return r


func datacore(ph: float) -> Node3D:
	var r := Node3D.new()
	var shell := m("dc_shell", Color(0.2, 0.22, 0.25), 0.35, 0.7, "metal")
	var led := m("dc_led", Color(0.3, 0.8, 1.0) if ph < 0.5 else Color(0.1, 0.3, 0.45), 0.2, 0.0, "glow")
	box(r, Vector3(0, 0.12, 0), Vector3(0.42, 0.24, 0.3), shell)
	box(r, Vector3(0, 0.245, 0), Vector3(0.44, 0.02, 0.32), m("dc_rim", Color(0.6, 0.6, 0.62), 0.3, 0.9, "metal"))
	for i in 3:
		box(r, Vector3(-0.1 + i * 0.1, 0.16, 0.152), Vector3(0.05, 0.025, 0.005), led)
	box(r, Vector3(0, 0.27, 0), Vector3(0.14, 0.03, 0.04), shell)
	return r


func beacon(lit: bool) -> Node3D:
	var r := Node3D.new()
	var steel := m("bc_steel", Color(0.55, 0.56, 0.57), 0.35, 0.85, "metal")
	var dark := m("bc_dark", Color(0.15, 0.16, 0.17), 0.5, 0.6, "metal")
	var lamp := m("bc_lamp", Color(0.3, 1.0, 0.5) if lit else Color(0.3, 0.75, 1.0), 0.2, 0.0, "glow") if lit else m("bc_lampoff", Color(0.2, 0.3, 0.35), 0.2, 0.3, "glass")
	for i in 3:
		var a := TAU * i / 3.0
		seg(r, Vector3(cos(a) * 0.45, 0.0, sin(a) * 0.45), Vector3(0, 1.0, 0), 0.025, steel)
	cyl(r, Vector3(0, 1.4, 0), 0.04, 1.6, steel)
	box(r, Vector3(0, 0.55, 0.0), Vector3(0.3, 0.3, 0.2), dark)
	box(r, Vector3(0, 0.6, 0.105), Vector3(0.18, 0.06, 0.01), lamp)
	ell(r, Vector3(0, 2.0, 0.15), Vector3(0.32, 0.32, 0.08), m("bc_dish", Color(0.82, 0.82, 0.8), 0.4, 0.5, "paint"), Vector3(-0.5, 0, 0))
	seg(r, Vector3(0, 2.0, 0.15), Vector3(0, 2.1, 0.45), 0.012, steel)
	ell(r, Vector3(0, 2.25, 0), Vector3(0.06, 0.06, 0.06), lamp)
	return r


func pine(_ph: float) -> Node3D:
	var r := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var bark := m("pn_bark", Color(0.3, 0.21, 0.14), 0.9, 0.0, "bark")
	cyl(r, Vector3(0, 1.4, 0), 0.04, 2.8, bark, Vector3.ZERO, 0.09)
	var tiers := 8
	for t in tiers:
		var k := float(t) / (tiers - 1)
		var y := 0.55 + k * 2.3
		var rad := lerpf(1.0, 0.16, k)
		var n := int(lerpf(9.0, 4.0, k))
		for i in n:
			var a := TAU * i / n + rng.randf_range(-0.3, 0.3) + t * 0.7
			var reach := rad * rng.randf_range(0.7, 1.0)
			var tip := Vector3(cos(a) * reach, y - reach * 0.4, sin(a) * reach)
			var g := m("pn_n%d" % (i % 3), Color(0.1, 0.24, 0.13).lerp(Color(0.2, 0.34, 0.17), float(i % 3) / 2.0), 0.85, 0.0, "leaf")
			seg(r, Vector3(0, y + 0.05, 0), tip, 0.02, bark)
			ell(r, (Vector3(0, y, 0) + tip) * 0.5 + Vector3(0, -0.04, 0), Vector3(reach * 0.55, 0.1, 0.22) * (1.1 - k * 0.4), g, Vector3(0, -a, 0.35))
	ell(r, Vector3(0, 2.95, 0), Vector3(0.1, 0.28, 0.1), m("pn_top", Color(0.17, 0.32, 0.17), 0.85, 0.0, "leaf"))
	return r


func tree(_ph: float) -> Node3D:
	var r := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 505
	var bark := m("tr_bark", Color(0.32, 0.25, 0.18), 0.9, 0.0, "bark")
	seg(r, Vector3(0, 0, 0), Vector3(0.05, 1.3, 0), 0.11, bark, 0.07)
	seg(r, Vector3(0.04, 1.1, 0), Vector3(0.55, 1.8, 0.1), 0.06, bark, 0.03)
	seg(r, Vector3(0.03, 1.2, 0), Vector3(-0.5, 1.9, -0.12), 0.06, bark, 0.03)
	seg(r, Vector3(0.05, 1.3, 0), Vector3(0.0, 2.15, 0.3), 0.055, bark, 0.025)
	for i in 40:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.85), rng.randf_range(-1, 1)).normalized()
		var c := Vector3(0, 2.0, 0) + Vector3(d.x * 0.9, d.y * 0.62, d.z * 0.85) * rng.randf_range(0.5, 1.0)
		var rad := rng.randf_range(0.2, 0.32)
		var shade := clampf(0.5 + d.y * 0.4, 0.0, 1.0)
		var g := m("tr_l%d" % int(shade * 4.0), Color(0.12, 0.26, 0.09).lerp(Color(0.32, 0.47, 0.18), float(int(shade * 4.0)) / 4.0), 0.8, 0.0, "leaf")
		ell(r, c, Vector3(rad, rad * 0.8, rad), g, Vector3(0, rng.randf() * TAU, rng.randf() * 0.5))
	return r


func car(_ph: float) -> Node3D:
	## A burnt-out hatchback, nose to +Z: blistered paint, rust, no glass.
	var r := Node3D.new()
	var paint := m("ca_paint", Color(0.42, 0.2, 0.15), 0.75, 0.3, "paint")
	var rust := m("ca_rust", Color(0.32, 0.17, 0.09), 0.95, 0.1, "earth")
	var dark := m("ca_dark", Color(0.05, 0.05, 0.05), 0.8, 0.1, "rubber")
	var chrome := m("ca_chrome", Color(0.5, 0.5, 0.5), 0.4, 0.8, "metal")
	box(r, Vector3(0, 0.3, 0), Vector3(0.78, 0.26, 1.62), paint)
	box(r, Vector3(0, 0.3, 0.6), Vector3(0.76, 0.2, 0.4), rust)
	box(r, Vector3(0, 0.56, -0.1), Vector3(0.7, 0.26, 0.8), paint)
	box(r, Vector3(0, 0.56, -0.1), Vector3(0.66, 0.2, 0.82), dark)        # empty window holes
	for x in [-0.33, 0.33]:
		box(r, Vector3(x, 0.56, -0.1), Vector3(0.04, 0.26, 0.04), paint)
	box(r, Vector3(0, 0.7, -0.1), Vector3(0.7, 0.04, 0.78), rust)
	for zx in [[0.4, 0.55], [-0.4, 0.55], [0.4, -0.55], [-0.4, -0.55]]:
		cyl(r, Vector3(zx[0], 0.15, zx[1]), 0.15, 0.12, dark, Vector3(0, 0, PI * 0.5))
		cyl(r, Vector3(zx[0] * 1.03, 0.15, zx[1]), 0.07, 0.13, chrome, Vector3(0, 0, PI * 0.5))
	box(r, Vector3(0, 0.22, 0.82), Vector3(0.74, 0.08, 0.04), chrome)
	box(r, Vector3(0, 0.22, -0.82), Vector3(0.74, 0.08, 0.04), chrome)
	return r


func barrels(_ph: float) -> Node3D:
	var r := Node3D.new()
	var cols := [Color(0.55, 0.22, 0.1), Color(0.18, 0.3, 0.42), Color(0.5, 0.4, 0.12)]
	var ps := [Vector3(-0.13, 0, 0.05), Vector3(0.13, 0, -0.06), Vector3(0.03, 0, 0.2)]
	for i in 3:
		var mat := m("bl_%d" % i, cols[i], 0.6, 0.4, "paint")
		var rim := m("bl_rim", Color(0.3, 0.3, 0.3), 0.5, 0.7, "metal")
		var h := 0.42 if i < 2 else 0.3
		cyl(r, ps[i] + Vector3(0, h * 0.5, 0), 0.12, h, mat)
		for y in [0.08, h * 0.5, h - 0.06]:
			cyl(r, ps[i] + Vector3(0, y, 0), 0.125, 0.02, rim)
	return r


func scrap_pile(_ph: float) -> Node3D:
	var r := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var mats := [m("sc_a", Color(0.55, 0.55, 0.58), 0.4, 0.8, "metal"), m("sc_b", Color(0.42, 0.24, 0.12), 0.9, 0.3, "earth"), m("sc_c", Color(0.3, 0.32, 0.35), 0.5, 0.7, "metal")]
	for i in 10:
		var a := rng.randf() * TAU
		box(r, Vector3(cos(a) * rng.randf() * 0.18, 0.04 + rng.randf() * 0.12, sin(a) * rng.randf() * 0.18), Vector3(rng.randf_range(0.08, 0.24), 0.02, rng.randf_range(0.04, 0.1)), mats[i % 3], Vector3(rng.randf() * 0.6, a, rng.randf() * 0.6))
	seg(r, Vector3(-0.2, 0.05, 0.0), Vector3(0.15, 0.25, 0.05), 0.015, mats[0])
	cyl(r, Vector3(0.1, 0.06, -0.12), 0.05, 0.12, mats[2], Vector3(0, 0, PI * 0.5))
	return r


func circuit_bundle(_ph: float) -> Node3D:
	var r := Node3D.new()
	var board := m("cb_board", Color(0.08, 0.38, 0.16), 0.5, 0.1, "paint")
	var chip := m("cb_chip", Color(0.08, 0.08, 0.08), 0.4, 0.3, "metal")
	var gold := m("cb_gold", Color(0.85, 0.7, 0.3), 0.3, 0.9, "metal")
	for k in 3:
		var y := 0.04 + k * 0.05
		box(r, Vector3(0, y, 0), Vector3(0.34, 0.015, 0.24), board, Vector3(0, k * 0.4, 0))
		box(r, Vector3(0.04, y + 0.015, 0.02), Vector3(0.08, 0.012, 0.07), chip, Vector3(0, k * 0.4, 0))
		box(r, Vector3(-0.1, y + 0.012, -0.06), Vector3(0.03, 0.01, 0.03), gold, Vector3(0, k * 0.4, 0))
	return r


func biomass_jar(ph: float) -> Node3D:
	var r := Node3D.new()
	cyl(r, Vector3(0, 0.2, 0), 0.12, 0.3, m("bj_glow", Color(0.45, 1.0, 0.3).lerp(Color(0.7, 1.0, 0.5), ph), 0.15, 0.0, "glow"))
	var metal := m("bj_cap", Color(0.45, 0.47, 0.5), 0.35, 0.85, "metal")
	cyl(r, Vector3(0, 0.38, 0), 0.13, 0.06, metal)
	cyl(r, Vector3(0, 0.03, 0), 0.13, 0.06, metal)
	for a in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
		box(r, Vector3(cos(a) * 0.125, 0.2, sin(a) * 0.125), Vector3(0.02, 0.32, 0.02), metal, Vector3(0, -a, 0))
	return r
