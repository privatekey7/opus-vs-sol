class_name Game
extends Node3D
## Entry point: loads models in background threads, builds Port Coral, spawns the hero and
## runs the game rules (vehicles, health, wanted level, death and arrest).
##
## Dev command-line options (after "--"):
##   --spawn=x,z,yaw_deg,pitch_deg   start position and camera
##   --bench                          fly the hero through the city and print FPS stats
##   --autowalk [--straight]          scripted walking/jumping for --write-movie captures
##   --autodrive [--quit|--exittest]  scripted driving test
##   --autocombat                     pick up weapons, aim and shoot (captures)
##   --give                           start with all weapons
##   --wanted=N                       start with N stars
##   --uncapped                       no 60 FPS cap; --fixedres disables dynamic resolution

static var inst: Game
static var prof := {}   # dev: accumulated microseconds per system (printed by --bench)


static func dev_int(prefix: String, default: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return int(a.trim_prefix(prefix))
	return default


static func prof_add(key: String, usec: int) -> void:
	prof[key] = prof.get(key, 0) + usec

const GAME_TITLE := "Неоновый прибой"
const CITY_NAME := "Порт-Коралл"
const MODELS := {
	"hero": "res://assets/people/hero.glb",
	"cop": "res://assets/people/cop.glb",
	"tourist": "res://assets/people/tourist.glb",
	"woman": "res://assets/people/woman.glb",
	"thug": "res://assets/people/thug.glb",
	"bikini": "res://assets/people/bikini.glb",
	"jogger": "res://assets/people/jogger.glb",
	"businessman": "res://assets/people/businessman.glb",
	"hotel": "res://assets/buildings/hotel.glb",
	"motel": "res://assets/buildings/motel.glb",
	"apartment": "res://assets/buildings/apartment.glb",
	"office": "res://assets/buildings/office.glb",
	"store": "res://assets/buildings/store.glb",
	"gasstation": "res://assets/buildings/gasstation.glb",
	"beachhouse": "res://assets/buildings/beachhouse.glb",
	"palm": "res://assets/props/palm.glb",
	"lamp": "res://assets/props/lamp.glb",
	"trafficlight": "res://assets/props/trafficlight.glb",
	"hydrant": "res://assets/props/hydrant.glb",
	"bench": "res://assets/props/bench.glb",
	"trashcan": "res://assets/props/trashcan.glb",
	"busstop": "res://assets/props/busstop.glb",
	"atm": "res://assets/props/atm.glb",
	"umbrella": "res://assets/props/umbrella.glb",
	"sedan": "res://assets/vehicles/sedan.glb",
	"sportscar": "res://assets/vehicles/sportscar.glb",
	"supercar": "res://assets/vehicles/supercar.glb",
	"convertible": "res://assets/vehicles/convertible.glb",
	"taxi": "res://assets/vehicles/taxi.glb",
	"police": "res://assets/vehicles/police.glb",
	"ambulance": "res://assets/vehicles/ambulance.glb",
	"pickup": "res://assets/vehicles/pickup.glb",
	"van": "res://assets/vehicles/van.glb",
	"bus": "res://assets/vehicles/bus.glb",
	"bat": "res://assets/weapons/bat.glb",
	"pistol": "res://assets/weapons/pistol.glb",
	"shotgun": "res://assets/weapons/shotgun.glb",
}
const VEHICLE_NAMES := {
	"sedan": "седан", "sportscar": "спорткар", "supercar": "суперкар", "convertible": "кабриолет",
	"taxi": "такси", "police": "полицейская машина", "ambulance": "скорая помощь",
	"pickup": "пикап", "van": "фургон", "bus": "автобус",
}
const PED_MODELS := ["tourist", "woman", "thug", "bikini", "jogger", "businessman"]
const ENTER_DISTANCE := 1.8
const SPAWN := Vector3(84.0, 0.2, 6.0)
const SPAWN_YAW := 90.0   # degrees; camera looks west at the hotels
# Weapon sets: one next to the start, others around the city.
const PICKUP_SETS := [
	[Vector3(82.0, 0.15, -12.0), Vector3(84.0, 0.15, -12.0), Vector3(86.0, 0.15, -12.0)],
	[Vector3(-50.0, 0.15, -65.7), Vector3(-47.0, 0.15, -65.7), Vector3(-44.0, 0.15, -65.7)],
	[Vector3(110.0, 0.0, -45.0), Vector3(112.0, 0.0, -45.0), Vector3(114.0, 0.0, -45.0)],
	[Vector3(-169.3, 0.15, 36.0), Vector3(-169.3, 0.15, 39.0), Vector3(-169.3, 0.15, 42.0)],
]

enum PlayState { PLAYING, WASTED, BUSTED }

var scenes := {}
var hero: Hero
var rig: CameraRig
var hud: Hud
var pause_menu: PauseMenu
var traffic: TrafficLights
var nav: NavGrid
var npcs: NpcManager
var traffic_ai: TrafficManager
var wanted: WantedSystem
var pickups: Pickups
var fx: Fx
var solid_rects: Array[Rect2] = []
var vehicles: Array[Vehicle] = []
var driving: Vehicle = null
var play_state := PlayState.PLAYING

var _loading := true
var _load_ui: CanvasLayer
var _load_bar: ProgressBar
var _load_label: Label
var _build_frames := 0
var _state_t := 0.0

# Dynamic resolution: trade render scale for a steady frame rate.
var _dynres := true
var _dr_frames := 0
var _dr_time := 0.0
var _dr_good := 0
var _dr_block := 0.0
var _dr_scale := 1.0

var _autodrive := false
var _autowalk := false
var _autocombat := false
var _auto_t := 0.0
var _bench := false
var _bench_t := 0.0
var _bench_samples: Array[float] = []
var _bench_points := [
	Vector3(84, 0.2, 6), Vector3(84, 0.2, -120), Vector3(40, 0.2, -75), Vector3(-10, 0.2, -75),
	Vector3(-85, 0.2, -75), Vector3(-85, 0.2, 0), Vector3(-10, 0.2, 0), Vector3(-10, 0.2, 75),
	Vector3(-120, 0.2, 75), Vector3(-160, 0.2, 150), Vector3(30, 0.2, 150), Vector3(110, 0.2, 60),
]


func _init() -> void:
	inst = self


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_bench = "--bench" in args
	_autowalk = "--autowalk" in args
	_autodrive = "--autodrive" in args
	_autocombat = "--autocombat" in args
	_dynres = not ("--fixedres" in args or (_bench and not "--dyn" in args))
	if (_bench and not "--dyn" in args) or "--uncapped" in args:
		Engine.max_fps = 0   # measure real throughput; normal play is capped at 60
	for a in args:
		if a.begins_with("--lod="):
			get_viewport().mesh_lod_threshold = float(a.trim_prefix("--lod="))
		if a.begins_with("--scale="):
			get_viewport().scaling_3d_scale = float(a.trim_prefix("--scale="))
			_dynres = false
	for a in args:
		if a.begins_with("--tick="):
			Engine.physics_ticks_per_second = int(a.trim_prefix("--tick="))
	if "--bench" in args:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_ensure_input()
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	_make_loading_ui()
	for id in MODELS:
		ResourceLoader.load_threaded_request(MODELS[id], "PackedScene", true)


func _ensure_input() -> void:
	## Mouse and number-key actions for step 3 (keyboard movement keys live in project.godot).
	var keys := {"reload": KEY_R, "weapon_1": KEY_1, "weapon_2": KEY_2, "weapon_3": KEY_3}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = keys[action]
			InputMap.action_add_event(action, ev)
	var buttons := {"fire": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT,
		"weapon_prev": MOUSE_BUTTON_WHEEL_UP, "weapon_next": MOUSE_BUTTON_WHEEL_DOWN}
	for action in buttons:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventMouseButton.new()
			ev.button_index = buttons[action]
			InputMap.action_add_event(action, ev)


func _make_loading_ui() -> void:
	_load_ui = CanvasLayer.new()
	_load_ui.layer = 20
	add_child(_load_ui)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.09, 0.03, 0.16)
	_load_ui.add_child(bg)
	var title := Label.new()
	title.text = GAME_TITLE.to_upper()
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.position = Vector2(-700, -200)
	title.size = Vector2(1400, 120)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.75))
	title.add_theme_color_override("font_outline_color", Color(0.2, 0.9, 1.0))
	title.add_theme_constant_override("outline_size", 6)
	_load_ui.add_child(title)
	_load_label = Label.new()
	_load_label.text = "Загрузка: " + CITY_NAME
	_load_label.set_anchors_preset(Control.PRESET_CENTER)
	_load_label.position = Vector2(-400, -40)
	_load_label.size = Vector2(800, 50)
	_load_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_load_label.add_theme_font_size_override("font_size", 32)
	_load_ui.add_child(_load_label)
	_load_bar = ProgressBar.new()
	_load_bar.set_anchors_preset(Control.PRESET_CENTER)
	_load_bar.position = Vector2(-400, 30)
	_load_bar.size = Vector2(800, 30)
	_load_bar.max_value = 1.0
	_load_ui.add_child(_load_bar)


func _process(delta: float) -> void:
	if _loading:
		_update_loading()
		return
	if _dynres:
		_update_dynres(delta)
	_update_play_state(delta)
	_update_prompt()
	if _bench:
		_update_bench(delta)
	elif _autowalk:
		_update_autowalk(delta)
	elif _autodrive:
		_update_autodrive(delta)
	elif _autocombat:
		_update_autocombat(delta)
	elif "--statetest" in OS.get_cmdline_user_args():
		_auto_t += delta
		if int(_auto_t) != int(_auto_t - delta):
			var nearest := 999.0
			for c in npcs.cops:
				if c.alive:
					nearest = minf(nearest, c.global_position.distance_to(hero.global_position))
			print("t=%d state=%d wanted=%d hp=%.0f cops=%d nearest_cop=%.1f police=%d hero=%s" % [int(_auto_t), play_state,
				wanted.level, hero.health, npcs.cops.size(), nearest, traffic_ai.police.size(), hero.global_position])
			for c in npcs.cops:
				print("    cop state=%d pos=%s path=%d/%d" % [c.state, c.global_position, c._path_i, c._path.size()])
		if _auto_t > Game.dev_int("--secs=", 60):
			get_tree().quit()
	elif "--battest" in OS.get_cmdline_user_args():
		_auto_t += delta
		if _auto_t > 3.0 and _auto_t - delta <= 3.0:
			hero.give_weapon("bat")
			var ped := npcs.spawn_ped("tourist", hero.global_position - hero.global_transform.basis.z * 1.2)
			set_meta("bat_ped", ped)
		var p2: Human = get_meta("bat_ped") if has_meta("bat_ped") else null
		if p2 and p2.alive and p2.state != Human.State.KNOCKED:
			p2.global_position = hero.global_position - hero.global_transform.basis.z * 1.2
			p2.velocity = Vector3.ZERO
		var swing := _auto_t > 3.5 and fmod(_auto_t, 0.7) < delta * 1.5
		Input.action_press("fire") if swing else Input.action_release("fire")
		if p2 and int(_auto_t * 2) != int((_auto_t - delta) * 2):
			print("t=%.1f ped hp=%.0f state=%d alive=%s wanted=%d" % [_auto_t, p2.health, p2.state, p2.alive, wanted.level])
		if _auto_t > 8.0:
			get_tree().quit()
	elif "--jacktest" in OS.get_cmdline_user_args():
		_auto_t += delta
		if _auto_t > 4.0 and _auto_t - delta <= 4.0:
			var best: Vehicle = null
			for v in traffic_ai.civil:
				if best == null or v.global_position.distance_to(hero.global_position) < best.global_position.distance_to(hero.global_position):
					best = v
			hero.global_position = best.driver_door()
			var n_before := npcs.peds.size()
			_enter_vehicle(best)
			var ped: Human = npcs.peds[-1]
			set_meta("jack_ped", ped)
			print("JACK %s ai=%s peds %d->%d driver_state=%d wanted=%d" % [best.model_id, best.ai, n_before, npcs.peds.size(), ped.state, wanted.level])
		if _auto_t > 7.0 and _auto_t - delta <= 7.0:
			var ped: Human = get_meta("jack_ped")
			print("after 3s driver state=%d pos=%s alive=%s" % [ped.state, ped.global_position, ped.alive])
			get_tree().quit()
	elif "--observe" in OS.get_cmdline_user_args():
		_auto_t += delta
		if int(_auto_t / 2.0) != int((_auto_t - delta) / 2.0):
			var line := "t=%d " % int(_auto_t)
			var cam := rig.camera
			var vis := 0
			for h in npcs.peds:
				var to := h.global_position - cam.global_position
				if to.length() < 60 and to.normalized().dot(-cam.global_transform.basis.z) > 0.5:
					vis += 1
			line += "peds=%d in_view=%d states=%s " % [npcs.peds.size(), vis, npcs.peds.map(func(h): return h.state)]
			print(line)
			line = ""
			if true:
				pass
			for v in []:
				var sig := traffic.get_signal(0 if absf(v.global_transform.basis.z.z) > 0.5 else 1)
				line += "[%s %.0f,%.0f v=%.1f sig=%d] " % [v.model_id, v.global_position.x, v.global_position.z, v.speed, sig]
			print(line)
		if _auto_t > 40.0:
			get_tree().quit()


func _update_loading() -> void:
	if _build_frames > 0:
		# Give the "building" label one frame on screen before the heavy work.
		_build_frames += 1
		if _build_frames == 3:
			_build_world()
		return
	var total := 0.0
	var done := true
	for id in MODELS:
		var progress := []
		var status := ResourceLoader.load_threaded_get_status(MODELS[id], progress)
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				total += 1.0
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				total += progress[0]
				done = false
			_:
				push_error("Failed to load " + MODELS[id])
				done = false
	_load_bar.value = total / MODELS.size() * 0.9
	if done:
		for id in MODELS:
			scenes[id] = ResourceLoader.load_threaded_get(MODELS[id])
		_load_label.text = "Строим город…"
		_load_bar.value = 0.95
		_build_frames = 1


func _build_world() -> void:
	var t0 := Time.get_ticks_msec()
	_setup_environment()
	fx = Fx.new()
	add_child(fx)
	traffic = TrafficLights.new()
	traffic.name = "TrafficLights"
	add_child(traffic)
	var city := Node3D.new()
	city.name = "City"
	add_child(city)
	var builder := CityBuilder.new(scenes, traffic)
	builder.build(city)
	vehicles = builder.vehicles
	solid_rects = builder.solid_rects
	var walk_areas: Array[Rect2] = builder.blocks.duplicate()
	walk_areas.append(Rect2(CityBuilder.PROMENADE_X0, -196.0, CityBuilder.PROMENADE_X1 - CityBuilder.PROMENADE_X0, 392.0))
	nav = NavGrid.new(solid_rects, walk_areas, CityBuilder.NS_ROADS, CityBuilder.EW_ROADS,
		Rect2(CityBuilder.PROMENADE_X0, -200, 16, 400))
	nav.blocks = builder.blocks.duplicate()
	nav.walk_areas = walk_areas

	wanted = WantedSystem.new()
	wanted.name = "Wanted"
	add_child(wanted)

	hero = Hero.new()
	hero.name = "Hero"
	hero.game = self
	add_child(hero)
	var spawn := SPAWN
	var yaw := deg_to_rad(SPAWN_YAW)
	var pitch := deg_to_rad(-12)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--spawn="):
			var p := a.trim_prefix("--spawn=").split(",")
			spawn = Vector3(float(p[0]), 1.0, float(p[1]))
			if p.size() > 2: yaw = deg_to_rad(float(p[2]))
			if p.size() > 3: pitch = deg_to_rad(float(p[3]))
	hero.global_position = spawn
	hero.rotation.y = yaw
	rig = CameraRig.new()
	rig.name = "CameraRig"
	rig.target = hero
	rig.pitch = pitch
	rig.yaw = yaw
	add_child(rig)

	npcs = NpcManager.new(self)
	add_child(npcs)
	traffic_ai = TrafficManager.new(self)
	add_child(traffic_ai)
	pickups = Pickups.new(self)
	add_child(pickups)
	var ids := ["bat", "pistol", "shotgun"]
	for set_pos in PICKUP_SETS:
		for i in 3:
			pickups.add(ids[i], set_pos[i])

	hud = Hud.new()
	add_child(hud)
	hud.set_game(self)
	_load_ui.queue_free()
	_loading = false
	pause_menu.enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.show_banner(CITY_NAME)
	var args := OS.get_cmdline_user_args()
	if "--pause" in args:
		pause_menu.set_paused(true)
	if "--fps" in args:
		hud.toggle_fps()
	if "--give" in args:
		for id in ids:
			hero.give_weapon(id)
	for a in args:
		if a.begins_with("--wanted="):
			var lvl := int(a.trim_prefix("--wanted="))
			wanted.heat = WantedSystem.THRESHOLDS[lvl]
			wanted._update_level()
	print("World built in %d ms, parked vehicles: %d" % [Time.get_ticks_msec() - t0, vehicles.size()])


func _setup_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.18, 0.42, 0.78)
	sky_mat.sky_horizon_color = Color(0.93, 0.72, 0.72)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color(0.93, 0.72, 0.72)
	sky_mat.ground_bottom_color = Color(0.3, 0.35, 0.45)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.85, 0.75, 0.8)
	env.fog_density = 0.0016
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	# 4096 atlas + soft filter (project settings) over a 40 m range: smooth palm shadows
	# instead of blocky, grainy ones.
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 40.0
	sun.directional_shadow_split_1 = 0.3
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	if "--noshadow" in OS.get_cmdline_user_args():
		sun.shadow_enabled = false


# ---------------------------------------------------------------- dynamic resolution

func _update_dynres(delta: float) -> void:
	## Keeps the frame rate at the 60 FPS cap by lowering the 3D render scale (FSR upscaling)
	## in heavy views and raising it again when there is headroom. Changes are rare and in
	## small steps because each one reallocates the render buffers.
	_dr_frames += 1
	_dr_time += delta
	_dr_block -= delta
	if _dr_time < 1.0:
		return
	var fps := _dr_frames / _dr_time
	_dr_frames = 0
	_dr_time = 0.0
	var vp := get_viewport()
	var new_scale := _dr_scale
	if fps < 54.0:
		new_scale = maxf(float(Game.dev_int("--drmin=", 60)) / 100.0, _dr_scale - (0.1 if fps < 45.0 else 0.06))
		_dr_good = 0
		_dr_block = 6.0
	elif fps > 58.5:
		_dr_good += 1
		if _dr_good >= 4 and _dr_block <= 0.0 and _dr_scale < 1.0:
			new_scale = minf(1.0, _dr_scale + 0.05)
			_dr_good = 0
	else:
		_dr_good = 0
	if not is_equal_approx(new_scale, _dr_scale):
		_dr_scale = new_scale
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if _dr_scale >= 0.999 else Viewport.SCALING_3D_MODE_FSR
		vp.scaling_3d_scale = _dr_scale


# ---------------------------------------------------------------- player helpers

func player_position() -> Vector3:
	return driving.global_position if driving else hero.global_position


func player_alive() -> bool:
	return play_state == PlayState.PLAYING and not hero.dead


func damage_player(amount: float, _cause: String) -> void:
	if not player_alive():
		return
	hero.take_damage(amount)
	rig.add_shake(clampf(amount / 20.0, 0.15, 0.6))
	if hero.dead:
		_wasted()


func on_player_gunshot(hit_people: bool) -> void:
	var pos := hero.global_position
	npcs.alert(pos, 35.0)
	if hit_people or npcs.witnesses(pos, 30.0) > 0:
		wanted.report("shots", pos)


func explosion(center: Vector3, radius: float, source: Vehicle) -> void:
	npcs.alert(center, 40.0)
	rig.add_shake(clampf(1.0 - rig.global_position.distance_to(center) / 60.0, 0.0, 1.0))
	for h in npcs.all_alive():
		var d: float = h.global_position.distance_to(center)
		if d < radius:
			h.take_damage(200.0 * (1.0 - d / radius), (h.global_position - center).normalized(), source)
	for v in vehicles:
		if v != source and is_instance_valid(v) and not v.wrecked:
			var d: float = v.global_position.distance_to(center)
			if d < radius:
				v.take_damage(70.0 * (1.0 - d / radius), Vector3.ZERO)
				v.apply_central_impulse((v.global_position - center).normalized() * v.mass * 3.0)
	if driving and driving == source:
		damage_player(200.0, "explosion")
	elif driving == null:
		var d: float = hero.global_position.distance_to(center)
		if d < radius * 1.3:
			damage_player(120.0 * (1.0 - d / (radius * 1.3)), "explosion")


func _wasted() -> void:
	if play_state != PlayState.PLAYING:
		return
	play_state = PlayState.WASTED
	_state_t = 4.5
	if driving:
		_exit_vehicle(true)
		hero.take_damage(999.0)
	hud.show_overlay("ПОТРАЧЕНО", Color(0.9, 0.12, 0.1))
	Engine.time_scale = 0.6


func bust() -> void:
	if play_state != PlayState.PLAYING or wanted.level == 0:
		return
	play_state = PlayState.BUSTED
	_state_t = 4.0
	if driving:
		_exit_vehicle(true)
	hero.play_busted()
	hud.show_overlay("АРЕСТОВАН", Color(0.35, 0.55, 1.0))
	Engine.time_scale = 0.6


func _update_play_state(delta: float) -> void:
	if play_state == PlayState.PLAYING:
		_check_hero_run_over()
		return
	_state_t -= delta / maxf(Engine.time_scale, 0.01)
	if _state_t <= 0.0:
		_respawn()


func _respawn() -> void:
	Engine.time_scale = 1.0
	if driving:
		_exit_vehicle(true)
	hero.respawn(SPAWN, deg_to_rad(SPAWN_YAW))
	rig.set_target(hero)
	rig.yaw = deg_to_rad(SPAWN_YAW)
	rig.global_position = SPAWN + Vector3.UP * 1.6
	wanted.clear()
	npcs.clear_cops()
	traffic_ai.clear_police()
	hud.hide_overlay()
	play_state = PlayState.PLAYING


func _check_hero_run_over() -> void:
	## Cars don't push the character controller; resolve being hit here.
	if driving or hero.dead or not hero.input_enabled:
		return
	for v in vehicles:
		if not is_instance_valid(v) or absf(v.speed) < 3.0:
			continue
		if v.global_position.distance_squared_to(hero.global_position) > 64.0:
			continue
		if v.distance_to_point(hero.global_position) < 0.4:
			var push := hero.global_position - v.global_position
			push.y = 0
			hero.velocity = push.normalized() * absf(v.speed) * 0.5 + Vector3.UP * 2.0
			Fx.inst.blood(hero.global_position + Vector3.UP, Vector3.UP)
			damage_player(absf(v.speed) * 2.5, "car")
			hero.knock_down()
			return


# ---------------------------------------------------------------- vehicles

func _unhandled_input(event: InputEvent) -> void:
	if _loading or get_tree().paused or not player_alive():
		return
	if event.is_action_pressed("interact"):
		if driving:
			_exit_vehicle()
		elif hero.input_enabled:
			var v := _nearest_vehicle()
			if v:
				_enter_vehicle(v)
		get_viewport().set_input_as_handled()


func _nearest_vehicle() -> Vehicle:
	if not hero.is_on_floor():
		return null
	var best: Vehicle = null
	var best_d := ENTER_DISTANCE
	for v in vehicles:
		if not is_instance_valid(v) or v.wrecked:
			continue
		var d: float = v.distance_to_point(hero.global_position)
		if d < best_d and v.global_transform.basis.y.y > 0.5:
			best_d = d
			best = v
	return best


func _enter_vehicle(v: Vehicle) -> void:
	if v.ai:
		_jack(v)
	driving = v
	hero.set_driving(true)
	v.set_occupied(true)
	v.impacted.connect(_on_vehicle_impact)
	rig.set_target(v)


func _jack(v: Vehicle) -> void:
	## Drag the NPC driver out: he falls next to the door, then runs off.
	var door := v.driver_door()
	var is_police := v.model_id == "police"
	var crew := traffic_ai.crew_of(v)
	v.set_ai(null)
	v.set_siren(false)
	if is_police:
		if crew > 0:
			var cop := npcs.spawn_cop(door + Vector3.UP * 0.2)
			cop.thrown_out_of_car()
		wanted.report("attack_cop", door)
	else:
		var ped := npcs.spawn_ped(PED_MODELS[randi() % PED_MODELS.size()], door + Vector3.UP * 0.2)
		ped.thrown_out_of_car()
		if npcs.witnesses(door, 25.0) > 1:   # the driver himself doesn't count
			wanted.report("carjack", door)


func _exit_vehicle(forced := false) -> void:
	var v := driving
	var points := v.exit_points()
	var spot: Vector3 = v.global_transform * points[-1]
	for p in points:
		var gp: Vector3 = v.global_transform * p
		if _hero_fits(gp):
			spot = gp
			break
	v.set_occupied(false)
	v.impacted.disconnect(_on_vehicle_impact)
	driving = null
	hero.global_position = spot
	hero.rotation.y = v.global_rotation.y
	hero.set_driving(false)
	rig.set_target(hero)
	if forced:
		hero.input_enabled = false


func _hero_fits(pos: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.34
	shape.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), pos + Vector3(0, 0.95, 0))
	q.collision_mask = 1 | 4 | 8
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _on_vehicle_impact(strength: float) -> void:
	rig.add_shake(clampf(strength / 8.0, 0.3, 1.2))
	if strength > 6.0:
		damage_player((strength - 6.0) * 2.0, "crash")
	if driving:
		for v in traffic_ai.police:
			if is_instance_valid(v) and v != driving and v.global_position.distance_to(driving.global_position) < 7.0:
				wanted.report("ram_police", driving.global_position)
				break
		npcs.alert(driving.global_position, 20.0)


func _update_prompt() -> void:
	if driving or not player_alive():
		hud.set_prompt("")
		return
	var v := _nearest_vehicle()
	if v == null:
		hud.set_prompt("")
	elif v.ai:
		hud.set_prompt("E — угнать: " + VEHICLE_NAMES[v.model_id])
	else:
		hud.set_prompt("E — сесть: " + VEHICLE_NAMES[v.model_id])


# ---------------------------------------------------------------- dev tools

func _update_autodrive(delta: float) -> void:
	## Dev: scripted driving to test handling, stability and exit in captures.
	_auto_t += delta
	var t := _auto_t
	if t > 0.5 and t - delta <= 0.5:
		var v := _nearest_vehicle()
		print("AUTODRIVE enter ", v.model_id if v else "none")
		if v: _enter_vehicle(v)
	if "--crashtest" in OS.get_cmdline_user_args():
		# Full throttle into the hotels, back up, repeat; then finish the car off.
		var phase := fmod(t, 5.0)
		var fwd_on := t > 1.0 and phase < 3.2 and t < 16.0
		var back_on := t > 1.0 and phase >= 3.2 and t < 16.0
		Input.action_press("move_forward") if fwd_on else Input.action_release("move_forward")
		Input.action_press("move_back") if back_on else Input.action_release("move_back")
		Input.action_press("move_left") if (t > 1.0 and t < 2.0) else Input.action_release("move_left")
		if driving and int(t * 2.0) != int((t - delta) * 2.0):
			print("t=%.1f speed=%.1f car_hp=%.0f hero_hp=%.0f up=%.2f" % [t, driving.speed, driving.health, hero.health, driving.global_transform.basis.y.y])
		if t > 16.0 and t - delta <= 16.0 and driving:
			var car := driving
			_exit_vehicle()
			car.take_damage(200.0, Vector3.ZERO)
			print("car set on fire")
		if t > 26.0 and "--quit" in OS.get_cmdline_user_args():
			get_tree().quit()
		return
	if "--exittest" in OS.get_cmdline_user_args():
		if t > 1.5 and t - delta <= 1.5:
			var car := driving
			_exit_vehicle()
			print("EXIT car=%s hero=%s local=%s" % [car.global_position, hero.global_position, car.global_transform.affine_inverse() * hero.global_position])
			get_tree().quit()
		return
	var keys := {"move_forward": (t > 1.0 and t < 7.0) or (t > 12.5 and t < 16.0),
		"move_left": t > 4.0 and t < 5.2, "move_back": t > 8.0 and t < 12.0,
		"move_right": t > 13.0 and t < 15.0, "handbrake": t > 14.0 and t < 15.0}
	for k in keys:
		if keys[k]: Input.action_press(k)
		else: Input.action_release(k)
	if driving and int(t * 2.0) != int((t - delta) * 2.0):
		print("t=%.1f speed=%.1f pos=%s up_y=%.3f hp=%.0f car_hp=%.0f fps=%d" % [t, driving.speed, driving.global_position,
			driving.global_transform.basis.y.y, hero.health, driving.health, Engine.get_frames_per_second()])
	if t > 17.0 and t - delta <= 17.0 and driving:
		_exit_vehicle()
		print("AUTODRIVE exit hero at ", hero.global_position)
	if t > 18.5 and "--quit" in OS.get_cmdline_user_args():
		get_tree().quit()


func _update_autocombat(delta: float) -> void:
	## Dev: walk to the start pickups, then aim and fire at the street.
	_auto_t += delta
	var t := _auto_t
	var stage := "walk"
	if t < 4.0:
		Input.action_press("move_back")
	else:
		Input.action_release("move_back")
		stage = "shoot"
	if t > 4.5 and t < 12.0:
		Input.action_press("aim")
	else:
		Input.action_release("aim")
	var fire_now := t > 5.5 and fmod(t, 0.8) < delta * 1.5
	if fire_now: Input.action_press("fire")
	else: Input.action_release("fire")
	if t > 8.0 and t - delta <= 8.0:
		hero._select("shotgun")
	if int(t) != int(t - delta):
		print("t=%d stage=%s weapon=%s ammo=%s wanted=%d hp=%.0f peds=%d cops=%d civ=%d police=%d fps=%d" % [int(t), stage,
			hero.current, hero.ammo_text(), wanted.level, hero.health, npcs.peds.size(), npcs.cops.size(),
			traffic_ai.civil.size(), traffic_ai.police.size(), Engine.get_frames_per_second()])
	if t > 20.0 and "--quit" in OS.get_cmdline_user_args():
		get_tree().quit()


func _update_bench(delta: float) -> void:
	_bench_t += delta
	var seg_time := 4.0
	var idx := int(_bench_t / seg_time)
	if idx >= _bench_points.size() - 1:
		_bench_samples.sort()
		var sum := 0.0
		for s in _bench_samples: sum += s
		print("BENCH frames=%d avg_fps=%.1f p5_fps=%.1f min_fps=%.1f" % [_bench_samples.size(),
			_bench_samples.size() / sum, 1.0 / _bench_samples[int(_bench_samples.size() * 0.95)],
			1.0 / _bench_samples[-1]])
		get_tree().quit()
		return
	var f := fmod(_bench_t, seg_time) / seg_time
	var p: Vector3 = _bench_points[idx].lerp(_bench_points[idx + 1], f)
	hero.global_position = p
	hero.velocity = Vector3.ZERO
	rig.yaw += delta * 0.6
	if _bench_t > 1.0:
		_bench_samples.append(delta)
		if int(_bench_t) != int(_bench_t - delta):
			print("t=%d proc=%.1fms phys=%.1fms scale=%.2f fps=%d pos=%s tris=%dk draws=%d objs=%d peds=%d civ=%d" % [int(_bench_t), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, get_viewport().scaling_3d_scale, Engine.get_frames_per_second(), p,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
				npcs.peds.size(), traffic_ai.civil.size()])
			var parts := []
			for k in prof:
				parts.append("%s=%.1fms" % [k, prof[k] / 1000.0 / maxf(Engine.get_frames_per_second(), 1.0)])
			var vp := get_viewport().get_viewport_rid()
			print("   per-frame: ", " ".join(parts), " | render_cpu=%.1fms setup=%.1fms gpu=%.1fms phys_total=%.1fms" % [
				RenderingServer.viewport_get_measured_render_time_cpu(vp), RenderingServer.get_frame_setup_time_cpu(),
				RenderingServer.viewport_get_measured_render_time_gpu(vp), Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
			prof.clear()


func _update_autowalk(delta: float) -> void:
	## Dev: scripted input to check animations in --write-movie captures.
	_auto_t += delta
	var t := _auto_t
	if t > 1.0: Input.action_press("move_forward")
	if t > 4.0 and t < 9.0: Input.action_press("sprint")
	else: Input.action_release("sprint")
	if absf(t - 6.0) < 0.05 or absf(t - 10.0) < 0.05: Input.action_press("jump")
	else: Input.action_release("jump")
	if t > 7.0 and t < 8.0 and not "--straight" in OS.get_cmdline_user_args(): rig.yaw += delta * 1.2
	if t > 11.0 and t - delta <= 11.0:
		Input.action_release("move_forward")
		print("AUTOWALK end pos ", hero.global_position)
	if t > 12.5:
		get_tree().quit()
