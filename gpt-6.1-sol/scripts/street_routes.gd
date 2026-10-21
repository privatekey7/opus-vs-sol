extends RefCounted

const XS := [-180.0, -100.0, -20.0, 60.0]
const ZS := [-160.0, -80.0, 0.0, 80.0, 160.0]
var road := AStar3D.new()
var walk := AStar3D.new()

func _init() -> void:
	for x in XS.size():
		for z in ZS.size():
			var id := x * 5 + z
			road.add_point(id, Vector3(XS[x], 0.16, ZS[z]))
			for corner in 4:
				var sx := -1.0 if corner % 2 == 0 else 1.0
				var sz := -1.0 if corner < 2 else 1.0
				walk.add_point(id * 4 + corner, Vector3(XS[x] + sx * 9.5, 0.18, ZS[z] + sz * 9.5))
	for x in XS.size():
		for z in ZS.size():
			var id := x * 5 + z
			if x < 3:
				road.connect_points(id, id + 5)
			if z < 4:
				road.connect_points(id, id + 1)
			for corner in 4:
				walk.connect_points(id * 4 + corner, id * 4 + (corner ^ 1))
				walk.connect_points(id * 4 + corner, id * 4 + (corner ^ 2))
				if x < 3 and corner % 2 == 1:
					walk.connect_points(id * 4 + corner, (id + 5) * 4 + corner - 1)
				if z < 4 and corner >= 2:
					walk.connect_points(id * 4 + corner, (id + 1) * 4 + corner - 2)
	for z in ZS.size():
		walk.add_point(1000 + z, Vector3(103, 0.18, ZS[z]))
		walk.connect_points(1000 + z, (15 + z) * 4 + 1)
		walk.connect_points(1000 + z, (15 + z) * 4 + 3)
		if z > 0:
			walk.connect_points(999 + z, 1000 + z)

func walk_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	return walk.get_point_path(walk.get_closest_point(from), walk.get_closest_point(to))

func projection(point: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var distance := INF
	for x in XS:
		var p := Vector3(x, 0.16, clampf(point.z, ZS[0], ZS[-1]))
		if p.distance_squared_to(point) < distance:
			best = p
			distance = p.distance_squared_to(point)
	for z in ZS:
		var p := Vector3(clampf(point.x, XS[0], XS[-1]), 0.16, z)
		if p.distance_squared_to(point) < distance:
			best = p
			distance = p.distance_squared_to(point)
	return best

func connect_projection(id: int, point: Vector3, forward := Vector3.ZERO) -> void:
	road.add_point(id, point)
	var neighbors: Array[int] = []
	for other in range(20):
		var p := road.get_point_position(other)
		var same_line := absf(p.x - point.x) < 0.1 or absf(p.z - point.z) < 0.1
		if not same_line:
			continue
		var blocked := false
		for between in range(20):
			if between == other:
				continue
			var q := road.get_point_position(between)
			if (q - point).length() > 0.1 and (q - point).length() < (p - point).length() - 0.1 and (q - point).normalized().dot((p - point).normalized()) > 0.99:
				blocked = true
		if not blocked:
			neighbors.append(other)
	var ahead: Array[int] = []
	for other in neighbors:
		if (road.get_point_position(other) - point).dot(forward) > 1:
			ahead.append(other)
	for other in (ahead if not ahead.is_empty() else neighbors):
		road.connect_points(id, other)

func road_path(from: Vector3, to: Vector3, forward: Vector3) -> PackedVector3Array:
	var start := projection(from)
	var goal := projection(to)
	if start.distance_to(goal) < 12:
		goal = road.get_point_position(randi() % 20)
	connect_projection(100, start, forward)
	connect_projection(101, goal)
	# На одном отрезке впереди цели не нужно сначала ехать до следующего перекрёстка.
	if (absf(start.x - goal.x) < 0.1 or absf(start.z - goal.z) < 0.1) and (goal - start).dot(forward) > 0:
		var blocked := false
		for id in range(20):
			var p := road.get_point_position(id)
			if p.distance_to(start) > 0.1 and p.distance_to(goal) > 0.1 and absf(p.distance_to(start) + p.distance_to(goal) - start.distance_to(goal)) < 0.1:
				blocked = true
		if not blocked:
			road.connect_points(100, 101)
	var points := road.get_point_path(100, 101)
	road.remove_point(100)
	road.remove_point(101)
	var result := PackedVector3Array()
	for i in range(1, points.size()):
		var dir := (points[i] - points[i - 1]).normalized()
		result.append(points[i] + dir.cross(Vector3.UP) * 3.0)
	return result
