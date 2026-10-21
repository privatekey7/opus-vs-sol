extends CharacterBody3D

const WALK_SPEED := 3.8
const RUN_SPEED := 7.5
var yaw := 0.0
var pitch := -0.16
var visual: Node3D
var pivot: Node3D
var arm: ShapeCast3D
var camera: Camera3D
var animator: AnimationPlayer
var clips: Dictionary = {}
var current_clip := ""
var vehicle = null
var camera_distance := 5.0
var notice := ""
var notice_time := 0.0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.35
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	visual = load("res://assets/people/hero.glb").instantiate()
	visual.scale = Vector3.ONE * 1.7444954588
	visual.rotation.y = yaw + PI
	add_child(visual)
	animator = visual.find_children("*", "AnimationPlayer", true, false)[0]
	for clip in animator.get_animation_list():
		var short_name: String = String(clip).get_slice("/", String(clip).get_slice_count("/") - 1)
		clips[short_name] = clip
		if short_name in ["idle", "walk", "run", "aim"]:
			animator.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	for mesh in visual.find_children("*", "MeshInstance3D", true, false):
		mesh.lod_bias = 0.5
	pivot = Node3D.new()
	add_child(pivot)
	pivot.top_level = true
	pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	arm = ShapeCast3D.new()
	arm.target_position = Vector3(0, 0, 5)
	arm.enabled = false
	arm.margin = 0.22
	arm.collision_mask = 1
	var camera_shape := SphereShape3D.new()
	camera_shape.radius = 0.24
	arm.shape = camera_shape
	arm.add_exception(self)
	pivot.add_child(arm)
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.near = 0.08
	camera.far = 650.0
	pivot.add_child(camera)
	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	play_clip("idle")
	update_camera(0.0)

func _process(delta: float) -> void:
	notice_time = maxf(0, notice_time - delta)
	update_camera(delta)

func update_camera(delta: float) -> void:
	var city = get_parent().get("life")
	var aiming: bool = city != null and city.combat != null and city.combat.aiming
	var target: Node3D = self if vehicle == null else vehicle
	var follow := target.get_global_transform_interpolated()
	var height := 1.55 if vehicle == null else maxf(1.6, vehicle.dimensions.y * 0.7)
	var distance := 5.0 if vehicle == null else maxf(6.5, vehicle.dimensions.z * 0.9 + 2.0)
	if aiming:
		distance = 3.2
	pivot.global_position = follow.origin + Vector3.UP * height
	var view_yaw := yaw if vehicle == null else follow.basis.get_euler().y + yaw
	if aiming:
		var right := Basis(Vector3.UP, view_yaw).x
		var ray := PhysicsRayQueryParameters3D.create(pivot.global_position, pivot.global_position + right * 0.6, 1, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		var offset := 0.55 if hit.is_empty() else maxf(0, pivot.global_position.distance_to(hit.position) - 0.26)
		pivot.global_position += right * offset
	pivot.rotation = Vector3(pitch, view_yaw, 0)
	arm.target_position.z = distance
	arm.force_shapecast_update()
	var safe_distance := distance * arm.get_closest_collision_safe_fraction()
	if safe_distance < camera_distance or delta <= 0:
		camera_distance = safe_distance
	else:
		camera_distance = lerpf(camera_distance, safe_distance, 1.0 - exp(-8.0 * delta))
	camera.position = Vector3(0, 0, camera_distance)
	camera.fov = lerpf(camera.fov, 55.0 if aiming else 68.0, 1.0 - exp(-10 * delta))
	if vehicle != null and vehicle.impact > 0.01:
		# Вибрация от удара направлена внутрь безопасной длины камеры.
		camera.position.z -= absf(sin(Time.get_ticks_msec() * 0.055)) * vehicle.impact * 0.65
		camera.rotation.z = sin(Time.get_ticks_msec() * 0.045) * vehicle.impact * 0.035
	else:
		camera.rotation.z = 0

func enter_vehicle(car) -> void:
	vehicle = car
	visual.hide()
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	arm.add_exception(car)
	yaw = 0
	pitch = -0.16
	car.start_engine()

func leave_vehicle(point: Vector3) -> void:
	var old_car = vehicle
	yaw += old_car.rotation.y
	old_car.speed = 0.0
	old_car.planar_velocity = Vector3.ZERO
	old_car.stop_engine()
	arm.remove_exception(old_car)
	vehicle = null
	global_position = point
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	collision_layer = 2
	collision_mask = 1
	visual.show()
	visual.rotation.y = yaw + PI
	play_clip("idle")

func _unhandled_input(event: InputEvent) -> void:
	var city = get_parent().get("life")
	if city != null:
		if city.outcome != "":
			return
		city.combat.input(event)
	if event.is_action_pressed("interact") and not event.is_echo():
		get_parent().interact()
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.0025
		pitch = clampf(pitch - event.relative.y * 0.0022, -1.05, 0.55)

func _physics_process(delta: float) -> void:
	var city = get_parent().get("life")
	if city != null and city.outcome != "":
		velocity = Vector3.ZERO
		return
	if vehicle != null:
		global_position = vehicle.global_position
		if vehicle.exit_requested and vehicle.planar_velocity.length() < 0.5 and absf(vehicle.speed) < 0.5:
			get_parent().try_exit_vehicle()
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Basis(Vector3.UP, yaw) * Vector3(input.x, 0, input.y)
	var running := Input.is_action_pressed("sprint")
	var speed := RUN_SPEED if running else WALK_SPEED
	var target := direction * speed
	velocity.x = move_toward(velocity.x, target.x, 28.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 28.0 * delta)
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = 8.0
	# Небольшой подъём на бордюр; стены остаются непреодолимыми.
	var horizontal_step := Vector3(velocity.x, 0, velocity.z) * delta
	if is_on_floor() and velocity.y <= 0 and horizontal_step.length_squared() > 0.00001:
		if test_move(global_transform, horizontal_step):
			var raised := global_transform
			raised.origin.y += 0.3
			if not test_move(global_transform, Vector3.UP * 0.3) and not test_move(raised, horizontal_step):
				global_position.y += 0.3
	move_and_slide()
	var planar := Vector2(velocity.x, velocity.z).length()
	if direction.length_squared() > 0.01:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(direction.x, direction.z), 1.0 - exp(-14.0 * delta))
	var armed_pose: bool = city != null and (city.combat.aiming or city.combat.attack_time > 0)
	if armed_pose:
		visual.rotation.y = lerp_angle(visual.rotation.y, yaw + PI, 1.0 - exp(-20 * delta))
	# В наборе нет прыжка: фиксируем согнутые ноги в позе бега.
	if not is_on_floor():
		play_clip("air")
		animator.play(clips["run"])
		animator.seek(0.2, true)
		animator.pause()
	else:
		if armed_pose:
			play_clip("shoot" if city.combat.attack_time > 0 and city.combat.selected > 0 else "aim")
			if current_clip == "aim":
				animator.play(clips["aim"], 0)
				animator.seek(0.8, true)
				animator.advance(0)
			visual.rotation.y = city.combat.aim_rotation()
		else:
			play_clip("run" if planar > 4.5 else ("walk" if planar > 0.2 else "idle"))
	if global_position.y < -10.0:
		global_position = Vector3(96, 1, 22)
		velocity = Vector3.ZERO
		reset_physics_interpolation()

func play_clip(clip: String) -> void:
	if current_clip == clip:
		return
	current_clip = clip
	if clips.has(clip):
		animator.play(clips[clip], 0.18)

func take_damage(amount: float, source := Vector3.ZERO, by_player := false) -> void:
	var city = get_parent().get("life")
	if city != null:
		city.damage(amount)
