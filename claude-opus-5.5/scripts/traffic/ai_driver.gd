class_name AIDriver
extends RefCounted
## Drives a Vehicle: civilians cruise along right-hand lanes, turn at intersections and stop
## at red lights; police chase the player along the streets (route over the intersection graph)
## and go straight for him once close.

enum Mode { CRUISE, PURSUIT, PARKED }

const CRUISE_SPEED := 11.0
const TURN_SPEED := 5.5
const PURSUIT_SPEED := 21.0
const STOP_LINE := 10.5        # stop line distance from the intersection centre
const TURN_IN := 9.0           # where the turn curve starts/ends, from the centre

var car: Vehicle
var mode := Mode.CRUISE
var game: Game

var _from := Vector2i.ZERO
var _to := Vector2i.ZERO
var _next := Vector2i.ZERO
var _turning := false
var _stuck := 0.0
var _reverse_t := 0.0
var _route: Array[Vector2i] = []
var _route_t := 0.0


func _init(p_car: Vehicle, p_game: Game, p_mode: int) -> void:
	car = p_car
	game = p_game
	mode = p_mode


func place_on_segment(a: Vector2i, b: Vector2i) -> void:
	_from = a
	_to = b
	_next = _pick_next(b, a)
	_turning = false


func _pick_next(at: Vector2i, came_from: Vector2i) -> Vector2i:
	var options := NavGrid.inst.neighbours(at)
	options.erase(came_from)
	if options.is_empty():
		return came_from
	return options[randi() % options.size()]


## Returns [throttle (-1..1), brake (0..1), steer (-1..1, + = left), handbrake]
func compute(delta: float) -> Array:
	if mode == Mode.PARKED:
		return [0.0, 1.0, 0.0, false]
	var p := car.global_position
	var target: Vector3
	var desired: float
	if mode == Mode.CRUISE:
		var r := _cruise_target(p)
		target = r[0]
		desired = r[1]
	else:
		var r := _pursuit_target(p, delta)
		target = r[0]
		desired = r[1]
	desired = minf(desired, _obstacle_limit())
	return _drive_to(target, desired, delta)


func _drive_to(target: Vector3, desired: float, delta: float) -> Array:
	var local := car.global_transform.affine_inverse() * target
	var angle := atan2(-local.x, -local.z)
	var steer := clampf(angle / maxf(car.steer_limit(), 0.15) * 1.2, -1.0, 1.0)
	var speed := car.speed
	# Unstick: if we want to go but don't move, back up for a moment.
	if _reverse_t > 0.0:
		_reverse_t -= delta
		return [-0.7, 0.0, -steer, false]
	if desired > 2.0 and absf(speed) < 0.4:
		_stuck += delta
		if _stuck > 2.5:
			_stuck = 0.0
			_reverse_t = 1.4
	else:
		_stuck = 0.0
	var err := desired - speed
	var throttle := 0.0
	var brake := 0.0
	if desired < 0.3 and speed < 0.6:
		brake = 1.0
	elif err > 0.0:
		throttle = clampf(err * 0.35, 0.0, 1.0)
	elif err < -0.6:
		brake = clampf(-err * 0.25, 0.0, 1.0)
	return [throttle, brake, steer, false]


func _cruise_target(p: Vector3) -> Array:
	var nav := NavGrid.inst
	var pa := nav.node_pos(_from)
	var pb := nav.node_pos(_to)
	var pc := nav.node_pos(_next)
	var dir_in := (pb - pa).normalized()
	var dir_out := (pc - pb).normalized()
	var right_in := Vector3(-dir_in.z, 0, dir_in.x)
	var right_out := Vector3(-dir_out.z, 0, dir_out.x)
	var seg_len := pa.distance_to(pb)
	var s := (p - pa).dot(dir_in)
	var entry := pb - dir_in * TURN_IN + right_in * NavGrid.LANE
	var exit := pb + dir_out * TURN_IN + right_out * NavGrid.LANE
	var straight := dir_in.dot(dir_out) > 0.9
	var u_turn := dir_in.dot(dir_out) < -0.9
	if u_turn:
		exit = pb + right_out * NavGrid.LANE - dir_out * 2.0
	if not _turning and s > seg_len - TURN_IN - 0.5:
		_turning = true
	if _turning:
		var chord := exit - entry
		var t := clampf((p - entry).dot(chord) / maxf(chord.length_squared(), 0.01), 0.0, 1.0)
		if t > 0.92 or (p - exit).dot(dir_out) > 0.0:
			_from = _to
			_to = _next
			_next = _pick_next(_to, _from)
			_turning = false
			return _cruise_target(p)
		var ctrl := _lane_corner(pb, dir_in, right_in, dir_out, right_out)
		var tt := minf(t + 0.35, 1.0)
		var tgt := entry * (1.0 - tt) * (1.0 - tt) + ctrl * 2.0 * (1.0 - tt) * tt + exit * tt * tt
		if t + 0.35 > 1.0:
			tgt = exit + dir_out * (t + 0.35 - 1.0) * 16.0
		return [tgt, CRUISE_SPEED * 0.8 if straight else TURN_SPEED]
	var desired := CRUISE_SPEED
	if not straight:
		# Slow down before turning.
		var to_turn := seg_len - TURN_IN - s
		desired = minf(desired, TURN_SPEED + maxf(to_turn, 0.0) * 0.35)
	# Traffic light ahead?
	var axis := 0 if absf(dir_in.z) > 0.5 else 1
	var to_stop := seg_len - STOP_LINE - s
	var sig := game.traffic.get_signal(axis)
	if to_stop > -0.5 and to_stop < 35.0:
		if sig == TrafficLights.Light.RED or (sig == TrafficLights.Light.YELLOW and to_stop > 5.0):
			desired = minf(desired, maxf(sqrt(2.0 * 3.0 * maxf(to_stop - 0.8, 0.0)) - 0.3, 0.0))
	var ahead := minf(s + 8.0, seg_len - TURN_IN)
	return [pa + dir_in * ahead + right_in * NavGrid.LANE, desired]


static func _lane_corner(pb: Vector3, dir_in: Vector3, right_in: Vector3, dir_out: Vector3, right_out: Vector3) -> Vector3:
	## Where the incoming and outgoing lane lines cross (control point of the turn curve).
	if absf(dir_in.dot(dir_out)) > 0.9:
		return pb + right_in * NavGrid.LANE
	var a := pb + right_in * NavGrid.LANE   # point on incoming lane line
	var b := pb + right_out * NavGrid.LANE  # point on outgoing lane line
	# a + dir_in * t lies on the outgoing line: (a + dir_in*t - b) · right_out = 0
	var t := (b - a).dot(right_out) / dir_in.dot(right_out)
	return a + dir_in * t


func _pursuit_target(p: Vector3, delta: float) -> Array:
	var goal := game.player_position()
	var dist := Vector2(goal.x - p.x, goal.z - p.z).length()
	var on_foot := game.driving == null
	if dist < 40.0:
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, goal + Vector3.UP * 1.0, 1)
		var clear := car.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
		if clear:
			game.wanted.seen()
			var spd := clampf(dist * 0.7, 3.0, PURSUIT_SPEED)
			if on_foot and dist < 12.0:
				spd = 0.0
			return [goal, spd]
	# Route along the streets.
	var nav := NavGrid.inst
	_route_t -= delta
	if _route.is_empty() or _route_t <= 0.0:
		_route_t = 2.0
		_route = nav.road_route(nav.nearest_node(p), nav.nearest_node(goal))
		if _route.is_empty():
			_route = [nav.nearest_node(goal)]
	while _route.size() > 1 and nav.node_pos(_route[0]).distance_to(p) < 9.0:
		_route.pop_front()
	var node_p := nav.node_pos(_route[0])
	var d_node := node_p.distance_to(p)
	var spd := PURSUIT_SPEED
	if d_node < 25.0 and _route.size() > 1:
		spd = 10.0   # slow down for the corner
	return [node_p, spd]


func _obstacle_limit() -> float:
	## Speed cap so we don't run into whatever is in front of us.
	var limit := [99.0]   # array so the lambda below can update it
	var inv := car.global_transform.affine_inverse()
	var half_w := car.size.x * 0.5 + 0.7
	var front := car.body_center.z - car.size.z * 0.5
	var look := 16.0 if mode == Mode.CRUISE else 8.0
	var check := func(pos: Vector3) -> void:
		var l := inv * pos
		var ahead := front - l.z
		if ahead > -0.5 and ahead < look and absf(l.x - car.body_center.x) < half_w:
			limit[0] = minf(limit[0], maxf((ahead - 3.0) * 0.8, 0.0))
	for v in game.vehicles:
		if v != car and is_instance_valid(v) and v.global_position.distance_squared_to(car.global_position) < 900.0:
			# Use the near end of the other car.
			var l2 := inv * v.global_position
			var other_half := v.size.z * 0.5
			check.call(v.global_position + (car.global_transform.basis.z * other_half if l2.z < 0 else Vector3.ZERO))
	if mode == Mode.CRUISE:
		for h in game.npcs.all_alive():
			if h.global_position.distance_squared_to(car.global_position) < 400.0:
				check.call(h.global_position)
		if game.driving == null and game.hero.visible:
			check.call(game.hero.global_position)
	return limit[0]
