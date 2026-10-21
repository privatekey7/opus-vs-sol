extends Node3D

const HeroController = preload("res://scripts/hero.gd")
const GameHUD = preload("res://scripts/hud.gd")
const VehicleController = preload("res://scripts/vehicle.gd")
const CityLife = preload("res://scripts/city_life.gd")
const STREETS := [-180.0, -100.0, -20.0, 60.0]
const AVENUES := [-160.0, -80.0, 0.0, 80.0, 160.0]
var cache: Dictionary = {}
var materials: Dictionary = {}
var batches: Dictionary = {}
var signals: Array[MeshInstance3D] = []
var hero: CharacterBody3D
var signal_time := -1
var benchmark_frames := 0
var benchmark_elapsed := 0.0
var benchmark_worst := 0.0
var life
var simulation_enabled := true
var traffic_clock := 0.0
var signal_materials: Dictionary = {}

func _exit_tree() -> void:
	preload("res://scripts/sound_bank.gd").cache.clear()

func _ready() -> void:
	setup_input()
	setup_environment()
	build_ground()
	build_roads()
	build_blocks()
	build_seafront()
	build_vehicles()
	flush_batches()
	hero = HeroController.new()
	hero.name = "Hero"
	hero.position = Vector3(98, 0.4, 24)
	hero.yaw = 0.38
	add_child(hero)
	life = CityLife.new()
	life.world = self
	life.hero = hero
	life.active = simulation_enabled
	add_child(life)
	var hud := GameHUD.new()
	hud.hero = hero
	add_child(hud)
	if "--tour" in OS.get_cmdline_user_args():
		hero.set_physics_process(false)
		hero.set_process(false)
		hero.set_process_unhandled_input(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("LAS BRISAS ready | Forward+ | 1920x1080 | FSR 70%")

func setup_input() -> void:
	var actions := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "sprint": KEY_SHIFT, "jump": KEY_SPACE, "pause": KEY_ESCAPE, "show_fps": KEY_F3, "interact": KEY_E}
	for action in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = actions[action]
		InputMap.action_add_event(action, event)
	for spec in [["aim", MOUSE_BUTTON_RIGHT], ["fire", MOUSE_BUTTON_LEFT]]:
		if not InputMap.has_action(spec[0]):
			InputMap.add_action(spec[0])
		var event := InputEventMouseButton.new()
		event.button_index = spec[1]
		InputMap.action_add_event(spec[0], event)
	for spec in [["reload", KEY_R], ["weapon_1", KEY_1], ["weapon_2", KEY_2], ["weapon_3", KEY_3]]:
		if not InputMap.has_action(spec[0]):
			InputMap.add_action(spec[0])
		var event := InputEventKey.new()
		event.physical_keycode = spec[1]
		InputMap.action_add_event(spec[0], event)

func mat(color: String, emission := false) -> StandardMaterial3D:
	var key := color + str(emission)
	if materials.has(key):
		return materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.roughness = 0.88
	if emission:
		m.emission_enabled = true
		m.emission = Color(color)
		m.emission_energy_multiplier = 1.8
	materials[key] = m
	return m

func setup_environment() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("51899e")
	sky_material.sky_horizon_color = Color("f7bdab")
	sky_material.ground_bottom_color = Color("496c75")
	sky_material.ground_horizon_color = Color("f7bdab")
	sky_material.sky_curve = 0.18
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a4c5da")
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("e7b8af")
	env.fog_density = 0.0013
	env.fog_sky_affect = 0.15
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32, -55, 0)
	sun.light_color = Color("ffd3a6")
	sun.light_energy = 1.65
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 62
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 0.25
	sun.directional_shadow_blend_splits = true
	add_child(sun)

func box(pos: Vector3, size: Vector3, color: String, solid := false) -> void:
	if not batches.has(color):
		batches[color] = []
	batches[color].append(Transform3D(Basis.IDENTITY.scaled(size), pos))
	if solid:
		wall(pos, size)

func wall(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cube := BoxShape3D.new()
	cube.size = size
	shape.shape = cube
	body.position = pos
	body.add_child(shape)
	add_child(body)

func flush_batches() -> void:
	for color in batches:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE
		cube.material = mat(color)
		multi.mesh = cube
		multi.instance_count = batches[color].size()
		for i in multi.instance_count:
			multi.set_instance_transform(i, batches[color][i])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multi
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
	batches.clear()

func asset(category: String, id: String, pos: Vector3, angle := 0.0) -> Node3D:
	var path := "res://assets/%s/%s.glb" % [category, id]
	if not cache.has(path):
		cache[path] = load(path)
	var node: Node3D = cache[path].instantiate()
	node.position = pos
	node.rotation.y = angle
	add_child(node)
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		mesh.visibility_range_end = 180.0 if category == "buildings" else 85.0
		mesh.visibility_range_end_margin = 8.0
		mesh.lod_bias = 0.35
		if category != "buildings":
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

func build_ground() -> void:
	box(Vector3(-35, -0.6, 0), Vector3(370, 1, 400), "b7af96", true)
	box(Vector3(131, -0.14, 0), Vector3(38, 0.24, 400), "e5ca98", true)
	box(Vector3(103, 0.02, 0), Vector3(18, 0.24, 400), "dabbb1", true)
	# Граница океана совпадает с кромкой воды. Плавание — отдельная механика.
	wall(Vector3(150, 8, 0), Vector3(1, 20, 402))
	wall(Vector3(-221, 8, 0), Vector3(2, 20, 404))
	for z in [-201, 201]:
		wall(Vector3(-35, 8, z), Vector3(374, 20, 2))
		box(Vector3(-35, 0.4, z + (1 if z < 0 else -1)), Vector3(370, 0.8, 0.7), "b4c8c6", true)
	box(Vector3(-219, 0.4, 0), Vector3(0.7, 0.8, 400), "b4c8c6", true)
	var ocean := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2200, 2200)
	var water := ShaderMaterial.new()
	water.shader = load("res://scripts/ocean.gdshader")
	plane.material = water
	ocean.mesh = plane
	ocean.position = Vector3(1250, -0.08, 0)
	add_child(ocean)

func build_roads() -> void:
	for x in STREETS:
		box(Vector3(x, -0.025, 0), Vector3(15, 0.12, 400), "3a4952", true)
		for side in [-1, 1]:
			var start := -200.0
			for finish in [-171.5, -91.5, -11.5, 68.5, 148.5, 200.0]:
				box(Vector3(x + side * 9.5, 0.035, (start + finish) / 2), Vector3(4, 0.25, finish - start), "c5c1b5", true)
				start = finish + 23.0
		for z in range(-195, 200, 9):
			if near_avenue(z, 13):
				continue
			for offset in [-0.18, 0.18]:
				box(Vector3(x + offset, 0.0435, z), Vector3(0.12, 0.015, 4.2), "ecc88a")
	for z in AVENUES:
		box(Vector3(-65, 0.045, z), Vector3(310, 0.06, 15), "3a4952", true)
		for side in [-1, 1]:
			var start := -220.0
			for finish in [-191.5, -111.5, -31.5, 48.5, 90.0]:
				box(Vector3((start + finish) / 2, 0.035, z + side * 9.5), Vector3(finish - start, 0.25, 4), "c5c1b5", true)
				start = finish + 23.0
		for x in range(-213, 86, 9):
			if near_street(x, 13):
				continue
			for offset in [-0.18, 0.18]:
				box(Vector3(x, 0.0835, z + offset), Vector3(4.2, 0.015, 0.12), "ecc88a")
		for x in STREETS:
			# Плоская поверхность перекрёстка перекрывает бордюры; разрывы тротуаров ниже.
			for side in [-1, 1]:
				for stripe in range(-5, 6, 2):
					box(Vector3(x + stripe, 0.0435, z + side * 12), Vector3(1.0, 0.015, 3), "f2e6cd")
					box(Vector3(x + side * 12, 0.0835, z + stripe), Vector3(3, 0.015, 1.0), "f2e6cd")
				var pole_pos := Vector3(x + side * 10.8, 0.17, z - side * 10.8)
				add_signal(pole_pos, PI if side < 0 else 0.0, 0)
			add_signal(Vector3(x - 10.8, 0.17, z - 10.8), PI / 2, 1)
	# Широкая прибрежная пешеходная полоса.
	for z in range(-180, 200, 16):
		box(Vector3(103, 0.151, z), Vector3(17, 0.012, 0.12), "eddfce")

func near_avenue(z: float, distance: float) -> bool:
	for road in AVENUES:
		if absf(z - road) < distance:
			return true
	return false

func near_street(x: float, distance: float) -> bool:
	for road in STREETS:
		if absf(x - road) < distance:
			return true
	return false

func build_blocks() -> void:
	var index := 0
	for x in [-140, -60, 20]:
		for z in [-120, -40, 40, 120]:
			box(Vector3(x, -0.015, z), Vector3(55, 0.18, 55), "99ad91", true)
			for dx in [-17, 17]:
				for dz in [-17, 17]:
					var id: String = ["apartment", "office", "store", "hotel"][(index + (1 if dz > 0 else 0)) % 4]
					if x == 20 and z == -120:
						id = "motel" if dx < 0 else "gasstation"
					asset("buildings", id, Vector3(x + dx, 0.08, z + dz), PI if dz > 0 else 0)
				index += 1
			for dz in [-23, 23]:
				asset("props", "palm", Vector3(x, 0.1, z + dz))
			asset("props", "hydrant", Vector3(x + 28, 0.17, z - 27))
	for z in [-182, 182]:
		for x in [-140, -60, 20]:
			asset("buildings", "store" if x == -60 else "motel", Vector3(x, 0, z), PI if z > 0 else 0)
	# Витрины вдоль бульвара, фасады к океану.
	for z in range(-185, 190, 27):
		if near_avenue(z, 18):
			continue
		asset("buildings", "hotel" if z % 2 else "motel", Vector3(82, 0, z), -PI / 2)
	for z in [-112, 46, 130]:
		asset("props", "busstop", Vector3(70.8, 0.17, z), PI / 2)
		asset("props", "atm", Vector3(92, 0.17, z + 9), -PI / 2)
	for x in STREETS:
		for z in range(-182, 190, 43):
			if not near_avenue(z, 18):
				asset("props", "lamp", Vector3(x - 9, 0.17, z), PI / 2)
	add_sign("ЛАС-БРИСАС", Vector3(96, 5.5, 11), PI / 2, Color("92e4dc"), 70)
	add_sign("O C E A N   D R I V E", Vector3(95, 4.4, 11), PI / 2, Color("ffc5bc"), 35)
	add_sign("PALMS MOTEL", Vector3(3, 8.8, -145), PI, Color("ffb5cb"), 45)
	add_sign("BRISA • FUEL", Vector3(37, 6.4, -146), PI, Color("a2f1df"), 35)

func build_vehicles() -> void:
	var kinds := ["convertible", "sedan", "sportscar", "supercar", "taxi", "police", "ambulance", "pickup", "van", "bus"]
	var spots := [Vector2(64.5, 20), Vector2(-24.5, 110), Vector2(64.5, 48), Vector2(-15.5, 35), Vector2(-95.5, -40), Vector2(-104.5, 112), Vector2(-175.5, -118), Vector2(-184.5, 35), Vector2(55.5, -115), Vector2(64, 112)]
	for i in kinds.size():
		var car := VehicleController.new()
		car.kind = kinds[i]
		car.name = kinds[i]
		car.position = Vector3(spots[i].x, 0.4, spots[i].y)
		car.rotation.y = PI if i % 3 == 1 else 0.0
		add_child(car)

func nearest_vehicle():
	var closest = null
	var distance := 2.4
	for car in get_tree().get_nodes_in_group("vehicles"):
		var d: float = car.approach_distance(hero.global_position)
		if d < distance:
			var local: Vector3 = car.to_local(hero.global_position + Vector3.UP)
			local.x = clampf(local.x, -car.dimensions.x * 0.4, car.dimensions.x * 0.4)
			local.z = clampf(local.z, -car.dimensions.z * 0.4, car.dimensions.z * 0.4)
			var ray := PhysicsRayQueryParameters3D.create(hero.global_position + Vector3.UP, car.to_global(local), 1)
			var hit := get_world_3d().direct_space_state.intersect_ray(ray)
			if hit.is_empty() or hit.collider == car:
				closest = car
				distance = d
	return closest

func interact() -> void:
	if life != null and life.outcome != "":
		return
	if hero.vehicle != null:
		hero.vehicle.exit_requested = true
		if absf(hero.vehicle.speed) < 0.5 and hero.vehicle.planar_velocity.length() < 0.5:
			try_exit_vehicle()
	else:
		var car = nearest_vehicle()
		if car != null:
			if car.ai_driver:
				car.eject_driver()
			hero.enter_vehicle(car)
			if life.witnessed(car.global_position):
				life.crime(1, car.global_position)

func add_signal(point: Vector3, angle: float, axis: int) -> void:
	var model := asset("props", "trafficlight", point, angle)
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		if not signal_materials.has(axis):
			var source: StandardMaterial3D = mesh.get_active_material(0)
			var material := ShaderMaterial.new()
			material.shader = load("res://scripts/traffic_signal.gdshader")
			material.set_shader_parameter("albedo_texture", source.albedo_texture)
			material.set_shader_parameter("tint", source.albedo_color)
			material.set_shader_parameter("mesh_to_root", model.global_transform.affine_inverse() * mesh.global_transform)
			signal_materials[axis] = material
		mesh.material_override = signal_materials[axis]
		mesh.visibility_range_end = 70
		mesh.set_meta("axis", axis)
		signals.append(mesh)

func signal_green(axis: int) -> bool:
	var phase := fmod(traffic_clock + (12.0 if axis == 1 else 0.0), 24.0)
	return phase < 10

func try_exit_vehicle() -> void:
	var point: Vector3 = hero.vehicle.exit_position()
	if point.is_finite():
		hero.leave_vehicle(point)
	else:
		hero.vehicle.exit_requested = false
		hero.notice = "Выход перекрыт — отъедьте от препятствия"
		hero.notice_time = 3.0

func build_seafront() -> void:
	for z in range(-188, 200, 23):
		asset("props", "palm", Vector3(110, 0.17, z), z * 0.22)
		if not near_avenue(z, 13):
			asset("props", "palm", Vector3(94, 0.17, z + 4), z * 0.12)
		asset("props", "bench", Vector3(108, 0.17, z + 6), -PI / 2)
		asset("props", "trashcan", Vector3(108.4, 0.17, z + 9))
	for z in range(-180, 190, 19):
		for x in [125, 139]:
			if absf(z - 29) < 12 or absf(z + 104) < 12:
				continue
			asset("props", "umbrella", Vector3(x, 0, z), -PI / 2 + sin(z) * 0.3)
	asset("buildings", "beachhouse", Vector3(127, 0, 28), -PI / 2)
	asset("buildings", "beachhouse", Vector3(126, 0, -104), -PI / 2)
	# Песчаный подход к берегу и тонкая полоса прибоя.
	box(Vector3(148.6, -0.025, 0), Vector3(2.5, 0.025, 400), "eae0c0")

func add_sign(text: String, pos: Vector3, angle: float, color: Color, font_size: int) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.rotation.y = angle
	label.font_size = font_size
	label.pixel_size = 0.012
	label.modulate = color
	label.outline_size = 5
	label.no_depth_test = false
	label.double_sided = false
	label.visibility_range_end = 90
	add_child(label)

func _process(delta: float) -> void:
	traffic_clock += delta
	var phase := int(fmod(traffic_clock, 24.0))
	if phase != signal_time:
		signal_time = phase
		for axis in signal_materials:
			var t: int = (phase + (12 if axis == 1 else 0)) % 24
			var material: ShaderMaterial = signal_materials[axis]
			material.set_shader_parameter("signal_color", Vector3(0.12, 1, 0.3) if t < 10 else (Vector3(1, 0.65, 0.08) if t < 12 else Vector3(1, 0.06, 0.03)))
			material.set_shader_parameter("signal_height", 2.1 if t < 10 else (2.73 if t < 12 else 3.35))
	if "--tour" in OS.get_cmdline_user_args():
		var t := Time.get_ticks_msec() * 0.001
		hero.pivot.rotation = Vector3(-0.18, 0.38 + sin(t * 0.18) * 0.75, 0)
	if not get_tree().paused and Engine.get_frames_drawn() > 120:
		benchmark_frames += 1
		benchmark_elapsed += delta
		benchmark_worst = maxf(benchmark_worst, delta)
		if benchmark_frames == 450:
			print("PERF: %0.1f FPS average; slowest frame %0.1f ms; GPU: %s" % [benchmark_frames / benchmark_elapsed, benchmark_worst * 1000, RenderingServer.get_video_adapter_name()])
