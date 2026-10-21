extends SceneTree

var game: Node3D
var hero
var city

func _initialize() -> void:
	seed(128)
	call_deferred("run")

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://shots/%s.png" % name)

func benchmark(name: String) -> void:
	for i in 60:
		await process_frame
	var times: Array[float] = []
	var previous := Time.get_ticks_usec()
	for i in 180:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - previous) / 1000.0)
		previous = now
	var total := 0.0
	for dt in times:
		total += dt
	times.sort()
	print("FINAL BENCH ", name, ": ", snappedf(180000.0 / total, 0.1), " FPS; p95=", snappedf(times[171], 0.1), " ms; max=", snappedf(times[-1], 0.1), " ms; state=", city.outcome)

func place(node: Node3D, point: Vector3, angle := 0.0) -> void:
	node.position = point
	node.rotation = Vector3(0, angle, 0)
	node.velocity = Vector3.ZERO
	if node.is_in_group("vehicles"):
		node.planar_velocity = Vector3.ZERO
		node.speed = 0
	node.reset_physics_interpolation()

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	hero = game.hero
	city = game.life
	city.immunity = 999
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(80)
	await shot("final_city")
	await benchmark("city_life")
	place(hero, Vector3(101.4, 0.4, 19))
	hero.yaw = 0
	hero.pitch = -0.045
	await frames(40)
	city.combat.select(1)
	Input.action_press("aim")
	await frames(60)
	await shot("final_aim")
	print("GUN DIRECTION: ", -city.combat.weapon.global_basis.z.normalized(), " CAMERA: ", -hero.camera.global_basis.z)
	await benchmark("aiming")
	var aim_point: Vector3 = hero.camera.global_position - hero.camera.global_basis.z * 13
	var victim = city.spawn_person("tourist", Vector3(aim_point.x, 0.2, aim_point.z))
	victim.set_physics_process(false)
	await frames(5)
	city.combat.attack()
	victim.set_physics_process(true)
	await shot("final_hit")
	await frames(100)
	await shot("final_fallen")
	city.wanted = 5
	city.last_seen_position = hero.global_position
	city.heat = 10
	for i in 6:
		city.replenish_police()
	Input.action_release("aim")
	hero.yaw = 0.95
	await benchmark("five_stars")
	await shot("final_wanted")
	# Крупный проверочный кадр исходной police и её света, без изменения игры.
	var patrol = city.patrols[0]
	hero.set_process(false)
	hero.pivot.global_position = patrol.global_position + Vector3(0, 2.2, 0)
	hero.pivot.rotation = Vector3(-0.16, patrol.rotation.y + 0.65, 0)
	hero.camera.position = Vector3(0, 0, 7)
	await shot("final_police")
	hero.set_process(true)
	city.immunity = 0
	city.damage(200)
	await frames(18)
	await shot("final_spent")
	await frames(220)
	city.wanted = 1
	var cop = city.spawn_person("cop", hero.position + Vector3(1.05, 0, 0), true)
	await frames(20)
	await shot("final_arrested")
	cop.set_physics_process(false)
	await frames(225)
	await shot("final_respawn")
	var car = get_nodes_in_group("vehicles")[0]
	place(car, Vector3(103, 0.4, 31), PI / 2)
	await frames(25)
	hero.enter_vehicle(car)
	city.immunity = 999
	Input.action_press("move_forward")
	for i in 160:
		await physics_frame
		if car.impact > 0.1:
			break
	Input.action_release("move_forward")
	await frames(9)
	await shot("final_crash")
	Input.action_press("move_back")
	Input.action_press("move_left")
	await frames(100)
	Input.action_release("move_back")
	Input.action_release("move_left")
	place(car, Vector3(-100, 0.4, 140))
	await frames(25)
	car.speed = 18
	car.planar_velocity = Vector3(0, 0, -18)
	Input.action_press("jump")
	Input.action_press("move_left")
	await frames(30)
	await shot("final_drift")
	print("DRIFT: lateral m/s=", absf(car.planar_velocity.dot(car.global_basis.x)), "; wheel center=", car.model.to_local(car.wheels[0].global_position))
	Input.action_release("move_left")
	Input.action_release("jump")
	get_nodes_in_group("vehicles")[0].exit_requested = true
	await frames(150)
	# Кадр светофора показывает именно поверхность GLB, без добавленного кружка.
	place(hero, Vector3(-89, 0.4, -16))
	hero.yaw = 0.8
	hero.pitch = -0.1
	await frames(30)
	await shot("final_signal")
	print("FINAL GALLERY complete")
	quit()
