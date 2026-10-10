extends Node
## Baker (autoload): builds real 3D models with Godot's own renderer and
## photographs them into sprites, so people and guns look solid and real
## (proper light, shadow and materials) while the world keeps its fast
## fake-3D engine.
##
## - People (survivors, the harvest crew) are posed by code on a simple
##   skeleton and shot from 8 directions, several animation frames each.
## - First-person views (the pilot's carbine at the hip and aimed down the
##   sight, Brigid's autocannon arms) are shot through a camera with the
##   game's field of view, with recoil frames.
## Everything is saved to the phone (user://bake_*) so it's built once.

signal finished
signal progress(fraction: float, label: String)

const BAKE_VERSION := 8
const Models3D = preload("res://scripts/models3d.gd")
const DIRS := 8
const GAME_HFOV := 66.8        ## degrees: matches the battle view (2 * atan(0.66))

var done := false
var busy := false
var sprites := {}              ## kind -> {"L": float, "dirs": [dir][frame] Texture2D}
var fp := {}                   ## first-person: name -> {"tex": Texture2D, "pos": Vector2, "muzzle": Vector2}
var _vp: SubViewport
var _root: Node3D
var _cam: Camera3D
var _light: DirectionalLight3D
var _mats := {}
var _noise_tex := {}


func dir_path() -> String:
	return "user://bake_v%d" % BAKE_VERSION


func bake() -> void:
	## Loads the cached sprites, or builds them (a few seconds, once).
	if done or busy:
		if busy:
			await finished
		return
	busy = true
	if not _load_cache():
		await _bake_all()
		_save_cache()
	busy = false
	done = true
	finished.emit()


# =============================================================================
# Scene setup
# =============================================================================

func _setup(size: Vector2i, ortho: bool) -> void:
	if _vp:
		_vp.queue_free()
	_vp = SubViewport.new()
	_vp.size = size
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.75)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	_light = DirectionalLight3D.new()
	_light.light_energy = 1.35
	_light.light_color = Color(1.0, 0.96, 0.9)
	_light.shadow_enabled = true
	_light.shadow_bias = 0.03
	_vp.add_child(_light)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.3
	fill.light_color = Color(0.7, 0.8, 1.0)
	fill.rotation = Vector3(-0.3, PI * 0.8, 0)
	_vp.add_child(fill)
	_cam = Camera3D.new()
	if ortho:
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	else:
		_cam.keep_aspect = Camera3D.KEEP_WIDTH
		_cam.fov = GAME_HFOV
		_cam.near = 0.01
	_vp.add_child(_cam)
	_root = Node3D.new()
	_vp.add_child(_root)


func _shoot() -> Image:
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _clear_root() -> void:
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()


# =============================================================================
# Materials and parts
# =============================================================================

func _noise(nm: String, freq: float, seed_v: int) -> ImageTexture:
	if _noise_tex.has(nm):
		return _noise_tex[nm]
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.fractal_octaves = 3
	var img := n.get_seamless_image(64, 64)
	img.convert(Image.FORMAT_RGBA8)
	var t := ImageTexture.create_from_image(img)
	_noise_tex[nm] = t
	return t


func _normal(nm: String, freq: float, seed_v: int, strength: float) -> ImageTexture:
	var key := "n_" + nm
	if _noise_tex.has(key):
		return _noise_tex[key]
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.fractal_octaves = 3
	var img := n.get_seamless_image(128, 128)
	img.convert(Image.FORMAT_RGBA8)
	img.bump_map_to_normal_map(strength)
	var t := ImageTexture.create_from_image(img)
	_noise_tex[key] = t
	return t


func _mat(key: String, col: Color, rough := 0.8, metal := 0.0, kind := "cloth") -> StandardMaterial3D:
	var k := "%s_%s" % [key, col.to_html()]
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	match kind:
		"cloth":
			m.normal_enabled = true
			m.normal_texture = _normal("cloth", 0.25, 3, 3.0)
			m.normal_scale = 0.25
			m.uv1_scale = Vector3(2, 2, 2)
		"metal":
			m.normal_enabled = true
			m.normal_texture = _normal("metal", 0.08, 5, 1.5)
			m.normal_scale = 0.3
			m.metallic_specular = 0.7
		"skin":
			m.rim_enabled = true
			m.rim = 0.25
			m.rim_tint = 0.6
		"rubber":
			m.normal_enabled = true
			m.normal_texture = _normal("rubber", 0.4, 9, 2.0)
			m.normal_scale = 0.4
		"glass":
			m.metallic_specular = 1.0
		"glow":
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = 1.5
		"chitin":
			# Glossy insect shell with a pitted surface.
			m.normal_enabled = true
			m.normal_texture = _normal("chitin", 0.35, 21, 4.0)
			m.normal_scale = 0.5
			m.uv1_scale = Vector3(3, 3, 3)
			m.metallic_specular = 0.8
			m.rim_enabled = true
			m.rim = 0.3
			m.rim_tint = 0.4
		"flesh":
			# Wet, veined alien flesh: rim light fakes the glow through skin.
			m.normal_enabled = true
			m.normal_texture = _normal("flesh", 0.12, 23, 3.0)
			m.normal_scale = 0.7
			m.uv1_scale = Vector3(2, 2, 2)
			m.rim_enabled = true
			m.rim = 0.6
			m.rim_tint = 0.9
			m.metallic_specular = 0.7
		"bone":
			m.normal_enabled = true
			m.normal_texture = _normal("bone", 0.2, 25, 2.0)
			m.normal_scale = 0.4
		"earth":
			m.normal_enabled = true
			m.normal_texture = _normal("earth", 0.15, 27, 6.0)
			m.normal_scale = 1.0
			m.uv1_scale = Vector3(2, 2, 2)
		"leaf":
			m.normal_enabled = true
			m.normal_texture = _normal("leaf", 0.6, 29, 6.0)
			m.normal_scale = 1.0
			m.uv1_scale = Vector3(4, 4, 4)
		"bark":
			m.normal_enabled = true
			m.normal_texture = _normal("bark", 0.4, 31, 6.0)
			m.normal_scale = 1.0
			m.uv1_scale = Vector3(1, 4, 1)
		"paint":
			# Painted steel, scuffed.
			m.normal_enabled = true
			m.normal_texture = _normal("paint", 0.18, 33, 1.5)
			m.normal_scale = 0.35
			m.metallic_specular = 0.6
		"wood":
			m.normal_enabled = true
			m.normal_texture = _normal("wood", 0.3, 35, 3.0)
			m.normal_scale = 0.6
			m.uv1_scale = Vector3(1, 6, 1)
		"alpha":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.metallic_specular = 0.9
	_mats[k] = m
	return m


func _part(parent: Node3D, mesh: Mesh, mat: Material, at: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _caps(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.0 + 0.001)
	m.radial_segments = 12
	m.rings = 4
	return m


func _cyl(r_top: float, r_bot: float, h: float, seg := 14) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


func _box(sx: float, sy: float, sz: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(sx, sy, sz)
	return m


func _sph(r: float, hh := -1.0) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0 if hh < 0.0 else hh
	m.radial_segments = 16
	m.rings = 8
	return m


func _joint(parent: Node3D, at: Vector3) -> Node3D:
	var j := Node3D.new()
	j.position = at
	parent.add_child(j)
	return j


# =============================================================================
# People
# =============================================================================

const STYLES := {
	"civ_a": {"top": Color(0.22, 0.3, 0.22), "legs": Color(0.18, 0.22, 0.34), "skin": Color(0.86, 0.68, 0.55), "hair": Color(0.25, 0.17, 0.1), "shoes": Color(0.15, 0.12, 0.1)},
	"civ_b": {"top": Color(0.62, 0.16, 0.14), "legs": Color(0.32, 0.32, 0.34), "skin": Color(0.55, 0.38, 0.27), "hair": Color(0.08, 0.07, 0.07), "shoes": Color(0.85, 0.85, 0.82), "beanie": Color(0.15, 0.2, 0.3)},
	"civ_c": {"top": Color(0.6, 0.52, 0.38), "legs": Color(0.16, 0.16, 0.18), "skin": Color(0.9, 0.75, 0.66), "hair": Color(0.82, 0.8, 0.78), "shoes": Color(0.2, 0.14, 0.1), "coat": true},
	"hazmat": {"top": Color(0.93, 0.78, 0.12), "legs": Color(0.93, 0.78, 0.12), "skin": Color(0.93, 0.78, 0.12), "hair": Color(0.93, 0.78, 0.12), "shoes": Color(0.1, 0.1, 0.1), "suit": true},
}


func _build_person(style: String, prop := "") -> Dictionary:
	## A 1.8 m person with a simple skeleton: returns the root and joints.
	var st: Dictionary = STYLES[style]
	var suit: bool = st.get("suit", false)
	var top := _mat("top", st["top"], 0.55 if suit else 0.9, 0.0, "rubber" if suit else "cloth")
	var legs := _mat("legs", st["legs"], 0.55 if suit else 0.9, 0.0, "rubber" if suit else "cloth")
	var skin := _mat("skin", st["skin"], 0.6, 0.0, "skin")
	var hair := _mat("hair", st["hair"], 0.95, 0.0, "cloth")
	var shoes := _mat("shoes", st["shoes"], 0.7, 0.0, "rubber")
	var root := Node3D.new()
	var j := {}
	var hips := _joint(root, Vector3(0, 0.95, 0))
	j["hips"] = hips
	_part(hips, _box(0.32, 0.18, 0.2), legs, Vector3(0, -0.02, 0))
	var spine := _joint(hips, Vector3(0, 0.08, 0))
	j["spine"] = spine
	# Torso: chest and belly, a little tapered.
	_part(spine, _caps(0.17, 0.5), top, Vector3(0, 0.24, 0), Vector3.ZERO, Vector3(1.15, 1.0, 0.75))
	_part(spine, _box(0.36, 0.2, 0.2), top, Vector3(0, 0.36, 0))
	if st.get("coat", false):
		_part(spine, _cyl(0.2, 0.25, 0.55), top, Vector3(0, -0.12, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.75))
	if suit:
		# Air tank and pack on the back, hose to the mask.
		_part(spine, _box(0.3, 0.38, 0.12), _mat("pack", Color(0.2, 0.2, 0.2), 0.6, 0.2, "rubber"), Vector3(0, 0.28, -0.17))
		_part(spine, _cyl(0.07, 0.07, 0.42), _mat("tank", Color(0.75, 0.75, 0.78), 0.3, 0.8, "metal"), Vector3(0.08, 0.3, -0.27))
	var neck := _joint(spine, Vector3(0, 0.5, 0))
	j["neck"] = neck
	_part(neck, _cyl(0.055, 0.06, 0.1), skin, Vector3(0, 0.03, 0))
	var head := _joint(neck, Vector3(0, 0.1, 0))
	j["head"] = head
	if suit:
		# Hood with a wide dark visor and a respirator.
		_part(head, _sph(0.15, 0.32), top, Vector3(0, 0.09, -0.01))
		_part(head, _box(0.2, 0.11, 0.06), _mat("visor", Color(0.12, 0.2, 0.24), 0.08, 0.3, "glass"), Vector3(0, 0.12, 0.13), Vector3(-0.15, 0, 0))
		_part(head, _cyl(0.04, 0.05, 0.07), _mat("resp", Color(0.15, 0.15, 0.15), 0.6, 0.1, "rubber"), Vector3(0, 0.02, 0.15), Vector3(PI * 0.5, 0, 0))
	else:
		_part(head, _sph(0.105, 0.24), skin, Vector3(0, 0.1, 0))
		_part(head, _sph(0.022), skin, Vector3(0, 0.09, 0.105))                       # nose
		for sx in [-0.04, 0.04]:
			_part(head, _sph(0.014), _mat("eye", Color(0.08, 0.06, 0.05), 0.2), Vector3(sx, 0.125, 0.092))
			_part(head, _sph(0.022, 0.03), skin, Vector3(sx * 2.6, 0.1, 0.0))        # ears
		if st.has("beanie"):
			_part(head, _sph(0.112, 0.16), _mat("beanie", st["beanie"], 0.95), Vector3(0, 0.17, -0.005))
		else:
			_part(head, _sph(0.11, 0.18), hair, Vector3(0, 0.155, -0.02))
			_part(head, _box(0.2, 0.1, 0.06), hair, Vector3(0, 0.12, -0.08))
	for side in [-1.0, 1.0]:
		var s := "l" if side < 0 else "r"
		var sh := _joint(spine, Vector3(side * 0.21, 0.43, 0))
		j[s + "_sh"] = sh
		_part(sh, _caps(0.055, 0.32), top, Vector3(0, -0.15, 0))
		var el := _joint(sh, Vector3(0, -0.3, 0))
		j[s + "_el"] = el
		_part(el, _caps(0.047, 0.29), top if (suit or style == "civ_c" or style == "civ_b") else skin, Vector3(0, -0.13, 0))
		var hand := _joint(el, Vector3(0, -0.28, 0))
		j[s + "_hand"] = hand
		_part(hand, _box(0.07, 0.1, 0.035), _mat("glove", Color(0.12, 0.12, 0.12), 0.7, 0.0, "rubber") if suit else skin, Vector3(0, -0.04, 0))
		var hip := _joint(hips, Vector3(side * 0.1, -0.07, 0))
		j[s + "_hip"] = hip
		_part(hip, _caps(0.075, 0.44), legs, Vector3(0, -0.2, 0))
		var knee := _joint(hip, Vector3(0, -0.42, 0))
		j[s + "_knee"] = knee
		_part(knee, _caps(0.06, 0.42), legs, Vector3(0, -0.2, 0))
		var foot := _joint(knee, Vector3(0, -0.41, 0))
		j[s + "_foot"] = foot
		_part(foot, _box(0.1, 0.07, 0.25), shoes, Vector3(0, -0.02, 0.05))
	if prop == "jar":
		var jar := _joint(j["r_hand"], Vector3(-0.08, -0.08, 0.06))
		j["jar"] = jar
		_part(jar, _cyl(0.07, 0.07, 0.16), _mat("jar", Color(0.45, 1.0, 0.3), 0.2, 0.0, "glow"), Vector3.ZERO)
		_part(jar, _cyl(0.075, 0.075, 0.03), _mat("cap", Color(0.5, 0.52, 0.55), 0.35, 0.8, "metal"), Vector3(0, 0.09, 0))
	elif prop == "knife":
		_part(j["r_hand"], _box(0.012, 0.012, 0.16), _mat("blade", Color(0.85, 0.87, 0.9), 0.15, 1.0, "metal"), Vector3(0, -0.08, 0.07))
		var jar2 := _joint(root, Vector3(-0.35, 0.08, 0.15))
		_part(jar2, _cyl(0.07, 0.07, 0.16), _mat("jar", Color(0.45, 1.0, 0.3), 0.2, 0.0, "glow"), Vector3.ZERO)
	return {"root": root, "j": j}


func _pose(j: Dictionary, anim: String, ph: float) -> void:
	## Puts the skeleton in a pose. ph is 0..1 through the cycle.
	var s := sin(ph * TAU)
	var c := cos(ph * TAU)
	for k in j:
		if j[k] is Node3D and k != "jar":
			j[k].rotation = Vector3.ZERO
	j["hips"].position = Vector3(0, 0.95, 0)
	match anim:
		"idle":
			j["spine"].rotation.x = 0.03 + s * 0.015
			j["l_sh"].rotation.z = -0.08
			j["r_sh"].rotation.z = 0.08
			j["head"].rotation.y = s * 0.25
		"wave":
			# Hiding and waving you over: right arm up, waving.
			j["spine"].rotation.x = 0.05
			j["r_sh"].rotation = Vector3(0.0, 0.0, 2.6)
			j["r_el"].rotation = Vector3(0.0, 0.0, 0.5 + s * 0.45)
			j["l_sh"].rotation.z = -0.15
			j["head"].rotation.x = -0.1
		"walk", "carry":
			var stride := 0.5
			j["hips"].position.y = 0.95 - absf(c) * 0.03
			j["l_hip"].rotation.x = s * stride
			j["r_hip"].rotation.x = -s * stride
			j["l_knee"].rotation.x = maxf(0.0, s) * 0.9 + 0.08
			j["r_knee"].rotation.x = maxf(0.0, -s) * 0.9 + 0.08
			j["l_foot"].rotation.x = maxf(0.0, s) * 0.3
			j["r_foot"].rotation.x = maxf(0.0, -s) * 0.3
			j["spine"].rotation.y = s * 0.08
			j["spine"].rotation.x = 0.06
			if anim == "walk":
				j["l_sh"].rotation.x = -s * 0.45
				j["r_sh"].rotation.x = s * 0.45
				j["l_el"].rotation.x = -0.3
				j["r_el"].rotation.x = -0.3
			else:
				# Both arms forward cradling the jar.
				j["l_sh"].rotation = Vector3(-0.85, 0.0, 0.3)
				j["r_sh"].rotation = Vector3(-0.85, 0.0, -0.3)
				j["l_el"].rotation.x = -0.9
				j["r_el"].rotation.x = -0.9
		"cut":
			# Kneeling over a carcass, sawing with the right hand.
			j["hips"].position.y = 0.56
			j["l_hip"].rotation.x = -1.45
			j["l_knee"].rotation.x = 1.45
			j["r_hip"].rotation.x = 0.0
			j["r_knee"].rotation.x = 1.55
			j["r_foot"].rotation.x = -0.6
			j["spine"].rotation.x = 0.55
			j["head"].rotation.x = 0.4
			j["l_sh"].rotation = Vector3(-1.1, 0.0, 0.25)
			j["l_el"].rotation.x = -0.4
			j["r_sh"].rotation = Vector3(-1.0 + s * 0.25, 0.0, -0.2)
			j["r_el"].rotation.x = -0.6 - c * 0.2


func _bake_people() -> void:
	var L := 1.05                # world size of the sprite square
	var S := 128
	var jobs := [
		["survivor_a", "civ_a", "", "wave", 4], ["survivor_a_walk", "civ_a", "", "walk", 8],
		["survivor_b", "civ_b", "", "wave", 4], ["survivor_b_walk", "civ_b", "", "walk", 8],
		["survivor_c", "civ_c", "", "wave", 4], ["survivor_c_walk", "civ_c", "", "walk", 8],
		["survivor_sit", "civ_a", "", "idle", 2],
		["hazmat_walk", "hazmat", "", "walk", 8], ["hazmat_carry", "hazmat", "jar", "carry", 8],
		["hazmat_cut", "hazmat", "knife", "cut", 4],
	]
	for n in jobs.size():
		var job: Array = jobs[n]
		progress.emit(float(n) / jobs.size() * 0.35, "People")
		var frames: int = job[4]
		_setup(Vector2i(S * frames, S), true)
		_cam.size = L
		_cam.position = Vector3(0, L * 0.5 - 0.02, 6.0)
		var models: Array = []
		for f in frames:
			var m := _build_person(job[1], job[2])
			# The model is 1.8 m tall; the game's people are 0.9 units.
			m["root"].scale = Vector3.ONE * 0.5
			m["root"].position = Vector3((f - (frames - 1) * 0.5) * L, 0, 0)
			_root.add_child(m["root"])
			_pose(m["j"], job[3], float(f) / frames)
			models.append(m)
		var dirs: Array = []
		for d in DIRS:
			var yaw := TAU * d / DIRS
			for m in models:
				m["root"].rotation.y = yaw
			# The sun is fixed in the world, so it turns with the model.
			_light.rotation = Vector3(-0.85, yaw + 0.7, 0)
			var img: Image = await _shoot()
			var row: Array = []
			for f in frames:
				row.append(ImageTexture.create_from_image(img.get_region(Rect2i(f * S, 0, S, S))))
			dirs.append(row)
		sprites[job[0]] = {"L": L, "dirs": dirs}
	_clear_root()


# =============================================================================
# First-person weapons
# =============================================================================

func _build_carbine(hazmat: bool) -> Dictionary:
	## A short assault carbine with a red-dot sight, held in two gloved hands.
	## Barrel points down -Z. Returns root, the muzzle node and sight height.
	var poly := _mat("poly", Color(0.09, 0.09, 0.1), 0.65, 0.0, "rubber")
	var steel := _mat("steel", Color(0.16, 0.17, 0.18), 0.35, 0.85, "metal")
	var tan_m := _mat("tan", Color(0.42, 0.37, 0.28), 0.7, 0.0, "rubber")
	var glove := _mat("glove", Color(0.93, 0.78, 0.12) if hazmat else Color(0.32, 0.25, 0.18), 0.7, 0.0, "rubber")
	var sleeve := _mat("sleeve", Color(0.93, 0.78, 0.12) if hazmat else Color(0.24, 0.27, 0.2), 0.85, 0.0, "cloth")
	var g := Node3D.new()
	# Receiver and handguard
	_part(g, _box(0.05, 0.07, 0.26), steel, Vector3(0, 0, 0))
	_part(g, _box(0.055, 0.03, 0.27), steel, Vector3(0, 0.048, 0))                    # top rail
	for i in 9:
		_part(g, _box(0.05, 0.004, 0.01), poly, Vector3(0, 0.064, -0.11 + i * 0.026))
	_part(g, _box(0.056, 0.06, 0.26), tan_m, Vector3(0, 0.005, -0.26))                # handguard
	for i in 5:
		_part(g, _box(0.06, 0.018, 0.03), poly, Vector3(0, 0.01, -0.17 - i * 0.045))  # vents
	_part(g, _cyl(0.011, 0.011, 0.2), steel, Vector3(0, 0.01, -0.48), Vector3(PI * 0.5, 0, 0))
	var brake := _part(g, _cyl(0.017, 0.017, 0.06, 10), steel, Vector3(0, 0.01, -0.6), Vector3(PI * 0.5, 0, 0))
	var muzzle := _joint(g, Vector3(0, 0.01, -0.64))
	# Magazine (slightly curved), pistol grip, stock
	_part(g, _box(0.032, 0.14, 0.07), poly, Vector3(0, -0.1, -0.02), Vector3(0.18, 0, 0))
	_part(g, _box(0.032, 0.08, 0.065), poly, Vector3(0, -0.2, 0.0), Vector3(0.32, 0, 0))
	_part(g, _box(0.035, 0.11, 0.045), poly, Vector3(0, -0.075, 0.1), Vector3(-0.3, 0, 0))
	var stock := Node3D.new()
	g.add_child(stock)
	_part(stock, _box(0.04, 0.03, 0.22), steel, Vector3(0, -0.005, 0.24))
	_part(stock, _box(0.045, 0.1, 0.09), poly, Vector3(0, -0.03, 0.36))
	# Magwell and trigger guard
	_part(g, _box(0.045, 0.04, 0.08), steel, Vector3(0, -0.05, -0.02))
	_part(g, _box(0.008, 0.008, 0.07), steel, Vector3(0, -0.085, 0.06))
	_part(g, _box(0.008, 0.02, 0.04), steel, Vector3(0.03, 0.015, 0.02))              # charging handle
	_part(g, _box(0.004, 0.025, 0.07), poly, Vector3(0.027, 0.0, -0.03))  # ejection port
	# Red-dot sight: tube, lens, mount
	var sight_y := 0.105
	_part(g, _box(0.03, 0.025, 0.05), steel, Vector3(0, 0.075, 0.02))
	var optic := _mat("optic", Color(0.07, 0.07, 0.08), 0.4, 0.6, "metal")
	for zz in [0.055, -0.015]:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.019
		ring.outer_radius = 0.026
		ring.rings = 20
		ring.ring_segments = 8
		_part(g, ring, optic, Vector3(0, sight_y, zz), Vector3(PI * 0.5, 0, 0))
	_part(g, _box(0.012, 0.006, 0.075), optic, Vector3(0, sight_y + 0.024, 0.02))
	_part(g, _box(0.006, 0.03, 0.06), optic, Vector3(0.024, sight_y - 0.008, 0.02))
	_part(g, _box(0.006, 0.03, 0.06), optic, Vector3(-0.024, sight_y - 0.008, 0.02))
	# Right hand on the grip, left hand wrapped round the handguard.
	_part(g, _box(0.06, 0.09, 0.08), glove, Vector3(0.012, -0.085, 0.11), Vector3(-0.3, 0, 0))
	for i in 3:
		_part(g, _caps(0.012, 0.065), glove, Vector3(-0.015, -0.06 - i * 0.022, 0.085), Vector3(0, 0, PI * 0.5))
	_part(g, _caps(0.013, 0.06), glove, Vector3(0.032, -0.02, 0.07), Vector3(-1.2, 0, 0))   # thumb
	_part(g, _caps(0.045, 0.34), sleeve, Vector3(0.1, -0.16, 0.27), Vector3(-1.0, 0.0, 0.55))
	_part(g, _box(0.07, 0.05, 0.1), glove, Vector3(-0.012, -0.04, -0.27))
	for i in 4:
		_part(g, _caps(0.012, 0.075), glove, Vector3(-0.005, 0.03, -0.23 - i * 0.024), Vector3(0, 0, PI * 0.5 + 0.15))
	_part(g, _caps(0.048, 0.42), sleeve, Vector3(-0.1, -0.2, -0.12), Vector3(-0.9, 0.0, -0.8))
	return {"root": g, "muzzle": muzzle, "sight_y": sight_y, "stock": stock}


func _build_arm() -> Dictionary:
	## Brigid's right arm: armoured forearm housing, hydraulics, ammo feed
	## and a six-barrel rotary autocannon in a vented shroud. Points to -Z.
	var armour := _mat("armour", Color(0.15, 0.17, 0.16), 0.75, 0.3, "paint")
	var dark := _mat("dark", Color(0.12, 0.12, 0.13), 0.45, 0.7, "metal")
	var steel := _mat("steel", Color(0.5, 0.51, 0.52), 0.3, 0.9, "metal")
	var hazard := _mat("hazard", Color(0.62, 0.48, 0.1), 0.75, 0.1, "metal")
	var hose := _mat("hose", Color(0.08, 0.08, 0.08), 0.8, 0.0, "rubber")
	var a := Node3D.new()
	_part(a, _box(0.5, 0.42, 1.5), armour, Vector3(0, 0, 0.3))
	_part(a, _box(0.44, 0.08, 1.4), armour, Vector3(0, 0.24, 0.3))
	_part(a, _box(0.52, 0.1, 0.06), dark, Vector3(0, 0.0, -0.2))                   # panel seams
	_part(a, _box(0.52, 0.1, 0.06), dark, Vector3(0, 0.0, 0.5))
	# Hazard chevrons painted on the inner side
	for i in 5:
		_part(a, _box(0.012, 0.06, 0.34), hazard if i % 2 == 0 else dark, Vector3(-0.255, 0.12 - i * 0.06, -0.3), Vector3(0.6, 0, 0))
	for i in 3:
		_part(a, _box(0.52, 0.02, 0.012), dark, Vector3(0, 0.15 - i * 0.04, 0.9))
	# Hydraulic pistons underneath
	for sx in [-0.14, 0.14]:
		_part(a, _cyl(0.04, 0.04, 0.9), steel, Vector3(sx, -0.27, 0.45), Vector3(PI * 0.5, 0, 0))
		_part(a, _cyl(0.06, 0.06, 0.5), dark, Vector3(sx, -0.27, 0.95), Vector3(PI * 0.5, 0, 0))
	# Ammo feed
	_part(a, _box(0.18, 0.2, 0.6), dark, Vector3(0.3, 0.08, 0.5))
	_part(a, _cyl(0.05, 0.05, 0.7), hose, Vector3(0.27, 0.2, 0.0), Vector3(PI * 0.5, 0, 0.2))
	# Shroud and rotary barrels
	_part(a, _cyl(0.2, 0.22, 0.6, 20), dark, Vector3(0, 0.02, -0.7), Vector3(PI * 0.5, 0, 0))
	for i in 8:
		_part(a, _box(0.03, 0.42, 0.08), steel, Vector3(0, 0.02, -0.52 - i * 0.06), Vector3(0, 0, i * 0.4))
	for i in 6:
		var ang := TAU * i / 6.0
		_part(a, _cyl(0.035, 0.035, 0.9, 10), steel, Vector3(cos(ang) * 0.09, 0.02 + sin(ang) * 0.09, -1.15), Vector3(PI * 0.5, 0, 0))
	_part(a, _cyl(0.17, 0.17, 0.06, 20), dark, Vector3(0, 0.02, -1.55), Vector3(PI * 0.5, 0, 0))
	var muzzle := _joint(a, Vector3(0, 0.02, -1.62))
	return {"root": a, "muzzle": muzzle}


func _fp_shot(key: String, model: Node3D, muzzle: Node3D) -> void:
	var img: Image = await _shoot()
	var used := img.get_used_rect()
	if used.size.x <= 0:
		used = Rect2i(0, 0, 1, 1)
	var crop := img.get_region(used)
	var m := _cam.unproject_position(muzzle.global_position)
	fp[key] = {"tex": ImageTexture.create_from_image(crop), "pos": Vector2(used.position), "muzzle": m, "img": crop}


func _bake_first_person() -> void:
	_setup(Vector2i(1280, 720), false)
	_cam.position = Vector3.ZERO
	_light.rotation = Vector3(-0.9, 0.4, 0)
	_light.shadow_enabled = true
	for hz in [false, true]:
		progress.emit(0.75 + (0.1 if hz else 0.0), "Weapons")
		var c := _build_carbine(hz)
		var g: Node3D = c["root"]
		_root.add_child(g)
		var suffix := "_hz" if hz else ""
		# Hip: low on the right, angled in.
		g.position = Vector3(0.12, -0.17, -0.48)
		g.rotation = Vector3(0.03, 0.12, 0.04)
		await _fp_shot("carbine_hip" + suffix, g, c["muzzle"])
		g.position += Vector3(0.0, 0.015, 0.05)
		g.rotation.x += 0.06
		await _fp_shot("carbine_hip_rec" + suffix, g, c["muzzle"])
		# Aimed: the sight's line is the camera's line.
		g.position = Vector3(0.0, -c["sight_y"], -0.3)
		g.rotation = Vector3.ZERO
		c["stock"].visible = false     # it's against your shoulder, out of view
		await _fp_shot("carbine_ads" + suffix, g, c["muzzle"])
		g.position += Vector3(0.0, 0.006, 0.04)
		g.rotation.x += 0.03
		await _fp_shot("carbine_ads_rec" + suffix, g, c["muzzle"])
		_clear_root()
	progress.emit(0.95, "Brigid's arms")
	var arm := _build_arm()
	var a: Node3D = arm["root"]
	_root.add_child(a)
	_light.rotation = Vector3(-0.8, -0.5, 0)
	a.position = Vector3(0.92, -0.5, -2.0)
	a.rotation = Vector3(0.08, 0.16, -0.05)
	await _fp_shot("arm_r", a, arm["muzzle"])
	a.position += Vector3(0.0, 0.0, 0.18)
	await _fp_shot("arm_r_rec", a, arm["muzzle"])
	_clear_root()
	# The left arm is the mirror image.
	for k in ["arm_r", "arm_r_rec"]:
		var src: Dictionary = fp[k]
		var img: Image = (src["img"] as Image).duplicate()
		img.flip_x()
		var w := 1280.0
		fp[k.replace("_r", "_l")] = {"tex": ImageTexture.create_from_image(img), "img": img,
			"pos": Vector2(w - src["pos"].x - img.get_width(), src["pos"].y),
			"muzzle": Vector2(w - src["muzzle"].x, src["muzzle"].y)}


func _bake_set(key: String, L: float, S: int, frames: int, builder: Callable, roll := 0.0) -> void:
	## Photographs one model from 8 directions, `frames` animation steps in a
	## row per shot. A non-zero roll lays the model down as a carcass.
	_setup(Vector2i(S * frames, S), true)
	_cam.size = L
	_cam.position = Vector3(0, L * 0.5 - 0.01, 8.0)
	_cam.far = 20.0
	var holders: Array = []
	for f in frames:
		var holder := Node3D.new()
		holder.position = Vector3((f - (frames - 1) * 0.5) * L, 0, 0)
		_root.add_child(holder)
		var model: Node3D = builder.call(float(f) / frames)
		holder.add_child(model)
		if roll != 0.0:
			_lay_down(holder, model, roll)
		holders.append(holder)
	var dirs: Array = []
	for d in DIRS:
		var yaw := TAU * d / DIRS
		for hd in holders:
			hd.rotation.y = yaw
		_light.rotation = Vector3(-0.85, yaw + 0.7, 0)
		var img: Image = await _shoot()
		var row: Array = []
		for f in frames:
			row.append(ImageTexture.create_from_image(img.get_region(Rect2i(f * S, 0, S, S))))
		dirs.append(row)
	sprites[key] = {"L": L, "dirs": dirs}
	_clear_root()


func _lay_down(holder: Node3D, model: Node3D, roll: float) -> void:
	## Rolls a model over and rests it on the ground, centred.
	model.rotation = Vector3(0, 0, roll)
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	var inv := holder.global_transform.affine_inverse()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var xf: Transform3D = inv * (mi as MeshInstance3D).global_transform
		var ab: AABB = (mi as MeshInstance3D).get_aabb()
		for i in 8:
			var p := xf * ab.get_endpoint(i)
			lo = lo.min(p)
			hi = hi.max(p)
	model.position = Vector3(-(lo.x + hi.x) * 0.5, -lo.y - 0.02, -(lo.z + hi.z) * 0.5)


func _bake_world_models() -> void:
	## 1.5: aliens, carcasses, Brigid, the Chest and every prop.
	var md = Models3D.new(self)
	var jobs := [
		["crawler", 1.4, 112, 6, func(ph): return md.crawler(ph), 0.0],
		["spitter", 1.25, 112, 6, func(ph): return md.spitter(ph), 0.0],
		["brute", 1.95, 144, 6, func(ph): return md.brute(ph), 0.0],
		["flyer", 1.5, 112, 4, func(ph): return md.flyer(ph), 0.0],
		["burrower", 2.0, 144, 6, func(ph): return md.burrower(ph), 0.0],
		["mound", 1.3, 80, 2, func(ph): return md.mound(ph), 0.0],
		["hive", 2.2, 144, 3, func(ph): return md.hive(ph, 1.0, false), 0.0],
		["mother", 3.9, 192, 3, func(ph): return md.hive(ph, 1.75, true), 0.0],
		["crawler_dead", 1.4, 112, 1, func(ph): return md.crawler(0.2, true), PI],
		["spitter_dead", 1.25, 112, 1, func(ph): return md.spitter(0.0, true), PI * 0.5],
		["brute_dead", 1.95, 144, 1, func(ph): return md.brute(0.25, true), PI * 0.5],
		["flyer_dead", 1.5, 112, 1, func(ph): return md.flyer(0.0, true), PI],
		["burrower_dead", 2.0, 144, 1, func(ph): return md.burrower(0.25, true), PI],
		["hive_dead", 2.2, 144, 1, func(ph): return md.hive(0.0, 1.0, false, true), 0.0],
		["mother_dead", 3.9, 192, 1, func(ph): return md.hive(0.0, 1.75, true, true), 0.0],
		["mech", 2.3, 160, 1, func(ph): return md.mech(ph), 0.0],
		["chest", 2.2, 128, 4, func(ph): return md.chest(ph, true), 0.0],
		["chest_nosuit", 2.2, 128, 4, func(ph): return md.chest(ph, false), 0.0],
		["cache", 0.65, 64, 2, func(ph): return md.crate(ph), 0.0],
		["item_fuel", 0.65, 64, 1, func(ph): return md.canister(ph), 0.0],
		["item_data", 0.65, 64, 2, func(ph): return md.datacore(ph), 0.0],
		["beacon_off", 2.6, 128, 1, func(ph): return md.beacon(false), 0.0],
		["beacon_on", 2.6, 128, 1, func(ph): return md.beacon(true), 0.0],
		["pine", 3.2, 160, 1, func(ph): return md.pine(ph), 0.0],
		["tree", 3.0, 160, 1, func(ph): return md.tree(ph), 0.0],
		["car", 1.8, 112, 1, func(ph): return md.car(ph), 0.0],
		["barrel", 0.7, 64, 1, func(ph): return md.barrels(ph), 0.0],
		["pile_scrap", 0.8, 64, 1, func(ph): return md.scrap_pile(ph), 0.0],
		["pile_circuits", 0.7, 64, 1, func(ph): return md.circuit_bundle(ph), 0.0],
		["jar_biomass", 0.6, 64, 2, func(ph): return md.biomass_jar(ph), 0.0],
	]
	for n in jobs.size():
		var j: Array = jobs[n]
		progress.emit(0.35 + 0.5 * float(n) / jobs.size(), "Creatures and props")
		await _bake_set(j[0], j[1], j[2], j[3], j[4], j[5])
	sprites["item_supply"] = sprites["cache"]


func _bake_all() -> void:
	var t0 := Time.get_ticks_msec()
	await _bake_people()
	await _bake_world_models()
	await _bake_first_person()
	if _vp:
		_vp.queue_free()
		_vp = null
	progress.emit(1.0, "Done")
	print("baked sprites in %d ms" % (Time.get_ticks_msec() - t0))


# =============================================================================
# Cache on disk
# =============================================================================

func _save_cache() -> void:
	var path := dir_path()
	DirAccess.make_dir_recursive_absolute(path)
	var meta := {"sprites": {}, "fp": {}}
	for k in sprites:
		var e: Dictionary = sprites[k]
		var dirs: Array = e["dirs"]
		meta["sprites"][k] = {"L": e["L"], "frames": (dirs[0] as Array).size()}
		for d in dirs.size():
			for f in (dirs[d] as Array).size():
				(dirs[d][f] as Texture2D).get_image().save_png("%s/%s_%d_%d.png" % [path, k, d, f])
	for k in fp:
		var e2: Dictionary = fp[k]
		(e2["img"] as Image).save_png("%s/fp_%s.png" % [path, k])
		meta["fp"][k] = {"pos": [e2["pos"].x, e2["pos"].y], "muzzle": [e2["muzzle"].x, e2["muzzle"].y]}
	var f := FileAccess.open(path + "/meta.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(meta))


func _remove_old_caches() -> void:
	var d := DirAccess.open("user://")
	if d == null:
		return
	for sub in d.get_directories():
		if sub.begins_with("bake_v") and sub != dir_path().get_file():
			var old := DirAccess.open("user://" + sub)
			if old:
				for f in old.get_files():
					old.remove(f)
			d.remove(sub)


func _load_cache() -> bool:
	_remove_old_caches()
	var path := dir_path()
	if not FileAccess.file_exists(path + "/meta.json"):
		return false
	var meta = JSON.parse_string(FileAccess.get_file_as_string(path + "/meta.json"))
	if not (meta is Dictionary):
		return false
	for k in meta["sprites"]:
		var e: Dictionary = meta["sprites"][k]
		var dirs: Array = []
		for d in DIRS:
			var row: Array = []
			for f in int(e["frames"]):
				var img := Image.load_from_file("%s/%s_%d_%d.png" % [path, k, d, f])
				if img == null:
					return false
				row.append(ImageTexture.create_from_image(img))
			dirs.append(row)
		sprites[k] = {"L": float(e["L"]), "dirs": dirs}
	for k in meta["fp"]:
		var e3: Dictionary = meta["fp"][k]
		var img2 := Image.load_from_file("%s/fp_%s.png" % [path, k])
		if img2 == null:
			return false
		fp[k] = {"tex": ImageTexture.create_from_image(img2), "img": img2,
			"pos": Vector2(e3["pos"][0], e3["pos"][1]), "muzzle": Vector2(e3["muzzle"][0], e3["muzzle"][1])}
	return true
