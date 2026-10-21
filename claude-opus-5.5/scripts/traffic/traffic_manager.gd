class_name TrafficManager
extends Node3D
## Spawns AI traffic around the player and police cars according to the wanted level.

const CIVIL_MODELS := ["sedan", "taxi", "sportscar", "convertible", "pickup", "van", "supercar", "sedan", "taxi"]
const CIVIL_COUNT := 10
const SPAWN_MIN := 45.0
const SPAWN_MAX := 130.0
const DESPAWN := 190.0
const POLICE_FOR_LEVEL := [0, 0, 1, 2, 3, 4]

var game: Game
var civil: Array[Vehicle] = []
var police: Array[Vehicle] = []
var _t := 0.0
var _police_t := 0.0
var _crew := {}   # police car -> cops still inside


func _init(p_game: Game) -> void:
	game = p_game
	name = "TrafficManager"


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_tick(delta)
	Game.prof_add("trafficmgr", Time.get_ticks_usec() - t0)


func _tick(delta: float) -> void:
	if game.hero == null:
		return
	_t -= delta
	if _t <= 0.0:
		_t = 0.7
		_maintain_civil()
	_police_t -= delta
	if _police_t <= 0.0:
		_police_t = 1.0
		_maintain_police()
	_deploy_cops()


func _out_of_view(p: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return true
	var to := p - cam.global_position
	return to.length() > 90.0 or to.normalized().dot(-cam.global_transform.basis.z) < 0.3


func _spawn_point() -> Array:
	## Random lane position on a road segment out of sight. Returns [pos, node_a, node_b] or [].
	var nav := NavGrid.inst
	var center := game.player_position()
	for attempt in 10:
		var a := Vector2i(randi() % nav.road_xs.size(), randi() % nav.road_zs.size())
		var nb := nav.neighbours(a)
		var b: Vector2i = nb[randi() % nb.size()]
		var pa := nav.node_pos(a)
		var pb := nav.node_pos(b)
		var seg := pa.distance_to(pb)
		var pos := NavGrid.lane_point(pa, pb, randf_range(16.0, seg - 22.0))
		var d: float = pos.distance_to(center)
		if d < SPAWN_MIN or d > SPAWN_MAX or not _out_of_view(pos):
			continue
		var free := true
		for v in game.vehicles:
			if is_instance_valid(v) and v.global_position.distance_to(pos) < 9.0:
				free = false
				break
		if free:
			return [pos, a, b]
	return []


func _spawn_car(id: String, mode: int) -> Vehicle:
	var sp := _spawn_point()
	if sp.is_empty():
		return null
	var v := Vehicle.new()
	v.setup(id, game.scenes[id])
	v.spawned_by_traffic = true
	var pa := NavGrid.inst.node_pos(sp[1])
	var pb := NavGrid.inst.node_pos(sp[2])
	var dir := (pb - pa).normalized()
	v.position = sp[0] + Vector3.UP * 0.05
	v.rotation.y = CityBuilder.yaw_facing(dir)
	add_child(v)
	v.linear_velocity = dir * (8.0 if mode == AIDriver.Mode.CRUISE else 12.0)
	var driver := AIDriver.new(v, game, mode)
	driver.place_on_segment(sp[1], sp[2])
	v.set_ai(driver)
	game.vehicles.append(v)
	return v


func _remove(v: Vehicle) -> void:
	civil.erase(v)
	police.erase(v)
	_crew.erase(v)
	game.vehicles.erase(v)
	v.queue_free()


func _maintain_civil() -> void:
	var center := game.player_position()
	for v in civil.duplicate():
		if not is_instance_valid(v):
			civil.erase(v)
			continue
		if v.occupied:
			civil.erase(v)   # the player took it; it's his now
			continue
		var d: float = v.global_position.distance_to(center)
		if d > DESPAWN or (v.wrecked and d > 60.0 and _out_of_view(v.global_position)):
			_remove(v)
	if civil.size() < Game.dev_int("--civ=", CIVIL_COUNT):
		var v := _spawn_car(CIVIL_MODELS[randi() % CIVIL_MODELS.size()], AIDriver.Mode.CRUISE)
		if v:
			civil.append(v)


func _maintain_police() -> void:
	var center := game.player_position()
	var level: int = game.wanted.level
	for v in police.duplicate():
		if not is_instance_valid(v):
			police.erase(v)
			continue
		if v.occupied:
			police.erase(v)
			continue
		var d: float = v.global_position.distance_to(center)
		if d > DESPAWN + 40.0 or (level == 0 and _out_of_view(v.global_position)):
			_remove(v)
		elif level == 0 and v.ai:
			v.set_siren(false)
			v.ai.mode = AIDriver.Mode.PARKED
		elif v.ai and v.ai.mode == AIDriver.Mode.PARKED and game.driving != null:
			v.ai.mode = AIDriver.Mode.PURSUIT   # player drove off: back to the chase
	var active := 0
	for v in police:
		if v.ai and v.ai.mode == AIDriver.Mode.PURSUIT:
			active += 1
	if active < POLICE_FOR_LEVEL[level] and game.player_alive():
		var v := _spawn_car("police", AIDriver.Mode.PURSUIT)
		if v:
			v.set_siren(true)
			police.append(v)
			_crew[v] = 2


func clear_police() -> void:
	for v in police.duplicate():
		if is_instance_valid(v) and not v.occupied:
			_remove(v)
	police.clear()


func _deploy_cops() -> void:
	## A police car that has stopped next to a player on foot lets its officers out.
	if game.driving != null:
		return
	var hero_pos := game.player_position()
	for v in police:
		if not is_instance_valid(v) or v.ai == null or _crew.get(v, 0) <= 0:
			continue
		if absf(v.speed) < 1.0 and v.global_position.distance_to(hero_pos) < 16.0:
			var n: int = _crew[v]
			_crew[v] = 0
			var pts := v.exit_points()
			for i in n:
				var p: Vector3 = v.global_transform * pts[i]
				game.npcs.spawn_cop(p + Vector3.UP * 0.2)
			v.ai.mode = AIDriver.Mode.PARKED


func crew_of(v: Vehicle) -> int:
	return _crew.get(v, 0)
