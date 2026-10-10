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
const Story = preload("res://scripts/story.gd")
const ModelArt = preload("res://scripts/battle/model_art.gd")
const Themes = preload("res://scripts/battle/themes.gd")
const SettingsScript = preload("res://scripts/settings.gd")

# --- View ---------------------------------------------------------------------
var COLUMNS := 200            ## rays per frame (from Settings: graphics quality)
const FOV_PLANE := 0.66       ## ~66 degree field of view
const EYE := 1.25             ## cockpit eye height above the mech's feet
const MAX_VIEW := 22.0
const FOG_DIST := 15.0
# Colours come from the zone's theme (themes.gd), set in _ready().
var FOG := Color(0.24, 0.12, 0.13)
var FACE_COLORS := {
	LevelMap.EMPTY: Color(0.38, 0.25, 0.2),      # dirt terraces and crater walls
	LevelMap.RUIN: Color(0.58, 0.52, 0.45),
	LevelMap.METAL: Color(0.42, 0.48, 0.56),
	LevelMap.ORGANIC: Color(0.55, 0.2, 0.42),
	LevelMap.PLATFORM: Color(0.5, 0.5, 0.53),
	LevelMap.RUBBLE: Color(0.42, 0.37, 0.33),
}
var GROUND_TOP := Color(0.27, 0.15, 0.13)
var PLATFORM_TOP := Color(0.36, 0.36, 0.39)
var zone_theme := {}
var tint := Color.WHITE       ## light colour on sprites
var weather := "none"
var survival := false         ## endless waves, infinite ammo, just for fun
var best_before := {}
var new_best := false
var paused := false
var pause_layer: CanvasLayer

# --- Salvage, harvesting and the Chest -----------------------------------------
## Everything you bring home has to go into the Chest: Mags's cargo walker
## that follows Brigid around. Scrap and circuits are carried by hand,
## biomass is cut out of alien carcasses in the hazmat suit, and survivors
## follow you to the Chest and strap in.
const CHEST_R := 0.45
const CHEST_REACH := 1.9
const HARVEST_TIME := 2.0
const BIOMASS_YIELD := {"crawler": 2, "spitter": 2, "flyer": 1, "brute": 6, "burrower": 4, "hive": 12, "mother": 40}
const CARRY_NAMES := {"scrap": "SCRAP", "circuits": "CIRCUITS", "biomass": "BIOMASS", "cargo": "CARGO"}
var chest := {}
var corpses: Array = []
var pickups: Array = []
var carrying := {}            ## {} or {"kind", "amount", "model", "item"}
var hazmat := false
var harvest_t := 0.0
var harvest_target = null
var hands_msg_cd := 0.0
var jump_z := 0.0             ## height above the ground while jumping (on foot)
var jump_v := 0.0
var want_jump := false
const MAX_JARS := 6
## The harvest team: volunteers riding in the Chest who climb out in hazmat
## suits and cut biomass from nearby carcasses whenever the area is quiet.
const CREW_COUNT := 3
const CREW_CUT_TIME := 4.0
var crew: Array = []
var chest_still_t := 0.0
var crew_told := false

# --- Controls -----------------------------------------------------------------
const MECH_R := LevelMap.MECH_R
const PILOT_R := 0.15
const PILOT_EYE := 0.55
const PILOT_WALK := 2.2
const PILOT_RUN := 3.8
const PILOT_STEP := 0.65     ## the pilot climbs anything Brigid can
const JUMP_V := 5.2
const GRAVITY := 15.0
const BOARD_DIST := 1.6
const CLIMB_TIME := 1.3
const DROP_TIME := 2.6
const LIFT_TIME := 2.2
const PICKUP_TIME := 8.0
const LZ_RADIUS := 2.5
const BEACON_TIME := 3.0
const KEY_TURN_SPEED := 2.4
var LOOK_SENS := 0.0065
var PITCH_SENS := 0.9         ## screen pixels of look per pixel of finger drag
const PITCH_LIMIT := 0.7      ## max look up/down, as a fraction of screen height
const JOY_RADIUS := 90.0
const FIRE_R := 78.0
const ROCKET_R := 52.0

# --- Aliens -------------------------------------------------------------------
const ALIEN_TYPES := {
	"crawler": {"hp": 30.0, "speed": 2.4, "dmg": 6.0, "range": 0.9, "cd": 0.8, "w": 1.0, "h": 0.9, "r": 0.25},
	"spitter": {"hp": 45.0, "speed": 1.5, "dmg": 9.0, "range": 7.0, "cd": 2.2, "w": 0.85, "h": 1.15, "r": 0.25},
	"brute": {"hp": 170.0, "speed": 1.15, "dmg": 18.0, "range": 1.25, "cd": 1.5, "w": 1.6, "h": 1.8, "r": 0.4},
	## Flies over walls at rooftop height, then dives at your cockpit.
	"flyer": {"hp": 22.0, "speed": 3.4, "dmg": 6.0, "range": 0.9, "cd": 1.0, "w": 1.0, "h": 0.8, "r": 0.25, "hover": 2.8},
	## Tunnels under everything, then bursts out of the ground beside you.
	"burrower": {"hp": 95.0, "speed": 1.6, "dmg": 13.0, "range": 1.1, "cd": 1.3, "w": 1.4, "h": 1.1, "r": 0.35, "dig": 2.7},
	"hive": {"hp": 300.0, "speed": 0.0, "dmg": 0.0, "range": 0.0, "cd": 5.0, "w": 2.0, "h": 1.7, "r": 0.5},
	"mother": {"hp": 1500.0, "speed": 0.0, "dmg": 0.0, "range": 0.0, "cd": 3.0, "w": 3.8, "h": 3.2, "r": 0.9},
}

enum State { PLAYING, WON, LOST, RETREATED }

var state := State.PLAYING
var map: LevelMap
var tex := {}
var tex3d := {}               ## 3D-rendered sprites: kind -> {"L", "dirs": [dir][frame]}
var font: Font
var rng := RandomNumberGenerator.new()

var pos := Vector2()
var angle := 0.0
var floor_z := 0.0            ## height of the ground under the mech (smoothed)
var eye_z := EYE
var falling := false
var body_r := MECH_R          ## collision radius of whatever you're in
var eye_h := EYE              ## eye height above the ground under you
var on_foot := false
var mech_pos := Vector2()     ## where the empty mech is parked
var mech_angle := 0.0
var mech_fz := 0.0
var pilot_hp := 40.0
var pilot_max_hp := 40.0
var pilot_down := false
var climb_t := 0.0            ## > 0 while climbing out of or into the mech
var climb_out := true
var climb_from := {}
var climb_to := {}
var caches: Array = []
var caches_found := 0

# --- Mission ------------------------------------------------------------------
var op := {}
var mtype := "destroy"
var diff := 1
var phase := "drop"           ## drop → fight → extract → lift
var drop_t := DROP_TIME
var lift_t := 0.0
var pickup_t := 0.0
var objective_done := false
var lz := Vector2()
var survivors_list: Array = []
var rescued := 0
var rescue_total := 0
var cargo: Array = []
var items_got := 0
var beacons: Array = []
var beacons_done := 0
var waves_total := 0
var wave := 0
var wave_timer := 0.0
var wave_pause := 3.0
var breaches: Array = []
var loot := {"scrap": 0, "circuits": 0, "biomass": 0, "shells": 0, "rockets": 0, "rounds": 0}
var ammo_left := {"shells": 0, "rockets": 0, "rounds": 0}
var radio_who := ""
var radio_text := ""
var radio_t := 0.0
var no_ammo_cd := 0.0
var aborted := false
var running := false
var told_foot := false
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
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	op = GameState.current_mission
	if op.is_empty():
		# Started the battle scene directly (testing): make a quick mission.
		op = {"title": "Test Drop", "zone": "Test Range", "type": "destroy", "hives": 1, "diff": 1, "seed": 7}
	mtype = op.get("type", "destroy")
	diff = int(op.get("diff", 1))
	survival = mtype == "endless"
	best_before = GameState.survival_best.duplicate()
	rng.seed = int(op.get("seed", 7)) + 99
	COLUMNS = Settings.columns()
	LOOK_SENS *= Settings.look_sensitivity
	PITCH_SENS *= Settings.look_sensitivity
	_apply_theme(Themes.pick(int(op.get("theme_seed", op.get("seed", 7)))))
	tex = AlienArt.build_all()
	tex3d = ModelArt.build_all()
	pilot_max_hp = GameState.pilot_max_hp()
	pilot_hp = pilot_max_hp
	for a in GameState.AMMO:
		ammo_left[a] = int(GameState.loadout.get(a, GameState.ammo_caps()[a] if GameState.current_mission.is_empty() else 0))

	map = LevelMap.new()
	var nest_count: int = op.get("hives", 0) + (1 if mtype == "boss" else 0)
	map.generate(int(op.get("seed", 7)), nest_count, String(zone_theme["layout"]))
	if zone_theme.get("organic_extra", false):
		# The swarm has grown over everything here.
		for i in map.kinds.size():
			if map.kinds[i] == LevelMap.RUIN and map.hard[i] == 0 and rng.randf() < 0.35:
				map.kinds[i] = LevelMap.ORGANIC
				map.wall_hp[i] = 1
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

	for i in map.hive_cells.size():
		var hc: Vector2i = map.hive_cells[i]
		_spawn("mother" if mtype == "boss" and i == 0 else "hive", Vector2(hc) + Vector2(0.5, 0.5), false)
	var nests := map.nest_cells.duplicate()
	for i in range(nests.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = nests[i]
		nests[i] = nests[j]
		nests[j] = tmp
	var count := mini(3 + diff * 2, nests.size())
	for i in count:
		var c: Vector2i = nests[i]
		_spawn(_pick_kind(), Vector2(c) + Vector2(rng.randf_range(0.3, 0.7), rng.randf_range(0.3, 0.7)), false)
	_place_props()

	_setup_mission()
	if not survival:
		_spawn_chest()

	_build_backdrop()
	col_events.resize(COLUMNS)
	for c in COLUMNS:
		col_events[c] = PackedFloat32Array()
	_update_flow()
	if survival:
		_show_msg("SURVIVAL — " + String(zone_theme["name"]).to_upper(), 4.0)
	else:
		_show_msg(String(op.get("title", "")).to_upper() + " — " + GameState.objective_text(op).to_upper(), 4.0)
	_radio("drop")
	Sfx.play("rocket", -4.0, 0.0, 0.6)
	_build_pause_menu()


func _apply_theme(t: Dictionary) -> void:
	zone_theme = t
	FOG = t["fog"]
	var walls: Dictionary = t["walls"]
	FACE_COLORS = {
		LevelMap.EMPTY: walls["empty"], LevelMap.RUIN: walls["ruin"], LevelMap.METAL: walls["metal"],
		LevelMap.ORGANIC: walls["organic"], LevelMap.PLATFORM: walls["platform"], LevelMap.RUBBLE: walls["rubble"],
	}
	GROUND_TOP = t["ground_top"]
	PLATFORM_TOP = t["platform_top"]
	tint = t["tint"]
	weather = t["weather"]


const SOLID_PROPS := {"car": 0.75, "barrel": 0.3, "tree": 0.35, "pine": 0.3}


func _place_props() -> void:
	## Scenery for the zone's theme: trees, wrecked cars, barrels, rocks.
	var kinds_list: Array = zone_theme["props"]
	var spots: Array = map.prop_spots.duplicate()
	var density: float = zone_theme.get("prop_density", 1.0)
	var extra := int(spots.size() * maxf(density - 1.0, 0.0))
	for i in extra * 4:
		if extra <= 0:
			break
		var x := rng.randi_range(1, map.w - 2)
		var y := rng.randi_range(1, map.h - 2)
		if map.kinds[map.idx(x, y)] != LevelMap.EMPTY:
			continue
		var sp := Vector2(x + rng.randf_range(0.25, 0.75), y + rng.randf_range(0.25, 0.75))
		if sp.distance_to(map.start) < 3.0:
			continue
		spots.append(sp)
		extra -= 1
	for sp: Vector2 in spots:
		var near_cache := false
		for c: Vector2 in map.cache_spots:
			if c.distance_to(sp) < 1.5:
				near_cache = true
		var kind: String = kinds_list[rng.randi_range(0, kinds_list.size() - 1)]
		if (near_cache or sp.distance_to(map.start) < 4.0) and SOLID_PROPS.has(kind):
			kind = "rock"
		props.append({"pos": sp, "z": map.height_at(sp), "kind": kind, "face": rng.randf() * TAU, "crushed": false})


func _crush_props() -> void:
	## Brigid walks through scenery: cars crumple, trees fall, barrels go up.
	for p in props:
		if p.get("crushed", false) or not SOLID_PROPS.has(p["kind"]):
			continue
		if pos.distance_to(p["pos"]) > MECH_R + float(SOLID_PROPS[p["kind"]]) * 0.6:
			continue
		_wreck_prop(p)


func _wreck_prop(p: Dictionary) -> void:
	p["crushed"] = true
	var pp: Vector2 = p["pos"]
	match p["kind"]:
		"barrel":
			explosions.append({"pos": pp, "z": p["z"] + 0.5, "t": 0.0, "dur": 0.8, "size": 1.1, "col": Color(1.0, 0.55, 0.15)})
			Sfx.play("boom", -4.0, 0.15)
			shake = maxf(shake, 6.0)
			for a in aliens:
				if not a["dead"] and a["pos"].distance_to(pp) < 2.2:
					_damage_alien(a, 60.0)
		"car":
			if not survival:
				_drop_pickup(pp + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3)), "scrap", rng.randi_range(4, 8))
			Sfx.play("hit", -2.0, 0.1, 0.6)
			shake = maxf(shake, 4.0)
			explosions.append({"pos": pp, "z": p["z"] + 0.3, "t": 0.0, "dur": 0.7, "size": 0.6, "col": Color(0.5, 0.48, 0.45), "smoke": true})
		_:
			Sfx.play("hit", -4.0, 0.1, 0.5)
			explosions.append({"pos": pp, "z": p["z"] + 1.5, "t": 0.0, "dur": 0.9, "size": 1.0, "col": Color(0.3, 0.45, 0.2), "smoke": true})

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
	var m := diff
	var r := rng.randf()
	var t := 0.0
	if m >= 2:
		t = 0.06 + 0.03 * m
		if r < t:
			return "brute"
		t += 0.12
		if r < t:
			return "flyer"
		t += 0.08
		if r < t:
			return "burrower"
	if r < t + 0.3:
		return "spitter"
	return "crawler"


func _spawn(kind: String, p: Vector2, awake: bool) -> Dictionary:
	var st: Dictionary = ALIEN_TYPES[kind]
	var hp: float = st["hp"] * (1.0 + 0.08 * (diff - 1))
	var a := {
		"kind": kind, "pos": p, "fz": map.height_at(p), "hp": hp, "max": hp, "awake": awake,
		"cd": rng.randf_range(0.5, 2.0) if kind == "hive" or kind == "mother" else 0.5, "anim": rng.randf() * 10.0,
		"flash": 0.0, "dead": false, "death_t": 0.0, "lunge": 0.0, "moving": false,
		"seed": rng.randf() * TAU, "st": st, "face": rng.randf() * TAU,
	}
	match kind:
		"flyer":
			a["mode"] = "cruise"
			a["mode_t"] = 0.0
			a["fz"] = map.height_at(p) + 0.6
		"burrower":
			a["under"] = true
			a["emerge"] = 0.0
			a["sink"] = 0.0
			a["up_t"] = 0.0
			a["dig_t"] = 0.0
			a["fz"] = map.height_at(p) - st["h"]
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
	horizon_y = vh * 0.5 + pitch + sin(bob_t * 2.0) * (11.0 if on_foot else 7.0) * bob_amount
	radio_t -= delta
	no_ammo_cd -= delta
	if state == State.PLAYING:
		if phase == "drop":
			_update_drop(delta)
		elif phase == "lift":
			_update_lift(delta)
		elif climb_t > 0.0:
			_update_climb(delta)
		else:
			if harvest_t > 0.0:
				_update_harvest(delta)
			else:
				_update_player(delta)
				_update_weapons(delta)
		if not chest.is_empty() and phase != "drop" and phase != "lift":
			_update_chest(delta)
		if phase != "drop" and phase != "lift":
			_update_mission(delta)
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
	# The dead stay where they fell: that's where the biomass is.
	for a in aliens:
		if a["dead"] and a["death_t"] > 0.7:
			corpses.append({"kind": a["kind"], "pos": a["pos"], "z": map.height_at(a["pos"]), "face": a["face"],
				"harvested": false, "seed": a["seed"]})
	aliens = aliens.filter(func(a): return not (a["dead"] and a["death_t"] > 0.7))
	if corpses.size() > 140:
		corpses = corpses.slice(corpses.size() - 140)
	hands_msg_cd -= delta
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
	var step_h := LevelMap.STEP
	if on_foot:
		running = move_vec.length() > 0.85 or Input.is_physical_key_pressed(KEY_SHIFT)
		speed = PILOT_RUN if running else PILOT_WALK
		step_h = PILOT_STEP
	var mv := inp * speed * delta
	var stand := map.height_at(pos)
	if on_foot:
		if want_jump and jump_z <= 0.0 and not falling:
			jump_v = JUMP_V
			jump_z = 0.001
			Sfx.play("step", -10.0, 0.1, 1.6)
		want_jump = false
		if jump_z > 0.0:
			jump_v -= GRAVITY * delta
			jump_z += jump_v * delta
			# In the air you clear whatever you've jumped above.
			stand = maxf(stand, floor_z + jump_z)
	var nx := pos + Vector2(mv.x, 0.0)
	if not map.blocked(nx, body_r, stand, step_h) and not _parked_mech_blocks(nx, body_r) and not (_chest_blocks(nx, body_r) and not _chest_blocks(pos, body_r)):
		pos = nx
	var ny := pos + Vector2(0.0, mv.y)
	if not map.blocked(ny, body_r, stand, step_h) and not _parked_mech_blocks(ny, body_r) and not (_chest_blocks(ny, body_r) and not _chest_blocks(pos, body_r)):
		pos = ny

	# Climb steps smoothly; drop off ledges with a heavy landing.
	var target := map.height_at(pos)
	if jump_z > 0.0:
		if target > floor_z:
			# Landed on something higher: the jump height becomes floor.
			jump_z = maxf(0.0, jump_z - (target - floor_z))
			floor_z = target
		if jump_z <= 0.0 or (jump_v < 0.0 and floor_z + jump_z <= target):
			jump_z = 0.0
			jump_v = 0.0
			Sfx.play("step", -8.0, 0.1, 1.3)
	if target < floor_z - 0.3 and jump_z <= 0.0:
		falling = true
	if target > floor_z:
		floor_z = move_toward(floor_z, target, delta * 3.0)
	else:
		floor_z = move_toward(floor_z, target, delta * 7.0)
	if falling and absf(floor_z - target) < 0.01:
		falling = false
		shake = maxf(shake, 12.0)
		Sfx.play("step", -1.0)
	eye_z = floor_z + eye_h + jump_z
	_check_caches()
	if not on_foot:
		_crush_props()

	var moving := inp.length()
	bob_amount = lerpf(bob_amount, moving, minf(1.0, delta * 6.0))
	if moving > 0.1:
		var prev := bob_t
		bob_t += delta * speed * 2.2
		if floor(prev / PI) != floor(bob_t / PI):
			if on_foot:
				Sfx.play("step", -15.0 if not running else -12.0, 0.1, 1.9)
			else:
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
		if on_foot:
			_fire_carbine()
		else:
			_fire_cannon()
	if not on_foot and (Input.is_physical_key_pressed(KEY_R) or Input.is_physical_key_pressed(KEY_F)):
		_fire_rocket()


func _fire_cannon() -> void:
	var guns: Array[int] = []
	if parts["left_arm"] > 0.0: guns.append(0)
	if parts["right_arm"] > 0.0: guns.append(1)
	if guns.is_empty():
		fire_cd = 0.4
		_show_msg("BOTH ARMS DESTROYED — USE ROCKETS", 1.0)
		return
	if ammo_left["shells"] <= 0:
		_out_of_ammo()
		fire_cd = 0.3
		return
	if not survival:
		ammo_left["shells"] -= 1
	var g: int = next_gun if guns.has(next_gun) else guns[0]
	next_gun = 1 - g
	fire_cd = 0.11 if guns.size() == 2 else 0.17
	muzzle[g] = 0.06
	recoil[g] = 1.0
	shake = maxf(shake, 1.5)
	Sfx.play("gun", -5.0)

	_shoot(Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0)), GameState.cannon_damage(), g)


func _fire_carbine() -> void:
	if not carrying.is_empty():
		fire_cd = 0.4
		if hands_msg_cd <= 0.0:
			hands_msg_cd = 2.0
			_show_msg("HANDS FULL — DROP IT OR TAKE IT TO THE CHEST", 1.6)
		return
	if ammo_left["rounds"] <= 0:
		_out_of_ammo()
		fire_cd = 0.3
		return
	if not survival:
		ammo_left["rounds"] -= 1
	fire_cd = 0.16
	muzzle[0] = 0.05
	recoil[0] = 1.0
	shake = maxf(shake, 0.8)
	Sfx.play("gun", -9.0, 0.05, 1.7)
	_shoot(Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(-4.0, 4.0)), GameState.carbine_damage(), 2)


func _shoot(spread: Vector2, damage: float, g: int) -> void:
	## One hitscan shot along the crosshair. g: 0/1 = mech arms, 2 = carbine.
	# The shot goes exactly where the crosshair points (screen centre),
	# with a few pixels of random spread.
	var target = _find_target(spread)
	var hit_point: Vector2
	var hit_z := eye_z
	if target != null:
		_damage_alien(target, damage)
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
	if rocket_cd > 0.0 or state != State.PLAYING or on_foot or climb_t > 0.0 or phase == "drop" or phase == "lift":
		return
	if ammo_left["rockets"] <= 0:
		_out_of_ammo()
		rocket_cd = 0.5
		return
	if not survival:
		ammo_left["rockets"] -= 1
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
		if a["dead"] or a.get("under", false):
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
	if a.get("under", false) or a.get("emerge", 0.0) > 0.0 or a.get("sink", 0.0) > 0.0:
		# Killed in its tunnel: the body is thrown up with the dirt.
		a["under"] = false
		a["emerge"] = 0.0
		a["sink"] = 0.0
		a["fz"] = map.height_at(a["pos"])
		_dirt_burst(a["pos"], 4)
	if _is_nest(a):
		hives_destroyed += 1
		for i in 5:
			var off := Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
			explosions.append({"pos": a["pos"] + off, "z": a["fz"] + rng.randf_range(0.3, 1.4), "t": -i * 0.08, "dur": 0.9, "size": 1.6, "col": Color(1.0, 0.45, 0.2)})
		Sfx.play("boom", 0.0)
		Sfx.play("screech", -2.0, 0.3)
		shake = maxf(shake, 14.0)
		var left := hives_total - hives_destroyed
		_show_msg(("BROOD MOTHER KILLED" if a["kind"] == "mother" else "HIVE DESTROYED") + ("" if left <= 0 or mtype == "destroy" or mtype == "boss" else " — %d LEFT" % left), 2.5)
		_radio("hive")
	else:
		kills += 1
		if a["kind"] == "brute":
			brutes += 1
		explosions.append({"pos": a["pos"], "z": a["fz"] + st["h"] * 0.5, "t": 0.0, "dur": 0.45, "size": st["w"] * 0.9, "col": Color(0.5, 0.95, 0.2)})
		Sfx.play("splat", -3.0)


func _damage_player(amount: float, src: Vector2) -> void:
	if state != State.PLAYING or phase == "drop" or phase == "lift":
		return
	var rel := wrapf((src - pos).angle() - angle, -PI, PI)
	if on_foot:
		if harvest_t > 0.0:
			harvest_t = 0.0
			harvest_target = null
			_show_msg("HARVEST INTERRUPTED", 1.5)
		pilot_hp = maxf(0.0, pilot_hp - amount)
		hit_flash = 0.3
		shake = maxf(shake, 6.0)
		dmg_indicators.append({"rel": rel, "t": 0.9})
		Sfx.play("hit", -7.0, 0.1, 1.5)
		return
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
	if part == "torso" and parts["torso"] / GameState.max_hp("torso") < 0.3 and not get_meta("warned_armor", false):
		set_meta("warned_armor", true)
		_radio("low_armor")
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
		if a["kind"] == "flyer":
			a["fz"] = move_toward(a["fz"], map.height_at(a["pos"]), delta * 7.0)
		return
	a["cd"] -= delta
	if a["kind"] == "flyer":
		_update_flyer(a, delta)
		return
	if a["kind"] == "burrower" and (a["under"] or a["emerge"] > 0.0 or a["sink"] > 0.0):
		_update_burrower(a, delta)
		return
	a["fz"] = move_toward(a["fz"], map.height_at(a["pos"]), delta * 5.0)
	if a["kind"] == "burrower":
		# On the surface: fight, and dig back down if you get away.
		a["up_t"] += delta
		if a["up_t"] > 7.0 and pos.distance_to(a["pos"]) > 5.5:
			a["sink"] = 0.8
			_dirt_burst(a["pos"], 4)
			return
	var to_p: Vector2 = pos - a["pos"]
	var dist := to_p.length()
	var st: Dictionary = a["st"]
	var dmg_mul := 1.0 + 0.06 * (diff - 1)
	var a_eye: float = a["fz"] + st["h"] * 0.8

	if _is_nest(a):
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
	elif los and same_level and dist < st["range"] + body_r + 0.1:
		if a["cd"] <= 0.0:
			_damage_player(st["dmg"] * dmg_mul, a["pos"])
			a["cd"] = st["cd"]
			a["lunge"] = 0.25
	elif los and same_level and dist < 6.0:
		move_dir = to_p / dist
	else:
		move_dir = _flow_dir(a["pos"])

	for b in aliens:
		if b == a or b["dead"] or _is_nest(b):
			continue
		var off: Vector2 = a["pos"] - b["pos"]
		var l := off.length()
		if l < 0.6 and l > 0.001:
			move_dir += off / l * (0.6 - l) * 2.0

	var step: Vector2 = move_dir.limit_length(1.0) * st["speed"] * speed_mul * delta
	a["moving"] = step.length() > 0.0005
	# Turn to face where we're going, or the player when standing.
	var want: float = step.angle() if a["moving"] and a["kind"] != "spitter" else to_p.angle()
	a["face"] = lerp_angle(a["face"], want, minf(1.0, delta * 8.0))
	var r: float = st["r"]
	var stand := map.height_at(a["pos"])
	var nx: Vector2 = a["pos"] + Vector2(step.x, 0.0)
	if not map.blocked(nx, r, stand) and nx.distance_to(pos) > r + body_r and not _parked_mech_blocks(nx, r):
		a["pos"] = nx
	var ny: Vector2 = a["pos"] + Vector2(0.0, step.y)
	if not map.blocked(ny, r, stand) and ny.distance_to(pos) > r + body_r and not _parked_mech_blocks(ny, r):
		a["pos"] = ny


func _first_sighting(kind: String) -> void:
	if get_meta("seen_" + kind, false):
		return
	set_meta("seen_" + kind, true)
	if kind == "flyer":
		_radio_line("pip", "Flyers! Up high, over the rooftops. Look up, Wren!")
	elif kind == "burrower":
		_radio_line("sandoval", "Seismic contact. Something is digging toward you. Rockets will flush it out.")


func _update_flyer(a: Dictionary, delta: float) -> void:
	## Cruises over the rooftops, weaving, then dives at the cockpit and
	## climbs away after the hit.
	var st: Dictionary = a["st"]
	var to_p: Vector2 = pos - a["pos"]
	var dist := to_p.length()
	var ground := map.height_at(a["pos"])
	if not a["awake"]:
		a["moving"] = false
		a["fz"] = move_toward(a["fz"], ground + st["hover"], delta * 1.5)
		if dist < 11.0:
			a["awake"] = true
			_first_sighting("flyer")
			Sfx.play("screech", lerpf(-6.0, -16.0, dist / 11.0), 0.3, 1.6)
		return
	a["mode_t"] -= delta
	var dir := to_p / maxf(dist, 0.001)
	var move := Vector2.ZERO
	var speed: float = st["speed"]
	# Fly high enough to clear whatever is underneath and just ahead.
	var ahead: Vector2 = a["pos"] + dir * 0.9
	var clear := maxf(ground, map.height_at(ahead)) + 0.4
	var cruise_z := maxf(clear, ground + st["hover"])
	var want_z := cruise_z
	match a["mode"]:
		"cruise":
			var weave := Vector2(-dir.y, dir.x) * sin(a["anim"] * 2.3 + a["seed"]) * 0.7
			if dist > 3.0:
				move = dir + weave
			else:
				# Circle around you, waiting for an opening.
				move = Vector2(-dir.y, dir.x) * (1.0 if sin(a["seed"]) > 0.0 else -1.0) + dir * (dist - 2.6) * 0.5
			if dist < 4.0 and a["cd"] <= 0.0:
				a["mode"] = "dive"
				a["mode_t"] = 2.5
				Sfx.play("screech", -6.0, 0.2, 1.8)
		"dive":
			move = dir
			speed *= 1.5
			want_z = maxf(clear, eye_z - 0.55)
			if dist < st["range"] + body_r and absf(a["fz"] + st["h"] * 0.5 - (eye_z - 0.3)) < 1.2:
				_damage_player(st["dmg"] * (1.0 + 0.06 * (diff - 1)), a["pos"])
				a["lunge"] = 0.25
				a["cd"] = st["cd"] * rng.randf_range(1.6, 2.4)
				a["mode"] = "climb"
				a["mode_t"] = 1.2
			elif a["mode_t"] <= 0.0:
				a["mode"] = "climb"
				a["mode_t"] = 0.8
		"climb":
			move = -dir + Vector2(-dir.y, dir.x) * 0.6
			want_z = cruise_z + 0.6
			if a["mode_t"] <= 0.0:
				a["mode"] = "cruise"
	# Keep apart from other flyers.
	for b in aliens:
		if b == a or b["dead"] or b["kind"] != "flyer":
			continue
		var off: Vector2 = a["pos"] - b["pos"]
		var l := off.length()
		if l < 0.8 and l > 0.001:
			move += off / l * (0.8 - l) * 2.0
	var step: Vector2 = move.limit_length(1.0) * speed * delta
	var np: Vector2 = a["pos"] + step
	np.x = clampf(np.x, 1.2, map.w - 1.2)
	np.y = clampf(np.y, 1.2, map.h - 1.2)
	# Never fly into a wall taller than you are: go up first.
	if map.height_at(np) > a["fz"] - 0.1:
		want_z = map.height_at(np) + 0.6
		np = a["pos"]
	if np.distance_to(pos) < body_r + 0.25:
		np = a["pos"]
	a["pos"] = np
	a["fz"] = move_toward(a["fz"], want_z, delta * (4.0 if a["mode"] == "dive" else 2.5))
	a["moving"] = true
	a["face"] = lerp_angle(a["face"], step.angle() if step.length() > 0.0005 else dir.angle(), minf(1.0, delta * 6.0))


func _update_burrower(a: Dictionary, delta: float) -> void:
	## Underground: a mound of churned earth moving straight at you, under
	## walls and all. Bullets can't reach it; rockets can. Close enough, it
	## bursts out of the ground.
	var st: Dictionary = a["st"]
	var ground := map.height_at(a["pos"])
	var to_p: Vector2 = pos - a["pos"]
	var dist := to_p.length()
	if a["sink"] > 0.0:
		a["sink"] -= delta
		a["fz"] = move_toward(a["fz"], ground - st["h"], delta * st["h"] / 0.8)
		if a["sink"] <= 0.0:
			a["under"] = true
			a["dig_t"] = 0.0
		return
	if a["emerge"] > 0.0:
		a["emerge"] -= delta
		a["fz"] = move_toward(a["fz"], ground, delta * st["h"] / 0.5)
		a["face"] = to_p.angle()
		if a["emerge"] <= 0.0:
			a["fz"] = ground
			a["up_t"] = 0.0
			a["cd"] = 0.4
		return
	a["fz"] = ground - st["h"]
	if not a["awake"]:
		a["moving"] = false
		if dist < 10.0:
			a["awake"] = true
		return
	_first_sighting("burrower")
	a["dig_t"] += delta
	var dir := to_p / maxf(dist, 0.001)
	if dist > 1.2:
		var np: Vector2 = a["pos"] + dir * st["dig"] * delta
		np.x = clampf(np.x, 1.2, map.w - 1.2)
		np.y = clampf(np.y, 1.2, map.h - 1.2)
		a["pos"] = np
	a["moving"] = true
	a["face"] = dir.angle()
	# Dirt kicked up along the way, and a rumble you can feel.
	if fmod(a["anim"], 0.18) < delta:
		explosions.append({"pos": a["pos"] - dir * 0.3, "z": ground + 0.1, "t": 0.0, "dur": 0.6, "size": 0.25, "col": Color(0.42, 0.32, 0.22), "smoke": true})
	if fmod(a["anim"], 0.7) < delta and dist < 9.0:
		Sfx.play("step", lerpf(-8.0, -22.0, dist / 9.0), 0.2, 0.45)
		if dist < 4.0:
			shake = maxf(shake, 3.0)
	var stand_ok := not map.blocked(a["pos"], st["r"], ground) and absf(ground - floor_z) < 1.0
	if (dist < 2.3 or a["dig_t"] > 14.0) and stand_ok:
		_burrower_surface(a, true)


func _burrower_surface(a: Dictionary, attack: bool) -> void:
	a["under"] = false
	a["emerge"] = 0.5
	_dirt_burst(a["pos"], 6)
	Sfx.play("boom", -8.0, 0.2, 0.6)
	Sfx.play("screech", -4.0, 0.2, 0.7)
	var d: float = a["pos"].distance_to(pos)
	shake = maxf(shake, 14.0 * clampf(1.0 - d / 6.0, 0.2, 1.0))
	if attack and d < 1.8:
		_damage_player(a["st"]["dmg"] * 1.3, a["pos"])


func _dirt_burst(p: Vector2, n: int) -> void:
	var g := map.height_at(p)
	for i in n:
		var off := Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))
		explosions.append({"pos": p + off, "z": g + rng.randf_range(0.1, 0.9), "t": -i * 0.04, "dur": 0.8, "size": 0.6, "col": Color(0.45, 0.34, 0.24), "smoke": true})


func _update_hive(a: Dictionary, dist: float) -> void:
	if dist < 12.0:
		a["awake"] = true
	if not a["awake"] or a["cd"] > 0.0:
		return
	a["cd"] = maxf(3.5, 7.5 - diff * 0.4)
	if a["kind"] == "mother":
		a["cd"] = maxf(2.0, 4.5 - diff * 0.2)
	var alive := 0
	for b in aliens:
		if not b["dead"] and not _is_nest(b):
			alive += 1
	if alive >= 8 + diff * 2:
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
				if not a.get("under", false) and a["pos"].distance_to(np) < st["r"] + 0.3 and z > a["fz"] - 0.1 and z < a["fz"] + st["h"] + 0.2:
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
			if np.distance_to(pos) < body_r + 0.15 and z > floor_z - 0.2 and z < eye_z + 0.5:
				_damage_player(pr["dmg"], pr["src"])
				pr["life"] = -1.0
				continue
		pr["pos"] = np
	projectiles = projectiles.filter(func(pr): return pr["life"] > 0.0)


func _explode_rocket(p: Vector2, z: float) -> void:
	_blast_terrain(p, z)
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
		if a.get("under", false):
			# The blast shakes diggers loose: it hurts and drives them up.
			if dd < 2.4:
				_damage_alien(a, GameState.rocket_damage() * 0.6 * (1.0 - dd / 2.4 * 0.5))
				if not a["dead"]:
					_burrower_surface(a, false)
			continue
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
	if on_foot and pilot_hp <= 0.0:
		pilot_down = true
		state = State.LOST
		Sfx.play("alarm", 0.0, 0.0)
		shake = 10.0
		_finish()
	elif parts["torso"] <= 0.0:
		state = State.LOST
		explosions.append({"pos": pos + Vector2.from_angle(angle) * 0.6, "z": eye_z - 0.6, "t": 0.0, "dur": 1.0, "size": 1.5, "col": Color(1.0, 0.5, 0.2)})
		Sfx.play("boom", 2.0)
		shake = 22.0
		_finish()
	elif aborted:
		state = State.RETREATED
		_finish()


func _finish() -> void:
	fire_touch = -1
	move_touch = -1
	look_touch = -1
	move_vec = Vector2.ZERO
	if survival:
		new_best = GameState.record_survival(wave, kills)
		return
	GameState.apply_mission_result({
		"won": state == State.WON,
		"aborted": state == State.RETREATED,
		"pilot_down": pilot_down,
		"kills": kills,
		"rescued": rescued,
		"loot": loot.duplicate(),
		"ammo_left": ammo_left.duplicate(),
		"parts": parts.duplicate(),
	})


# --- Missions -------------------------------------------------------------------

var _start_dist := PackedInt32Array()


func _blast_terrain(p: Vector2, z: float) -> void:
	## Rockets level ruins and walls, but they also kill anyone and wreck
	## anything nearby. That's why some jobs are done on foot.
	var result := map.blast(p, 1.3)
	var destroyed: Array = result["destroyed"]
	for c: Vector2i in destroyed:
		var cp := Vector2(c) + Vector2(0.5, 0.5)
		for k in 3:
			var off := Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4))
			explosions.append({"pos": cp + off, "z": map.height_at(cp) + rng.randf_range(0.5, 2.0), "t": -k * 0.07, "dur": 1.1, "size": 0.9, "col": Color(0.55, 0.5, 0.45), "smoke": true})
		props.append({"pos": cp + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3)), "z": map.height_at(cp), "kind": "rock"})
	if not destroyed.is_empty():
		Sfx.play("boom", -2.0, 0.1, 0.7)
		shake = maxf(shake, 12.0)
		_update_flow()
	elif result["hard_hit"] and not get_meta("told_hard", false):
		set_meta("told_hard", true)
		_radio_line("mags", "That's a pre-war blast shelter. Rockets won't scratch it. You'll have to walk in.")
	# Collateral damage.
	for pr in props:
		if not pr.get("crushed", false) and SOLID_PROPS.has(pr["kind"]) and pr["pos"].distance_to(p) < 1.6:
			_wreck_prop(pr)
	for sv in survivors_list:
		if not sv.get("strapped", false) and not sv.get("dead", false) and sv["pos"].distance_to(p) < 2.0:
			sv["dead"] = true
			sv["freed"] = true
			sv["t"] = 99.0
			if not sv.get("stray", false):
				rescue_total -= 1
			_show_msg("A SURVIVOR WAS KILLED IN THE BLAST", 3.0)
			_radio("blast_civilian")
	for it in cargo:
		if not it["taken"] and it["pos"].distance_to(p) < 1.8:
			it["taken"] = true
			it["destroyed"] = true
			_show_msg("CARGO DESTROYED IN THE BLAST", 2.5)
			_radio("cargo_lost")
	for c2 in caches:
		if not c2["taken"] and c2["pos"].distance_to(p) < 1.6:
			c2["taken"] = true
	for b in beacons:
		if not b["done"] and b["pos"].distance_to(p) < 1.4:
			b["prog"] = 0.0


func _radio_line(who: String, text: String) -> void:
	radio_who = who
	radio_text = text
	radio_t = 5.0


func _is_nest_kind(k: String) -> bool:
	return k == "hive" or k == "mother"


func _is_nest(a: Dictionary) -> bool:
	return a["kind"] == "hive" or a["kind"] == "mother"


func _radio(kind: String) -> void:
	var lines: Array = Story.RADIO.get(kind, [])
	if lines.is_empty():
		return
	var line: Array = lines[rng.randi_range(0, lines.size() - 1)]
	radio_who = line[0]
	radio_text = line[1]
	radio_t = 5.0


func _out_of_ammo() -> void:
	Sfx.play("click", -2.0)
	if no_ammo_cd <= 0.0:
		no_ammo_cd = 6.0
		_radio("no_ammo")
		_show_msg("OUT OF AMMO", 1.5)


func _pick_cells(count: int, need_mech: bool, min_dist: int, spacing: float, avoid: Array = []) -> Array:
	## Random open cells, at least min_dist steps from the drop point and
	## spaced apart from each other, hives and anything in `avoid`.
	var cands: Array = []
	for y in range(1, map.h - 1):
		for x in range(1, map.w - 1):
			var i := map.idx(x, y)
			if map.kinds[i] != LevelMap.EMPTY or _start_dist[i] < min_dist:
				continue
			if need_mech and not map.mech_cells[i]:
				continue
			cands.append(Vector2(x + 0.5, y + 0.5))
	for i in range(cands.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = cands[i]
		cands[i] = cands[j]
		cands[j] = tmp
	var out: Array = []
	for c: Vector2 in cands:
		if out.size() >= count:
			break
		var ok := true
		for q: Vector2 in out + avoid:
			if q.distance_to(c) < spacing:
				ok = false
				break
		for hc in map.hive_cells:
			if (Vector2(hc) + Vector2(0.5, 0.5)).distance_to(c) < 3.0:
				ok = false
		if ok:
			out.append(c)
	return out


func _setup_mission() -> void:
	_start_dist = map.distance_field(Vector2i(int(map.start.x), int(map.start.y)), true)
	var nooks: Array = map.cache_spots.duplicate()
	match mtype:
		"rescue":
			rescue_total = int(op.get("rescue", 3))
			var spots: Array = nooks.slice(0, rescue_total)
			nooks = nooks.slice(rescue_total)
			spots.append_array(_pick_cells(rescue_total - spots.size(), false, 8, 5.0, spots))
			for sp: Vector2 in spots:
				survivors_list.append({"pos": sp, "z": map.height_at(sp), "freed": false, "anim": rng.randf() * 3.0, "t": 0.0})
			rescue_total = survivors_list.size()
		"retrieve":
			var n := int(op.get("items", 4))
			var k := mini(n / 2, nooks.size())
			var spots2: Array = nooks.slice(0, k)
			nooks = nooks.slice(k)
			spots2.append_array(_pick_cells(n - k, true, 7, 5.0, spots2))
			var kind := "item_" + String(op.get("item_kind", "supply"))
			for sp: Vector2 in spots2:
				cargo.append({"pos": sp, "z": map.height_at(sp), "taken": false, "kind": kind, "anim": rng.randf() * 3.0, "face": rng.randf() * TAU})
		"scout":
			for sp: Vector2 in _pick_cells(int(op.get("beacons", 3)), true, 8, 7.0):
				beacons.append({"pos": sp, "z": map.height_at(sp), "prog": 0.0, "done": false, "face": rng.randf() * TAU})
		"survive":
			waves_total = int(op.get("waves", 3))
			breaches = _pick_cells(4, true, 10, 6.0)
			if breaches.is_empty():
				breaches = [Vector2(map.w - 3.5, map.h - 3.5)]
		"endless":
			# Survival: the swarm pours in from all sides, forever.
			waves_total = 1000000
			wave_pause = 4.0
			breaches = _pick_cells(6, true, 9, 5.0)
			if breaches.is_empty():
				breaches = [Vector2(map.w - 3.5, map.h - 3.5)]
			nooks.clear()
	# Sometimes someone is hiding even when nobody called for help.
	if mtype != "rescue" and not nooks.is_empty() and rng.randf() < 0.6:
		var sp2: Vector2 = nooks.pop_front()
		survivors_list.append({"pos": sp2, "z": map.height_at(sp2), "freed": false, "anim": 0.0, "t": 0.0, "stray": true})
	for sp3: Vector2 in nooks:
		caches.append({"pos": sp3, "z": map.height_at(sp3), "taken": false, "anim": rng.randf() * 3.0, "face": rng.randf() * TAU})
	# Landing zone for pickup.
	if mtype == "survive" or survival:
		lz = map.start
	else:
		var lzs := _pick_cells(1, true, 9, 0.0, cargo.map(func(it): return it["pos"]))
		lz = lzs[0] if not lzs.is_empty() else map.start


func _update_drop(delta: float) -> void:
	drop_t -= delta
	var k := clampf(drop_t / DROP_TIME, 0.0, 1.0)
	floor_z = map.height_at(pos)
	eye_z = floor_z + EYE + 26.0 * k * k
	shake = maxf(shake, 2.5 * k)
	if not chest.is_empty():
		chest["fz"] = map.height_at(chest["pos"]) + 26.0 * k * k
	if drop_t <= 0.0:
		phase = "fight"
		eye_z = floor_z + EYE
		shake = 22.0
		Sfx.play("boom", -3.0)
		Sfx.play("step", 0.0)
		for i in 8:
			var p := pos + Vector2.from_angle(TAU * i / 8.0) * 1.3
			explosions.append({"pos": p, "z": floor_z + 0.2, "t": 0.0, "dur": 0.9, "size": 0.7, "col": Color(0.55, 0.45, 0.38), "smoke": true})


func _update_lift(delta: float) -> void:
	for c in crew:
		if c["state"] != "in":
			loot["biomass"] += int(c["carry"])
			c["carry"] = 0
			c["state"] = "in"
	lift_t += delta
	var k := clampf(lift_t / LIFT_TIME, 0.0, 1.0)
	eye_z = floor_z + EYE + 24.0 * k * k
	shake = maxf(shake, 3.0 * (1.0 - k))
	if not chest.is_empty():
		chest["fz"] = map.height_at(chest["pos"]) + 24.0 * k * k
	if lift_t >= LIFT_TIME:
		state = State.WON
		_finish()


func _alive_hostiles() -> int:
	var n := 0
	for a in aliens:
		if not a["dead"] and not _is_nest(a):
			n += 1
	return n


func _update_waves(delta: float) -> void:
	var alive := _alive_hostiles()
	if wave_pause > 0.0:
		wave_pause -= delta
		if wave_pause <= 0.0 and wave < waves_total:
			wave += 1
			wave_timer = 0.0
			_spawn_wave()
		return
	wave_timer += delta
	if survival:
		if alive == 0 or (alive <= 2 and wave_timer > 25.0) or wave_timer > 50.0:
			wave_pause = 6.0
			corpses.clear()
			# Repair drones patch Brigid up between waves.
			for pn in GameState.PARTS:
				parts[pn] = minf(GameState.max_hp(pn), parts[pn] + GameState.max_hp(pn) * 0.15)
			pilot_hp = minf(pilot_max_hp, pilot_hp + pilot_max_hp * 0.25)
			_show_msg("WAVE %d HELD — REPAIR DRONES +15%%" % wave, 2.5)
		return
	if wave < waves_total and (alive <= 1 or wave_timer > 40.0):
		wave_pause = 5.0
		_show_msg("WAVE %d HELD — NEXT ONE COMING" % wave, 2.5)


func _spawn_wave() -> void:
	var n := 4 + 2 * wave + diff
	if survival:
		# Every wave is bigger and every third wave the swarm gets tougher.
		diff = 1 + wave / 3
		n = mini(4 + wave * 2, 24)
		n = mini(n, 36 - _alive_hostiles())
	for k in n:
		var b: Vector2 = breaches[k % breaches.size()]
		for attempt in 8:
			var p := b + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 1.6)
			if not map.blocked(p, 0.3, map.height_at(b)):
				_spawn(_pick_kind(), p, true)
				explosions.append({"pos": p, "z": map.height_at(p) + 0.3, "t": -k * 0.05, "dur": 0.5, "size": 0.6, "col": Color(0.75, 0.3, 0.8)})
				break
	if survival:
		_show_msg("WAVE %d" % wave, 2.0)
	else:
		_show_msg("WAVE %d / %d" % [wave, waves_total], 2.0)
	_radio("wave")
	Sfx.play("screech", -2.0, 0.2)


func _cargo_needed() -> int:
	var n := 0
	for it in cargo:
		if not it.get("destroyed", false):
			n += 1
	return n


func _objective_met() -> bool:
	match mtype:
		"destroy", "boss":
			return hives_total > 0 and hives_destroyed >= hives_total
		"rescue":
			var n := 0
			for sv in survivors_list:
				if sv.get("strapped", false) and not sv.get("stray", false):
					n += 1
			return n >= rescue_total
		"retrieve":
			return items_got >= _cargo_needed()
		"scout":
			return beacons_done >= beacons.size()
		"endless":
			return false
		"survive":
			return wave >= waves_total and wave_pause <= 0.0 and (_alive_hostiles() == 0 or (_alive_hostiles() <= 1 and wave_timer > 20.0))
	return false


func _update_mission(delta: float) -> void:
	_update_followers(delta)
	for b in beacons:
		if b["done"]:
			continue
		if pos.distance_to(b["pos"]) < 1.7:
			b["prog"] += delta
			if b["prog"] >= BEACON_TIME:
				b["done"] = true
				beacons_done += 1
				Sfx.play("pickup", 0.0, 0.0, 0.7)
				_show_msg("RELAY ONLINE %d/%d" % [beacons_done, beacons.size()], 2.0)
		else:
			b["prog"] = maxf(0.0, b["prog"] - delta * 0.5)
	if mtype == "survive" or survival:
		_update_waves(delta)
	if not objective_done and _objective_met():
		objective_done = true
		phase = "extract"
		Sfx.play("pickup", 2.0, 0.0, 0.6)
		_show_msg("OBJECTIVE COMPLETE — GET TO THE GREEN FLARE", 3.0)
		_radio("objective_done")
		if mtype == "destroy" or mtype == "boss":
			# The song stops: every remaining alien collapses.
			for a in aliens:
				if not a["dead"]:
					_damage_alien(a, 1e9)
	if objective_done and phase == "extract":
		var in_lz := pos.distance_to(lz) < LZ_RADIUS
		if in_lz and not on_foot and climb_t <= 0.0:
			if pickup_t == 0.0:
				_radio("extract_inbound")
				Sfx.play("rocket", -6.0, 0.0, 0.5)
			pickup_t += delta
			if pickup_t >= PICKUP_TIME:
				phase = "lift"
				lift_t = 0.0
				_radio("extracted")
				Sfx.play("rocket", 0.0, 0.0, 0.6)
		elif in_lz and on_foot and msg_t < 0.0:
			_show_msg("CLIMB BACK INTO BRIGID — THE GANNET LIFTS THE WALKER", 2.0)


func _objective_string() -> String:
	if phase == "drop":
		var cond: String = String(zone_theme["name"]).get_slice("·", 1).strip_edges()
		if survival:
			return "DROPPING INTO %s" % String(zone_theme["name"]).to_upper()
		return "DROPPING INTO %s — %s" % [String(op.get("zone", "")).to_upper(), cond.to_upper()]
	if phase == "lift":
		return "EXTRACTING — GOING HOME"
	if objective_done:
		if pickup_t > 0.0:
			return "HOLD THE LZ — GANNET LANDING IN %ds" % int(ceil(PICKUP_TIME - pickup_t))
		return "EXTRACT: GET BRIGID TO THE GREEN FLARE"
	if survival:
		var best := "  ·  BEST WAVE %d" % int(best_before["wave"]) if int(best_before["wave"]) > 0 else ""
		if wave_pause > 0.0:
			return "WAVE %d IN %ds%s" % [wave + 1, int(ceil(wave_pause)), best]
		return "WAVE %d — %d HOSTILES — %d KILLS%s" % [wave, _alive_hostiles(), kills, best]
	match mtype:
		"destroy":
			return "DESTROY HIVES %d/%d" % [hives_destroyed, hives_total]
		"boss":
			return "KILL THE BROOD MOTHER (%d/%d NESTS DOWN)" % [hives_destroyed, hives_total]
		"rescue":
			var n := 0
			var following := 0
			for sv in survivors_list:
				if sv.get("strapped", false) and not sv.get("stray", false):
					n += 1
				elif sv["freed"] and not sv.get("dead", false):
					following += 1
			if following > 0:
				return "LEAD %d SURVIVOR%s TO THE CHEST (%d/%d SAFE)" % [following, "S" if following > 1 else "", n, rescue_total]
			return "RESCUE SURVIVORS %d/%d" % [n, rescue_total]
		"retrieve":
			if carrying.get("kind", "") == "cargo":
				return "CARRY THE CARGO TO THE CHEST (%d/%d STOWED)" % [items_got, _cargo_needed()]
			return "RECOVER CARGO %d/%d — CARRY IT TO THE CHEST" % [items_got, _cargo_needed()]
		"scout":
			for b in beacons:
				if not b["done"] and b["prog"] > 0.0:
					return "ACTIVATING RELAY... %d%%" % int(b["prog"] / BEACON_TIME * 100.0)
			return "ACTIVATE RELAYS %d/%d" % [beacons_done, beacons.size()]
		"survive":
			if wave_pause > 0.0 and wave < waves_total:
				return "WAVE %d/%d IN %ds" % [wave + 1, waves_total, int(ceil(wave_pause))]
			return "SURVIVE WAVE %d/%d — %d HOSTILES" % [wave, waves_total, _alive_hostiles()]
	return ""


# --- Climbing out of and into the mech ----------------------------------------

func _parked_mech_blocks(p: Vector2, r: float) -> bool:
	return on_foot and p.distance_to(mech_pos) < MECH_R + r


func _check_caches() -> void:
	## Salvage is picked up by hand (on foot), one load at a time, and has
	## to be carried to the Chest. Survivors start following you.
	var reach := body_r + 0.45
	for c in caches:
		if c["taken"] or pos.distance_to(c["pos"]) > reach or absf(floor_z - c["z"]) > 0.7:
			continue
		if not on_foot:
			if hands_msg_cd <= 0.0:
				hands_msg_cd = 3.0
				_show_msg("SALVAGE CACHE — CLIMB OUT TO OPEN IT", 1.8)
			continue
		c["taken"] = true
		caches_found += 1
		Sfx.play("pickup", -2.0, 0.0)
		var roll := rng.randf()
		if roll < 0.4:
			_found_load(c["pos"], "scrap", rng.randi_range(6, 12) + diff)
		elif roll < 0.6:
			_found_load(c["pos"], "circuits", rng.randi_range(2, 4))
		else:
			var kind: String = ["shells", "rockets", "rounds"][rng.randi_range(0, 2)]
			var amount: int = {"shells": rng.randi_range(80, 150), "rockets": 2, "rounds": rng.randi_range(30, 50)}[kind]
			ammo_left[kind] += amount
			_show_msg("AMMO CRATE  +%d %s (LOADED STRAIGHT IN)" % [amount, GameState.AMMO_NAMES[kind].to_upper()], 2.0)
	if on_foot and carrying.is_empty() and harvest_t <= 0.0:
		for pk in pickups:
			if pos.distance_to(pk["pos"]) > PILOT_R + 0.45 or absf(floor_z - pk["z"]) > 0.7:
				continue
			pickups.erase(pk)
			_carry(pk["kind"], pk["amount"], pk.get("item"))
			break
	for sv in survivors_list:
		if sv["freed"] or sv.get("dead", false) or pos.distance_to(sv["pos"]) > reach + 0.2 or absf(floor_z - sv["z"]) > 0.8:
			continue
		sv["freed"] = true
		sv["t"] = 0.0
		Sfx.play("pickup", 0.0, 0.0, 0.8)
		_show_msg("SURVIVOR FOUND — THEY'LL FOLLOW YOU TO THE CHEST", 2.5)
		_radio("rescue")
	for it in cargo:
		if it["taken"] or it.get("deposited", false) or pos.distance_to(it["pos"]) > reach + 0.2 or absf(floor_z - it["z"]) > 0.8:
			continue
		if not on_foot or not carrying.is_empty():
			if hands_msg_cd <= 0.0:
				hands_msg_cd = 3.0
				_show_msg("CLIMB OUT TO CARRY THE CARGO" if not on_foot else "HANDS FULL", 1.8)
			continue
		it["taken"] = true
		_carry("cargo", 1, it)
		break


func _found_load(at: Vector2, kind: String, amount: int) -> void:
	if carrying.is_empty():
		_carry(kind, amount, null)
	else:
		_drop_pickup(at, kind, amount)
		_show_msg("%d %s — HANDS FULL, LEFT IT HERE" % [amount, CARRY_NAMES[kind]], 2.0)


func _carry(kind: String, amount: int, item) -> void:
	var model: String = {"scrap": "pile_scrap", "circuits": "pile_circuits", "biomass": "jar_biomass"}.get(kind, "")
	if kind == "cargo":
		model = item["kind"]
	carrying = {"kind": kind, "amount": amount, "model": model, "item": item}
	Sfx.play("pickup", -4.0, 0.05, 1.1)
	if kind == "cargo":
		_show_msg("CARGO IN HAND — TAKE IT TO THE CHEST", 2.0)
	else:
		_show_msg("CARRYING %d %s — TAKE IT TO THE CHEST" % [amount, CARRY_NAMES[kind]], 2.0)


func _drop_pickup(at: Vector2, kind: String, amount: int, item = null) -> void:
	var model: String = {"scrap": "pile_scrap", "circuits": "pile_circuits", "biomass": "jar_biomass"}.get(kind, "")
	pickups.append({"pos": at, "z": map.height_at(at), "kind": kind, "amount": amount, "model": model, "item": item, "face": rng.randf() * TAU})


func _drop_carried() -> void:
	if carrying.is_empty():
		return
	var at := pos + Vector2.from_angle(angle) * 0.35
	if carrying["kind"] == "cargo":
		var it: Dictionary = carrying["item"]
		it["taken"] = false
		it["pos"] = at
		it["z"] = map.height_at(at)
	else:
		_drop_pickup(at, carrying["kind"], carrying["amount"])
	carrying = {}
	Sfx.play("step", -12.0, 0.1, 1.4)


# --- The Chest -----------------------------------------------------------------

func _spawn_chest() -> void:
	var spot := map.start + Vector2(1.5, 0)
	for k in 16:
		var p := map.start + Vector2.from_angle(TAU * k / 16.0) * 1.6
		if not map.blocked(p, CHEST_R, map.height_at(p)) and absf(map.height_at(p) - map.height_at(map.start)) < 0.4:
			spot = p
			break
	chest = {"pos": spot, "fz": map.height_at(spot) + 26.0, "face": angle, "anim": 0.0, "moving": false, "stuck_t": 0.0}
	for i in CREW_COUNT:
		crew.append({"state": "in", "pos": spot, "z": map.height_at(spot), "face": 0.0, "target": null, "t": 0.0,
			"carry": 0, "moving": false, "stuck_t": 0.0, "anim": rng.randf() * 3.0})


func _chest_blocks(p: Vector2, r: float) -> bool:
	return not chest.is_empty() and p.distance_to(chest["pos"]) < CHEST_R + r


func _near_chest() -> bool:
	return not chest.is_empty() and pos.distance_to(chest["pos"]) < CHEST_REACH and absf(floor_z - chest["fz"]) < 1.0


func _update_chest(delta: float) -> void:
	## Trots after you, keeping a couple of metres back. Gets around walls
	## using the same path field as the aliens; if it gets truly stuck it
	## catches up the long way round (we skip the boring part).
	# It follows Brigid. While you're out on foot it waits beside her.
	var cp: Vector2 = chest["pos"]
	var goal := mech_pos if on_foot else pos
	var goal_z := mech_fz + EYE if on_foot else eye_z
	var to_p := goal - cp
	var dist := to_p.length()
	var keep := 2.0 if on_foot else 2.4
	var step := Vector2.ZERO
	if dist > keep:
		var dir := to_p / dist
		if dist > 3.0 or not map.line_of_sight(cp, chest["fz"] + 1.0, goal, goal_z):
			dir = _flow_dir(cp) if not on_foot else dir
		step = dir * minf(3.4, 1.5 + dist * 0.6) * delta
	var stand := map.height_at(cp)
	var moved := false
	for axis in 2:
		var np := cp + (Vector2(step.x, 0.0) if axis == 0 else Vector2(0.0, step.y))
		if step == Vector2.ZERO:
			break
		if map.blocked(np, CHEST_R, stand) or np.distance_to(pos) < body_r + CHEST_R or (on_foot and np.distance_to(mech_pos) < MECH_R + CHEST_R):
			continue
		cp = np
		moved = true
	chest["moving"] = moved
	if moved:
		chest["anim"] += delta
		chest["face"] = lerp_angle(chest["face"], step.angle(), minf(1.0, delta * 5.0))
	chest["pos"] = cp
	chest["fz"] = move_toward(chest["fz"], map.height_at(cp), delta * 4.0)
	if dist > 7.0 and not moved:
		chest["stuck_t"] += delta
	else:
		chest["stuck_t"] = 0.0
	if chest["stuck_t"] > 4.0:
		for k in 12:
			var p := goal - Vector2.from_angle(angle + (k - 6) * 0.35) * 2.2
			var hh := map.height_at(p)
			if not map.blocked(p, CHEST_R, hh) and absf(hh - map.height_at(goal)) < 0.6:
				chest["pos"] = p
				chest["fz"] = hh
				chest["stuck_t"] = 0.0
				_dirt_burst(p, 3)
				_show_msg("THE CHEST CATCHES UP", 1.5)
				break
	if not get_meta("chest_told", false) and phase == "fight" and time > 9.0 and GameState.missions_won < 3:
		set_meta("chest_told", true)
		_radio_line("mags", "The Chest is trotting behind you. Everything goes in it: scrap, circuits, biomass, people. Hazmat suit's on its hook.")
	_update_crew(delta)
	# Anything carried in is stowed; anyone following straps in.
	if on_foot and not carrying.is_empty() and _near_chest():
		_deposit()
	for sv in survivors_list:
		if sv["freed"] and not sv.get("strapped", false) and not sv.get("dead", false) and sv["pos"].distance_to(chest["pos"]) < CHEST_REACH:
			sv["strapped"] = true
			rescued += 1
			Sfx.play("pickup", -2.0, 0.0, 0.7)
			_show_msg("SURVIVOR STRAPPED IN — %d ABOARD THE CHEST" % rescued, 2.0)


func _deposit() -> void:
	var kind: String = carrying["kind"]
	if kind == "cargo":
		var it: Dictionary = carrying["item"]
		it["deposited"] = true
		items_got += 1
		_show_msg("CARGO STOWED %d/%d" % [items_got, _cargo_needed()], 2.0)
	else:
		loot[kind] += int(carrying["amount"])
		_show_msg("+%d %s IN THE CHEST" % [carrying["amount"], CARRY_NAMES[kind]], 1.8)
	carrying = {}
	Sfx.play("pickup", 0.0, 0.0, 1.3)
	Sfx.play("hatch", -14.0, 0.1, 1.6)


func _update_followers(delta: float) -> void:
	## Found survivors follow you (Half-Life style) until they reach the Chest.
	for sv in survivors_list:
		if not sv["freed"] or sv.get("strapped", false) or sv.get("dead", false):
			continue
		sv["t"] += delta
		var sp: Vector2 = sv["pos"]
		var to_p := pos - sp
		var dist := to_p.length()
		var want := 1.0 + float(survivors_list.find(sv) % 3) * 0.35
		# Head for the Chest when it's close, otherwise stay with you.
		var target := pos
		if not chest.is_empty() and sp.distance_to(chest["pos"]) < 5.0:
			target = chest["pos"]
			want = 0.5
		var to_t := target - sp
		var d_t := to_t.length()
		sv["moving"] = false
		if d_t > want:
			var dir := to_t / d_t
			if target == pos and (dist > 3.0 or not map.line_of_sight(sp, sv["z"] + 0.5, pos, eye_z)):
				dir = _flow_dir(sp)
			var speed := minf(3.6, 1.6 + d_t * 0.8)
			var stand := map.height_at(sp)
			var np := sp + dir * speed * delta
			for other in survivors_list:
				if other != sv and other["freed"] and not other.get("strapped", false):
					var off: Vector2 = np - other["pos"]
					if off.length() < 0.35 and off.length() > 0.001:
						np += off.normalized() * 0.02
			if not map.blocked(np, 0.15, stand, PILOT_STEP) and np.distance_to(pos) > body_r + 0.15 and not _parked_mech_blocks(np, 0.15):
				sv["pos"] = np
				sv["moving"] = true
			sv["face"] = dir.angle()
		else:
			sv["face"] = to_p.angle()
		sv["z"] = map.height_at(sv["pos"])


# --- The harvest team ------------------------------------------------------------

func _threat_near(p: Vector2, radius: float) -> bool:
	for a in aliens:
		if not a["dead"] and a["awake"] and not _is_nest(a) and not a.get("under", false) and a["pos"].distance_to(p) < radius:
			return true
	return false


func _update_crew(delta: float) -> void:
	## Volunteers in hazmat suits climb out of the Chest when it stands still
	## and nothing hostile is close, cut biomass from nearby carcasses, and
	## carry it back. At the first sign of trouble they run for the Chest.
	var cp: Vector2 = chest["pos"]
	chest_still_t = 0.0 if chest["moving"] else chest_still_t + delta
	var calm := not _threat_near(cp, 10.0)
	for c in crew:
		match c["state"]:
			"in":
				c["pos"] = cp
				if calm and chest_still_t > 1.5 and phase != "lift":
					var target = _crew_pick_corpse(cp)
					if target != null:
						target["claimed"] = true
						c["target"] = target
						c["state"] = "go"
						c["stuck_t"] = 0.0
						if not crew_told:
							crew_told = true
							_radio_line("sandoval", "Area's quiet. My harvest team is going out to cut. Keep the bugs off them, Wren.")
			"go":
				var tgt: Dictionary = c["target"]
				if _crew_danger(c, cp):
					continue
				if _crew_move(c, tgt["pos"], 2.0, 0.55, delta):
					c["state"] = "cut"
					c["t"] = 0.0
					c["face"] = (tgt["pos"] - c["pos"]).angle()
				elif c["stuck_t"] > 2.5:
					tgt["claimed"] = false
					tgt["crew_skip"] = true
					c["state"] = "back"
			"cut":
				if _crew_danger(c, cp):
					continue
				c["t"] += delta
				c["anim"] += delta
				if fmod(c["t"], 0.9) < delta and pos.distance_to(c["pos"]) < 8.0:
					Sfx.play("splat", -18.0, 0.3, 1.4)
				if c["t"] >= CREW_CUT_TIME:
					var tgt2: Dictionary = c["target"]
					tgt2["harvested"] = true
					tgt2["claimed"] = false
					c["carry"] = int(BIOMASS_YIELD.get(tgt2["kind"], 1))
					c["target"] = null
					c["state"] = "back"
					c["stuck_t"] = 0.0
			"back":
				var arrived := _crew_move(c, cp, 1.9 if c["carry"] > 0 else 2.6, 0.8, delta)
				if arrived or c["stuck_t"] > 3.0:
					if c["carry"] > 0:
						loot["biomass"] += int(c["carry"])
						_show_msg("+%d BIOMASS — HARVEST TEAM" % c["carry"], 1.8)
						Sfx.play("pickup", -8.0, 0.0, 1.2)
					c["carry"] = 0
					c["state"] = "in"


func _crew_pick_corpse(from: Vector2):
	var best = null
	var bd := 11.0
	var fz := map.height_at(from)
	for cp in corpses:
		if cp["harvested"] or cp.get("claimed", false) or cp.get("crew_skip", false):
			continue
		var d: float = from.distance_to(cp["pos"])
		if d < bd and absf(cp["z"] - fz) < 1.0 and map.line_of_sight(from, fz + 0.4, cp["pos"], cp["z"] + 0.4) \
				and (harvest_target == null or cp != harvest_target):
			bd = d
			best = cp
	return best


func _crew_danger(c: Dictionary, cp: Vector2) -> bool:
	if _threat_near(c["pos"], 7.0) or c["pos"].distance_to(cp) > 13.0:
		if c["target"] != null:
			c["target"]["claimed"] = false
			c["target"] = null
		c["state"] = "back"
		c["stuck_t"] = 0.0
		if not get_meta("crew_fallback_cd", false):
			set_meta("crew_fallback_cd", true)
			_show_msg("HARVEST TEAM FALLING BACK TO THE CHEST", 2.0)
			get_tree().create_timer(8.0).timeout.connect(func(): set_meta("crew_fallback_cd", false))
		return true
	return false


func _crew_move(c: Dictionary, target: Vector2, speed: float, arrive: float, delta: float) -> bool:
	var p: Vector2 = c["pos"]
	var to_t := target - p
	var d := to_t.length()
	if d < arrive:
		c["moving"] = false
		return true
	var step := to_t / d * speed * delta
	var stand := map.height_at(p)
	var moved := false
	for axis in 2:
		var np := p + (Vector2(step.x, 0.0) if axis == 0 else Vector2(0.0, step.y))
		if not map.blocked(np, 0.15, stand, PILOT_STEP):
			p = np
			moved = true
	c["pos"] = p
	c["z"] = map.height_at(p)
	c["moving"] = moved
	c["face"] = step.angle()
	if moved:
		c["anim"] += delta
		c["stuck_t"] = 0.0
	else:
		c["stuck_t"] += delta
	return false


# --- Harvesting biomass ----------------------------------------------------------

func _nearest_corpse():
	var best = null
	var bd := 1.6
	for c in corpses:
		if c["harvested"] or c.get("claimed", false):
			continue
		var d: float = pos.distance_to(c["pos"])
		if d < bd and absf(c["z"] - floor_z) < 0.8:
			bd = d
			best = c
	return best


func _update_harvest(delta: float) -> void:
	## Two seconds of careful cutting in the hazmat suit.
	var prev := harvest_t
	harvest_t += delta
	bob_amount = lerpf(bob_amount, 0.0, minf(1.0, delta * 6.0))
	if floor(prev * 3.0) != floor(harvest_t * 3.0):
		Sfx.play("splat", -10.0, 0.3, 1.3)
	if harvest_t >= HARVEST_TIME + 0.15:
		var c: Dictionary = harvest_target
		c["harvested"] = true
		harvest_t = 0.0
		harvest_target = null
		var amount := int(BIOMASS_YIELD.get(c["kind"], 1))
		if carrying.get("kind", "") == "biomass":
			# Jars stack: keep cutting, deliver them all in one trip.
			carrying["amount"] += amount
			carrying["jars"] += 1
			Sfx.play("pickup", -4.0, 0.05, 1.1)
			_show_msg("+%d BIOMASS — %d JARS, %d IN ALL (MAX %d JARS)" % [amount, carrying["jars"], carrying["amount"], MAX_JARS], 2.0)
		else:
			_carry("biomass", amount, null)
			carrying["jars"] = 1


func _action() -> Array:
	## The context button under EXIT MECH: [label, enabled] or [] for none.
	if not on_foot or climb_t > 0.0 or state != State.PLAYING or phase == "drop" or phase == "lift":
		return []
	if harvest_t > 0.0:
		return ["HARVESTING…", false]
	var corpse = null if survival else _nearest_corpse()
	if hazmat and corpse != null and carrying.get("kind", "") == "biomass" and int(carrying.get("jars", 1)) < MAX_JARS:
		return ["HARVEST (JAR %d/%d)" % [int(carrying["jars"]) + 1, MAX_JARS], true]
	if not carrying.is_empty():
		return ["DROP " + String(CARRY_NAMES[carrying["kind"]]), true]
	if hazmat and corpse != null:
		return ["HARVEST BIOMASS", true]
	if _near_chest():
		return ["TAKE OFF HAZMAT" if hazmat else "PUT ON HAZMAT", true]
	if corpse != null:
		return ["HAZMAT ON THE CHEST", false]
	return []


func _do_action() -> void:
	var act := _action()
	if act.is_empty():
		return
	var label: String = act[0]
	if not act[1]:
		if label == "HAZMAT ON THE CHEST":
			_show_msg("ALIEN TISSUE IS TOXIC — PUT ON THE HAZMAT SUIT AT THE CHEST", 2.2)
		return
	Sfx.play("click")
	if label.begins_with("DROP"):
		_drop_carried()
	elif label.begins_with("HARVEST"):
		harvest_target = _nearest_corpse()
		harvest_t = 0.001
		fire_touch = -1
		move_touch = -1
		move_vec = Vector2.ZERO
		angle = (harvest_target["pos"] - pos).angle()
		pitch = -get_viewport_rect().size.y * 0.3
	else:
		hazmat = not hazmat
		Sfx.play("hatch", -8.0, 0.0, 1.4)
		_show_msg("HAZMAT SUIT ON — GO CUT SOME BIOMASS" if hazmat else "HAZMAT SUIT BACK ON ITS HOOK", 1.8)


func _action_rect(s: Vector2) -> Rect2:
	return Rect2(s.x - 206, 294, 190, 50)


func _toggle_mech() -> void:
	if state != State.PLAYING or climb_t > 0.0:
		return
	if on_foot:
		_start_board()
	else:
		_start_exit()


func _can_board() -> int:
	## 0 = can climb in, 1 = too far, 2 = not behind it, 3 = wrong level.
	var to_mech := mech_pos - pos
	if to_mech.length() > BOARD_DIST:
		return 1
	if absf(floor_z - mech_fz) > 1.0:
		return 3
	if (pos - mech_pos).normalized().dot(-Vector2.from_angle(mech_angle)) < 0.25:
		return 2
	return 0


func _start_exit() -> void:
	var fwd := Vector2.from_angle(angle)
	var side := Vector2(-fwd.y, fwd.x)
	var here := map.height_at(pos)
	var spot := Vector2.INF
	for off in [-fwd * 0.95, -fwd * 0.95 + side * 0.45, -fwd * 0.95 - side * 0.45, -fwd * 0.75 + side * 0.8, -fwd * 0.75 - side * 0.8, side * 0.95, -side * 0.95]:
		var p: Vector2 = pos + off
		var hh := map.height_at(p)
		if not map.blocked(p, PILOT_R, hh, PILOT_STEP) and absf(hh - here) <= 1.2:
			spot = p
			break
	if spot == Vector2.INF:
		_show_msg("NO ROOM BEHIND THE MECH TO CLIMB OUT", 1.5)
		return
	mech_pos = pos
	mech_angle = angle
	mech_fz = floor_z
	climb_out = true
	climb_from = {"pos": pos, "floor": floor_z, "eye": EYE, "angle": angle}
	climb_to = {"pos": spot, "floor": map.height_at(spot), "eye": PILOT_EYE, "angle": angle}
	climb_t = CLIMB_TIME
	_stop_inputs()
	Sfx.play("hatch", -3.0, 0.0)


func _start_board() -> void:
	match _can_board():
		1:
			_show_msg("GET CLOSER TO YOUR MECH", 1.2)
			return
		2:
			_show_msg("CLIMB IN FROM THE MECH'S BACK", 1.5)
			return
		3:
			_show_msg("GET LEVEL WITH YOUR MECH", 1.5)
			return
	if not carrying.is_empty():
		_drop_carried()
		_show_msg("YOU SET IT DOWN TO CLIMB IN", 1.5)
	climb_out = false
	climb_from = {"pos": pos, "floor": floor_z, "eye": PILOT_EYE, "angle": angle}
	climb_to = {"pos": mech_pos, "floor": mech_fz, "eye": EYE, "angle": mech_angle}
	climb_t = CLIMB_TIME
	_stop_inputs()
	Sfx.play("hatch", -3.0, 0.0)


func _stop_inputs() -> void:
	fire_touch = -1
	move_touch = -1
	look_touch = -1
	move_vec = Vector2.ZERO


func _climb_progress() -> float:
	return clampf(1.0 - climb_t / CLIMB_TIME, 0.0, 1.0)


func _update_climb(delta: float) -> void:
	climb_t -= delta
	var t := _climb_progress()
	var e := smoothstep(0.0, 1.0, t)
	var from_pos: Vector2 = climb_from["pos"]
	pos = from_pos.lerp(climb_to["pos"], e)
	floor_z = lerpf(climb_from["floor"], climb_to["floor"], e)
	eye_h = lerpf(climb_from["eye"], climb_to["eye"], e) + sin(t * PI) * 0.3
	angle = lerp_angle(climb_from["angle"], climb_to["angle"], e)
	eye_z = floor_z + eye_h
	bob_amount = 0.0
	if climb_t > 0.0:
		return
	climb_t = 0.0
	if climb_out:
		on_foot = true
		body_r = PILOT_R
		eye_h = PILOT_EYE
		Sfx.play("step", -8.0, 0.1, 1.6)
		if not told_foot:
			told_foot = true
			_show_msg("ON FOOT — SQUEEZE WHERE BRIGID CAN'T FIT", 3.0)
			_radio("foot")
	else:
		on_foot = false
		body_r = MECH_R
		eye_h = EYE
		pos = mech_pos
		angle = mech_angle
		floor_z = mech_fz
		eye_z = floor_z + eye_h
		Sfx.play("step", -2.0)
		shake = 6.0
	_update_flow()


func _in_cockpit_view() -> bool:
	if climb_t > 0.0:
		var t := _climb_progress()
		return (climb_out and t < 0.45) or (not climb_out and t > 0.55)
	return not on_foot


func _show_msg(text: String, dur: float) -> void:
	msg = text
	msg_t = dur


# =============================================================================
# Input
# =============================================================================

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if state != State.PLAYING and end_time > 1.0 and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE]:
			_leave()
		elif state == State.PLAYING and (event.keycode == KEY_ESCAPE or event.keycode == KEY_P):
			_set_paused(true)
		elif state == State.PLAYING and event.keycode == KEY_J:
			want_jump = true
		elif state == State.PLAYING and event.keycode == KEY_C:
			_do_action()
		elif state == State.PLAYING and event.keycode == KEY_X:
			_toggle_mech()
		return
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position
		var s := get_viewport_rect().size
		if event.pressed:
			if Music.covers(p):
				return
			if state != State.PLAYING:
				if end_time > 1.2:
					_leave()
				return
			if _retreat_rect().has_point(p):
				Sfx.play("click")
				_set_paused(true)
				return
			if _action_rect(s).has_point(p) and not _action().is_empty():
				_do_action()
				return
			if _mech_button_rect(s).has_point(p) and phase != "drop" and phase != "lift":
				_toggle_mech()
				return
			if climb_t > 0.0 or phase == "drop" or phase == "lift":
				return
			if p.distance_to(_fire_center(s)) < FIRE_R * 1.2:
				fire_touch = event.index
				return
			if not on_foot and p.distance_to(_rocket_center(s)) < ROCKET_R * 1.25:
				_fire_rocket()
				return
			if on_foot and p.distance_to(_rocket_center(s)) < ROCKET_R * 1.25:
				want_jump = true
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
	elif event is InputEventScreenDrag and state == State.PLAYING and climb_t <= 0.0:
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
	## The pause button, top-left.
	return Rect2(16, 16, 150, 46)


func _leave() -> void:
	get_tree().paused = false
	if survival:
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/base.tscn")


# --- Pause menu ------------------------------------------------------------------

func _notification(what: int) -> void:
	# Pause when the phone app goes to the background.
	if what == NOTIFICATION_APPLICATION_PAUSED and state == State.PLAYING and is_inside_tree():
		_set_paused(true)


func _build_pause_menu() -> void:
	pause_layer = CanvasLayer.new()
	pause_layer.layer = 20
	pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_layer.visible = false
	add_child(pause_layer)


func _set_paused(on: bool) -> void:
	if pause_layer == null or paused == on:
		return
	paused = on
	get_tree().paused = on
	pause_layer.visible = on
	fire_touch = -1
	move_touch = -1
	look_touch = -1
	move_vec = Vector2.ZERO
	if on:
		_show_pause_main()


func _clear_pause() -> void:
	for c in pause_layer.get_children():
		c.queue_free()


func _pause_backdrop() -> CenterContainer:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_layer.add_child(center)
	return center


func _pause_button(text: String, col: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(420, 64)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", col)
	b.pressed.connect(func():
		Sfx.play("click")
		cb.call())
	return b


func _show_pause_main() -> void:
	_clear_pause()
	var center := _pause_backdrop()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	v.add_child(title)
	var sub := Label.new()
	sub.text = (("Survival · wave %d · %d kills" % [wave, kills]) if survival else String(op.get("title", "")) + " — " + String(op.get("zone", ""))) + "\n" + String(zone_theme["name"])
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.8, 0.85, 0.8))
	v.add_child(sub)
	v.add_child(_pause_button("Resume", Color(0.5, 1.0, 0.6), func(): _set_paused(false)))
	v.add_child(_pause_button("Settings", Color(0.9, 0.9, 0.9), func():
		_clear_pause()
		var c2 := _pause_backdrop()
		c2.add_child(SettingsScript.build_panel(func():
			_apply_live_settings()
			_show_pause_main()))))
	if survival:
		v.add_child(_pause_button("End run", Color(1.0, 0.75, 0.35), func(): _confirm_quit(false)))
	else:
		v.add_child(_pause_button("Abort mission (fly home)", Color(1.0, 0.75, 0.35), func(): _confirm_quit(false)))
	v.add_child(_pause_button("Quit to main menu", Color(1.0, 0.5, 0.45), func(): _confirm_quit(true)))


func _confirm_quit(to_menu: bool) -> void:
	_clear_pause()
	var center := _pause_backdrop()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)
	var l := Label.new()
	if survival:
		l.text = "End this run? Your wave counts toward your best."
	else:
		l.text = "Abort the mission? The Gannet pulls you out.\nYou keep what you found, but the job isn't done."
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 22)
	v.add_child(l)
	v.add_child(_pause_button("Yes, " + ("end run" if survival else "abort"), Color(1.0, 0.6, 0.45), func():
		aborted = true
		state = State.RETREATED
		_finish()
		_set_paused(false)
		if to_menu:
			get_tree().change_scene_to_file("res://scenes/menu.tscn")))
	v.add_child(_pause_button("No, keep fighting", Color(0.5, 1.0, 0.6), func(): _show_pause_main()))


func _apply_live_settings() -> void:
	LOOK_SENS = 0.0065 * Settings.look_sensitivity
	PITCH_SENS = 0.9 * Settings.look_sensitivity
	var cols := Settings.columns()
	if cols != COLUMNS:
		COLUMNS = cols
		col_events.resize(COLUMNS)
		for c in COLUMNS:
			col_events[c] = PackedFloat32Array()


func _mech_button_rect(s: Vector2) -> Rect2:
	return Rect2(s.x - 206, 236, 190, 50)


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
	_draw_weather(w, h)
	if _in_cockpit_view():
		_draw_guns(w, h)
		_draw_cockpit(w, h)
	elif climb_t <= 0.0:
		_draw_pilot_gun(w, h)
		_draw_visor(w, h)
	_draw_hud(w, h, horizon, proj_scale)
	if climb_t > 0.0:
		_draw_climb_overlay(w, h)

	draw_set_transform(Vector2.ZERO)
	if state == State.PLAYING:
		_draw_touch_controls(w, h)
	else:
		_draw_end_screen(w, h)


func _sky_x(rel: float, w: float) -> float:
	return w * 0.5 * (1.0 + tan(rel) / FOV_PLANE)


func _draw_sky(w: float, h: float, horizon: float) -> void:
	var top: Color = zone_theme["sky_top"]
	var hor: Color = zone_theme["sky_horizon"]
	draw_rect(Rect2(-40, -40, w + 80, horizon - h * 0.55 + 41), top)
	draw_polygon(
		PackedVector2Array([Vector2(-40, horizon - h * 0.55), Vector2(w + 40, horizon - h * 0.55), Vector2(w + 40, horizon), Vector2(-40, horizon)]),
		PackedColorArray([top, top, hor, hor]))
	var half_fov := atan(FOV_PLANE) + 0.05
	var star_k: float = zone_theme["stars"]
	if star_k > 0.0:
		for st in stars:
			var rel := wrapf(st["a"] - angle, -PI, PI)
			if absf(rel) > half_fov:
				continue
			var y: float = horizon - st["e"] * h * 0.45
			var b: float = st["b"] * (0.6 + 0.4 * sin(time * 2.0 + st["a"] * 9.0)) * star_k
			draw_rect(Rect2(_sky_x(rel, w), y, 2, 2), Color(1, 0.95, 0.9, b * clampf((horizon - y) / (h * 0.45), 0.0, 1.0) * 1.3))

	# Ringed gas giant (the Lantern) hanging over the battlefield, washed
	# out by daylight or haze in brighter zones.
	var prel := wrapf(0.9 - angle, -PI, PI)
	if zone_theme["planet"] and absf(prel) < half_fov + 0.3:
		var c := Vector2(_sky_x(prel, w), horizon - h * 0.31)
		var r := 64.0
		var wash := clampf(hor.get_luminance() - 0.35, 0.0, 0.6)
		var ring: Array[Vector2] = []
		for i in 49:
			var t := float(i) / 48.0 * TAU
			ring.append(c + Vector2(cos(t) * r * 1.9, sin(t) * r * 0.42).rotated(-0.25))
		draw_polyline(PackedVector2Array(ring.slice(24, 49)), Color(0.9, 0.75, 0.6, 0.6 - wash * 0.6), 3.0)
		draw_circle(c, r, Color(0.78, 0.5, 0.38).lerp(top, wash))
		draw_circle(c + Vector2(14, 10), r * 0.86, Color(0.58, 0.32, 0.27).lerp(top, wash))
		draw_circle(c + Vector2(26, 18), r * 0.7, Color(0.38, 0.18, 0.18).lerp(top, wash))
		draw_polyline(PackedVector2Array(ring.slice(0, 25)), Color(0.95, 0.82, 0.65, 0.8 - wash * 0.8), 3.0)

	# Distant ridges (two layers).
	var strips := 80
	var sw := w / strips
	for layer in 2:
		var ridge := ridge_far if layer == 0 else ridge_near
		var col: Color = zone_theme["ridge_far"] if layer == 0 else zone_theme["ridge_near"]
		for i in strips:
			var xc := (i + 0.5) * sw
			var rel := atan((2.0 * xc / w - 1.0) * FOV_PLANE)
			var a := wrapf(angle + rel, 0.0, TAU)
			var hgt: float = ridge[int(a / TAU * 256.0) % 256]
			draw_rect(Rect2(i * sw, horizon - hgt, sw + 1.0, hgt + 1.0), col)


func _draw_ground(w: float, h: float, horizon: float) -> void:
	var gf: Color = zone_theme["ground_far"]
	var gn: Color = zone_theme["ground_near"]
	draw_polygon(
		PackedVector2Array([Vector2(-40, horizon), Vector2(w + 40, horizon), Vector2(w + 40, h + 40), Vector2(-40, h + 40)]),
		PackedColorArray([gf, gf, gn, gn]))


func _draw_weather(w: float, h: float) -> void:
	## Rain, snow, dust, ash, spores or fireflies. The particles are worked
	## out from time alone (no state), and slide sideways as you turn.
	if weather == "none":
		return
	var shift := angle / TAU * w * 2.2
	match weather:
		"rain":
			for i in 140:
				var sp := 900.0 + fposmod(i * 37.0, 400.0)
				var x := fposmod(i * 97.13 - shift + time * 60.0, w + 40.0) - 20.0
				var y := fposmod(i * 53.7 + time * sp, h + 60.0) - 30.0
				draw_line(Vector2(x, y), Vector2(x - 4.0, y + 22.0), Color(0.7, 0.8, 1.0, 0.28), 1.5)
			draw_rect(Rect2(0, 0, w, h), Color(0.3, 0.4, 0.6, 0.06))
		"snow":
			for i in 110:
				var sp2 := 40.0 + fposmod(i * 13.0, 50.0)
				var x2 := fposmod(i * 97.13 - shift + sin(time * 0.8 + i) * 24.0, w + 20.0) - 10.0
				var y2 := fposmod(i * 61.3 + time * sp2, h + 20.0) - 10.0
				draw_circle(Vector2(x2, y2), 1.5 + fposmod(i * 0.37, 2.0), Color(1, 1, 1, 0.75))
		"dust":
			for i in 50:
				var x3 := fposmod(i * 131.7 - shift + time * (30.0 + i), w + 20.0) - 10.0
				var y3 := fposmod(i * 71.3 + sin(time + i) * 10.0, h)
				draw_circle(Vector2(x3, y3), 1.2, Color(1.0, 0.95, 0.8, 0.35))
			draw_rect(Rect2(0, 0, w, h), Color(1.0, 0.92, 0.75, 0.05))
		"ash":
			for i in 90:
				var x4 := fposmod(i * 97.13 - shift + time * 25.0 + sin(time + i) * 20.0, w + 20.0) - 10.0
				var y4 := fposmod(i * 61.3 + time * (25.0 + fposmod(i * 7.0, 20.0)), h + 20.0) - 10.0
				draw_rect(Rect2(x4, y4, 2.5, 2.0), Color(0.2, 0.2, 0.18, 0.55))
			draw_rect(Rect2(0, 0, w, h), Color(0.55, 0.5, 0.3, 0.07))
		"spores":
			for i in 60:
				var x5 := fposmod(i * 113.1 - shift + sin(time * 0.5 + i) * 40.0, w + 20.0) - 10.0
				var y5 := fposmod(i * 67.9 - time * (12.0 + fposmod(i * 3.0, 12.0)), h + 20.0) - 10.0
				var pulse := 0.5 + 0.5 * sin(time * 3.0 + i)
				draw_circle(Vector2(x5, y5), 2.5, Color(1.0, 0.5, 0.95, 0.25 + 0.35 * pulse))
		"fireflies":
			for i in 34:
				var x6 := fposmod(i * 151.3 - shift + sin(time * 0.6 + i * 1.7) * 60.0, w + 20.0) - 10.0
				var y6 := h * 0.45 + fposmod(i * 37.1, h * 0.4) + sin(time * 0.9 + i) * 25.0
				var blink := clampf(sin(time * 2.0 + i * 2.3) * 2.0, 0.0, 1.0)
				if blink > 0.0:
					draw_circle(Vector2(x6, y6), 5.0, Color(0.9, 1.0, 0.4, 0.15 * blink))
					draw_circle(Vector2(x6, y6), 2.0, Color(1.0, 1.0, 0.6, 0.9 * blink))


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
			if d_out > MAX_VIEW or clip <= 0.0 or (cut > 0.0 and clip <= horizon - cut / d_out) or (cut <= 0.0 and clip <= horizon):
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
					_draw_face(x, cw, y_top, y_vis, nh, cur_h, kinds[ci], side, wall_x, d_in, horizon, ps, ci)
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
		LevelMap.RUBBLE:
			col = FACE_COLORS[LevelMap.RUBBLE].darkened(0.15)
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


func _draw_face(x: float, cw: float, y_top: float, y_vis: float, top_h: float, base_h: float, kind: int, side: int, wall_x: float, d: float, horizon: float, proj_scale: float, cell := 0) -> void:
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
					var win: Color = zone_theme["window"]
					var lit_k: float = zone_theme["lit"]
					var wcol := int(floor(wall_x * 2.0))
					var floor_i := 0
					while z + 0.5 < top_h - 0.3:
						var wy0 := horizon - (z + 0.5 - eye_z) * k
						var wy1 := horizon - (z - eye_z) * k
						var hsh := fposmod(sin(float(cell * 7 + wcol * 13 + floor_i * 31 + side * 5) * 12.9898) * 43758.5453, 1.0)
						if hsh < lit_k:
							# Someone left a light on. Or someone's still in there.
							var warm := Color(1.0, 0.78, 0.4).lerp(FOG, fog * 0.6)
							warm.a = 0.95 - 0.1 * float(hsh < lit_k * 0.15) * (0.5 + 0.5 * sin(time * 9.0 + cell))
							_vband(x, cw, wy0, wy1, lo, hi, warm)
						else:
							_vband(x, cw, wy0, wy1, lo, hi, Color(win.r, win.g, win.b, 0.75 * (1.0 - fog)))
						z += 1.3
						floor_i += 1
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
		if pr.y > 0.15 and pr.y < (MAX_VIEW if tex3d.has(p["kind"]) else 14.0):
			items.append([pr.y, 1, p, pr.x])
	for p in projectiles:
		var pr := _project(p["pos"])
		if pr.y > 0.15 and pr.y < MAX_VIEW:
			items.append([pr.y, 2, p, pr.x])
	for cc in caches:
		if cc["taken"]:
			continue
		var pr := _project(cc["pos"])
		if pr.y > 0.15 and pr.y < MAX_VIEW:
			items.append([pr.y, 4, cc, pr.x])
	for sv in survivors_list:
		if sv.get("strapped", false) or sv.get("dead", false):
			continue
		var pr := _project(sv["pos"])
		if pr.y > 0.15 and pr.y < MAX_VIEW:
			items.append([pr.y, 6, sv, pr.x])
	for cp in corpses:
		var pr := _project(cp["pos"])
		if pr.y > 0.15 and pr.y < 16.0:
			items.append([pr.y + 0.01, 11, cp, pr.x])
	for pk in pickups:
		var pr := _project(pk["pos"])
		if pr.y > 0.15 and pr.y < MAX_VIEW:
			items.append([pr.y, 12, pk, pr.x])
	if not chest.is_empty():
		var pr := _project(chest["pos"])
		if pr.y > 0.15 and pr.y < MAX_VIEW:
			items.append([pr.y, 13, chest, pr.x])
	for c in crew:
		if c["state"] == "in":
			continue
		var pr := _project(c["pos"])
		if pr.y > 0.15 and pr.y < MAX_VIEW:
			items.append([pr.y - 0.02, 14, c, pr.x])
	for it in cargo:
		if it["taken"]:
			continue
		var pr := _project(it["pos"])
		if pr.y > 0.15 and pr.y < MAX_VIEW:
			items.append([pr.y, 7, it, pr.x])
	for b in beacons:
		var pr := _project(b["pos"])
		if pr.y > 0.15 and pr.y < MAX_VIEW:
			items.append([pr.y, 8, b, pr.x])
	if objective_done and phase == "extract":
		var pr := _project(lz)
		if pr.y > 0.15:
			items.append([pr.y, 10, {}, pr.x])
			if pickup_t > 0.0:
				items.append([pr.y - 0.05, 9, {}, pr.x])
	if not _in_cockpit_view():
		var pr := _project(mech_pos)
		if pr.y > 0.15 and pr.y < MAX_VIEW:
			items.append([pr.y, 5, {}, pr.x])
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
				var lw: float = tex3d[o["kind"]]["L"]
				var nest := _is_nest(o)
				var rate := 7.0 if o["moving"] else 0.0
				if nest:
					rate = 2.0
				var ground_z := map.height_at(o["pos"])
				var cut := -1e9
				if o["kind"] == "burrower" and not o["dead"] and (o["under"] or o["emerge"] > 0.0 or o["sink"] > 0.0):
					# A mound of moving earth; while coming up, the body rises out of it.
					var mt3: Texture2D = _view_frame("mound", o["face"], o["pos"], o["anim"] * 6.0)
					var ml3: float = tex3d["mound"]["L"]
					_billboard(mt3, sx, ty, ml3, ml3, ground_z - 0.15, tint.lerp(FOG, fog * 0.85), horizon, proj_scale, col_w)
					if o["under"]:
						continue
					cut = ground_z
				elif o["kind"] == "flyer":
					rate = 14.0
				var frame: Texture2D = _view_frame(o["kind"], o["face"], o["pos"], o["anim"] * rate)
				var mod := tint.lerp(FOG, fog * 0.85)
				var ww: float = lw * (1.0 + o["lunge"] * 0.25)
				var hh: float = lw * (1.0 + o["lunge"] * 0.15)
				var bob: float = absf(sin(o["anim"] * rate * PI * 0.5)) * 0.05 * lw if o["moving"] else 0.0
				if o["kind"] == "flyer":
					bob = sin(o["anim"] * 3.0 + o["seed"]) * 0.08
				if not o["dead"] and cut < -1e8:
					var sh_r: float = st["w"] * 0.45
					if o["kind"] == "flyer":
						sh_r *= clampf(1.0 - (o["fz"] - ground_z) * 0.12, 0.4, 1.0)
					_draw_shadow(o["pos"], ground_z if o["kind"] == "flyer" else o["fz"], sh_r, horizon, proj_scale, fog, ty)
				if o["dead"]:
					var k: float = clampf(o["death_t"] / 0.6, 0.0, 1.0)
					hh *= 1.0 - k
					ww *= 1.0 + k * 0.4
					mod = mod.lerp(Color(0.3, 0.6, 0.1), 0.5)
					mod.a = 1.0 - k
				if o["flash"] > 0.0:
					mod = Color(2.0, 2.0, 2.0)
				_billboard(frame, sx, ty, ww, hh, o["fz"] + bob, mod, horizon, proj_scale, col_w, cut)
				var rect := _body_rect(sx, ty, st["w"], st["h"], o["fz"], horizon, proj_scale)
				if not o["dead"] and (_is_nest(o) or o["kind"] == "brute") and o["hp"] < o["max"] and rect.size.x > 6.0:
					var bar := Rect2(rect.position.x, rect.position.y - 10.0, rect.size.x, 5.0)
					if bar.position.y < _clip_at(c, ty):
						draw_rect(bar, Color(0, 0, 0, 0.6))
						draw_rect(Rect2(bar.position, Vector2(bar.size.x * o["hp"] / o["max"], bar.size.y)), Color(0.9, 0.2, 0.6))
				if o == locked_target and state == State.PLAYING:
					_draw_brackets(rect, Color(1.0, 0.25, 0.2))
			1:
				var mod2 := tint.lerp(FOG, fog * 0.85)
				var pk: String = o["kind"]
				if tex3d.has(pk):
					var pl: float = tex3d[pk]["L"]
					var crushed: bool = o.get("crushed", false)
					if pk == "barrel" and crushed:
						continue
					if not crushed:
						_draw_shadow(o["pos"], o["z"], float(SOLID_PROPS.get(pk, 0.3)) * 0.8, horizon, proj_scale, fog, ty)
					var pt: Texture2D = _view_frame(pk, o.get("face", 0.0), o["pos"], 0.0)
					if crushed:
						# Flattened car, or a felled tree lying in the mud.
						mod2 = mod2.darkened(0.3)
						_billboard(pt, sx, ty, pl * (1.25 if pk == "car" else 1.1), pl * (0.35 if pk == "car" else 0.22), o["z"], mod2, horizon, proj_scale, col_w)
					else:
						_billboard(pt, sx, ty, pl, pl, o["z"], mod2, horizon, proj_scale, col_w)
				else:
					var t: Texture2D = tex[pk][0]
					if pk == "crystal":
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
			4:
				_draw_shadow(o["pos"], o["z"], 0.3, horizon, proj_scale, fog, ty)
				var ct: Texture2D = _view_frame("cache", o["face"], o["pos"], time * 3.0 + o["anim"])
				_billboard(ct, sx, ty, tex3d["cache"]["L"], tex3d["cache"]["L"], o["z"], tint.lerp(FOG, fog * 0.6), horizon, proj_scale, col_w)
			6:
				var sfp: Vector2 = o["pos"]
				var sface := (pos - sfp).angle() + sin(time * 0.7 + o["anim"]) * 0.4
				if o["freed"]:
					sface = o.get("face", sface)
				var st2: Texture2D = _view_frame("survivor", sface, sfp, time * (6.0 if o.get("moving", false) else 3.0) + o["anim"])
				var smod := tint.lerp(FOG, fog * 0.6)
				var sz: float = map.height_at(o["pos"])
				_draw_shadow(sfp, sz, 0.18, horizon, proj_scale, fog, ty)
				var sl: float = tex3d["survivor"]["L"]
				_billboard(st2, sx, ty, sl, sl, sz, smod, horizon, proj_scale, col_w)
			7:
				_draw_shadow(o["pos"], o["z"], 0.28, horizon, proj_scale, fog, ty)
				var itex: Texture2D = _view_frame(o["kind"], o["face"], o["pos"], time * 3.0 + o["anim"])
				var il: float = tex3d[o["kind"]]["L"]
				_billboard(itex, sx, ty, il, il, o["z"], tint.lerp(FOG, fog * 0.6), horizon, proj_scale, col_w)
			14:
				var hk := "hazmat_cut" if o["state"] == "cut" else ("hazmat_carry" if o["carry"] > 0 else "hazmat_walk")
				var hl: float = tex3d[hk]["L"]
				_draw_shadow(o["pos"], o["z"], 0.16, horizon, proj_scale, fog, ty)
				var hf: Texture2D = _view_frame(hk, o["face"], o["pos"], o["anim"] * (5.0 if o["state"] == "cut" else 6.0) if o["moving"] or o["state"] == "cut" else 0.0)
				_billboard(hf, sx, ty, hl, hl, o["z"], tint.lerp(FOG, fog * 0.6), horizon, proj_scale, col_w)
				if o["state"] == "cut":
					var br := _body_rect(sx, ty, 0.5, 0.7, o["z"], horizon, proj_scale)
					if br.size.x > 4.0:
						var pb := Rect2(br.position.x - 6, br.position.y - 10, br.size.x + 12, 5)
						draw_rect(pb, Color(0, 0, 0, 0.6))
						draw_rect(Rect2(pb.position, Vector2(pb.size.x * clampf(o["t"] / CREW_CUT_TIME, 0.0, 1.0), pb.size.y)), Color(0.5, 1.0, 0.3))
			11:
				# A carcass. Harvested ones are hollowed out and grey.
				var ck: String = o["kind"] + "_dead"
				var cl: float = tex3d[ck]["L"]
				var cframe: Texture2D = _view_frame(ck, o["face"], o["pos"], 0.0)
				var cmod := tint.lerp(FOG, fog * 0.85)
				var squash := 1.0
				if o["harvested"]:
					# Cut open and emptied: greyer and flatter.
					cmod = cmod.darkened(0.35).lerp(Color(0.35, 0.33, 0.3), 0.35)
					squash = 0.7
				_billboard(cframe, sx, ty, cl, cl * squash, o["z"], cmod, horizon, proj_scale, col_w)
				if not o["harvested"] and hazmat and on_foot and o == _nearest_corpse() and fmod(time, 0.8) < 0.5:
					_draw_brackets(_body_rect(sx, ty, cl * 0.8, cl * 0.45, o["z"], horizon, proj_scale), Color(0.6, 1.0, 0.3))
			12:
				var pm: String = o["model"]
				var pl2: float = tex3d[pm]["L"]
				_draw_shadow(o["pos"], o["z"], 0.22, horizon, proj_scale, fog, ty)
				_billboard(_view_frame(pm, o["face"], o["pos"], time * 3.0), sx, ty, pl2, pl2, o["z"], tint.lerp(FOG, fog * 0.6), horizon, proj_scale, col_w)
			13:
				var chk := "chest_nosuit" if hazmat else "chest"
				var chl: float = tex3d[chk]["L"]
				_draw_shadow(o["pos"], map.height_at(o["pos"]), 0.6, horizon, proj_scale, fog, ty)
				var chf: Texture2D = _view_frame(chk, o["face"], o["pos"], o["anim"] * 7.0 if o["moving"] else 0.0)
				var cbob: float = absf(sin(o["anim"] * 7.0 * PI * 0.5)) * 0.04 if o["moving"] else 0.0
				_billboard(chf, sx, ty, chl, chl, o["fz"] + cbob, tint.lerp(FOG, fog * 0.7), horizon, proj_scale, col_w)
				# Strapped-in survivors riding on the roof.
				var n_on := 0
				for sv in survivors_list:
					if not sv.get("strapped", false):
						continue
					var right := Vector2.from_angle(angle).orthogonal()
					var off := right * (float(n_on % 3) - 1.0) * 0.32
					var spr := _project(o["pos"] + off)
					if spr.y > 0.15:
						var sl2: float = tex3d["survivor"]["L"] * 0.8
						_billboard(_view_frame("survivor", (pos - o["pos"]).angle(), o["pos"], 0.0), spr.x, spr.y, sl2, sl2, o["fz"] + 1.32 + float(n_on / 3) * 0.1, tint.lerp(FOG, fog * 0.6), horizon, proj_scale, col_w)
					n_on += 1
				if on_foot and _near_chest() and fmod(time, 0.8) < 0.5 and not carrying.is_empty():
					_draw_brackets(_body_rect(sx, ty, 1.2, 1.4, o["fz"], horizon, proj_scale), Color(1.0, 0.75, 0.25))
			8:
				_draw_shadow(o["pos"], o["z"], 0.4, horizon, proj_scale, fog, ty)
				var bk := "beacon_on" if o["done"] else "beacon_off"
				var btex: Texture2D = _view_frame(bk, o["face"], o["pos"], 0.0)
				_billboard(btex, sx, ty, tex3d[bk]["L"], tex3d[bk]["L"], o["z"], tint.lerp(FOG, fog * 0.7), horizon, proj_scale, col_w)
				var brect := _body_rect(sx, ty, 0.7, 2.6, o["z"], horizon, proj_scale)
				if not o["done"] and o["prog"] > 0.0 and brect.size.x > 4.0:
					var pbar := Rect2(brect.position.x - 10, brect.position.y - 12, brect.size.x + 20, 6)
					draw_rect(pbar, Color(0, 0, 0, 0.6))
					draw_rect(Rect2(pbar.position, Vector2(pbar.size.x * o["prog"] / BEACON_TIME, pbar.size.y)), Color(0.3, 0.9, 1.0))
			9:
				# The Gannet coming down onto the landing zone.
				var k9 := clampf(pickup_t / PICKUP_TIME, 0.0, 1.0)
				var dz := map.height_at(lz) + lerpf(16.0, 2.8, 1.0 - pow(1.0 - k9, 3.0))
				var dframes: Array = tex["dropship"]
				_billboard(dframes[int(time * 12.0) % 2], sx, ty, 4.5, 4.5, dz, tint.lerp(FOG, fog * 0.5), horizon, proj_scale, col_w)
			10:
				# Green flare and light beam over the landing zone.
				var gz := map.height_at(lz)
				var gy: float = horizon + (eye_z - gz) * proj_scale / ty
				var bw := clampf(0.25 * proj_scale / ty, 2.0, 30.0)
				var pulse := 0.6 + 0.4 * sin(time * 6.0)
				var c10 := clampi(int(sx / col_w), 0, COLUMNS - 1)
				var clip10 := _clip_at(c10, ty)
				draw_rect(Rect2(sx - bw * 0.5, -40.0, bw, minf(gy, clip10) + 40.0), Color(0.4, 1.0, 0.5, 0.18 * pulse))
				if gy < clip10:
					draw_circle(Vector2(sx, gy), bw * 1.4, Color(0.5, 1.0, 0.6, 0.6 * pulse))
			5:
				_draw_shadow(mech_pos, mech_fz, 0.6, horizon, proj_scale, fog, ty)
				var mt: Texture2D = _view_frame("mech", mech_angle, mech_pos, 0.0)
				var ml: float = tex3d["mech"]["L"]
				_billboard(mt, sx, ty, ml, ml, mech_fz, tint.lerp(FOG, fog * 0.85), horizon, proj_scale, col_w)
				var mrect := _body_rect(sx, ty, 1.3, 2.0, mech_fz, horizon, proj_scale)
				if on_foot and climb_t <= 0.0 and _can_board() == 0 and fmod(time, 0.8) < 0.5:
					_draw_brackets(mrect, Color(0.4, 1.0, 0.6))
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


func _view_frame(kind: String, face: float, at: Vector2, frame_pos: float) -> Texture2D:
	## Picks the pre-rendered view that matches the angle we see the object from.
	var set3: Dictionary = tex3d[kind]
	var rel := wrapf(face - (pos - at).angle(), -PI, PI)
	var d := posmod(int(round(-rel / (TAU / ModelArt.DIRS))), ModelArt.DIRS)
	var frames: Array = set3["dirs"][d]
	return frames[posmod(int(frame_pos), frames.size())]


func _draw_shadow(at: Vector2, z: float, radius: float, horizon: float, ps: float, fog: float, depth: float) -> void:
	## A soft dark ellipse on the ground under an object, in true perspective.
	if z > eye_z - 0.05:
		return
	var center := _project(at)
	if center.y < 0.4:
		return
	var cy := horizon + (eye_z - z) * ps / center.y
	var col_w := get_viewport_rect().size.x / COLUMNS
	if cy >= _clip_at(clampi(int(center.x / col_w), 0, COLUMNS - 1), depth + 0.2):
		return
	var pts := PackedVector2Array()
	for k in 14:
		var pr := _project(at + Vector2.from_angle(TAU * k / 14.0) * radius)
		if pr.y < 0.3:
			return
		pts.append(Vector2(pr.x, horizon + (eye_z - z) * ps / pr.y))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.4 * (1.0 - fog)))


func _body_rect(sx: float, ty: float, w: float, h: float, z: float, horizon: float, ps: float) -> Rect2:
	var bottom := horizon + (eye_z - z) * ps / ty
	var sw := w * ps / ty
	var sh := h * ps / ty
	return Rect2(sx - sw * 0.5, bottom - sh, sw, sh)


func _billboard(t: Texture2D, sx: float, ty: float, ww: float, hh: float, z: float, mod: Color, horizon: float, proj_scale: float, col_w: float, floor_cut := -1e9) -> Rect2:
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
	# Anything below floor_cut (a digger still half in the ground) is hidden.
	var floor_y := horizon + (eye_z - floor_cut) * proj_scale / ty if floor_cut > -1e8 else 1e9
	if top >= floor_y:
		return Rect2(left, top, sw, sh)
	var c0 := maxi(int(floor(left / col_w)), 0)
	var c1 := mini(int(ceil((left + sw) / col_w)), COLUMNS)
	for c in range(c0, c1):
		var clip := _clip_at(c, ty)
		if top >= clip:
			continue
		var vis_bottom := minf(minf(bottom, clip), floor_y)
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


func _carbine_geom(w: float, h: float) -> Array:
	## [grip end, barrel end, muzzle] of the pilot's carbine on screen.
	var sway := Vector2(sin(bob_t) * 12.0, absf(cos(bob_t)) * 9.0) * bob_amount
	var rec: float = recoil[0]
	var base := Vector2(w * 0.74, h * 1.06) + sway + Vector2(rec * 6.0, rec * 16.0)
	var tip := Vector2(w * 0.6, h * 0.76) + sway * 0.6 + Vector2(rec * 3.0, rec * 8.0)
	var dir := (tip - base).normalized()
	return [base, tip, tip + dir * 34.0]


func _glove_col() -> Color:
	return Color(0.9, 0.78, 0.15) if hazmat else Color(0.4, 0.3, 0.2)


func _draw_carried(w: float, h: float) -> void:
	## Both hands full: the load sits low in front of you.
	var sway := Vector2(sin(bob_t * 2.0) * 10.0, absf(sin(bob_t * 2.0)) * 8.0) * bob_amount
	var c := Vector2(w * 0.5, h * 0.9) + sway
	var gl := _glove_col()
	var sleeve := Color(0.85, 0.72, 0.12) if hazmat else Color(0.22, 0.25, 0.2)
	draw_colored_polygon(PackedVector2Array([Vector2(w * 0.12, h + 30), Vector2(w * 0.24, h + 30), c + Vector2(-110, 20), c + Vector2(-150, 0)]), sleeve)
	draw_colored_polygon(PackedVector2Array([Vector2(w * 0.88, h + 30), Vector2(w * 0.76, h + 30), c + Vector2(110, 20), c + Vector2(150, 0)]), sleeve)
	match carrying["kind"]:
		"scrap":
			var cols := [Color(0.55, 0.55, 0.58), Color(0.45, 0.3, 0.2), Color(0.35, 0.37, 0.4), Color(0.6, 0.5, 0.3)]
			for k in 11:
				var o := Vector2(sin(k * 2.3) * 110.0, -50.0 - cos(k * 1.7) * 45.0 - k * 7.0)
				draw_set_transform(c + o, sin(k * 1.3) * 0.7, Vector2.ONE)
				draw_rect(Rect2(-65, -15, 130, 30), cols[k % 4])
				draw_rect(Rect2(-65, -15, 130, 30), Color(0, 0, 0, 0.5), false, 3.0)
				draw_line(Vector2(-50, -4), Vector2(40, -4), Color(1, 1, 1, 0.25), 2.0)
				draw_set_transform(Vector2.ZERO)
		"circuits":
			for k in 3:
				var r2 := Rect2(c + Vector2(-110, -50 - k * 22), Vector2(220, 18))
				draw_rect(r2, Color(0.1, 0.45, 0.2))
				for j in 6:
					draw_rect(Rect2(r2.position + Vector2(14 + j * 34, 4), Vector2(16, 8)), Color(0.12, 0.12, 0.12) if j % 2 == 0 else Color(0.9, 0.75, 0.3))
		"biomass":
			# A stack of jars in a carry crate, up to MAX_JARS.
			var glow := 0.75 + 0.25 * sin(time * 4.0)
			var jars := int(carrying.get("jars", 1))
			draw_circle(c + Vector2(0, -70), 110.0, Color(0.5, 1.0, 0.3, 0.1 * glow))
			for j in jars:
				var col_i := j % 3
				var row_i := j / 3
				var jc := c + Vector2((col_i - 1) * 78.0 + (row_i * 20.0), -60.0 - row_i * 92.0)
				draw_rect(Rect2(jc + Vector2(-32, -45), Vector2(64, 80)), Color(0.45, 0.95, 0.3, 0.85 * glow))
				draw_circle(jc + Vector2(-8, -fmod(time * 30.0 + j * 17.0, 60.0) + 20.0), 4.0, Color(0.8, 1.0, 0.6, 0.6))
				draw_rect(Rect2(jc + Vector2(-36, -55), Vector2(72, 13)), Color(0.4, 0.42, 0.45))
				draw_rect(Rect2(jc + Vector2(-36, 33), Vector2(72, 10)), Color(0.4, 0.42, 0.45))
			draw_rect(Rect2(c + Vector2(-135, -2), Vector2(270, 26)), Color(0.3, 0.25, 0.18))
		_:
			var col := Color(0.55, 0.45, 0.3)
			match String(carrying["model"]):
				"item_fuel": col = Color(0.85, 0.3, 0.15)
				"item_data": col = Color(0.3, 0.6, 0.9)
			draw_rect(Rect2(c + Vector2(-120, -130), Vector2(240, 130)), col)
			draw_rect(Rect2(c + Vector2(-120, -130), Vector2(240, 130)), Color(0, 0, 0, 0.5), false, 3.0)
			draw_rect(Rect2(c + Vector2(-120, -80), Vector2(240, 14)), col.darkened(0.3))
	draw_circle(c + Vector2(-120, -20), 30.0, gl)
	draw_circle(c + Vector2(120, -20), 30.0, gl)


func _draw_harvest(w: float, h: float) -> void:
	## Kneeling at the carcass: forceps, scalpel and a sample jar.
	var t := clampf(harvest_t / HARVEST_TIME, 0.0, 1.0)
	var c := Vector2(w * 0.5, h * 0.86)
	var flesh := Color(0.42, 0.55, 0.2)
	if harvest_target != null and String(harvest_target["kind"]) in ["brute", "hive", "mother"]:
		flesh = Color(0.5, 0.25, 0.5)
	# The open carcass filling the bottom of the view.
	var pts := PackedVector2Array()
	for k in 24:
		var a := PI + PI * k / 23.0
		pts.append(c + Vector2(cos(a) * w * 0.42, sin(a) * h * 0.36 + 60.0))
	pts.append(Vector2(w * 0.92, h + 40))
	pts.append(Vector2(w * 0.08, h + 40))
	draw_colored_polygon(pts, flesh)
	for k in 7:
		var a2 := PI * 1.1 + k * 0.12
		draw_line(c + Vector2(cos(a2) * w * 0.35, sin(a2) * h * 0.3 + 60.0), c + Vector2(cos(a2) * w * 0.12, sin(a2) * h * 0.1 + 70.0), flesh.darkened(0.35), 4.0)
	# The cut opens up and the glowing tissue shows.
	var open := minf(1.0, t * 2.0)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-130, -10), c + Vector2(0, -10 - 50 * open), c + Vector2(130, -10), c + Vector2(0, -10 + 40 * open)]), Color(0.12, 0.2, 0.05))
	draw_circle(c + Vector2(0, -12), 34.0 * open, Color(0.6, 1.0, 0.35, 0.85))
	# Left hand: forceps holding the cut open.
	var lh := c + Vector2(-170 + sin(time * 5.0) * 6.0, -40)
	draw_line(lh, c + Vector2(-40, -20 - 30 * open), Color(0.75, 0.78, 0.8), 5.0)
	draw_line(lh + Vector2(0, 10), c + Vector2(-40, -5 + 25 * open), Color(0.75, 0.78, 0.8), 5.0)
	draw_circle(lh, 34.0, _glove_col())
	draw_colored_polygon(PackedVector2Array([lh + Vector2(-30, 10), lh + Vector2(10, 30), Vector2(w * 0.1, h + 40), Vector2(-40, h + 40)]), Color(0.85, 0.72, 0.12))
	# Right hand: scalpel sawing back and forth, then the jar.
	var rh := c + Vector2(150 + sin(time * 14.0) * 30.0 * (1.0 - t), -50 + cos(time * 14.0) * 10.0)
	if t < 0.75:
		draw_line(rh, rh + Vector2(-90, 30), Color(0.85, 0.88, 0.9), 4.0)
		draw_line(rh + Vector2(-70, 23), rh + Vector2(-100, 34), Color(1, 1, 1), 2.0)
	else:
		var k3 := (t - 0.75) / 0.25
		var jar := c + Vector2(80, -30 - k3 * 120.0)
		draw_rect(Rect2(jar - Vector2(28, 40), Vector2(56, 64)), Color(0.5, 1.0, 0.3, 0.85))
		draw_rect(Rect2(jar - Vector2(31, 48), Vector2(62, 10)), Color(0.4, 0.42, 0.45))
		rh = jar + Vector2(40, 0)
	draw_circle(rh, 34.0, _glove_col())
	draw_colored_polygon(PackedVector2Array([rh + Vector2(30, 10), rh + Vector2(-10, 30), Vector2(w * 0.9, h + 40), Vector2(w + 40, h + 40)]), Color(0.85, 0.72, 0.12))
	# Goo drips
	for k in 5:
		var gy := fmod(time * 90.0 + k * 41.0, 90.0)
		draw_circle(c + Vector2(-60 + k * 30, -10 + gy), 4.0, Color(0.6, 1.0, 0.35, 0.7 * (1.0 - gy / 90.0)))
	var bar := Rect2(w * 0.5 - 160, h * 0.33, 320, 16)
	draw_rect(bar, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * t, bar.size.y)), Color(0.5, 1.0, 0.3))
	_text("HARVESTING BIOMASS", Vector2(w * 0.5, h * 0.33 - 10), 22, Color(0.7, 1.0, 0.5))


func _draw_pilot_gun(w: float, h: float) -> void:
	if harvest_t > 0.0:
		_draw_harvest(w, h)
		return
	if not carrying.is_empty():
		_draw_carried(w, h)
		return
	var g := _carbine_geom(w, h)
	var base: Vector2 = g[0]
	var tip: Vector2 = g[1]
	var muz: Vector2 = g[2]
	var dir := (tip - base).normalized()
	var n := Vector2(-dir.y, dir.x)
	# Gloved hand and sleeve
	var grip := base.lerp(tip, 0.3)
	draw_colored_polygon(PackedVector2Array([Vector2(w + 20, h + 20), Vector2(w * 0.8, h + 20), grip - n * 20 + dir * 10, grip + n * 30 - dir * 10]), Color(0.85, 0.72, 0.12) if hazmat else Color(0.22, 0.25, 0.2))
	draw_circle(grip + n * 4, 26.0, _glove_col())
	# Gun body, magazine, barrel and sight
	draw_colored_polygon(PackedVector2Array([base + n * 30, base - n * 26, tip - n * 12, tip + n * 14]), Color(0.2, 0.21, 0.23))
	draw_polyline(PackedVector2Array([base + n * 30, tip + n * 14, tip - n * 12]), Color(0.38, 0.4, 0.43), 2.0)
	var mag := base.lerp(tip, 0.45)
	draw_colored_polygon(PackedVector2Array([mag - n * 14, mag - n * 14 + dir * 22, mag - n * 52 + dir * 16, mag - n * 50 - dir * 4]), Color(0.14, 0.14, 0.15))
	draw_line(tip, muz, Color(0.1, 0.1, 0.11), 10.0)
	# Left hand gripping the barrel: palm underneath, fingers wrapped over
	# the top, arm coming in from the bottom left.
	var fore := base.lerp(tip, 0.74)
	var sleeve := Color(0.85, 0.72, 0.12) if hazmat else Color(0.22, 0.25, 0.2)
	var gc := _glove_col()
	draw_colored_polygon(PackedVector2Array([Vector2(w * 0.28, h + 40), Vector2(w * 0.44, h + 40), fore - n * 10.0 + dir * 22.0, fore - n * 34.0 - dir * 6.0]), sleeve)
	draw_colored_polygon(PackedVector2Array([fore - n * 12.0 - dir * 20.0, fore - n * 12.0 + dir * 24.0, fore - n * 38.0 + dir * 18.0, fore - n * 40.0 - dir * 14.0]), gc)
	for k in 4:
		var fp := fore + dir * (-14.0 + k * 11.0)
		draw_line(fp - n * 14.0, fp + n * 15.0, gc.darkened(0.45), 10.0)
		draw_line(fp - n * 13.0, fp + n * 13.0, gc, 7.0)
	draw_line(fore - n * 16.0 - dir * 22.0, fore + n * 4.0 - dir * 26.0, gc, 9.0)
	var sight := base.lerp(tip, 0.7) + n * 16
	draw_rect(Rect2(sight - Vector2(5, 9), Vector2(10, 9)), Color(0.12, 0.12, 0.13))
	draw_circle(sight + Vector2(0, -4), 2.0, Color(0.4, 1.0, 0.6))
	if muzzle[0] > 0.0:
		draw_circle(muz + dir * 10.0, 22.0, Color(1.0, 0.75, 0.3, 0.55))
		draw_circle(muz + dir * 6.0, 11.0, Color(1.0, 0.97, 0.8))


func _draw_visor(w: float, h: float) -> void:
	if hazmat:
		# Hazmat hood: a yellow-rimmed faceplate, slightly fogged.
		draw_rect(Rect2(-40, -40, w + 80, h + 80), Color(0.9, 0.95, 0.6, 0.06))
		var y := Color(0.85, 0.72, 0.12, 0.95)
		draw_colored_polygon(PackedVector2Array([Vector2(-40, -40), Vector2(w * 0.12, -40), Vector2(-40, h * 0.45)]), y)
		draw_colored_polygon(PackedVector2Array([Vector2(w + 40, -40), Vector2(w * 0.88, -40), Vector2(w + 40, h * 0.45)]), y)
		draw_colored_polygon(PackedVector2Array([Vector2(-40, h + 40), Vector2(-40, h * 0.7), Vector2(w * 0.08, h + 40)]), y)
		draw_colored_polygon(PackedVector2Array([Vector2(w + 40, h + 40), Vector2(w + 40, h * 0.7), Vector2(w * 0.92, h + 40)]), y)
		var breath := 0.5 + 0.5 * sin(time * 1.6)
		draw_circle(Vector2(w * 0.5, h * 1.05), w * 0.12, Color(1, 1, 1, 0.05 * breath))
	# Helmet visor edges.
	var c := Color(0.02, 0.03, 0.03, 0.85)
	draw_colored_polygon(PackedVector2Array([Vector2(-40, -40), Vector2(w + 40, -40), Vector2(w + 40, h * 0.06), Vector2(w * 0.75, h * 0.02), Vector2(w * 0.25, h * 0.02), Vector2(-40, h * 0.06)]), c)
	draw_colored_polygon(PackedVector2Array([Vector2(-40, -40), Vector2(w * 0.04, -40), Vector2(-40, h * 0.3)]), c)
	draw_colored_polygon(PackedVector2Array([Vector2(w + 40, -40), Vector2(w * 0.96, -40), Vector2(w + 40, h * 0.3)]), c)
	draw_line(Vector2(w * 0.25, h * 0.02), Vector2(w * 0.75, h * 0.02), Color(0.4, 1.0, 0.6, 0.25), 2.0)
	if hit_flash > 0.0:
		draw_rect(Rect2(-40, -40, w + 80, h + 80), Color(1, 0.1, 0.05, hit_flash * 0.8))
	if pilot_hp < pilot_max_hp * 0.35:
		var pulse := 0.15 + 0.12 * sin(time * 7.0)
		draw_rect(Rect2(-40, -40, w + 80, 60), Color(1, 0, 0, pulse))
		draw_rect(Rect2(-40, h - 20, w + 80, 60), Color(1, 0, 0, pulse))


func _draw_climb_overlay(w: float, h: float) -> void:
	var t := _climb_progress()
	var a := sin(t * PI) * 0.92
	draw_rect(Rect2(-40, -40, w + 80, h + 80), Color(0.0, 0.0, 0.0, a))
	# Hatch frame sliding past
	var off := (t - 0.5) * h * (1.0 if climb_out else -1.0)
	draw_rect(Rect2(w * 0.2, h * 0.5 + off - 6.0, w * 0.6, 12.0), Color(0.5, 0.5, 0.45, a * 0.8))
	_text("CLIMBING OUT…" if climb_out else "CLIMBING IN…", Vector2(w * 0.5, h * 0.45), 30, Color(0.4, 1.0, 0.6, a))


func _muzzle_pos(g: int, w: float, h: float) -> Vector2:
	if g == 2:
		return _carbine_geom(w, h)[2]
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
	var ch_r := 12.0 if on_foot else 22.0
	draw_arc(cc, ch_r, 0, TAU, 32, ch_col, 2.0)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_line(cc + d * ch_r * 0.45, cc + d * ch_r * 1.35, ch_col, 2.0)
	draw_circle(cc, 2.0, ch_col)

	# Objective bar
	_text(_objective_string(), Vector2(w * 0.5, h * 0.06 + 30.0), 20, Color(1.0, 0.9, 0.4) if objective_done else hud)
	if radio_t > 0.0 and radio_who != "":
		var who: Dictionary = Story.CAST[radio_who]
		var line := "%s: %s" % [String(who["name"]).to_upper(), radio_text]
		var tw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var ra := clampf(radio_t, 0.0, 1.0)
		draw_rect(Rect2(w * 0.5 - tw * 0.5 - 10, h * 0.06 + 42.0, tw + 20, 28), Color(0, 0, 0, 0.55 * ra))
		var wc: Color = who["color"]
		wc.a = ra
		_text(line, Vector2(w * 0.5, h * 0.06 + 62.0), 17, wc)

	# Retreat button
	var rr := _retreat_rect()
	draw_rect(rr, Color(0.05, 0.06, 0.07, 0.8))
	draw_rect(rr, hud, false, 2.0)
	draw_rect(Rect2(rr.position + Vector2(18, 13), Vector2(6, 20)), hud)
	draw_rect(Rect2(rr.position + Vector2(30, 13), Vector2(6, 20)), hud)
	_text("MENU", rr.get_center() + Vector2(14, 7), 18, hud)

	# Mech status
	var panel := Rect2(16, 72, 150, 150)
	draw_rect(panel, Color(0.02, 0.06, 0.04, 0.75))
	draw_rect(panel, Color(0.2, 0.5, 0.3), false, 1.5)
	var ratios := {}
	for p in GameState.PARTS:
		ratios[p] = parts[p] / GameState.max_hp(p)
	MechDiagram.draw_mech(self, panel.get_center() + Vector2(0, -2), 1.1, ratios, fmod(time, 0.6) < 0.3)
	if on_foot:
		_text("MECH PARKED", Vector2(panel.get_center().x, panel.end.y - 6.0), 14, Color(1.0, 0.85, 0.3))
		var pb := Rect2(16, panel.end.y + 8.0, 150, 18)
		var ratio := pilot_hp / pilot_max_hp
		draw_rect(pb, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(pb.position, Vector2(pb.size.x * ratio, pb.size.y)), MechDiagram.part_color(ratio))
		draw_rect(pb, hud, false, 1.0)
		_text("PILOT %d/%d" % [int(ceil(pilot_hp)), int(pilot_max_hp)], pb.get_center() + Vector2(0, 6), 14, Color.WHITE)

	_draw_minimap(w)

	# Climb out / climb in button
	if state == State.PLAYING:
		var mb := _mech_button_rect(Vector2(w, h))
		var label := "EXIT MECH"
		var lit := true
		if on_foot:
			match _can_board():
				0: label = "CLIMB IN"
				1:
					label = "BOARD (GO TO MECH)"
					lit = false
				2:
					label = "GO TO ITS BACK"
					lit = false
				3:
					label = "BOARD (GET LEVEL)"
					lit = false
		var glow := lit and on_foot and fmod(time, 0.8) < 0.4
		draw_rect(mb, Color(0.1, 0.3, 0.15, 0.9) if glow else Color(0.05, 0.08, 0.07, 0.85))
		draw_rect(mb, hud if lit else Color(0.3, 0.45, 0.35), false, 2.0)
		_text(label, mb.get_center() + Vector2(0, 7), 17, hud if lit else Color(0.5, 0.65, 0.55))
		var act := _action()
		if not act.is_empty():
			var ab := _action_rect(Vector2(w, h))
			var en: bool = act[1]
			var acol := Color(1.0, 0.8, 0.3) if en else Color(0.6, 0.55, 0.4)
			draw_rect(ab, Color(0.25, 0.18, 0.04, 0.9) if en and fmod(time, 1.0) < 0.5 else Color(0.08, 0.07, 0.05, 0.85))
			draw_rect(ab, acol, false, 2.0)
			_text(act[0], ab.get_center() + Vector2(0, 7), 16, acol)

	if on_foot:
		var fy := h * 0.955
		if not carrying.is_empty():
			var what := "CARGO" if carrying["kind"] == "cargo" else "%d %s" % [carrying["amount"], CARRY_NAMES[carrying["kind"]]]
			if carrying["kind"] == "biomass":
				what += " (%d/%d JARS)" % [int(carrying.get("jars", 1)), MAX_JARS]
			_text("CARRYING %s — TAKE IT TO THE CHEST%s" % [what, "   ·   HAZMAT ON" if hazmat else ""], Vector2(w * 0.5, fy), 17, Color(1.0, 0.8, 0.3))
		else:
			_text("CARBINE  %s ROUNDS    %s%s" % [_ammo_str("rounds"), "RUNNING" if running else "PUSH STICK ALL THE WAY TO RUN", "   ·   HAZMAT ON" if hazmat else ""], Vector2(w * 0.5, fy), 17, hud if ammo_left["rounds"] > 0 else Color(1, 0.3, 0.2))
		_draw_hud_messages(w, h, cc)
		return

	# Weapon status on the console
	var cy := h * 0.955
	var gun_txt := "SHELLS %s  L %s R %s" % [_ammo_str("shells"), "●" if parts["left_arm"] > 0.0 else "✕", "●" if parts["right_arm"] > 0.0 else "✕"]
	_text(gun_txt, Vector2(w * 0.5 - 130, cy), 18, hud if ammo_left["shells"] > 0 else Color(1, 0.3, 0.2))
	var bar := Rect2(w * 0.5 + 10, cy - 15, 180, 16)
	var rk_ready := clampf(1.0 - rocket_cd / GameState.rocket_cooldown(), 0.0, 1.0)
	draw_rect(bar, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * rk_ready, bar.size.y)), Color(1.0, 0.6, 0.15) if rk_ready >= 1.0 else Color(0.5, 0.35, 0.15))
	draw_rect(bar, hud, false, 1.0)
	_text(("%s ROCKETS" % _ammo_str("rockets")) + (" READY" if rk_ready >= 1.0 else " · RELOADING"), bar.get_center() + Vector2(0, 30), 14, hud if ammo_left["rockets"] > 0 else Color(1, 0.3, 0.2))

	_draw_hud_messages(w, h, cc)


func _draw_hud_messages(w: float, h: float, cc: Vector2) -> void:
	# Messages
	if msg_t > 0.0 and state == State.PLAYING:
		var a := clampf(msg_t, 0.0, 1.0)
		_text(msg, Vector2(w * 0.5, h * 0.24), 30, Color(1.0, 0.85, 0.3, a))
	if not on_foot and parts["torso"] / GameState.max_hp("torso") < 0.3 and state == State.PLAYING and fmod(time, 0.8) < 0.5:
		_text("HULL CRITICAL", Vector2(w * 0.5, h * 0.15), 26, Color(1, 0.2, 0.15))
	if on_foot and pilot_hp < pilot_max_hp * 0.35 and state == State.PLAYING and fmod(time, 0.8) < 0.5:
		_text("PILOT BADLY HURT — GET BACK IN THE MECH", Vector2(w * 0.5, h * 0.15), 24, Color(1, 0.2, 0.15))

	# Hit direction markers
	for d in dmg_indicators:
		var v := Vector2(sin(d["rel"]), -cos(d["rel"]))
		var p := cc + Vector2(v.x * w * 0.3, v.y * h * 0.3)
		var n := Vector2(-v.y, v.x)
		var a2: float = clampf(d["t"], 0.0, 1.0)
		draw_colored_polygon(PackedVector2Array([p + v * 22.0, p - v * 6.0 + n * 26.0, p - v * 6.0 - n * 26.0]), Color(1, 0.15, 0.1, a2 * 0.85))

	if time < 9.0 and state == State.PLAYING and Settings.show_hints:
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
				LevelMap.RUBBLE:
					c = Color(0.5, 0.42, 0.3, 0.6)
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
		if _is_nest(a):
			var pulse := 6.0 + 2.0 * sin(time * 4.0)
			draw_rect(Rect2(p - Vector2(pulse, pulse), Vector2(pulse, pulse) * 2.0), Color(0.9, 0.3, 1.0))
		elif a.get("under", false):
			# Seismic contact: a pulsing ring.
			if a["awake"]:
				draw_arc(p, 3.0 + fmod(time * 8.0, 6.0), 0, TAU, 10, Color(0.9, 0.6, 0.3, 0.9), 1.5)
		elif a["kind"] == "flyer":
			var fv := Vector2.from_angle(a["face"])
			var col := Color(1.0, 0.55, 0.2) if a["awake"] else Color(0.8, 0.55, 0.2)
			draw_colored_polygon(PackedVector2Array([p + fv * 6.0, p + fv.rotated(2.4) * 5.0, p + fv.rotated(-2.4) * 5.0]), col)
		else:
			draw_circle(p, 3.5 if a["kind"] != "brute" else 5.5, Color(1.0, 0.25, 0.2) if a["awake"] else Color(0.8, 0.55, 0.2))
	var mpulse := 0.5 + 0.5 * sin(time * 5.0)
	if not survival:
		for cp in corpses:
			if cp["harvested"]:
				continue
			var crl: Vector2 = cp["pos"] - pos
			if absf(crl.x) < radius - 0.3 and absf(crl.y) < radius - 0.3:
				draw_rect(Rect2(center + crl * cs - Vector2(2, 2), Vector2(4, 4)), Color(0.5, 0.9, 0.3, 0.7))
		for pk in pickups:
			var prl: Vector2 = pk["pos"] - pos
			if absf(prl.x) < radius - 0.3 and absf(prl.y) < radius - 0.3:
				draw_rect(Rect2(center + prl * cs - Vector2(3, 3), Vector2(6, 6)), Color(1.0, 0.85, 0.2))
	for sv2 in survivors_list:
		if sv2["freed"] and not sv2.get("strapped", false) and not sv2.get("dead", false):
			var frl: Vector2 = sv2["pos"] - pos
			if absf(frl.x) < radius - 0.3 and absf(frl.y) < radius - 0.3:
				draw_circle(center + frl * cs, 3.0, Color(0.6, 1.0, 1.0))
	for c in crew:
		if c["state"] == "in":
			continue
		var crl2: Vector2 = c["pos"] - pos
		if absf(crl2.x) < radius - 0.3 and absf(crl2.y) < radius - 0.3:
			draw_circle(center + crl2 * cs, 2.5, Color(1.0, 0.9, 0.2))
	if not chest.is_empty():
		var chr: Vector2 = chest["pos"] - pos
		var chc := Color(1.0, 0.65, 0.15)
		if absf(chr.x) < radius - 0.3 and absf(chr.y) < radius - 0.3:
			var q := center + chr * cs
			draw_rect(Rect2(q - Vector2(5, 4), Vector2(10, 8)), chc)
			draw_rect(Rect2(q - Vector2(5, 4), Vector2(10, 8)), Color(0, 0, 0), false, 1.0)
		else:
			var cv := chr.normalized()
			draw_rect(Rect2(center + cv * (mm.size.x * 0.5 - 8.0) - Vector2(4, 3), Vector2(8, 6)), chc)
	for sv in survivors_list:
		if sv["freed"]:
			continue
		var srel: Vector2 = sv["pos"] - pos
		if absf(srel.x) < radius - 0.3 and absf(srel.y) < radius - 0.3:
			draw_circle(center + srel * cs, 4.0, Color(1, 1, 1, 0.6 + 0.4 * mpulse))
	for it in cargo:
		if it["taken"]:
			continue
		var irel: Vector2 = it["pos"] - pos
		if absf(irel.x) < radius - 0.3 and absf(irel.y) < radius - 0.3:
			draw_rect(Rect2(center + irel * cs - Vector2(4, 4), Vector2(8, 8)), Color(0.4, 0.9, 1.0))
		else:
			var iv := irel.normalized()
			draw_circle(center + iv * (mm.size.x * 0.5 - 8.0), 3.5, Color(0.4, 0.9, 1.0))
	for b in beacons:
		var brel: Vector2 = b["pos"] - pos
		var bc := Color(0.3, 1.0, 0.5) if b["done"] else Color(0.3, 0.8, 1.0)
		if absf(brel.x) < radius - 0.3 and absf(brel.y) < radius - 0.3:
			draw_arc(center + brel * cs, 6.0, 0, TAU, 12, bc, 2.0)
		elif not b["done"]:
			var bv := brel.normalized()
			draw_circle(center + bv * (mm.size.x * 0.5 - 8.0), 3.5, bc)
	for bp: Vector2 in breaches:
		var prel := bp - pos
		if absf(prel.x) < radius - 0.3 and absf(prel.y) < radius - 0.3:
			var q := center + prel * cs
			draw_line(q - Vector2(4, 4), q + Vector2(4, 4), Color(1, 0.3, 0.3), 2.0)
			draw_line(q - Vector2(4, -4), q + Vector2(4, -4), Color(1, 0.3, 0.3), 2.0)
	var lrel := lz - pos
	var lcol := Color(0.4, 1.0, 0.5, 0.9 if objective_done else 0.35)
	if absf(lrel.x) < radius - 0.3 and absf(lrel.y) < radius - 0.3:
		draw_arc(center + lrel * cs, LZ_RADIUS * cs * (0.8 + 0.2 * mpulse if objective_done else 1.0), 0, TAU, 24, lcol, 2.0)
	elif objective_done:
		var lv := lrel.normalized()
		var le := center + lv * (mm.size.x * 0.5 - 10.0)
		draw_circle(le, 6.0, lcol)
	for cc in caches:
		if cc["taken"]:
			continue
		var crel: Vector2 = cc["pos"] - pos
		if absf(crel.x) < radius - 0.3 and absf(crel.y) < radius - 0.3:
			draw_rect(Rect2(center + crel * cs - Vector2(3, 3), Vector2(6, 6)), Color(1.0, 0.85, 0.2))
	if on_foot:
		var mrel := mech_pos - pos
		var mp := center + mrel * cs
		if absf(mrel.x) < radius - 0.3 and absf(mrel.y) < radius - 0.3:
			draw_circle(mp, 6.0, Color(0.4, 1.0, 0.6))
			draw_line(mp, mp + Vector2.from_angle(mech_angle) * 10.0, Color(0.4, 1.0, 0.6), 2.0)
		else:
			var mv := mrel.normalized()
			var me := center + mv * (mm.size.x * 0.5 - 8.0)
			draw_circle(me, 6.0, Color(0.4, 1.0, 0.6))
	# Off-screen hive arrows so the player always knows where to go.
	for a in aliens:
		if a["dead"] or not _is_nest(a):
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
	if not survival:
		_text("IN CHEST: SCRAP %d · CIRC %d · BIO %d" % [loot["scrap"], loot["circuits"], loot["biomass"]], Vector2(mm.get_center().x, mm.end.y + 156.0), 13, Color(0.9, 0.85, 0.6, 0.9))
		if rescued > 0:
			_text("%d SURVIVOR%s STRAPPED IN" % [rescued, "S" if rescued > 1 else ""], Vector2(mm.get_center().x, mm.end.y + 174.0), 13, Color(0.9, 0.85, 0.6, 0.9))


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

	if climb_t > 0.0:
		return
	if on_foot:
		var jc := _rocket_center(Vector2(w, h))
		draw_circle(jc, ROCKET_R, Color(0.3, 0.7, 1.0, 0.35 if jump_z <= 0.0 else 0.15))
		draw_arc(jc, ROCKET_R, 0, TAU, 40, Color(0.6, 0.85, 1.0, 0.9), 3.0)
		_text("JUMP", jc + Vector2(0, 7), 20, Color(1, 1, 1, 0.85))
		return
	var rc := _rocket_center(Vector2(w, h))
	var rk_ready := clampf(1.0 - rocket_cd / GameState.rocket_cooldown(), 0.0, 1.0)
	draw_circle(rc, ROCKET_R, Color(1.0, 0.55, 0.1, 0.4 if rk_ready >= 1.0 else 0.15))
	draw_arc(rc, ROCKET_R, -PI * 0.5, -PI * 0.5 + TAU * rk_ready, 40, Color(1, 0.75, 0.3, 0.9), 4.0)
	_text("RKT", rc + Vector2(0, 7), 20, Color(1, 1, 1, 0.85 if rk_ready >= 1.0 else 0.4))


func _draw_end_screen(w: float, h: float) -> void:
	var k := clampf(end_time / 0.8, 0.0, 1.0)
	draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.65 * k))
	if survival:
		_draw_survival_end(w, h, k)
		return
	var title := "EXTRACTED"
	var col := Color(0.4, 1.0, 0.6)
	if state == State.LOST:
		title = "PILOT DOWN" if pilot_down else "MECH DOWN"
		col = Color(1.0, 0.3, 0.2)
	elif state == State.RETREATED:
		title = "ABORTED"
		col = Color(1.0, 0.8, 0.3)
	col.a = k
	_text(title, Vector2(w * 0.5, h * 0.3), 54, col)
	_text(String(op.get("title", "")) + " — " + String(op.get("zone", "")), Vector2(w * 0.5, h * 0.37), 22, Color(1, 1, 1, 0.8 * k))
	var lines := [
		"Objective: " + ("complete" if objective_done else "not complete"),
		"Aliens killed: %d     Survivors rescued: %d" % [kills, rescued],
		"In the Chest: %d scrap · %d circuits · %d biomass" % [loot["scrap"], loot["circuits"], loot["biomass"]],
		"Ammo left: %d shells · %d rockets · %d rounds" % [ammo_left["shells"], ammo_left["rockets"], ammo_left["rounds"]],
	]
	if state == State.LOST:
		lines.append("Rafa hauled Brigid home under fire. Half the salvage was lost.")
	for i in lines.size():
		_text(lines[i], Vector2(w * 0.5, h * 0.46 + i * 36), 22, Color(1, 1, 1, k))
	if end_time > 1.2:
		var blink := 0.5 + 0.5 * sin(time * 4.0)
		_text("TAP TO FLY HOME TO THE ROCK", Vector2(w * 0.5, h * 0.84), 24, Color(1, 0.85, 0.3, blink))


func _draw_survival_end(w: float, h: float, k: float) -> void:
	var title := "RUN OVER"
	if state == State.LOST:
		title = "PILOT DOWN" if pilot_down else "BRIGID DOWN"
	_text(title, Vector2(w * 0.5, h * 0.28), 54, Color(1.0, 0.45, 0.25, k))
	_text("Survival — " + String(zone_theme["name"]), Vector2(w * 0.5, h * 0.35), 22, Color(1, 1, 1, 0.8 * k))
	_text("WAVE %d" % wave, Vector2(w * 0.5, h * 0.5), 64, Color(1.0, 0.85, 0.3, k))
	_text("%d aliens killed" % kills, Vector2(w * 0.5, h * 0.58), 26, Color(1, 1, 1, k))
	if new_best:
		var glow := 0.6 + 0.4 * sin(time * 6.0)
		_text("NEW BEST!", Vector2(w * 0.5, h * 0.67), 34, Color(0.4, 1.0, 0.6, k * glow))
	else:
		_text("Best: wave %d · %d kills" % [int(best_before["wave"]), int(best_before["kills"])], Vector2(w * 0.5, h * 0.67), 22, Color(0.8, 0.85, 0.8, k))
	if end_time > 1.2:
		var blink := 0.5 + 0.5 * sin(time * 4.0)
		_text("TAP TO RETURN TO THE MENU", Vector2(w * 0.5, h * 0.84), 24, Color(1, 0.85, 0.3, blink))


func _ammo_str(kind: String) -> String:
	return "∞" if survival else str(ammo_left[kind])
