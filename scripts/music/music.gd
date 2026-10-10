extends CanvasLayer
## Music player (autoload "Music"). Plays the 20 generated songs and shows a
## small player bar at the top of every screen: previous / song list /
## next / pause. Songs are composed on demand (in the background) and cached
## on disk, so each one is only ever composed once per device.

const Composer = preload("res://scripts/music/composer.gd")

const CACHE_DIR := "user://music_cache"
const CACHE_VERSION := 1
const SETTINGS_PATH := "user://music.cfg"
const LOOPS_PER_SONG := 2
const VOLUME_DB := -7.0

## name, bpm, scale, chord progression (scale degrees), drums, bass, lead,
## arpeggio, bass key (MIDI), pad level, swing.
const SONGS := [
	{"name": "Hive Breakers", "bpm": 128, "scale": "minor", "prog": [0, 5, 2, 6], "drums": "four", "bass": "octave", "lead": "saw", "arp": true, "key": 33},
	{"name": "Iron Rain", "bpm": 140, "scale": "phrygian", "prog": [0, 1, 0, 6], "drums": "rock", "bass": "sync", "lead": "square", "arp": false, "key": 40},
	{"name": "Neon Crawlers", "bpm": 118, "scale": "dorian", "prog": [0, 3, 0, 4], "drums": "break", "bass": "sync", "lead": "pulse", "arp": true, "key": 38},
	{"name": "Last Light Over Ruins", "bpm": 92, "scale": "minor", "prog": [0, 5, 3, 4], "drums": "halftime", "bass": "long", "lead": "triangle", "arp": false, "key": 38, "pad": 1.0},
	{"name": "Cockpit Fever", "bpm": 150, "scale": "major", "prog": [0, 4, 5, 3], "drums": "rock", "bass": "octave", "lead": "square", "arp": false, "key": 36},
	{"name": "Spitter Swing", "bpm": 112, "scale": "mixolydian", "prog": [0, 6, 3, 0], "drums": "shuffle", "bass": "walk", "lead": "square", "arp": false, "key": 31, "swing": 0.33},
	{"name": "Brute Force", "bpm": 100, "scale": "harmonic", "prog": [0, 5, 3, 4], "drums": "halftime", "bass": "sync", "lead": "saw", "arp": false, "key": 35},
	{"name": "Ringed Planet", "bpm": 84, "scale": "major", "prog": [0, 3, 5, 4], "drums": "halftime", "bass": "long", "lead": "bell", "arp": true, "key": 36, "pad": 1.0},
	{"name": "Salvage Run", "bpm": 160, "scale": "minor", "prog": [0, 6, 5, 6], "drums": "dnb", "bass": "octave", "lead": "pulse", "arp": false, "key": 33},
	{"name": "Hangar Blues", "bpm": 96, "scale": "mixolydian", "prog": [0, 3, 0, 4], "drums": "shuffle", "bass": "walk", "lead": "triangle", "arp": false, "key": 40, "swing": 0.33},
	{"name": "Hatch Open", "bpm": 124, "scale": "dorian", "prog": [0, 3, 6, 4], "drums": "disco", "bass": "pulse", "lead": "bell", "arp": true, "key": 38},
	{"name": "Swarm Alarm", "bpm": 170, "scale": "phrygian", "prog": [0, 1, 6, 1], "drums": "dnb", "bass": "sync", "lead": "saw", "arp": true, "key": 36},
	{"name": "Stomp and Roll", "bpm": 136, "scale": "major", "prog": [0, 0, 3, 4], "drums": "rock", "bass": "octave", "lead": "saw", "arp": false, "key": 31},
	{"name": "Red Horizon", "bpm": 108, "scale": "harmonic", "prog": [0, 3, 4, 4], "drums": "march", "bass": "long", "lead": "square", "arp": false, "key": 33},
	{"name": "Pilot on Foot", "bpm": 132, "scale": "minor", "prog": [0, 6, 5, 4], "drums": "break", "bass": "pulse", "lead": "pulse", "arp": false, "key": 40},
	{"name": "Organic Walls", "bpm": 90, "scale": "phrygian", "prog": [0, 1, 0, 1], "drums": "halftime", "bass": "long", "lead": "bell", "arp": false, "key": 35, "pad": 1.2},
	{"name": "Victory Over Earth", "bpm": 120, "scale": "major", "prog": [0, 4, 5, 3], "drums": "march", "bass": "octave", "lead": "square", "arp": true, "key": 36},
	{"name": "Night Shift", "bpm": 104, "scale": "dorian", "prog": [0, 2, 3, 4], "drums": "four", "bass": "walk", "lead": "triangle", "arp": false, "key": 38, "pad": 0.8},
	{"name": "Rocket Salvo", "bpm": 146, "scale": "minor", "prog": [0, 3, 5, 4], "drums": "disco", "bass": "sync", "lead": "saw", "arp": true, "key": 33},
	{"name": "Home Before Dawn", "bpm": 88, "scale": "major", "prog": [0, 5, 3, 4], "drums": "halftime", "bass": "long", "lead": "triangle", "arp": true, "key": 31, "pad": 1.0},
]

var current := 0
var paused := false

var _player: AudioStreamPlayer
var _streams := {}          ## index -> AudioStreamWAV (kept in memory)
var _job: Composer = null   ## song being composed
var _job_index := -1
var _thread: Thread = null
var _thread_done := false
var _use_thread := true
var _queue: Array[int] = []
var _played := 0.0

var _bar: PanelContainer
var _title: Button
var _pause_btn: Button
var _list: PanelContainer


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_use_thread = not OS.has_feature("web") or OS.has_feature("threads")
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	_load_settings()
	_player = AudioStreamPlayer.new()
	_player.volume_db = VOLUME_DB
	_player.bus = "Music"
	add_child(_player)
	_build_ui()
	_request(current)


func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()


# --- Public -----------------------------------------------------------------

func play_song(i: int) -> void:
	current = posmod(i, SONGS.size())
	_played = 0.0
	paused = false
	_save_settings()
	_request(current)
	_refresh_ui()


func next_song() -> void:
	play_song(current + 1)


func prev_song() -> void:
	play_song(current - 1)


func toggle_pause() -> void:
	paused = not paused
	_player.stream_paused = paused
	if not paused and not _player.playing and _streams.has(current):
		_start_playback()
	_save_settings()
	_refresh_ui()


func covers(p: Vector2) -> bool:
	## True if a screen point is on the player, so games can ignore that touch.
	if _bar and _bar.get_global_rect().has_point(p):
		return true
	return _list != null and _list.visible and _list.get_global_rect().has_point(p)


# --- Playback & composing ---------------------------------------------------

func _request(i: int) -> void:
	if _streams.has(i):
		if i == current:
			_start_playback()
		return
	var cached := _load_cached(i)
	if cached:
		_remember(i, cached)
		if i == current:
			_start_playback()
		return
	if i == current:
		_player.stop()
	if _job_index == i or _queue.has(i):
		if i == current and _queue.has(i):
			_queue.erase(i)
			_queue.push_front(i)
		return
	if i == current:
		_queue.push_front(i)
	else:
		_queue.append(i)
	_start_next_job()


func _start_playback() -> void:
	_player.stream = _streams[current]
	_played = 0.0
	if not paused:
		_player.play()
	_player.stream_paused = paused
	_refresh_ui()
	# Get the following song ready in the background.
	var nxt := (current + 1) % SONGS.size()
	if not _streams.has(nxt) and not FileAccess.file_exists(_cache_path(nxt)):
		_request(nxt)


func _start_next_job() -> void:
	if _job != null or _queue.is_empty():
		return
	_job_index = _queue.pop_front()
	_job = Composer.new()
	var def: Dictionary = SONGS[_job_index].duplicate()
	def["seed"] = 1000 + _job_index * 7919
	_job.prepare(def)
	_thread_done = false
	if _use_thread:
		_thread = Thread.new()
		_thread.start(_thread_work)


func _thread_work() -> void:
	while not _job.work(Time.get_ticks_usec() + 1000000):
		pass
	_thread_done = true


func _process(delta: float) -> void:
	if _job != null:
		var finished := false
		if _use_thread:
			finished = _thread_done
			if finished:
				_thread.wait_to_finish()
				_thread = null
		else:
			# No threads (some web builds): compose a little each frame.
			finished = _job.work(Time.get_ticks_usec() + 5000)
		if finished:
			var idx := _job_index
			var stream: AudioStreamWAV = _job.stream
			_job = null
			_job_index = -1
			_save_cached(idx, stream)
			_remember(idx, stream)
			if idx == current:
				_start_playback()
			_start_next_job()
		elif _job_index == current:
			_title.text = "♪ Composing \"%s\"… %d%%" % [SONGS[current]["name"], int(_job.progress * 100.0)]

	if _player.playing and not paused and _player.stream:
		_played += delta
		var length: float = _player.stream.get_length()
		if length > 0.0 and _played >= length * LOOPS_PER_SONG:
			next_song()


func _remember(i: int, s: AudioStreamWAV) -> void:
	_streams[i] = s
	# Keep memory small: only the current song and its neighbours.
	for k in _streams.keys():
		var d: int = absi(k - current)
		if d > 1 and d < SONGS.size() - 1:
			_streams.erase(k)


func _cache_path(i: int) -> String:
	return "%s/song_%02d_v%d.pcm" % [CACHE_DIR, i, CACHE_VERSION]


func _save_cached(i: int, s: AudioStreamWAV) -> void:
	var f := FileAccess.open(_cache_path(i), FileAccess.WRITE)
	if f == null:
		return
	f.store_32(s.mix_rate)
	f.store_32(s.data.size())
	f.store_buffer(s.data)


func _load_cached(i: int) -> AudioStreamWAV:
	if not FileAccess.file_exists(_cache_path(i)):
		return null
	var f := FileAccess.open(_cache_path(i), FileAccess.READ)
	if f == null:
		return null
	var rate := f.get_32()
	var size := f.get_32()
	var data := f.get_buffer(size)
	if data.size() != size or size == 0:
		return null
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = size / 2
	return s


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("music", "current", current)
	cf.set_value("music", "paused", paused)
	cf.save(SETTINGS_PATH)


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		current = clampi(int(cf.get_value("music", "current", 0)), 0, SONGS.size() - 1)
		paused = bool(cf.get_value("music", "paused", false))


# --- Player bar ---------------------------------------------------------------

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.04, 0.82)
	style.border_color = Color(0.2, 0.5, 0.3, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(2)

	_bar = PanelContainer.new()
	_bar.add_theme_stylebox_override("panel", style)
	_bar.anchor_left = 0.5
	_bar.anchor_right = 0.5
	_bar.offset_left = -240
	_bar.offset_right = 240
	_bar.offset_top = 3
	_bar.offset_bottom = 37
	root.add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	_bar.add_child(row)

	row.add_child(_small_button("◀◀", prev_song, 54))
	_title = _small_button("", _toggle_list, 0)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_title.alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_title)
	row.add_child(_small_button("▶▶", next_song, 54))
	_pause_btn = _small_button("❚❚", toggle_pause, 54)
	row.add_child(_pause_btn)

	_list = PanelContainer.new()
	var list_style := style.duplicate() as StyleBoxFlat
	list_style.bg_color = Color(0.03, 0.05, 0.04, 0.98)
	_list.add_theme_stylebox_override("panel", list_style)
	_list.anchor_left = 0.5
	_list.anchor_right = 0.5
	_list.offset_left = -240
	_list.offset_right = 240
	_list.offset_top = 40
	_list.visible = false
	root.add_child(_list)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	_list.add_child(grid)
	for i in SONGS.size():
		var idx := i
		var pick := func() -> void:
			_list.visible = false
			play_song(idx)
		var b := _small_button("%02d  %s" % [i + 1, SONGS[i]["name"]], pick, 236)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		grid.add_child(b)
	_refresh_ui()


func _small_button(text: String, cb: Callable, min_w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_w, 30)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color(0.55, 1.0, 0.7))
	b.add_theme_color_override("font_hover_color", Color(0.8, 1.0, 0.85))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.14, 0.1, 0.9)
	normal.set_corner_radius_all(4)
	normal.set_content_margin_all(4)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.12, 0.24, 0.16, 0.95)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b


func _toggle_list() -> void:
	_list.visible = not _list.visible


func _refresh_ui() -> void:
	if _title == null:
		return
	_title.text = "♪ %02d/%d  %s" % [current + 1, SONGS.size(), SONGS[current]["name"]]
	_pause_btn.text = "▶" if paused else "❚❚"
