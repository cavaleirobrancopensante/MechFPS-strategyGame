extends Control
## St. Columba's Rock: the base between missions.
## Tabs: Operations (map room), Base (modules and crew), Mech (repairs and
## ammo), Research (Sandoval's lab). Built in code; rebuilt after changes.

const Story = preload("res://scripts/story.gd")
const RockScene = preload("res://scripts/base/rock_scene.gd")
const MechDiagram = preload("res://scripts/mech_diagram.gd")

const ACCENT := Color(0.4, 1.0, 0.6)
const WARN := Color(1.0, 0.75, 0.25)
const BAD := Color(1.0, 0.35, 0.3)
const DIM := Color(0.65, 0.7, 0.7)

var tab := "ops"
var selected_op := 0
var building_menu := -1   ## slot index whose "build" list is open
var demolish_armed := -1
var confirm_reset := false
var chatter_line: Array = []
var chatter_timer := 0.0
var _root: Control
var _chat_name: Label
var _chat_text: Label
var _chat_face: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = _make_theme()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_next_chatter()
	_build()
	if not GameState.last_report.is_empty():
		_show_report()


func _process(delta: float) -> void:
	chatter_timer += delta
	if chatter_timer > 10.0:
		_next_chatter()


# =============================================================================
# Layout
# =============================================================================

func _build() -> void:
	if _root:
		_root.queue_free()
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	margin.add_theme_constant_override("margin_top", 44)
	add_child(margin)
	_root = margin

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)
	v.add_child(_resource_bar())

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 10)
	v.add_child(cols)

	# Left: the Rock and its people
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(400, 0)
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)
	var scene := Control.new()
	scene.set_script(RockScene)
	scene.custom_minimum_size = Vector2(400, 300)
	left.add_child(scene)
	left.add_child(_chatter_box())

	# Right: tabs
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	cols.add_child(right)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	right.add_child(tabs)
	for t in [["ops", "MAP ROOM"], ["base", "BASE & PEOPLE"], ["mech", "BRIGID"], ["lab", "LAB"]]:
		var key: String = t[0]
		var b := _button(t[1], true)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 44)
		if key == tab:
			b.add_theme_stylebox_override("normal", _flat(Color(0.2, 0.45, 0.28)))
		b.pressed.connect(func():
			tab = key
			building_menu = -1
			Sfx.play("click")
			_build())
		tabs.add_child(b)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	match tab:
		"ops": _tab_ops(content)
		"base": _tab_base(content)
		"mech": _tab_mech(content)
		"lab": _tab_lab(content)


func _resource_bar() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var title := _label("ST. COLUMBA'S ROCK · DAY %d" % GameState.day, 22, ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	row.add_child(_label("People %d (%d idle) · Beds %d" % [GameState.survivors, maxi(0, GameState.idle_people()), GameState.beds()], 17, Color(1.0, 0.85, 0.6)))
	for k in GameState.RESOURCES:
		row.add_child(_label("%s %d" % [GameState.RES_NAMES[k], GameState.res[k]], 17, GameState.RES_COLORS[k]))
	row.add_child(_label("Shells %d · Rkt %d · Rnd %d" % [GameState.ammo["shells"], GameState.ammo["rockets"], GameState.ammo["rounds"]], 17, Color(1.0, 0.6, 0.4)))
	return row


# =============================================================================
# Chatter
# =============================================================================

func _chatter_box() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(400, 110)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	_chat_face = Control.new()
	_chat_face.custom_minimum_size = Vector2(64, 64)
	_chat_face.draw.connect(_draw_face.bind(_chat_face))
	h.add_child(_chat_face)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	_chat_name = _label("", 16, ACCENT)
	v.add_child(_chat_name)
	_chat_text = _label("", 16, Color.WHITE, true)
	v.add_child(_chat_text)
	var more := _button("…", true)
	more.custom_minimum_size = Vector2(44, 44)
	more.pressed.connect(_next_chatter)
	h.add_child(more)
	_refresh_chatter()
	return p


func _next_chatter() -> void:
	chatter_timer = 0.0
	GameState.chatter_i += 1
	chatter_line = Story.CHATTER[GameState.chatter_i % Story.CHATTER.size()]
	_refresh_chatter()


func _refresh_chatter() -> void:
	if _chat_name == null or chatter_line.is_empty():
		return
	var who: Dictionary = Story.CAST[chatter_line[0]]
	_chat_name.text = "%s — %s" % [who["name"], who["role"]]
	_chat_name.add_theme_color_override("font_color", who["color"])
	_chat_text.text = chatter_line[1]
	_chat_face.set_meta("who", chatter_line[0])
	_chat_face.queue_redraw()


func _draw_face(c: Control) -> void:
	_draw_portrait(c, c.get_meta("who", "quill"), c.size * 0.5, minf(c.size.x, c.size.y) * 0.48)


static func _draw_portrait(c: CanvasItem, who: String, center: Vector2, r: float) -> void:
	## Simple painted portraits, one style per character.
	var col: Color = Story.CAST[who]["color"]
	c.draw_circle(center, r, col.darkened(0.6))
	c.draw_arc(center, r, 0, TAU, 32, col, 2.0)
	var skin: Color = {"quill": Color(0.85, 0.7, 0.6), "anselm": Color(0.9, 0.75, 0.65), "mags": Color(0.45, 0.3, 0.22),
		"sandoval": Color(0.8, 0.62, 0.5), "rafa": Color(0.7, 0.52, 0.4), "pip": Color(0.95, 0.8, 0.7), "wren": Color(0.8, 0.65, 0.55)}[who]
	var head := center + Vector2(0, -r * 0.1)
	# Shoulders
	c.draw_circle(center + Vector2(0, r * 0.95), r * 0.75, col.darkened(0.2))
	c.draw_circle(head, r * 0.42, skin)
	match who:
		"quill":
			c.draw_rect(Rect2(head + Vector2(-r * 0.45, -r * 0.6), Vector2(r * 0.9, r * 0.25)), Color(0.15, 0.2, 0.35))
			c.draw_rect(Rect2(head + Vector2(-r * 0.25, -r * 0.7), Vector2(r * 0.5, r * 0.12)), Color(0.9, 0.8, 0.3))
		"anselm":
			c.draw_arc(head, r * 0.5, PI * 0.9, PI * 2.1, 16, Color(0.4, 0.28, 0.18), r * 0.18)
			c.draw_circle(head + Vector2(0, r * 0.35), r * 0.22, Color(0.85, 0.85, 0.85))
		"mags":
			c.draw_circle(head + Vector2(0, -r * 0.3), r * 0.38, Color(0.1, 0.08, 0.08))
			c.draw_rect(Rect2(head + Vector2(-r * 0.4, -r * 0.2), Vector2(r * 0.8, r * 0.12)), Color(0.95, 0.6, 0.2))
		"sandoval":
			c.draw_circle(head + Vector2(-r * 0.15, -r * 0.02), r * 0.12, Color(0.9, 0.95, 1.0))
			c.draw_circle(head + Vector2(r * 0.15, -r * 0.02), r * 0.12, Color(0.9, 0.95, 1.0))
			c.draw_arc(head + Vector2(0, -r * 0.2), r * 0.42, PI, TAU, 12, Color(0.75, 0.75, 0.75), r * 0.12)
		"rafa":
			c.draw_rect(Rect2(head + Vector2(-r * 0.32, -r * 0.1), Vector2(r * 0.64, r * 0.14)), Color(0.15, 0.15, 0.15))
			c.draw_arc(head, r * 0.46, PI, TAU, 12, Color(0.3, 0.45, 0.3), r * 0.15)
		"pip":
			c.draw_arc(head, r * 0.5, PI * 0.95, PI * 2.05, 16, Color(0.85, 0.4, 0.2), r * 0.16)
			c.draw_arc(head, r * 0.55, PI * 1.1, PI * 1.9, 12, Color(0.2, 0.2, 0.2), r * 0.06)
		_:
			c.draw_arc(head, r * 0.48, PI, TAU, 12, Color(0.25, 0.2, 0.18), r * 0.15)
	# Eyes
	if who != "sandoval" and who != "rafa":
		c.draw_circle(head + Vector2(-r * 0.14, 0), r * 0.05, Color(0.1, 0.1, 0.1))
		c.draw_circle(head + Vector2(r * 0.14, 0), r * 0.05, Color(0.1, 0.1, 0.1))


# =============================================================================
# Map room: operations
# =============================================================================

func _tab_ops(box: VBoxContainer) -> void:
	selected_op = clampi(selected_op, 0, GameState.operations.size() - 1)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	box.add_child(h)
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(330, 0)
	list.add_theme_constant_override("separation", 6)
	h.add_child(list)
	for i in GameState.operations.size():
		var op: Dictionary = GameState.operations[i]
		var idx := i
		var tag := "★ STORY · " if op.get("story", false) else ""
		var b := _button("%s%s\n%s · %s · fuel %d" % [tag, op["title"], op["zone"], GameState.objective_text(op), op["fuel"]], true)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 66)
		b.add_theme_font_size_override("font_size", 15)
		if i == selected_op:
			b.add_theme_stylebox_override("normal", _flat(Color(0.2, 0.42, 0.28)))
		elif op.get("story", false):
			b.add_theme_stylebox_override("normal", _flat(Color(0.3, 0.25, 0.1)))
		b.pressed.connect(func():
			selected_op = idx
			Sfx.play("click")
			_build())
		list.add_child(b)

	var op: Dictionary = GameState.operations[selected_op]
	var d := VBoxContainer.new()
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d.add_theme_constant_override("separation", 6)
	h.add_child(d)
	if op.get("story", false):
		d.add_child(_label(op.get("act_title", ""), 15, WARN))
	d.add_child(_label(op["title"], 24, Color.WHITE))
	d.add_child(_label("%s  ·  Threat %s" % [op["zone"], "▲".repeat(clampi(op["diff"], 1, 9))], 16, DIM))
	d.add_child(_label("Objective: %s, then reach the landing zone for pickup." % GameState.objective_text(op), 16, ACCENT, true))
	d.add_child(_label("Reward: %s" % GameState.cost_text(op.get("reward", {})) + ("  + the people you rescue" if op["type"] == "rescue" else ""), 16, WARN, true))
	d.add_child(HSeparator.new())
	for line: Array in op.get("briefing", []):
		d.add_child(_dialogue_row(line[0], line[1]))
	d.add_child(HSeparator.new())
	var caps := GameState.ammo_caps()
	var load_txt := "Loadout: %d / %d shells · %d / %d rockets · %d / %d rounds" % [
		mini(caps["shells"], GameState.ammo["shells"]), caps["shells"],
		mini(caps["rockets"], GameState.ammo["rockets"]), caps["rockets"],
		mini(caps["rounds"], GameState.ammo["rounds"]), caps["rounds"]]
	d.add_child(_label(load_txt, 15, Color(1.0, 0.6, 0.4), true))
	if GameState.hp_ratio("torso") < 0.35:
		d.add_child(_label("Warning: Brigid's torso is badly damaged.", 15, BAD))
	var can: bool = GameState.res["fuel"] >= op["fuel"]
	var launch := _button("LAUNCH — fuel %d" % op["fuel"] if can else "NOT ENOUGH FUEL", can)
	launch.custom_minimum_size = Vector2(0, 64)
	launch.add_theme_font_size_override("font_size", 24)
	launch.pressed.connect(func():
		if GameState.launch(selected_op):
			Sfx.play("step")
			get_tree().change_scene_to_file("res://scenes/battle.tscn"))
	d.add_child(launch)


func _dialogue_row(who: String, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var face := Control.new()
	face.custom_minimum_size = Vector2(38, 38)
	face.set_meta("who", who)
	face.draw.connect(_draw_face.bind(face))
	row.add_child(face)
	var cast: Dictionary = Story.CAST[who]
	var l := _label("%s: %s" % [cast["name"], text], 15, Color(0.92, 0.92, 0.9), true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row


# =============================================================================
# Base modules and people
# =============================================================================

func _tab_base(box: VBoxContainer) -> void:
	var gs := GameState
	box.add_child(_label("People are the Rock's most precious resource. Everyone you rescue moves in, needs a bed, and can work a job.", 15, DIM, true))
	var people := _label("People: %d   ·   Beds: %d   ·   Working: %d   ·   Idle: %d" % [gs.survivors, gs.beds(), gs.crew_assigned(), maxi(0, gs.idle_people())], 17, Color(1.0, 0.85, 0.6))
	box.add_child(people)
	if gs.survivors > gs.beds():
		box.add_child(_label("%d people are sleeping in the chapel and can't work. Build or upgrade a Bunkhouse." % (gs.survivors - gs.beds()), 15, BAD, true))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for i in gs.slots.size():
		grid.add_child(_slot_card(i))


func _slot_card(i: int) -> Control:
	var gs := GameState
	var sl: Dictionary = gs.slots[i]
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(380, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	v.add_child(_label(gs.SLOT_NAMES[i].to_upper(), 13, DIM))
	if not sl.has("type"):
		if building_menu == i:
			v.add_child(_label("Build what?", 16, Color.WHITE))
			for type in gs.BUILDINGS:
				var t: String = type
				var cost: Dictionary = gs.build_cost(t)
				var b := _button("%s — %s" % [gs.BUILDINGS[t]["name"], gs.cost_text(cost)], gs.can_afford(cost))
				b.tooltip_text = gs.BUILDINGS[t]["desc"]
				b.add_theme_font_size_override("font_size", 14)
				b.custom_minimum_size = Vector2(0, 38)
				b.pressed.connect(func():
					if gs.build(i, t):
						Sfx.play("hit", -10.0)
					building_menu = -1
					_build())
				v.add_child(b)
			var cancel := _button("Cancel", true)
			cancel.custom_minimum_size = Vector2(0, 34)
			cancel.pressed.connect(func():
				building_menu = -1
				_build())
			v.add_child(cancel)
		else:
			v.add_child(_label("Empty", 18, DIM))
			var b2 := _button("Build here…", true)
			b2.pressed.connect(func():
				building_menu = i
				_build())
			v.add_child(b2)
		return p

	var info: Dictionary = gs.BUILDINGS[sl["type"]]
	v.add_child(_label("%s  Lv %d" % [info["name"], sl["level"]], 18, Color.WHITE))
	v.add_child(_label(info["desc"], 14, DIM, true))
	v.add_child(_label(gs.production_preview(i), 15, ACCENT, true))

	var req := gs.crew_required(i)
	if req > 0:
		var crew_row := HBoxContainer.new()
		crew_row.add_theme_constant_override("separation", 6)
		var crew: int = sl.get("crew", 0)
		var minus := _button("−", crew > 0)
		minus.custom_minimum_size = Vector2(44, 40)
		minus.pressed.connect(func():
			gs.assign_crew(i, -1)
			_build())
		crew_row.add_child(minus)
		var dots := ""
		for k in req:
			dots += "● " if k < crew else "○ "
		var cl := _label("Crew %s %d/%d" % [dots, crew, req], 16, Color(1.0, 0.85, 0.6) if crew >= req else WARN)
		cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		crew_row.add_child(cl)
		var plus := _button("+", crew < req and gs.idle_people() > 0)
		plus.custom_minimum_size = Vector2(44, 40)
		plus.pressed.connect(func():
			gs.assign_crew(i, 1)
			_build())
		crew_row.add_child(plus)
		v.add_child(crew_row)

	if sl["type"] == "ammo":
		var fr := HBoxContainer.new()
		fr.add_theme_constant_override("separation", 4)
		for f in [["shells", "Shells"], ["rockets", "Rockets"], ["rounds", "Rounds"]]:
			var key: String = f[0]
			var fb := _button(f[1], true)
			fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			fb.custom_minimum_size = Vector2(0, 36)
			fb.add_theme_font_size_override("font_size", 14)
			if gs.ammo_focus == key:
				fb.add_theme_stylebox_override("normal", _flat(Color(0.5, 0.3, 0.12)))
			fb.pressed.connect(func():
				gs.ammo_focus = key
				gs.save_game()
				_build())
			fr.add_child(fb)
		v.add_child(fr)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	if sl["level"] < gs.MAX_LEVEL:
		var uc := gs.upgrade_cost(i)
		var ub := _button("Upgrade — %s" % gs.cost_text(uc), gs.can_afford(uc))
		ub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ub.add_theme_font_size_override("font_size", 14)
		ub.pressed.connect(func():
			if gs.upgrade(i):
				Sfx.play("hit", -10.0)
			_build())
		actions.add_child(ub)
	else:
		var mx := _label("Fully upgraded", 14, DIM)
		mx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(mx)
	var db := _button("Sure?" if demolish_armed == i else "Demolish", true)
	db.add_theme_font_size_override("font_size", 13)
	db.custom_minimum_size = Vector2(90, 40)
	db.pressed.connect(func():
		if demolish_armed == i:
			gs.demolish(i)
			demolish_armed = -1
		else:
			demolish_armed = i
		_build())
	actions.add_child(db)
	v.add_child(actions)
	return p


# =============================================================================
# Brigid: repairs and ammunition
# =============================================================================

func _tab_mech(box: VBoxContainer) -> void:
	var gs := GameState
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	box.add_child(h)
	var diagram := Control.new()
	diagram.set_script(MechDiagram)
	diagram.custom_minimum_size = Vector2(170, 200)
	h.add_child(diagram)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(_label("Mags patches Brigid with scrap: 1 scrap per 4 points of armour.", 15, DIM, true))
	for part in gs.PARTS:
		var p: String = part
		var row := HBoxContainer.new()
		var ratio := gs.hp_ratio(p)
		var name_l := _label("%s  %d/%d" % [gs.PART_NAMES[p], int(ceil(gs.part_hp[p])), int(gs.max_hp(p))], 17, MechDiagram.part_color(ratio) if ratio > 0.0 else BAD)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		var cost := gs.repair_cost(p)
		var b := _button("Repair %d scrap" % cost if cost > 0 else "OK", cost > 0 and gs.res["scrap"] > 0)
		b.custom_minimum_size = Vector2(170, 40)
		b.pressed.connect(func():
			gs.repair(p)
			Sfx.play("click")
			_build())
		row.add_child(b)
		v.add_child(row)
	var total := gs.total_repair_cost()
	var all := _button("Repair all (%d scrap)" % total if total > 0 else "Fully repaired", total > 0 and gs.res["scrap"] > 0)
	all.pressed.connect(func():
		gs.repair_all()
		Sfx.play("click")
		_build())
	v.add_child(all)

	box.add_child(HSeparator.new())
	box.add_child(_label("AMMUNITION", 18, ACCENT))
	var caps := gs.ammo_caps()
	for a in gs.AMMO:
		box.add_child(_label("%s: %d in stock · Brigid carries up to %d per drop" % [gs.AMMO_NAMES[a], gs.ammo[a], caps[a]], 16, Color(1.0, 0.7, 0.5)))
	box.add_child(_label("Unused ammo comes home with you. Make more in the Ammo Factory (Base tab); research Ammo Racks to carry more.", 14, DIM, true))

	box.add_child(HSeparator.new())
	var reset := _button("Tap again to wipe the save and start over" if confirm_reset else "New campaign", true)
	reset.add_theme_font_size_override("font_size", 14)
	reset.pressed.connect(func():
		if confirm_reset:
			gs.new_campaign()
			confirm_reset = false
		else:
			confirm_reset = true
		_build())
	box.add_child(reset)


# =============================================================================
# Lab: research
# =============================================================================

func _tab_lab(box: VBoxContainer) -> void:
	var gs := GameState
	box.add_child(_dialogue_row("sandoval", "Biomass, circuits and a little scrap. Bring me those and I'll make Brigid sing. Well. Not like the Choir."))
	for id in gs.RESEARCH:
		var r: String = id
		var info: Dictionary = gs.RESEARCH[r]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(_label("%s   Lv %d/%d" % [info["name"], gs.research[r], info["max"]], 17, Color.WHITE))
		v.add_child(_label(info["desc"], 14, DIM))
		row.add_child(v)
		var txt := "Done"
		var ok := false
		if not gs.research_maxed(r):
			var c := gs.research_cost(r)
			txt = gs.cost_text(c)
			ok = gs.can_afford(c)
		var b := _button(txt, ok)
		b.custom_minimum_size = Vector2(250, 44)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func():
			if gs.do_research(r):
				Sfx.play("pickup")
			_build())
		row.add_child(b)
		box.add_child(row)


# =============================================================================
# Night report
# =============================================================================

func _show_report() -> void:
	var r: Dictionary = GameState.last_report
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.7)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = Vector2(760, 0)
	p.position = Vector2(-380, -300)
	shade.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	v.add_child(_label("NIGHT AT THE ROCK — DAY %d DAWNS" % r.get("day", GameState.day), 22, WARN))
	for l in r.get("mission", []):
		v.add_child(_label(l, 16, Color.WHITE, true))
	v.add_child(HSeparator.new())
	for l in r.get("production", []):
		v.add_child(_label("• " + l, 15, ACCENT, true))
	v.add_child(HSeparator.new())
	for line: Array in r.get("talk", []):
		v.add_child(_dialogue_row(line[0], line[1]))
	var ok := _button("Good morning", true)
	ok.custom_minimum_size = Vector2(0, 54)
	ok.pressed.connect(func():
		GameState.last_report = {}
		GameState.save_game()
		shade.queue_free())
	v.add_child(ok)
	# Centre it once laid out.
	await get_tree().process_frame
	p.position = (size - p.size) * 0.5 + Vector2(0, 16)


# =============================================================================
# Widgets
# =============================================================================

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.09, 0.11, 0.12)
	panel.border_color = Color(0.2, 0.45, 0.3)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(10)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("normal", "Button", _flat(Color(0.14, 0.3, 0.2)))
	t.set_stylebox("hover", "Button", _flat(Color(0.18, 0.4, 0.26)))
	t.set_stylebox("pressed", "Button", _flat(Color(0.25, 0.55, 0.35)))
	t.set_stylebox("disabled", "Button", _flat(Color(0.13, 0.14, 0.15)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.47, 0.48))
	return t


func _flat(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(6)
	s.set_content_margin_all(8)
	return s


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
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 46)
	return b
