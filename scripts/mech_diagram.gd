extends Control
## Mech silhouette coloured by part health. Used as a widget in the hangar,
## and its static draw function is reused by the battle HUD.

const PART_RECTS := {
	"legs": [Rect2(-24, 12, 15, 44), Rect2(9, 12, 15, 44)],
	"torso": [Rect2(-21, -34, 42, 48)],
	"left_arm": [Rect2(-40, -30, 15, 38), Rect2(-36, 8, 7, 14)],
	"right_arm": [Rect2(25, -30, 15, 38), Rect2(29, 8, 7, 14)],
}


static func part_color(ratio: float) -> Color:
	if ratio <= 0.0:
		return Color(0.22, 0.22, 0.24)
	if ratio > 0.6:
		return Color(0.25, 0.85, 0.4)
	if ratio > 0.3:
		return Color(0.95, 0.8, 0.2)
	return Color(0.95, 0.25, 0.2)


static func draw_mech(ci: CanvasItem, center: Vector2, k: float, ratios: Dictionary, blink := false) -> void:
	for part in PART_RECTS:
		var r: float = ratios.get(part, 1.0)
		var col := part_color(r)
		if blink and r > 0.0 and r <= 0.3:
			col = col.lerp(Color.WHITE, 0.5)
		for rect: Rect2 in PART_RECTS[part]:
			var rr := Rect2(center + rect.position * k, rect.size * k)
			ci.draw_rect(rr, col.darkened(0.55))
			ci.draw_rect(rr.grow(-2.0 * k), col)
			if r <= 0.0:
				ci.draw_line(rr.position, rr.end, Color(0.9, 0.2, 0.15), 2.0)
				ci.draw_line(Vector2(rr.end.x, rr.position.y), Vector2(rr.position.x, rr.end.y), Color(0.9, 0.2, 0.15), 2.0)
	# Cockpit window
	ci.draw_rect(Rect2(center + Vector2(-10, -26) * k, Vector2(20, 9) * k), Color(0.4, 0.8, 1.0, 0.9))


func _draw() -> void:
	var ratios := {}
	for p in GameState.PARTS:
		ratios[p] = GameState.hp_ratio(p)
	var s := minf(size.x / 100.0, size.y / 120.0)
	draw_mech(self, size * 0.5 + Vector2(0, -6 * s), s, ratios)
