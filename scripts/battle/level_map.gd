extends RefCounted
## The battlefield is a flat 2D grid. The cockpit view raycasts through it to
## fake 3D, and the minimap draws it directly.

enum { EMPTY, RUIN, METAL, ORGANIC }

var w := 32
var h := 32
var cells := PackedByteArray()
var start := Vector2(2.5, 2.5)
var start_angle := 0.0
var hive_cells: Array[Vector2i] = []
var nest_cells: Array[Vector2i] = []  ## where dormant aliens wait at mission start
var prop_spots: Array[Vector2] = []    ## decorative rubble on the ground
var rng := RandomNumberGenerator.new()


func generate(seed_value: int, hive_count: int) -> void:
	rng.seed = seed_value
	cells.resize(w * h)
	cells.fill(EMPTY)
	for x in w:
		_put_cell(x, 0, METAL)
		_put_cell(x, h - 1, METAL)
	for y in h:
		_put_cell(0, y, METAL)
		_put_cell(w - 1, y, METAL)

	# Ruined buildings and wrecked structures.
	for i in 34:
		var bw := rng.randi_range(1, 4)
		var bh := rng.randi_range(1, 3)
		if rng.randf() < 0.5:
			var tmp := bw
			bw = bh
			bh = tmp
		var bx := rng.randi_range(1, w - 1 - bw)
		var by := rng.randi_range(1, h - 1 - bh)
		var kind := RUIN if rng.randf() < 0.7 else METAL
		var hollow := bw >= 3 and bh >= 3 and rng.randf() < 0.5
		for yy in bh:
			for xx in bw:
				if hollow and xx > 0 and yy > 0 and xx < bw - 1 and yy < bh - 1:
					continue
				_put_cell(bx + xx, by + yy, kind)

	# Clear the landing zone.
	var sc := Vector2i(2, 2)
	for yy in range(1, 6):
		for xx in range(1, 6):
			_put_cell(xx, yy, EMPTY)
	start = Vector2(sc.x + 0.5, sc.y + 0.5)
	start_angle = PI * 0.25

	# Seal off unreachable pockets so every open cell connects to the start.
	var dist := distance_field(sc)
	for i in w * h:
		if cells[i] == EMPTY and dist[i] < 0:
			cells[i] = RUIN

	_place_hives(dist, hive_count)

	# Organic growth around the hives.
	for hc in hive_cells:
		for yy in range(hc.y - 2, hc.y + 3):
			for xx in range(hc.x - 2, hc.x + 3):
				if in_bounds(xx, yy) and xx > 0 and yy > 0 and xx < w - 1 and yy < h - 1:
					if cell(xx, yy) != EMPTY or rng.randf() < 0.12:
						if Vector2i(xx, yy).distance_to(hc) >= 1.5:
							_put_cell(xx, yy, ORGANIC)
		_put_cell(hc.x, hc.y, EMPTY)
	# Make sure organic walls didn't cut anything off.
	dist = distance_field(sc)
	for i in w * h:
		if cells[i] == EMPTY and dist[i] < 0:
			cells[i] = ORGANIC
	for hc in hive_cells:
		if dist[idx(hc.x, hc.y)] < 0:
			_carve_to_open(hc)

	# Nest spots and rubble.
	dist = distance_field(sc)
	nest_cells.clear()
	prop_spots.clear()
	for y in h:
		for x in w:
			if cells[idx(x, y)] != EMPTY or dist[idx(x, y)] < 0:
				continue
			var near_hive := false
			for hc in hive_cells:
				if Vector2i(x, y).distance_to(hc) <= 4.0 and Vector2i(x, y) != hc:
					near_hive = true
			if near_hive:
				nest_cells.append(Vector2i(x, y))
			if rng.randf() < 0.09 and dist[idx(x, y)] > 2:
				prop_spots.append(Vector2(x + rng.randf_range(0.2, 0.8), y + rng.randf_range(0.2, 0.8)))


func _place_hives(dist: PackedInt32Array, count: int) -> void:
	hive_cells.clear()
	var candidates: Array[Vector2i] = []
	for y in range(2, h - 2):
		for x in range(2, w - 2):
			var d := dist[idx(x, y)]
			if cells[idx(x, y)] == EMPTY and d >= 14:
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
		_put_cell(w - 4, h - 4, EMPTY)


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _carve_to_open(from: Vector2i) -> void:
	## Digs a straight corridor toward the map centre until it meets open ground.
	var p := from
	var target := Vector2i(w / 2, h / 2)
	for i in 64:
		var step := Vector2i(signi(target.x - p.x), 0) if abs(target.x - p.x) > abs(target.y - p.y) else Vector2i(0, signi(target.y - p.y))
		if step == Vector2i.ZERO:
			break
		p += step
		if p.x <= 0 or p.y <= 0 or p.x >= w - 1 or p.y >= h - 1:
			break
		_put_cell(p.x, p.y, EMPTY)


# --- Queries --------------------------------------------------------------

func idx(x: int, y: int) -> int:
	return y * w + x


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


func cell(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return METAL
	return cells[idx(x, y)]


func _put_cell(x: int, y: int, v: int) -> void:
	if in_bounds(x, y):
		cells[idx(x, y)] = v


func is_wall_at(p: Vector2) -> bool:
	return cell(int(floor(p.x)), int(floor(p.y))) != EMPTY


func blocked(p: Vector2, r: float) -> bool:
	return is_wall_at(p + Vector2(-r, -r)) or is_wall_at(p + Vector2(r, -r)) \
		or is_wall_at(p + Vector2(-r, r)) or is_wall_at(p + Vector2(r, r))


func line_of_sight(a: Vector2, b: Vector2) -> bool:
	var length := a.distance_to(b)
	var steps := int(length / 0.25) + 1
	for i in range(1, steps):
		if is_wall_at(a.lerp(b, float(i) / steps)):
			return false
	return true


func cast(o: Vector2, rd: Vector2) -> Array:
	## DDA raycast. Returns [perpendicular distance, side, wall_x (0..1), wall type].
	var mx := int(floor(o.x))
	var my := int(floor(o.y))
	var ddx := 1e30 if rd.x == 0.0 else absf(1.0 / rd.x)
	var ddy := 1e30 if rd.y == 0.0 else absf(1.0 / rd.y)
	var step_x := 1
	var step_y := 1
	var sdx: float
	var sdy: float
	if rd.x < 0.0:
		step_x = -1
		sdx = (o.x - mx) * ddx
	else:
		sdx = (mx + 1.0 - o.x) * ddx
	if rd.y < 0.0:
		step_y = -1
		sdy = (o.y - my) * ddy
	else:
		sdy = (my + 1.0 - o.y) * ddy
	var side := 0
	var kind := METAL
	for i in 96:
		if sdx < sdy:
			sdx += ddx
			mx += step_x
			side = 0
		else:
			sdy += ddy
			my += step_y
			side = 1
		kind = cell(mx, my)
		if kind != EMPTY:
			break
	var perp := (sdx - ddx) if side == 0 else (sdy - ddy)
	var wall_x := (o.y + perp * rd.y) if side == 0 else (o.x + perp * rd.x)
	wall_x -= floor(wall_x)
	return [perp, side, wall_x, kind]


func distance_field(from: Vector2i) -> PackedInt32Array:
	## BFS step distance from a cell to every open cell (-1 = unreachable).
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(-1)
	if cell(from.x, from.y) != EMPTY:
		return dist
	var queue: Array[Vector2i] = [from]
	dist[idx(from.x, from.y)] = 0
	var head := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var d := dist[idx(c.x, c.y)]
		for dv in dirs:
			var n: Vector2i = c + dv
			if in_bounds(n.x, n.y) and cells[idx(n.x, n.y)] == EMPTY and dist[idx(n.x, n.y)] < 0:
				dist[idx(n.x, n.y)] = d + 1
				queue.append(n)
	return dist
