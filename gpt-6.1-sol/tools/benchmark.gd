extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var hero: CharacterBody3D = game.hero
	hero.set_physics_process(false)
	hero.set_process(false)
	hero.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var stops := [
		["promenade", Vector3(100, 0.2, 24), 0.38],
		["downtown", Vector3(-100, 0.2, 0), -0.5],
		["fuel_motel", Vector3(20, 0.2, -157), PI],
		["beach", Vector3(119, 0.2, 35), -1.1],
		["intersection", Vector3(-20, 0.2, -80), 0.6]
	]
	for stop in stops:
		hero.position = stop[1]
		hero.reset_physics_interpolation()
		hero.yaw = stop[2]
		hero.pitch = -0.14
		hero.update_camera(0.0)
		hero.pivot.rotation = Vector3(-0.14, stop[2], 0)
		hero.visual.rotation.y = stop[2] + PI
		for i in 45:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://shots/%s.png" % stop[0])
		var start := Time.get_ticks_usec()
		for i in 180:
			await process_frame
		var elapsed := (Time.get_ticks_usec() - start) / 1000000.0
		print("BENCH ", stop[0], ": ", snappedf(180.0 / elapsed, 0.1), " FPS")
	var hud = game.get_children().filter(func(n): return n is CanvasLayer)[0]
	hud.toggle_pause()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://shots/pause.png")
	quit()
