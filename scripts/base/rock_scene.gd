extends Control
## An animated picture of St. Columba's Rock at dawn: the abbey, the bell
## tower, the lighthouse, the bee garden, the Gannet on its pad, the sea,
## and whatever modules you've built, drawn where they stand.

const SLOT_ANCHORS := [Vector2(0.13, 0.47), Vector2(0.29, 0.47), Vector2(0.80, 0.66), Vector2(0.74, 0.47), Vector2(0.47, 0.56), Vector2(0.625, 0.17)]

signal site_pressed(index: int)

var t := 0.0
var selected := -1
var show_markers := false


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _marker_pos(i: int) -> Vector2:
	return _p(SLOT_ANCHORS[i].x, SLOT_ANCHORS[i].y) + Vector2(0, 20.0 * _scale())


func _scale() -> float:
	return clampf(size.x / 400.0, 0.8, 2.0)


func _gui_input(event: InputEvent) -> void:
	if not show_markers:
		return
	var tapped: bool = (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if not tapped:
		return
	# Nearest site to the tap, if it's close enough to a marker or its building.
	var best := -1
	var best_d := 1e9
	for i in GameState.slots.size():
		var d := minf(event.position.distance_to(_marker_pos(i)), event.position.distance_to(_p(SLOT_ANCHORS[i].x, SLOT_ANCHORS[i].y) + Vector2(0, -12) * _scale()))
		if d < best_d:
			best_d = d
			best = i
	if best >= 0 and best_d < 48.0 * _scale():
		site_pressed.emit(best)
		accept_event()


func _p(fx: float, fy: float) -> Vector2:
	return Vector2(fx * size.x, fy * size.y)


func _draw() -> void:
	var w := size.x
	var h := size.y
	# Dawn sky
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.68), Vector2(0, h * 0.68)]),
		PackedColorArray([Color(0.08, 0.1, 0.25), Color(0.1, 0.1, 0.28), Color(0.95, 0.55, 0.35), Color(0.9, 0.45, 0.35)]))
	for i in 18:
		var sx := fposmod(i * 97.0, w)
		var sy := fposmod(i * 53.0, h * 0.3)
		draw_rect(Rect2(sx, sy, 2, 2), Color(1, 1, 1, 0.3 + 0.3 * sin(t * 2.0 + i)))
	# The Lantern
	var lc := _p(0.82, 0.16)
	draw_arc(lc, 34, PI, TAU, 24, Color(1.0, 0.85, 0.6, 0.5), 2.0)
	draw_circle(lc, 18, Color(1.0, 0.72, 0.45))
	draw_circle(lc + Vector2(5, 4), 14, Color(0.85, 0.5, 0.35))
	draw_arc(lc, 34, 0, PI, 24, Color(1.0, 0.9, 0.7, 0.8), 2.0)

	# Sea
	draw_rect(Rect2(0, h * 0.68, w, h * 0.32), Color(0.1, 0.22, 0.35))
	for row in 6:
		var y := h * (0.71 + row * 0.05)
		var pts := PackedVector2Array()
		for i in 25:
			var x := i * w / 24.0
			pts.append(Vector2(x, y + sin(x * 0.05 + t * 1.5 + row) * 2.0))
		draw_polyline(pts, Color(0.5, 0.7, 0.85, 0.25 - row * 0.03), 1.5)
	# Sun glitter
	for i in 6:
		draw_line(_p(0.3 + i * 0.03, 0.7 + i * 0.03), _p(0.33 + i * 0.03, 0.7 + i * 0.03), Color(1, 0.8, 0.5, 0.4 + 0.3 * sin(t * 3.0 + i)), 2.0)

	# The island
	var rock := PackedVector2Array([_p(0.03, 0.72), _p(0.06, 0.5), _p(0.12, 0.47), _p(0.9, 0.47), _p(0.95, 0.55), _p(0.98, 0.74), _p(0.6, 0.78), _p(0.3, 0.77)])
	draw_colored_polygon(rock, Color(0.2, 0.18, 0.2))
	draw_colored_polygon(PackedVector2Array([_p(0.06, 0.5), _p(0.12, 0.47), _p(0.9, 0.47), _p(0.92, 0.5)]), Color(0.3, 0.42, 0.25))
	# Hangar cave door in the cliff
	draw_rect(Rect2(_p(0.43, 0.6), _p(0.12, 0.08)), Color(0.08, 0.07, 0.08))
	draw_rect(Rect2(_p(0.44, 0.665), _p(0.10, 0.01)), Color(1.0, 0.75, 0.35, 0.7 + 0.2 * sin(t * 2.0)))

	# Abbey hall
	var hall := Rect2(_p(0.36, 0.34), _p(0.22, 0.13))
	draw_rect(hall, Color(0.62, 0.58, 0.52))
	draw_colored_polygon(PackedVector2Array([hall.position, Vector2(hall.end.x, hall.position.y), Vector2(hall.get_center().x, hall.position.y - h * 0.07)]), Color(0.35, 0.3, 0.32))
	for i in 4:
		var wx := hall.position.x + hall.size.x * (0.14 + i * 0.22)
		var win := Rect2(wx, hall.position.y + hall.size.y * 0.3, hall.size.x * 0.08, hall.size.y * 0.4)
		draw_rect(win, Color(1.0, 0.8, 0.4, 0.75 + 0.2 * sin(t + i)))
		draw_circle(Vector2(win.get_center().x, win.position.y), win.size.x * 0.5, Color(1.0, 0.8, 0.4, 0.75 + 0.2 * sin(t + i)))
	# Kitchen chimney smoke (Brother Anselm's bread)
	var ch := _p(0.39, 0.29)
	draw_rect(Rect2(ch, _p(0.015, 0.05)), Color(0.4, 0.36, 0.34))
	for i in 4:
		var k := fposmod(t * 0.25 + i * 0.25, 1.0)
		draw_circle(ch + Vector2(4 + k * 20.0, -k * 40.0), 3.0 + k * 6.0, Color(0.9, 0.9, 0.95, 0.35 * (1.0 - k)))
	# Bell tower with a swinging bell and a cross
	var tower := Rect2(_p(0.6, 0.2), _p(0.05, 0.27))
	draw_rect(tower, Color(0.58, 0.54, 0.5))
	draw_colored_polygon(PackedVector2Array([tower.position, Vector2(tower.end.x, tower.position.y), Vector2(tower.get_center().x, tower.position.y - h * 0.06)]), Color(0.35, 0.3, 0.32))
	var bell_c := Vector2(tower.get_center().x, tower.position.y + tower.size.y * 0.22)
	draw_rect(Rect2(bell_c - Vector2(tower.size.x * 0.32, tower.size.y * 0.12), Vector2(tower.size.x * 0.64, tower.size.y * 0.22)), Color(0.15, 0.12, 0.12))
	var swing := sin(t * 1.3) * 0.25
	draw_colored_polygon(PackedVector2Array([bell_c + Vector2(-5, -6).rotated(swing), bell_c + Vector2(5, -6).rotated(swing), bell_c + Vector2(8, 6).rotated(swing), bell_c + Vector2(-8, 6).rotated(swing)]), Color(0.85, 0.65, 0.25))
	var top := Vector2(tower.get_center().x, tower.position.y - h * 0.06)
	draw_line(top, top + Vector2(0, -h * 0.05), Color(0.3, 0.28, 0.28), 2.0)
	draw_line(top + Vector2(-5, -h * 0.035), top + Vector2(5, -h * 0.035), Color(0.3, 0.28, 0.28), 2.0)
	draw_arc(top + Vector2(0, -h * 0.035), 3.5, 0, TAU, 12, Color(0.3, 0.28, 0.28), 1.5)

	# Lighthouse with a sweeping beam
	var lh := Rect2(_p(0.88, 0.25), _p(0.035, 0.22))
	draw_colored_polygon(PackedVector2Array([Vector2(lh.position.x + lh.size.x * 0.15, lh.position.y), Vector2(lh.end.x - lh.size.x * 0.15, lh.position.y), lh.end, Vector2(lh.position.x, lh.end.y)]), Color(0.9, 0.9, 0.88))
	for i in 3:
		draw_rect(Rect2(lh.position.x, lh.position.y + lh.size.y * (0.2 + i * 0.3), lh.size.x, lh.size.y * 0.1), Color(0.75, 0.2, 0.18))
	var lamp := Vector2(lh.get_center().x, lh.position.y - 4)
	draw_circle(lamp, 5, Color(1.0, 0.95, 0.6))
	var beam := sin(t * 0.8)
	var bdir := Vector2(beam, -0.15).normalized()
	draw_colored_polygon(PackedVector2Array([lamp, lamp + bdir.rotated(0.08) * w * 0.4, lamp + bdir.rotated(-0.08) * w * 0.4]), Color(1.0, 0.95, 0.6, 0.12 * absf(beam)))

	# Bee garden
	for row in 3:
		draw_line(_p(0.18, 0.49 + row * 0.02), _p(0.26, 0.49 + row * 0.02), Color(0.45, 0.7, 0.3), 3.0)
	for i in 3:
		var hv := _p(0.205 + i * 0.03, 0.465)
		draw_rect(Rect2(hv - Vector2(4, 6), Vector2(8, 6)), Color(0.85, 0.75, 0.45))
		draw_rect(Rect2(hv - Vector2(5, 8), Vector2(10, 2)), Color(0.55, 0.45, 0.3))
	for i in 5:
		var bee := _p(0.23, 0.42) + Vector2(sin(t * 3.0 + i * 1.7) * 18.0, cos(t * 2.3 + i) * 6.0)
		draw_circle(bee, 1.2, Color(1.0, 0.9, 0.2))

	# Landing pad and the Gannet
	var pad := _p(0.085, 0.46)
	draw_line(pad + Vector2(-14, 0), pad + Vector2(14, 0), Color(0.9, 0.85, 0.3), 3.0)
	var bob := sin(t * 2.0) * 1.0
	var g := pad + Vector2(0, -10 + bob)
	draw_colored_polygon(PackedVector2Array([g + Vector2(-16, 2), g + Vector2(14, 2), g + Vector2(18, -3), g + Vector2(6, -7), g + Vector2(-12, -6)]), Color(0.35, 0.4, 0.38))
	draw_line(g + Vector2(-22, -9), g + Vector2(22, -9), Color(0.25, 0.28, 0.27), 2.0)
	draw_circle(g + Vector2(10, -3), 2.0, Color(0.6, 0.9, 1.0))

	# Built modules
	var sc := _scale()
	for i in GameState.slots.size():
		var s: Dictionary = GameState.slots[i]
		if s.has("type"):
			draw_set_transform(_p(SLOT_ANCHORS[i].x, SLOT_ANCHORS[i].y), 0.0, Vector2(sc, sc))
			_draw_module(s["type"], s["level"], Vector2.ZERO)
			draw_set_transform(Vector2.ZERO)

	# Gulls
	for i in 3:
		var gx := fposmod(t * (14.0 + i * 5.0) + i * 140.0, w + 60.0) - 30.0
		var gy := h * (0.25 + i * 0.07) + sin(t * 2.0 + i) * 4.0
		var flap := 3.0 + sin(t * 8.0 + i) * 2.0
		draw_polyline(PackedVector2Array([Vector2(gx - 6, gy - flap), Vector2(gx, gy), Vector2(gx + 6, gy - flap)]), Color(0.95, 0.95, 0.95), 1.5)

	if show_markers:
		_draw_markers()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.2, 0.45, 0.3), false, 2.0)


func _draw_markers() -> void:
	## Numbered site markers you can tap. Empty sites show a "+".
	var font := ThemeDB.fallback_font
	var sc := _scale()
	for i in GameState.slots.size():
		var s: Dictionary = GameState.slots[i]
		var c := _marker_pos(i)
		var r := 13.0 * sc
		var built := s.has("type")
		var sel := i == selected
		var short_staffed := built and GameState.crew_required(i) > int(s.get("crew", 0))
		if sel:
			var pulse := 0.5 + 0.5 * sin(t * 5.0)
			draw_circle(c, r + 6.0 + pulse * 3.0, Color(0.4, 1.0, 0.6, 0.25))
		draw_circle(c, r, Color(0.05, 0.1, 0.08, 0.85))
		draw_arc(c, r, 0, TAU, 24, Color(0.4, 1.0, 0.6) if sel else (Color(0.85, 0.9, 0.85) if built else Color(0.85, 0.9, 0.85, 0.5)), 2.5 if sel else 1.5)
		var txt := str(i + 1) if built else "+"
		var fs := int(15 * sc)
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, c + Vector2(-tw * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if built else Color(0.8, 0.9, 0.85, 0.8))
		if short_staffed:
			draw_circle(c + Vector2(r * 0.8, -r * 0.8), 4.0 * sc, Color(1.0, 0.7, 0.2))
		if sel or not built:
			var label_txt: String = GameState.BUILDINGS[s["type"]]["name"] if built else GameState.SLOT_NAMES[i]
			var nfs := int(12 * sc)
			var nw := font.get_string_size(label_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x
			var np := c + Vector2(-nw * 0.5, r + nfs + 2.0)
			np.x = clampf(np.x, 4.0, size.x - nw - 4.0)
			draw_rect(Rect2(np + Vector2(-4, -nfs), Vector2(nw + 8, nfs + 5)), Color(0, 0, 0, 0.55))
			draw_string(font, np, label_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, Color(1, 1, 1, 0.9) if sel else Color(0.8, 0.85, 0.8, 0.7))


func _draw_module(type: String, level: int, a: Vector2) -> void:
	var k := 1.0 + 0.18 * (level - 1)
	match type:
		"crane":
			var base := a
			var top := a + Vector2(0, -34) * k
			draw_line(base, top, Color(0.95, 0.75, 0.2), 3.0)
			draw_line(top, top + Vector2(26, 6) * k, Color(0.95, 0.75, 0.2), 2.5)
			var hook := top + Vector2(24, 6) * k
			var drop := 10.0 + sin(t * 1.2) * 6.0
			draw_line(hook, hook + Vector2(0, drop), Color(0.2, 0.2, 0.2), 1.0)
			draw_rect(Rect2(hook + Vector2(-3, drop), Vector2(6, 4)), Color(0.5, 0.5, 0.5))
		"ammo":
			var r := Rect2(a + Vector2(-16, -16) * k, Vector2(32, 16) * k)
			draw_rect(r, Color(0.45, 0.42, 0.4))
			draw_rect(Rect2(r.position + Vector2(4, 4) * k, Vector2(8, 5) * k), Color(1.0, 0.6, 0.2, 0.6 + 0.3 * sin(t * 4.0)))
			var chim := r.position + Vector2(r.size.x - 8 * k, 0)
			draw_rect(Rect2(chim + Vector2(0, -12) * k, Vector2(5, 12) * k), Color(0.3, 0.28, 0.28))
			for i in 3:
				var q := fposmod(t * 0.4 + i * 0.33, 1.0)
				draw_circle(chim + Vector2(3 + q * 10.0, -12 * k - q * 26.0), 2.5 + q * 5.0, Color(0.4, 0.4, 0.42, 0.45 * (1.0 - q)))
		"reactor":
			var c := a + Vector2(0, -8) * k
			draw_circle(c, 12 * k, Color(0.25, 0.3, 0.25))
			draw_circle(c, 9 * k, Color(0.4, 1.0, 0.35, 0.5 + 0.3 * sin(t * 2.5)))
			draw_rect(Rect2(a + Vector2(-14, -2) * k, Vector2(28, 4) * k), Color(0.3, 0.3, 0.3))
		"circuits":
			var r2 := Rect2(a + Vector2(-12, -14) * k, Vector2(24, 14) * k)
			draw_rect(r2, Color(0.35, 0.38, 0.45))
			for i in 3:
				var on := fmod(t * 2.0 + i * 0.7, 1.0) < 0.5
				draw_circle(r2.position + Vector2(5 + i * 7, 5) * k, 1.6 * k, Color(0.3, 0.9, 1.0) if on else Color(0.1, 0.2, 0.25))
		"bunks":
			for i in level:
				var hp := a + Vector2(-14 + i * 12, 0) * k
				draw_rect(Rect2(hp + Vector2(-5, -9), Vector2(10, 9)), Color(0.55, 0.42, 0.3))
				draw_colored_polygon(PackedVector2Array([hp + Vector2(-6, -9), hp + Vector2(6, -9), hp + Vector2(0, -15)]), Color(0.35, 0.25, 0.2))
				draw_rect(Rect2(hp + Vector2(-2, -6), Vector2(3, 3)), Color(1.0, 0.85, 0.4))
		"radio":
			var b := a
			var tip := a + Vector2(0, -26) * k
			draw_line(b + Vector2(-5, 0), tip, Color(0.7, 0.7, 0.72), 1.5)
			draw_line(b + Vector2(5, 0), tip, Color(0.7, 0.7, 0.72), 1.5)
			for i in 3:
				var y := lerpf(b.y, tip.y, 0.25 + i * 0.25)
				draw_line(Vector2(b.x - 4 * (1.0 - (i + 1) * 0.25), y), Vector2(b.x + 4 * (1.0 - (i + 1) * 0.25), y), Color(0.7, 0.7, 0.72), 1.0)
			draw_circle(tip, 2.5, Color(1.0, 0.2, 0.15) if fmod(t, 1.0) < 0.5 else Color(0.4, 0.1, 0.1))
			draw_arc(tip, 8.0 + fmod(t * 10.0, 10.0), -PI * 0.8, -PI * 0.2, 8, Color(1.0, 0.4, 0.3, 0.4), 1.0)
