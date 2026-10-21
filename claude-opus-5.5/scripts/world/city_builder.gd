class_name CityBuilder
extends RefCounted
## Builds Port Coral procedurally from the GLB assets and Godot primitives.
## Axes: +X east (towards the ocean), +Z south. Ground level y = 0, sidewalks y = SLAB_H.

const HALF := 200.0            # playable area is [-200, 200] on X/Z (beach ends at SEA_LIMIT)
const ROAD_W := 12.0
const SLAB_H := 0.15
const SIDEWALK := 4.5          # building front line distance from curb
const NS_ROADS := [-160.0, -85.0, -10.0, 70.0]   # x of roads running north-south (70 = Ocean Drive)
const EW_ROADS := [-150.0, -75.0, 0.0, 75.0, 150.0]
const OCEAN_DRIVE_X := 70.0
const PROMENADE_X0 := 76.0
const PROMENADE_X1 := 92.0
const BEACH_FLAT_END := 130.0
const BEACH_SLOPE := 0.05
const WATER_Y := -0.35
const SEA_LIMIT := 158.0

const LAYER_WORLD := 1
const LAYER_BOUNDS := 4

# Footprint X × Z in metres (front faces −Z), from assets/README.md.
const FOOTPRINT := {
	"hotel": Vector2(13.63, 13.67),
	"motel": Vector2(11.76, 8.56),
	"apartment": Vector2(15.74, 16.69),
	"office": Vector2(15.76, 15.88),
	"store": Vector2(12.74, 10.96),
	"gasstation": Vector2(8.50, 8.91),
	"beachhouse": Vector2(6.86, 5.15),
}
const HEIGHT := {"hotel": 12.0, "motel": 9.0, "apartment": 18.0, "office": 24.0, "store": 6.0}

# Render profile per model: visibility range end (0 = unlimited), casts shadow.
const PROFILE := {
	"hotel": [0.0, true], "motel": [0.0, true], "apartment": [0.0, true], "office": [0.0, true],
	"store": [0.0, true], "gasstation": [400.0, true], "beachhouse": [350.0, true],
	"palm": [260.0, true], "lamp": [160.0, true], "trafficlight": [170.0, true],
	"hydrant": [60.0, false], "bench": [70.0, false], "trashcan": [60.0, false],
	"busstop": [110.0, true], "atm": [60.0, false], "umbrella": [140.0, true],
}

var scenes: Dictionary
var traffic: TrafficLights
var root: Node3D
var rng := RandomNumberGenerator.new()
# Occupancy of the whole map so models never stand inside each other.
# "ground" = what stands at body height (low collision boxes), "tall" = things up high
# (palm crowns, lamp and traffic-light arms, building volumes).
var _occ_ground: Array[Rect2] = []
var _occ_tall: Array[Rect2] = []
var _local_rects := {}   # id -> [ground Rect2, tall Rect2 or null] in model space
const TALL_IDS := ["palm", "lamp", "trafficlight", "hotel", "motel", "apartment", "office", "store", "gasstation", "beachhouse"]
var vehicles: Array[Vehicle] = []
# For navigation and the minimap.
const NAV_SOLID_IDS := ["hotel", "motel", "apartment", "office", "store", "gasstation", "beachhouse", "busstop", "palm", "umbrella"]
var solid_rects: Array[Rect2] = []
var blocks: Array[Rect2] = []
var _lamp_mesh: SphereMesh
var _mat_road: ShaderMaterial
var _mat_marks: ShaderMaterial
var _mat_walk: ShaderMaterial
var _mat_promenade: ShaderMaterial
var _mat_grass: ShaderMaterial
var _mat_sand: ShaderMaterial
var _mat_water: ShaderMaterial
var _static_body: StaticBody3D


func _init(p_scenes: Dictionary, p_traffic: TrafficLights) -> void:
	scenes = p_scenes
	traffic = p_traffic
	rng.seed = 1985


func build(p_root: Node3D) -> void:
	root = p_root
	_make_materials()
	_static_body = StaticBody3D.new()
	_static_body.name = "Ground"
	_static_body.collision_layer = LAYER_WORLD
	root.add_child(_static_body)
	_build_ground()
	_build_roads()
	_build_traffic_lights()   # first, so nothing else gets placed into them
	_build_blocks()
	_build_promenade()
	_build_beach()
	_build_parked_cars()
	_build_bounds()


# ---------------------------------------------------------------- materials

func _shader_mat(path: String, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


func _make_materials() -> void:
	_mat_road = _shader_mat("res://shaders/road.gdshader")
	_mat_marks = _shader_mat("res://shaders/road.gdshader", {"markings": true})
	_mat_walk = _shader_mat("res://shaders/pavement.gdshader")
	_mat_promenade = _shader_mat("res://shaders/pavement.gdshader", {
		"tile_color": Color(0.86, 0.66, 0.62), "joint_color": Color(0.7, 0.55, 0.5),
		"curb_color": Color(0.9, 0.86, 0.8), "tile_size": 1.5})
	_mat_grass = _shader_mat("res://shaders/ground.gdshader")
	_mat_sand = _shader_mat("res://shaders/ground.gdshader", {
		"color_a": Color(0.86, 0.76, 0.58), "color_b": Color(0.93, 0.85, 0.68), "scale": 0.25,
		"wet_level": WATER_Y + 0.1, "wet_color": Color(0.62, 0.52, 0.38)})
	_mat_water = _shader_mat("res://shaders/water.gdshader", {
		"shore_x": BEACH_FLAT_END + (-WATER_Y) / BEACH_SLOPE})
	# Flattened dome matching the lens glass of the traffic light.
	_lamp_mesh = SphereMesh.new()
	_lamp_mesh.radius = 0.2
	_lamp_mesh.height = 0.1
	_lamp_mesh.radial_segments = 16
	_lamp_mesh.rings = 6


# ---------------------------------------------------------------- helpers

static func yaw_facing(dir: Vector3) -> float:
	## Yaw that turns a model's −Z front towards dir.
	return atan2(-dir.x, -dir.z)


func _add_box_visual(center: Vector3, size: Vector3, mat: Material, collide := true, shadow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if collide:
		_add_box_collision(Transform3D(Basis(), center), size)
	return mi


func _add_box_collision(xf: Transform3D, size: Vector3, body: StaticBody3D = null) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = xf
	(body if body else _static_body).add_child(cs)


func _add_plane(center: Vector3, size: Vector2, mat: Material, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = mat
	mi.position = center
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


func place(id: String, pos: Vector3, yaw: float) -> Node3D:
	## Places a model unconditionally and marks its space as occupied.
	_reserve(id, pos, yaw)
	var n: Node3D = scenes[id].instantiate()
	n.position = pos
	n.rotation.y = yaw
	root.add_child(n)
	var prof: Array = PROFILE.get(id, [0.0, true])
	var vis_end: float = prof[0]
	if HEIGHT.has(id):
		vis_end = float(Game.dev_int("--bvis=", 0))
	for gi in n.find_children("*", "GeometryInstance3D", true, false):
		gi.visibility_range_end = vis_end
		if not prof[1]:
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if HEIGHT.has(id):
		# Boxy buildings cast their shadow from a box instead of the dense mesh: same look on
		# the street, a fraction of the shadow-pass cost.
		for gi in n.find_children("*", "GeometryInstance3D", true, false):
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sh := MeshInstance3D.new()
		var sb := BoxMesh.new()
		var fpb: Vector2 = FOOTPRINT[id]
		sb.size = Vector3(fpb.x * 0.94, HEIGHT[id] * 0.97, fpb.y * 0.94)
		sh.mesh = sb
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		sh.position.y = HEIGHT[id] * 0.97 * 0.5
		n.add_child(sh)
		var occ := OccluderInstance3D.new()
		var box := BoxOccluder3D.new()
		var fp: Vector2 = FOOTPRINT[id]
		box.size = Vector3(fp.x * 0.86, HEIGHT[id] * 0.85, fp.y * 0.86)
		occ.occluder = box
		occ.position = Vector3(0, HEIGHT[id] * 0.85 * 0.5, 0)
		n.add_child(occ)
	return n


func try_place(id: String, pos: Vector3, yaw: float) -> Node3D:
	## Places a model only if it doesn't overlap anything already placed.
	if not fits(id, pos, yaw):
		return null
	return place(id, pos, yaw)


func fits(id: String, pos: Vector3, yaw: float) -> bool:
	var lr := _get_local_rects(id)
	if not _is_free(_world_rect(lr[0], pos, yaw), _occ_ground):
		return false
	return lr[1] == null or _is_free(_world_rect(lr[1], pos, yaw), _occ_tall)


func _reserve(id: String, pos: Vector3, yaw: float) -> void:
	var lr := _get_local_rects(id)
	_occ_ground.append(_world_rect(lr[0], pos, yaw))
	if id in NAV_SOLID_IDS:
		solid_rects.append(_world_rect(lr[0], pos, yaw).grow(-0.2))
	if lr[1] != null:
		_occ_tall.append(_world_rect(lr[1], pos, yaw))


func _reserve_area(r: Rect2) -> void:
	_occ_ground.append(r)
	_occ_tall.append(r)


static func _is_free(r: Rect2, occ: Array[Rect2]) -> bool:
	for f in occ:
		if f.intersects(r):
			return false
	return true


static func _world_rect(local: Rect2, pos: Vector3, yaw: float) -> Rect2:
	## Axis-aligned world XZ bounds of a model-space XZ rect after yaw + translation.
	var b := Basis(Vector3.UP, yaw)
	var out := Rect2()
	for i in 4:
		var c := Vector2(local.position.x + local.size.x * (i % 2), local.position.y + local.size.y * (i / 2))
		var w := b * Vector3(c.x, 0, c.y)
		var p := Vector2(w.x + pos.x, w.z + pos.z)
		out = Rect2(p, Vector2.ZERO) if i == 0 else out.expand(p)
	return out


func _get_local_rects(id: String) -> Array:
	## Measures a model once: ground rect from its low collision boxes, tall rect from
	## its visual bounds (palm crowns shrunk a bit, since fronds droop).
	if _local_rects.has(id):
		return _local_rects[id]
	var inst: Node3D = scenes[id].instantiate()
	var ground := Rect2()
	var have_ground := false
	for cs in inst.find_children("*", "CollisionShape3D", true, false):
		var xf := xf_to(cs, inst)
		var faces: PackedVector3Array = cs.shape.get_faces()
		var lo := INF
		for f in faces:
			lo = minf(lo, (xf * f).y)
		if lo > 2.5:
			continue
		for f in faces:
			var w := xf * f
			var p := Vector2(w.x, w.z)
			ground = Rect2(p, Vector2.ZERO) if not have_ground else ground.expand(p)
			have_ground = true
	var vis := AABB()
	var have_vis := false
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = xf_to(mi, inst) * mi.get_aabb()
		vis = a if not have_vis else vis.merge(a)
		have_vis = true
	inst.free()
	var vis_rect := Rect2(vis.position.x, vis.position.z, vis.size.x, vis.size.z)
	if not have_ground:
		ground = vis_rect
	ground = ground.grow(0.25)
	var tall = null
	if id in TALL_IDS:
		tall = vis_rect.grow(-1.2) if id == "palm" else vis_rect
	_local_rects[id] = [ground, tall]
	return _local_rects[id]


static func xf_to(n: Node, root_node: Node) -> Transform3D:
	## Transform of n relative to root_node (works outside the scene tree).
	var t := Transform3D.IDENTITY
	while n != root_node and n != null:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


# ---------------------------------------------------------------- ground

func _build_ground() -> void:
	# Grass far around the city (only seen in the distance).
	_add_plane(Vector3((-1400.0 + PROMENADE_X1) * 0.5, -0.03, 0), Vector2(1400.0 + PROMENADE_X1, 2400), _mat_grass)
	# Asphalt base under the whole street grid.
	var city_w := PROMENADE_X0 + HALF
	var asphalt := _add_plane(Vector3((PROMENADE_X0 - HALF) * 0.5, 0.0, 0), Vector2(city_w, HALF * 2.0), _mat_road)
	asphalt.name = "Asphalt"
	_add_box_collision(Transform3D(Basis(), Vector3((BEACH_FLAT_END - HALF) * 0.5, -1.0, 0)),
		Vector3(BEACH_FLAT_END + HALF, 2.0, HALF * 2.0 + 20.0))


func _build_roads() -> void:
	# Lane marking strips between intersections.
	var half_w := ROAD_W * 0.5
	for x in NS_ROADS:
		var zs := [-HALF - half_w]
		zs.append_array(EW_ROADS)
		zs.append(HALF + half_w)
		for i in zs.size() - 1:
			var z0: float = zs[i] + half_w
			var z1: float = zs[i + 1] - half_w
			var mi := _add_plane(Vector3(x, 0.01, (z0 + z1) * 0.5), Vector2(ROAD_W, z1 - z0), _mat_marks)
			mi.set_instance_shader_parameter("seg_len", z1 - z0)
			mi.set_instance_shader_parameter("seg_w", ROAD_W)
			mi.set_instance_shader_parameter("cw_start", 1.0 if i > 0 else 0.0)
			mi.set_instance_shader_parameter("cw_end", 1.0 if i < zs.size() - 2 else 0.0)
	for z in EW_ROADS:
		var xs := [-HALF - half_w]
		xs.append_array(NS_ROADS)
		for i in xs.size() - 1:
			var x0: float = xs[i] + half_w
			var x1: float = xs[i + 1] - half_w
			# Plane rotated -90° so its UV.y runs along +X.
			var mi := _add_plane(Vector3((x0 + x1) * 0.5, 0.01, z), Vector2(ROAD_W, x1 - x0), _mat_marks, -PI / 2)
			mi.set_instance_shader_parameter("seg_len", x1 - x0)
			mi.set_instance_shader_parameter("seg_w", ROAD_W)
			mi.set_instance_shader_parameter("cw_start", 1.0 if i > 0 else 0.0)
			mi.set_instance_shader_parameter("cw_end", 1.0)


# ---------------------------------------------------------------- blocks

func _build_blocks() -> void:
	var xb := [-HALF, -160.0, -85.0, -10.0, OCEAN_DRIVE_X]
	var zb := [-HALF, -150.0, -75.0, 0.0, 75.0, 150.0, HALF]
	var half_w := ROAD_W * 0.5
	for ci in xb.size() - 1:
		for ri in zb.size() - 1:
			var x0: float = xb[ci] + (half_w if ci > 0 else 0.0)
			var x1: float = xb[ci + 1] - half_w
			var z0: float = zb[ri] + (half_w if ri > 0 else 0.0)
			var z1: float = zb[ri + 1] - (half_w if ri < zb.size() - 2 else 0.0)
			_build_block(Rect2(x0, z0, x1 - x0, z1 - z0), ci, ri, zb.size() - 1)


func _build_block(r: Rect2, ci: int, ri: int, rows: int) -> void:
	blocks.append(r)
	var c := r.get_center()
	_add_box_visual(Vector3(c.x, SLAB_H * 0.5, c.y), Vector3(r.size.x, SLAB_H, r.size.y), _mat_walk)
	var inner := r.grow(-SIDEWALK - 0.3)
	_add_plane(Vector3(inner.get_center().x, SLAB_H + 0.005, inner.get_center().y), inner.size, _mat_grass)

	# Which edges face a road: [north(-Z), south(+Z), west(-X), east(+X)]
	var road_n := ri > 0
	var road_s := ri < rows - 1
	var road_w := ci > 0
	var road_e := true

	if ci == 1 and ri == 4:
		_build_gas_motel_block(r)
	elif ci == 0:
		_fill_row(r, Vector3.RIGHT, ["apartment", "store", "office", "apartment", "store"], 0.15)
	elif ci == 3:
		_fill_row(r, Vector3.RIGHT, ["hotel"], 0.08)
		_fill_row(r, Vector3.LEFT, ["apartment", "store", "apartment", "office"], 0.25)
	else:
		var pool := ["office", "apartment", "office", "store"] if ci == 2 else ["apartment", "store", "apartment", "hotel"]
		if road_n:
			_fill_row(r, Vector3.FORWARD, pool, 0.2)
		if road_s:
			_fill_row(r, Vector3.BACK, pool, 0.2)

	_scatter_palms(inner, 3 if ci < 3 else 2)
	# Street furniture along road-facing edges.
	if road_n: _street_props(r, Vector3.FORWARD)
	if road_s: _street_props(r, Vector3.BACK)
	if road_w: _street_props(r, Vector3.LEFT)
	if road_e: _street_props(r, Vector3.RIGHT)


func _edge_frame(r: Rect2, facing: Vector3) -> Array:
	## Returns [start point on the curb line, direction along the edge, edge length].
	var y := SLAB_H
	if facing == Vector3.FORWARD:
		return [Vector3(r.position.x, y, r.position.y), Vector3.RIGHT, r.size.x]
	elif facing == Vector3.BACK:
		return [Vector3(r.end.x, y, r.end.y), Vector3.LEFT, r.size.x]
	elif facing == Vector3.LEFT:
		return [Vector3(r.position.x, y, r.end.y), Vector3.FORWARD, r.size.y]
	return [Vector3(r.end.x, y, r.position.y), Vector3.BACK, r.size.y]


func _fill_row(r: Rect2, facing: Vector3, pool: Array, skip_chance: float) -> void:
	var ef := _edge_frame(r, facing)
	var start: Vector3 = ef[0]
	var along: Vector3 = ef[1]
	var length: float = ef[2]
	var cursor := 4.0
	while true:
		var id: String = pool[rng.randi() % pool.size()]
		var fp: Vector2 = FOOTPRINT[id]
		if cursor + fp.x > length - 4.0:
			break
		var center := start + along * (cursor + fp.x * 0.5) - facing * (SIDEWALK + fp.y * 0.5)
		if rng.randf() >= skip_chance and fits(id, center, yaw_facing(facing)):
			place(id, center, yaw_facing(facing))
			cursor += fp.x + rng.randf_range(2.0, 5.0)
		else:
			cursor += fp.x * 0.6


func _build_gas_motel_block(r: Rect2) -> void:
	# Gas station on the north-east corner with an asphalt forecourt, a store beside it,
	# motels lining the south edge.
	var fore := Rect2(r.end.x - 32.0, r.position.y + 0.5, 31.5, 26.0)
	_add_plane(Vector3(fore.get_center().x, SLAB_H + 0.01, fore.get_center().y), fore.size, _mat_road)
	_reserve_area(fore)
	var gas_pos := Vector3(r.end.x - 16.0, SLAB_H, r.position.y + 15.0)
	place("gasstation", gas_pos, yaw_facing(Vector3.FORWARD))
	place("store", Vector3(r.end.x - 42.0, SLAB_H, r.position.y + SIDEWALK + 5.5), yaw_facing(Vector3.FORWARD))
	_fill_row(r, Vector3.BACK, ["motel"], 0.0)


func _scatter_palms(inner: Rect2, count: int) -> void:
	var placed := 0
	var tries := 0
	while placed < count and tries < 40:
		tries += 1
		var p := Vector2(rng.randf_range(inner.position.x + 2, inner.end.x - 2), rng.randf_range(inner.position.y + 2, inner.end.y - 2))
		if try_place("palm", Vector3(p.x, SLAB_H, p.y), rng.randf() * TAU):
			placed += 1


func _street_props(r: Rect2, facing: Vector3) -> void:
	var ef := _edge_frame(r, facing)
	var start: Vector3 = ef[0]
	var along: Vector3 = ef[1]
	var length: float = ef[2]
	var yaw := yaw_facing(facing)
	# Lamps: pole near the curb, arm over the road.
	var n_lamps := maxi(1, int(length / 30.0))
	for i in n_lamps:
		var t := (i + 0.5) * length / n_lamps
		var pole := start + along * t - facing * 0.7
		try_place("lamp", pole - Basis(Vector3.UP, yaw) * Vector3(0, 0, 1.255), yaw)
	var spots := []   # distances along the edge free for other props
	for i in range(int(length / 6.0)):
		var t := 8.0 + i * 6.0
		if t < length - 8.0:
			spots.append(t)
	spots.shuffle()
	if spots.is_empty():
		return
	var take := func() -> float:
		return spots.pop_back() if not spots.is_empty() else -1.0
	var t: float = take.call()
	if t > 0 and rng.randf() < 0.7:
		try_place("hydrant", start + along * t - facing * 0.8, yaw)
	for k in 2:
		t = take.call()
		if t > 0:
			try_place("trashcan", start + along * t - facing * 1.0, yaw + rng.randf_range(-0.3, 0.3))
	t = take.call()
	if t > 0 and rng.randf() < 0.6:
		try_place("bench", start + along * t - facing * 2.4, yaw)
	t = take.call()
	if t > 0 and rng.randf() < 0.25:
		try_place("busstop", start + along * t - facing * 2.2, yaw)
	t = take.call()
	if t > 0 and rng.randf() < 0.3:
		try_place("atm", start + along * t - facing * (SIDEWALK - 0.4), yaw)


# ---------------------------------------------------------------- waterfront

func _build_promenade() -> void:
	var w := PROMENADE_X1 - PROMENADE_X0
	var cx := (PROMENADE_X0 + PROMENADE_X1) * 0.5
	_add_box_visual(Vector3(cx, SLAB_H * 0.5, 0), Vector3(w, SLAB_H, HALF * 2.0 + 40.0), _mat_promenade)
	var z := -HALF + 4.0
	var i := 0
	while z < HALF - 2.0:
		try_place("palm", Vector3(PROMENADE_X0 + 2.5, SLAB_H, z), rng.randf() * TAU)
		try_place("palm", Vector3(PROMENADE_X1 - 2.5, SLAB_H, z + 8.0), rng.randf() * TAU)
		if i % 2 == 0:
			var yaw := yaw_facing(Vector3.LEFT)
			var pole := Vector3(PROMENADE_X0 + 0.7, SLAB_H, z + 4.0)
			try_place("lamp", pole - Basis(Vector3.UP, yaw) * Vector3(0, 0, 1.255), yaw)
		else:
			try_place("bench", Vector3(PROMENADE_X1 - 3.0, SLAB_H, z + 2.0), yaw_facing(Vector3.RIGHT))
			try_place("trashcan", Vector3(PROMENADE_X1 - 3.0, SLAB_H, z + 4.0), 0.0)
		z += 16.0
		i += 1


func _build_beach() -> void:
	var z_len := HALF * 2.0 + 1200.0
	# Flat dry sand
	var flat_w := BEACH_FLAT_END - PROMENADE_X1
	_add_plane(Vector3((PROMENADE_X1 + BEACH_FLAT_END) * 0.5, 0.0, 0), Vector2(flat_w, z_len), _mat_sand)
	# Sloping sand into the water
	var slope_len := 120.0
	var ang := atan(BEACH_SLOPE)
	var mid_x := BEACH_FLAT_END + cos(ang) * slope_len * 0.5
	var mid_y := -sin(ang) * slope_len * 0.5
	var slope := _add_plane(Vector3(mid_x, mid_y, 0), Vector2(slope_len, z_len), _mat_sand)
	slope.rotation = Vector3(0, 0, -ang)
	var cs_xf := Transform3D(Basis(Vector3.BACK, -ang), Vector3(mid_x, mid_y, 0)).translated_local(Vector3(0, -1.0, 0))
	_add_box_collision(cs_xf, Vector3(slope_len, 2.0, HALF * 2.0 + 20.0))
	# Ocean to the horizon
	var water := _add_plane(Vector3(BEACH_FLAT_END + 2000.0, WATER_Y, 0), Vector2(4000.0, 4000.0), _mat_water)
	water.name = "Ocean"
	# Lifeguard houses and umbrellas
	var houses := [-115.0, 5.0, 125.0]
	for hz in houses:
		place("beachhouse", Vector3(120.0, 0.0, hz), yaw_facing(Vector3.RIGHT))
	var zz := -HALF + 6.0
	while zz < HALF - 4.0:
		for x in [102.0, 113.0, 124.0]:
			var near_house := false
			for hz in houses:
				if absf(zz - hz) < 9.0 and x > 110.0:
					near_house = true
			if near_house or rng.randf() < 0.45:
				continue
			try_place("umbrella", Vector3(x + rng.randf_range(-2, 2), 0.0, zz + rng.randf_range(-2, 2)),
				yaw_facing(Vector3.RIGHT) + rng.randf_range(-0.5, 0.5))
		zz += 10.0


# ---------------------------------------------------------------- traffic lights

func _build_traffic_lights() -> void:
	var dirs := [Vector3.FORWARD, Vector3.BACK, Vector3.RIGHT, Vector3.LEFT]
	for x in NS_ROADS:
		for z in EW_ROADS:
			var c := Vector3(x, SLAB_H, z)
			for d: Vector3 in dirs:
				if d == Vector3.LEFT and x >= OCEAN_DRIVE_X:
					continue   # nothing comes from the beach side of Ocean Drive
				var left := Vector3(d.z, 0, -d.x)
				# Pole on the far-left corner, close to the curb so the head (5.75 m out on the
				# arm) hangs over the centre line instead of the oncoming lane.
				var corner := c + d * 7.2 + left * 6.5
				var yaw := atan2(d.x, d.z)   # lenses (−Z) face the approaching driver
				var basis := Basis(Vector3.UP, yaw)
				var model := place("trafficlight", corner - basis * Vector3(2.85, 0, -0.15), yaw)
				traffic.register(model, 0 if absf(d.z) > 0.5 else 1, _lamp_mesh, PROFILE["trafficlight"][0])


# ---------------------------------------------------------------- parked cars

const PARKED := {
	"sedan": 4, "sportscar": 3, "supercar": 2, "convertible": 3, "taxi": 4,
	"police": 2, "ambulance": 1, "pickup": 3, "van": 2, "bus": 1,
}


func _build_parked_cars() -> void:
	## Cars parked along the curbs (right-hand side of each lane, facing the traffic flow).
	# A few hand-placed ones right next to the starting point on Ocean Drive.
	var east_curb := OCEAN_DRIVE_X + ROAD_W * 0.5
	_spawn_vehicle("convertible", Vector3(east_curb - 0.1 - 0.97, 0, 16.0), yaw_facing(Vector3.FORWARD))
	_spawn_vehicle("supercar", Vector3(east_curb - 0.1 - 1.14, 0, 26.0), yaw_facing(Vector3.FORWARD))
	_spawn_vehicle("taxi", Vector3(east_curb - 0.1 - 1.08, 0, 36.0), yaw_facing(Vector3.FORWARD))
	var counts := PARKED.duplicate()
	counts["convertible"] -= 1
	counts["supercar"] -= 1
	counts["taxi"] -= 1
	var pool := []
	for id in counts:
		for i in counts[id]:
			pool.append(id)
	pool.shuffle()
	# Candidate spots: [center on the curb line, facing, along-direction]
	var spots := []
	var half_w := ROAD_W * 0.5
	for x in NS_ROADS:
		var zs := [-HALF]
		zs.append_array(EW_ROADS)
		zs.append(HALF)
		for i in zs.size() - 1:
			var z := float(zs[i]) + 16.0
			while z < float(zs[i + 1]) - 16.0:
				spots.append([Vector3(x + half_w, 0, z), Vector3.FORWARD])   # east side, northbound
				spots.append([Vector3(x - half_w, 0, z), Vector3.BACK])      # west side, southbound
				z += 13.0
	for z in EW_ROADS:
		var xs := [-HALF]
		xs.append_array(NS_ROADS)
		for i in xs.size() - 1:
			var x := float(xs[i]) + 16.0
			while x < float(xs[i + 1]) - 16.0:
				spots.append([Vector3(x, 0, z + half_w), Vector3.RIGHT])     # south side, eastbound
				spots.append([Vector3(x, 0, z - half_w), Vector3.LEFT])      # north side, westbound
				x += 13.0
	# Shuffle deterministically
	for i in range(spots.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = spots[i]
		spots[i] = spots[j]
		spots[j] = tmp
	for id in pool:
		while not spots.is_empty():
			var sp: Array = spots.pop_back()
			var facing: Vector3 = sp[1]
			var half_width: float = _get_local_rects(id)[0].size.x * 0.5 - 0.25
			# Curb is on the right of the driving direction.
			var right := Vector3(-facing.z, 0, facing.x)
			var pos: Vector3 = sp[0] - right * (0.1 + half_width)
			if _spawn_vehicle(id, pos, yaw_facing(facing)):
				break


func _spawn_vehicle(id: String, pos: Vector3, yaw: float) -> Vehicle:
	if not fits(id, pos, yaw):
		return null
	_reserve(id, pos, yaw)
	var v := Vehicle.new()
	v.setup(id, scenes[id])
	v.position = pos
	v.rotation.y = yaw
	root.add_child(v)
	vehicles.append(v)
	return v


# ---------------------------------------------------------------- bounds

func _build_bounds() -> void:
	var body := StaticBody3D.new()
	body.name = "MapBounds"
	body.collision_layer = LAYER_BOUNDS
	body.collision_mask = 0
	root.add_child(body)
	var h := 60.0
	var west := -HALF
	var east := SEA_LIMIT
	var span_x := east - west
	_add_box_collision(Transform3D(Basis(), Vector3(west - 1.0, h * 0.5 - 5.0, 0)), Vector3(2, h, HALF * 2 + 4), body)
	_add_box_collision(Transform3D(Basis(), Vector3(east + 1.0, h * 0.5 - 5.0, 0)), Vector3(2, h, HALF * 2 + 4), body)
	_add_box_collision(Transform3D(Basis(), Vector3((west + east) * 0.5, h * 0.5 - 5.0, -HALF - 1.0)), Vector3(span_x + 4, h, 2), body)
	_add_box_collision(Transform3D(Basis(), Vector3((west + east) * 0.5, h * 0.5 - 5.0, HALF + 1.0)), Vector3(span_x + 4, h, 2), body)
