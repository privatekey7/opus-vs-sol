extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	game.simulation_enabled = false
	root.add_child(game)
	var car = get_nodes_in_group("vehicles")[0]
	car.position = Vector3(102, 0.4, 31)
	car.rotation.y = PI / 2
	car.reset_physics_interpolation()
	game.hero.enter_vehicle(car)
	game.life.immunity = 999
	for i in 30:
		await physics_frame
	Input.action_press("move_forward")
	for i in 180:
		await physics_frame
	Input.action_release("move_forward")
	print("JAM START ", car.position, " yaw=", car.rotation.y, " speed=", car.speed)
	Input.action_press("move_back")
	Input.action_press("move_left")
	for i in 150:
		await physics_frame
		if i % 15 == 0:
			print(i, " position=", car.position, " yaw=", car.rotation.y, " speed=", car.speed, " planar=", car.planar_velocity, " floor=", car.is_on_floor(), " contacts=", car.get_slide_collision_count())
	Input.action_release("move_left")
	Input.action_release("move_back")
	quit()
