extends CharacterBody3D

const DATA := {
	"sedan": [Vector3(2.042, 1.469, 4.6), [0.35322, 0.35324, 0.34309, 0.34334], 27.0, 8.0, "Седан"],
	"sportscar": [Vector3(2.044, 1.338, 4.5), [0.36614, 0.38023, 0.38297, 0.38481], 35.0, 11.0, "Спорткар"],
	"supercar": [Vector3(2.261, 1.194, 4.6), [0.37974, 0.38686, 0.36967, 0.36339], 40.0, 13.0, "Суперкар"],
	"convertible": [Vector3(1.923, 1.238, 4.6), [0.32851, 0.32871, 0.32469, 0.32477], 30.0, 9.0, "Кабриолет"],
	"taxi": [Vector3(2.147, 1.666, 4.7), [0.39975, 0.40734, 0.37458, 0.37432], 26.0, 8.0, "Такси"],
	"police": [Vector3(2.239, 1.784, 4.8), [0.37226, 0.37143, 0.36781, 0.36750], 33.0, 10.0, "Патрульная машина"],
	"ambulance": [Vector3(3.058, 3.084, 6.2), [0.45752, 0.45649, 0.42319, 0.42348], 23.0, 6.0, "Скорая помощь"],
	"pickup": [Vector3(2.328, 1.798, 5.3), [0.41580, 0.41590, 0.39362, 0.39365], 26.0, 7.0, "Пикап"],
	"van": [Vector3(2.542, 2.273, 5.2), [0.43258, 0.43294, 0.43378, 0.43250], 23.0, 6.5, "Фургон"],
	"bus": [Vector3(4.126, 4.414, 10), [0.66857, 0.66327, 0.64284, 0.64054], 19.0, 4.5, "Автобус"]
}
var kind := "sedan"
var dimensions := Vector3.ONE
var model: Node3D
var model_rest := Transform3D.IDENTITY
var body: Node3D
var body_rest := Transform3D.IDENTITY
var occupied := false
var exit_requested := false
var speed := 0.0
var steer := 0.0
var rpm := 850.0
var impact := 0.0
var impact_cooldown := 0.0
var wheels: Array[Node3D] = []
var spins: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_distance := 0.0
var previous_distance := 0.0
var previous_steer := 0.0
var wheelbase := 2.6
var hull: BoxShape3D
var rotation_probe: BoxShape3D
var motor: AudioStreamPlayer3D
var generator: AudioStreamGenerator
var playback: AudioStreamGeneratorPlayback
var phase := 0.0
var sound_rpm := 850.0
var sound_gain := 0.0
var planar_velocity := Vector3.ZERO
var drifting := false
var ai_driver := false
var police_ai := false
var driver = null
var ai_route := PackedVector3Array()
var ai_index := 0
var ai_timer := 0.0
var ai_stuck := 0.0
var recovery := 0.0
var waiting_red := false
var overtake := PackedVector3Array()
var overtake_index := 0
var siren: AudioStreamPlayer3D
var beacons: Array[OmniLight3D] = []
const Sounds = preload("res://scripts/sound_bank.gd")

func life():
	return get_parent().get("life")

func _exit_tree() -> void:
	playback = null
	if is_instance_valid(motor):
		motor.stop()
	if is_instance_valid(siren):
		siren.stop()

func _ready() -> void:
	add_to_group("vehicles")
	collision_layer = 5
	collision_mask = 3
	floor_snap_length = 0.4
	safe_margin = 0.002
	max_slides = 8
	floor_max_angle = deg_to_rad(40)
	dimensions = DATA[kind][0]
	var path := "res://assets/vehicles/%s.glb" % kind
	var world = get_parent()
	if not world.cache.has(path):
		world.cache[path] = load(path)
	model = world.cache[path].instantiate()
	add_child(model)
	model_rest = model.transform
	model.top_level = true
	model.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	model.global_transform = global_transform * model_rest
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.lod_bias = 0.3
		mesh.visibility_range_end = 85
		mesh.visibility_range_end_margin = 12
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hull = BoxShape3D.new()
	hull.size = Vector3(dimensions.x * 0.97, dimensions.y, dimensions.z * 0.97)
	var shape := CollisionShape3D.new()
	var convex := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	var x := hull.size.x * 0.5
	var z := hull.size.z * 0.5
	var bevel := minf(0.24, x * 0.2)
	for y in [0.0, dimensions.y]:
		for corner in [Vector2(-x + bevel, -z), Vector2(x - bevel, -z), Vector2(x, -z + bevel), Vector2(x, z - bevel), Vector2(x - bevel, z), Vector2(-x + bevel, z), Vector2(-x, z - bevel), Vector2(-x, -z + bevel)]:
			points.append(Vector3(corner.x, y, corner.y))
	convex.points = points
	shape.shape = convex
	add_child(shape)
	rotation_probe = BoxShape3D.new()
	rotation_probe.size = hull.size - Vector3(0.12, 0.18, 0.2)
	for id in ["fl", "fr", "rl", "rr"]:
		wheels.append(model.find_child("wheel_" + id, true, false))
	wheelbase = clampf(absf(model.to_local(wheels[0].global_position).z - model.to_local(wheels[2].global_position).z), 1.8, 8.0)
	body = model.find_child("body", true, false)
	if body:
		body_rest = body.transform
	motor = AudioStreamPlayer3D.new()
	generator = AudioStreamGenerator.new()
	generator.mix_rate = 22050
	generator.buffer_length = 0.12
	motor.stream = generator
	motor.volume_db = -5
	motor.unit_size = 12
	motor.max_distance = 65
	add_child(motor)
	if kind == "police":
		siren = AudioStreamPlayer3D.new()
		siren.stream = Sounds.sound("siren")
		siren.volume_db = -8
		siren.unit_size = 18
		siren.max_distance = 110
		add_child(siren)
		for side in [-1, 1]:
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(side * 0.45, dimensions.y + 0.05, 0)
			lamp.omni_range = 4
			lamp.light_color = Color("ff3046") if side < 0 else Color("407dff")
			lamp.light_energy = 0
			add_child(lamp)
			beacons.append(lamp)

func start_engine() -> void:
	occupied = true
	ai_driver = false
	police_ai = false
	set_siren(false)
	exit_requested = false
	motor.stop()
	motor.stream = generator
	motor.volume_db = -5
	motor.pitch_scale = 1
	motor.play()
	playback = motor.get_stream_playback()
	sound_gain = 0.0
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.visibility_range_end = 0

func stop_engine() -> void:
	occupied = false
	exit_requested = false
	motor.stop()
	playback = null
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.visibility_range_end = 85

func start_ai(person = null, pursuing := false) -> void:
	ai_route = PackedVector3Array()
	overtake = PackedVector3Array()
	overtake_index = 0
	ai_index = 0
	ai_stuck = 0
	recovery = 0
	ai_driver = true
	police_ai = pursuing
	driver = person
	motor.stream = Sounds.sound("engine")
	motor.volume_db = -19
	motor.play()
	set_siren(pursuing)
	ai_timer = 0

func set_siren(on: bool) -> void:
	if siren != null:
		if on and not siren.playing:
			siren.play()
		elif not on:
			siren.stop()
	for light in beacons:
		light.light_energy = 3 if on else 0

func eject_driver() -> void:
	ai_driver = false
	police_ai = false
	set_siren(false)
	speed = 0
	planar_velocity = Vector3.ZERO
	if is_instance_valid(driver):
		var point := exit_position()
		if not point.is_finite():
			point = global_position + global_basis.x * (dimensions.x / 2 + 1)
		driver.in_car = null
		driver.global_position = point
		driver.origin = point
		driver.collision_layer = 9
		driver.show()
		driver.animator.active = true
		driver.reset_physics_interpolation()
		if driver.police:
			driver.stunned = 2.8
			if life() != null and not life().officers.has(driver):
				life().officers.append(driver)
		driver.flee(global_position)
		driver = null
	motor.stop()

func take_damage(amount: float, source := Vector3.ZERO, by_player := true) -> void:
	impact = maxf(impact, 0.5)
	if by_player and kind == "police" and life() != null:
		life().crime(2, global_position)

func ai_controls(delta: float) -> Vector3:
	var city = life()
	if city == null:
		return Vector3.ZERO
	if police_ai and global_position.distance_to(city.hero.global_position) < 75 and city.visible(global_position + Vector3.UP * 1.3, city.hero.global_position + Vector3.UP, [get_rid()]):
		city.seen = true
	ai_timer -= delta
	if ai_route.is_empty() or ai_index >= ai_route.size() or (police_ai and ai_timer < 0):
		var destination: Vector3 = city.last_seen_position if police_ai else city.routes.road.get_point_position(randi() % 20)
		ai_route = city.routes.road_path(global_position, destination, -global_basis.z)
		ai_index = 0
		ai_timer = 5
	if ai_route.is_empty():
		return Vector3(0, 1, 0)
	var target := ai_route[mini(ai_index, ai_route.size() - 1)]
	var difference := target - global_position
	difference.y = 0
	if difference.length() < 7 and ai_index < ai_route.size() - 1:
		ai_index += 1
		target = ai_route[ai_index]
		difference = target - global_position
		difference.y = 0
	elif difference.length() < 6:
		ai_index = ai_route.size()
	if overtake_index < overtake.size():
		target = overtake[overtake_index]
		if target.distance_to(global_position) < 3:
			overtake_index += 1
		if overtake_index < overtake.size():
			target = overtake[overtake_index]
			difference = target - global_position
			difference.y = 0
	var angle := angle_difference(rotation.y, atan2(-difference.x, -difference.z))
	var desired_speed := 13.0 if police_ai else 8.5
	desired_speed = minf(desired_speed, 3.5 + 9 * maxf(0, 1 - absf(angle) / 0.8))
	if overtake_index < overtake.size():
		desired_speed = minf(desired_speed, 4.5)
	waiting_red = false
	var forward := -global_basis.z
	if not police_ai:
		var axis := 0 if absf(forward.z) > absf(forward.x) else 1
		if not get_parent().signal_green(axis):
			for id in city.routes.road.get_point_ids():
				var diff: Vector3 = city.routes.road.get_point_position(id) - global_position
				var along := diff.dot(forward)
				var side := absf(diff.cross(forward).y)
				var stop_line := dimensions.z * 0.5 + 4.5
				if side < 6 and along > stop_line - 2 and along < stop_line + maxf(5, speed * speed / 18):
					desired_speed = 0
					waiting_red = true
	var from := global_position + Vector3.UP * 0.9
	var ray := PhysicsRayQueryParameters3D.create(from, from + forward * (dimensions.z * 0.5 + 2 + absf(speed) * 0.5), 3, [get_rid()])
	var obstacle := get_world_3d().direct_space_state.intersect_ray(ray)
	if not obstacle.is_empty():
		desired_speed = 0
		var other = obstacle.collider
		if other.is_in_group("vehicles") and not other.ai_driver and not other.occupied and overtake_index >= overtake.size():
			var side := -global_basis.x * 3.8
			var clearance: float = (dimensions.z + other.dimensions.z) * 0.5 + 3
			var first: Vector3 = other.global_position - forward * clearance + side
			var second: Vector3 = other.global_position + forward * clearance + side
			var side_ray := PhysicsRayQueryParameters3D.create(first + Vector3.UP, second + Vector3.UP, 3, [get_rid()])
			if get_world_3d().direct_space_state.intersect_ray(side_ray).is_empty():
				overtake = PackedVector3Array([first, second])
				overtake_index = 0
	if police_ai and global_position.distance_to(city.hero.global_position) < 7:
		desired_speed = 0
	if absf(speed) < 0.3 and not waiting_red:
		ai_stuck += delta
	else:
		ai_stuck = 0
	if ai_stuck > 5:
		recovery = 0.9
		ai_stuck = 0
		ai_timer = 0
	if recovery > 0:
		recovery -= delta
		return Vector3(0, 1, -signf(angle) * 0.5)
	return Vector3(1 if speed < desired_speed - 0.3 else 0, 1 if speed > desired_speed + 0.3 else 0, clampf(angle * 1.7, -1, 1))

func _physics_process(delta: float) -> void:
	impact = move_toward(impact, 0, delta * 1.2)
	impact_cooldown = maxf(0, impact_cooldown - delta)
	previous_distance = wheel_distance
	previous_steer = steer
	var controlled: bool = occupied and not exit_requested and (life() == null or life().outcome == "")
	var controls := ai_controls(delta) if ai_driver and not occupied else Vector3.ZERO
	var gas: bool = controlled and Input.is_action_pressed("move_forward") or controls.x > 0.5
	var brake: bool = controlled and Input.is_action_pressed("move_back") or controls.y > 0.5
	var parking: bool = (not occupied and not ai_driver) or exit_requested or (occupied and not controlled)
	var handbrake: bool = controlled and Input.is_action_pressed("jump")
	var before_speed := speed
	var max_speed: float = DATA[kind][2]
	var acceleration: float = DATA[kind][3]
	if parking:
		speed = move_toward(speed, 0, 30 * delta)
	elif handbrake:
		speed = move_toward(speed, 0, 7.5 * delta)
	elif gas:
		speed = move_toward(speed, max_speed if speed > -0.5 else 0.0, (acceleration if speed > -0.5 else 22.0) * delta)
	elif brake:
		if ai_driver and recovery <= 0:
			speed = move_toward(speed, 0, 20 * delta)
		else:
			speed = move_toward(speed, 0.0 if speed > 0.5 else -7.0, (24.0 if speed > 0.5 else acceleration * 0.65) * delta)
	else:
		speed = move_toward(speed, 0, (1.2 + absf(speed) * 0.05) * delta)
	var input_steer := Input.get_axis("move_right", "move_left") if controlled else controls.z
	var max_steer := lerpf(0.55, 0.18, clampf(absf(speed) / 32.0, 0, 1))
	steer = move_toward(steer, input_steer * max_steer, 1.8 * delta)
	if is_on_floor() and absf(speed) > 0.05:
		var turn := speed / wheelbase * tan(steer) * delta * (1.65 if handbrake else 1.0)
		var proposed := global_transform
		proposed.basis = Basis(Vector3.UP, rotation.y + turn)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = rotation_probe
		query.transform = proposed * Transform3D(Basis.IDENTITY, Vector3(0, dimensions.y * 0.5 + 0.08, 0))
		query.collision_mask = 3
		query.exclude = [get_rid()]
		if get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			rotation.y += turn
		# Заблокированный поворот не запрещает отъехать от стены назад.
	var forward := -global_basis.z
	var desired := forward * speed
	var grip := 1.1 if handbrake else 11.0
	planar_velocity = planar_velocity.lerp(desired, 1.0 - exp(-grip * delta))
	if parking:
		planar_velocity = planar_velocity.move_toward(Vector3.ZERO, 30 * delta)
	if handbrake:
		planar_velocity = planar_velocity.move_toward(Vector3.ZERO, 1.5 * delta)
	drifting = handbrake and absf(planar_velocity.dot(global_basis.x)) > 0.7
	velocity.x = planar_velocity.x
	velocity.z = planar_velocity.z
	velocity.y = maxf(velocity.y - 24 * delta, -20) if not is_on_floor() else 0.0
	var step := Vector3(velocity.x, 0, velocity.z) * delta
	if is_on_floor() and step.length_squared() > 0.00001 and test_move(global_transform, step):
		var raised := global_transform
		raised.origin.y += 0.32
		if not test_move(global_transform, Vector3.UP * 0.32) and not test_move(raised, step):
			global_position.y += 0.32
	var origin := global_position
	var incoming := Vector3(velocity.x, 0, velocity.z)
	move_and_slide()
	var displacement := global_position - origin
	wheel_distance += displacement.dot(forward)
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var normal := collision.get_normal()
		var closing := maxf(0, -incoming.dot(normal))
		var other = collision.get_collider()
		if other != null and other.has_method("take_damage") and other.is_in_group("people") and closing > 2.8:
			other.take_damage(closing * 18, global_position, occupied)
		if other == (life().hero if life() != null else null) and closing > 3:
			life().damage(closing * 3)
		if absf(normal.y) < 0.65:
			if closing > 0.01:
				planar_velocity = planar_velocity.slide(normal)
			if closing > 1.8 and impact_cooldown <= 0:
				impact = clampf(closing / 10.0, 0.35, 1)
				impact_cooldown = 0.65
				planar_velocity += normal * minf(closing * 0.28, 3.5)
				if life() != null:
					life().car_impact(self, collision.get_position(), normal, closing)
			if closing > 0.01:
				speed = planar_velocity.dot(forward)
	if is_zero_approx(speed) and planar_velocity.length() < 0.03:
		planar_velocity = Vector3.ZERO
	var gear_ratio := fmod(absf(speed), 8.0) / 8.0
	rpm = lerpf(rpm, 850.0 + gear_ratio * 3300.0 + (900.0 if gas else 0), 1.0 - exp(-5 * delta))
	if not is_finite(position.y) or position.y < -10:
		position = Vector3(64, 0.4, 20)
		velocity = Vector3.ZERO
		planar_velocity = Vector3.ZERO
		speed = 0
		reset_physics_interpolation()

func _process(delta: float) -> void:
	var fraction := Engine.get_physics_interpolation_fraction()
	model.global_transform = get_global_transform_interpolated() * model_rest
	var render_distance := lerpf(previous_distance, wheel_distance, fraction)
	var render_steer := lerpf(previous_steer, steer, fraction)
	for i in 4:
		spins[i] = -render_distance / float(DATA[kind][1][i])
		wheels[i].quaternion = Quaternion(Vector3.UP, render_steer if i < 2 else 0) * Quaternion(Vector3.RIGHT, spins[i])
	if body:
		var pitch := sin(Time.get_ticks_msec() * 0.065) * impact * 0.065
		body.transform = body_rest * Transform3D(Basis(Vector3.RIGHT, pitch), Vector3.ZERO)
	if police_ai:
		for i in beacons.size():
			beacons[i].light_energy = 5.0 if (int(Time.get_ticks_msec() / 180) + i) % 2 == 0 else 0.0
	if ai_driver and not occupied:
		motor.pitch_scale = 0.65 + absf(speed) * 0.055
	if not occupied or playback == null:
		return
	var frames := playback.get_frames_available()
	for i in frames:
		sound_rpm = lerpf(sound_rpm, rpm, 0.001)
		sound_gain = move_toward(sound_gain, 0.25, 1.0 / 22050)
		phase = fmod(phase + (sound_rpm / 60.0 * 2.0) / 22050.0, 1.0)
		var wave := sin(TAU * phase) * 0.56 + sin(TAU * phase * 2) * 0.26 + sin(TAU * phase * 4) * 0.1
		var sample := wave * sound_gain
		playback.push_frame(Vector2(sample, sample))

func approach_distance(point: Vector3) -> float:
	var local := to_local(point)
	var nearest := Vector3(clampf(local.x, -dimensions.x / 2, dimensions.x / 2), clampf(local.y, 0, dimensions.y), clampf(local.z, -dimensions.z / 2, dimensions.z / 2))
	return local.distance_to(nearest)

func exit_position() -> Vector3:
	for side in [-1.0, 1.0]:
		for z_offset in [-0.18, 0.18]:
			var point := to_global(Vector3(side * (dimensions.x * 0.5 + 0.7), 0, dimensions.z * z_offset))
			var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2, point - Vector3.UP * 2, 1, [get_rid()])
			var ground := get_world_3d().direct_space_state.intersect_ray(ray)
			if ground.is_empty() or ground.normal.y < 0.7:
				continue
			if absf(ground.position.y - global_position.y) > 0.65 or ground.collider.is_in_group("vehicles"):
				continue
			point.y = ground.position.y + 0.03
			var query := PhysicsShapeQueryParameters3D.new()
			var capsule := CapsuleShape3D.new()
			capsule.height = 1.8
			capsule.radius = 0.34
			query.shape = capsule
			query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.9)
			query.collision_mask = 1
			if get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
				return point
	return Vector3.INF
