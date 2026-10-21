class_name Pickups
extends Node3D
## Weapon pickups: a spinning weapon above a glowing ring with a tall light beam so they can
## be spotted from far away. Walk into one to take it; it comes back after a while.

const RESPAWN := 45.0
const COLORS := {"bat": Color(1.0, 0.85, 0.2), "pistol": Color(0.2, 0.9, 1.0), "shotgun": Color(1.0, 0.4, 0.15)}
const SHOW_SCALE := {"bat": 1.4, "pistol": 3.5, "shotgun": 1.6}

var game: Game
var items: Array[Dictionary] = []   # {id, pos, node, active, timer}


func _init(p_game: Game) -> void:
	game = p_game
	name = "Pickups"


func add(id: String, pos: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var c: Color = COLORS[id]
	# Beam
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.22
	cyl.height = 30.0
	cyl.radial_segments = 12
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	beam.mesh = cyl
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.albedo_color = Color(c.r, c.g, c.b, 0.4)
	# Fades out up close so it doesn't fill the screen, stays bright from afar.
	bm.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	bm.distance_fade_min_distance = 3.0
	bm.distance_fade_max_distance = 25.0
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = 15.0
	root.add_child(beam)
	# Ring on the ground
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.55
	tor.outer_radius = 0.7
	tor.rings = 24
	tor.ring_segments = 6
	ring.mesh = tor
	var rm := StandardMaterial3D.new()
	rm.albedo_color = c
	rm.emission_enabled = true
	rm.emission = c
	rm.emission_energy_multiplier = 2.5
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = 0.05
	root.add_child(ring)
	# Weapon
	var spinner := Node3D.new()
	spinner.name = "Spinner"
	spinner.position.y = 0.9
	root.add_child(spinner)
	var w: Node3D = game.scenes[id].instantiate()
	w.scale = Vector3.ONE * SHOW_SCALE[id]
	spinner.add_child(w)
	for gi in w.find_children("*", "GeometryInstance3D", true, false):
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Centre the weapon on the spinner.
	var mi := w.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var aabb: AABB = CityBuilder.xf_to(mi, spinner) * mi.get_aabb()
	w.position -= aabb.get_center()
	spinner.rotation.x = -0.35
	items.append({"id": id, "pos": pos, "node": root, "spinner": spinner, "active": true, "timer": 0.0})


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var hero := game.hero
	for it in items:
		var node: Node3D = it.node
		if not it.active:
			it.timer -= delta
			if it.timer <= 0.0:
				it.active = true
				node.visible = true
			continue
		var sp: Node3D = it.spinner
		sp.rotation.y = t * 1.8
		sp.position.y = 0.9 + sin(t * 2.5) * 0.12
		if hero and game.driving == null and game.player_alive() and hero.global_position.distance_to(it.pos) < 1.5:
			if hero.give_weapon(it.id):
				it.active = false
				it.timer = RESPAWN
				node.visible = false
				Fx.inst.play_sound("click", it.pos, 2.0, 0.7)
				game.hud.show_message(Hero.WEAPON_NAMES[it.id])
