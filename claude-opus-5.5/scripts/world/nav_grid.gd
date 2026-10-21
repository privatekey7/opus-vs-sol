class_name NavGrid
extends RefCounted
## Pathfinding data for NPCs.
## * Walking: AStarGrid2D over the map with buildings and big props marked solid.
## * Driving: graph of intersections; lanes are offset to the right of the road centre line.

const CELL := 1.5
const ORIGIN := Vector2(-200.0, -200.0)
const SIZE := Vector2(360.0, 400.0)
const LANE := 2.1            # lane centre offset from the road centre line

static var inst: NavGrid

var astar := AStarGrid2D.new()
var road_xs: Array = []       # x of north-south roads
var road_zs: Array = []       # z of east-west roads
var blocks: Array[Rect2] = [] # city blocks (for the minimap)
var walk_areas: Array[Rect2] = [] # blocks + promenade: sidewalk rings for pedestrians
var promenade: Rect2


func _init(solid_rects: Array[Rect2], p_blocks: Array[Rect2], p_road_xs: Array, p_road_zs: Array, p_promenade: Rect2) -> void:
	inst = self
	blocks = p_blocks
	walk_areas = p_blocks
	road_xs = p_road_xs
	road_zs = p_road_zs
	promenade = p_promenade
	astar.region = Rect2i(0, 0, int(SIZE.x / CELL), int(SIZE.y / CELL))
	astar.cell_size = Vector2(CELL, CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for r in solid_rects:
		var a := _cell(Vector3(r.position.x, 0, r.position.y))
		var b := _cell(Vector3(r.end.x, 0, r.end.y))
		for x in range(a.x, b.x + 1):
			for y in range(a.y, b.y + 1):
				var c := Vector2i(x, y)
				if astar.is_in_boundsv(c):
					astar.set_point_solid(c, true)


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor((p.x - ORIGIN.x) / CELL)), int(floor((p.z - ORIGIN.y) / CELL)))


func _world(c: Vector2i) -> Vector3:
	return Vector3(ORIGIN.x + (c.x + 0.5) * CELL, 0.0, ORIGIN.y + (c.y + 0.5) * CELL)


func _nearest_free(c: Vector2i) -> Vector2i:
	if astar.is_in_boundsv(c) and not astar.is_point_solid(c):
		return c
	for r in range(1, 6):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				for cc in [Vector2i(c.x + dx, c.y + dy), Vector2i(c.x + dy, c.y + dx)]:
					if astar.is_in_boundsv(cc) and not astar.is_point_solid(cc):
						return cc
	return c


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	## Walking path around buildings (y = 0); empty if unreachable.
	var a := _nearest_free(_cell(from))
	var b := _nearest_free(_cell(to))
	var out := PackedVector3Array()
	if not astar.is_in_boundsv(a) or not astar.is_in_boundsv(b):
		return out
	var ids := astar.get_id_path(a, b, true)
	# Thin the path: keep turning points only.
	var prev_dir := Vector2i.ZERO
	for i in ids.size():
		if i > 0 and i < ids.size() - 1:
			var d := ids[i + 1] - ids[i]
			if d == prev_dir:
				continue
			prev_dir = d
		out.append(_world(ids[i]))
	if out.size() > 0:
		out[out.size() - 1] = Vector3(to.x, 0, to.z)
	return out


func is_walkable(p: Vector3) -> bool:
	var c := _cell(p)
	return astar.is_in_boundsv(c) and not astar.is_point_solid(c)


## ---------------------------------------------------------------- sidewalk rings

func ring_for(p: Vector3) -> Array:
	## Sidewalk loop (4 corners, clockwise) of the block containing or nearest to p.
	var best := -1
	var best_d := INF
	for i in walk_areas.size():
		var r: Rect2 = walk_areas[i]
		var d := Vector2(maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0), maxf(maxf(r.position.y - p.z, p.z - r.end.y), 0.0)).length()
		if d < best_d:
			best_d = d
			best = i
	return ring_of(walk_areas[best])


static func ring_of(r: Rect2) -> Array:
	var g := r.grow(-3.3)
	return [Vector3(g.position.x, 0, g.position.y), Vector3(g.end.x, 0, g.position.y),
		Vector3(g.end.x, 0, g.end.y), Vector3(g.position.x, 0, g.end.y)]


## ---------------------------------------------------------------- road graph

func node_pos(n: Vector2i) -> Vector3:
	return Vector3(road_xs[n.x], 0, road_zs[n.y])


func nearest_node(p: Vector3) -> Vector2i:
	var bx := 0
	var bz := 0
	for i in road_xs.size():
		if absf(road_xs[i] - p.x) < absf(road_xs[bx] - p.x):
			bx = i
	for j in road_zs.size():
		if absf(road_zs[j] - p.z) < absf(road_zs[bz] - p.z):
			bz = j
	return Vector2i(bx, bz)


func neighbours(n: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var m: Vector2i = n + d
		if m.x >= 0 and m.x < road_xs.size() and m.y >= 0 and m.y < road_zs.size():
			out.append(m)
	return out


func road_route(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	## Breadth-first route over intersections (grid is tiny: 4 x 5).
	var prev := {from: from}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var n: Vector2i = queue.pop_front()
		if n == to:
			break
		for m in neighbours(n):
			if not prev.has(m):
				prev[m] = n
				queue.append(m)
	var route: Array[Vector2i] = []
	if not prev.has(to):
		return route
	var cur := to
	while cur != from:
		route.push_front(cur)
		cur = prev[cur]
	return route


static func lane_point(a: Vector3, b: Vector3, along: float) -> Vector3:
	## Point on the right-hand lane of the road a→b, `along` metres from a.
	var dir := (b - a).normalized()
	var right := Vector3(-dir.z, 0, dir.x)
	return a + dir * along + right * LANE


func on_road_segment(p: Vector3) -> Array:
	## If p lies on a road between intersections, returns [node_a, node_b] ordered so that
	## p is on the right-hand lane when driving a→b. Otherwise [].
	for i in road_xs.size():
		if absf(p.x - road_xs[i]) < 6.0:
			for j in road_zs.size() - 1:
				if p.z > road_zs[j] + 6.0 and p.z < road_zs[j + 1] - 6.0:
					var a := Vector2i(i, j)
					var b := Vector2i(i, j + 1)
					# Southbound (+Z) uses the west lane (x < road x).
					return [a, b] if p.x < road_xs[i] else [b, a]
	for j in road_zs.size():
		if absf(p.z - road_zs[j]) < 6.0:
			for i in road_xs.size() - 1:
				if p.x > road_xs[i] + 6.0 and p.x < road_xs[i + 1] - 6.0:
					var a := Vector2i(i, j)
					var b := Vector2i(i + 1, j)
					# Eastbound (+X) uses the south lane (z > road z).
					return [a, b] if p.z > road_zs[j] else [b, a]
	return []
