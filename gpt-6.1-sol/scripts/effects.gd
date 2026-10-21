extends Node3D

const Sounds = preload("res://scripts/sound_bank.gd")
var materials: Dictionary = {}

func glow(color: Color) -> StandardMaterial3D:
	if materials.has(color):
		return materials[color]
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	materials[color] = material
	return material

func burst(point: Vector3, normal := Vector3.UP, color := Color("ffbd66"), count := 15) -> void:
	var particles := CPUParticles3D.new()
	particles.amount = count
	particles.one_shot = true
	particles.explosiveness = 1
	particles.lifetime = 0.55
	particles.direction = normal
	particles.spread = 65
	particles.initial_velocity_min = 2
	particles.initial_velocity_max = 7
	particles.gravity = Vector3(0, -9, 0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.045, 0.045, 0.045)
	mesh.material = glow(color)
	particles.mesh = mesh
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
	particles.global_position = point
	particles.emitting = true
	get_tree().create_timer(0.8, false).timeout.connect(particles.queue_free)

func tracer(from: Vector3, to: Vector3, color := Color("ffe3a0"), duration := 0.075) -> void:
	if from.distance_to(to) < 0.01:
		return
	var line := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.018, 0.018, from.distance_to(to))
	mesh.material = glow(color)
	line.mesh = mesh
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line)
	line.global_position = (from + to) * 0.5
	line.look_at(to, Vector3.FORWARD if absf((to - from).normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP)
	get_tree().create_timer(duration, false).timeout.connect(line.queue_free)

func play_sound(id: String, point: Vector3, volume := 0.0) -> void:
	var audio := AudioStreamPlayer3D.new()
	audio.stream = Sounds.sound(id)
	audio.volume_db = volume
	audio.max_db = 0
	audio.unit_size = 12
	audio.max_distance = 100
	add_child(audio)
	audio.global_position = point
	audio.play()
	audio.finished.connect(audio.queue_free)
