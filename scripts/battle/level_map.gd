extends RefCounted
## The battlefield is a 2D grid where every cell has a kind and a height.
## Ground, rolling hills, craters, raised platforms, stairs, low cover walls
## and tall ruins are all just cells with different heights. The cockpit view
## raycasts through this grid to fake 3D; the minimap draws it from above.

enum { EMPTY, RUIN, METAL, ORGANIC, PLATFORM, RUBBLE }

const STEP := 0.6        ## highest ledge a walker can climb onto
const BORDER_H := 5.0
const MECH_R := 0.55     ## the mech is too wide for one-square gaps

var w := 32
var h := 32
var kinds := PackedByteArray()
var heights := PackedFloat32Array()
var terrain := PackedFloat32Array()   ## natural ground height before structures
var max_height := BORDER_H
var start := Vector2(2.5, 2.5)
var hive_cells: Array[Vector2i] = []
var nest_cells: Array[Vector2i] = []  ## where dormant aliens wait at mission start
var prop_spots: Array[Vector2] = []   ## decorative rubble on the ground
var cache_spots: Array[Vector2] = []  ## salvage caches only the pilot can reach
var mech_cells := PackedByteArray()   ## 1 where the mech can stand
var bunker_interiors: Array[Rect2i] = []
var rng := RandomNumberGenerator.new()
var _reserved := PackedByteArray()    ## cells that buildings must not overwrite
var hard := PackedByteArray()         ## 1 = can't be blasted (bunkers, map edge)
var wall_hp := PackedByteArray()      ## rocket hits left before a wall collapses


var layout := "ruins"

const LAYOUTS := {
	## hills amplitude, craters, platforms
	"ruins": [1.8, 3, 4],
	"town": [1.0, 2, 2],
	"quarry": [3.2, 5, 6],
	"village": [1.6, 2, 2],
	"forest": [2.0, 5, 2],
	"industrial": [0.8, 2, 4],
}


func generate(seed_value: int, hive_count: int, layout_name := "ruins") -> void:
	layout = layout_name if LAYOUTS.has(layout_name) else "ruins"
	var lay: Array = LAYOUTS[layout]
	rng.seed = seed_value
	var n := w * h
	kinds.resize(n)
	kinds.fill(EMPTY)
	heights.resize(n)
	heights.fill(0.0)
	terrain.resize(n)
	terrain.fill(0.0)
	_reserved.resize(n)
	_reserved.fill(0)

	# 1. Rolling hills, in 0.25 terraces so they're always walkable.
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.07
	for y in h:
		for x in w:
			var t := snappedf(clampf(noise.get_noise_2d(x, y) * lay[0], 0.0, 0.75 if layout != "quarry" else 1.5), 0.25)
			terrain[idx(x, y)] = t
			heights[idx(x, y)] = t

	# 2. Flat landing zone.
	for yy in range(1, 7):
		for xx in range(1, 7):
			_flatten(xx, yy, 0.0)
			_reserve(xx, yy)
	start = Vector2(3.5, 3.5)

	# 3. Craters: a ring at -0.5 and a floor at -1.0, so you can walk in and out.
	for i in int(lay[1]):
		var r := rng.randf_range(2.0, 3.0)
		var c := Vector2(rng.randf_range(7, w - 6), rng.randf_range(7, h - 6))
		for yy in range(int(c.y - r - 1), int(c.y + r + 2)):
			for xx in range(int(c.x - r - 1), int(c.x + r + 2)):
				if not _inner(xx, yy) or _reserved[idx(xx, yy)]:
					continue
				var d := Vector2(xx + 0.5, yy + 0.5).distance_to(c)
				if d < r + 1.0:
					_flatten(xx, yy, 0.0)
				if d < r:
					heights[idx(xx, yy)] = -1.0 if d < r - 1.0 else -0.5
					_reserve(xx, yy)

	# 4. Raised platforms with a staircase down one side.
	for i in int(lay[2]):
		var pw := rng.randi_range(3, 5)
		var ph := rng.randi_range(3, 4)
		var px := rng.randi_range(2, w - 3 - pw)
		var py := rng.randi_range(2, h - 3 - ph)
		if _rect_reserved(px - 1, py - 1, pw + 2, ph + 2):
			continue
		var top := 0.0
		for yy in ph:
			for xx in pw:
				top = maxf(top, terrain[idx(px + xx, py + yy)])
		var plat_h := snappedf(top + rng.randf_range(1.2, 1.8), 0.5)
		for yy in ph:
			for xx in pw:
				_set_cell(px + xx, py + yy, PLATFORM, plat_h)
				_reserve(px + xx, py + yy)
		var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		var dir: Vector2i = dirs[rng.randi_range(0, 3)]
		var cell := Vector2i(px + pw / 2, py + ph / 2)
		while cell.x >= px and cell.x < px + pw and cell.y >= py and cell.y < py + ph:
			cell += dir
		var cur := plat_h
		while _inner(cell.x, cell.y):
			cur -= 0.5
			if cur <= terrain[idx(cell.x, cell.y)] + 0.01:
				break
			_set_cell(cell.x, cell.y, PLATFORM, cur)
			_reserve(cell.x, cell.y)
			cell += dir

	# 4b. Bunkers: hollow buildings with a one-square door. Too narrow for
	# the mech, so only the pilot can get inside on foot.
	bunker_interiors.clear()
	for i in 25:
		if bunker_interiors.size() >= 3:
			break
		var bw := rng.randi_range(4, 5)
		var bh := rng.randi_range(4, 5)
		var bx := rng.randi_range(3, w - 4 - bw)
		var by := rng.randi_range(3, h - 4 - bh)
		if _rect_reserved(bx - 2, by - 2, bw + 4, bh + 4):
			continue
		var floor_h := 9.0
		for yy in range(-2, bh + 2):
			for xx in range(-2, bw + 2):
				floor_h = minf(floor_h, terrain[idx(bx + xx, by + yy)])
		# Flatten the bunker and a ring around it so the door is always walkable.
		for yy in range(-2, bh + 2):
			for xx in range(-2, bw + 2):
				_flatten(bx + xx, by + yy, floor_h)
				_reserve(bx + xx, by + yy)
		var wall_kind := METAL if i % 2 == 0 else RUIN
		for yy in bh:
			for xx in bw:
				if xx == 0 or yy == 0 or xx == bw - 1 or yy == bh - 1:
					_set_cell(bx + xx, by + yy, wall_kind, floor_h + 2.6)
		var door: Vector2i
		match rng.randi_range(0, 3):
			0: door = Vector2i(bx + bw / 2, by)
			1: door = Vector2i(bx + bw / 2, by + bh - 1)
			2: door = Vector2i(bx, by + bh / 2)
			_: door = Vector2i(bx + bw - 1, by + bh / 2)
		_set_cell(door.x, door.y, EMPTY, floor_h)
		bunker_interiors.append(Rect2i(bx + 1, by + 1, bw - 2, bh - 2))

	# 5–6. Buildings, walls and cover, in the zone's layout style.
	match layout:
		"town": _layout_town()
		"quarry": _layout_scatter(10, 1, 3, 2.0, 3.2, 6)
		"village": _layout_village()
		"forest": _layout_scatter(12, 1, 3, 2.2, 3.4, 6)
		"industrial": _layout_industrial()
		_: _layout_ruins()

	# 7. Map border.
	for x in w:
		_set_cell(x, 0, METAL, BORDER_H)
		_set_cell(x, h - 1, METAL, BORDER_H)
	for y in h:
		_set_cell(0, y, METAL, BORDER_H)
		_set_cell(w - 1, y, METAL, BORDER_H)

	# 8. Every walkable cell must connect back to the landing zone.
	var sc := Vector2i(3, 3)
	var dist := distance_field(sc, true)
	_seal_unreachable(dist, RUIN, 3.0)

	# 9. Hives (always somewhere the mech can reach), with alien growth.
	compute_mech_reach(start)
	_place_hives(dist, hive_count)
	for hc in hive_cells:
		for yy in range(hc.y - 2, hc.y + 3):
			for xx in range(hc.x - 2, hc.x + 3):
				if not _inner(xx, yy) or Vector2i(xx, yy).distance_to(hc) < 1.5:
					continue
				var k := kinds[idx(xx, yy)]
				if k == RUIN or k == METAL:
					kinds[idx(xx, yy)] = ORGANIC
				elif k == EMPTY and rng.randf() < 0.12:
					_set_cell(xx, yy, ORGANIC, terrain[idx(xx, yy)] + 2.0)
		_set_cell(hc.x, hc.y, EMPTY, terrain[idx(hc.x, hc.y)])
	_ensure_mech_access(sc)
	dist = distance_field(sc, true)
	_seal_unreachable(dist, ORGANIC, 2.0)
	compute_mech_reach(start)
	_place_caches(dist)

	# 10. Alien nests and rubble.
	nest_cells.clear()
	prop_spots.clear()
	for y in h:
		for x in w:
			var i := idx(x, y)
			if dist[i] < 0 or kinds[i] == RUIN or kinds[i] == METAL or kinds[i] == ORGANIC:
				continue
			for hc in hive_cells:
				if Vector2i(x, y).distance_to(hc) <= 4.0 and Vector2i(x, y) != hc:
					nest_cells.append(Vector2i(x, y))
					break
			if rng.randf() < 0.09 and dist[i] > 2 and kinds[i] == EMPTY:
				prop_spots.append(Vector2(x + rng.randf_range(0.2, 0.8), y + rng.randf_range(0.2, 0.8)))

	max_height = 0.0
	for v in heights:
		max_height = maxf(max_height, v)

	# Destructible terrain: how many rocket hits each wall can take.
	hard.resize(w * h)
	hard.fill(0)
	wall_hp.resize(w * h)
	wall_hp.fill(0)
	for y in h:
		for x in w:
			var i := idx(x, y)
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				hard[i] = 1
			match kinds[i]:
				RUIN: wall_hp[i] = 1 if heights[i] - terrain[i] < 1.5 else 2
				METAL: wall_hp[i] = 3
				ORGANIC: wall_hp[i] = 1
	for r in bunker_interiors:
		# Pre-war blast shelters: rockets won't scratch them.
		for yy in range(r.position.y - 1, r.end.y + 1):
			for xx in range(r.position.x - 1, r.end.x + 1):
				if in_bounds(xx, yy) and is_solid(xx, yy):
					hard[idx(xx, yy)] = 1


func _layout_ruins() -> void:
	## Ruined buildings of varied height and low cover walls.
	for i in 30:
		var bw := rng.randi_range(1, 4)
		var bh := rng.randi_range(1, 3)
		if rng.randf() < 0.5:
			var tmp := bw
			bw = bh
			bh = tmp
		var bx := rng.randi_range(1, w - 1 - bw)
		var by := rng.randi_range(1, h - 1 - bh)
		var kind := RUIN if rng.randf() < 0.7 else METAL
		var base := 0.0
		for yy in bh:
			for xx in bw:
				base = maxf(base, terrain[idx(bx + xx, by + yy)])
		var tall := snappedf(base + rng.randf_range(2.4, 4.2), 0.2)
		var hollow := bw >= 3 and bh >= 3 and rng.randf() < 0.5
		for yy in bh:
			for xx in bw:
				if hollow and xx > 0 and yy > 0 and xx < bw - 1 and yy < bh - 1:
					continue
				if not _reserved[idx(bx + xx, by + yy)]:
					# Ragged roofs: each cell a little different.
					_set_cell(bx + xx, by + yy, kind, tall - rng.randi_range(0, 2) * 0.4)

	for i in 10:
		var length := rng.randi_range(2, 5)
		var horizontal := rng.randf() < 0.5
		var x0 := rng.randi_range(2, w - 3)
		var y0 := rng.randi_range(2, h - 3)
		for k in length:
			var xx := x0 + (k if horizontal else 0)
			var yy := y0 + (0 if horizontal else k)
			if _inner(xx, yy) and not _reserved[idx(xx, yy)] and kinds[idx(xx, yy)] == EMPTY:
				_set_cell(xx, yy, RUIN, terrain[idx(xx, yy)] + 0.95)



func _building(bx: int, by: int, bw: int, bh: int, kind: int, tall: float, ragged: bool, hollow: bool) -> void:
	var base := 0.0
	for yy in bh:
		for xx in bw:
			if in_bounds(bx + xx, by + yy):
				base = maxf(base, terrain[idx(bx + xx, by + yy)])
	for yy in bh:
		for xx in bw:
			var x := bx + xx
			var y := by + yy
			if not _inner(x, y) or _reserved[idx(x, y)]:
				continue
			if hollow and xx > 0 and yy > 0 and xx < bw - 1 and yy < bh - 1:
				continue
			_set_cell(x, y, kind, base + tall - (rng.randi_range(0, 2) * 0.4 if ragged else 0.0))


func _low_wall(x0: int, y0: int, length: int, horizontal: bool, kind: int, height: float) -> void:
	for k in length:
		var xx := x0 + (k if horizontal else 0)
		var yy := y0 + (0 if horizontal else k)
		if _inner(xx, yy) and not _reserved[idx(xx, yy)] and kinds[idx(xx, yy)] == EMPTY:
			_set_cell(xx, yy, kind, terrain[idx(xx, yy)] + height)


func _layout_scatter(count: int, min_size: int, max_size: int, hmin: float, hmax: float, walls: int) -> void:
	## Sparse sheds and ruins in open ground (quarry, forest).
	for i in count:
		var bw := rng.randi_range(min_size, max_size)
		var bh := rng.randi_range(min_size, max_size)
		_building(rng.randi_range(2, w - 2 - bw), rng.randi_range(2, h - 2 - bh), bw, bh, RUIN if rng.randf() < 0.75 else METAL, rng.randf_range(hmin, hmax), true, false)
	for i in walls:
		_low_wall(rng.randi_range(2, w - 3), rng.randi_range(2, h - 3), rng.randi_range(2, 5), rng.randf() < 0.5, RUIN, 0.95)


func _layout_town() -> void:
	## City blocks between two-square streets: tall buildings, narrow alleys.
	var by := 2
	while by < h - 4:
		var bx := 2
		while bx < w - 4:
			var bw := mini(4, w - 2 - bx)
			var bh := mini(4, h - 2 - by)
			match rng.randi_range(0, 3):
				0:
					_building(bx, by, bw, bh, RUIN, rng.randf_range(3.0, 4.6), true, rng.randf() < 0.5)
				1:
					# Two buildings with a one-square alley between them.
					_building(bx, by, bw, 1 + bh / 2 - 1, RUIN, rng.randf_range(2.4, 4.0), true, false)
					_building(bx, by + bh / 2 + 1, bw, bh - bh / 2 - 1, METAL if rng.randf() < 0.3 else RUIN, rng.randf_range(2.4, 4.0), true, false)
				2:
					_building(bx, by, 2, bh, RUIN, rng.randf_range(2.6, 4.2), true, false)
					_building(bx + 3, by, 1, bh, RUIN, rng.randf_range(2.4, 3.6), true, false)
				_:
					pass  # a small square: open space
			bx += 6
		by += 6
	for i in 5:
		_low_wall(rng.randi_range(2, w - 3), rng.randi_range(2, h - 3), rng.randi_range(2, 3), rng.randf() < 0.5, RUIN, 0.95)


func _layout_village() -> void:
	## Cottages with pitched roofs, fences and open fields.
	for i in 12:
		var bw := rng.randi_range(2, 3)
		var bh := rng.randi_range(3, 4)
		if rng.randf() < 0.5:
			var tmp := bw
			bw = bh
			bh = tmp
		var bx := rng.randi_range(2, w - 2 - bw)
		var by := rng.randi_range(2, h - 2 - bh)
		_building(bx, by, bw, bh, RUIN, 2.2, false, false)
		# Pitched roof: the middle line of the cottage stands higher.
		if bw <= bh:
			for yy in bh:
				var c := Vector2i(bx + bw / 2, by + yy)
				if _inner(c.x, c.y) and kinds[idx(c.x, c.y)] == RUIN:
					heights[idx(c.x, c.y)] += 0.7
		else:
			for xx in bw:
				var c2 := Vector2i(bx + xx, by + bh / 2)
				if _inner(c2.x, c2.y) and kinds[idx(c2.x, c2.y)] == RUIN:
					heights[idx(c2.x, c2.y)] += 0.7
	for i in 14:
		_low_wall(rng.randi_range(2, w - 3), rng.randi_range(2, h - 3), rng.randi_range(3, 6), rng.randf() < 0.5, RUIN, 0.75)


func _layout_industrial() -> void:
	## Warehouses, storage tanks, shipping containers and pipe runs.
	for i in 7:
		var bw := rng.randi_range(3, 5)
		var bh := rng.randi_range(4, 6)
		_building(rng.randi_range(2, w - 2 - bw), rng.randi_range(2, h - 2 - bh), bw, bh, METAL, rng.randf_range(3.0, 4.6), false, rng.randf() < 0.3)
	for i in 3:
		var c := Vector2i(rng.randi_range(4, w - 5), rng.randi_range(4, h - 5))
		for yy in range(-1, 2):
			for xx in range(-1, 2):
				if absi(xx) + absi(yy) <= 1:
					_building(c.x + xx, c.y + yy, 1, 1, METAL, 3.6, false, false)
	for i in 8:
		var horizontal := rng.randf() < 0.5
		var x0 := rng.randi_range(2, w - 5)
		var y0 := rng.randi_range(2, h - 5)
		_building(x0, y0, 3 if horizontal else 1, 1 if horizontal else 3, METAL, rng.randf_range(1.2, 1.6), false, false)
	for i in 6:
		_low_wall(rng.randi_range(2, w - 3), rng.randi_range(2, h - 3), rng.randi_range(5, 9), rng.randf() < 0.5, METAL, 0.85)


func _place_hives(dist: PackedInt32Array, count: int) -> void:
	hive_cells.clear()
	var candidates: Array[Vector2i] = []
	for y in range(2, h - 2):
		for x in range(2, w - 2):
			var i := idx(x, y)
			if kinds[i] == EMPTY and dist[i] >= 14 and heights[i] >= 0.0 and heights[i] <= 0.75 and mech_cells[i]:
				candidates.append(Vector2i(x, y))
	_shuffle(candidates)
	var min_spacing := 8.0
	while hive_cells.size() < count and min_spacing >= 2.0:
		for c in candidates:
			if hive_cells.size() >= count:
				break
			var ok := true
			for hc in hive_cells:
				if c.distance_to(hc) < min_spacing:
					ok = false
					break
			if ok:
				hive_cells.append(c)
		min_spacing -= 2.0
	if hive_cells.is_empty() and count > 0:
		hive_cells.append(Vector2i(w - 4, h - 4))
		_set_cell(w - 4, h - 4, EMPTY, terrain[idx(w - 4, h - 4)])


func compute_mech_reach(from: Vector2) -> void:
	## Marks every cell the mech can stand in, by flood-filling a half-square
	## grid of test points with the mech's full width.
	var pw := w * 2
	var phh := h * 2
	var ok := PackedByteArray()
	ok.resize(pw * phh)
	var ph := PackedFloat32Array()
	ph.resize(pw * phh)
	for j in phh:
		for i in pw:
			var p := Vector2((i + 0.5) * 0.5, (j + 0.5) * 0.5)
			var fh := height_at(p)
			ph[j * pw + i] = fh
			ok[j * pw + i] = 0 if blocked(p, MECH_R, fh) else 1
	mech_cells.resize(w * h)
	mech_cells.fill(0)
	var si := int(from.y * 2.0) * pw + int(from.x * 2.0)
	if ok[si] == 0:
		return
	var seen := PackedByteArray()
	seen.resize(pw * phh)
	var queue := PackedInt32Array([si])
	seen[si] = 1
	var head := 0
	while head < queue.size():
		var pi := queue[head]
		head += 1
		var px := pi % pw
		var py := pi / pw
		mech_cells[idx(px / 2, py / 2)] = 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = px + d.x
			var ny: int = py + d.y
			if nx < 0 or ny < 0 or nx >= pw or ny >= phh:
				continue
			var ni := ny * pw + nx
			if seen[ni] or not ok[ni] or absf(ph[ni] - ph[pi]) > STEP:
				continue
			seen[ni] = 1
			queue.append(ni)


func _place_caches(dist: PackedInt32Array) -> void:
	## Salvage caches go where the pilot can walk but the mech can't fit:
	## one inside each bunker, plus a few in other tight spots.
	cache_spots.clear()
	for r in bunker_interiors:
		var c := r.position + r.size / 2
		if dist[idx(c.x, c.y)] >= 0 and not mech_cells[idx(c.x, c.y)]:
			cache_spots.append(Vector2(c) + Vector2(0.5, 0.5))
	var extra: Array[Vector2i] = []
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var i := idx(x, y)
			if kinds[i] == EMPTY and dist[i] >= 6 and not mech_cells[i]:
				extra.append(Vector2i(x, y))
	_shuffle(extra)
	for c in extra:
		if cache_spots.size() >= 4:
			break
		var p := Vector2(c) + Vector2(0.5, 0.5)
		var far_enough := true
		for q in cache_spots:
			if q.distance_to(p) < 6.0:
				far_enough = false
				break
		if far_enough:
			cache_spots.append(p)


func _seal_unreachable(dist: PackedInt32Array, kind: int, extra: float) -> void:
	for i in w * h:
		if dist[i] < 0 and (kinds[i] == EMPTY or kinds[i] == PLATFORM):
			kinds[i] = kind
			heights[i] = maxf(terrain[i], 0.0) + extra


func _ensure_mech_access(sc: Vector2i) -> void:
	## Opens wide corridors until every hive and most of the open ground can
	## be reached by the mech. One-square nooks are left alone on purpose.
	for attempt in 12:
		compute_mech_reach(start)
		var dist := distance_field(sc, true)
		var target := Vector2i(-1, -1)
		for hc in hive_cells:
			if dist[idx(hc.x, hc.y)] < 0 or not mech_cells[idx(hc.x, hc.y)]:
				target = hc
				break
		if target.x < 0:
			var open := 0
			var reach := 0
			var cands: Array[Vector2i] = []
			for y in range(1, h - 1):
				for x in range(1, w - 1):
					var i := idx(x, y)
					if dist[i] < 0:
						continue
					open += 1
					if mech_cells[i]:
						reach += 1
					elif not blocked(Vector2(x + 0.5, y + 0.5), MECH_R, heights[i]):
						# Roomy enough for the mech, just cut off.
						cands.append(Vector2i(x, y))
			if reach >= open * 0.85 or cands.is_empty():
				return
			target = cands[rng.randi_range(0, cands.size() - 1)]
		_carve_to_open(target, sc)


func _carve_to_open(from: Vector2i, toward: Vector2i) -> void:
	## Digs a corridor at natural ground height toward the landing zone.
	var p := from
	for i in 80:
		var dx := toward.x - p.x
		var dy := toward.y - p.y
		if dx == 0 and dy == 0:
			break
		var step := Vector2i(signi(dx), 0) if abs(dx) > abs(dy) else Vector2i(0, signi(dy))
		p += step
		if not _inner(p.x, p.y):
			break
		# Three squares wide so the mech fits through, even at corners.
		var side := Vector2i(step.y, step.x)
		for q in [p - side, p, p + side]:
			if _inner(q.x, q.y) and (kinds[idx(q.x, q.y)] != EMPTY or heights[idx(q.x, q.y)] != terrain[idx(q.x, q.y)]):
				_set_cell(q.x, q.y, EMPTY, terrain[idx(q.x, q.y)])


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _flatten(x: int, y: int, v: float) -> void:
	terrain[idx(x, y)] = v
	heights[idx(x, y)] = v
	kinds[idx(x, y)] = EMPTY


func _reserve(x: int, y: int) -> void:
	_reserved[idx(x, y)] = 1


func _rect_reserved(x: int, y: int, rw: int, rh: int) -> bool:
	for yy in range(y, y + rh):
		for xx in range(x, x + rw):
			if in_bounds(xx, yy) and _reserved[idx(xx, yy)]:
				return true
	return false


func _inner(x: int, y: int) -> bool:
	return x >= 1 and y >= 1 and x < w - 1 and y < h - 1


func _set_cell(x: int, y: int, kind: int, height: float) -> void:
	if in_bounds(x, y):
		kinds[idx(x, y)] = kind
		heights[idx(x, y)] = height


# --- Queries --------------------------------------------------------------

func idx(x: int, y: int) -> int:
	return y * w + x


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


func kind_of(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return METAL
	return kinds[idx(x, y)]


func cell_h(x: int, y: int) -> float:
	if not in_bounds(x, y):
		return BORDER_H
	return heights[idx(x, y)]


func height_at(p: Vector2) -> float:
	return cell_h(int(floor(p.x)), int(floor(p.y)))


func blast(center: Vector2, radius: float) -> Dictionary:
	## A rocket explosion. Damages breakable walls in range and turns the
	## ones that give way into rubble. Returns {"destroyed": [...], "hard_hit": bool}.
	var destroyed: Array[Vector2i] = []
	var hard_hit := false
	for yy in range(int(floor(center.y - radius)), int(floor(center.y + radius)) + 1):
		for xx in range(int(floor(center.x - radius)), int(floor(center.x + radius)) + 1):
			if not in_bounds(xx, yy) or not is_solid(xx, yy):
				continue
			var nearest := Vector2(clampf(center.x, xx, xx + 1), clampf(center.y, yy, yy + 1))
			if nearest.distance_to(center) > radius:
				continue
			var i := idx(xx, yy)
			if hard[i]:
				hard_hit = true
				continue
			if wall_hp[i] > 1:
				wall_hp[i] -= 1
				continue
			wall_hp[i] = 0
			kinds[i] = RUBBLE
			heights[i] = maxf(terrain[i], 0.0) + 0.45
			destroyed.append(Vector2i(xx, yy))
	return {"destroyed": destroyed, "hard_hit": hard_hit}


func is_solid(x: int, y: int) -> bool:
	## True for building-type cells (used for minimap colours and textures).
	var k := kind_of(x, y)
	return k == RUIN or k == METAL or k == ORGANIC


func blocked(p: Vector2, r: float, floor_h: float, step := STEP) -> bool:
	## A walker standing at floor_h can't move to p if any part of its
	## footprint is too high to step onto.
	var limit := floor_h + step
	if height_at(p + Vector2(-r, -r)) > limit or height_at(p + Vector2(r, -r)) > limit \
		or height_at(p + Vector2(-r, r)) > limit or height_at(p + Vector2(r, r)) > limit:
		return true
	if r > 0.45:
		# Wide bodies: also test edge midpoints and centre so a one-square
		# pillar can't slip between the corners.
		return height_at(p) > limit or height_at(p + Vector2(r, 0)) > limit \
			or height_at(p + Vector2(-r, 0)) > limit or height_at(p + Vector2(0, r)) > limit \
			or height_at(p + Vector2(0, -r)) > limit
	return false


func line_of_sight(a: Vector2, za: float, b: Vector2, zb: float) -> bool:
	## True if the straight 3D line between two points clears the terrain.
	var length := a.distance_to(b)
	var steps := int(length / 0.25) + 1
	for i in range(1, steps):
		var t := float(i) / steps
		if height_at(a.lerp(b, t)) > lerpf(za, zb, t):
			return false
	return true


func open_distance(o: Vector2, dir: Vector2, max_d: float) -> float:
	## How far one can walk from o along dir before hitting a ledge.
	var floor_h := height_at(o)
	var d := 0.0
	while d < max_d:
		d += 0.25
		var hh := height_at(o + dir * d)
		if hh > floor_h + STEP:
			break
		floor_h = hh
	return d


func distance_field(from: Vector2i, both_ways: bool) -> PackedInt32Array:
	## BFS step distance from a cell (-1 = unreachable).
	## both_ways: only use edges walkable in both directions (map building).
	## otherwise: distance for a walker travelling *toward* `from`, so they
	## may drop off ledges but must climb at most STEP (alien pathfinding).
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(-1)
	if not in_bounds(from.x, from.y):
		return dist
	var queue: Array[Vector2i] = [from]
	dist[idx(from.x, from.y)] = 0
	var head := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var ci := idx(c.x, c.y)
		var hc := heights[ci]
		for dv in dirs:
			var nn: Vector2i = c + dv
			if not in_bounds(nn.x, nn.y):
				continue
			var ni := idx(nn.x, nn.y)
			if dist[ni] >= 0:
				continue
			var hn := heights[ni]
			# The walker moves from nn to c.
			var ok := hc - hn <= STEP
			if both_ways:
				ok = absf(hc - hn) <= STEP
			if ok:
				dist[ni] = dist[ci] + 1
				queue.append(nn)
	return dist
