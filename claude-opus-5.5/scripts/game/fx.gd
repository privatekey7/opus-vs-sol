class_name Fx
extends Node3D
## One-shot visual and sound effects: sparks, blood, dust, smoke, fire, explosions,
## muzzle flashes, bullet holes and synthesised sounds. Everything is pooled or auto-freed.

static var inst: Fx

const MAX_HOLES := 40

var _mat_spark: ShaderMaterial
var _mat_blood: ShaderMaterial
var _mat_dust: ShaderMaterial
var _mat_smoke: ShaderMaterial
var _mat_black: ShaderMaterial
var _mat_fire: ShaderMaterial
var _mat_hole: StandardMaterial3D
var _mat_tracer: StandardMaterial3D
var _mat_flash: ShaderMaterial
var _quad: QuadMesh
var _hole_mesh: QuadMesh
var _holes: Array[MeshInstance3D] = []
var _sounds := {}


func _init() -> void:
	inst = self
	name = "Fx"


func _ready() -> void:
	_mat_spark = _particle_mat(Color(1.0, 0.8, 0.3), 0.3, 2.5)
	_mat_blood = _particle_mat(Color(0.5, 0.02, 0.02, 0.95), 0.35, 1.0)
	_mat_dust = _particle_mat(Color(0.65, 0.6, 0.55, 0.6), 0.8, 1.0)
	_mat_smoke = _particle_mat(Color(0.4, 0.4, 0.42, 0.45), 0.9, 1.0)
	_mat_black = _particle_mat(Color(0.06, 0.06, 0.06, 0.65), 0.9, 1.0)
	_mat_fire = _particle_mat(Color(1.0, 0.45, 0.1, 0.9), 0.8, 2.2)
	_mat_flash = _particle_mat(Color(1.0, 0.85, 0.5), 0.7, 3.0)
	_mat_hole = StandardMaterial3D.new()
	_mat_hole.albedo_color = Color(0.05, 0.05, 0.05)
	_mat_hole.roughness = 1.0
	_mat_tracer = StandardMaterial3D.new()
	_mat_tracer.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_tracer.albedo_color = Color(1.0, 0.9, 0.5)
	_quad = QuadMesh.new()
	_quad.size = Vector2(0.12, 0.12)
	_hole_mesh = QuadMesh.new()
	_hole_mesh.size = Vector2(0.09, 0.09)
	_sounds["pistol"] = _make_shot(0.22, 1800.0, 0.55, 3)
	_sounds["shotgun"] = _make_shot(0.4, 900.0, 0.8, 5)
	_sounds["bat"] = _make_thud()
	_sounds["explosion"] = _make_shot(1.6, 300.0, 1.0, 9)
	_sounds["click"] = _make_click()


func _particle_mat(c: Color, softness: float, brightness: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/particle.gdshader")
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("softness", softness)
	m.set_shader_parameter("brightness", brightness)
	return m


## ---------------------------------------------------------------- particles

func _burst(pos: Vector3, normal: Vector3, mat: Material, amount: int, speed: float, life: float,
		size: float, gravity: float, spread := 60.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -gravity, 0)
	pm.scale_min = size * 0.6
	pm.scale_max = size
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	var curve := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(1, 0.2))
	curve.curve = c
	pm.scale_curve = curve
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.1, 0.1)
	q.material = mat
	p.draw_pass_1 = q
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.local_coords = false
	add_child(p)
	p.global_position = pos
	if normal.length() > 0.01:
		var n := normal.normalized()
		var up := Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT
		p.global_transform.basis = Basis.looking_at(n, up)
	p.emitting = true
	get_tree().create_timer(life + 0.5, false).timeout.connect(p.queue_free)
	return p


func sparks(pos: Vector3, normal: Vector3, amount := 16) -> void:
	_burst(pos, normal, _mat_spark, amount, 7.0, 0.45, 0.35, 9.8, 50.0)


func blood(pos: Vector3, normal: Vector3) -> void:
	_burst(pos, normal, _mat_blood, 18, 3.0, 0.6, 0.9, 9.8, 35.0)


func dust(pos: Vector3, normal: Vector3) -> void:
	_burst(pos, normal, _mat_dust, 10, 2.0, 0.8, 1.6, 1.0, 40.0)
	sparks(pos, normal, 5)


func explosion(pos: Vector3) -> void:
	_burst(pos, Vector3.UP, _mat_fire, 50, 9.0, 0.9, 22.0, -2.0, 180.0)
	_burst(pos, Vector3.UP, _mat_black, 30, 4.0, 2.5, 30.0, -1.5, 120.0)
	_burst(pos, Vector3.UP, _mat_spark, 40, 16.0, 1.2, 0.5, 9.8, 180.0)
	flash(pos, Color(1.0, 0.6, 0.25), 25.0, 0.5, 12.0)
	play_sound("explosion", pos, 6.0)


func flash(pos: Vector3, color: Color, rng: float, time: float, energy := 6.0) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.omni_range = rng
	l.light_energy = energy
	l.shadow_enabled = false
	add_child(l)
	l.global_position = pos
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, time)
	tw.tween_callback(l.queue_free)


func muzzle_flash(pos: Vector3, dir: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	q.material = _mat_flash
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos + dir * 0.08
	mi.scale = Vector3.ONE * randf_range(0.8, 1.3)
	get_tree().create_timer(0.05, false).timeout.connect(mi.queue_free)
	flash(pos, Color(1.0, 0.8, 0.45), 6.0, 0.08, 4.0)


func bullet_hole(pos: Vector3, normal: Vector3) -> void:
	var mi: MeshInstance3D
	if _holes.size() >= MAX_HOLES:
		mi = _holes.pop_front()
	else:
		mi = MeshInstance3D.new()
		mi.mesh = _hole_mesh
		mi.material_override = _mat_hole
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 40.0
		add_child(mi)
	_holes.append(mi)
	var n := normal.normalized()
	var up := Vector3.UP if absf(n.y) < 0.95 else Vector3.FORWARD
	mi.global_transform = Transform3D(Basis.looking_at(-n, up), pos + n * 0.01)


func tracer(from: Vector3, to: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var len := from.distance_to(to)
	if len < 0.5:
		return
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, minf(len, 6.0))
	bm.material = _mat_tracer
	mi.mesh = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var dir := (to - from).normalized()
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	mi.global_transform = Transform3D(Basis.looking_at(dir, up), from + dir * minf(len, 6.0) * 0.5)
	var tw := create_tween()
	tw.tween_property(mi, "global_position", to - dir * minf(len, 6.0) * 0.5, minf(len / 300.0, 0.1))
	tw.tween_callback(mi.queue_free)


## Continuous emitter attached to a node (vehicle smoke and fire). kind: "smoke", "black", "fire".
func make_emitter(kind: String) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.5
	pm.gravity = Vector3(0, 0.6, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	var curve := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(1, 1.0))
	curve.curve = c
	pm.scale_curve = curve
	var q := QuadMesh.new()
	q.size = Vector2(0.1, 0.1)
	match kind:
		"fire":
			q.material = _mat_fire
			pm.scale_min = 6.0
			pm.scale_max = 9.0
			p.lifetime = 0.6
			p.amount = 24
		"black":
			q.material = _mat_black
			pm.scale_min = 8.0
			pm.scale_max = 14.0
			p.lifetime = 2.2
			p.amount = 24
		_:
			q.material = _mat_smoke
			pm.scale_min = 6.0
			pm.scale_max = 10.0
			p.lifetime = 1.8
			p.amount = 16
	p.process_material = pm
	p.draw_pass_1 = q
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 10, 8))
	return p


## ---------------------------------------------------------------- sounds

func play_sound(id: String, pos: Vector3, volume := 1.0, pitch := 1.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = _sounds[id]
	p.unit_size = 15.0
	p.max_distance = 250.0
	p.volume_db = linear_to_db(clampf(volume, 0.01, 4.0))
	p.pitch_scale = pitch * randf_range(0.93, 1.07)
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


static func _wav(samples: PackedFloat32Array, rate: int, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w


static func _make_shot(length: float, cutoff_hz: float, body: float, seed_v: int) -> AudioStreamWAV:
	## Gunshot / blast: sharp noise transient, low-passed tail and a low boom.
	var rate := 22050
	var n := int(rate * length)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var lp := 0.0
	var lp2 := 0.0
	var a := clampf(cutoff_hz / rate * TAU, 0.01, 1.0)
	for i in n:
		var t := float(i) / rate
		var noise := rng.randf() * 2.0 - 1.0
		lp += (noise - lp) * a
		lp2 += (lp - lp2) * a
		var crack := noise * exp(-t * 90.0)
		var tail := lp2 * 3.0 * exp(-t * (6.0 / length))
		var boom := sin(TAU * (70.0 - 30.0 * t / length) * t) * exp(-t * (4.0 / length)) * body
		s[i] = (crack * 0.8 + tail + boom * 0.7) * 0.8
	return _wav(s, rate)


static func _make_thud() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.25)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	for i in n:
		var t := float(i) / rate
		s[i] = (sin(TAU * 110.0 * t) * 0.9 + (rng.randf() - 0.5) * 0.6) * exp(-t * 25.0)
	return _wav(s, rate)


static func _make_click() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.08)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / rate
		s[i] = sin(TAU * 2400.0 * t) * exp(-t * 120.0) * 0.6 + sin(TAU * 900.0 * t) * exp(-t * 60.0) * 0.4
	return _wav(s, rate)


static func make_siren() -> AudioStreamWAV:
	## Two-tone police wail, looped.
	var rate := 22050
	var n := rate * 2
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / rate
		var f := 650.0 + 450.0 * (0.5 - 0.5 * cos(TAU * t / 2.0))
		phase += f / rate
		var v := sin(TAU * phase) * 0.6 + sin(TAU * phase * 2.0) * 0.2 + sin(TAU * phase * 3.0) * 0.1
		s[i] = v * 0.7
	return _wav(s, rate, true)


static func make_engine_loop() -> AudioStreamWAV:
	## Engine hum at ~1800 rpm for AI cars; played with pitch_scale following their speed.
	var rate := 22050
	var n := int(rate * 0.5)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var lp := 0.0
	var f := 60.0   # firing frequency; 0.5 s holds exactly 30 cycles so the loop is seamless
	for i in n:
		var t := float(i) / rate
		var p := TAU * f * t
		var v := sin(p) * 0.5 + sin(p * 2.0 + 0.7) * 0.25 + sin(p * 0.5) * 0.3 + (rng.randf() - 0.5) * 0.1
		lp += (v - lp) * 0.2
		s[i] = lp * 0.8
	return _wav(s, rate, true)
