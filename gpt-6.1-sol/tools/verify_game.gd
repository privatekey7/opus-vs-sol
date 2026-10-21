extends SceneTree

var failures := 0

func check(condition: bool, description: String) -> void:
	print("PASS: " if condition else "FAIL: ", description)
	if not condition:
		failures += 1

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	game.simulation_enabled = false
	root.add_child(game)
	var player: CharacterBody3D = game.hero
	await frames(45)
	check(player.is_on_floor(), "Hero settles on promenade")
	var origin := player.position
	Input.action_press("move_forward")
	await frames(60)
	Input.action_release("move_forward")
	var walked := player.position.distance_to(origin)
	check(walked > 3 and walked < 5, "WASD walking speed and movement")
	await frames(20)
	origin = player.position
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await frames(60)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	check(player.position.distance_to(origin) > walked * 1.6, "Shift runs faster")
	await frames(20)
	var floor_y := player.position.y
	Input.action_press("jump")
	await frames(12)
	Input.action_release("jump")
	check(player.position.y > floor_y + 0.5, "Jump rises above floor")
	await frames(70)
	check(player.is_on_floor(), "Jump lands")
	# Нативная коллизия отеля у набережной.
	player.position = Vector3(98, 0.5, 31)
	player.yaw = 0
	await frames(25)
	Input.action_press("move_left")
	await frames(240)
	Input.action_release("move_left")
	check(player.position.x > 88, "Imported hotel collision blocks hero")
	player.position = Vector3(147, 0.5, 50)
	await frames(30)
	Input.action_press("move_right")
	await frames(120)
	Input.action_release("move_right")
	check(player.position.x < 150, "Shoreline boundary blocks exit")
	var hud = game.get_children().filter(func(n): return n is CanvasLayer)[0]
	hud.toggle_pause()
	check(paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and hud.pause_panel.visible, "Pause freezes tree and frees cursor")
	hud.toggle_pause()
	check(not paused and (DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED), "Continue resumes game and camera")
	player.position = Vector3(91, 0.3, 31)
	player.yaw = -PI / 2
	player.pitch = -0.1
	await frames(30)
	check(player.camera.position.z < 4.9, "Camera sphere sweep detects hotel wall")
	check(game.signals.size() >= 40, "Every intersection has traffic signals")
	print("VERIFICATION: ", failures, " failures")
	quit(1 if failures else 0)
