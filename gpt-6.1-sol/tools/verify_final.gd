extends SceneTree

var failures := 0
var game: Node3D
var hero
var city

func check(ok: bool, label: String) -> void:
	print("PASS: " if ok else "FAIL: ", label)
	if not ok:
		failures += 1

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func place(node: Node3D, point: Vector3, angle := 0.0) -> void:
	node.global_position = point
	node.rotation = Vector3(0, angle, 0)
	node.velocity = Vector3.ZERO
	if node.is_in_group("vehicles"):
		node.speed = 0
		node.planar_velocity = Vector3.ZERO
	node.reset_physics_interpolation()

func key(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	hero._unhandled_input(event)

func _initialize() -> void:
	seed(493)
	call_deferred("run")

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	hero = game.hero
	city = game.life
	city.immunity = 999
	await frames(120)
	var people := get_nodes_in_group("people")
	var kinds: Dictionary = {}
	for person in people:
		kinds[person.kind] = true
	check(people.size() >= 14 and kinds.size() == 7, "All seven non-hero people types populate city")
	var walker = people[0]
	var before: Vector3 = walker.position
	await frames(120)
	check(walker.position.distance_to(before) > 1, "Pedestrians actually walk on sidewalk routes")
	check(city.routes.walk.get_point_path(0, 79).size() > 4 and city.routes.road.get_point_path(0, 19).size() > 3, "Connected walking and street routes go around blocks")
	check(game.signals.size() >= 40 and game.signals[0].material_override is ShaderMaterial and game.signals[0].mesh is ArrayMesh, "Traffic lamps use original lens shader, no floating circle")
	# Трафик: остановка до перекрёстка, затем возобновление движения.
	var cars := get_nodes_in_group("vehicles")
	var traffic = cars[2]
	for car in cars:
		car.ai_driver = false
		car.speed = 0
		car.planar_velocity = Vector3.ZERO
	place(traffic, Vector3(-177, 0.3, 25))
	await frames(25)
	traffic.ai_driver = true
	traffic.overtake = PackedVector3Array()
	traffic.overtake_index = 0
	traffic.recovery = 0
	traffic.ai_stuck = 0
	traffic.steer = 0
	traffic.speed = 8
	traffic.planar_velocity = Vector3(0, 0, -8)
	traffic.ai_route = PackedVector3Array([Vector3(-177, 0.16, 0), Vector3(-177, 0.16, -80)])
	traffic.ai_index = 0
	traffic.ai_timer = 100
	game.traffic_clock = 12.5
	await frames(180)
	print("RED STATE: position=", traffic.position, " yaw=", traffic.rotation.y, " speed=", traffic.speed, " waiting=", traffic.waiting_red)
	check(traffic.waiting_red and absf(traffic.speed) < 0.5 and traffic.position.z > 6, "Civilian driver stops at red before intersection")
	var stopped_z: float = traffic.position.z
	game.traffic_clock = 0
	await frames(120)
	check(traffic.position.z < stopped_z - 3, "Civilian driver continues on green")
	traffic.ai_driver = false
	place(traffic, Vector3(63, 0.3, 36))
	await frames(25)
	traffic.start_ai(traffic.driver)
	place(hero, traffic.exit_position())
	await frames(5)
	var driver = traffic.driver
	key("interact")
	check(hero.vehicle == traffic and not traffic.ai_driver and driver.in_car == null and driver.visible, "E ejects actual driver and transfers driving to hero")
	check(city.wanted > 0, "Witnessed carjacking causes wanted level")
	key("interact")
	await frames(10)
	check(hero.vehicle == null and hero.visual.visible, "Exit after carjacking restores walking")
	# Изолируем последующие попадания от движения посторонних.
	city.active = false
	for person in get_nodes_in_group("people"):
		person.set_physics_process(false)
	for car in get_nodes_in_group("vehicles"):
		car.ai_driver = false
		car.speed = 0
		car.planar_velocity = Vector3.ZERO
	for pickup in city.combat.pickups.slice(0, 3):
		place(hero, pickup.global_position + Vector3.UP * 0.4)
		await frames(35)
	check(city.combat.owned == [true, true, true], "All three nearby world weapons are picked up")
	key("weapon_1")
	check(city.combat.selected == 0, "Key 1 selects bat")
	key("weapon_2")
	check(city.combat.selected == 1, "Key 2 selects pistol")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	hero._unhandled_input(wheel)
	check(city.combat.selected == 2, "Mouse wheel cycles owned weapons")
	key("weapon_2")
	place(hero, Vector3(103, 0.4, 24))
	hero.yaw = 0
	hero.pitch = -0.045
	Input.action_press("aim")
	await frames(70)
	check((-city.combat.weapon.global_basis.z.normalized()).dot(-hero.camera.global_basis.z) > 0.98, "Held firearm pose points along reticle direction")
	var aim_point: Vector3 = hero.camera.global_position - hero.camera.global_basis.z * 13
	var victim = city.spawn_person("tourist", Vector3(aim_point.x, 0.2, aim_point.z))
	victim.set_physics_process(false)
	await frames(5)
	var ammo: int = city.combat.loaded[1]
	var fired: bool = city.combat.attack()
	check(fired and city.combat.loaded[1] == ammo - 1, "Pistol fires and consumes magazine ammunition")
	check(victim.fallen and city.combat.hit_time > 0, "Reticle/muzzle ray hits person, hit marker appears and victim falls")
	city.combat.reload()
	check(city.combat.reloading > 0, "Reload starts")
	await frames(100)
	check(city.combat.loaded[1] == 12 and city.combat.reserve[1] == 59, "Reload transfers reserve ammunition into magazine")
	key("weapon_3")
	check(city.combat.attack() and city.combat.loaded[2] == 5, "Shotgun fires pellets and spends one shell")
	await frames(60)
	key("weapon_1")
	var melee = city.spawn_person("thug", hero.position + Vector3(0, 0, -1.75))
	melee.set_physics_process(false)
	await frames(5)
	check(city.combat.attack() and melee.fallen, "Bat swing hits and knocks down nearby person")
	Input.action_release("aim")
	var scared = people[1]
	city.gunfire(scared.position, false)
	check(scared.fear > 0, "Bystanders flee from gunfire")
	# Преступления, полиция и пули.
	city.active = true
	city.wanted = 0
	city.wanted_timer = 0
	city.severe_timer = 0
	var cop = city.spawn_person("cop", hero.position + Vector3(0, 0, -10), true)
	cop.set_physics_process(false)
	cop.take_damage(10, hero.position, true)
	check(city.wanted >= 2, "Assault on police escalates wanted level")
	city.active = false
	city.immunity = 0
	city.health = 100
	city.police_shoot(cop)
	check(city.health < 100 and city.hurt > 0, "Police bullet trace damages hero")
	for i in 5:
		city.active = true
		city.wanted_timer = 0
		city.crime(1, hero.position)
	city.active = false
	check(city.wanted == 5, "Wanted level reaches and caps at five stars")
	city.replenish_police()
	city.replenish_police()
	city.replenish_police()
	city.replenish_police()
	city.replenish_police()
	check(city.officers.size() >= 6 and city.patrols.size() == 3, "Five stars recruit more foot cops and three patrol cars")
	check(city.patrols[0].siren.playing and city.patrols[0].beacons.size() == 2, "Patrol siren and alternating roof lights are enabled")
	for person in get_nodes_in_group("people"):
		person.set_physics_process(false)
	for patrol in city.patrols:
		patrol.set_physics_process(false)
		patrol.police_ai = false
	city.active = true
	city.police_timer = 999
	city.seen = false
	city.unseen = 0
	city.heat = 10
	await frames(2100)
	check(city.wanted == 0, "Wanted stars fade after sustained escape from observation")
	city.active = false
	# Арест, восстановление и смерть с очисткой оружия.
	city.wanted = 1
	place(cop, hero.position + Vector3(1.05, 0, 0))
	cop.set_physics_process(true)
	await frames(3)
	check(city.outcome == "АРЕСТОВАН", "Close foot cop arrests wanted pedestrian")
	cop.set_physics_process(false)
	await frames(230)
	check(city.outcome == "" and city.health == 100 and city.wanted == 0 and city.combat.selected == -1, "Arrest respawn clears wanted, weapons and restores health")
	city.combat.give(1)
	city.immunity = 0
	city.health = 10
	city.wanted = 2
	city.damage(20)
	check(city.outcome == "ПОТРАЧЕНО", "Lethal damage displays spent screen")
	await frames(230)
	check(city.outcome == "" and city.health == 100 and city.wanted == 0 and not city.combat.owned.has(true), "Death respawn removes all weapons and wanted stars")
	# Арест игрока в остановившейся машине.
	var car = cars[0]
	place(car, Vector3(63, 0.4, 24))
	await frames(20)
	hero.enter_vehicle(car)
	city.wanted = 1
	var officer = city.spawn_person("cop", car.exit_position() + Vector3(0.5, 0, 0), true)
	await frames(5)
	check(city.outcome == "АРЕСТОВАН", "Cop at driver door arrests and extracts stopped driver")
	officer.set_physics_process(false)
	await frames(230)
	check(hero.vehicle == null and hero.visual.visible and city.wanted == 0, "Car arrest respawn restores hero on foot")
	print("FINAL VERIFICATION: ", failures, " failures")
	quit(1 if failures else 0)
