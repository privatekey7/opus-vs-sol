extends CharacterBody3D

const SCALES := {"cop": 1.7843919564, "tourist": 1.7505452665, "woman": 1.4812555337, "thug": 1.8290786731, "bikini": 1.6260519810, "jogger": 1.7492516445, "businessman": 1.7610197929}
var kind := "tourist"
var police := false
var life
var model: Node3D
var animator: AnimationPlayer
var clips: Dictionary = {}
var animation := ""
var health := 50.0
var fallen := false
var in_car = null
var path := PackedVector3Array()
var path_index := 0
var path_timer := 0.0
var fear := 0.0
var fear_origin := Vector3.ZERO
var shoot_timer := 1.0
var corpse_time := 0.0
var origin := Vector3.ZERO
var meshes: Array[Node] = []
var flash := 0.0
var idle_time := 0.0
var stuck := 0.0
var stunned := 0.0
var gun: Node3D
var skeleton: Skeleton3D

func _ready() -> void:
	add_to_group("people")
	if police:
		add_to_group("cops")
		health = 90
	collision_layer = 9
	collision_mask = 3
	floor_snap_length = 0.4
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.75
	capsule.radius = 0.29
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.88
	add_child(shape)
	model = life.scene("res://assets/people/%s.glb" % kind).instantiate()
	model.scale = Vector3.ONE * float(SCALES[kind])
	add_child(model)
	animator = model.find_children("*", "AnimationPlayer", true, false)[0]
	for clip in animator.get_animation_list():
		var short_name: String = String(clip).get_slice("/", String(clip).get_slice_count("/") - 1)
		clips[short_name] = clip
		if short_name in ["idle", "walk", "run", "aim"]:
			animator.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	meshes = model.find_children("*", "MeshInstance3D", true, false)
	for mesh in meshes:
		mesh.lod_bias = 0.18
		mesh.visibility_range_end = 65
		mesh.visibility_range_end_margin = 8
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	origin = position
	path_timer = randf_range(0.1, 0.8)
	play("idle")
	if police:
		skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
		var hand := BoneAttachment3D.new()
		skeleton.add_child(hand)
		hand.bone_name = "mixamorig_RightHand"
		gun = life.scene("res://assets/weapons/pistol.glb").instantiate()
		hand.add_child(gun)
		gun.transform = life.combat.mount_transform("pistol")
		for mesh in gun.find_children("*", "MeshInstance3D", true, false):
			mesh.visibility_range_end = 40
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func play(clip: String) -> void:
	if animation != clip and clips.has(clip):
		animation = clip
		animator.play(clips[clip], 0.18)

func flee(point: Vector3) -> void:
	if not police and not fallen and in_car == null:
		fear = 10.0
		fear_origin = point
		path_timer = 0

func take_damage(amount: float, source := Vector3.ZERO, by_player := true) -> void:
	if fallen:
		return
	health -= amount
	flash = 0.13
	for mesh in meshes:
		mesh.material_overlay = life.fx.glow(Color("e56b65"))
	life.fx.burst(global_position + Vector3.UP, (global_position - source).normalized(), Color("d66c65"), 9)
	if by_player:
		life.crime(2 if police else 1, global_position)
	flee(source)
	if health <= 0:
		fallen = true
		collision_layer = 0
		collision_mask = 1
		velocity = Vector3.ZERO
		play("death")
		corpse_time = 0

func update_path() -> void:
	var destination := Vector3.ZERO
	if police and life.wanted > 0:
		destination = life.last_seen_position
		var hero_point := destination
		# Выбираем подход к игроку, видимый с тротуара, а не прямую сквозь квартал.
		var best := INF
		for id in life.routes.walk.get_point_ids():
			var p: Vector3 = life.routes.walk.get_point_position(id)
			var d := p.distance_squared_to(hero_point)
			if d < best and life.visible(p + Vector3.UP, hero_point + Vector3.UP, [get_rid()]):
				best = d
				destination = hero_point if d < 0.01 else life.routes.walk.get_point_position(id)
	else:
		var best := -INF
		var ids: PackedInt64Array = life.routes.walk.get_point_ids()
		for i in 12:
			var point: Vector3 = life.routes.walk.get_point_position(ids[randi() % ids.size()])
			var score := randf() * 30 - global_position.distance_to(point) * 0.2
			if fear > 0:
				score += point.distance_to(fear_origin)
			if score > best:
				best = score
				destination = point
	path = life.routes.walk_path(global_position, destination)
	if police and life.wanted > 0 and life.visible(destination + Vector3.UP, life.last_seen_position + Vector3.UP, [get_rid()]):
		path.append(life.last_seen_position)
	path_index = 0
	path_timer = 1.2 if police else randf_range(6, 12)

func _physics_process(delta: float) -> void:
	if in_car != null:
		global_position = in_car.global_position
		return
	if stunned > 0:
		stunned -= delta
		play("knocked_down")
		return
	if flash > 0:
		flash -= delta
		if flash <= 0:
			for mesh in meshes:
				mesh.material_overlay = null
	if fallen:
		corpse_time += delta
		if corpse_time > 4:
			animator.pause()
		if police and corpse_time > 25:
			queue_free()
			return
		if corpse_time > 40 and global_position.distance_to(life.hero.global_position) > 30 and not police:
			health = 50
			fallen = false
			collision_layer = 9
			position = origin
			reset_physics_interpolation()
			play("idle")
		return
	var far := global_position.distance_squared_to(life.hero.global_position) > 80 * 80
	animator.active = not far
	if far and not police:
		return
	fear = maxf(0, fear - delta)
	shoot_timer -= delta
	path_timer -= delta
	if path_timer <= 0:
		update_path()
	var target := global_position
	if path_index < path.size():
		target = path[path_index]
		if Vector2(target.x - position.x, target.z - position.z).length() < 0.75:
			path_index += 1
			if path_index >= path.size():
				path_timer = 0
	var speed := 4.2 if fear > 0 else (3.8 if police and life.wanted > 0 else (2.0 if kind == "jogger" else 1.35))
	var seeing := false
	if police and life.wanted > 0 and life.outcome == "":
		var player_point: Vector3 = life.hero.global_position
		var distance := global_position.distance_to(player_point)
		seeing = distance < 60 and life.visible(global_position + Vector3.UP * 1.45, player_point + Vector3.UP, [get_rid()])
		if seeing:
			life.seen = true
		if seeing and distance < 18:
			target = player_point
			if life.hero.vehicle != null:
				var exit: Vector3 = life.hero.vehicle.to_global(Vector3(-life.hero.vehicle.dimensions.x / 2 - 0.65, 0, -life.hero.vehicle.dimensions.z * 0.18))
				target = exit
			if (life.hero.vehicle == null and distance < 1.3) or (life.hero.vehicle != null and absf(life.hero.vehicle.speed) < 1.5 and global_position.distance_to(target) < 1.6):
				life.finish("АРЕСТОВАН")
				return
		if seeing and distance < 30 and distance > 5 and life.wanted >= 2 and shoot_timer <= 0:
			shoot_timer = randf_range(1.0, 1.7)
			life.police_shoot(self)
		if seeing and distance < 18 and distance > 9 and shoot_timer > 0.9 and life.wanted >= 2:
			speed = 0
	var direction := target - global_position
	direction.y = 0
	if direction.length() > 0.1:
		direction = direction.normalized()
	else:
		direction = Vector3.ZERO
	if stuck > 0.7:
		direction = (direction + direction.cross(Vector3.UP) * 0.8).normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor():
		velocity.y -= 22 * delta
	else:
		velocity.y = 0
	var step := Vector3(velocity.x, 0, velocity.z) * delta
	if is_on_floor() and test_move(global_transform, step):
		var raised := global_transform
		raised.origin.y += 0.29
		if not test_move(global_transform, Vector3.UP * 0.29) and not test_move(raised, step):
			global_position.y += 0.29
	var before := global_position
	move_and_slide()
	if before.distance_squared_to(global_position) < 0.00001 and speed > 0:
		stuck += delta
	else:
		stuck = maxf(0, stuck - delta)
	if stuck > 3:
		path_timer = 0
		stuck = 0
	if seeing and police:
		var to_hero: Vector3 = life.hero.global_position - global_position
		model.rotation.y = lerp_angle(model.rotation.y, atan2(to_hero.x, to_hero.z), 0.2)
	else:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(direction.x, direction.z), 0.2)
	play("aim" if speed == 0 and seeing else ("run" if speed > 2.5 else "walk"))
	if animation == "aim" and gun != null:
		animator.play(clips["aim"], 0)
		animator.seek(0.8, true)
		animator.advance(0)
		var bone := skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_RightHand"))
		var local_direction := model.global_basis.inverse() * skeleton.global_basis * bone.basis * gun.transform.basis * Vector3.FORWARD
		var desired: Vector3 = life.hero.global_position - global_position
		model.rotation.y = atan2(desired.x, desired.z) - atan2(local_direction.x, local_direction.z)
