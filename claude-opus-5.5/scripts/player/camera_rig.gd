class_name CameraRig
extends Node3D
## Third-person orbit camera. Mouse rotates; a SpringArm3D keeps it out of walls.
## Follows either the hero on foot or a vehicle (then it swings in behind the car).

const MOUSE_SENS := 0.0025
const PITCH_MIN := deg_to_rad(-65)
const PITCH_MAX := deg_to_rad(40)
# In a car the camera never looks up: an arm pointing down-and-back would pass through the
# car's own body (which the spring arm ignores) and show the interior.
const PITCH_MAX_CAR := deg_to_rad(-4)
const FOLLOW_SHARPNESS := 18.0
const ONFOOT_DISTANCE := 4.2
const ONFOOT_HEIGHT := 1.6
const AIM_DISTANCE := 1.9
const SPRING_MASK := 1 | 8          # world + vehicles

var target: Node3D
var yaw := 0.0
var pitch := deg_to_rad(-12)
var camera: Camera3D
var aim := false

var _pitch_node: Node3D
var _spring: SpringArm3D
var _pivot_height := ONFOOT_HEIGHT
var _distance := ONFOOT_DISTANCE
var _mouse_idle := 10.0
var _shake := 0.0
var _aim_k := 0.0
var _recoil := 0.0          # extra pitch from weapon kick, recovers over time


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_pitch_node = Node3D.new()
	add_child(_pitch_node)
	_spring = SpringArm3D.new()
	_spring.spring_length = ONFOOT_DISTANCE
	_spring.collision_mask = SPRING_MASK
	_spring.margin = 0.15
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	_spring.shape = sphere
	_spring.position = Vector3(0.45, 0, 0)   # slight over-the-shoulder offset
	_pitch_node.add_child(_spring)
	camera = Camera3D.new()
	camera.fov = 70
	camera.far = 2500
	camera.near = 0.1
	_spring.add_child(camera)
	camera.make_current()
	if target:
		set_target(target)
		global_position = target.global_position + Vector3.UP * _pivot_height


func set_target(t: Node3D) -> void:
	target = t
	_spring.clear_excluded_objects()
	if t is CollisionObject3D:
		_spring.add_excluded_object((t as CollisionObject3D).get_rid())
	if t is Vehicle:
		var v := t as Vehicle
		_distance = clampf(v.size.z * 0.9 + 2.5, 5.5, 13.0)
		_pivot_height = v.body_center.y + v.size.y * 0.5 + 0.6
		pitch = minf(pitch, PITCH_MAX_CAR)
	else:
		_distance = ONFOOT_DISTANCE
		_pivot_height = ONFOOT_HEIGHT


func add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func add_recoil(amount: float) -> void:
	_recoil = minf(_recoil + amount, 0.25)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := MOUSE_SENS * (0.6 if aim else 1.0)
		yaw -= event.relative.x * sens
		var max_pitch := PITCH_MAX_CAR if target is Vehicle else PITCH_MAX
		pitch = clampf(pitch - event.relative.y * sens, PITCH_MIN, max_pitch)
		_mouse_idle = 0.0


func _process(delta: float) -> void:
	if not target:
		return
	_mouse_idle += delta
	var goal := target.get_global_transform_interpolated().origin + Vector3.UP * _pivot_height
	if target is Vehicle:
		# Firmer follow at speed, and swing in behind the car when the mouse is idle.
		global_position = global_position.lerp(goal, clampf(25.0 * delta, 0.0, 1.0))
		var v := target as Vehicle
		if _mouse_idle > 1.2 and absf(v.speed) > 2.0:
			var car_yaw := target.global_rotation.y
			if v.speed < -2.0:
				car_yaw += PI
			yaw = lerp_angle(yaw, car_yaw, clampf(delta * 2.5, 0.0, 1.0))
			pitch = lerpf(pitch, deg_to_rad(-10), clampf(delta * 1.5, 0.0, 1.0))
		_aim_k = 0.0
	else:
		global_position = global_position.lerp(goal, clampf(FOLLOW_SHARPNESS * delta, 0.0, 1.0))
		var hero := target as Hero
		hero.camera_yaw = yaw
		aim = hero.aiming
		_aim_k = move_toward(_aim_k, 1.0 if aim else 0.0, delta * 6.0)
	_spring.spring_length = lerpf(_distance, AIM_DISTANCE, _aim_k)
	_spring.position = Vector3(lerpf(0.45, 0.75, _aim_k), lerpf(0.0, 0.1, _aim_k), 0) if not target is Vehicle else Vector3.ZERO
	camera.fov = lerpf(70.0, 52.0, _aim_k)
	rotation = Vector3(0, yaw, 0)
	_recoil = move_toward(_recoil, 0.0, delta * maxf(_recoil * 6.0, 0.05))
	_pitch_node.rotation = Vector3(pitch + _recoil, 0, 0)
	if _shake > 0.001:
		camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.3
		camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.3
		_shake = move_toward(_shake, 0.0, delta * 2.0)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
