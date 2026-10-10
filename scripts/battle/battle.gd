extends Node2D
## Battle scene. The world is a 2D grid where every cell has a height
## (see level_map.gd): ground, hills, craters, platforms, stairs, low walls
## and tall ruins. The cockpit view fakes 3D by marching one ray per screen
## column through the grid, drawing the front faces and tops of cells from
## near to far (a "2.5D" heightfield renderer, like Doom or Comanche).
## Aliens, props and effects are flat sprites scaled by distance and clipped
## against whatever terrain is in front of them.

const LevelMap = preload("res://scripts/battle/level_map.gd")
const AlienArt = preload("res://scripts/battle/alien_art.gd")
const MechDiagram = preload("res://scripts/mech_diagram.gd")

# --- View ---------------------------------------------------------------------
const COLUMNS := 200          ## rays per frame; lower = faster on old phones
const FOV_PLANE := 0.66       ## ~66 degree field of view
const EYE := 1.25             ## cockpit eye height above the mech's feet
const MAX_VIEW := 22.0
const FOG_DIST := 15.0
const FOG := Color(0.24, 0.12, 0.13)
const FACE_COLORS := {
	LevelMap.EMPTY: Color(0.38, 0.25, 0.2),      # dirt terraces and crater walls
	LevelMap.RUIN: Color(0.58, 0.52, 0.45),
	LevelMap.METAL: Color(0.42, 0.48, 0.56),
	LevelMap.ORGANIC: Color(0.55, 0.2, 0.42),
	LevelMap.PLATFORM: Color(0.5, 0.5, 0.53),
}
const GROUND_TOP := Color(0.27, 0.15, 0.13)
const PLATFORM_TOP := Color(0.36, 0.36, 0.39)

# --- Controls -----------------------------------------------------------------
const PLAYER_R := 0.3
const KEY_TURN_SPEED := 2.4
const LOOK_SENS := 0.0065
const PITCH_SENS := 0.9       ## screen pixels of look per pixel of finger drag
const PITCH_LIMIT := 0.7      ## max look up/down, as a fraction of screen height
const JOY_RADIUS := 90.0
const FIRE_R := 78.0
const ROCKET_R := 52.0

# --- Aliens -------------------------------------------------------------------
const ALIEN_TYPES := {
	"crawler": {"hp": 30.0, "speed": 2.4, "dmg": 6.0, "range": 0.9, "cd": 0.8, "w": 1.0, "h": 0.9, "r": 0.25},
	"spitter": {"hp": 45.0, "speed": 1.5, "dmg": 9.0, "range": 7.0, "cd": 2.2, "w": 0.85, "h": 1.15, "r": 0.25},
	"brute": {"hp": 170.0, "speed": 1.15, "dmg": 18.0, "range": 1.25, "cd": 1.5, "w": 1.6, "h": 1.8, "r": 0.4},
	"hive": {"hp": 300.0, "speed": 0.0, "dmg": 0.0, "range": 0.0, "cd": 5.0, "w": 2.0, "h": 1.7, "r": 0.5},
}

enum State { PLAYING, WON, LOST, RETREATED }

var state := State.PLAYING
var map: LevelMap
var tex := {}
var font: Font
var rng := RandomNumberGenerator.new()

var pos := Vector2()
var angle := 0.0
var floor_z := 0.0            ## height of the ground under the mech (smoothed)
var eye_z := EYE
var falling := false
var parts := {}
var aliens: Array = []
var props: Array = []
var projectiles: Array = []
var explosions: Array = []
var tracers: Array = []
var col_events: Array = []    ## per column: [depth, clip_y, depth, clip_y, ...]
var flow := PackedInt32Array()
var flow_timer := 0.0
var time := 0.0
var end_time := 0.0

var fire_cd := 0.0
var rocket_cd := 0.0
var next_gun := 0
var muzzle := [0.0, 0.0]
var recoil := [0.0, 0.0]
var shake := 0.0
var hit_flash := 0.0
var dmg_indicators: Array = []
var bob_t := 0.0
var bob_amount := 0.0
var alarm_cd := 0.0
var retreat_armed := 0.0
var msg := ""
var msg_t := 0.0
var locked_target = null
var smoke_timer := 0.0

var kills := 0
var brutes := 0
var hives_total := 0
var hives_destroyed := 0
var mission_no := 1

var move_touch := -1
var move_origin := Vector2()
var move_vec := Vector2()
var look_touch := -1
var look_last_x := 0.0
var look_last_y := 0.0
var pitch := 0.0              ## look up (+) / down (-), in screen pixels
var horizon_y := 360.0
var fire_touch := -1

var stars: Array = []
var ridge_far := PackedFloat32Array()
var ridge_near := PackedFloat32Array()
var cracks: Array = []


func _ready() -> void:
	font = ThemeDB.fallback_font
	mission_no = GameState.mission
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rng.seed = GameState.mission_seed() + 99
	tex = AlienArt.build_all()

	map = LevelMap.new()
	map.generate(GameState.mission_seed(), GameState.mission_hive_count())
	hives_total = map.hive_cells.size()
	pos = map.start
	floor_z = map.height_at(pos)
	eye_z = floor_z + EYE
	var best_open := -1.0
	for i in 24:
		var a := TAU * i / 24.0
		var d := map.open_distance(pos, Vector2.from_angle(a), 12.0)
		if d > best_open:
			best_open = d
			angle = a
	for p in GameState.PARTS:
		parts[p] = GameState.part_hp[p]

	for hc in map.hive_cells:
		_spawn("hive", Vector2(hc) + Vector2(0.5, 0.5), false)
	var nests := map.nest_cells.duplicate()
	for i in range(nests.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = nests[i]
		nests[i] = nests[j]
		nests[j] = tmp
	var count := mini(3 + GameState.mission * 2, nests.size())
	for i in count:
		var c: Vector2i = nests[i]
		_spawn(_pick_kind(), Vector2(c) + Vector2(rng.randf_range(0.3, 0.7), rng.randf_range(0.3, 0.7)), false)
	for sp in map.prop_spots:
		props.append({"pos": sp, "z": map.height_at(sp), "kind": "crystal" if rng.randf() < 0.3 else "rock"})

	_build_backdrop()
	col_events.resize(COLUMNS)
	for c in COLUMNS:
		col_events[c] = PackedFloat32Array()
	_update_flow()
	_show_msg("MISSION %d — DESTROY %d HIVE%s" % [GameState.mission, hives_total, "" if hives_total == 1 else "S"], 3.5)
	Sfx.play("step")


func _build_backdrop() -> void:
	for i in 90:
		stars.append({"a": rng.randf() * TAU, "e": rng.randf_range(0.2, 1.0), "b": rng.randf_range(0.3, 1.0)})
	ridge_far.resize(256)
	ridge_near.resize(256)
	var ph := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	for i in 256:
		var a := float(i) / 256.0 * TAU
		ridge_far[i] = 40.0 + 22.0 * sin(a * 3.0 + ph[0]) + 12.0 * sin(a * 7.0 + ph[1]) + 6.0 * sin(a * 17.0 + ph[2])
		ridge_near[i] = maxf(0.0, 14.0 + 16.0 * sin(a * 5.0 + ph[3]) + 8.0 * sin(a * 13.0 + ph[0]))
	for i in 16:
		var p := Vector2(rng.randf_range(0.2, 0.8), rng.randf_range(0.15, 0.55))
		var pts: Array[Vector2] = [p]
		var dir := Vector2.from_angle(rng.randf() * TAU)
		for s in rng.randi_range(3, 6):
			dir = dir.rotated(rng.randf_range(-0.7, 0.7))
			p += dir * rng.randf_range(0.02, 0.06)
			pts.append(p)
		cracks.append({"pts": pts, "threshold": 0.65 - i * 0.04})


func _pick_kind() -> String:
	var m := GameState.mission
	var r := rng.randf()
	if m >= 2 and r < 0.06 + 0.03 * m:
		return "brute"
	if r < 0.35:
		return "spitter"
	return "crawler"


func _spawn(kind: String, p: Vector2, awake: bool) -> Dictionary:
	var st: Dictionary = ALIEN_TYPES[kind]
	var hp: float = st["hp"] * (1.0 + 0.08 * (GameState.mission - 1))
	var a := {
		"kind": kind, "pos": p, "fz": map.height_at(p), "hp": hp, "max": hp, "awake": awake,
		"cd": rng.randf_range(0.5, 2.0) if kind == "hive" else 0.5, "anim": rng.randf() * 10.0,
		"flash": 0.0, "dead": false, "death_t": 0.0, "lunge": 0.0, "moving": false,
		"seed": rng.randf() * TAU, "st": st,
	}
	aliens.append(a)
	return a


# =============================================================================
# Update
# =============================================================================

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	time += delta
	var vh := get_viewport_rect().size.y
	pitch = clampf(pitch, -vh * PITCH_LIMIT, vh * PITCH_LIMIT)
	horizon_y = vh * 0.5 + pitch + sin(bob_t * 2.0) * 7.0 * bob_amount
	if state == State.PLAYING:
		_update_player(delta)
		_update_weapons(delta)
		flow_timer -= delta
		if flow_timer <= 0.0:
			_update_flow()
			flow_timer = 0.35
		for a in aliens:
			_update_alien(a, delta)
		_update_projectiles(delta)
		_check_end()
	else:
		end_time += delta
		for a in aliens:
			if a["dead"]:
				a["death_t"] += delta
	aliens = aliens.filter(func(a): return not (a["dead"] and a["death_t"] > 0.7))
	_update_effects(delta)
	queue_redraw()


func _update_player(delta: float) -> void:
	var fwd := -move_vec.y
	var strafe := move_vec.x
	var turn := 0.0
	if Input.is_physical_key_pressed(KEY_W): fwd += 1.0
	if Input.is_physical_key_pressed(KEY_S): fwd -= 1.0
	if Input.is_physical_key_pressed(KEY_A): strafe -= 1.0
	if Input.is_physical_key_pressed(KEY_D): strafe += 1.0
	if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_Q): turn -= 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_E): turn += 1.0
	if Input.is_physical_key_pressed(KEY_UP): fwd += 1.0
	if Input.is_physical_key_pressed(KEY_DOWN): fwd -= 1.0
	angle = wrapf(angle + turn * KEY_TURN_SPEED * delta, -PI, PI)
	if Input.is_physical_key_pressed(KEY_PAGEUP) or Input.is_physical_key_pressed(KEY_T): pitch += 420.0 * delta
	if Input.is_physical_key_pressed(KEY_PAGEDOWN) or Input.is_physical_key_pressed(KEY_G): pitch -= 420.0 * delta

	var dir := Vector2.from_angle(angle)
	var right := Vector2(-dir.y, dir.x)
	var inp := (dir * fwd + right * strafe).limit_length(1.0)
	var speed := GameState.walk_speed() * _legs_factor()
	var mv := inp * speed * delta
	var stand := map.height_at(pos)
	var nx := pos + Vector2(mv.x, 0.0)
	if not map.blocked(nx, PLAYER_R, stand):
		pos = nx
	var ny := pos + Vector2(0.0, mv.y)
	if not map.blocked(ny, PLAYER_R, stand):
		pos = ny

	# Climb steps smoothly; drop off ledges with a heavy landing.
	var target := map.height_at(pos)
	if target < floor_z - 0.3:
		falling = true
	if target > floor_z:
		floor_z = move_toward(floor_z, target, delta * 3.0)
	else:
		floor_z = move_toward(floor_z, target, delta * 7.0)
	if falling and absf(floor_z - target) < 0.01:
		falling = false
		shake = maxf(shake, 12.0)
		Sfx.play("step", -1.0)
	eye_z = floor_z + EYE

	var moving := inp.length()
	bob_amount = lerpf(bob_amount, moving, minf(1.0, delta * 6.0))
	if moving > 0.1:
		var prev := bob_t
		bob_t += delta * speed * 2.2
		if floor(prev / PI) != floor(bob_t / PI):
			Sfx.play("step", -7.0)
			shake = maxf(shake, 3.0)


func _legs_factor() -> float:
	var r: float = parts["legs"] / GameState.max_hp("legs")
	return 0.4 if r <= 0.0 else 0.65 + 0.35 * r


func _update_weapons(delta: float) -> void:
	fire_cd -= delta
	rocket_cd -= delta
	retreat_armed = maxf(0.0, retreat_armed - delta)
	for i in 2:
		muzzle[i] = maxf(0.0, muzzle[i] - delta)
		recoil[i] = maxf(0.0, recoil[i] - delta * 7.0)
	locked_target = _find_target(Vector2.ZERO)
	var firing := fire_touch >= 0 or Input.is_physical_key_pressed(KEY_SPACE)
	if firing and fire_cd <= 0.0:
		_fire_cannon()
	if Input.is_physical_key_pressed(KEY_R) or Input.is_physical_key_pressed(KEY_F):
		_fire_rocket()


func _fire_cannon() -> void:
	var guns: Array[int] = []
	if parts["left_arm"] > 0.0: guns.append(0)
	if parts["right_arm"] > 0.0: guns.append(1)
	if guns.is_empty():
		fire_cd = 0.4
		_show_msg("BOTH ARMS DESTROYED — USE ROCKETS", 1.0)
		return
	var g: int = next_gun if guns.has(next_gun) else guns[0]
	next_gun = 1 - g
	fire_cd = 0.11 if guns.size() == 2 else 0.17
	muzzle[g] = 0.06
	recoil[g] = 1.0
	shake = maxf(shake, 1.5)
	Sfx.play("gun", -5.0)

	# The shot goes exactly where the crosshair points (screen centre),
	# with a few pixels of random spread.
	var spread := Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
	var target = _find_target(spread)
	var hit_point: Vector2
	var hit_z := eye_z
	if target != null:
		_damage_alien(target, GameState.cannon_damage())
		var tp: Vector2 = target["pos"]
		hit_point = tp - (tp - pos).normalized() * 0.2
		hit_z = _aim_height_at(spread, Vector2.from_angle(angle).dot(hit_point - pos))
		explosions.append({"pos": hit_point, "z": hit_z, "t": 0.0, "dur": 0.22, "size": 0.3, "col": Color(0.6, 1.0, 0.3)})
	else:
		var impact := _aim_impact(spread)
		hit_point = impact["pos"]
		hit_z = impact["z"]
		if impact["kind"] == "ground":
			explosions.append({"pos": hit_point, "z": hit_z + 0.05, "t": 0.0, "dur": 0.25, "size": 0.3, "col": Color(0.6, 0.45, 0.3)})
		elif impact["kind"] == "wall":
			explosions.append({"pos": hit_point, "z": hit_z, "t": 0.0, "dur": 0.16, "size": 0.22, "col": Color(1.0, 0.8, 0.4)})
	tracers.append({"g": g, "pos": hit_point, "z": hit_z, "t": 0.05})


func _fire_rocket() -> void:
	if rocket_cd > 0.0 or state != State.PLAYING:
		return
	rocket_cd = GameState.rocket_cooldown()
	var dir := Vector2.from_angle(angle)
	# Climb/dive rate matching the crosshair line: aiming below the horizon dives.
	var s := get_viewport_rect().size
	var slope := -(s.y * 0.5 - horizon_y) / (s.x * 0.5 / FOV_PLANE)
	projectiles.append({"kind": "rocket", "pos": pos + dir * 0.4, "vel": dir * 10.0, "z": eye_z + slope * 0.4, "vz": slope * 10.0, "life": 3.0})
	Sfx.play("rocket", -2.0)
	shake = maxf(shake, 4.0)


func _aim_point(spread: Vector2) -> Vector2:
	return get_viewport_rect().size * 0.5 + spread


func _find_target(spread: Vector2):
	## Returns the nearest alien whose visible sprite is under the crosshair.
	var s := get_viewport_rect().size
	var proj_scale := s.x * 0.5 / FOV_PLANE
	var aim := _aim_point(spread)
	var col := clampi(int(aim.x / s.x * COLUMNS), 0, COLUMNS - 1)
	var best = null
	var best_d := INF
	for a in aliens:
		if a["dead"]:
			continue
		var pr := _project(a["pos"])
		if pr.y <= 0.2 or pr.y > MAX_VIEW:
			continue
		var st: Dictionary = a["st"]
		var half_w: float = st["w"] * 0.5 * proj_scale / pr.y * 0.8
		var bottom: float = horizon_y + (eye_z - a["fz"]) * proj_scale / pr.y
		var top: float = bottom - st["h"] * proj_scale / pr.y * 0.95
		if absf(pr.x - aim.x) < half_w and aim.y > top and aim.y < bottom and pr.y < best_d:
			if aim.y < _clip_at(col, pr.y):
				best = a
				best_d = pr.y
	return best


func _aim_ray(spread: Vector2) -> Vector2:
	## World direction of the aim point (forward component = 1).
	var s := get_viewport_rect().size
	var dir := Vector2.from_angle(angle)
	var right := Vector2(-dir.y, dir.x)
	var cam_x := _aim_point(spread).x / s.x * 2.0 - 1.0
	return dir + right * FOV_PLANE * cam_x


func _aim_slope(spread: Vector2) -> float:
	## Height change per unit of forward distance along the crosshair line.
	var s := get_viewport_rect().size
	return -(_aim_point(spread).y - horizon_y) / (s.x * 0.5 / FOV_PLANE)


func _aim_height_at(spread: Vector2, depth: float) -> float:
	return eye_z + _aim_slope(spread) * depth


func _aim_impact(spread: Vector2) -> Dictionary:
	## Traces the crosshair line through the height grid: ground, wall or sky.
	var rd := _aim_ray(spread)
	var slope := _aim_slope(spread)
	var mx := int(floor(pos.x))
	var my := int(floor(pos.y))
	var ddx := 1e30 if rd.x == 0.0 else absf(1.0 / rd.x)
	var ddy := 1e30 if rd.y == 0.0 else absf(1.0 / rd.y)
	var step_x := -1 if rd.x < 0.0 else 1
	var step_y := -1 if rd.y < 0.0 else 1
	var sdx := (pos.x - mx) * ddx if rd.x < 0.0 else (mx + 1.0 - pos.x) * ddx
	var sdy := (pos.y - my) * ddy if rd.y < 0.0 else (my + 1.0 - pos.y) * ddy
	var cur_h := map.cell_h(mx, my)
	for i in 96:
		var d_out := minf(sdx, sdy)
		if eye_z + slope * d_out < cur_h and slope < 0.0:
			var d_hit := (cur_h - eye_z) / slope
			return {"kind": "ground", "pos": pos + rd * d_hit, "z": cur_h}
		if d_out > MAX_VIEW:
			break
		if sdx < sdy:
			sdx += ddx
			mx += step_x
		else:
			sdy += ddy
			my += step_y
		var nh := map.cell_h(mx, my)
		var z := eye_z + slope * d_out
		if z < nh:
			return {"kind": "wall", "pos": pos + rd * d_out * 0.98, "z": z}
		cur_h = nh
	return {"kind": "sky", "pos": pos + rd * MAX_VIEW, "z": eye_z + slope * MAX_VIEW}


func _project(world: Vector2) -> Vector2:
	## Returns (screen x, depth). Depth <= 0 means behind the camera.
	var s := get_viewport_rect().size
	var dir := Vector2.from_angle(angle)
	var right := Vector2(-dir.y, dir.x)
	var rel := world - pos
	var ty := dir.dot(rel)
	if ty <= 0.001:
		return Vector2(-99999.0, ty)
	var tx := right.dot(rel) / FOV_PLANE
	return Vector2(s.x * 0.5 * (1.0 + tx / ty), ty)


func _clip_at(col: int, depth: float) -> float:
	## Screen y above which a thing at `depth` in this column is still visible.
	var ev: PackedFloat32Array = col_events[col]
	var clip := 1e9
	var i := 0
	while i < ev.size():
		if ev[i] >= depth:
			break
		clip = ev[i + 1]
		i += 2
	return clip


func _damage_alien(a: Dictionary, amount: float) -> void:
	if a["dead"]:
		return
	a["hp"] -= amount
	a["flash"] = 0.08
	a["awake"] = true
	if a["hp"] > 0.0:
		return
	a["dead"] = true
	a["death_t"] = 0.0
	var st: Dictionary = a["st"]
	if a["kind"] == "hive":
		hives_destroyed += 1
		for i in 5:
			var off := Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
			explosions.append({"pos": a["pos"] + off, "z": a["fz"] + rng.randf_range(0.3, 1.4), "t": -i * 0.08, "dur": 0.9, "size": 1.6, "col": Color(1.0, 0.45, 0.2)})
		Sfx.play("boom", 0.0)
		Sfx.play("screech", -2.0, 0.3)
		shake = maxf(shake, 14.0)
		var left := hives_total - hives_destroyed
		_show_msg("HIVE DESTROYED" + ("" if left <= 0 else " — %d LEFT" % left), 2.5)
	else:
		kills += 1
		if a["kind"] == "brute":
			brutes += 1
		explosions.append({"pos": a["pos"], "z": a["fz"] + st["h"] * 0.5, "t": 0.0, "dur": 0.45, "size": st["w"] * 0.9, "col": Color(0.5, 0.95, 0.2)})
		Sfx.play("splat", -3.0)


func _damage_player(amount: float, src: Vector2) -> void:
	if state != State.PLAYING:
		return
	var rel := wrapf((src - pos).angle() - angle, -PI, PI)
	var r := rng.randf()
	var part := "torso"
	if absf(rel) > 2.2:
		part = "legs" if r < 0.55 else "torso"
	elif absf(rel) < 0.5:
		if r < 0.45: part = "torso"
		elif r < 0.65: part = "left_arm"
		elif r < 0.85: part = "right_arm"
		else: part = "legs"
	else:
		var side := "right_arm" if rel > 0.0 else "left_arm"
		if r < 0.55: part = side
		elif r < 0.8: part = "torso"
		else: part = "legs"
	if parts[part] <= 0.0:
		part = "torso"
	var was_alive: bool = parts[part] > 0.0
	parts[part] = maxf(0.0, parts[part] - amount)
	hit_flash = 0.25
	shake = maxf(shake, 9.0)
	dmg_indicators.append({"rel": rel, "t": 0.9})
	Sfx.play("hit", -3.0)
	if was_alive and parts[part] <= 0.0 and part != "torso":
		Sfx.play("alarm", -2.0, 0.0)
		_show_msg("%s DESTROYED" % GameState.PART_NAMES[part].to_upper(), 2.5)


func _update_flow() -> void:
	flow = map.distance_field(Vector2i(int(floor(pos.x)), int(floor(pos.y))), false)


func _flow_dir(p: Vector2) -> Vector2:
	var c := Vector2i(int(floor(p.x)), int(floor(p.y)))
	var here := map.cell_h(c.x, c.y)
	var limit := here + LevelMap.STEP
	var best := c
	var bd := flow[map.idx(c.x, c.y)] if map.in_bounds(c.x, c.y) else -1
	if bd < 0:
		bd = 1 << 30
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var n := c + Vector2i(dx, dy)
			if not map.in_bounds(n.x, n.y) or map.cell_h(n.x, n.y) > limit:
				continue
			if dx != 0 and dy != 0:
				if map.cell_h(c.x + dx, c.y) > limit or map.cell_h(c.x, c.y + dy) > limit:
					continue
			var d := flow[map.idx(n.x, n.y)]
			if d >= 0 and d < bd:
				bd = d
				best = n
	var target := Vector2(best) + Vector2(0.5, 0.5)
	if best == c:
		target = pos
	var v := target - p
	return v.normalized() if v.length() > 0.01 else Vector2.ZERO


func _update_alien(a: Dictionary, delta: float) -> void:
	a["anim"] += delta
	a["flash"] = maxf(0.0, a["flash"] - delta)
	a["lunge"] = maxf(0.0, a["lunge"] - delta)
	if a["dead"]:
		a["death_t"] += delta
		return
	a["cd"] -= delta
	a["fz"] = move_toward(a["fz"], map.height_at(a["pos"]), delta * 5.0)
	var to_p: Vector2 = pos - a["pos"]
	var dist := to_p.length()
	var st: Dictionary = a["st"]
	var dmg_mul := 1.0 + 0.06 * (GameState.mission - 1)
	var a_eye: float = a["fz"] + st["h"] * 0.8

	if a["kind"] == "hive":
		_update_hive(a, dist)
		return
	if not a["awake"]:
		if dist < 9.0 and map.line_of_sight(a["pos"], a_eye, pos, eye_z):
			a["awake"] = true
			Sfx.play("screech", lerpf(-4.0, -16.0, dist / 9.0), 0.25)
		else:
			a["moving"] = false
			return

	var los := dist < 12.0 and map.line_of_sight(a["pos"], a_eye, pos, eye_z)
	var same_level: bool = absf(a["fz"] - floor_z) < 1.0
	var move_dir := Vector2.ZERO
	var speed_mul := 1.0
	if a["kind"] == "spitter" and los and dist < st["range"]:
		if dist < 3.5:
			move_dir = -to_p / dist
		else:
			var side := 1.0 if sin(a["anim"] * 0.7 + a["seed"]) > 0.0 else -1.0
			move_dir = Vector2(-to_p.y, to_p.x).normalized() * side
			speed_mul = 0.5
		if a["cd"] <= 0.0:
			var d := to_p / dist
			var z0: float = a["fz"] + st["h"] * 0.7
			var vz := (eye_z - 0.4 - z0) / dist * 5.5
			projectiles.append({"kind": "acid", "pos": a["pos"] + d * 0.3, "vel": d * 5.5, "z": z0, "vz": vz, "life": 4.0, "dmg": st["dmg"] * dmg_mul, "src": a["pos"]})
			a["cd"] = st["cd"] * rng.randf_range(0.8, 1.3)
			a["lunge"] = 0.2
			Sfx.play("splat", -12.0, 0.3)
	elif los and same_level and dist < st["range"] + PLAYER_R + 0.1:
		if a["cd"] <= 0.0:
			_damage_player(st["dmg"] * dmg_mul, a["pos"])
			a["cd"] = st["cd"]
			a["lunge"] = 0.25
	elif los and same_level and dist < 6.0:
		move_dir = to_p / dist
	else:
		move_dir = _flow_dir(a["pos"])

	for b in aliens:
		if b == a or b["dead"] or b["kind"] == "hive":
			continue
		var off: Vector2 = a["pos"] - b["pos"]
		var l := off.length()
		if l < 0.6 and l > 0.001:
			move_dir += off / l * (0.6 - l) * 2.0

	var step: Vector2 = move_dir.limit_length(1.0) * st["speed"] * speed_mul * delta
	a["moving"] = step.length() > 0.0005
	var r: float = st["r"]
	var stand := map.height_at(a["pos"])
	var nx: Vector2 = a["pos"] + Vector2(step.x, 0.0)
	if not map.blocked(nx, r, stand) and nx.distance_to(pos) > r + PLAYER_R:
		a["pos"] = nx
	var ny: Vector2 = a["pos"] + Vector2(0.0, step.y)
	if not map.blocked(ny, r, stand) and ny.distance_to(pos) > r + PLAYER_R:
		a["pos"] = ny


func _update_hive(a: Dictionary, dist: float) -> void:
	if dist < 12.0:
		a["awake"] = true
	if not a["awake"] or a["cd"] > 0.0:
		return
	a["cd"] = maxf(3.5, 7.5 - GameState.mission * 0.4)
	var alive := 0
	for b in aliens:
		if not b["dead"] and b["kind"] != "hive":
			alive += 1
	if alive >= 8 + GameState.mission * 2:
		return
	var stand := map.height_at(a["pos"])
	for attempt in 8:
		var p: Vector2 = a["pos"] + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.7, 1.4)
		if not map.blocked(p, 0.3, stand):
			_spawn(_pick_kind(), p, true)
			explosions.append({"pos": p, "z": map.height_at(p) + 0.3, "t": 0.0, "dur": 0.5, "size": 0.7, "col": Color(0.75, 0.3, 0.8)})
			Sfx.play("splat", lerpf(-6.0, -18.0, clampf(dist / 12.0, 0.0, 1.0)), 0.3)
			return


func _update_projectiles(delta: float) -> void:
	smoke_timer -= delta
	var puff := smoke_timer <= 0.0
	if puff:
		smoke_timer = 0.03
	for pr in projectiles:
		pr["life"] -= delta
		var np: Vector2 = pr["pos"] + pr["vel"] * delta
		pr["z"] += pr["vz"] * delta
		var z: float = pr["z"]
		var ground := map.height_at(np)
		if pr["kind"] == "rocket":
			if puff:
				explosions.append({"pos": pr["pos"], "z": z, "t": 0.0, "dur": 0.5, "size": 0.18, "col": Color(0.55, 0.52, 0.5), "smoke": true})
			var hit: bool = ground > z or pr["life"] <= 0.0
			for a in aliens:
				if a["dead"]:
					continue
				var st: Dictionary = a["st"]
				if a["pos"].distance_to(np) < st["r"] + 0.3 and z > a["fz"] - 0.1 and z < a["fz"] + st["h"] + 0.2:
					hit = true
					break
			if hit:
				_explode_rocket(pr["pos"], maxf(z, map.height_at(pr["pos"]) + 0.1))
				pr["life"] = -1.0
				continue
		else:
			if ground > z or pr["life"] <= 0.0:
				explosions.append({"pos": pr["pos"], "z": maxf(z, ground), "t": 0.0, "dur": 0.3, "size": 0.35, "col": Color(0.6, 1.0, 0.2)})
				pr["life"] = -1.0
				continue
			if np.distance_to(pos) < PLAYER_R + 0.15 and z > floor_z - 0.2 and z < eye_z + 0.5:
				_damage_player(pr["dmg"], pr["src"])
				pr["life"] = -1.0
				continue
		pr["pos"] = np
	projectiles = projectiles.filter(func(pr): return pr["life"] > 0.0)


func _explode_rocket(p: Vector2, z: float) -> void:
	explosions.append({"pos": p, "z": z, "t": 0.0, "dur": 0.75, "size": 1.4, "col": Color(1.0, 0.6, 0.2)})
	for i in 3:
		var off := Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))
		explosions.append({"pos": p + off, "z": z + rng.randf_range(-0.3, 0.5), "t": -0.06 * (i + 1), "dur": 0.6, "size": 0.9, "col": Color(1.0, 0.75, 0.3)})
	Sfx.play("boom", -1.0)
	var d := p.distance_to(pos)
	shake = maxf(shake, 16.0 * clampf(1.0 - d / 9.0, 0.25, 1.0))
	for a in aliens:
		if a["dead"]:
			continue
		var st: Dictionary = a["st"]
		var dd: float = a["pos"].distance_to(p)
		var dz: float = z - (a["fz"] + st["h"] * 0.5)
		var d3 := sqrt(dd * dd + dz * dz)
		if d3 < 1.9:
			_damage_alien(a, GameState.rocket_damage() * (1.0 - d3 / 1.9 * 0.6))


func _update_effects(delta: float) -> void:
	for e in explosions:
		e["t"] += delta
	explosions = explosions.filter(func(e): return e["t"] < e["dur"])
	for t in tracers:
		t["t"] -= delta
	tracers = tracers.filter(func(t): return t["t"] > 0.0)
	for d in dmg_indicators:
		d["t"] -= delta
	dmg_indicators = dmg_indicators.filter(func(d): return d["t"] > 0.0)
	shake *= exp(-delta * 9.0)
	hit_flash = maxf(0.0, hit_flash - delta)
	msg_t -= delta
	if state == State.PLAYING and parts["torso"] / GameState.max_hp("torso") < 0.3:
		alarm_cd -= delta
		if alarm_cd <= 0.0:
			Sfx.play("alarm", -9.0, 0.0)
			alarm_cd = 1.3


func _check_end() -> void:
	if parts["torso"] <= 0.0:
		state = State.LOST
		explosions.append({"pos": pos + Vector2.from_angle(angle) * 0.6, "z": eye_z - 0.6, "t": 0.0, "dur": 1.0, "size": 1.5, "col": Color(1.0, 0.5, 0.2)})
		Sfx.play("boom", 2.0)
		shake = 22.0
		_finish()
	elif hives_destroyed >= hives_total:
		state = State.WON
		# The hive mind is severed: every remaining alien collapses.
		for a in aliens:
			if not a["dead"]:
				_damage_alien(a, 1e9)
		_finish()


func _finish() -> void:
	fire_touch = -1
	move_touch = -1
	look_touch = -1
	move_vec = Vector2.ZERO
	GameState.apply_battle_result({
		"won": state == State.WON,
		"retreated": state == State.RETREATED,
		"kills": kills,
		"brutes": brutes,
		"hives_destroyed": hives_destroyed,
		"hives_total": hives_total,
		"parts": parts.duplicate(),
	})


func _show_msg(text: String, dur: float) -> void:
	msg = text
	msg_t = dur


# =============================================================================
# Input
# =============================================================================

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if state != State.PLAYING and end_time > 1.0 and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE]:
			get_tree().change_scene_to_file("res://scenes/hangar.tscn")
		return
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position
		var s := get_viewport_rect().size
		if event.pressed:
			if state != State.PLAYING:
				if end_time > 1.2:
					get_tree().change_scene_to_file("res://scenes/hangar.tscn")
				return
			if _retreat_rect().has_point(p):
				if retreat_armed > 0.0:
					state = State.RETREATED
					_finish()
				else:
					retreat_armed = 2.5
					Sfx.play("click")
				return
			if p.distance_to(_fire_center(s)) < FIRE_R * 1.2:
				fire_touch = event.index
				return
			if p.distance_to(_rocket_center(s)) < ROCKET_R * 1.25:
				_fire_rocket()
				return
			if p.x < s.x * 0.45:
				if move_touch < 0:
					move_touch = event.index
					move_origin = p
					move_vec = Vector2.ZERO
			elif look_touch < 0:
				look_touch = event.index
				look_last_x = p.x
				look_last_y = p.y
		else:
			if event.index == move_touch:
				move_touch = -1
				move_vec = Vector2.ZERO
			if event.index == look_touch:
				look_touch = -1
			if event.index == fire_touch:
				fire_touch = -1
	elif event is InputEventScreenDrag and state == State.PLAYING:
		if event.index == move_touch:
			var v: Vector2 = (event.position - move_origin) / JOY_RADIUS
			move_vec = v.limit_length(1.0) if v.length() > 0.12 else Vector2.ZERO
		elif event.index == look_touch:
			angle = wrapf(angle + (event.position.x - look_last_x) * LOOK_SENS, -PI, PI)
			pitch -= (event.position.y - look_last_y) * PITCH_SENS
			look_last_x = event.position.x
			look_last_y = event.position.y
		elif event.index == fire_touch:
			# Sliding your thumb on the fire button also turns the mech.
			angle = wrapf(angle + event.relative.x * LOOK_SENS * 0.7, -PI, PI)
			pitch -= event.relative.y * PITCH_SENS * 0.7


func _fire_center(s: Vector2) -> Vector2:
	return Vector2(s.x - 150.0, s.y - 165.0)


func _rocket_center(s: Vector2) -> Vector2:
	return Vector2(s.x - 318.0, s.y - 105.0)


func _retreat_rect() -> Rect2:
	return Rect2(16, 16, 150, 46)


# =============================================================================
# Drawing
# =============================================================================

func _draw() -> void:
	var s := get_viewport_rect().size
	var w := s.x
	var h := s.y
	var shake_off := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * shake
	draw_set_transform(shake_off)

	var proj_scale := w * 0.5 / FOV_PLANE
	var horizon := horizon_y
	_draw_sky(w, h, horizon)
	_draw_ground(w, h, horizon)
	_draw_world(w, h, horizon, proj_scale)
	_draw_sprites(w, h, horizon, proj_scale)
	_draw_tracers(w, h, horizon, proj_scale)
	_draw_guns(w, h)
	_draw_cockpit(w, h)
	_draw_hud(w, h, horizon, proj_scale)

	draw_set_transform(Vector2.ZERO)
	if state == State.PLAYING:
		_draw_touch_controls(w, h)
	else:
		_draw_end_screen(w, h)


func _sky_x(rel: float, w: float) -> float:
	return w * 0.5 * (1.0 + tan(rel) / FOV_PLANE)


func _draw_sky(w: float, h: float, horizon: float) -> void:
	draw_rect(Rect2(-40, -40, w + 80, horizon - h * 0.55 + 41), Color(0.04, 0.02, 0.09))
	draw_polygon(
		PackedVector2Array([Vector2(-40, horizon - h * 0.55), Vector2(w + 40, horizon - h * 0.55), Vector2(w + 40, horizon), Vector2(-40, horizon)]),
		PackedColorArray([Color(0.04, 0.02, 0.09), Color(0.04, 0.02, 0.09), Color(0.5, 0.2, 0.16), Color(0.5, 0.2, 0.16)]))
	var half_fov := atan(FOV_PLANE) + 0.05
	for st in stars:
		var rel := wrapf(st["a"] - angle, -PI, PI)
		if absf(rel) > half_fov:
			continue
		var y: float = horizon - st["e"] * h * 0.45
		var b: float = st["b"] * (0.6 + 0.4 * sin(time * 2.0 + st["a"] * 9.0))
		draw_rect(Rect2(_sky_x(rel, w), y, 2, 2), Color(1, 0.95, 0.9, b * clampf((horizon - y) / (h * 0.45), 0.0, 1.0) * 1.3))

	# Ringed gas giant hanging over the battlefield.
	var prel := wrapf(0.9 - angle, -PI, PI)
	if absf(prel) < half_fov + 0.3:
		var c := Vector2(_sky_x(prel, w), horizon - h * 0.31)
		var r := 64.0
		var ring: Array[Vector2] = []
		for i in 49:
			var t := float(i) / 48.0 * TAU
			ring.append(c + Vector2(cos(t) * r * 1.9, sin(t) * r * 0.42).rotated(-0.25))
		draw_polyline(PackedVector2Array(ring.slice(24, 49)), Color(0.9, 0.75, 0.6, 0.6), 3.0)
		draw_circle(c, r, Color(0.78, 0.5, 0.38))
		draw_circle(c + Vector2(14, 10), r * 0.86, Color(0.58, 0.32, 0.27))
		draw_circle(c + Vector2(26, 18), r * 0.7, Color(0.38, 0.18, 0.18))
		draw_polyline(PackedVector2Array(ring.slice(0, 25)), Color(0.95, 0.82, 0.65, 0.8), 3.0)

	# Distant mountain ridges (two layers).
	var strips := 80
	var sw := w / strips
	for layer in 2:
		var ridge := ridge_far if layer == 0 else ridge_near
		var col := Color(0.24, 0.1, 0.13) if layer == 0 else Color(0.15, 0.06, 0.09)
		for i in strips:
			var xc := (i + 0.5) * sw
			var rel := atan((2.0 * xc / w - 1.0) * FOV_PLANE)
			var a := wrapf(angle + rel, 0.0, TAU)
			var hgt: float = ridge[int(a / TAU * 256.0) % 256]
			draw_rect(Rect2(i * sw, horizon - hgt, sw + 1.0, hgt + 1.0), col)


func _draw_ground(w: float, h: float, horizon: float) -> void:
	draw_polygon(
		PackedVector2Array([Vector2(-40, horizon), Vector2(w + 40, horizon), Vector2(w + 40, h + 40), Vector2(-40, h + 40)]),
		PackedColorArray([Color(0.26, 0.14, 0.12), Color(0.26, 0.14, 0.12), Color(0.13, 0.09, 0.08), Color(0.13, 0.09, 0.08)]))



func _draw_world(w: float, h: float, horizon: float, proj_scale: float) -> void:
	## Heightfield renderer. For every screen column a ray walks the grid from
	## the mech outward. Each cell contributes its front face (if it is taller
	## than the cell before it) and its top surface. Everything is drawn near
	## to far, only above `clip` (the highest pixel already covered), so nearer
	## terrain hides what's behind it. Height-0 ground is the backdrop polygon,
	## so flat ground costs nothing to draw.
	var dir := Vector2.from_angle(angle)
	var plane := Vector2(-dir.y, dir.x) * FOV_PLANE
	var col_w := w / COLUMNS
	# Local copies: direct array access is much faster than method calls.
	var hmax := map.max_height
	var heights := map.heights
	var kinds := map.kinds
	var mw := map.w
	var mh := map.h
	var ez := eye_z
	var ps := proj_scale
	var px := pos.x
	var py := pos.y
	var cut := (hmax - ez) * ps
	for c in COLUMNS:
		var cam_x := 2.0 * (c + 0.5) / COLUMNS - 1.0
		var rdx := dir.x + plane.x * cam_x
		var rdy := dir.y + plane.y * cam_x
		var x := c * col_w
		var cw := col_w + 1.0
		var ev := PackedFloat32Array()

		var mx := int(floor(px))
		var my := int(floor(py))
		var ddx := 1e30 if rdx == 0.0 else absf(1.0 / rdx)
		var ddy := 1e30 if rdy == 0.0 else absf(1.0 / rdy)
		var step_x := -1 if rdx < 0.0 else 1
		var step_y := -1 if rdy < 0.0 else 1
		var sdx := (px - mx) * ddx if rdx < 0.0 else (mx + 1.0 - px) * ddx
		var sdy := (py - my) * ddy if rdy < 0.0 else (my + 1.0 - py) * ddy

		var clip := h + 4.0
		var ci := my * mw + mx
		var cur_h: float = heights[ci]
		var cur_k: int = kinds[ci]
		var d_in := 0.0
		for i in 64:
			var side := 0
			var d_out := sdx
			if sdy < sdx:
				side = 1
				d_out = sdy

			# Top surface of the current cell (only visible when below the eye).
			if cur_h < ez:
				var y_far := horizon + (ez - cur_h) * ps / maxf(d_out, 0.05)
				if cur_h != 0.0 or cur_k != LevelMap.EMPTY:
					var y_near := clip
					if d_in > 0.05:
						y_near = minf(horizon + (ez - cur_h) * ps / d_in, clip)
					if y_near > y_far:
						draw_rect(Rect2(x, y_far, cw, y_near - y_far), _top_color(cur_h, cur_k, d_out))
				if y_far < clip:
					clip = y_far
					ev.append(d_out)
					ev.append(clip)

			# Stop when out of range, or when nothing farther can rise above
			# what's already covered.
			if d_out > MAX_VIEW or clip <= 0.0 or clip <= horizon - cut / d_out:
				break

			if side == 0:
				sdx += ddx
				mx += step_x
			else:
				sdy += ddy
				my += step_y
			if mx < 0 or my < 0 or mx >= mw or my >= mh:
				break
			d_in = d_out
			ci = my * mw + mx
			var nh: float = heights[ci]
			if nh > cur_h:
				var y_top := horizon - (nh - ez) * ps / d_in
				var y_vis := minf(horizon - (cur_h - ez) * ps / d_in, clip)
				if y_vis > y_top:
					var wall_x := (py + d_in * rdy) if side == 0 else (px + d_in * rdx)
					wall_x -= floorf(wall_x)
					_draw_face(x, cw, y_top, y_vis, nh, cur_h, kinds[ci], side, wall_x, d_in, horizon, ps)
				if y_top < clip:
					clip = y_top
					ev.append(d_in)
					ev.append(clip)
			cur_h = nh
			cur_k = kinds[ci]
		col_events[c] = ev


func _top_color(height: float, kind: int, d: float) -> Color:
	var col: Color
	match kind:
		LevelMap.PLATFORM:
			col = PLATFORM_TOP
		LevelMap.EMPTY:
			col = GROUND_TOP.lightened(clampf(height * 0.12, 0.0, 0.3)) if height >= 0.0 else GROUND_TOP.darkened(0.35 * minf(-height, 1.0))
		_:
			col = FACE_COLORS.get(kind, FACE_COLORS[LevelMap.METAL]).darkened(0.35)
	return col.lerp(FOG, clampf(d / FOG_DIST, 0.0, 1.0))


func _vband(x: float, cw: float, y0: float, y1: float, lo: float, hi: float, c: Color) -> void:
	## Draws a vertical slice of a face, kept within [lo, hi].
	var a := maxf(y0, lo)
	var b := minf(y1, hi)
	if b > a:
		draw_rect(Rect2(x, a, cw, b - a), c)


func _draw_face(x: float, cw: float, y_top: float, y_vis: float, top_h: float, base_h: float, kind: int, side: int, wall_x: float, d: float, horizon: float, proj_scale: float) -> void:
	var fog := clampf(d / FOG_DIST, 0.0, 1.0)
	var base: Color = FACE_COLORS.get(kind, FACE_COLORS[LevelMap.METAL])
	if side == 1:
		base = base.darkened(0.22)
	var face_h := top_h - base_h
	var yt := y_top
	if kind == LevelMap.RUIN and face_h > 1.5:
		# Jagged broken roofline.
		var seg := floorf(wall_x * 5.0)
		var jag := fposmod(sin(seg * 12.9898 + side * 3.1 + top_h * 7.0) * 43758.5453, 1.0)
		yt += 0.25 * jag * proj_scale / d
	elif kind == LevelMap.ORGANIC:
		base = base.lightened(0.12 * sin(time * 3.0 + wall_x * 10.0))
	var col := base.lerp(FOG, fog)
	var lo := maxf(yt, -50.0)
	var hi := minf(y_vis, 5000.0)
	if hi <= lo:
		return
	draw_rect(Rect2(x, lo, cw, hi - lo), col)

	var k := proj_scale / d
	var shade := Color(0, 0, 0, 0.35 * (1.0 - fog))
	match kind:
		LevelMap.RUIN:
			if face_h > 1.5:
				var u := fposmod(wall_x * 2.0, 1.0)
				if u > 0.25 and u < 0.62:
					var z := base_h + 0.7
					while z + 0.5 < top_h - 0.3:
						var wy0 := horizon - (z + 0.5 - eye_z) * k
						var wy1 := horizon - (z - eye_z) * k
						_vband(x, cw, wy0, wy1, lo, hi, Color(0.06, 0.04, 0.05, 0.75 * (1.0 - fog)))
						z += 1.3
				if fposmod(wall_x * 4.0, 1.0) < 0.06:
					draw_rect(Rect2(x, lo, cw, hi - lo), shade)
			else:
				# Low cover wall: lighter capstone along the top.
				_vband(x, cw, y_top, y_top + 0.12 * k, lo, hi, base.lightened(0.25).lerp(FOG, fog))
		LevelMap.METAL:
			if fposmod(wall_x * 4.0, 1.0) < 0.07:
				draw_rect(Rect2(x, lo, cw, hi - lo), shade)
			var stripe := Color(0.75, 0.6, 0.1) if fposmod(wall_x * 6.0, 1.0) < 0.5 else Color(0.1, 0.1, 0.1)
			var sy0 := horizon - (base_h + 0.35 - eye_z) * k
			var sy1 := horizon - (base_h + 0.15 - eye_z) * k
			_vband(x, cw, sy0, sy1, lo, hi, stripe.lerp(FOG, fog))
		LevelMap.ORGANIC:
			var u2 := fposmod(wall_x * 3.0, 1.0)
			if u2 > 0.42 and u2 < 0.55:
				var glow := Color(1.0, 0.55, 0.15).lerp(FOG, fog * 0.7)
				glow.a = 0.6 + 0.4 * sin(time * 4.0 + wall_x * 20.0)
				var gz := base_h + face_h * 0.45
				_vband(x, cw, horizon - (gz + 0.2 - eye_z) * k, horizon - (gz - eye_z) * k, lo, hi, glow)
		_:
			# Steps, platform sides, terraces and crater walls: bright lip on top
			# so every ledge reads clearly.
			_vband(x, cw, y_top, y_top + maxf(2.0, 0.06 * k), lo, hi, base.lightened(0.35).lerp(FOG, fog))


func _draw_sprites(w: float, h: float, horizon: float, proj_scale: float) -> void:
	var items: Array = []
	for a in aliens:
		var pr := _project(a["pos"])
		if pr.y > 0.15 and pr.y < MAX_VIEW:
			items.append([pr.y, 0, a, pr.x])
	for p in props:
		var pr := _project(p["pos"])
		if pr.y > 0.15 and pr.y < 14.0:
			items.append([pr.y, 1, p, pr.x])
	for p in projectiles:
		var pr := _project(p["pos"])
		if pr.y > 0.15 and pr.y < MAX_VIEW:
			items.append([pr.y, 2, p, pr.x])
	for e in explosions:
		if e["t"] < 0.0:
			continue
		var pr := _project(e["pos"])
		if pr.y > 0.15 and pr.y < MAX_VIEW:
			items.append([pr.y, 3, e, pr.x])
	items.sort_custom(func(x, y): return x[0] > y[0])

	var col_w := w / COLUMNS
	for it in items:
		var ty: float = it[0]
		var sx: float = it[3]
		var o: Dictionary = it[2]
		var fog := clampf(ty / FOG_DIST, 0.0, 1.0)
		var c := clampi(int(sx / col_w), 0, COLUMNS - 1)
		match it[1]:
			0:
				var st: Dictionary = o["st"]
				var frames: Array = tex[o["kind"]]
				var rate := 7.0 if o["moving"] else 2.0
				var frame: Texture2D = frames[int(o["anim"] * rate) % frames.size()]
				var mod := Color.WHITE.lerp(FOG, fog * 0.85)
				var ww: float = st["w"] * (1.0 + o["lunge"] * 0.6)
				var hh: float = st["h"] * (1.0 + o["lunge"] * 0.3)
				if o["dead"]:
					var k: float = clampf(o["death_t"] / 0.6, 0.0, 1.0)
					hh *= 1.0 - k
					ww *= 1.0 + k * 0.4
					mod = mod.lerp(Color(0.3, 0.6, 0.1), 0.5)
					mod.a = 1.0 - k
				if o["flash"] > 0.0:
					mod = Color(2.0, 2.0, 2.0)
				var rect := _billboard(frame, sx, ty, ww, hh, o["fz"], mod, horizon, proj_scale, col_w)
				if not o["dead"] and (o["kind"] == "hive" or o["kind"] == "brute") and o["hp"] < o["max"] and rect.size.x > 6.0:
					var bar := Rect2(rect.position.x, rect.position.y - 10.0, rect.size.x, 5.0)
					if bar.position.y < _clip_at(c, ty):
						draw_rect(bar, Color(0, 0, 0, 0.6))
						draw_rect(Rect2(bar.position, Vector2(bar.size.x * o["hp"] / o["max"], bar.size.y)), Color(0.9, 0.2, 0.6))
				if o == locked_target and state == State.PLAYING:
					_draw_brackets(rect, Color(1.0, 0.25, 0.2))
			1:
				var t: Texture2D = tex[o["kind"]][0]
				var mod2 := Color.WHITE.lerp(FOG, fog * 0.85)
				if o["kind"] == "crystal":
					mod2 = mod2.lerp(Color(1.4, 1.4, 1.4), 0.3 + 0.2 * sin(time * 2.0))
				_billboard(t, sx, ty, 0.6, 0.6, o["z"], mod2, horizon, proj_scale, col_w)
			2:
				if ty < 0.5:
					continue
				var cy: float = horizon + (eye_z - o["z"]) * proj_scale / ty
				if cy >= _clip_at(c, ty):
					continue
				if o["kind"] == "rocket":
					var r := clampf(0.09 * proj_scale / ty, 2.0, 40.0)
					draw_circle(Vector2(sx, cy), r * 2.2, Color(1.0, 0.5, 0.1, 0.35))
					draw_circle(Vector2(sx, cy), r, Color(1.0, 0.95, 0.7))
				else:
					var r2 := clampf(0.14 * proj_scale / ty, 2.0, 60.0)
					draw_circle(Vector2(sx, cy), r2 * 1.8, Color(0.5, 1.0, 0.1, 0.3))
					draw_circle(Vector2(sx, cy), r2, Color(0.75, 1.0, 0.3))
			3:
				var cy2: float = horizon + (eye_z - o["z"]) * proj_scale / ty
				if cy2 >= _clip_at(c, ty + 0.3):
					continue
				var k2: float = o["t"] / o["dur"]
				if ty < 0.6 and o["size"] < 0.5:
					continue
				var base_r: float = minf(o["size"] * proj_scale / ty, h * 0.28)
				var ec: Color = o["col"]
				if o.get("smoke", false):
					draw_circle(Vector2(sx, cy2 - k2 * base_r), base_r * (0.6 + k2 * 1.6), Color(ec.r, ec.g, ec.b, 0.35 * (1.0 - k2)))
				else:
					var rr := base_r * (0.35 + 0.75 * k2)
					draw_circle(Vector2(sx, cy2), rr, Color(ec.r, ec.g * 0.6, ec.b * 0.5, 0.55 * (1.0 - k2)))
					draw_circle(Vector2(sx, cy2), rr * 0.7, Color(ec.r, ec.g, ec.b, 0.9 * (1.0 - k2)))
					if k2 < 0.35:
						draw_circle(Vector2(sx, cy2), rr * 0.4, Color(1, 1, 0.9, 1.0 - k2 * 2.5))


func _billboard(t: Texture2D, sx: float, ty: float, ww: float, hh: float, z: float, mod: Color, horizon: float, proj_scale: float, col_w: float) -> Rect2:
	## Draws a sprite standing on height z, one screen column at a time, cut
	## off wherever nearer terrain covers it.
	var sw := ww * proj_scale / ty
	var sh := hh * proj_scale / ty
	var bottom := horizon + (eye_z - z) * proj_scale / ty
	var top := bottom - sh
	var left := sx - sw * 0.5
	if sw < 1.0 or sh < 1.0:
		return Rect2(left, top, sw, sh)
	var tw := float(t.get_width())
	var th := float(t.get_height())
	var c0 := maxi(int(floor(left / col_w)), 0)
	var c1 := mini(int(ceil((left + sw) / col_w)), COLUMNS)
	for c in range(c0, c1):
		var clip := _clip_at(c, ty)
		if top >= clip:
			continue
		var vis_bottom := minf(bottom, clip)
		var xa := maxf(c * col_w, left)
		var xb := minf((c + 1) * col_w, left + sw)
		if xb <= xa:
			continue
		var u0 := (xa - left) / sw
		var u1 := (xb - left) / sw
		var v1 := (vis_bottom - top) / sh
		draw_texture_rect_region(t, Rect2(xa, top, xb - xa + 0.5, vis_bottom - top), Rect2(u0 * tw, 0, (u1 - u0) * tw, v1 * th), mod)
	return Rect2(left, top, sw, sh)


func _draw_brackets(r: Rect2, c: Color) -> void:
	var l := clampf(minf(r.size.x, r.size.y) * 0.25, 6.0, 24.0)
	var g := r.grow(4.0)
	for corner in [g.position, Vector2(g.end.x, g.position.y), g.end, Vector2(g.position.x, g.end.y)]:
		var sxn := 1.0 if corner.x == g.position.x else -1.0
		var syn := 1.0 if corner.y == g.position.y else -1.0
		draw_line(corner, corner + Vector2(l * sxn, 0), c, 2.0)
		draw_line(corner, corner + Vector2(0, l * syn), c, 2.0)


func _muzzle_pos(g: int, w: float, h: float) -> Vector2:
	var tip := Vector2(w * 0.3, h * 0.77) if g == 0 else Vector2(w * 0.7, h * 0.77)
	var base := Vector2(w * 0.12, h * 1.04) if g == 0 else Vector2(w * 0.88, h * 1.04)
	return tip.lerp(base, recoil[g] * 0.08)


func _draw_tracers(w: float, h: float, horizon: float, proj_scale: float) -> void:
	for t in tracers:
		var pr := _project(t["pos"])
		if pr.y <= 0.1:
			continue
		var end := Vector2(pr.x, horizon + (eye_z - t["z"]) * proj_scale / pr.y)
		var start := _muzzle_pos(t["g"], w, h)
		draw_line(start, end, Color(1.0, 0.85, 0.4, 0.8), 3.0)
		draw_line(start, start.lerp(end, 0.4), Color(1, 1, 0.9, 0.9), 1.5)


func _draw_guns(w: float, h: float) -> void:
	for g in 2:
		var arm := "left_arm" if g == 0 else "right_arm"
		var alive: bool = parts[arm] > 0.0
		var tip := _muzzle_pos(g, w, h)
		var base := Vector2(w * 0.12, h * 1.04) if g == 0 else Vector2(w * 0.88, h * 1.04)
		var dir := (tip - base).normalized()
		var n := Vector2(-dir.y, dir.x)
		var body_col := Color(0.26, 0.28, 0.3) if alive else Color(0.12, 0.1, 0.1)
		var poly := PackedVector2Array([base + n * 56, base - n * 56, tip - n * 18, tip + n * 18])
		draw_colored_polygon(poly, body_col)
		draw_polyline(PackedVector2Array([base + n * 56, tip + n * 18, tip - n * 18]), Color(0.45, 0.48, 0.5), 2.0)
		# Barrel shroud with cooling slots
		for i in 3:
			var p := tip.lerp(base, 0.15 + i * 0.12)
			draw_line(p + n * 14, p - n * 14, Color(0.1, 0.1, 0.12), 3.0)
		if not alive:
			if rng.randf() < 0.35:
				var sp := tip.lerp(base, rng.randf_range(0.0, 0.5))
				draw_line(sp, sp + Vector2.from_angle(rng.randf() * TAU) * 14.0, Color(1.0, 0.85, 0.3), 2.0)
			continue
		if muzzle[g] > 0.0:
			var fl := tip + dir * 26.0
			draw_circle(fl, 30.0, Color(1.0, 0.7, 0.2, 0.55))
			draw_circle(fl, 16.0, Color(1.0, 0.95, 0.75))


func _draw_cockpit(w: float, h: float) -> void:
	var frame := Color(0.08, 0.09, 0.1)
	var edge := Color(0.3, 0.32, 0.36)
	var top := PackedVector2Array([Vector2(-40, -40), Vector2(w + 40, -40), Vector2(w + 40, h * 0.07), Vector2(w * 0.8, h * 0.105), Vector2(w * 0.2, h * 0.105), Vector2(-40, h * 0.07)])
	var left := PackedVector2Array([Vector2(-40, h * 0.05), Vector2(w * 0.035, h * 0.07), Vector2(w * 0.07, h * 0.88), Vector2(-40, h * 0.9)])
	var right := PackedVector2Array([Vector2(w + 40, h * 0.05), Vector2(w * 0.965, h * 0.07), Vector2(w * 0.93, h * 0.88), Vector2(w + 40, h * 0.9)])
	var bottom := PackedVector2Array([Vector2(-40, h + 40), Vector2(-40, h * 0.89), Vector2(w * 0.2, h * 0.87), Vector2(w * 0.35, h * 0.905), Vector2(w * 0.65, h * 0.905), Vector2(w * 0.8, h * 0.87), Vector2(w + 40, h * 0.89), Vector2(w + 40, h + 40)])
	for poly in [top, left, right, bottom]:
		draw_colored_polygon(poly, frame)
	draw_polyline(PackedVector2Array([Vector2(0, h * 0.07), Vector2(w * 0.2, h * 0.105), Vector2(w * 0.8, h * 0.105), Vector2(w, h * 0.07)]), edge, 2.0)
	draw_line(Vector2(w * 0.035, h * 0.07), Vector2(w * 0.07, h * 0.88), edge, 2.0)
	draw_line(Vector2(w * 0.965, h * 0.07), Vector2(w * 0.93, h * 0.88), edge, 2.0)
	draw_polyline(PackedVector2Array([Vector2(0, h * 0.89), Vector2(w * 0.2, h * 0.87), Vector2(w * 0.35, h * 0.905), Vector2(w * 0.65, h * 0.905), Vector2(w * 0.8, h * 0.87), Vector2(w, h * 0.89)]), edge, 2.0)
	# Rivets
	for i in 9:
		draw_circle(Vector2(w * (0.25 + i * 0.0625), h * 0.05), 3.0, Color(0.2, 0.22, 0.25))

	# Glass reflections and cracks
	draw_line(Vector2(w * 0.12, h * 0.2), Vector2(w * 0.2, h * 0.12), Color(1, 1, 1, 0.05), 6.0)
	draw_line(Vector2(w * 0.86, h * 0.75), Vector2(w * 0.9, h * 0.68), Color(1, 1, 1, 0.04), 8.0)
	var torso_r: float = parts["torso"] / GameState.max_hp("torso")
	for cr in cracks:
		if torso_r < cr["threshold"]:
			var pts := PackedVector2Array()
			for p: Vector2 in cr["pts"]:
				pts.append(Vector2(p.x * w, p.y * h))
			draw_polyline(pts, Color(0.9, 0.95, 1.0, 0.5), 1.5)

	if hit_flash > 0.0:
		draw_rect(Rect2(-40, -40, w + 80, h + 80), Color(1, 0.1, 0.05, hit_flash * 0.8))
	if torso_r < 0.3 and state == State.PLAYING:
		var pulse := 0.12 + 0.1 * sin(time * 6.0)
		draw_rect(Rect2(-40, -40, w + 80, 70), Color(1, 0, 0, pulse))
		draw_rect(Rect2(-40, h - 30, w + 80, 70), Color(1, 0, 0, pulse))


func _text(t: String, center: Vector2, size: int, c: Color) -> void:
	var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(center.x - tw * 0.5, center.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)


func _draw_hud(w: float, h: float, horizon: float, proj_scale: float) -> void:
	var hud := Color(0.4, 1.0, 0.6)
	var locked := locked_target != null
	var cc := Vector2(w * 0.5, h * 0.5)
	# Horizon ticks so you can tell how far up or down you're looking.
	for sgn in [-1.0, 1.0]:
		draw_line(Vector2(w * 0.5 + sgn * 70.0, horizon), Vector2(w * 0.5 + sgn * 120.0, horizon), Color(0.4, 1.0, 0.6, 0.45), 2.0)
	var ch_col := Color(1.0, 0.3, 0.2) if locked else hud
	draw_arc(cc, 22.0, 0, TAU, 32, ch_col, 2.0)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_line(cc + d * 10.0, cc + d * 30.0, ch_col, 2.0)
	draw_circle(cc, 2.0, ch_col)

	# Objective bar
	var obj := "MISSION %d    HIVES %d/%d    KILLS %d" % [mission_no, hives_destroyed, hives_total, kills]
	_text(obj, Vector2(w * 0.5, h * 0.06), 22, hud)

	# Retreat button
	var rr := _retreat_rect()
	draw_rect(rr, Color(0.15, 0.03, 0.03, 0.85) if retreat_armed > 0.0 else Color(0.05, 0.06, 0.07, 0.8))
	draw_rect(rr, Color(0.8, 0.3, 0.2), false, 2.0)
	_text("TAP AGAIN" if retreat_armed > 0.0 else "RETREAT", rr.get_center() + Vector2(0, 7), 18, Color(1, 0.6, 0.5))

	# Mech status
	var panel := Rect2(16, 72, 150, 150)
	draw_rect(panel, Color(0.02, 0.06, 0.04, 0.75))
	draw_rect(panel, Color(0.2, 0.5, 0.3), false, 1.5)
	var ratios := {}
	for p in GameState.PARTS:
		ratios[p] = parts[p] / GameState.max_hp(p)
	MechDiagram.draw_mech(self, panel.get_center() + Vector2(0, -2), 1.1, ratios, fmod(time, 0.6) < 0.3)

	_draw_minimap(w)

	# Weapon status on the console
	var cy := h * 0.955
	var gun_txt := "CANNON  L %s  R %s" % ["●" if parts["left_arm"] > 0.0 else "✕", "●" if parts["right_arm"] > 0.0 else "✕"]
	_text(gun_txt, Vector2(w * 0.5 - 130, cy), 18, hud)
	var bar := Rect2(w * 0.5 + 10, cy - 15, 180, 16)
	var rk_ready := clampf(1.0 - rocket_cd / GameState.rocket_cooldown(), 0.0, 1.0)
	draw_rect(bar, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * rk_ready, bar.size.y)), Color(1.0, 0.6, 0.15) if rk_ready >= 1.0 else Color(0.5, 0.35, 0.15))
	draw_rect(bar, hud, false, 1.0)
	_text("ROCKETS READY" if rk_ready >= 1.0 else "RELOADING", bar.get_center() + Vector2(0, 30), 14, hud)

	# Messages
	if msg_t > 0.0 and state == State.PLAYING:
		var a := clampf(msg_t, 0.0, 1.0)
		_text(msg, Vector2(w * 0.5, h * 0.24), 30, Color(1.0, 0.85, 0.3, a))
	if parts["torso"] / GameState.max_hp("torso") < 0.3 and state == State.PLAYING and fmod(time, 0.8) < 0.5:
		_text("HULL CRITICAL", Vector2(w * 0.5, h * 0.15), 26, Color(1, 0.2, 0.15))

	# Hit direction markers
	for d in dmg_indicators:
		var v := Vector2(sin(d["rel"]), -cos(d["rel"]))
		var p := cc + Vector2(v.x * w * 0.3, v.y * h * 0.3)
		var n := Vector2(-v.y, v.x)
		var a2: float = clampf(d["t"], 0.0, 1.0)
		draw_colored_polygon(PackedVector2Array([p + v * 22.0, p - v * 6.0 + n * 26.0, p - v * 6.0 - n * 26.0]), Color(1, 0.15, 0.1, a2 * 0.85))

	if time < 9.0 and state == State.PLAYING:
		var fade := clampf(9.0 - time, 0.0, 1.0)
		_text("LEFT THUMB: WALK     RIGHT SIDE: DRAG TO AIM     HOLD FIRE: GUNS", Vector2(w * 0.5, h * 0.82), 18, Color(1, 1, 1, 0.7 * fade))


func _draw_minimap(w: float) -> void:
	var mm := Rect2(w - 206, 14, 190, 190)
	draw_rect(mm, Color(0.02, 0.07, 0.05, 0.85))
	var radius := 9
	var cs := mm.size.x / (2.0 * radius)
	var center := mm.get_center()
	var pc := Vector2i(int(floor(pos.x)), int(floor(pos.y)))
	for gy in range(pc.y - radius - 1, pc.y + radius + 2):
		for gx in range(pc.x - radius - 1, pc.x + radius + 2):
			if not map.in_bounds(gx, gy):
				continue
			var k := map.kind_of(gx, gy)
			var hh := map.cell_h(gx, gy)
			var c := Color(0, 0, 0, 0)
			match k:
				LevelMap.RUIN:
					c = Color(0.35, 0.45, 0.38) if hh - map.terrain[map.idx(gx, gy)] > 1.5 else Color(0.55, 0.6, 0.45)
				LevelMap.METAL:
					c = Color(0.3, 0.38, 0.48)
				LevelMap.ORGANIC:
					c = Color(0.55, 0.16, 0.42)
				LevelMap.PLATFORM:
					c = Color(0.45, 0.5, 0.6, 0.55 + clampf(hh * 0.15, 0.0, 0.4))
				_:
					if hh > 0.01:
						c = Color(0.3, 0.5, 0.3, clampf(hh * 0.4, 0.1, 0.35))
					elif hh < -0.01:
						c = Color(0, 0, 0, 0.55)
			if c.a <= 0.0:
				continue
			var r := Rect2(center + (Vector2(gx, gy) - pos) * cs, Vector2(cs, cs)).intersection(mm)
			if r.has_area():
				draw_rect(r, c)
	for a in aliens:
		if a["dead"]:
			continue
		var rel: Vector2 = a["pos"] - pos
		if absf(rel.x) > radius - 0.3 or absf(rel.y) > radius - 0.3:
			continue
		var p := center + rel * cs
		if a["kind"] == "hive":
			var pulse := 6.0 + 2.0 * sin(time * 4.0)
			draw_rect(Rect2(p - Vector2(pulse, pulse), Vector2(pulse, pulse) * 2.0), Color(0.9, 0.3, 1.0))
		else:
			draw_circle(p, 3.5 if a["kind"] != "brute" else 5.5, Color(1.0, 0.25, 0.2) if a["awake"] else Color(0.8, 0.55, 0.2))
	# Off-screen hive arrows so the player always knows where to go.
	for a in aliens:
		if a["dead"] or a["kind"] != "hive":
			continue
		var rel2: Vector2 = a["pos"] - pos
		if absf(rel2.x) <= radius - 0.3 and absf(rel2.y) <= radius - 0.3:
			continue
		var v := rel2.normalized()
		var edge := center + v * (mm.size.x * 0.5 - 8.0)
		draw_colored_polygon(PackedVector2Array([edge + v * 7.0, edge - v * 5.0 + v.orthogonal() * 6.0, edge - v * 5.0 - v.orthogonal() * 6.0]), Color(0.9, 0.3, 1.0))
	var fwd := Vector2.from_angle(angle)
	var fov := atan(FOV_PLANE)
	draw_line(center, center + fwd.rotated(-fov) * 40.0, Color(0.4, 1.0, 0.6, 0.35), 1.0)
	draw_line(center, center + fwd.rotated(fov) * 40.0, Color(0.4, 1.0, 0.6, 0.35), 1.0)
	draw_colored_polygon(PackedVector2Array([center + fwd * 10.0, center + fwd.rotated(2.4) * 7.0, center + fwd.rotated(-2.4) * 7.0]), Color(0.4, 1.0, 0.6))
	draw_rect(mm, Color(0.2, 0.5, 0.3), false, 2.0)
	# Altitude readout under the minimap.
	_text("ELEV %+.1f" % floor_z, Vector2(mm.get_center().x, mm.end.y + 20.0), 15, Color(0.4, 1.0, 0.6, 0.8))


func _draw_touch_controls(w: float, h: float) -> void:
	if move_touch >= 0:
		draw_arc(move_origin, JOY_RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.3), 3.0)
		draw_circle(move_origin + move_vec * JOY_RADIUS, 34.0, Color(1, 1, 1, 0.25))
	else:
		var hint := Vector2(170, h - 175)
		draw_arc(hint, JOY_RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.12), 2.0)
		_text("MOVE", hint + Vector2(0, 7), 18, Color(1, 1, 1, 0.25))

	var fc := _fire_center(Vector2(w, h))
	draw_circle(fc, FIRE_R, Color(0.9, 0.15, 0.1, 0.55 if fire_touch >= 0 else 0.3))
	draw_arc(fc, FIRE_R, 0, TAU, 48, Color(1, 0.5, 0.4, 0.8), 3.0)
	_text("FIRE", fc + Vector2(0, 9), 26, Color(1, 1, 1, 0.85))

	var rc := _rocket_center(Vector2(w, h))
	var rk_ready := clampf(1.0 - rocket_cd / GameState.rocket_cooldown(), 0.0, 1.0)
	draw_circle(rc, ROCKET_R, Color(1.0, 0.55, 0.1, 0.4 if rk_ready >= 1.0 else 0.15))
	draw_arc(rc, ROCKET_R, -PI * 0.5, -PI * 0.5 + TAU * rk_ready, 40, Color(1, 0.75, 0.3, 0.9), 4.0)
	_text("RKT", rc + Vector2(0, 7), 20, Color(1, 1, 1, 0.85 if rk_ready >= 1.0 else 0.4))


func _draw_end_screen(w: float, h: float) -> void:
	var k := clampf(end_time / 0.8, 0.0, 1.0)
	draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.6 * k))
	var title := "HIVES DESTROYED"
	var col := Color(0.4, 1.0, 0.6)
	if state == State.LOST:
		title = "MECH DOWN"
		col = Color(1.0, 0.3, 0.2)
	elif state == State.RETREATED:
		title = "RETREATED"
		col = Color(1.0, 0.8, 0.3)
	col.a = k
	_text(title, Vector2(w * 0.5, h * 0.36), 54, col)
	var r: Dictionary = GameState.last_result
	var lines := [
		"Aliens killed: %d" % kills,
		"Hives destroyed: %d / %d" % [hives_destroyed, hives_total],
		"Credits earned: +%d     Salvage: +%d" % [r.get("credits", 0), r.get("salvage", 0)],
	]
	if state == State.LOST:
		lines.append("The recovery crew dragged your mech back to the hangar.")
	for i in lines.size():
		_text(lines[i], Vector2(w * 0.5, h * 0.48 + i * 38), 24, Color(1, 1, 1, k))
	if end_time > 1.2:
		var blink := 0.5 + 0.5 * sin(time * 4.0)
		_text("TAP TO RETURN TO THE HANGAR", Vector2(w * 0.5, h * 0.8), 24, Color(1, 0.85, 0.3, blink))
