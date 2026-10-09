extends Node
## Campaign state shared between the hangar and battles (autoload "GameState").

const VERSION := "1.0a"
const SAVE_PATH := "user://mechfps_save.cfg"

const PARTS := ["torso", "left_arm", "right_arm", "legs"]
const PART_NAMES := {
	"torso": "Torso",
	"left_arm": "Left Arm",
	"right_arm": "Right Arm",
	"legs": "Legs",
}
const BASE_MAX_HP := {"torso": 120.0, "left_arm": 60.0, "right_arm": 60.0, "legs": 80.0}
const REPAIR_COST_PER_HP := 2.0

## Upgrade costs scale with the level being bought (level 1 = base cost, level 2 = 2x...).
const UPGRADES := {
	"cannon": {"name": "Autocannon Calibre", "desc": "+25% cannon damage", "max": 5, "credits": 150, "salvage": 2},
	"armor": {"name": "Armor Plating", "desc": "+20% max HP on every part", "max": 5, "credits": 200, "salvage": 3},
	"servos": {"name": "Leg Servos", "desc": "+10% walking speed", "max": 4, "credits": 120, "salvage": 2},
	"rockets": {"name": "Rocket Pod", "desc": "+30% rocket damage, faster reload", "max": 4, "credits": 180, "salvage": 4},
}

var credits := 300
var salvage := 0
var mission := 1
var kills_total := 0
var levels := {"cannon": 0, "armor": 0, "servos": 0, "rockets": 0}
var part_hp := {}
## Summary of the last battle, shown in the hangar.
var last_result := {}


func _ready() -> void:
	_reset_values()
	load_game()


func _reset_values() -> void:
	credits = 300
	salvage = 0
	mission = 1
	kills_total = 0
	levels = {"cannon": 0, "armor": 0, "servos": 0, "rockets": 0}
	last_result = {}
	part_hp = {}
	for p in PARTS:
		part_hp[p] = max_hp(p)


# --- Derived stats -------------------------------------------------------

func max_hp(part: String) -> float:
	return BASE_MAX_HP[part] * (1.0 + 0.2 * levels["armor"])


func hp_ratio(part: String) -> float:
	return clampf(part_hp.get(part, 0.0) / max_hp(part), 0.0, 1.0)


func cannon_damage() -> float:
	return 9.0 * (1.0 + 0.25 * levels["cannon"])


func rocket_damage() -> float:
	return 70.0 * (1.0 + 0.3 * levels["rockets"])


func rocket_cooldown() -> float:
	return maxf(2.0, 5.0 - 0.6 * levels["rockets"])


func walk_speed() -> float:
	return 2.6 * (1.0 + 0.1 * levels["servos"])


# --- Mission difficulty ---------------------------------------------------

func mission_hive_count() -> int:
	return mini(1 + mission / 2, 5)


func mission_seed() -> int:
	return 7919 * mission + 17


# --- Upgrades -------------------------------------------------------------

func upgrade_cost(id: String) -> Dictionary:
	var u: Dictionary = UPGRADES[id]
	var next_level: int = levels[id] + 1
	return {"credits": u["credits"] * next_level, "salvage": u["salvage"] * next_level}


func is_maxed(id: String) -> bool:
	return levels[id] >= UPGRADES[id]["max"]


func can_buy(id: String) -> bool:
	if is_maxed(id):
		return false
	var c := upgrade_cost(id)
	return credits >= c["credits"] and salvage >= c["salvage"]


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	var c := upgrade_cost(id)
	credits -= c["credits"]
	salvage -= c["salvage"]
	if id == "armor":
		# Keep each part at the same health ratio when max HP grows.
		var ratios := {}
		for p in PARTS:
			ratios[p] = hp_ratio(p)
		levels[id] += 1
		for p in PARTS:
			part_hp[p] = ratios[p] * max_hp(p)
	else:
		levels[id] += 1
	save_game()
	return true


# --- Repairs --------------------------------------------------------------

func repair_cost(part: String) -> int:
	return int(ceil((max_hp(part) - part_hp[part]) * REPAIR_COST_PER_HP))


func repair(part: String) -> void:
	## Repairs as much as the player can afford.
	var missing: float = max_hp(part) - part_hp[part]
	if missing <= 0.0:
		return
	var affordable_hp := float(credits) / REPAIR_COST_PER_HP
	var amount := minf(missing, affordable_hp)
	credits -= int(ceil(amount * REPAIR_COST_PER_HP))
	credits = maxi(credits, 0)
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


# --- Battle results -------------------------------------------------------

func apply_battle_result(result: Dictionary) -> void:
	## result: won, retreated, kills, brutes, hives_destroyed, hives_total, parts
	var won: bool = result.get("won", false)
	var kills: int = result.get("kills", 0)
	var hives: int = result.get("hives_destroyed", 0)
	var earned_credits := kills * 12 + hives * 60
	var earned_salvage := hives * 2 + int(result.get("brutes", 0))
	if won:
		earned_credits += 150 + mission * 25
		earned_salvage += 2
	credits += earned_credits
	salvage += earned_salvage
	kills_total += kills

	var parts: Dictionary = result.get("parts", {})
	for p in PARTS:
		part_hp[p] = clampf(parts.get(p, part_hp[p]), 0.0, max_hp(p))
	if not won and not result.get("retreated", false):
		# The recovery crew drags the wreck home and patches the core.
		part_hp["torso"] = maxf(part_hp["torso"], max_hp("torso") * 0.3)
	part_hp["torso"] = maxf(part_hp["torso"], 1.0)

	last_result = {
		"mission": mission,
		"won": won,
		"retreated": result.get("retreated", false),
		"credits": earned_credits,
		"salvage": earned_salvage,
		"kills": kills,
		"hives": hives,
		"hives_total": result.get("hives_total", 0),
	}
	if won:
		mission += 1
	save_game()


func new_campaign() -> void:
	_reset_values()
	save_game()


# --- Save / load ----------------------------------------------------------

func save_game() -> void:
	var cf := ConfigFile.new()
	cf.set_value("campaign", "credits", credits)
	cf.set_value("campaign", "salvage", salvage)
	cf.set_value("campaign", "mission", mission)
	cf.set_value("campaign", "kills_total", kills_total)
	cf.set_value("campaign", "levels", levels)
	cf.set_value("campaign", "part_hp", part_hp)
	cf.set_value("campaign", "last_result", last_result)
	cf.save(SAVE_PATH)


func load_game() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	credits = cf.get_value("campaign", "credits", credits)
	salvage = cf.get_value("campaign", "salvage", salvage)
	mission = cf.get_value("campaign", "mission", mission)
	kills_total = cf.get_value("campaign", "kills_total", kills_total)
	var saved_levels: Dictionary = cf.get_value("campaign", "levels", {})
	for k in levels.keys():
		levels[k] = int(saved_levels.get(k, levels[k]))
	var saved_hp: Dictionary = cf.get_value("campaign", "part_hp", {})
	for p in PARTS:
		part_hp[p] = clampf(float(saved_hp.get(p, max_hp(p))), 0.0, max_hp(p))
	last_result = cf.get_value("campaign", "last_result", {})
