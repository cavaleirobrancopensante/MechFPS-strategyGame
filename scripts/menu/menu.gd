extends Control
## Main menu: Survival, Continue, New Game, Load Game, Settings, Quit.

const ModelArt = preload("res://scripts/battle/model_art.gd")
const SettingsScript = preload("res://scripts/settings.gd")

const ACCENT := Color(0.4, 1.0, 0.6)
const GOLD := Color(1.0, 0.8, 0.3)

var t := 0.0
var _mech_tex: Texture2D
var _buttons: VBoxContainer
var _overlay: Control
var _confirm_slot := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = _make_theme()
	_mech_tex = ImageTexture.create_from_image(ModelArt._render(ModelArt._mech(), 0.35, 160, 2.3))
	_build()
	# Build (or load) the 3D-photographed people and weapons in the
	# background while you're on the menu.
	if not Baker.done:
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 15)
		lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 0.7))
		lbl.position = Vector2(20, 690)
		lbl.text = "Preparing models…"
		add_child(lbl)
		Baker.progress.connect(func(f, what): if is_instance_valid(lbl): lbl.text = "Preparing models… %s %d%%" % [what, int(f * 100.0)])
		Baker.finished.connect(func():
			if is_instance_valid(lbl):
				lbl.queue_free()
			_use_baked_mech())
		Baker.bake()
	else:
		_use_baked_mech()


func _use_baked_mech() -> void:
	## Show the photographed 3D Brigid on the menu once it exists.
	if Baker.sprites.has("mech"):
		_mech_tex = Baker.sprites["mech"]["dirs"][1][0]


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	# Dusk sky over a ruined skyline, the Lantern hanging above.
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([Color(0.05, 0.03, 0.1), Color(0.07, 0.04, 0.12), Color(0.55, 0.22, 0.18), Color(0.45, 0.16, 0.16)]))
	var lc := Vector2(w * 0.72, h * 0.3)
	draw_circle(lc, 120, Color(0.95, 0.62, 0.4))
	draw_circle(lc + Vector2(26, 20), 104, Color(0.72, 0.4, 0.3))
	draw_circle(lc + Vector2(48, 34), 86, Color(0.45, 0.22, 0.2))
	var ring := PackedVector2Array()
	for i in 65:
		var a := float(i) / 64.0 * TAU
		ring.append(lc + Vector2(cos(a) * 230, sin(a) * 46).rotated(-0.22))
	draw_polyline(ring, Color(1.0, 0.85, 0.65, 0.7), 3.0)
	for i in 40:
		var sx := fposmod(i * 131.0, w)
		var sy := fposmod(i * 71.0, h * 0.5)
		draw_rect(Rect2(sx, sy, 2, 2), Color(1, 1, 1, 0.3 + 0.3 * sin(t * 1.5 + i)))
	# Skyline layers
	for layer in 3:
		var base_y := h * (0.62 + layer * 0.1)
		var col: Color = [Color(0.2, 0.09, 0.12), Color(0.13, 0.06, 0.09), Color(0.07, 0.04, 0.06)][layer]
		var x := -fposmod(t * (6.0 + layer * 10.0), 140.0)
		var k := 0
		while x < w + 140:
			var bw := 50.0 + fposmod(k * 37.0 + layer * 13.0, 70.0)
			var bh := 40.0 + fposmod(k * 53.0 + layer * 29.0, 120.0) * (1.0 - layer * 0.25)
			draw_rect(Rect2(x, base_y - bh, bw, bh + h), col)
			if layer == 0 and k % 3 == 0:
				draw_rect(Rect2(x + 10, base_y - bh + 14, 6, 6), Color(1.0, 0.75, 0.35, 0.5 + 0.4 * sin(t + k)))
			x += bw + 6.0
			k += 1
	# Brigid standing guard
	var mh := h * 0.62
	var bob := sin(t * 1.2) * 3.0
	draw_texture_rect(_mech_tex, Rect2(w * 0.62 - mh * 0.5, h - mh - 10 + bob, mh, mh), false)
	# Drifting ash
	for i in 50:
		var ax := fposmod(i * 97.0 + t * (14.0 + i % 7 * 3.0), w)
		var ay := fposmod(i * 61.0 + t * (22.0 + i % 5 * 4.0), h)
		draw_rect(Rect2(ax, ay, 2, 2), Color(0.9, 0.8, 0.75, 0.35))


func _build() -> void:
	for c in get_children():
		c.queue_free()
	var left := VBoxContainer.new()
	left.position = Vector2(60, 70)
	left.custom_minimum_size = Vector2(440, 0)
	left.add_theme_constant_override("separation", 10)
	add_child(left)
	var title := Label.new()
	title.text = "HIVE BREAKERS"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", ACCENT)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 10)
	left.add_child(title)
	var sub := Label.new()
	sub.text = "One walker. One rock. One last stand."
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(1, 0.9, 0.8))
	left.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 16)
	left.add_child(gap)

	_buttons = left
	var best: Dictionary = GameState.survival_best
	var surv := _menu_button("SURVIVAL", "Endless waves · infinite ammo · best: wave %d" % best["wave"], true)
	surv.add_theme_stylebox_override("normal", _flat(Color(0.45, 0.25, 0.08, 0.92)))
	surv.add_theme_stylebox_override("hover", _flat(Color(0.6, 0.33, 0.1, 0.95)))
	surv.pressed.connect(func():
		GameState.start_survival()
		Sfx.play("step")
		get_tree().change_scene_to_file("res://scenes/battle.tscn"))
	left.add_child(surv)
	var cont_sum := GameState.slot_summary(GameState.last_slot) if GameState.last_slot > 0 else {}
	var cont := _menu_button("CONTINUE", ("Slot %d · Day %d · %s" % [GameState.last_slot, cont_sum["day"], cont_sum["story"]]) if not cont_sum.is_empty() else "No campaign yet", not cont_sum.is_empty())
	cont.pressed.connect(func():
		if GameState.load_slot(GameState.last_slot):
			get_tree().change_scene_to_file("res://scenes/base.tscn"))
	left.add_child(cont)
	var newg := _menu_button("NEW GAME", "Start the campaign at St. Columba's Rock", true)
	newg.pressed.connect(func(): _show_slots(true))
	left.add_child(newg)
	var loadb := _menu_button("LOAD GAME", "Pick one of %d save slots" % GameState.SLOT_COUNT, true)
	loadb.pressed.connect(func(): _show_slots(false))
	left.add_child(loadb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var sett := _menu_button("SETTINGS", "", true)
	sett.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sett.pressed.connect(_show_settings)
	row.add_child(sett)
	var quit := _menu_button("QUIT", "", true)
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit.pressed.connect(func(): get_tree().quit())
	row.add_child(quit)
	left.add_child(row)

	var ver := Label.new()
	ver.text = "v" + GameState.VERSION
	ver.add_theme_font_size_override("font_size", 14)
	ver.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.position = Vector2(-70, -30)
	add_child(ver)


func _menu_button(title: String, sub: String, enabled: bool) -> Button:
	var b := Button.new()
	b.text = title if sub == "" else "%s\n%s" % [title, sub]
	b.disabled = not enabled
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(440, 74 if sub != "" else 58)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22 if sub == "" else 20)
	return b


func _overlay_box() -> VBoxContainer:
	if _overlay:
		_overlay.queue_free()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.7)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_overlay = shade
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(640, 0)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	return v


func _close_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null
	_confirm_slot = -1


func _show_slots(new_game: bool) -> void:
	var v := _overlay_box()
	var title := Label.new()
	title.text = "NEW GAME — PICK A SLOT" if new_game else "LOAD GAME"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", ACCENT)
	v.add_child(title)
	for i in range(1, GameState.SLOT_COUNT + 1):
		var si := i
		var sum := GameState.slot_summary(i)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := "Slot %d — empty" % i
		if not sum.is_empty():
			label = "Slot %d — Day %d · %d people · %s\nSaved %s" % [i, sum["day"], sum["people"], sum["story"], String(sum["saved_at"]).replace("T", " ")]
		var b := _menu_button(label, "", new_game or not sum.is_empty())
		b.add_theme_font_size_override("font_size", 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if new_game and not sum.is_empty() and _confirm_slot == i:
			b.text = "Slot %d — tap again to OVERWRITE this campaign" % i
			b.add_theme_stylebox_override("normal", _flat(Color(0.45, 0.1, 0.08)))
		b.pressed.connect(func():
			if new_game:
				if not GameState.slot_summary(si).is_empty() and _confirm_slot != si:
					_confirm_slot = si
					_show_slots(true)
					return
				GameState.start_new_game(si)
				get_tree().change_scene_to_file("res://scenes/base.tscn")
			elif GameState.load_slot(si):
				get_tree().change_scene_to_file("res://scenes/base.tscn"))
		row.add_child(b)
		if not new_game and not sum.is_empty():
			var del := Button.new()
			del.text = "Sure?" if _confirm_slot == -10 - i else "Delete"
			del.custom_minimum_size = Vector2(100, 58)
			del.focus_mode = Control.FOCUS_NONE
			del.pressed.connect(func():
				if _confirm_slot == -10 - si:
					GameState.delete_slot(si)
					_confirm_slot = -1
					_build()
					_show_slots(false)
				else:
					_confirm_slot = -10 - si
					_show_slots(false))
			row.add_child(del)
		v.add_child(row)
	var back := _menu_button("Back", "", true)
	back.alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.pressed.connect(_close_overlay)
	v.add_child(back)


func _show_settings() -> void:
	if _overlay:
		_overlay.queue_free()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.7)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_overlay = shade
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	center.add_child(SettingsScript.build_panel(_close_overlay))


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 20
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.07, 0.09, 0.1, 0.97)
	panel.border_color = Color(0.25, 0.55, 0.35)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(8)
	panel.set_content_margin_all(18)
	th.set_stylebox("panel", "PanelContainer", panel)
	th.set_stylebox("normal", "Button", _flat(Color(0.08, 0.14, 0.11, 0.9)))
	th.set_stylebox("hover", "Button", _flat(Color(0.12, 0.26, 0.17, 0.95)))
	th.set_stylebox("pressed", "Button", _flat(Color(0.2, 0.45, 0.28)))
	th.set_stylebox("disabled", "Button", _flat(Color(0.08, 0.09, 0.1, 0.8)))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color(0.85, 1.0, 0.9))
	th.set_color("font_disabled_color", "Button", Color(0.45, 0.5, 0.48))
	return th


func _flat(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(8)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.border_color = Color(0.3, 0.6, 0.4, 0.6)
	s.border_width_left = 3
	return s
