extends SceneTree

var game: Node3D
var hero
var city
var frame := 0
var victim

func _initialize() -> void:
	seed(34)
	call_deferred("run")

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	hero = game.hero
	city = game.life
	city.immunity = 999
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	process_frame.connect(tick)

func tick() -> void:
	frame += 1
	if frame == 35:
		hero.position = Vector3(101.4, 0.4, 19)
		hero.velocity = Vector3.ZERO
		hero.reset_physics_interpolation()
		hero.yaw = 0
		hero.pitch = -0.045
	if frame == 55:
		city.combat.give(1)
		Input.action_press("aim")
	if frame == 75:
		var target: Vector3 = hero.camera.global_position - hero.camera.global_basis.z * 13
		victim = city.spawn_person("tourist", Vector3(target.x, 0.2, target.z))
		victim.set_physics_process(false)
	if frame == 85:
		city.combat.attack()
		victim.set_physics_process(true)
	if frame == 105:
		city.combat.reload()
	if frame == 120:
		city.wanted = 5
		city.last_seen_position = hero.global_position
		city.heat = 10
		for i in 6:
			city.replenish_police()
	if frame == 150:
		Input.action_release("aim")
		hero.yaw = 0.65
	if frame == 180:
		city.immunity = 0
		city.damage(200)
	if frame in [28, 80, 95, 145, 175, 195, 295]:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://shots/final_review_%d.png" % frame)
	if frame == 300:
		quit()
