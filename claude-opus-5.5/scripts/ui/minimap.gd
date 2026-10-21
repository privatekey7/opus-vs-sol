class_name Minimap
extends Control
## Radar in the corner: city blocks, buildings, beach and sea, pickups, police and the
## player's arrow. Rotates with the camera so "up" is where the camera looks.

const RANGE_M := 110.0          # metres from the centre to the edge

var game: Game
var _blink := 0.0


func _ready() -> void:
	clip_contents = true
	custom_minimum_size = Vector2(260, 260)
	size = Vector2(260, 260)


func _process(delta: float) -> void:
	_blink += delta
	queue_redraw()


func _draw() -> void:
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.12, 0.3, 0.12, 0.85))
	if game == null or game.hero == null or game.nav == null:
		return
	var c := game.player_position()
	var s := sz.x * 0.5 / RANGE_M
	var yaw := game.rig.yaw
	draw_set_transform(sz * 0.5, yaw, Vector2(s, s))
	var off := Vector2(-c.x, -c.z)
	# City asphalt, promenade, beach, sea
	draw_rect(Rect2(Vector2(-200, -200) + off, Vector2(276, 400)), Color(0.22, 0.22, 0.25))
	draw_rect(Rect2(Vector2(76, -400) + off, Vector2(16, 800)), Color(0.85, 0.62, 0.62))
	draw_rect(Rect2(Vector2(92, -400) + off, Vector2(45, 800)), Color(0.86, 0.78, 0.55))
	draw_rect(Rect2(Vector2(137, -400) + off, Vector2(600, 800)), Color(0.12, 0.45, 0.7))
	for b in game.nav.blocks:
		draw_rect(Rect2(b.position + off, b.size), Color(0.55, 0.55, 0.55))
	for r in game.solid_rects:
		draw_rect(Rect2(r.position + off, r.size), Color(0.33, 0.3, 0.38))
	# Pickups
	for it in game.pickups.items:
		if it.active:
			var p: Vector3 = it.pos
			draw_circle(Vector2(p.x, p.z) + off, 3.2, Pickups.COLORS[it.id])
	# Police
	var blink := int(_blink * 4.0) % 2 == 0
	for v in game.traffic_ai.police:
		if is_instance_valid(v):
			draw_circle(Vector2(v.global_position.x, v.global_position.z) + off, 3.5, Color(1, 0.2, 0.2) if blink else Color(0.2, 0.4, 1))
	for h in game.npcs.cops:
		if h.alive:
			draw_circle(Vector2(h.global_position.x, h.global_position.z) + off, 2.2, Color(0.3, 0.5, 1.0))
	# Player arrow
	var fwd: Vector3
	if game.driving:
		fwd = -game.driving.global_transform.basis.z
	else:
		fwd = -game.hero.global_transform.basis.z
		if game.hero.aiming:
			fwd = -game.rig.camera.global_transform.basis.z
	var f := Vector2(fwd.x, fwd.z).normalized()
	var rgt := Vector2(-f.y, f.x)
	var tip := f * 7.0
	draw_colored_polygon(PackedVector2Array([tip, -f * 4.0 + rgt * 4.5, -f * 1.5, -f * 4.0 - rgt * 4.5]), Color(1, 1, 1))
	draw_polyline(PackedVector2Array([tip, -f * 4.0 + rgt * 4.5, -f * 1.5, -f * 4.0 - rgt * 4.5, tip]), Color(0, 0, 0), 0.8)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# North marker
	var north := Vector2(0, -1).rotated(yaw) * (sz.x * 0.5 - 12.0) + sz * 0.5
	draw_circle(north, 9.0, Color(0, 0, 0, 0.6))
	draw_string(ThemeDB.fallback_font, north + Vector2(-5, 6), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0), false, 3.0)
