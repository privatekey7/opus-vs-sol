extends Node3D

const Routes = preload("res://scripts/street_routes.gd")
const Person = preload("res://scripts/pedestrian.gd")
const Combat = preload("res://scripts/combat.gd")
const FX = preload("res://scripts/effects.gd")
const Vehicle = preload("res://scripts/vehicle.gd")
var world
var hero
var active := true
var routes
var combat
var fx
var wanted := 0
var heat := 0.0
var unseen := 0.0
var seen := false
var health := 100.0
var hurt := 0.0
var impact_flash := 0.0
var outcome := ""
var outcome_time := 0.0
var immunity := 0.0
var police_timer := 0.0
var patrols: Array[Node] = []
var officers: Array[Node] = []
var wanted_timer := 0.0
var severe_timer := 0.0
var last_seen_position := Vector3(98, 0.14, 24)

func scene(path: String) -> PackedScene:
	if not world.cache.has(path):
		world.cache[path] = load(path)
	return world.cache[path]

func _ready() -> void:
	routes = Routes.new()
	fx = FX.new()
	add_child(fx)
	combat = Combat.new()
	combat.life = self
	combat.hero = hero
	add_child(combat)
	if active:
		populate()

func spawn_person(kind: String, point: Vector3, cop := false):
	var person := Person.new()
	person.kind = kind
	person.police = cop
	person.life = self
	person.position = point
	add_child(person)
	return person

func populate() -> void:
	var types := ["tourist", "woman", "thug", "bikini", "jogger", "businessman", "cop"]
	var points := [Vector3(98, 0.3, 6), Vector3(104, 0.3, 38), Vector3(70, 0.3, 50), Vector3(103, 0.3, -18), Vector3(50.5, 0.3, 65), Vector3(-10.5, 0.3, 18), Vector3(-29.5, 0.3, -30), Vector3(-90.5, 0.3, -65), Vector3(-109.5, 0.3, 92), Vector3(-170.5, 0.3, -132), Vector3(50.5, 0.3, -115), Vector3(-10.5, 0.3, 132)]
	for i in points.size():
		var kind: String = types[i % types.size()]
		var person = spawn_person(kind, points[i], kind == "cop")
		if person.police:
			officers.append(person)
	var cars := get_tree().get_nodes_in_group("vehicles")
	for index in [2, 4, 8]:
		var car = cars[index]
		var driver = spawn_person("businessman" if index == 4 else "tourist", car.position)
		driver.in_car = car
		driver.hide()
		driver.animator.active = false
		driver.collision_layer = 0
		car.start_ai(driver, false)

func visible(from: Vector3, to: Vector3, excludes: Array = []) -> bool:
	var ids: Array[RID] = []
	ids.assign(excludes)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, ids)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hero.vehicle != null and hit.collider == hero.vehicle):
		return true
	return hit.collider.is_in_group("people") and (hit.collider.global_position + Vector3.UP).distance_to(to) < 0.6

func witnessed(point: Vector3, radius := 35.0) -> bool:
	for person in get_tree().get_nodes_in_group("people"):
		if not person.fallen and person.global_position.distance_to(point) < radius:
			var exclusions := [person.get_rid()]
			if person.in_car != null:
				exclusions.append(person.in_car.get_rid())
			if visible(person.global_position + Vector3.UP * 1.4, point + Vector3.UP, exclusions):
				return true
	return false

func crime(severity: int, point: Vector3) -> void:
	if not active or outcome != "":
		return
	# Каждое преступление поднимает уровень; дробь одного выстрела не создаёт пять звёзд.
	if wanted_timer <= 0 or severity >= 2 and severe_timer <= 0:
		wanted = clampi(wanted + severity, 1, 5)
		wanted_timer = 0.7
		if severity >= 2:
			severe_timer = 1
	heat = 10
	unseen = 0
	last_seen_position = hero.global_position
	police_timer = minf(police_timer, 0.1)
	refresh_patrols()

func refresh_patrols() -> void:
	patrols = patrols.filter(func(p): return is_instance_valid(p) and p.ai_driver and not p.occupied)
	var chasing := mini(3, 1 + wanted / 2) if wanted > 0 else 0
	for i in patrols.size():
		var car = patrols[i]
		var pursuing := i < chasing
		if car.police_ai != pursuing:
			car.ai_timer = 0
		car.police_ai = pursuing
		car.set_siren(pursuing)

func gunfire(point: Vector3, by_player: bool) -> void:
	for person in get_tree().get_nodes_in_group("people"):
		if person.global_position.distance_to(point) < 50:
			person.flee(point)
	if by_player and witnessed(point, 40):
		crime(1, point)

func damage(amount: float) -> void:
	if outcome != "" or immunity > 0:
		return
	health = maxf(0, health - amount)
	hurt = 0.65
	if health <= 0:
		finish("ПОТРАЧЕНО")

func car_impact(car, point: Vector3, normal: Vector3, force: float) -> void:
	fx.burst(point, normal + Vector3.UP * 0.5, Color("ffc879"), 24)
	fx.play_sound("impact", point, 4)
	if car.occupied:
		impact_flash = 0.7
		hero.notice = "УДАР  •  %d км/ч" % int(force * 3.6)
		hero.notice_time = 1.3
		if force > 7:
			damage(minf(60, (force - 6) * 2))

func police_shoot(cop) -> void:
	if outcome != "":
		return
	var from: Vector3 = cop.global_position + Vector3.UP * 1.4
	var target: Vector3 = hero.global_position + Vector3.UP * 1.15
	var ray := PhysicsRayQueryParameters3D.create(from, target, 3, [cop.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	var end := target
	if not hit.is_empty():
		end = hit.position
		if hit.collider == hero or hit.collider == hero.vehicle:
			damage(5 if hero.vehicle != null else 9)
	fx.tracer(from, end, Color("ffbd95"))
	fx.play_sound("pistol", from, -8)
	gunfire(from, false)

func spawn_location(for_car: bool) -> Vector3:
	var graph: AStar3D = routes.road if for_car else routes.walk
	var selected := Vector3.ZERO
	var score := INF
	for id in graph.get_point_ids():
		var point := graph.get_point_position(id)
		var distance := point.distance_to(hero.global_position)
		var preference := absf(distance - (85 if for_car else 48))
		if distance > 28 and preference < score:
			var query := PhysicsShapeQueryParameters3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(2.5, 2, 5) if for_car else Vector3(0.8, 1.7, 0.8)
			query.shape = shape
			query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 1.1)
			query.collision_mask = 1
			if get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
				selected = point
				score = preference
	return selected + Vector3.UP * 0.2

func replenish_police() -> void:
	officers = officers.filter(func(p): return is_instance_valid(p))
	patrols = patrols.filter(func(p): return is_instance_valid(p))
	refresh_patrols()
	if wanted <= 0:
		return
	var alive := 0
	for person in officers:
		if not person.fallen:
			alive += 1
	if alive < mini(6, wanted + 1):
		var person = spawn_person("cop", spawn_location(false), true)
		officers.append(person)
	if patrols.size() < mini(3, 1 + wanted / 2):
		var car := Vehicle.new()
		car.kind = "police"
		car.position = spawn_location(true)
		var dir: Vector3 = hero.global_position - car.position
		car.rotation.y = atan2(-signf(dir.x), 0) if absf(dir.x) > absf(dir.z) else (PI if dir.z > 0 else 0.0)
		world.add_child(car)
		var driver = spawn_person("cop", car.position, true)
		driver.in_car = car
		driver.hide()
		driver.collision_layer = 0
		driver.animator.active = false
		car.start_ai(driver, true)
		patrols.append(car)
	refresh_patrols()

func finish(text: String) -> void:
	if outcome != "":
		return
	outcome = text
	outcome_time = 3.5
	combat.aiming = false
	if hero.vehicle != null:
		if text == "АРЕСТОВАН":
			var point: Vector3 = hero.vehicle.exit_position()
			if point.is_finite():
				hero.leave_vehicle(point)
		if hero.vehicle != null:
			hero.vehicle.exit_requested = true
	if hero.vehicle == null:
		hero.play_clip("death" if text == "ПОТРАЧЕНО" else "knocked_down")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func respawn() -> void:
	if hero.vehicle != null:
		hero.leave_vehicle(Vector3(98, 0.4, 24))
	for car in patrols:
		if is_instance_valid(car):
			if is_instance_valid(car.driver) and car.driver.in_car == car:
				car.driver.queue_free()
			car.queue_free()
	patrols.clear()
	for person in officers:
		if is_instance_valid(person):
			person.queue_free()
	officers.clear()
	wanted = 0
	heat = 0
	unseen = 0
	health = 100
	immunity = 4
	outcome = ""
	hurt = 0
	combat.reset_inventory()
	hero.global_position = Vector3(98, 0.4, 24)
	hero.velocity = Vector3.ZERO
	hero.reset_physics_interpolation()
	hero.visual.show()
	hero.yaw = 0.38
	hero.pitch = -0.16
	hero.play_clip("idle")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	hurt = maxf(0, hurt - delta)
	impact_flash = maxf(0, impact_flash - delta)
	immunity = maxf(0, immunity - delta)
	wanted_timer = maxf(0, wanted_timer - delta)
	severe_timer = maxf(0, severe_timer - delta)
	if outcome != "":
		outcome_time -= delta
		if outcome_time <= 0:
			respawn()
		return
	if not active:
		return
	police_timer -= delta
	if police_timer <= 0:
		police_timer = 2.5
		replenish_police()
	if wanted > 0:
		if seen:
			unseen = 0
			last_seen_position = hero.global_position
		else:
			unseen += delta
		seen = false
		heat = maxf(0, heat - delta)
		if unseen > 10 and heat <= 0:
			wanted -= 1
			unseen = 4
			refresh_patrols()
