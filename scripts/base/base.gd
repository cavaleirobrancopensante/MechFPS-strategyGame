extends Control
## St. Columba's Rock: the base between missions. Layout from docs/UI_STUDY.md:
## a header with the menu button and resource chips, one tab's content in the
## middle, the crew's radio chatter in a strip, and big tabs at the thumbs:
## MISSIONS (where next?), BASE (what do my people do?), BRIGID (is my mech
## ready?) and LAB (what do I improve?). Built in code; rebuilt after changes.

const Story = preload("res://scripts/story.gd")
const RockScene = preload("res://scripts/base/rock_scene.gd")
const MechDiagram = preload("res://scripts/mech_diagram.gd")
const SettingsScript = preload("res://scripts/settings.gd")

const ACCENT := Color(0.4, 1.0, 0.6)
const WARN := Color(1.0, 0.75, 0.25)
const BAD := Color(1.0, 0.35, 0.3)
const DIM := Color(0.65, 0.7, 0.7)
const GOLD := Color(1.0, 0.82, 0.3)
const PANEL_BG := Color(0.09, 0.11, 0.12)

## One colour and one word per mission type, used everywhere.
const TYPE_STYLE := {
	"destroy": {"name": "DESTROY", "color": Color(1.0, 0.45, 0.3)},
	"boss": {"name": "BROOD MOTHER", "color": Color(0.9, 0.35, 1.0)},
	"rescue": {"name": "RESCUE", "color": Color(1.0, 0.85, 0.55)},
	"retrieve": {"name": "RETRIEVE", "color": Color(0.4, 0.9, 1.0)},
	"survive": {"name": "HOLD OUT", "color": Color(1.0, 0.6, 0.2)},
	"scout": {"name": "SCOUT", "color": Color(0.45, 1.0, 0.7)},
}
const TABS := [["ops", "MISSIONS"], ["base", "BASE"], ["mech", "BRIGID"], ["lab", "LAB"]]

static var tab := "ops"
static var selected_op := 0
static var selected_site := -1

var demolish_armed := -1
var chatter_line: Array = []
var chatter_timer := 0.0
var _root: Control
var _overlay: Control
var _chat_text: Label
var _chat_face: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = _make_theme()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if selected_site < 0:
		selected_site = 0
		for i in GameState.slots.size():
			if GameState.slots[i].has("type"):
				selected_site = i
				break
	_next_chatter()
	_build()
	if not GameState.last_report.is_empty():
		_show_report()


func _process(delta: float) -> void:
	chatter_timer += delta
	if chatter_timer > 12.0:
		_next_chatter()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _overlay:
			_close_overlay()
		else:
			_open_menu()


# =============================================================================
# Layout
# =============================================================================

func _build() -> void:
	if _root:
		_root.queue_free()
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 42)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)
	move_child(margin, 1)
	_root = margin

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	margin.add_child(v)
	v.add_child(_header())
	var content := Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(content)
	var inner: Control
	match tab:
		"ops": inner = _tab_ops()
		"base": inner = _tab_base()
		"mech": inner = _tab_mech()
		_: inner = _tab_lab()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_child(inner)
	v.add_child(_chatter_strip())
	v.add_child(_tab_bar())


func _header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var menu := _button("☰", true)
	menu.custom_minimum_size = Vector2(56, 52)
	menu.add_theme_font_size_override("font_size", 26)
	menu.pressed.connect(func():
		Sfx.play("click")
		_open_menu())
	row.add_child(menu)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tv)
	tv.add_child(_label("ST. COLUMBA'S ROCK", 20, ACCENT))
	tv.add_child(_label("Day %d · Slot %d" % [GameState.day, GameState.slot], 14, DIM))

	var gs := GameState
	var people_col := Color(1.0, 0.85, 0.6)
	var ppl_note := "%d working · %d beds" % [gs.crew_assigned(), gs.beds()]
	row.add_child(_chip("People", str(gs.survivors), ppl_note, people_col, gs.survivors > gs.beds()))
	for k in gs.RESOURCES:
		row.add_child(_chip(gs.RES_NAMES[k], str(gs.res[k]), "", gs.RES_COLORS[k]))
	row.add_child(_chip("Ammo", "%d·%d·%d" % [gs.ammo["shells"], gs.ammo["rockets"], gs.ammo["rounds"]], "shells·rkts·rnds", Color(1.0, 0.6, 0.4)))
	return row


func _chip(title: String, value: String, note: String, col: Color, alert := false) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.1)
	sb.border_color = BAD if alert else Color(col.r, col.g, col.b, 0.55)
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(96, 52)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -4)
	p.add_child(v)
	v.add_child(_label(value, 21, Color.WHITE))
	v.add_child(_label(title if note == "" else "%s · %s" % [title, note], 11, col))
	return p


func _tab_bar() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for t in TABS:
		var key: String = t[0]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 60)
		var badge := _tab_badge(key)
		b.text = t[1] + ("   " + badge if badge != "" else "")
		b.add_theme_font_size_override("font_size", 21)
		if key == tab:
			b.add_theme_stylebox_override("normal", _flat(Color(0.2, 0.5, 0.3), ACCENT))
			b.add_theme_stylebox_override("hover", _flat(Color(0.2, 0.5, 0.3), ACCENT))
			b.add_theme_color_override("font_color", Color.WHITE)
		else:
			b.add_theme_stylebox_override("normal", _flat(Color(0.1, 0.14, 0.13)))
			b.add_theme_color_override("font_color", Color(0.75, 0.85, 0.8))
		b.pressed.connect(func():
			tab = key
			demolish_armed = -1
			Sfx.play("click")
			_build())
		row.add_child(b)
	return row


func _tab_badge(key: String) -> String:
	## A short hint on each tab, so you can see what needs you without looking.
	var gs := GameState
	match key:
		"ops":
			for op in gs.operations:
				if op.get("story", false):
					return "★"
		"base":
			if gs.idle_people() > 0:
				return "%d idle" % gs.idle_people()
			if gs.survivors > gs.beds():
				return "! beds"
		"mech":
			if gs.total_repair_cost() > 0:
				return "! repair"
		"lab":
			var n := 0
			for id in gs.RESEARCH:
				if not gs.research_maxed(id) and gs.can_afford(gs.research_cost(id)):
					n += 1
			if n > 0:
				return "%d ready" % n
	return ""


func _panel(min_w := 0.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if min_w > 0.0:
		p.custom_minimum_size = Vector2(min_w, 0)
	else:
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p


func _scroll_box(parent: Control, sep := 8) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", sep)
	scroll.add_child(box)
	return box


# =============================================================================
# Chatter: one radio strip above the tabs
# =============================================================================

func _chatter_strip() -> Control:
	var p := PanelContainer.new()
	var sb := _flat(Color(0.07, 0.09, 0.09), Color(0.2, 0.35, 0.28))
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	_chat_face = Control.new()
	_chat_face.custom_minimum_size = Vector2(38, 38)
	_chat_face.draw.connect(_draw_face.bind(_chat_face))
	h.add_child(_chat_face)
	_chat_text = _label("", 16, Color.WHITE)
	_chat_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_chat_text.clip_text = true
	_chat_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_chat_text)
	var more := _button("›", true)
	more.custom_minimum_size = Vector2(52, 38)
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
	if _chat_text == null or not is_instance_valid(_chat_text) or chatter_line.is_empty():
		return
	var who: Dictionary = Story.CAST[chatter_line[0]]
	_chat_text.text = "%s: %s" % [who["name"], chatter_line[1]]
	_chat_text.tooltip_text = chatter_line[1]
	_chat_text.add_theme_color_override("font_color", Color(who["color"]).lerp(Color.WHITE, 0.45))
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
	if who != "sandoval" and who != "rafa":
		c.draw_circle(head + Vector2(-r * 0.14, 0), r * 0.05, Color(0.1, 0.1, 0.1))
		c.draw_circle(head + Vector2(r * 0.14, 0), r * 0.05, Color(0.1, 0.1, 0.1))


# =============================================================================
# MISSIONS: cards on the left, briefing on the right, LAUNCH pinned
# =============================================================================

func _type_style(op: Dictionary) -> Dictionary:
	return TYPE_STYLE.get(op.get("type", "destroy"), TYPE_STYLE["destroy"])


func _tab_ops() -> Control:
	var gs := GameState
	selected_op = clampi(selected_op, 0, gs.operations.size() - 1)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)

	var left := _panel(400)
	h.add_child(left)
	var list := _scroll_box(left, 6)
	list.add_child(_label("OPERATIONS BOARD · pick one", 14, DIM))
	for i in gs.operations.size():
		list.add_child(_op_card(i))

	var right := _panel()
	h.add_child(right)
	var d := VBoxContainer.new()
	d.add_theme_constant_override("separation", 6)
	right.add_child(d)
	var op: Dictionary = gs.operations[selected_op]
	var ts := _type_style(op)
	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 8)
	tag_row.add_child(_badge(ts["name"], ts["color"]))
	if op.get("story", false):
		tag_row.add_child(_badge("★ STORY", GOLD))
		var act := _label(op.get("act_title", ""), 14, GOLD)
		act.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		act.clip_text = true
		tag_row.add_child(act)
	d.add_child(tag_row)
	d.add_child(_label(op["title"], 26, Color.WHITE))
	d.add_child(_label("%s   ·   Threat %s   ·   Fuel %d" % [op["zone"], "▲".repeat(clampi(op["diff"], 1, 9)), op["fuel"]], 15, DIM))
	d.add_child(_label("▶ " + GameState.objective_text(op) + ", then reach the green flare for pickup.", 17, ts["color"], true))
	var reward := gs.cost_text(op.get("reward", {}))
	d.add_child(_label("Reward: " + reward + ("  + the people you rescue" if op["type"] == "rescue" else ""), 15, WARN, true))
	d.add_child(HSeparator.new())
	var brief := _scroll_box(d, 6)
	for line: Array in op.get("briefing", []):
		brief.add_child(_dialogue_row(line[0], line[1]))
	if op.get("briefing", []).is_empty():
		brief.add_child(_label("No briefing. Get in, get it done, get out.", 15, DIM))

	# Pinned at the bottom: what you're taking and the big button.
	d.add_child(HSeparator.new())
	var caps := gs.ammo_caps()
	var load_row := HBoxContainer.new()
	load_row.add_theme_constant_override("separation", 14)
	for a in gs.AMMO:
		var have := mini(caps[a], gs.ammo[a])
		load_row.add_child(_label("%s %d/%d" % [["Shells", "Rockets", "Rounds"][gs.AMMO.find(a)], have, caps[a]], 15, Color(1.0, 0.6, 0.4) if have > 0 else BAD))
	var armour := gs.hp_ratio("torso")
	load_row.add_child(_label("Torso %d%%" % int(armour * 100.0), 15, MechDiagram.part_color(armour)))
	d.add_child(load_row)
	var can: bool = gs.res["fuel"] >= op["fuel"]
	var why := ""
	if not can:
		why = "NOT ENOUGH FUEL (need %d, have %d) — run the Bioreactor" % [op["fuel"], gs.res["fuel"]]
	var launch := _button("LAUNCH  ▶" if can else why, can)
	launch.custom_minimum_size = Vector2(0, 66)
	launch.add_theme_font_size_override("font_size", 26 if can else 16)
	if can:
		launch.add_theme_stylebox_override("normal", _flat(Color(0.18, 0.55, 0.3), ACCENT))
		launch.add_theme_stylebox_override("hover", _flat(Color(0.22, 0.62, 0.35), ACCENT))
	launch.pressed.connect(func():
		if gs.launch(selected_op):
			Sfx.play("step")
			get_tree().change_scene_to_file("res://scenes/battle.tscn"))
	d.add_child(launch)
	return h


func _op_card(i: int) -> Control:
	var op: Dictionary = GameState.operations[i]
	var ts := _type_style(op)
	var col: Color = ts["color"]
	var story: bool = op.get("story", false)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 74)
	var on := i == selected_op
	var bg := Color(0.16, 0.24, 0.2) if on else Color(0.11, 0.13, 0.13)
	var border := GOLD if story else (ACCENT if on else Color(0.2, 0.25, 0.24))
	for st in ["normal", "hover", "pressed"]:
		var sb := _flat(bg if st != "hover" else bg.lightened(0.06), border)
		sb.set_border_width_all(2 if on or story else 1)
		b.add_theme_stylebox_override(st, sb)
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var stripe := ColorRect.new()
	stripe.color = col
	stripe.custom_minimum_size = Vector2(8, 0)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(stripe)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var top := _label(("★ STORY · " if story else "") + String(ts["name"]), 12, GOLD if story else col)
	v.add_child(top)
	var title := _label(op["title"], 18, Color.WHITE)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(title)
	var sub := _label("%s · threat %d · fuel %d" % [op["zone"], op["diff"], op["fuel"]], 13, DIM)
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(sub)
	for c in v.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fuel_ok: bool = GameState.res["fuel"] >= op["fuel"]
	if not fuel_ok:
		var nf := _label("NO FUEL ", 12, BAD)
		nf.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(nf)
	b.pressed.connect(func():
		selected_op = i
		Sfx.play("click")
		_build())
	return b


func _badge(text: String, col: Color) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.2)
	sb.border_color = col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(_label(text, 13, col))
	return p


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
# BASE: tap a site on the Rock, manage just that site
# =============================================================================

func _tab_base() -> Control:
	var gs := GameState
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.15
	h.add_child(left)
	var scene := Control.new()
	scene.set_script(RockScene)
	scene.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scene.set("selected", selected_site)
	scene.set("show_markers", true)
	scene.connect("site_pressed", func(i: int):
		selected_site = i
		demolish_armed = -1
		Sfx.play("click")
		_build())
	left.add_child(scene)
	left.add_child(_label("Tap a numbered site on the Rock to manage it.", 14, DIM))

	var right := _panel()
	h.add_child(right)
	var v := _scroll_box(right, 8)

	# People summary: the Rock's most precious resource.
	var ppl := HBoxContainer.new()
	ppl.add_theme_constant_override("separation", 10)
	var pl := _label("PEOPLE  %d   ·   working %d   ·   idle %d   ·   beds %d" % [gs.survivors, gs.crew_assigned(), maxi(0, gs.idle_people()), gs.beds()], 16, Color(1.0, 0.85, 0.6))
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ppl.add_child(pl)
	var auto := _button("Auto-assign", gs.idle_people() > 0)
	auto.custom_minimum_size = Vector2(140, 40)
	auto.add_theme_font_size_override("font_size", 15)
	auto.pressed.connect(func():
		gs.auto_assign()
		gs.save_game()
		Sfx.play("click")
		_build())
	ppl.add_child(auto)
	v.add_child(ppl)
	if gs.survivors > gs.beds():
		v.add_child(_label("%d people sleep in the chapel and can't work. Build or upgrade a Bunkhouse." % (gs.survivors - gs.beds()), 14, BAD, true))
	v.add_child(HSeparator.new())

	var i := clampi(selected_site, 0, gs.slots.size() - 1)
	var sl: Dictionary = gs.slots[i]
	v.add_child(_label("SITE %d · %s" % [i + 1, gs.SLOT_NAMES[i].to_upper()], 14, DIM))
	if not sl.has("type"):
		v.add_child(_label("Empty ground. Build:", 20, Color.WHITE))
		for type in gs.BUILDINGS:
			v.add_child(_build_option(i, type))
		return h

	var info: Dictionary = gs.BUILDINGS[sl["type"]]
	var title_row := HBoxContainer.new()
	var tl := _label(info["name"], 24, Color.WHITE)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(tl)
	title_row.add_child(_label("LEVEL " + "■".repeat(sl["level"]) + "□".repeat(gs.MAX_LEVEL - sl["level"]), 16, ACCENT))
	v.add_child(title_row)
	v.add_child(_label(info["desc"], 15, DIM, true))
	v.add_child(_label(gs.production_preview(i), 17, ACCENT, true))

	var req := gs.crew_required(i)
	if req > 0:
		var crew: int = sl.get("crew", 0)
		var crew_row := HBoxContainer.new()
		crew_row.add_theme_constant_override("separation", 8)
		var minus := _button("−", crew > 0)
		minus.custom_minimum_size = Vector2(60, 52)
		minus.add_theme_font_size_override("font_size", 26)
		minus.pressed.connect(func():
			gs.assign_crew(i, -1)
			_build())
		crew_row.add_child(minus)
		var dots := ""
		for k in req:
			dots += "● " if k < crew else "○ "
		var cl := _label("CREW  %s  %d/%d" % [dots, crew, req], 19, Color(1.0, 0.85, 0.6) if crew >= req else WARN)
		cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		crew_row.add_child(cl)
		var plus := _button("+", crew < req and gs.idle_people() > 0)
		plus.custom_minimum_size = Vector2(60, 52)
		plus.add_theme_font_size_override("font_size", 26)
		plus.pressed.connect(func():
			gs.assign_crew(i, 1)
			_build())
		crew_row.add_child(plus)
		v.add_child(crew_row)
		if crew < req:
			v.add_child(_label("Short of hands: works at reduced output." if crew > 0 else "Nobody working here: it produces nothing.", 14, WARN))

	if sl["type"] == "ammo":
		v.add_child(_ammo_focus_row())

	v.add_child(HSeparator.new())
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	if sl["level"] < gs.MAX_LEVEL:
		var uc := gs.upgrade_cost(i)
		var ub := _button("Upgrade to Lv %d — %s" % [sl["level"] + 1, gs.cost_text(uc)], gs.can_afford(uc))
		ub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ub.custom_minimum_size = Vector2(0, 52)
		ub.pressed.connect(func():
			if gs.upgrade(i):
				Sfx.play("hit", -10.0)
			_build())
		actions.add_child(ub)
	else:
		var mx := _label("Fully upgraded", 16, DIM)
		mx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(mx)
	var db := _button("Tap again to demolish" if demolish_armed == i else "Demolish", true)
	db.add_theme_font_size_override("font_size", 14)
	db.custom_minimum_size = Vector2(130 if demolish_armed != i else 200, 52)
	db.add_theme_stylebox_override("normal", _flat(Color(0.35, 0.1, 0.08) if demolish_armed == i else Color(0.16, 0.12, 0.12)))
	db.pressed.connect(func():
		if demolish_armed == i:
			gs.demolish(i)
			demolish_armed = -1
		else:
			demolish_armed = i
		_build())
	actions.add_child(db)
	v.add_child(actions)
	return h


func _build_option(i: int, type: String) -> Control:
	var gs := GameState
	var info: Dictionary = gs.BUILDINGS[type]
	var cost: Dictionary = gs.build_cost(type)
	var ok := gs.can_afford(cost)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not ok
	b.custom_minimum_size = Vector2(0, 62)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_right = -12
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var n := _label(info["name"], 18, Color.WHITE if ok else DIM)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(n)
	var workers: int = info["workers"]
	top.add_child(_label(("%d crew · " % workers if workers > 0 else "") + gs.cost_text(cost), 14, WARN if ok else BAD))
	var dl := _label(info["desc"], 13, DIM)
	dl.clip_text = true
	dl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(dl)
	for c in top.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(func():
		if gs.build(i, type):
			Sfx.play("hit", -10.0)
			gs.auto_assign()
			gs.save_game()
		_build())
	return b


func _ammo_focus_row() -> Control:
	var gs := GameState
	var v := VBoxContainer.new()
	v.add_child(_label("The factory makes:", 15, DIM))
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 6)
	v.add_child(fr)
	for f in [["shells", "Shells"], ["rockets", "Rockets"], ["rounds", "Rounds"]]:
		var key: String = f[0]
		var fb := _button(f[1], true)
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fb.custom_minimum_size = Vector2(0, 46)
		if gs.ammo_focus == key:
			fb.add_theme_stylebox_override("normal", _flat(Color(0.5, 0.3, 0.12), Color(1.0, 0.6, 0.3)))
		fb.pressed.connect(func():
			gs.ammo_focus = key
			gs.save_game()
			Sfx.play("click")
			_build())
		fr.add_child(fb)
	return v


# =============================================================================
# BRIGID: armour on the left, ammunition on the right
# =============================================================================

func _tab_mech() -> Control:
	var gs := GameState
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)

	var left := _panel()
	h.add_child(left)
	var lh := HBoxContainer.new()
	lh.add_theme_constant_override("separation", 12)
	left.add_child(lh)
	var diagram := Control.new()
	diagram.set_script(MechDiagram)
	diagram.custom_minimum_size = Vector2(170, 220)
	lh.add_child(diagram)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	lh.add_child(v)
	v.add_child(_label("ARMOUR", 18, ACCENT))
	v.add_child(_label("Mags patches Brigid with scrap: 1 scrap per 4 points.", 14, DIM, true))
	for part in gs.PARTS:
		var p: String = part
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var ratio := gs.hp_ratio(p)
		var name_l := _label("%s  %d/%d" % [gs.PART_NAMES[p], int(ceil(gs.part_hp[p])), int(gs.max_hp(p))], 17, MechDiagram.part_color(ratio) if ratio > 0.0 else BAD)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		var cost := gs.repair_cost(p)
		var b := _button("Repair · %d scrap" % cost if cost > 0 else "✓", cost > 0 and gs.res["scrap"] > 0)
		b.custom_minimum_size = Vector2(170, 44)
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(func():
			gs.repair(p)
			Sfx.play("click")
			_build())
		row.add_child(b)
		v.add_child(row)
	var total := gs.total_repair_cost()
	var all := _button("Repair everything · %d scrap" % total if total > 0 else "Fully repaired", total > 0 and gs.res["scrap"] > 0)
	all.custom_minimum_size = Vector2(0, 54)
	all.pressed.connect(func():
		gs.repair_all()
		Sfx.play("click")
		_build())
	v.add_child(all)

	var right := _panel(430)
	h.add_child(right)
	var r := VBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	right.add_child(r)
	r.add_child(_label("AMMUNITION", 18, ACCENT))
	var caps := gs.ammo_caps()
	for a in gs.AMMO:
		var row2 := VBoxContainer.new()
		row2.add_theme_constant_override("separation", 2)
		row2.add_child(_label("%s — %d in stock" % [gs.AMMO_NAMES[a], gs.ammo[a]], 17, Color(1.0, 0.7, 0.5)))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 12)
		bar.max_value = caps[a]
		bar.value = mini(caps[a], gs.ammo[a])
		row2.add_child(bar)
		row2.add_child(_label("Brigid carries %d / %d per drop" % [mini(caps[a], gs.ammo[a]), caps[a]], 13, DIM))
		r.add_child(row2)
	r.add_child(HSeparator.new())
	if gs.has_building("ammo", false):
		r.add_child(_ammo_focus_row())
	else:
		r.add_child(_label("No Ammo Factory yet. Build one in the BASE tab, or find ammo in salvage caches.", 14, WARN, true))
	r.add_child(_label("Unused ammo comes home with you. Research Ammo Racks in the LAB to carry more.", 13, DIM, true))
	return h


# =============================================================================
# LAB: research cards in two columns
# =============================================================================

func _tab_lab() -> Control:
	var gs := GameState
	var p := _panel()
	var box := _scroll_box(p, 8)
	box.add_child(_dialogue_row("sandoval", "Biomass, circuits and a little scrap. Bring me those and I'll make Brigid sing. Well. Not like the Choir."))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(grid)
	for id in gs.RESEARCH:
		var rid: String = id
		var info: Dictionary = gs.RESEARCH[rid]
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", _flat(Color(0.11, 0.13, 0.14), Color(0.2, 0.3, 0.28)))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		card.add_child(v)
		var top := HBoxContainer.new()
		var nl := _label(info["name"], 18, Color.WHITE)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(nl)
		var lv: int = gs.research[rid]
		top.add_child(_label("■".repeat(lv) + "□".repeat(int(info["max"]) - lv), 16, ACCENT))
		v.add_child(top)
		var dl := _label(info["desc"], 14, DIM, true)
		v.add_child(dl)
		var txt := "Complete"
		var ok := false
		if not gs.research_maxed(rid):
			var c := gs.research_cost(rid)
			txt = "Research · " + gs.cost_text(c)
			ok = gs.can_afford(c)
		var b := _button(txt, ok)
		b.custom_minimum_size = Vector2(0, 44)
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(func():
			if gs.do_research(rid):
				Sfx.play("pickup")
			_build())
		v.add_child(b)
		grid.add_child(card)
	return p


# =============================================================================
# Menu (☰)
# =============================================================================

func _open_menu() -> void:
	var center := _overlay_center()
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(460, 0)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	v.add_child(_label("ST. COLUMBA'S ROCK", 26, ACCENT))
	v.add_child(_label("Day %d · saved in slot %d" % [GameState.day, GameState.slot], 15, DIM))
	var resume := _button("Resume", true)
	resume.custom_minimum_size = Vector2(0, 58)
	resume.pressed.connect(_close_overlay)
	v.add_child(resume)
	var settings := _button("Settings", true)
	settings.custom_minimum_size = Vector2(0, 58)
	settings.pressed.connect(func():
		_close_overlay()
		var c2 := _overlay_center()
		c2.add_child(SettingsScript.build_panel(_close_overlay)))
	v.add_child(settings)
	var quit := _button("Save & quit to main menu", true)
	quit.custom_minimum_size = Vector2(0, 58)
	quit.pressed.connect(func():
		GameState.save_game()
		get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	v.add_child(quit)
	v.add_child(_label("The game saves itself after every change.", 13, DIM))


func _overlay_center() -> CenterContainer:
	_close_overlay()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.7)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_overlay = shade
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	return center


func _close_overlay() -> void:
	if _overlay and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null


# =============================================================================
# Night report
# =============================================================================

func _show_report() -> void:
	var r: Dictionary = GameState.last_report
	var center := _overlay_center()
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(780, 0)
	center.add_child(p)
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
		_close_overlay())
	v.add_child(ok)


# =============================================================================
# Widgets
# =============================================================================

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL_BG
	panel.border_color = Color(0.2, 0.4, 0.3)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(8)
	panel.set_content_margin_all(10)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("normal", "Button", _flat(Color(0.14, 0.3, 0.2)))
	t.set_stylebox("hover", "Button", _flat(Color(0.18, 0.4, 0.26)))
	t.set_stylebox("pressed", "Button", _flat(Color(0.25, 0.55, 0.35)))
	t.set_stylebox("disabled", "Button", _flat(Color(0.12, 0.13, 0.14)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.47, 0.48))
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.15, 0.12, 0.1)
	bar_bg.set_corner_radius_all(4)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(1.0, 0.6, 0.3)
	bar_fill.set_corner_radius_all(4)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	return t


func _flat(c: Color, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(6)
	s.set_content_margin_all(8)
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(2)
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
