extends Node
## Player settings (autoload "Settings"): volumes, look sensitivity,
## graphics quality and control hints. Saved separately from campaigns.

signal changed

const PATH := "user://settings.cfg"
const QUALITY_COLUMNS := [120, 160, 200]
const QUALITY_NAMES := ["Low (fastest)", "Medium", "High"]

var music_volume := 0.7
var sfx_volume := 0.9
var look_sensitivity := 1.0
var quality := 2
var show_hints := true


func _ready() -> void:
	# Separate audio buses so music and effects have their own volume.
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	load_settings()
	apply()


func columns() -> int:
	return QUALITY_COLUMNS[clampi(quality, 0, 2)]


func apply() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(music_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(sfx_volume, 0.0001)))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), music_volume <= 0.001)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), sfx_volume <= 0.001)
	changed.emit()


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in ["music_volume", "sfx_volume", "look_sensitivity", "quality", "show_hints"]:
		cf.set_value("settings", k, get(k))
	cf.save(PATH)


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k in ["music_volume", "sfx_volume", "look_sensitivity", "quality", "show_hints"]:
		set(k, cf.get_value("settings", k, get(k)))


static func build_panel(on_close: Callable) -> PanelContainer:
	## A settings panel usable from the main menu, the base and the pause menu.
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(620, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	v.add_child(title)
	var s: Node = Engine.get_main_loop().root.get_node("Settings")
	v.add_child(_slider_row("Music volume", s.music_volume, func(x):
		s.music_volume = x
		s.apply()))
	v.add_child(_slider_row("Effects volume", s.sfx_volume, func(x):
		s.sfx_volume = x
		s.apply()))
	v.add_child(_slider_row("Look sensitivity", (s.look_sensitivity - 0.4) / 1.6, func(x):
		s.look_sensitivity = 0.4 + x * 1.6
		s.apply()))
	var qrow := HBoxContainer.new()
	var ql := Label.new()
	ql.text = "Graphics"
	ql.custom_minimum_size = Vector2(200, 0)
	ql.add_theme_font_size_override("font_size", 20)
	qrow.add_child(ql)
	for i in 3:
		var qi := i
		var b := Button.new()
		b.text = ["Low", "Medium", "High"][i]
		b.toggle_mode = true
		b.button_pressed = s.quality == i
		b.custom_minimum_size = Vector2(120, 50)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func():
			s.quality = qi
			for c in qrow.get_children():
				if c is Button:
					c.button_pressed = c == b
			s.apply())
		qrow.add_child(b)
	v.add_child(qrow)
	var hint := CheckButton.new()
	hint.text = "Show control hints in battle"
	hint.button_pressed = s.show_hints
	hint.focus_mode = Control.FOCUS_NONE
	hint.add_theme_font_size_override("font_size", 20)
	hint.toggled.connect(func(on):
		s.show_hints = on
		s.apply())
	v.add_child(hint)
	var note := Label.new()
	note.text = "Low: fewer screen columns and no film effects (bloom, colour grade, grain). Medium: light bloom. High: full detail."
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", Color(0.65, 0.7, 0.7))
	v.add_child(note)
	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(0, 56)
	done.focus_mode = Control.FOCUS_NONE
	done.pressed.connect(func():
		s.save_settings()
		on_close.call())
	v.add_child(done)
	return p


static func _slider_row(label: String, value: float, cb: Callable) -> Control:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(200, 0)
	l.add_theme_font_size_override("font_size", 20)
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.01
	sl.value = value
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(300, 44)
	sl.focus_mode = Control.FOCUS_NONE
	sl.value_changed.connect(cb)
	row.add_child(sl)
	return row
