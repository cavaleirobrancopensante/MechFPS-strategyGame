extends Node
## Campaign state for life at the Rock (autoload "GameState"):
## resources, ammunition, base modules and their crews, research, the
## mech's damage, the story, and the operations on the map-room board.

const Story = preload("res://scripts/story.gd")

const VERSION := "3.1"
const SLOT_COUNT := 3
const META_PATH := "user://meta.cfg"
const OLD_SAVE_PATH := "user://rock_save.cfg"

# --- Mech ---------------------------------------------------------------------
const PARTS := ["torso", "left_arm", "right_arm", "legs"]
const PART_NAMES := {"torso": "Torso", "left_arm": "Left Arm", "right_arm": "Right Arm", "legs": "Legs"}
const BASE_MAX_HP := {"torso": 120.0, "left_arm": 60.0, "right_arm": 60.0, "legs": 80.0}
const SCRAP_PER_HP := 0.25

# --- Resources and ammunition -------------------------------------------------
const RESOURCES := ["scrap", "circuits", "biomass", "fuel"]
const RES_NAMES := {"scrap": "Scrap", "circuits": "Circuits", "biomass": "Biomass", "fuel": "Fuel"}
const RES_COLORS := {"scrap": Color(0.75, 0.75, 0.8), "circuits": Color(0.4, 0.9, 1.0), "biomass": Color(0.6, 1.0, 0.4), "fuel": Color(1.0, 0.75, 0.3)}
const AMMO := ["shells", "rockets", "rounds"]
const AMMO_NAMES := {"shells": "Cannon shells", "rockets": "Rockets", "rounds": "Carbine rounds"}
const AMMO_BASE_CAP := {"shells": 400, "rockets": 6, "rounds": 120}

# --- Research (Sandoval's lab) ------------------------------------------------
## Cost doubles, triples... with each level.
const RESEARCH := {
	"cannon": {"name": "Autocannon Calibre", "desc": "+25% cannon damage", "max": 5, "cost": {"scrap": 20, "circuits": 3, "biomass": 10}},
	"armor": {"name": "Armour Plating", "desc": "+20% max HP on every part", "max": 5, "cost": {"scrap": 30, "circuits": 2, "biomass": 10}},
	"servos": {"name": "Leg Servos", "desc": "+10% walking speed", "max": 4, "cost": {"scrap": 15, "circuits": 4, "biomass": 5}},
	"rockets": {"name": "Rocket Pod", "desc": "+30% rocket damage, faster reload", "max": 4, "cost": {"scrap": 20, "circuits": 5, "biomass": 10}},
	"racks": {"name": "Ammo Racks", "desc": "+25% ammunition carried on missions", "max": 4, "cost": {"scrap": 25, "circuits": 2, "biomass": 5}},
	"carbine": {"name": "Carbine Upgrade", "desc": "+30% carbine damage", "max": 3, "cost": {"scrap": 10, "circuits": 3, "biomass": 10}},
	"suit": {"name": "Pilot Armour", "desc": "+15 pilot health on foot", "max": 3, "cost": {"scrap": 10, "circuits": 2, "biomass": 15}},
}

# --- Base modules -------------------------------------------------------------
const SLOT_NAMES := ["Old Quarry", "Cloister Yard", "Boathouse", "South Field", "Crypt", "Bell Tower"]
const BUILDINGS := {
	"crane": {"name": "Salvage Crane", "desc": "Hauls scrap from the old quarry every night.", "workers": 1, "cost": {"scrap": 30, "circuits": 2}},
	"ammo": {"name": "Ammo Factory", "desc": "Turns scrap into shells, rockets or rounds.", "workers": 2, "cost": {"scrap": 50, "circuits": 6}},
	"reactor": {"name": "Bioreactor", "desc": "Turns alien biomass into dropship fuel.", "workers": 1, "cost": {"scrap": 40, "circuits": 6}},
	"circuits": {"name": "Circuit Shop", "desc": "Strips scrap down for usable electronics.", "workers": 1, "cost": {"scrap": 35, "circuits": 2}},
	"bunks": {"name": "Bunkhouse", "desc": "Beds for 4 more survivors per level.", "workers": 0, "cost": {"scrap": 25, "circuits": 0}},
	"radio": {"name": "Radio Mast", "desc": "One more operation on the board; caches show on the minimap.", "workers": 1, "cost": {"scrap": 40, "circuits": 10}},
}
const MAX_LEVEL := 3
const BASE_BEDS := 6

# --- State --------------------------------------------------------------------
var day := 1
var res := {}
var ammo := {}
var survivors := 6   ## people living on the Rock (the crew you assign to jobs)
var slots: Array = []
var ammo_focus := "shells"
var research := {}
var part_hp := {}
var story_index := 0
var operations: Array = []
var current_mission := {}
var loadout := {}
var last_report := {}
var missions_won := 0
var kills_total := 0
var chatter_i := 0

## "campaign" or "survival". Survival never touches the campaign save.
var mode := "campaign"
var slot := 1
var last_slot := 0
var survival_best := {"wave": 0, "kills": 0}


func _ready() -> void:
	new_campaign(false)
	_load_meta()
	# Older versions kept one save: move it into slot 1.
	if FileAccess.file_exists(OLD_SAVE_PATH) and not FileAccess.file_exists(slot_path(1)):
		DirAccess.rename_absolute(OLD_SAVE_PATH, slot_path(1))
		if last_slot == 0:
			last_slot = 1
			_save_meta()


# =============================================================================
# Save slots and modes
# =============================================================================

func slot_path(i: int) -> String:
	return "user://rock_slot_%d.cfg" % i


func slot_summary(i: int) -> Dictionary:
	## {} if empty, else {day, story, people, saved_at}.
	var cf := ConfigFile.new()
	if cf.load(slot_path(i)) != OK:
		return {}
	var story_i: int = cf.get_value("rock", "story_index", 0)
	var title := "Campaign complete" if story_i >= Story.STORY_MISSIONS.size() else "Next: " + String(Story.STORY_MISSIONS[story_i]["title"])
	return {"day": cf.get_value("rock", "day", 1), "story": title, "people": cf.get_value("rock", "survivors", 0), "saved_at": cf.get_value("rock", "saved_at", "")}


func start_new_game(i: int) -> void:
	slot = i
	mode = "campaign"
	new_campaign(true)
	last_slot = i
	_save_meta()


func load_slot(i: int) -> bool:
	if not FileAccess.file_exists(slot_path(i)):
		return false
	slot = i
	mode = "campaign"
	new_campaign(false)
	load_game()
	last_slot = i
	_save_meta()
	return true


func delete_slot(i: int) -> void:
	if FileAccess.file_exists(slot_path(i)):
		DirAccess.remove_absolute(slot_path(i))
	if last_slot == i:
		last_slot = 0
		_save_meta()


func start_survival() -> void:
	# Survival runs on a fresh, stock Brigid: campaign upgrades don't carry
	# over (the campaign itself stays safe in its save slot).
	new_campaign(false)
	slot = 0
	mode = "survival"
	current_mission = {"title": "Survival", "zone": "", "type": "endless", "diff": 1, "fuel": 0,
		"seed": randi(), "reward": {}, "briefing": []}
	loadout = {"shells": 999999, "rockets": 999999, "rounds": 999999}


func record_survival(wave: int, kills: int) -> bool:
	var best := wave > int(survival_best["wave"]) or (wave == int(survival_best["wave"]) and kills > int(survival_best["kills"]))
	if best:
		survival_best = {"wave": wave, "kills": kills}
		_save_meta()
	return best


func _save_meta() -> void:
	var cf := ConfigFile.new()
	cf.set_value("meta", "last_slot", last_slot)
	cf.set_value("meta", "survival_best", survival_best)
	cf.save(META_PATH)


func _load_meta() -> void:
	var cf := ConfigFile.new()
	if cf.load(META_PATH) != OK:
		return
	last_slot = cf.get_value("meta", "last_slot", 0)
	survival_best = cf.get_value("meta", "survival_best", survival_best)


func new_campaign(save := true) -> void:
	day = 1
	res = {"scrap": 60, "circuits": 8, "biomass": 0, "fuel": 6}
	ammo = {"shells": 700, "rockets": 10, "rounds": 200}
	survivors = 6
	slots = [{"type": "crane", "level": 1, "crew": 1}, {"type": "ammo", "level": 1, "crew": 2}, {}, {}, {}, {}]
	ammo_focus = "shells"
	research = {}
	for k in RESEARCH:
		research[k] = 0
	part_hp = {}
	for p in PARTS:
		part_hp[p] = max_hp(p)
	story_index = 0
	current_mission = {}
	loadout = {}
	last_report = {}
	missions_won = 0
	kills_total = 0
	generate_operations()
	if save:
		save_game()


# =============================================================================
# Derived stats
# =============================================================================

func max_hp(part: String) -> float:
	return BASE_MAX_HP[part] * (1.0 + 0.2 * research.get("armor", 0))


func hp_ratio(part: String) -> float:
	return clampf(part_hp.get(part, 0.0) / max_hp(part), 0.0, 1.0)


func cannon_damage() -> float:
	return 9.0 * (1.0 + 0.25 * research["cannon"])


func rocket_damage() -> float:
	return 70.0 * (1.0 + 0.3 * research["rockets"])


func rocket_cooldown() -> float:
	return maxf(2.0, 5.0 - 0.6 * research["rockets"])


func walk_speed() -> float:
	return 2.6 * (1.0 + 0.1 * research["servos"])


func carbine_damage() -> float:
	return 8.0 * (1.0 + 0.3 * research["carbine"])


func pilot_max_hp() -> float:
	return 40.0 + 15.0 * research["suit"]


func ammo_caps() -> Dictionary:
	var k: float = 1.0 + 0.25 * research["racks"]
	return {"shells": int(AMMO_BASE_CAP["shells"] * k), "rockets": int(AMMO_BASE_CAP["rockets"] * k), "rounds": int(AMMO_BASE_CAP["rounds"] * k)}


func mission_diff() -> int:
	return int(current_mission.get("diff", 1))


func mission_seed() -> int:
	return int(current_mission.get("seed", 17))


# =============================================================================
# Resources
# =============================================================================

func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if res.get(k, 0) < cost[k]:
			return false
	return true


func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k in cost:
		res[k] -= cost[k]
	return true


static func cost_text(cost: Dictionary) -> String:
	var parts_txt: Array[String] = []
	for k in ["scrap", "circuits", "biomass", "fuel"]:
		if cost.get(k, 0) > 0:
			parts_txt.append("%d %s" % [cost[k], RES_NAMES[k].to_lower()])
	return ", ".join(parts_txt) if not parts_txt.is_empty() else "free"


static func scaled(cost: Dictionary, mult: float) -> Dictionary:
	var out := {}
	for k in cost:
		out[k] = int(ceil(cost[k] * mult))
	return out


# =============================================================================
# Research
# =============================================================================

func research_cost(id: String) -> Dictionary:
	return scaled(RESEARCH[id]["cost"], research[id] + 1)


func research_maxed(id: String) -> bool:
	return research[id] >= RESEARCH[id]["max"]


func do_research(id: String) -> bool:
	if research_maxed(id) or not pay(research_cost(id)):
		return false
	if id == "armor":
		var ratios := {}
		for p in PARTS:
			ratios[p] = hp_ratio(p)
		research[id] += 1
		for p in PARTS:
			part_hp[p] = ratios[p] * max_hp(p)
	else:
		research[id] += 1
	save_game()
	return true


# =============================================================================
# Repairs
# =============================================================================

func repair_cost(part: String) -> int:
	return int(ceil((max_hp(part) - part_hp[part]) * SCRAP_PER_HP))


func repair(part: String) -> void:
	var missing: float = max_hp(part) - part_hp[part]
	if missing <= 0.0:
		return
	var amount := minf(missing, float(res["scrap"]) / SCRAP_PER_HP)
	res["scrap"] = maxi(0, res["scrap"] - int(ceil(amount * SCRAP_PER_HP)))
	part_hp[part] = minf(part_hp[part] + amount, max_hp(part))
	save_game()


func repair_all() -> void:
	for p in PARTS:
		repair(p)


func total_repair_cost() -> int:
	var t := 0
	for p in PARTS:
		t += repair_cost(p)
	return t


# =============================================================================
# Base modules and crew
# =============================================================================

func beds() -> int:
	var b := BASE_BEDS
	for s in slots:
		if s.get("type", "") == "bunks":
			b += 4 * int(s["level"])
	return b


func workers_total() -> int:
	## People who can work: everyone with a bed.
	return mini(survivors, beds())


func crew_required(slot_i: int) -> int:
	## Bigger buildings need more hands.
	var sl: Dictionary = slots[slot_i]
	if not sl.has("type"):
		return 0
	var w: int = BUILDINGS[sl["type"]]["workers"]
	return 0 if w == 0 else w + int(sl["level"]) - 1


func crew_assigned() -> int:
	var n := 0
	for sl in slots:
		n += int(sl.get("crew", 0))
	return n


func idle_people() -> int:
	return workers_total() - crew_assigned()


func crew_factor(slot_i: int) -> float:
	var req := crew_required(slot_i)
	if req == 0:
		return 1.0
	return clampf(float(slots[slot_i].get("crew", 0)) / req, 0.0, 1.0)


func assign_crew(slot_i: int, delta: int) -> void:
	var sl: Dictionary = slots[slot_i]
	if not sl.has("type"):
		return
	var cur: int = sl.get("crew", 0)
	var nxt := clampi(cur + delta, 0, crew_required(slot_i))
	if nxt > cur and idle_people() <= 0:
		return
	sl["crew"] = nxt
	save_game()


func auto_assign() -> void:
	## Sends idle people to unfilled jobs (slot order), and pulls crew off
	## jobs if beds were lost.
	while crew_assigned() > workers_total():
		for i in range(slots.size() - 1, -1, -1):
			if slots[i].get("crew", 0) > 0:
				slots[i]["crew"] -= 1
				break
	for i in slots.size():
		while idle_people() > 0 and slots[i].has("type") and slots[i].get("crew", 0) < crew_required(i):
			slots[i]["crew"] = slots[i].get("crew", 0) + 1


func staffing() -> Array:
	## Whether each slot is running at all (has at least some crew, or needs none).
	var out: Array = []
	for i in slots.size():
		out.append(slots[i].has("type") and crew_factor(i) > 0.0)
	return out


func has_building(type: String, staffed_only := true) -> bool:
	var st := staffing()
	for i in slots.size():
		if slots[i].get("type", "") == type and (st[i] or not staffed_only):
			return true
	return false


func build_cost(type: String) -> Dictionary:
	return BUILDINGS[type]["cost"]


func upgrade_cost(slot_i: int) -> Dictionary:
	var s: Dictionary = slots[slot_i]
	return scaled(BUILDINGS[s["type"]]["cost"], s["level"] + 1)


func build(slot_i: int, type: String) -> bool:
	if slots[slot_i].has("type") or not pay(build_cost(type)):
		return false
	slots[slot_i] = {"type": type, "level": 1, "crew": 0}
	auto_assign()
	save_game()
	return true


func upgrade(slot_i: int) -> bool:
	var s: Dictionary = slots[slot_i]
	if not s.has("type") or s["level"] >= MAX_LEVEL or not pay(upgrade_cost(slot_i)):
		return false
	s["level"] += 1
	auto_assign()
	save_game()
	return true


func demolish(slot_i: int) -> void:
	var s: Dictionary = slots[slot_i]
	if not s.has("type"):
		return
	# Half the build cost comes back as scrap.
	res["scrap"] += int(BUILDINGS[s["type"]]["cost"]["scrap"] * 0.5)
	slots[slot_i] = {}
	auto_assign()
	save_game()


func _out(slot_i: int, full: int) -> int:
	## Output scaled by how many of the jobs are filled.
	return int(floor(full * crew_factor(slot_i)))


func production_preview(slot_i: int) -> String:
	var s: Dictionary = slots[slot_i]
	if not s.has("type"):
		return ""
	var l: int = s["level"]
	match s["type"]:
		"crane": return "+%d scrap / night" % _out(slot_i, [0, 6, 10, 15][l])
		"circuits": return "Up to %d circuits / night (4 scrap each)" % _out(slot_i, [0, 2, 3, 5][l])
		"reactor": return "Up to %d biomass → %d fuel / night" % [_out(slot_i, [0, 6, 12, 18][l]), _out(slot_i, [0, 6, 12, 18][l]) / 2]
		"ammo":
			var budget: int = _out(slot_i, [0, 6, 10, 15][l])
			match ammo_focus:
				"shells": return "Up to %d shells / night (%d scrap)" % [budget * 40, budget]
				"rockets": return "Up to %d rockets / night (2 scrap + 1 circuit each)" % [budget / 2]
				_: return "Up to %d rounds / night (%d scrap)" % [budget * 15, budget]
		"bunks": return "%d beds" % [4 * l]
		"radio": return "+1 operation; caches on minimap"
	return ""


func run_night() -> Array:
	## Overnight production. Returns report lines.
	var lines: Array = []
	var st := staffing()
	# The crew always scavenges a little by hand.
	res["scrap"] += 2
	for i in slots.size():
		var s: Dictionary = slots[i]
		if not s.has("type"):
			continue
		var bname: String = BUILDINGS[s["type"]]["name"]
		if not st[i]:
			if BUILDINGS[s["type"]]["workers"] > 0:
				lines.append("%s: nobody assigned, so it sat idle." % bname)
			continue
		var l: int = s["level"]
		match s["type"]:
			"crane":
				var n: int = _out(i, [0, 6, 10, 15][l])
				res["scrap"] += n
				lines.append("%s: +%d scrap." % [bname, n])
			"circuits":
				var made := mini(_out(i, [0, 2, 3, 5][l]), res["scrap"] / 4)
				res["scrap"] -= made * 4
				res["circuits"] += made
				lines.append("%s: +%d circuits." % [bname, made] if made > 0 else "%s: not enough scrap." % bname)
			"reactor":
				var bio := mini(_out(i, [0, 6, 12, 18][l]), res["biomass"])
				bio -= bio % 2
				res["biomass"] -= bio
				res["fuel"] += bio / 2
				lines.append("%s: %d biomass → +%d fuel." % [bname, bio, bio / 2] if bio > 0 else "%s: no biomass to burn." % bname)
			"ammo":
				var budget: int = mini(_out(i, [0, 6, 10, 15][l]), res["scrap"])
				match ammo_focus:
					"shells":
						res["scrap"] -= budget
						ammo["shells"] += budget * 40
						lines.append("%s: +%d cannon shells." % [bname, budget * 40])
					"rockets":
						var n := mini(budget / 2, res["circuits"])
						res["scrap"] -= n * 2
						res["circuits"] -= n
						ammo["rockets"] += n
						lines.append("%s: +%d rockets." % [bname, n] if n > 0 else "%s: needs scrap and circuits for rockets." % bname)
					_:
						res["scrap"] -= budget
						ammo["rounds"] += budget * 15
						lines.append("%s: +%d carbine rounds." % [bname, budget * 15])
				if budget == 0 and ammo_focus != "rockets":
					lines[-1] = "%s: no scrap to work with." % name
	if survivors > beds():
		lines.append("%d people are sleeping in the chapel and can't work. Build bunks." % (survivors - beds()))
	if idle_people() > 0:
		lines.append("%d people had no job. Assign them in the Base tab." % idle_people())
	return lines


# =============================================================================
# Operations
# =============================================================================

func generate_operations() -> void:
	operations.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = day * 7919 + story_index * 104729 + 3
	if story_index < Story.STORY_MISSIONS.size():
		var sm: Dictionary = Story.STORY_MISSIONS[story_index].duplicate(true)
		sm["story"] = true
		sm["seed"] = 5000 + story_index * 977
		sm["act_title"] = ["", "Act I — Landfall", "Act II — The Singing", "Act III — The Brood Mother"][sm["act"]]
		operations.append(sm)
	var side_count := 2 + (1 if has_building("radio") else 0)
	var types := ["destroy", "rescue", "retrieve", "survive", "scout"]
	var used: Array = []
	for i in side_count:
		var t: String = types[rng.randi_range(0, types.size() - 1)]
		while used.has(t) and used.size() < types.size():
			t = types[rng.randi_range(0, types.size() - 1)]
		used.append(t)
		operations.append(_side_op(t, rng, 1 + (i % 2)))
	operations.append(_side_op("patrol", rng, 0))


func _side_op(t: String, rng: RandomNumberGenerator, fuel: int) -> Dictionary:
	var d := clampi(1 + day / 3 + (1 if fuel >= 2 else 0) - (1 if fuel == 0 else 0), 1, 9)
	var zone: String = Story.ZONES[rng.randi_range(0, Story.ZONES.size() - 1)]
	var text: Dictionary = Story.SIDE_TEXT[t]
	var title: String = text["titles"][rng.randi_range(0, text["titles"].size() - 1)]
	var brief: Array = text["briefing"][rng.randi_range(0, text["briefing"].size() - 1)].duplicate()
	brief[1] = String(brief[1]).replace("{zone}", zone)
	var m := 1.5 if fuel >= 2 else (0.5 if fuel == 0 else 1.0)
	var op := {"story": false, "title": title.replace("{zone}", zone), "zone": zone, "type": t, "diff": d, "fuel": fuel,
		"seed": rng.randi(), "briefing": [brief], "hives": 0}
	match t:
		"destroy":
			op["hives"] = 1 + (1 if d >= 3 else 0) + (1 if d >= 6 else 0)
			op["reward"] = scaled({"scrap": 12 + 4 * d, "circuits": 1 + d / 2}, m)
		"rescue":
			op["rescue"] = 2 + d / 3
			op["hives"] = 1
			op["reward"] = scaled({"scrap": 8 + 2 * d}, m)
		"retrieve":
			op["items"] = 3 + d / 3
			op["item_kind"] = "supply"
			op["reward"] = scaled({"scrap": 10 + 3 * d, "circuits": 2 + d / 2}, m)
		"survive":
			op["waves"] = 3 + d / 2
			op["reward"] = scaled({"scrap": 20 + 5 * d, "circuits": 2 + d / 3}, m)
		"scout":
			op["beacons"] = 3
			op["hives"] = 1
			op["reward"] = scaled({"scrap": 8, "circuits": 5 + d}, m)
		"patrol":
			op["type"] = "destroy"
			op["hives"] = 1
			op["reward"] = {"scrap": 8}
	return op


static func objective_text(op: Dictionary) -> String:
	match op.get("type", ""):
		"destroy": return "Destroy %d hive%s" % [op["hives"], "" if op["hives"] == 1 else "s"]
		"rescue": return "Rescue %d survivors" % op["rescue"]
		"retrieve":
			var kind: String = {"fuel": "fuel canisters", "data": "data cores"}.get(op.get("item_kind", ""), "supply crates")
			return "Recover %d %s" % [op["items"], kind]
		"survive": return "Survive %d waves" % op["waves"]
		"scout": return "Activate %d relay beacons" % op["beacons"]
		"boss": return "Kill the Brood Mother"
	return ""


func launch(op_i: int) -> bool:
	var op: Dictionary = operations[op_i]
	if res["fuel"] < op["fuel"]:
		return false
	res["fuel"] -= op["fuel"]
	current_mission = op.duplicate(true)
	# Load ammunition from the stockpile, up to what Brigid can carry.
	var caps := ammo_caps()
	loadout = {}
	for a in AMMO:
		var n := mini(caps[a], ammo[a])
		loadout[a] = n
		ammo[a] -= n
	save_game()
	return true


func apply_mission_result(r: Dictionary) -> void:
	## r: won, aborted, pilot_down, kills, rescued,
	## loot {scrap, circuits, biomass, shells, rockets, rounds}, ammo_left, parts.
	var op := current_mission
	var won: bool = r.get("won", false)
	var lost: bool = not won and not r.get("aborted", false)
	var lines: Array = []
	var loot: Dictionary = r.get("loot", {})

	# Unused ammunition goes back on the shelf, plus anything found.
	var ammo_left: Dictionary = r.get("ammo_left", loadout)
	for a in AMMO:
		ammo[a] += int(ammo_left.get(a, 0)) + int(loot.get(a, 0))

	var keep := 0.5 if lost else 1.0
	var gained := {}
	for k in ["scrap", "circuits", "biomass"]:
		var n := int(loot.get(k, 0) * keep)
		if n > 0:
			res[k] += n
			gained[k] = n
	if won:
		var reward: Dictionary = op.get("reward", {})
		for k in reward:
			res[k] = res.get(k, 0) + reward[k]
			gained[k] = gained.get(k, 0) + reward[k]
		missions_won += 1
	var rescued: int = r.get("rescued", 0)
	survivors += rescued
	auto_assign()
	kills_total += int(r.get("kills", 0))

	var parts: Dictionary = r.get("parts", {})
	for p in PARTS:
		part_hp[p] = clampf(parts.get(p, part_hp[p]), 0.0, max_hp(p))
	if lost:
		part_hp["torso"] = maxf(part_hp["torso"], max_hp("torso") * 0.3)
	part_hp["torso"] = maxf(part_hp["torso"], 1.0)

	var outcome := "EXTRACTED" if won else ("ABORTED" if r.get("aborted", false) else ("PILOT DOWN" if r.get("pilot_down", false) else "MECH DOWN"))
	lines.append("%s — %s" % [op.get("title", "Operation"), outcome])
	var gtxt: Array[String] = []
	for k in ["scrap", "circuits", "biomass", "fuel"]:
		if gained.get(k, 0) > 0:
			gtxt.append("+%d %s" % [gained[k], RES_NAMES[k].to_lower()])
	for a in AMMO:
		if loot.get(a, 0) > 0:
			gtxt.append("+%d %s" % [loot[a], AMMO_NAMES[a].to_lower()])
	if rescued > 0:
		gtxt.append("+%d survivors" % rescued)
	if not gtxt.is_empty():
		lines.append("Brought home: " + ", ".join(gtxt) + ".")
	if lost:
		lines.append("Rafa hauled Brigid home under fire. Half the salvage was lost.")

	var talk: Array = []
	if won and op.get("story", false):
		talk = op.get("debrief", []).duplicate()
		story_index += 1
		if story_index >= Story.STORY_MISSIONS.size():
			talk.append_array(Story.ENDING)
	elif won:
		talk = [["quill", "Good work at %s. Rest up." % op.get("zone", "the zone")]]
	else:
		talk = [["anselm", "You came home. That's what matters tonight."]]

	var production := run_night()
	talk.append(Story.NIGHT[(day + story_index) % Story.NIGHT.size()])
	day += 1
	generate_operations()
	last_report = {"day": day, "mission": lines, "production": production, "talk": talk}
	current_mission = {}
	loadout = {}
	save_game()


# =============================================================================
# Save / load
# =============================================================================

func save_game() -> void:
	if mode != "campaign":
		return
	var cf := ConfigFile.new()
	cf.set_value("rock", "saved_at", Time.get_datetime_string_from_system(false, true))
	for key in ["day", "res", "ammo", "survivors", "slots", "ammo_focus", "research", "part_hp", "story_index",
			"operations", "current_mission", "loadout", "last_report", "missions_won", "kills_total", "chatter_i"]:
		cf.set_value("rock", key, get(key))
	cf.save(slot_path(slot))


func load_game() -> void:
	var cf := ConfigFile.new()
	if cf.load(slot_path(slot)) != OK:
		return
	for key in ["day", "survivors", "ammo_focus", "story_index", "missions_won", "kills_total", "chatter_i"]:
		set(key, cf.get_value("rock", key, get(key)))
	for key in ["res", "ammo", "research", "part_hp"]:
		var saved: Dictionary = cf.get_value("rock", key, {})
		var cur: Dictionary = get(key)
		for k in cur.keys():
			if saved.has(k):
				cur[k] = saved[k]
	var saved_slots: Array = cf.get_value("rock", "slots", [])
	if saved_slots.size() == SLOT_NAMES.size():
		slots = saved_slots
	for sl in slots:
		if sl.has("type") and not sl.has("crew"):
			sl["crew"] = 0
	auto_assign()
	operations = cf.get_value("rock", "operations", operations)
	current_mission = cf.get_value("rock", "current_mission", {})
	loadout = cf.get_value("rock", "loadout", {})
	last_report = cf.get_value("rock", "last_report", {})
	if not current_mission.is_empty():
		# The app was closed mid-mission: count it as aborted.
		apply_mission_result({"aborted": true, "ammo_left": loadout})
	if operations.is_empty():
		generate_operations()
