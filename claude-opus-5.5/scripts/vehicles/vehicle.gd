class_name Vehicle
extends RigidBody3D
## Drivable car built on a RigidBody3D with ray-cast suspension and a simple tyre model.
## Model front is −Z, left side −X (assets/README.md). Wheel pivots spin around local X.
## Driven by the player, by an AIDriver, or parked (brakes on).

signal impacted(strength: float)

const LAYER_VEHICLE := 8
const GROUND_MASK := 1           # world geometry the wheels stand on
const TRAVEL := 0.22             # suspension travel above the rest position, m
const STATIC_COMP := 0.09        # spring compression at rest, m
const DAMPING_RATIO := 0.4
const DROOP := 0.12              # how far a wheel can hang below rest
const UPRIGHT_STRENGTH := 6.0
const MAX_HEALTH := 100.0

# Wheel radii from assets/README.md: FL, FR, RL, RR.
const RADII := {
	"sedan": [0.353220274, 0.353242327, 0.343094212, 0.343344008],
	"sportscar": [0.366144482, 0.380233066, 0.382972428, 0.384811932],
	"supercar": [0.379739736, 0.386856672, 0.369667408, 0.363394208],
	"convertible": [0.328507321, 0.328708461, 0.324688286, 0.324766374],
	"taxi": [0.399750943, 0.407335141, 0.374577982, 0.374324579],
	"police": [0.372256828, 0.371432157, 0.367813478, 0.367500195],
	"ambulance": [0.457517049, 0.456486186, 0.423194304, 0.423483740],
	"pickup": [0.415802891, 0.415904764, 0.393622942, 0.393654333],
	"van": [0.432583465, 0.432938659, 0.433780751, 0.432495698],
	"bus": [0.668566187, 0.663274761, 0.642835199, 0.640541751],
}

# mass kg, engine force N, top speed m/s, max steer rad, drive (0 rwd, 1 awd, 2 fwd), grip, cylinders
const SPECS := {
	"sedan": [1400.0, 7500.0, 46.0, 0.6, 2, 1.25, 4],
	"sportscar": [1300.0, 10000.0, 58.0, 0.58, 0, 1.4, 6],
	"supercar": [1350.0, 12500.0, 68.0, 0.55, 1, 1.5, 8],
	"convertible": [1300.0, 8000.0, 50.0, 0.6, 0, 1.3, 6],
	"taxi": [1500.0, 7500.0, 45.0, 0.6, 0, 1.25, 4],
	"police": [1600.0, 10500.0, 57.0, 0.58, 0, 1.35, 8],
	"ambulance": [3200.0, 14000.0, 38.0, 0.55, 0, 1.15, 8],
	"pickup": [2000.0, 10000.0, 43.0, 0.58, 0, 1.2, 8],
	"van": [2400.0, 10500.0, 38.0, 0.55, 0, 1.15, 6],
	"bus": [9000.0, 32000.0, 27.0, 0.6, 0, 1.15, 6],
}

static var _engine_loop: AudioStreamWAV
static var _siren_stream: AudioStreamWAV

var model_id := ""
var occupied := false            # player is driving
var ai: AIDriver = null          # NPC driver (null = nobody inside)
var size := Vector3.ONE          # body bounds in vehicle space
var body_center := Vector3.ZERO
var speed := 0.0                 # forward speed, m/s (negative = reversing)
var rpm := 900.0
var throttle_input := 0.0
var health := MAX_HEALTH
var wrecked := false
var siren_on := false
var spawned_by_traffic := false

var _wheels: Array[Dictionary] = []
var _engine_force := 7000.0
var _max_speed := 45.0
var _max_steer := 0.6
var _drive := 0
var _grip := 1.25
var _steer := 0.0
var _spring_k := 0.0
var _spring_c := 0.0
var _prev_velocity := Vector3.ZERO
var _impact_cooldown := 0.0
var _upside_down_time := 0.0
var _gear := 1
var _audio: EngineAudio
var _ai_audio: AudioStreamPlayer3D
var _crash_player: AudioStreamPlayer3D
var _body: Node3D
var _body_mesh: MeshInstance3D
var _bend := Vector3.ZERO
var _body_base := Transform3D.IDENTITY
var _smoke: GPUParticles3D
var _smoke_kind := ""
var _fire_t := -1.0
var _siren: AudioStreamPlayer3D
var _lights: Array[MeshInstance3D] = []
var _light_omni: OmniLight3D
var _light_t := 0.0


func setup(id: String, scene: PackedScene) -> void:
	model_id = id
	name = id.capitalize()
	var spec: Array = SPECS[id]
	mass = spec[0]
	_engine_force = spec[1]
	_max_speed = spec[2]
	_max_steer = spec[3]
	_drive = spec[4]
	_grip = spec[5]
	collision_layer = LAYER_VEHICLE
	collision_mask = 1 | 4 | LAYER_VEHICLE
	continuous_cd = not "--noccd" in OS.get_cmdline_user_args()
	can_sleep = true
	linear_damp = 0.02
	angular_damp = 0.6
	var pm := PhysicsMaterial.new()
	pm.friction = 0.4
	pm.bounce = 0.05
	physics_material_override = pm

	var model: Node3D = scene.instantiate()
	add_child(model)
	for gi in model.find_children("*", "GeometryInstance3D", true, false):
		gi.visibility_range_end = 220.0
	_body = model.find_child("body", true, false) as Node3D
	_body_base = _body.transform
	_body_mesh = model.find_child("body_mesh", true, false) as MeshInstance3D
	var aabb: AABB = CityBuilder.xf_to(_body_mesh, self) * _body_mesh.get_aabb()
	size = aabb.size
	body_center = aabb.get_center()
	var radii: Array = RADII[id]
	var names := ["wheel_fl", "wheel_fr", "wheel_rl", "wheel_rr"]
	for i in 4:
		var pivot := model.find_child(names[i], true, false) as Node3D
		var pos: Vector3 = CityBuilder.xf_to(pivot, self).origin
		_wheels.append({
			"node": pivot, "base_pos": pivot.position, "pos": pos, "radius": radii[i],
			"front": i < 2, "left": i % 2 == 0, "spin": 0.0, "susp": TRAVEL, "contact": false,
		})
	var min_r: float = radii.min()
	# Collision: lower body box + cabin box for cars, one box for tall vehicles.
	var bottom := maxf(aabb.position.y, min_r * 0.8)
	var top := aabb.end.y
	if size.y > 2.0:
		_add_box(Vector3(size.x * 0.96, top - bottom, size.z * 0.98), Vector3(body_center.x, (top + bottom) * 0.5, body_center.z))
	else:
		var split := bottom + (top - bottom) * 0.5
		_add_box(Vector3(size.x * 0.96, split - bottom, size.z * 0.98), Vector3(body_center.x, (split + bottom) * 0.5, body_center.z))
		_add_box(Vector3(size.x * 0.82, top - split, size.z * 0.55), Vector3(body_center.x, (top + split) * 0.5, body_center.z + size.z * 0.05))
	# Low centre of mass keeps it planted.
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(body_center.x, min_r * 0.9, body_center.z)
	var wheel_mass := mass / 4.0
	_spring_k = wheel_mass * 9.8 / STATIC_COMP
	_spring_c = 2.0 * DAMPING_RATIO * sqrt(_spring_k * wheel_mass)

	_audio = EngineAudio.new()
	_audio.cylinders = spec[6]
	_audio.position = Vector3(0, 0.6, body_center.z - size.z * 0.3)
	add_child(_audio)
	_crash_player = AudioStreamPlayer3D.new()
	_crash_player.stream = EngineAudio.crash_stream()
	_crash_player.unit_size = 12.0
	add_child(_crash_player)
	if id == "police":
		_add_lightbar()


func _add_box(box_size: Vector3, center: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box_size
	cs.shape = bs
	cs.position = center
	add_child(cs)


func _add_lightbar() -> void:
	## Red/blue flashers on the roof plus a coloured light, toggled with the siren.
	for i in 2:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.42, 0.12, 0.22)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		var c := Color(1.0, 0.1, 0.1) if i == 0 else Color(0.15, 0.3, 1.0)
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.0
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(body_center.x + (-0.28 if i == 0 else 0.28), body_center.y + size.y * 0.5 + 0.02, body_center.z + size.z * 0.02)
		add_child(mi)
		_lights.append(mi)
	_light_omni = OmniLight3D.new()
	_light_omni.omni_range = 9.0
	_light_omni.light_energy = 0.0
	_light_omni.shadow_enabled = false
	_light_omni.position = Vector3(body_center.x, body_center.y + size.y * 0.5 + 0.4, body_center.z)
	add_child(_light_omni)


func set_siren(on: bool) -> void:
	if model_id != "police" or siren_on == on:
		return
	siren_on = on
	if on:
		if _siren == null:
			if _siren_stream == null:
				_siren_stream = Fx.make_siren()
			_siren = AudioStreamPlayer3D.new()
			_siren.stream = _siren_stream
			_siren.unit_size = 18.0
			_siren.max_distance = 220.0
			_siren.volume_db = -3.0
			add_child(_siren)
		_siren.play()
	elif _siren:
		_siren.stop()
	if not on:
		for l in _lights:
			(l.material_override as StandardMaterial3D).emission_energy_multiplier = 0.0
		_light_omni.light_energy = 0.0


func _ready() -> void:
	_prev_velocity = linear_velocity


## Seat/exit helpers -------------------------------------------------------------

func set_occupied(value: bool) -> void:
	occupied = value
	sleeping = false
	_audio.set_running(value and not wrecked)
	if value and _ai_audio:
		_ai_audio.stop()


func set_ai(driver: AIDriver) -> void:
	ai = driver
	sleeping = false
	if driver and not occupied:
		if _ai_audio == null:
			if _engine_loop == null:
				_engine_loop = Fx.make_engine_loop()
			_ai_audio = AudioStreamPlayer3D.new()
			_ai_audio.stream = _engine_loop
			_ai_audio.unit_size = 5.0
			_ai_audio.max_distance = 45.0
			_ai_audio.volume_db = -8.0
			add_child(_ai_audio)
		_ai_audio.play()
	elif _ai_audio:
		_ai_audio.stop()


func steer_limit() -> float:
	return _max_steer / (1.0 + absf(speed) / 14.0)


func exit_points() -> Array[Vector3]:
	## Candidate positions (vehicle space) for the driver to step out: driver door first.
	var hx := size.x * 0.5 + 0.75
	var door_z := body_center.z - size.z * 0.12
	return [
		Vector3(body_center.x - hx, 0.2, door_z), Vector3(body_center.x + hx, 0.2, door_z),
		Vector3(body_center.x, 0.2, body_center.z + size.z * 0.5 + 1.0),
		Vector3(body_center.x, 0.2, body_center.z - size.z * 0.5 - 1.0),
		Vector3(body_center.x, size.y + 0.3, body_center.z),
	]


func driver_door() -> Vector3:
	return global_transform * exit_points()[0]


func distance_to_point(p: Vector3) -> float:
	## Horizontal distance from a world point to the car body outline.
	var local := global_transform.affine_inverse() * p
	var half := size * 0.5
	var d := Vector2(maxf(absf(local.x - body_center.x) - half.x, 0.0), maxf(absf(local.z - body_center.z) - half.z, 0.0))
	return d.length()


## Damage ------------------------------------------------------------------------

func take_damage(amount: float, at: Vector3) -> void:
	if wrecked:
		return
	health -= amount
	sleeping = false
	_update_damage_fx()
	if health <= 0.0:
		health = 0.0
		if _fire_t < 0.0:
			_fire_t = 4.0   # burns a few seconds, then explodes
	if at != Vector3.ZERO and amount > 3.0:
		Fx.inst.sparks(at, (at - global_position).normalized(), 10)


func _update_damage_fx() -> void:
	var kind := ""
	if health <= 0.0:
		kind = "fire"
	elif health < 30.0:
		kind = "black"
	elif health < 60.0:
		kind = "smoke"
	if kind == _smoke_kind:
		return
	_smoke_kind = kind
	if _smoke:
		_smoke.queue_free()
		_smoke = null
	if kind != "":
		_smoke = Fx.inst.make_emitter(kind)
		# From under the hood (front of the car).
		_smoke.position = Vector3(body_center.x, body_center.y + size.y * 0.25, body_center.z - size.z * 0.33)
		add_child(_smoke)
		_smoke.emitting = true


func _explode() -> void:
	wrecked = true
	_fire_t = -1.0
	set_siren(false)
	if _ai_audio:
		_ai_audio.stop()
	_audio.set_running(false)
	ai = null
	var center := global_transform * body_center
	Fx.inst.explosion(center)
	apply_central_impulse(Vector3.UP * mass * 6.0)
	apply_torque_impulse(Vector3(randf() - 0.5, 0, randf() - 0.5) * mass * 4.0)
	# Burnt shell: darken the body with an overlay.
	var burnt := StandardMaterial3D.new()
	burnt.albedo_color = Color(0.03, 0.03, 0.03, 0.82)
	burnt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	burnt.roughness = 1.0
	for gi in find_children("*", "GeometryInstance3D", true, false):
		if gi is MeshInstance3D and gi != _smoke:
			(gi as MeshInstance3D).material_overlay = burnt
	_smoke_kind = ""
	_update_damage_fx_wreck()
	Game.inst.explosion(center, 7.0, self)


func _update_damage_fx_wreck() -> void:
	if _smoke:
		_smoke.queue_free()
	_smoke = Fx.inst.make_emitter("black")
	_smoke.position = body_center
	add_child(_smoke)
	_smoke.emitting = true


## Physics ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_tick(delta)
	Game.prof_add("vehicle", Time.get_ticks_usec() - t0)


func _tick(delta: float) -> void:
	if sleeping and not occupied and ai == null:
		return
	var throttle := 0.0
	var brake := 0.0
	var steer_in := 0.0
	var handbrake := false
	var xf := global_transform
	var fwd := -xf.basis.z
	speed = linear_velocity.dot(fwd)
	if wrecked:
		brake = 0.6
	elif occupied:
		var accel_in := Input.get_action_strength("move_forward")
		var back_in := Input.get_action_strength("move_back")
		steer_in = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
		handbrake = Input.is_action_pressed("handbrake")
		if accel_in > 0.0:
			if speed < -0.5:
				brake = accel_in
			else:
				throttle = accel_in
		if back_in > 0.0:
			if speed > 0.5:
				brake = back_in
			else:
				throttle = -back_in * 0.6
	elif ai:
		var c := ai.compute(delta)
		throttle = c[0]
		brake = c[1]
		steer_in = c[2]
		handbrake = c[3]
	else:
		brake = 1.0
	throttle_input = absf(throttle)
	if health < 60.0:
		throttle *= 0.45 + 0.55 * health / 60.0   # damaged engine loses power

	# Steering: smooth, and less lock at speed.
	_steer = move_toward(_steer, steer_in * steer_limit(), delta * 2.5)

	var state := get_world_3d().direct_space_state
	var up := xf.basis.y
	var com_world := xf * center_of_mass
	var driven := 0
	for w in _wheels:
		if _drive == 1 or (_drive == 0 and not w.front) or (_drive == 2 and w.front):
			driven += 1
	var grounded := 0
	for w in _wheels:
		var r: float = w.radius
		var anchor: Vector3 = xf * (w.pos + Vector3(0, TRAVEL, 0))
		var ray_len: float = TRAVEL + DROOP + r
		var q := PhysicsRayQueryParameters3D.create(anchor, anchor - up * ray_len, GROUND_MASK, [get_rid()])
		var hit := state.intersect_ray(q)
		if hit.is_empty():
			w.contact = false
			w.susp = TRAVEL + DROOP
			if w.front or not handbrake:
				w.spin -= speed / r * delta
			continue
		w.contact = true
		grounded += 1
		var contact: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		var susp: float = anchor.distance_to(contact) - r
		w.susp = susp
		var comp: float = TRAVEL + STATIC_COMP - susp
		var pv := linear_velocity + angular_velocity.cross(contact - com_world)
		var f_susp := maxf(0.0, _spring_k * comp - _spring_c * pv.dot(up))
		f_susp = minf(f_susp, mass * 9.8 * 3.0)
		apply_force(up * f_susp, contact - xf.origin)

		# Tyre frame on the ground plane.
		var wf := fwd
		if w.front:
			wf = wf.rotated(up, _steer)
		wf = (wf - normal * wf.dot(normal)).normalized()
		var wr := wf.cross(normal).normalized()
		var v_long := pv.dot(wf)
		var v_lat := pv.dot(wr)
		var mu: float = _grip
		var rear_locked: bool = handbrake and not w.front
		if rear_locked:
			mu *= 0.55
		var wheel_mass := mass / 4.0
		# Lateral: cancel sideways slip, limited by grip.
		var f_lat := -v_lat * wheel_mass / delta * 0.55
		# Longitudinal: engine, brakes, rolling resistance.
		var f_long := 0.0
		var is_driven: bool = _drive == 1 or (_drive == 0 and not w.front) or (_drive == 2 and w.front)
		if is_driven and throttle != 0.0:
			var top := _max_speed if throttle > 0.0 else _max_speed * 0.3
			var falloff := clampf(1.0 - absf(speed) / top, 0.0, 1.0)
			f_long += throttle * _engine_force / driven * (0.35 + 0.65 * falloff) * (1.0 if absf(speed) < top else 0.0)
		var stop_force := absf(v_long) * wheel_mass / delta * 0.5
		if brake > 0.0:
			f_long -= signf(v_long) * minf(brake * mass * 9.0 / 4.0, stop_force)
		if rear_locked:
			f_long -= signf(v_long) * minf(mass * 9.8 * 0.5 / 4.0, stop_force)
		f_long -= v_long * 12.0
		var f := wr * f_lat + wf * f_long
		var f_max := mu * f_susp
		if f.length() > f_max:
			f = f.normalized() * f_max
		apply_force(f, contact - xf.origin)
		if not rear_locked:
			w.spin -= v_long / r * delta

	# Aerodynamic drag
	apply_central_force(-linear_velocity * linear_velocity.length() * 0.45)
	_keep_upright(delta, grounded)
	_detect_impact(delta)
	_update_engine(delta)
	_update_wheel_visuals()
	if _fire_t > 0.0:
		_fire_t -= delta
		if _fire_t <= 0.0:
			_explode()

	# Let parked cars fall asleep once settled.
	if not occupied and ai == null and grounded == 4 and linear_velocity.length() < 0.05 and angular_velocity.length() < 0.05 and _fire_t < 0.0:
		sleeping = true


func _process(delta: float) -> void:
	if siren_on and _lights.size() == 2:
		_light_t += delta
		var phase := int(_light_t * 6.0) % 2
		(_lights[0].material_override as StandardMaterial3D).emission_energy_multiplier = 4.0 if phase == 0 else 0.2
		(_lights[1].material_override as StandardMaterial3D).emission_energy_multiplier = 4.0 if phase == 1 else 0.2
		_light_omni.light_color = Color(1.0, 0.15, 0.15) if phase == 0 else Color(0.2, 0.35, 1.0)
		_light_omni.light_energy = 2.5
	if _ai_audio and _ai_audio.playing:
		_ai_audio.pitch_scale = clampf(0.6 + absf(speed) / 12.0, 0.6, 2.2)


func _keep_upright(delta: float, grounded: int) -> void:
	## Counteracts roll/pitch so the car doesn't flip on flat ground; rights it if stuck on its roof.
	var up := global_transform.basis.y
	var axis := up.cross(Vector3.UP)
	var strength := UPRIGHT_STRENGTH if grounded < 4 else UPRIGHT_STRENGTH * 0.4
	var inertia_guess := mass * (size.x * size.x + size.y * size.y) / 12.0
	apply_torque(axis * strength * strength * inertia_guess)
	# Damp roll/pitch rates (not yaw).
	var av := angular_velocity
	var yaw_rate := av.project(up)
	apply_torque(-(av - yaw_rate) * inertia_guess * 2.0)
	if up.y < 0.3:
		_upside_down_time += delta
		if _upside_down_time > 2.0 and linear_velocity.length() < 2.0:
			var yaw := global_rotation.y
			global_transform = Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3.UP * 1.5)
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			_upside_down_time = 0.0
	else:
		_upside_down_time = 0.0


func _detect_impact(delta: float) -> void:
	_impact_cooldown -= delta
	var dv := linear_velocity - _prev_velocity
	dv.y *= 0.3   # landing bumps matter less than hitting walls
	var prev := _prev_velocity
	_prev_velocity = linear_velocity
	var strength := dv.length()
	if strength > 2.2 and _impact_cooldown <= 0.0:
		_impact_cooldown = 0.35
		_crash_player.volume_db = linear_to_db(clampf(strength / 12.0, 0.15, 1.0))
		_crash_player.pitch_scale = randf_range(0.8, 1.15)
		_crash_player.play()
		# Where did we hit? On the side of the car facing the old travel direction.
		var hit_dir := prev.normalized() if prev.length() > 1.0 else -dv.normalized()
		var local_dir := global_transform.basis.inverse() * hit_dir
		var local_pt := body_center + Vector3(local_dir.x * size.x * 0.5, 0.0, local_dir.z * size.z * 0.5)
		var world_pt := global_transform * local_pt
		Fx.inst.sparks(world_pt, hit_dir * -1.0, int(clampf(strength * 3.0, 10, 40)))
		Fx.inst.dust(world_pt, hit_dir * -1.0)
		if strength > 3.5:
			take_damage((strength - 3.0) * 3.2, Vector3.ZERO)
			_bend_body(local_dir, strength)
		impacted.emit(strength)


func _bend_body(local_dir: Vector3, strength: float) -> void:
	## Cheap "crumple": the body shell twists and sinks a little more with every big hit.
	var k := clampf(strength / 25.0, 0.0, 1.0)
	_bend.x = clampf(_bend.x + local_dir.z * 0.02 * k, -0.06, 0.06)
	_bend.z = clampf(_bend.z - local_dir.x * 0.025 * k, -0.07, 0.07)
	_bend.y = clampf(_bend.y + randf_range(-0.03, 0.03) * k, -0.05, 0.05)
	_body.transform = _body_base * Transform3D(Basis.from_euler(_bend), Vector3(0, -absf(_bend.x + _bend.z) * 0.6, 0))


func _update_engine(delta: float) -> void:
	# Automatic gearbox: 5 gears spread over the top speed.
	var ratio := absf(speed) / _max_speed
	var gear_f := ratio * 5.0
	_gear = clampi(int(gear_f) + 1, 1, 5)
	var in_gear := clampf(gear_f - (_gear - 1), 0.0, 1.0)
	var target_rpm := 900.0 + in_gear * 4800.0 + (1.0 - in_gear) * 600.0 * float(_gear > 1)
	if absf(speed) < 1.0:
		target_rpm = 900.0 + throttle_input * 2600.0
	rpm = move_toward(rpm, target_rpm, delta * 9000.0)
	_audio.rpm = rpm
	_audio.throttle = throttle_input


func _update_wheel_visuals() -> void:
	for w in _wheels:
		var node: Node3D = w.node
		var offset: float = clampf(TRAVEL - w.susp, -DROOP, TRAVEL)
		node.position = w.base_pos + Vector3(0, offset, 0)
		var steer: float = _steer if w.front else 0.0
		w.spin = wrapf(w.spin, -TAU, TAU)
		node.quaternion = Quaternion(Vector3.UP, steer) * Quaternion(Vector3.RIGHT, w.spin)
