extends SceneTree

var game: Node3D
var player: CharacterBody3D
var car: CharacterBody3D
var frame := 0
var frame_clock := 0
var timings: Array[float] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	player = game.hero
	car = get_nodes_in_group("vehicles")[0]
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	process_frame.connect(tick)

func press_e() -> void:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	player._unhandled_input(event)

func tick() -> void:
	frame += 1
	var now := Time.get_ticks_usec()
	if frame > 90 and frame <= 240 and frame_clock > 0:
		timings.append((now - frame_clock) / 1000.0)
	frame_clock = now
	if frame == 20:
		car.position = Vector3(-100, 0.4, 140)
		car.reset_physics_interpolation()
		player.position = car.exit_position()
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
		player.yaw = -0.3
	if frame == 35:
		press_e()
	if frame == 45:
		Input.action_press("move_forward")
	if frame == 155:
		Input.action_release("move_forward")
		Input.action_press("move_left")
	if frame == 165:
		Input.action_release("move_left")
		Input.action_press("jump")
	if frame > 165 and frame < 215:
		player.yaw += 0.04
	if frame == 215:
		Input.action_release("jump")
		press_e()
	if frame in [29, 120, 200, 280]:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://shots/drive_review_%d.png" % frame)
	if frame == 295:
		var sum := 0.0
		for ms in timings:
			sum += ms
		timings.sort()
		print("DRIVE REVIEW: occupied=", player.vehicle != null, "; frames=", timings.size(), "; real average FPS=", 1000.0 * timings.size() / maxf(sum, 1.0), "; p95 ms=", timings[int(timings.size() * 0.95)])
	if frame == 300:
		quit()
