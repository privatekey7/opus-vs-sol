extends SceneTree

var failures := 0
var game: Node3D
var player: CharacterBody3D

func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func teleport(node: Node3D, point: Vector3, angle := 0.0) -> void:
	node.position = point
	node.rotation = Vector3(0, angle, 0)
	node.velocity = Vector3.ZERO
	if node.is_in_group("vehicles"):
		node.planar_velocity = Vector3.ZERO
	node.reset_physics_interpolation()

func key_e() -> void:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	player._unhandled_input(event)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.simulation_enabled = false
	root.add_child(game)
	player = game.hero
	await frames(45)
	var cars := get_nodes_in_group("vehicles")
	check(cars.size() == 10, "All ten vehicle kinds exist")
	for car in cars:
		var point: Vector3 = car.exit_position()
		check(point.is_finite(), "%s has clear door exit" % car.kind)
		if not point.is_finite():
			continue
		teleport(player, point)
		await frames(5)
		key_e()
		check(player.vehicle == car and not player.visual.visible and car.occupied, "E enters %s" % car.kind)
		check(car.wheels.size() == 4 and car.wheels[0] != null and car.motor.playing, "%s wheels and synthesized motor ready" % car.kind)
		var before: Vector3 = car.position
		Input.action_press("move_forward")
		await frames(60)
		Input.action_release("move_forward")
		check(car.position.distance_to(before) > 1 and absf(car.rotation.x) < 0.001 and absf(car.rotation.z) < 0.001, "%s drives upright on its street" % car.kind)
		Input.action_press("jump")
		await frames(40)
		Input.action_release("jump")
		key_e()
		await frames(45)
		check(player.vehicle == null and player.visual.visible and not car.occupied, "E exits %s" % car.kind)
	# Прямая длинная улица, без зданий и машин на пути.
	var car = cars[0]
	teleport(car, Vector3(-180, 0.4, 130))
	await frames(25)
	teleport(player, car.exit_position())
	await frames(5)
	key_e()
	var start: Vector3 = car.position
	Input.action_press("move_forward")
	await frames(120)
	Input.action_release("move_forward")
	check(car.speed > 10 and car.position.z < start.z - 10, "W accelerates forward along -Z")
	check(car.spins[0] < 0 or absf(car.spins[0]) > 0.01, "Wheels roll during travel")
	check(car.rpm > 1100, "Engine RPM rises with gas and speed")
	Input.action_press("move_left")
	await frames(25)
	Input.action_release("move_left")
	check(car.steer > 0.1 and car.rotation.y > 0.05, "A turns front wheels and car left")
	Input.action_press("jump")
	Input.action_press("move_left")
	var skid_seen := false
	for i in 30:
		await physics_frame
		skid_seen = skid_seen or car.drifting
	Input.action_release("move_left")
	check(skid_seen, "Handbrake retains lateral momentum and produces drift")
	await frames(150)
	Input.action_release("jump")
	check(absf(car.speed) < 0.1, "Space handbrake stops car")
	teleport(car, Vector3(-180, 0.4, 100))
	await frames(25)
	Input.action_press("move_back")
	await frames(80)
	Input.action_release("move_back")
	check(car.speed < -2 and car.position.z > 102, "S selects reverse from stop")
	key_e()
	await frames(90)
	check(player.vehicle == null and car.speed == 0, "E brakes moving car and exits safely")
	# Столкновение с неподвижной машиной.
	var target = cars[1]
	teleport(target, Vector3(-180, 0.4, 80))
	teleport(car, Vector3(-180, 0.4, 94))
	await frames(30)
	teleport(player, car.exit_position())
	await frames(3)
	key_e()
	Input.action_press("move_forward")
	var hit_seen := false
	for i in 180:
		await physics_frame
		hit_seen = hit_seen or car.impact > 0.1
	Input.action_release("move_forward")
	check(hit_seen and car.position.z > 84, "Collision with another car blocks travel and produces impact")
	# Удар о закрытый фасад отеля: движение на запад.
	car.speed = 0
	teleport(car, Vector3(102, 0.4, 31), PI / 2)
	await frames(25)
	Input.action_press("move_forward")
	hit_seen = false
	var visible_feedback := false
	for i in 180:
		await physics_frame
		hit_seen = hit_seen or car.impact > 0.1
		visible_feedback = visible_feedback or (game.life.impact_flash > 0 and game.life.fx.get_child_count() > 0)
	Input.action_release("move_forward")
	check(hit_seen and car.position.x > 90, "Building collision blocks vehicle and produces impact")
	check(visible_feedback, "Wall impact creates particles, crash sound and HUD flash")
	check(absf(car.rotation.x) < 0.001 and absf(car.rotation.z) < 0.001 and car.position.y > -0.2 and car.position.y < 0.5, "Vehicle remains upright and on ground after impact")
	var jammed_x: float = car.position.x
	Input.action_press("move_back")
	Input.action_press("move_left")
	await frames(120)
	Input.action_release("move_back")
	Input.action_release("move_left")
	check(car.position.x > jammed_x + 1, "Reverse with steering frees vehicle after wall collision")
	car.speed = 0
	teleport(car, Vector3(-180, 0.4, 100))
	await frames(30)
	var hud = game.get_children().filter(func(n): return n is CanvasLayer)[0]
	hud.toggle_pause()
	check(paused, "Pause works while driving")
	hud.toggle_pause()
	key_e()
	await frames(10)
	check(player.vehicle == null and player.collision_layer == 2, "Walking and collisions restored after exit")
	# Обе двери перекрыты: герой не должен появиться внутри препятствия.
	teleport(player, car.exit_position())
	await frames(3)
	key_e()
	var blockers: Array[StaticBody3D] = []
	for side in [-1, 1]:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.3, 3, car.dimensions.z)
		shape.shape = box
		body.add_child(shape)
		body.position = car.position + Vector3(side * (car.dimensions.x / 2 + 0.7), 1.5, 0)
		game.add_child(body)
		blockers.append(body)
	await frames(3)
	key_e()
	check(player.vehicle == car and player.notice_time > 0, "Blocked doors keep hero inside and display explanation")
	for body in blockers:
		body.queue_free()
	await frames(3)
	key_e()
	await frames(3)
	check(player.vehicle == null, "Exit succeeds after doors are clear")
	for sample in [[Vector3(-100, 1, 30), 0.035], [Vector3(-100, 1, 0), 0.075], [Vector3(-109, 1, 30), 0.16]]:
		teleport(player, sample[0])
		await frames(50)
		check(absf(player.position.y - sample[1]) < 0.012, "Feet match road/curb height %.3f" % sample[1])
	teleport(player, Vector3(91, 0.4, 31))
	player.yaw = -PI / 2
	await frames(30)
	check(player.camera_distance < 4.9, "Walking camera still avoids wall")
	var before: float = player.camera_distance
	player.yaw = PI / 2
	await process_frame
	await process_frame
	check(player.camera_distance > before and player.camera_distance < 4.99, "Camera extends smoothly rather than jumping")
	print("VEHICLE VERIFICATION: ", failures, " failures")
	quit(1 if failures else 0)
