extends Node3D

const IDS := ["bat", "pistol", "shotgun"]
const NAMES := ["БИТА", "ПИСТОЛЕТ", "ДРОБОВИК"]
const CAPACITY := [0, 12, 6]
var life
var hero
var owned: Array[bool] = [false, false, false]
var loaded: Array[int] = [0, 0, 0]
var reserve: Array[int] = [0, 0, 0]
var selected := -1
var reloading := 0.0
var cooldown := 0.0
var attack_time := 0.0
var hit_time := 0.0
var aiming := false
var attachment: BoneAttachment3D
var weapon: Node3D
var mounts: Dictionary
var pickups: Array[Node3D] = []
var skeleton: Skeleton3D
var hand_bone := -1

func _ready() -> void:
	mounts = JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapon_mounts.json"))
	skeleton = hero.visual.find_children("*", "Skeleton3D", true, false)[0]
	hand_bone = skeleton.find_bone("mixamorig_RightHand")
	attachment = BoneAttachment3D.new()
	skeleton.add_child(attachment)
	attachment.bone_name = "mixamorig_RightHand"
	if life.active:
		for origin in [Vector3(99, 0.22, 19), Vector3(-109, 0.25, 28), Vector3(49, 0.25, -101)]:
			for i in 3:
				create_pickup(i, origin + Vector3(i * 2.4, 0, 0))

func mount_transform(id: String) -> Transform3D:
	var data: Dictionary = mounts[id]
	var b: Array = data.local_basis
	var o: Array = data.local_origin
	return Transform3D(Basis(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]), Vector3(b[6], b[7], b[8])), Vector3(o[0], o[1], o[2]))

func create_pickup(index: int, point: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = point
	root.set_meta("weapon", index)
	root.set_meta("cooldown", 0.0)
	var model: Node3D = life.scene("res://assets/weapons/%s.glb" % IDS[index]).instantiate()
	root.add_child(model)
	model.rotation = Vector3(0, 0.5, PI / 2 if index != 2 else 0.0)
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.visibility_range_end = 55
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bottom := INF
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var bounds: AABB = mesh.get_aabb()
		for corner in 8:
			bottom = minf(bottom, root.to_local(mesh.to_global(bounds.get_endpoint(corner))).y)
	model.position.y -= bottom
	root.set_meta("settled", false)
	var label := Label3D.new()
	label.name = "Caption"
	label.text = NAMES[index] + "\nПОДОЙТИ"
	label.font_size = 32
	label.pixel_size = 0.004
	label.position.y = 1.35
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("ffdc90")
	label.visibility_range_end = 45
	root.add_child(label)
	var beam := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.045, 1.1, 0.045)
	box.material = life.fx.glow(Color("ffcf78"))
	beam.mesh = box
	beam.position.y = 0.6
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.visibility_range_end = 55
	root.add_child(beam)
	pickups.append(root)

func give(index: int) -> void:
	if not owned[index]:
		owned[index] = true
		loaded[index] = CAPACITY[index]
	reserve[index] = mini(180, reserve[index] + (60 if index == 1 else 24))
	select(index)
	hero.notice = "Подобрано: " + NAMES[index]
	hero.notice_time = 2.0

func select(index: int) -> void:
	if index < 0 or index > 2 or not owned[index]:
		return
	selected = index
	reloading = 0
	if weapon != null:
		weapon.queue_free()
	weapon = life.scene("res://assets/weapons/%s.glb" % IDS[index]).instantiate()
	attachment.add_child(weapon)
	weapon.transform = mount_transform(IDS[index])
	for mesh in weapon.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func reload() -> void:
	if selected <= 0 or reloading > 0 or reserve[selected] <= 0 or loaded[selected] >= CAPACITY[selected] or hero.vehicle != null:
		return
	reloading = 1.3 if selected == 1 else 2.1
	life.fx.play_sound("reload", hero.global_position + Vector3.UP, -5)

func aim_rotation() -> float:
	if weapon == null or hand_bone < 0:
		return hero.yaw + PI
	var bone := skeleton.global_basis * skeleton.get_bone_global_pose(hand_bone).basis
	var local_forward: Vector3 = hero.visual.global_basis.inverse() * (bone * weapon.transform.basis * Vector3.FORWARD)
	var desired: Vector3 = -hero.camera.global_basis.z
	return atan2(desired.x, desired.z) - atan2(local_forward.x, local_forward.z)

func input(event: InputEvent) -> void:
	if life.outcome != "":
		return
	if event.is_action_pressed("reload"):
		reload()
	for i in 3:
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			select(i)
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var direction := 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
		for i in range(1, 4):
			var next := posmod(maxi(selected, 0) + direction * i, 3)
			if owned[next]:
				select(next)
				break

func _physics_process(delta: float) -> void:
	cooldown = maxf(0, cooldown - delta)
	attack_time = maxf(0, attack_time - delta)
	hit_time = maxf(0, hit_time - delta)
	aiming = Input.is_action_pressed("aim") and selected >= 0 and hero.vehicle == null and life.outcome == ""
	attachment.visible = selected >= 0 and hero.vehicle == null and life.outcome == ""
	if reloading > 0:
		reloading -= delta
		if reloading <= 0 and selected > 0:
			var amount := mini(CAPACITY[selected] - loaded[selected], reserve[selected])
			loaded[selected] += amount
			reserve[selected] -= amount
	if selected == 0:
		attachment.rotation.z = sin(clampf(attack_time / 0.35, 0, 1) * PI) * -1.1
	else:
		attachment.rotation = Vector3.ZERO
	for pickup in pickups:
		if not pickup.get_meta("settled"):
			var exclusions: Array[RID] = [hero.get_rid()]
			for person in get_tree().get_nodes_in_group("people"):
				exclusions.append(person.get_rid())
			for car in get_tree().get_nodes_in_group("vehicles"):
				exclusions.append(car.get_rid())
			var ray := PhysicsRayQueryParameters3D.create(pickup.global_position + Vector3.UP * 3, pickup.global_position - Vector3.UP * 4, 1, exclusions)
			var floor_hit := get_world_3d().direct_space_state.intersect_ray(ray)
			if not floor_hit.is_empty():
				pickup.global_position.y = floor_hit.position.y + 0.025
				pickup.set_meta("settled", true)
		var remaining: float = pickup.get_meta("cooldown")
		if remaining > 0:
			pickup.set_meta("cooldown", maxf(0, remaining - delta))
			pickup.visible = false
		else:
			pickup.visible = true
			pickup.get_node("Caption").visible = pickup.global_position.distance_to(hero.global_position) > 4
			if hero.vehicle == null and life.outcome == "" and pickup.global_position.distance_to(hero.global_position) < 1.65:
				give(pickup.get_meta("weapon"))
				pickup.set_meta("cooldown", 35.0)
	if Input.is_action_just_pressed("fire"):
		attack()

func attack() -> bool:
	if selected < 0 or hero.vehicle != null or cooldown > 0 or reloading > 0 or life.outcome != "":
		return false
	if selected > 0 and loaded[selected] == 0:
		reload()
		return false
	attack_time = 0.35
	cooldown = [0.6, 0.28, 0.9][selected]
	if selected == 0:
		life.fx.play_sound("bat", hero.global_position + Vector3.UP)
		var closest = null
		var distance := 2.4
		var direction: Vector3 = -hero.camera.global_basis.z
		for person in get_tree().get_nodes_in_group("people"):
			if person.fallen or person.in_car != null:
				continue
			var diff: Vector3 = person.global_position - hero.global_position
			if diff.length() < distance and diff.normalized().dot(Vector3(direction.x, 0, direction.z).normalized()) > 0.2 and life.visible(hero.global_position + Vector3.UP, person.global_position + Vector3.UP, [hero.get_rid()]):
				closest = person
				distance = diff.length()
		if closest != null:
			closest.take_damage(65, hero.global_position)
			hit_time = 0.22
		return true
	loaded[selected] -= 1
	life.fx.play_sound(IDS[selected], hero.global_position + Vector3.UP, 0 if selected == 1 else 3)
	life.gunfire(hero.global_position, true)
	var camera: Camera3D = hero.camera
	var aim_start := camera.global_position
	var aim_direction := -camera.global_basis.z
	var aim_end := aim_start + aim_direction * 180
	var ray := PhysicsRayQueryParameters3D.create(aim_start, aim_end, 1, [hero.get_rid()])
	var aim_hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not aim_hit.is_empty():
		aim_end = aim_hit.position
	var muzzle: Node3D = weapon.find_child("muzzle", true, false)
	var origin: Vector3 = muzzle.global_position if muzzle != null else hero.global_position + Vector3.UP * 1.4
	var forward := (aim_end - origin).normalized()
	for i in (8 if selected == 2 else 1):
		var spread := 0.038 if selected == 2 else (0.001 if aiming else 0.012)
		var dir := (forward + camera.global_basis.x * randf_range(-spread, spread) + camera.global_basis.y * randf_range(-spread, spread)).normalized()
		var end := origin + dir * (65 if selected == 2 else 180)
		ray = PhysicsRayQueryParameters3D.create(origin, end, 1, [hero.get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			end = hit.position
			life.fx.burst(end, hit.normal, Color("ffd28b"), 7)
			if hit.collider.has_method("take_damage"):
				hit.collider.take_damage(22 if selected == 2 else 55, hero.global_position, true)
				hit_time = 0.2
		life.fx.tracer(origin, end)
	life.fx.burst(origin, forward, Color("ffe4a4"), 5)
	return true

func reset_inventory() -> void:
	owned = [false, false, false]
	loaded = [0, 0, 0]
	reserve = [0, 0, 0]
	selected = -1
	reloading = 0
	attack_time = 0
	aiming = false
	if weapon != null:
		weapon.queue_free()
		weapon = null
	for pickup in pickups:
		pickup.set_meta("cooldown", 0.0)
		pickup.show()
