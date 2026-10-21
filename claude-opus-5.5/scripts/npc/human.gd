class_name Human
extends CharacterBody3D
## Pedestrian or police officer on foot. Body forward is −Z; the GLB (front +Z) is turned by PI.

enum Role { PED, COP }
enum State { WANDER, FLEE, CHASE, ATTACK, KNOCKED, DEAD, LEAVE }

const LAYER_NPC := 16
const GRAVITY := 15.0
const WALK_SPEED := 1.35
const RUN_SPEED := 4.6
const COP_RUN_SPEED := 5.3
const WALK_ANIM_SPEED := 1.6
const RUN_ANIM_SPEED := 5.2

var role := Role.PED
var state := State.WANDER
var model_id := ""
var health := 40.0
var alive := true
var dead_time := 0.0
var manager: NpcManager

var _model: Node3D
var _anim: AnimationPlayer
var _names := {}
var _current := ""
var _collision: CollisionShape3D
# Wander along a sidewalk ring
var _ring: Array = []
var _ring_i := 0
var _ring_dir := 1
# Flee / chase
var _threat := Vector3.ZERO
var _flee_t := 0.0
var _path := PackedVector3Array()
var _path_i := 0
var _repath_t := 0.0
var _stuck_t := 0.0
var _knock_t := 0.0
var _shoot_t := 1.0
var _los_t := 0.0
var _has_los := false
var _anim_skip := 0
var _weapon: Node3D


func setup(id: String, scene: PackedScene, p_role: int) -> void:
	model_id = id
	role = p_role
	collision_layer = LAYER_NPC
	collision_mask = 1 | 2 | 4 | 8
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(50)
	safe_margin = 0.02
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.75
	_collision = CollisionShape3D.new()
	_collision.shape = shape
	_collision.position.y = 0.875
	add_child(_collision)
	_model = scene.instantiate()
	_model.scale = Vector3.ONE * AnimUtil.PEOPLE_SCALE[id]
	_model.rotation.y = PI
	add_child(_model)
	for gi in _model.find_children("*", "GeometryInstance3D", true, false):
		gi.visibility_range_end = 110.0
	_anim = _model.find_children("*", "AnimationPlayer", true, false)[0]
	_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_names = AnimUtil.clip_names(_anim)
	for c in ["idle", "walk", "run"]:
		_anim.get_animation(_names[c]).loop_mode = Animation.LOOP_LINEAR
	if role == Role.COP:
		health = 70.0
		AnimUtil.make_pose_clip(_anim, _names, "aim_hold", "aim", 0.8)
		_weapon = AnimUtil.attach_weapon(_model, manager.game.scenes["pistol"], "pistol")
	_play("idle", 0.0)


func reset_at(pos: Vector3, p_state: int) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	state = p_state
	alive = true
	dead_time = 0.0
	health = 70.0 if role == Role.COP else 40.0
	collision_layer = LAYER_NPC
	_collision.disabled = false
	visible = true
	_path = PackedVector3Array()
	_current = ""
	if state == State.WANDER:
		_ring = NavGrid.inst.ring_for(pos)
		_ring_dir = 1 if randf() < 0.5 else -1
		_ring_i = _nearest_ring_corner()
	_play("idle", 0.0)
	reset_physics_interpolation()


func _nearest_ring_corner() -> int:
	var best := 0
	for i in 4:
		if global_position.distance_to(_ring[i]) < global_position.distance_to(_ring[best]):
			best = i
	return best


func _play(clip: String, blend := 0.25, speed := 1.0) -> void:
	if _current != clip:
		_current = clip
		_anim.play(_names[clip], blend)
	_anim.speed_scale = speed


## ---------------------------------------------------------------- events

func take_damage(amount: float, from_dir: Vector3, attacker: Node) -> void:
	if not alive:
		return
	health -= amount
	if role == Role.COP and attacker is Hero:
		manager.game.wanted.report("attack_cop", global_position)
	if health <= 0.0:
		die(from_dir, attacker)
	elif role == Role.PED:
		start_flee(global_position - from_dir * 5.0)


func die(_from_dir: Vector3, attacker: Node) -> void:
	if not alive:
		return
	alive = false
	state = State.DEAD
	dead_time = 0.0
	velocity = Vector3.ZERO
	collision_layer = 0
	_collision.disabled = true
	_play("death", 0.15)
	if attacker is Hero or (attacker is Vehicle and (attacker as Vehicle).occupied):
		manager.game.wanted.report("kill_cop" if role == Role.COP else "kill_ped", global_position)
	manager.alert(global_position, 25.0)


func hit_by_vehicle(v: Vehicle) -> void:
	## Called by NpcManager when a moving car runs into us.
	if not alive or state == State.KNOCKED:
		return
	var spd := absf(v.speed)
	var push := (global_position - v.global_position)
	push.y = 0
	Fx.inst.blood(global_position + Vector3.UP, Vector3.UP)
	if v.occupied:
		manager.game.wanted.report("hit_cop" if role == Role.COP else "run_over", global_position)
	if spd > 7.0:
		health = 0.0
		die(push, v)
		global_position += push.normalized() * 0.8
	else:
		health -= spd * 4.0
		state = State.KNOCKED
		_knock_t = 2.8
		velocity = Vector3.ZERO
		_play("knocked_down", 0.1)
		manager.alert(global_position, 15.0)


func start_flee(from_pos: Vector3) -> void:
	if not alive or role == Role.COP or state == State.KNOCKED:
		return
	_threat = from_pos
	_flee_t = randf_range(6.0, 10.0)
	state = State.FLEE


func thrown_out_of_car() -> void:
	## Driver dragged out by the player: falls, then runs away.
	state = State.KNOCKED
	_knock_t = 2.6
	_play("knocked_down", 0.05)


## ---------------------------------------------------------------- update

func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_tick(delta)
	Game.prof_add("human", Time.get_ticks_usec() - t0)


func _tick(delta: float) -> void:
	if state == State.DEAD:
		dead_time += delta
		_tick_anim(delta)
		return
	var game := manager.game
	var target_vel := Vector3.ZERO
	match state:
		State.WANDER:
			target_vel = _wander()
		State.FLEE:
			_flee_t -= delta
			var away := global_position - _threat
			away.y = 0
			if away.length() < 0.1:
				away = Vector3(randf() - 0.5, 0, randf() - 0.5)
			target_vel = away.normalized() * RUN_SPEED
			if _flee_t <= 0.0:
				state = State.WANDER
				_ring = NavGrid.inst.ring_for(global_position)
				_ring_i = _nearest_ring_corner()
		State.KNOCKED:
			_knock_t -= delta
			if _knock_t <= 0.0:
				if health <= 0.0:
					die(Vector3.ZERO, null)
				elif role == Role.COP:
					state = State.CHASE
				else:
					state = State.WANDER
					start_flee(game.player_position())
		State.CHASE, State.ATTACK:
			target_vel = _cop_update(delta)
		State.LEAVE:
			target_vel = _wander()
	velocity.x = target_vel.x
	velocity.z = target_vel.z
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta
	var before := global_position
	if is_on_floor() and Vector2(target_vel.x, target_vel.z).length() > 0.1:
		_try_step_up(Vector3(target_vel.x, 0, target_vel.z) * delta)
	move_and_slide()
	var hv := Vector2(target_vel.x, target_vel.z)
	if hv.length() > 0.2:
		var want := atan2(-target_vel.x, -target_vel.z)
		rotation.y = lerp_angle(rotation.y, want, clampf(delta * 8.0, 0.0, 1.0))
		# Blocked? turn around on the ring, or try a fresh path.
		var moved := (global_position - before).length() / delta
		if moved < hv.length() * 0.25:
			_stuck_t += delta
			if _stuck_t > 1.2:
				_stuck_t = 0.0
				if state == State.WANDER or state == State.LEAVE:
					_ring_dir = -_ring_dir
					_ring_i = posmod(_ring_i + _ring_dir, 4)
				_path = PackedVector3Array()
		else:
			_stuck_t = 0.0
	if state != State.KNOCKED and state != State.ATTACK:
		var spd := hv.length()
		if spd > 3.0:
			_play("run", 0.2, spd / RUN_ANIM_SPEED)
		elif spd > 0.3:
			_play("walk", 0.25, spd / WALK_ANIM_SPEED)
		else:
			_play("idle", 0.3)
	_tick_anim(delta)


func _try_step_up(motion: Vector3) -> void:
	## Climb curbs: if blocked at foot level but free 0.35 m higher, lift the body.
	var probe := motion.normalized() * maxf(motion.length(), 0.15)
	if not test_move(global_transform, probe):
		return
	var up := Vector3(0, 0.35, 0)
	if test_move(global_transform, up):
		return
	if test_move(global_transform.translated(up), probe):
		return
	global_position += up


func _tick_anim(delta: float) -> void:
	## Distant NPCs update their skeleton less often.
	var cam := get_viewport().get_camera_3d()
	var far := cam != null and cam.global_position.distance_squared_to(global_position) > 35.0 * 35.0
	_anim_skip += 1
	var every := 3 if far else 1
	if _anim_skip >= every:
		var t0 := Time.get_ticks_usec()
		_anim.advance(delta * _anim_skip)
		Game.prof_add("npc_anim", Time.get_ticks_usec() - t0)
		_anim_skip = 0


func _wander() -> Vector3:
	if _ring.is_empty():
		_ring = NavGrid.inst.ring_for(global_position)
	var target: Vector3 = _ring[_ring_i]
	var to := target - global_position
	to.y = 0
	if to.length() < 0.8:
		_ring_i = posmod(_ring_i + _ring_dir, 4)
		# Sometimes cross the street to the neighbouring block at a corner.
		if randf() < 0.25 and state == State.WANDER:
			var nxt: Vector3 = _ring[_ring_i]
			var dir := (target - nxt).normalized()
			var across := target + dir * 18.6
			if NavGrid.inst.is_walkable(across):
				var ring2 := NavGrid.inst.ring_for(across)
				_ring = ring2
				_ring_i = 0
				for i in 4:
					if (ring2[i] as Vector3).distance_to(across) < (ring2[_ring_i] as Vector3).distance_to(across):
						_ring_i = i
		return Vector3.ZERO
	return to.normalized() * WALK_SPEED


func _follow_path(goal: Vector3, delta: float, speed: float) -> Vector3:
	_repath_t -= delta
	if _path.is_empty() or _repath_t <= 0.0 or (_path.size() > 0 and _path[_path.size() - 1].distance_to(goal) > 4.0):
		_path = NavGrid.inst.find_path(global_position, goal)
		_path_i = 0
		_repath_t = 1.0
	while _path_i < _path.size():
		var p := _path[_path_i]
		var to := p - global_position
		to.y = 0
		if to.length() < 0.9 and _path_i < _path.size() - 1:
			_path_i += 1
			continue
		return to.normalized() * speed
	var direct := goal - global_position
	direct.y = 0
	return direct.normalized() * speed if direct.length() > 0.5 else Vector3.ZERO


func _cop_update(delta: float) -> Vector3:
	var game := manager.game
	var wanted := game.wanted.level
	if wanted == 0 or not game.player_alive():
		state = State.LEAVE
		_ring = NavGrid.inst.ring_for(global_position)
		_ring_i = _nearest_ring_corner()
		return Vector3.ZERO
	var hero := game.hero
	var target_pos := game.player_position()
	var to := target_pos - global_position
	to.y = 0
	var dist := to.length()
	# Line of sight check a few times per second.
	_los_t -= delta
	if _los_t <= 0.0:
		_los_t = 0.35
		var eye := global_position + Vector3.UP * 1.6
		var q := PhysicsRayQueryParameters3D.create(eye, target_pos + Vector3.UP * 1.2, 1)
		_has_los = dist < 60.0 and get_world_3d().direct_space_state.intersect_ray(q).is_empty()
		if _has_los and dist < 45.0:
			game.wanted.seen()
	# Arrest: touching the hero on foot, or at the door of a stopped car.
	if game.driving == null and dist < 1.25 and hero.is_on_floor():
		game.bust()
		return Vector3.ZERO
	if game.driving != null:
		var door_d := game.driving.distance_to_point(global_position)
		if door_d < 1.6 and absf(game.driving.speed) < 1.5:
			game.bust()
			return Vector3.ZERO
	# Shoot at 2+ stars when in clear view.
	if wanted >= 2 and _has_los and dist < 22.0 and dist > 3.0:
		state = State.ATTACK
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z) + AnimUtil.AIM_YAW, clampf(delta * 8.0, 0.0, 1.0))
		_play("aim_hold", 0.2)
		_shoot_t -= delta
		if _shoot_t <= 0.0:
			_shoot_t = randf_range(0.9, 1.6)
			_fire_at(target_pos)
		return Vector3.ZERO
	state = State.CHASE
	if dist < 1.0:
		return Vector3.ZERO
	if _has_los and dist < 12.0:
		return to.normalized() * COP_RUN_SPEED
	return _follow_path(target_pos, delta, COP_RUN_SPEED)


func _fire_at(target: Vector3) -> void:
	var game := manager.game
	var muzzle := global_position + Vector3.UP * 1.45
	if _weapon:
		var m := _weapon.find_child("muzzle", true, false) as Node3D
		if m:
			muzzle = m.global_position
	var aim := target + Vector3.UP * randf_range(0.9, 1.5)
	var hit_chance := 0.35
	if game.driving != null:
		hit_chance = 0.5   # big target, but the car takes most of it
	var miss := randf() > hit_chance
	if miss:
		aim += Vector3(randf_range(-1.5, 1.5), randf_range(-0.5, 1.0), randf_range(-1.5, 1.5))
	var dir := (aim - muzzle).normalized()
	Fx.inst.muzzle_flash(muzzle, dir)
	Fx.inst.play_sound("pistol", muzzle, 0.8)
	var q := PhysicsRayQueryParameters3D.create(muzzle, muzzle + dir * 60.0, 1 | 2 | 8, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := muzzle + dir * 60.0
	if not hit.is_empty():
		end = hit.position
		var col: Object = hit.collider
		if col is Hero:
			game.damage_player(8.0, "bullet")
			Fx.inst.blood(end, -dir)
		elif col is Vehicle:
			(col as Vehicle).take_damage(4.0, end)
			if col == game.driving:
				game.damage_player(2.5, "bullet")
			Fx.inst.sparks(end, hit.normal, 8)
		else:
			Fx.inst.dust(end, hit.normal)
			Fx.inst.bullet_hole(end, hit.normal)
	Fx.inst.tracer(muzzle, end)
