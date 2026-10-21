extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	game.simulation_enabled = false
	root.add_child(game)
	var player: CharacterBody3D = game.hero
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in 40:
		await physics_frame
	for car in get_nodes_in_group("vehicles"):
		player.position = car.exit_position()
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
		for i in 5:
			await physics_frame
		game.interact()
		for i in 45:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://shots/vehicle_%s.png" % car.kind)
		var started := Time.get_ticks_usec()
		var last := started
		var worst := 0.0
		Input.action_press("move_forward")
		for i in 180:
			player.yaw = sin(i * 0.025) * 0.16
			await process_frame
			var now := Time.get_ticks_usec()
			worst = maxf(worst, (now - last) / 1000.0)
			last = now
		Input.action_release("move_forward")
		var elapsed := (Time.get_ticks_usec() - started) / 1000000.0
		print("DRIVE BENCH ", car.kind, ": ", snappedf(180.0 / elapsed, 0.1), " FPS; slowest=", snappedf(worst, 0.1), " ms; speed=", snappedf(absf(car.speed) * 3.6, 0.1), " km/h")
		game.interact()
		for i in 160:
			await physics_frame
		if player.vehicle != null:
			push_error("Could not exit " + car.kind)
			quit(1)
			return
	print("DRIVE BENCH completed: all ten vehicles")
	quit()
