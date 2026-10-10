extends RefCounted
## The battlefield is a 2D grid where every cell has a kind and a height.
## Ground, rolling hills, craters, raised platforms, stairs, low cover walls
## and tall ruins are all just cells with different heights. The cockpit view
## raycasts through this grid to fake 3D; the minimap draws it from above.

enum { EMPTY, RUIN, METAL, ORGANIC, PLATFORM }

const STEP := 0.6        ## highest ledge a walker can climb onto
const BORDER_H := 5.0

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
var rng := RandomNumberGenerator.new()
var _reserved := PackedByteArray()    ## cells that buildings must not overwrite


func generate(seed_value: int, hive_count: int) -> void:
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
			var t := snappedf(clampf(noise.get_noise_2d(x, y) * 1.8, 0.0, 0.75), 0.25)
			terrain[idx(x, y)] = t
			heights[idx(x, y)] = t

	# 2. Flat landing zone.
	for yy in range(1, 7):
		for xx in range(1, 7):
			_flatten(xx, yy, 0.0)
			_reserve(xx, yy)
	start = Vector2(3.5, 3.5)

	# 3. Craters: a ring at -0.5 and a floor at -1.0, so you can walk in and out.
	for i in 3:
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
	for i in 4:
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

	# 5. Tall ruined buildings of varied height.
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

	# 6. Low cover walls you can see and shoot over, but not walk through.
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

	# 9. Hives, with alien growth around them.
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
	dist = distance_field(sc, true)
	for hc in hive_cells:
		if dist[idx(hc.x, hc.y)] < 0:
			_carve_to_open(hc, sc)
	dist = distance_field(sc, true)
	_seal_unreachable(dist, ORGANIC, 2.0)

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


func _place_hives(dist: PackedInt32Array, count: int) -> void:
	hive_cells.clear()
	var candidates: Array[Vector2i] = []
	for y in range(2, h - 2):
		for x in range(2, w - 2):
			var i := idx(x, y)
			if kinds[i] == EMPTY and dist[i] >= 14 and heights[i] >= 0.0 and heights[i] <= 0.75:
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
	if hive_cells.is_empty():
		hive_cells.append(Vector2i(w - 4, h - 4))
		_set_cell(w - 4, h - 4, EMPTY, terrain[idx(w - 4, h - 4)])


func _seal_unreachable(dist: PackedInt32Array, kind: int, extra: float) -> void:
	for i in w * h:
		if dist[i] < 0 and (kinds[i] == EMPTY or kinds[i] == PLATFORM):
			kinds[i] = kind
			heights[i] = maxf(terrain[i], 0.0) + extra


func _carve_to_open(from: Vector2i, toward: Vector2i) -> void:
	## Digs a corridor at natural ground height toward the landing zone.
	var p := from
	for i in 80:
		var dx := toward.x - p.x
		var dy := toward.y - p.y
		if dx == 0 and dy == 0:
			break
		p += Vector2i(signi(dx), 0) if abs(dx) > abs(dy) else Vector2i(0, signi(dy))
		if not _inner(p.x, p.y):
			break
		_set_cell(p.x, p.y, EMPTY, terrain[idx(p.x, p.y)])


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


func is_solid(x: int, y: int) -> bool:
	## True for building-type cells (used for minimap colours and textures).
	var k := kind_of(x, y)
	return k == RUIN or k == METAL or k == ORGANIC


func blocked(p: Vector2, r: float, floor_h: float) -> bool:
	## A walker standing at floor_h can't move to p if any corner is too high.
	var limit := floor_h + STEP
	return height_at(p + Vector2(-r, -r)) > limit or height_at(p + Vector2(r, -r)) > limit \
		or height_at(p + Vector2(-r, r)) > limit or height_at(p + Vector2(r, r)) > limit


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
