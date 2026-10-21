extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func save(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://shots/%s.png" % name)

func run() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	game.simulation_enabled = false
	root.add_child(game)
	await frames(35)
	game.life.damage(200)
	await frames(20)
	await save("final_spent")
	await frames(225)
	game.life.wanted = 1
	game.life.spawn_person("cop", game.hero.position + Vector3(1.05, 0, 0), true)
	await frames(20)
	await save("final_arrested")
	await frames(225)
	await save("final_respawn")
	quit()
