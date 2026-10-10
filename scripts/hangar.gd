extends Control
## Hangar: repair the mech, buy upgrades, launch the next mission.
## The whole UI is built in code so the scene file stays tiny.

const MechDiagramScript = preload("res://scripts/mech_diagram.gd")

const ACCENT := Color(0.4, 1.0, 0.6)
const WARN := Color(1.0, 0.75, 0.25)
const BAD := Color(1.0, 0.35, 0.3)

var _confirm_reset := false
var _root_box: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = _make_theme()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build()


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.09, 0.11, 0.12)
	panel.border_color = Color(0.2, 0.45, 0.3)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(14)
	t.set_stylebox("panel", "PanelContainer", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.14, 0.3, 0.2)
	btn.set_corner_radius_all(6)
	btn.set_content_margin_all(10)
	var btn_hover := btn.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.18, 0.4, 0.26)
	var btn_pressed := btn.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = Color(0.25, 0.55, 0.35)
	var btn_disabled := btn.duplicate() as StyleBoxFlat
	btn_disabled.bg_color = Color(0.13, 0.14, 0.15)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", btn_hover)
	t.set_stylebox("pressed", "Button", btn_pressed)
	t.set_stylebox("disabled", "Button", btn_disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.47, 0.48))
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.04, 0.05, 0.05)
	bar_bg.set_corner_radius_all(3)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	return t


func _build() -> void:
	if _root_box:
		_root_box.queue_free()
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	margin.add_theme_constant_override("margin_top", 48)  # room for the music player
	add_child(margin)
	_root_box = margin

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)

	# Header
	var header := HBoxContainer.new()
	v.add_child(header)
	var title := _label("HIVE BREAKERS  ·  MECH HANGAR", 30, ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_label("Credits: %d     Salvage: %d" % [GameState.credits, GameState.salvage], 24, WARN))
	header.add_child(_label("   v" + GameState.VERSION, 16, Color(0.5, 0.55, 0.55)))

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	v.add_child(cols)
	cols.add_child(_build_status())
	cols.add_child(_build_upgrades())
	cols.add_child(_build_mission())


func _panel(title: String, ratio: float) -> Array:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = ratio
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	p.add_child(box)
	box.add_child(_label(title, 22, ACCENT))
	return [p, box]


func _build_status() -> Control:
	var pb := _panel("MECH STATUS", 1.0)
	var box: VBoxContainer = pb[1]
	var diagram := Control.new()
	diagram.set_script(MechDiagramScript)
	diagram.custom_minimum_size = Vector2(0, 150)
	box.add_child(diagram)
	for part in GameState.PARTS:
		var hp: float = GameState.part_hp[part]
		var mx := GameState.max_hp(part)
		var ratio := GameState.hp_ratio(part)
		var row := HBoxContainer.new()
		box.add_child(row)
		var name_l := _label("%s  %d/%d" % [GameState.PART_NAMES[part], int(ceil(hp)), int(mx)], 18, MechDiagramScript.part_color(ratio) if ratio > 0.0 else BAD)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		var cost := GameState.repair_cost(part)
		var b := _button("Repair %d cr" % cost if cost > 0 else "OK", cost > 0 and GameState.credits > 0)
		b.custom_minimum_size = Vector2(150, 44)
		b.pressed.connect(func():
			GameState.repair(part)
			Sfx.play("click")
			_build())
		row.add_child(b)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		bar.value = ratio * 100.0
		var fill := StyleBoxFlat.new()
		fill.bg_color = MechDiagramScript.part_color(ratio)
		fill.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		box.add_child(bar)
	var total := GameState.total_repair_cost()
	var all := _button("Repair all (%d cr)" % total if total > 0 else "Fully repaired", total > 0 and GameState.credits > 0)
	all.pressed.connect(func():
		GameState.repair_all()
		Sfx.play("click")
		_build())
	box.add_child(all)
	return pb[0]


func _build_upgrades() -> Control:
	var pb := _panel("UPGRADES", 1.2)
	var box: VBoxContainer = pb[1]
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	for id in GameState.UPGRADES:
		var u: Dictionary = GameState.UPGRADES[id]
		var lvl: int = GameState.levels[id]
		list.add_child(_label("%s   Lv %d/%d" % [u["name"], lvl, u["max"]], 19, Color.WHITE))
		list.add_child(_label(u["desc"], 16, Color(0.65, 0.7, 0.7), true))
		var text := "MAXED"
		if not GameState.is_maxed(id):
			var c := GameState.upgrade_cost(id)
			text = "Upgrade — %d cr, %d salvage" % [c["credits"], c["salvage"]]
		var b := _button(text, GameState.can_buy(id))
		b.custom_minimum_size = Vector2(0, 46)
		b.pressed.connect(func():
			if GameState.buy(id):
				Sfx.play("hit", -10.0)
			_build())
		list.add_child(b)
	return pb[0]


func _build_mission() -> Control:
	var pb := _panel("NEXT MISSION", 1.0)
	var box: VBoxContainer = pb[1]
	var m := GameState.mission
	box.add_child(_label("Operation %d" % m, 26, Color.WHITE))
	var hives := GameState.mission_hive_count()
	box.add_child(_label("Target: %d alien hive%s" % [hives, "" if hives == 1 else "s"], 18, Color(0.85, 0.85, 0.85)))
	var threats := "Crawlers, spitters"
	if m >= 2:
		threats += ", brutes"
	box.add_child(_label("Threats: " + threats, 18, Color(0.85, 0.85, 0.85)))
	box.add_child(_label("Destroy every hive to sever the hive mind.", 16, Color(0.6, 0.65, 0.65), true))

	var r := GameState.last_result
	if not r.is_empty():
		var outcome := "VICTORY" if r.get("won", false) else ("RETREAT" if r.get("retreated", false) else "MECH DOWN")
		var col := ACCENT if r.get("won", false) else (WARN if r.get("retreated", false) else BAD)
		box.add_child(HSeparator.new())
		box.add_child(_label("Last: Operation %d — %s" % [r.get("mission", 0), outcome], 18, col))
		box.add_child(_label("Kills %d · Hives %d/%d · +%d cr · +%d salvage" % [r.get("kills", 0), r.get("hives", 0), r.get("hives_total", 0), r.get("credits", 0), r.get("salvage", 0)], 15, Color(0.75, 0.75, 0.75), true))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var torso := GameState.hp_ratio("torso")
	if torso < 0.35:
		box.add_child(_label("Warning: torso badly damaged!", 17, BAD))
	var launch := _button("LAUNCH MISSION", true)
	launch.custom_minimum_size = Vector2(0, 76)
	launch.add_theme_font_size_override("font_size", 28)
	launch.pressed.connect(func():
		Sfx.play("step")
		get_tree().change_scene_to_file("res://scenes/battle.tscn"))
	box.add_child(launch)

	var reset := _button("Tap again to wipe save" if _confirm_reset else "New campaign", true)
	reset.custom_minimum_size = Vector2(0, 40)
	reset.add_theme_font_size_override("font_size", 15)
	reset.pressed.connect(func():
		if _confirm_reset:
			GameState.new_campaign()
			_confirm_reset = false
		else:
			_confirm_reset = true
		_build())
	box.add_child(reset)
	return pb[0]


func _label(text: String, font_size: int, color: Color, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, enabled: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(0, 48)
	return b
