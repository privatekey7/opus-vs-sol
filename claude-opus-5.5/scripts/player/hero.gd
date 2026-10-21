class_name Hero
extends CharacterBody3D
## On-foot player controller. Body forward is −Z; the GLB (front +Z) is turned by PI inside.
## Also holds the player's health and weapons (aim, fire, reload, melee).

const MODEL_SCALE := 1.7444954588
const WALK_SPEED := 2.2
const RUN_SPEED := 6.2
const AIM_SPEED := 1.8
const ACCEL := 12.0
const AIR_ACCEL := 3.0
const JUMP_VELOCITY := 5.2
const GRAVITY := 15.0
const TURN_SPEED := 10.0
const STEP_HEIGHT := 0.35
const MAX_HEALTH := 100.0
# Native speeds of the in-place clips, used to scale playback so feet don't slide.
const WALK_ANIM_SPEED := 1.6
const RUN_ANIM_SPEED := 5.2
# Airborne pose: a mid-stride frame of the run clip (legs apart, arms swinging).
const JUMP_POSE_TIME := 0.1

const WEAPON_ORDER := ["", "bat", "pistol", "shotgun"]
const WEAPON_NAMES := {"": "Кулаки", "bat": "Бита", "pistol": "Пистолет", "shotgun": "Дробовик"}
# mag size, ammo given by a pickup, damage, range, fire interval, reload time, pellets, spread (deg)
const WEAPONS := {
	"bat": [0, 0, 45.0, 2.0, 0.55, 0.0, 1, 0.0],
	"pistol": [12, 36, 26.0, 120.0, 0.22, 1.3, 1, 0.6],
	"shotgun": [6, 18, 13.0, 45.0, 0.85, 2.2, 8, 4.5],
}

var camera_yaw := 0.0          # set by CameraRig; movement is relative to it
var input_enabled := true
var game: Game
var health := MAX_HEALTH
var dead := false
var aiming := false
var current := ""              # "" = unarmed
var owned := {}                # id -> {"mag": int, "reserve": int}
var reloading := 0.0

var _model: Node3D
var _anim: AnimationPlayer
var _anim_names := {}
var _current_anim := ""
var _airborne_time := 0.0
var _collision: CollisionShape3D
var _weapon: Node3D
var _fire_cd := 0.0
var _aim_hold_t := 0.0         # keeps the aim pose briefly after hip-fire
var _knock_t := 0.0
var _swing_t := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4 | 8 | 16
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(50)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.8
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.9
	add_child(cs)
	_collision = cs

	_model = game.scenes["hero"].instantiate()
	_model.name = "Model"
	_model.scale = Vector3.ONE * MODEL_SCALE
	_model.rotation.y = PI
	add_child(_model)
	_anim = _model.find_children("*", "AnimationPlayer", true, false)[0]
	_anim_names = AnimUtil.clip_names(_anim)
	for loop_clip in ["idle", "walk", "run"]:
		_anim.get_animation(_anim_names[loop_clip]).loop_mode = Animation.LOOP_LINEAR
	AnimUtil.make_pose_clip(_anim, _anim_names, "jump", "run", JUMP_POSE_TIME)
	AnimUtil.make_pose_clip(_anim, _anim_names, "aim_hold", "aim", 0.8)
	_play("idle", 0.0)


func _play(clip: String, blend := 0.2, speed := 1.0) -> void:
	if _current_anim != clip:
		_current_anim = clip
		_anim.play(_anim_names[clip], blend)
	_anim.speed_scale = speed


## Hides the hero while driving and brings him back when stepping out.
func set_driving(driving: bool) -> void:
	visible = not driving
	_collision.disabled = driving
	input_enabled = not driving
	process_mode = Node.PROCESS_MODE_DISABLED if driving else Node.PROCESS_MODE_INHERIT
	velocity = Vector3.ZERO
	aiming = false
	if not driving:
		_current_anim = ""
		_play("idle", 0.0)
		reset_physics_interpolation()


## ---------------------------------------------------------------- health

func take_damage(amount: float) -> void:
	if dead:
		return
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		dead = true
		input_enabled = false
		aiming = false
		if visible:
			_play("death", 0.15)


func knock_down() -> void:
	## Hit by a car while on foot.
	if dead:
		return
	_knock_t = 2.6
	input_enabled = false
	aiming = false
	_play("knocked_down", 0.1)


func play_busted() -> void:
	input_enabled = false
	aiming = false
	velocity = Vector3.ZERO
	_play("idle", 0.2)


func respawn(pos: Vector3, yaw: float) -> void:
	set_driving(false)
	dead = false
	health = MAX_HEALTH
	owned.clear()
	_select("")
	reloading = 0.0
	_knock_t = 0.0
	global_position = pos
	rotation.y = yaw
	velocity = Vector3.ZERO
	input_enabled = true
	reset_physics_interpolation()


## ---------------------------------------------------------------- weapons

func give_weapon(id: String) -> bool:
	var spec: Array = WEAPONS[id]
	if owned.has(id):
		if id == "bat":
			return false
		owned[id].reserve += spec[1]
	else:
		owned[id] = {"mag": spec[0], "reserve": spec[1]}
	_select(id)
	return true


func _select(id: String) -> void:
	if id != "" and not owned.has(id):
		return
	current = id
	reloading = 0.0
	_swing_t = 0.0
	_weapon = AnimUtil.attach_weapon(_model, game.scenes[id] if id != "" else null, id)


func _cycle(step: int) -> void:
	var i := WEAPON_ORDER.find(current)
	for k in WEAPON_ORDER.size():
		i = posmod(i + step, WEAPON_ORDER.size())
		var id: String = WEAPON_ORDER[i]
		if id == "" or owned.has(id):
			_select(id)
			return


func ammo_text() -> String:
	if current == "" or current == "bat":
		return ""
	var o: Dictionary = owned[current]
	return "%d / %d" % [o.mag, o.reserve]


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event.is_action_pressed("weapon_1"):
		_select("bat")
	elif event.is_action_pressed("weapon_2"):
		_select("pistol")
	elif event.is_action_pressed("weapon_3"):
		_select("shotgun")
	elif event.is_action_pressed("weapon_next"):
		_cycle(1)
	elif event.is_action_pressed("weapon_prev"):
		_cycle(-1)
	elif event.is_action_pressed("reload"):
		_start_reload()


func _start_reload() -> void:
	if current == "" or current == "bat" or reloading > 0.0:
		return
	var o: Dictionary = owned[current]
	if o.mag < WEAPONS[current][0] and o.reserve > 0:
		reloading = WEAPONS[current][5]


func _update_weapons(delta: float) -> void:
	_fire_cd -= delta
	_aim_hold_t -= delta
	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0:
			reloading = 0.0
			var o: Dictionary = owned[current]
			var need: int = WEAPONS[current][0] - o.mag
			var take := mini(need, o.reserve)
			o.mag += take
			o.reserve -= take
	if _weapon and current == "bat":
		# Swing: the bat arcs around the wrist.
		var k := 0.0
		if _swing_t > 0.0:
			_swing_t -= delta
			k = sin(clampf(1.0 - _swing_t / 0.35, 0.0, 1.0) * PI)
		(_weapon.get_parent() as Node3D).rotation = Vector3(-1.6 * k, 0, 0)
	aiming = input_enabled and is_on_floor() and current != "" and current != "bat" and Input.is_action_pressed("aim")
	if input_enabled and current != "" and Input.is_action_just_pressed("fire") and _fire_cd <= 0.0:
		if current == "bat":
			_swing()
		else:
			_shoot()


func _aim_direction() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	return -cam.global_transform.basis.z


func _shoot() -> void:
	var spec: Array = WEAPONS[current]
	var o: Dictionary = owned[current]
	if reloading > 0.0:
		return
	if o.mag <= 0:
		Fx.inst.play_sound("click", global_position + Vector3.UP, 0.8)
		_fire_cd = 0.3
		_start_reload()
		return
	o.mag -= 1
	_fire_cd = spec[4]
	_aim_hold_t = 0.7
	var cam := get_viewport().get_camera_3d()
	var fwd := -cam.global_transform.basis.z
	# Face the shot immediately.
	rotation.y = atan2(fwd.x, fwd.z) + AnimUtil.AIM_YAW
	_play("aim_hold", 0.05)
	var muzzle := global_position + Vector3.UP * 1.4 - global_transform.basis.z * 0.6
	if _weapon:
		var m := _weapon.find_child("muzzle", true, false) as Node3D
		if m:
			muzzle = m.global_position
	var cam_pos := cam.global_position
	var start_t := maxf((global_position + Vector3.UP * 1.4 - cam_pos).dot(fwd), 0.0)
	var space := get_world_3d().direct_space_state
	var hit_people := false
	for i in spec[6]:
		var dir := fwd
		if spec[7] > 0.0:
			var s := deg_to_rad(spec[7])
			dir = dir.rotated(cam.global_transform.basis.x, randf_range(-s, s)).rotated(cam.global_transform.basis.y, randf_range(-s, s))
		var from := cam_pos + dir * start_t
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * spec[3], 1 | 8 | 16, [get_rid()])
		var hit := space.intersect_ray(q)
		var end: Vector3 = from + dir * spec[3]
		if not hit.is_empty():
			end = hit.position
			hit_people = _apply_hit(hit, dir, spec[2]) or hit_people
		if i < 3:
			Fx.inst.tracer(muzzle, end)
	Fx.inst.muzzle_flash(muzzle, fwd)
	Fx.inst.play_sound(current, muzzle, 1.6)
	game.rig.add_recoil(0.025 if current == "pistol" else 0.07)
	game.on_player_gunshot(hit_people)
	if o.mag == 0:
		_start_reload()


func _apply_hit(hit: Dictionary, dir: Vector3, damage: float) -> bool:
	var col: Object = hit.collider
	var pos: Vector3 = hit.position
	var n: Vector3 = hit.normal
	if col is Human:
		var h := col as Human
		if h.alive and h.role == Human.Role.PED:
			game.wanted.report("hit_ped", pos)
		h.take_damage(damage, dir, self)
		Fx.inst.blood(pos, -dir)
		return true
	if col is Vehicle:
		var v := col as Vehicle
		v.take_damage(damage * 0.4, pos)
		if v.model_id == "police" and v.ai:
			game.wanted.report("attack_cop", pos)
		Fx.inst.sparks(pos, n, 12)
		Fx.inst.bullet_hole(pos, n)
		return false
	Fx.inst.dust(pos, n)
	Fx.inst.bullet_hole(pos, n)
	return false


func _swing() -> void:
	_fire_cd = WEAPONS["bat"][4]
	_swing_t = 0.35
	get_tree().create_timer(0.15, false).timeout.connect(_swing_hit)


func _swing_hit() -> void:
	if dead:
		return
	var fwd := -global_transform.basis.z
	var center := global_position + Vector3.UP * 1.0 + fwd * 1.0
	var sphere := SphereShape3D.new()
	sphere.radius = 0.9
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis(), center)
	q.collision_mask = 8 | 16
	q.exclude = [get_rid()]
	var hits := get_world_3d().direct_space_state.intersect_shape(q, 8)
	var hit_any := false
	for h in hits:
		var col: Object = h.collider
		if col is Human and (col as Human).alive:
			var hu := col as Human
			if hu.role == Human.Role.PED:
				game.wanted.report("hit_ped", hu.global_position)
			hu.take_damage(WEAPONS["bat"][2], fwd, self)
			if hu.alive:
				hu.thrown_out_of_car()   # knocked to the ground
			Fx.inst.blood(hu.global_position + Vector3.UP * 1.4, -fwd)
			hit_any = true
		elif col is Vehicle:
			(col as Vehicle).take_damage(6.0, center)
			hit_any = true
	if hit_any:
		Fx.inst.play_sound("bat", center, 1.5)
		game.npcs.alert(global_position, 15.0)


## ---------------------------------------------------------------- movement

func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_tick(delta)
	Game.prof_add("hero", Time.get_ticks_usec() - t0)


func _tick(delta: float) -> void:
	if _knock_t > 0.0:
		_knock_t -= delta
		if _knock_t <= 0.0 and not dead:
			input_enabled = true
			_current_anim = ""
	var input := Vector2.ZERO
	var sprint := false
	if input_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		sprint = Input.is_action_pressed("sprint")
	_update_weapons(delta)
	var aim_pose := aiming or _aim_hold_t > 0.0
	# Camera-relative direction on the ground plane.
	var dir := Vector3(input.x, 0, input.y).rotated(Vector3.UP, camera_yaw)
	if dir.length() > 1.0:
		dir = dir.normalized()
	var target_speed := RUN_SPEED if sprint else WALK_SPEED
	if aim_pose:
		target_speed = AIM_SPEED
	var target := dir * target_speed
	var on_floor := is_on_floor()
	var accel := ACCEL if on_floor else AIR_ACCEL
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(target, accel * maxf(target_speed, 2.0) * delta)
	velocity.x = hv.x
	velocity.z = hv.z

	if on_floor:
		if input_enabled and Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * delta

	if on_floor and hv.length() > 0.1:
		_try_step_up(hv * delta)
	move_and_slide()

	if aim_pose and not dead and input_enabled:
		var f := _aim_direction()
		rotation.y = lerp_angle(rotation.y, atan2(f.x, f.z) + AnimUtil.AIM_YAW, clampf(20.0 * delta, 0.0, 1.0))
	elif dir.length() > 0.05:
		var want := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, want, clampf(TURN_SPEED * delta, 0.0, 1.0))

	_update_animation(delta, aim_pose)


func _try_step_up(motion: Vector3) -> void:
	## Lifts the body over curbs and low steps that would otherwise block it.
	var probe := motion.normalized() * maxf(motion.length(), 0.15)
	if not test_move(global_transform, probe):
		return
	var up := Vector3(0, STEP_HEIGHT, 0)
	if test_move(global_transform, up):
		return
	var raised := global_transform.translated(up)
	if test_move(raised, probe):
		return
	global_position += up


func _update_animation(delta: float, aim_pose: bool) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor():
		_airborne_time = 0.0
	else:
		_airborne_time += delta
	if dead or _knock_t > 0.0 or not input_enabled:
		return   # death / knock-down / busted clips keep playing
	if _airborne_time > 0.18 or (velocity.y > 1.0 and not is_on_floor()):
		_play("jump", 0.15)
	elif aim_pose:
		_play("aim_hold", 0.12)
	elif speed > 3.6:
		_play("run", 0.2, clampf(speed / RUN_ANIM_SPEED, 0.6, 1.6))
	elif speed > 0.3:
		_play("walk", 0.2, clampf(speed / WALK_ANIM_SPEED, 0.5, 1.8))
	else:
		_play("idle", 0.3)
