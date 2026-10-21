class_name NpcManager
extends Node3D
## Keeps a small crowd of pedestrians alive around the player and dispatches foot cops
## according to the wanted level. Also resolves cars running into people.

const PED_MODELS := ["tourist", "woman", "thug", "bikini", "jogger", "businessman"]
const PED_COUNT := 14
const SPAWN_MIN := 22.0
const SPAWN_MAX := 75.0
const DESPAWN := 95.0
const COPS_FOR_LEVEL := [0, 2, 3, 4, 5, 6]

var game: Game
var peds: Array[Human] = []
var cops: Array[Human] = []
var _pool := {}            # model id -> Array[Human] of inactive humans
var _spawn_t := 0.0
var _cop_t := 0.0
var _initial_fill := 2


func _init(p_game: Game) -> void:
	game = p_game
	name = "NpcManager"


func all_alive() -> Array[Human]:
	var out: Array[Human] = []
	for h in peds:
		if h.alive:
			out.append(h)
	for h in cops:
		if h.alive:
			out.append(h)
	return out


func _get_human(id: String, role: int) -> Human:
	var pool: Array = _pool.get(id, [])
	if not pool.is_empty():
		var h: Human = pool.pop_back()
		h.process_mode = Node.PROCESS_MODE_INHERIT
		return h
	var human := Human.new()
	human.manager = self
	add_child(human)
	human.setup(id, game.scenes[id], role)
	return human


func _release(h: Human) -> void:
	peds.erase(h)
	cops.erase(h)
	h.visible = false
	h.process_mode = Node.PROCESS_MODE_DISABLED
	h.global_position = Vector3(0, -50, 0)
	h.collision_layer = 0
	if not _pool.has(h.model_id):
		_pool[h.model_id] = []
	_pool[h.model_id].append(h)


func spawn_ped(id: String, pos: Vector3) -> Human:
	var h := _get_human(id, Human.Role.PED)
	h.reset_at(pos, Human.State.WANDER)
	peds.append(h)
	return h


func spawn_cop(pos: Vector3) -> Human:
	var h := _get_human("cop", Human.Role.COP)
	h.reset_at(pos, Human.State.CHASE)
	cops.append(h)
	return h


func clear_cops() -> void:
	for c in cops.duplicate():
		_release(c)


func alert(pos: Vector3, radius: float) -> void:
	## Gunshots, crashes, bodies: pedestrians nearby run away.
	for h in peds:
		if h.alive and h.global_position.distance_to(pos) < radius:
			h.start_flee(pos)


func witnesses(pos: Vector3, radius: float) -> int:
	var n := 0
	for h in peds:
		if h.alive and h.global_position.distance_to(pos) < radius:
			n += 1
	for h in cops:
		if h.alive and h.global_position.distance_to(pos) < radius * 1.6:
			n += 1
	return n


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_tick(delta)
	Game.prof_add("npcmgr", Time.get_ticks_usec() - t0)


func _tick(delta: float) -> void:
	if game.hero == null:
		return
	var center := game.player_position()
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = 0.5
		_maintain_peds(center)
	_cop_t -= delta
	if _cop_t <= 0.0:
		_cop_t = 1.5
		_maintain_cops(center)
	_check_vehicle_hits()


func _out_of_view(p: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return true
	var to := p - cam.global_position
	return to.length() > 55.0 or to.normalized().dot(-cam.global_transform.basis.z) < 0.35


func _maintain_peds(center: Vector3) -> void:
	for h in peds.duplicate():
		var d: float = h.global_position.distance_to(center)
		if d > DESPAWN or (not h.alive and h.dead_time > 25.0 and _out_of_view(h.global_position)):
			_release(h)
	var alive_count := 0
	for h in peds:
		if h.alive:
			alive_count += 1
	if alive_count >= Game.dev_int("--peds=", PED_COUNT):
		return
	# Try a few random sidewalk spots around the player. Right after (re)spawning the whole
	# crowd appears at once (the loading screen hides it); later only out of sight or far away.
	var initial := _initial_fill > 0
	var budget := 8 if initial else 1
	for attempt in (40 if initial else 8):
		if budget <= 0:
			break
		var ang := randf() * TAU
		var r := randf_range(SPAWN_MIN, SPAWN_MAX)
		var p := center + Vector3(cos(ang) * r, 0, sin(ang) * r)
		var ring := NavGrid.inst.ring_for(p)
		var i := randi() % 4
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % 4]
		var pos := a.lerp(b, randf())
		pos.y = 0.3
		var d := pos.distance_to(center)
		if d < (8.0 if initial else SPAWN_MIN) or not NavGrid.inst.is_walkable(pos):
			continue
		if not initial and not _out_of_view(pos) and d < 42.0:
			continue
		spawn_ped(PED_MODELS[randi() % PED_MODELS.size()], pos)
		budget -= 1
		alive_count += 1
		if alive_count >= Game.dev_int("--peds=", PED_COUNT):
			break
	_initial_fill -= 1


func _maintain_cops(center: Vector3) -> void:
	for c in cops.duplicate():
		var d: float = c.global_position.distance_to(center)
		if (not c.alive and c.dead_time > 25.0 and _out_of_view(c.global_position)) or \
				(c.state == Human.State.LEAVE and _out_of_view(c.global_position)) or d > 140.0:
			_release(c)
	var want: int = COPS_FOR_LEVEL[game.wanted.level]
	var active := 0
	for c in cops:
		if c.alive and c.state != Human.State.LEAVE:
			active += 1
	if active >= want or not game.player_alive():
		return
	for attempt in 8:
		var ang := randf() * TAU
		var r := randf_range(35.0, 60.0)
		var p := center + Vector3(cos(ang) * r, 0.3, sin(ang) * r)
		if NavGrid.inst.is_walkable(p) and _out_of_view(p) and absf(p.x) < 195 and absf(p.z) < 195 and p.x < 150:
			spawn_cop(p)
			return


func _check_vehicle_hits() -> void:
	## Cars don't collide with people physically; resolve it here.
	var movers: Array[Vehicle] = []
	for v in game.vehicles:
		if is_instance_valid(v) and absf(v.speed) > 2.5:
			movers.append(v)
	if movers.is_empty():
		return
	for h in peds + cops:
		if not h.alive or h.state == Human.State.KNOCKED:
			continue
		for v in movers:
			if v.global_position.distance_squared_to(h.global_position) > 64.0:
				continue
			if v.distance_to_point(h.global_position) < 0.35:
				h.hit_by_vehicle(v)
				break
