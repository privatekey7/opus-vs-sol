class_name Hud
extends CanvasLayer
## On-screen overlay: wanted stars, health, weapon and ammo, speed, minimap, crosshair,
## messages, FPS counter (F3) and the WASTED / BUSTED screens.

var game: Game
var _fps_label: Label
var _banner: Label
var _banner_time := 0.0
var _prompt: Label
var _stars: Control
var _weapon_label: Label
var _ammo_label: Label
var _health_bar: ProgressBar
var _speed_label: Label
var _crosshair: Control
var _message: Label
var _message_t := 0.0
var _overlay: ColorRect
var _overlay_label: Label
var _minimap: Minimap
var _star_blink := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5
	_fps_label = _label(Vector2(16, 12), 22, Color(0.6, 1.0, 0.6))
	_fps_label.visible = false

	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_banner.position = Vector2(-400, -180)
	_banner.size = Vector2(800, 80)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 52)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.45, 0.75))
	_banner.add_theme_color_override("font_outline_color", Color(0.1, 0.0, 0.2))
	_banner.add_theme_constant_override("outline_size", 12)
	_banner.modulate.a = 0.0
	add_child(_banner)

	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-400, -90)
	_prompt.size = Vector2(800, 40)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 28)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 8)
	_prompt.visible = false
	add_child(_prompt)

	# Wanted stars (top right)
	_stars = Control.new()
	_stars.position = Vector2(1920 - 330, 24)
	_stars.size = Vector2(310, 60)
	_stars.draw.connect(_draw_stars)
	add_child(_stars)
	# Weapon + ammo
	_weapon_label = _label(Vector2(1920 - 330, 90), 30, Color(1, 1, 1))
	_weapon_label.size = Vector2(310, 40)
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_label = _label(Vector2(1920 - 330, 128), 30, Color(1.0, 0.85, 0.4))
	_ammo_label.size = Vector2(310, 40)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Minimap + health (bottom left)
	_minimap = Minimap.new()
	_minimap.position = Vector2(30, 1080 - 30 - 260 - 30)
	add_child(_minimap)
	_health_bar = ProgressBar.new()
	_health_bar.position = Vector2(30, 1080 - 30 - 22)
	_health_bar.size = Vector2(260, 22)
	_health_bar.max_value = Hero.MAX_HEALTH
	_health_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.25, 0.85, 0.35)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.15, 0.05, 0.8)
	bg.border_color = Color.BLACK
	bg.set_border_width_all(2)
	_health_bar.add_theme_stylebox_override("fill", fill)
	_health_bar.add_theme_stylebox_override("background", bg)
	add_child(_health_bar)
	# Speed (bottom right)
	_speed_label = _label(Vector2(1920 - 330, 1080 - 90), 44, Color(1, 1, 1))
	_speed_label.size = Vector2(300, 60)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Crosshair
	_crosshair = Control.new()
	_crosshair.position = Vector2(960 - 20, 540 - 20)
	_crosshair.size = Vector2(40, 40)
	_crosshair.draw.connect(_draw_crosshair)
	_crosshair.visible = false
	add_child(_crosshair)
	# Pickup / info messages
	_message = _label(Vector2(560, 200), 36, Color(1.0, 0.9, 0.5))
	_message.size = Vector2(800, 50)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.modulate.a = 0.0
	# Death / arrest screen
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_overlay_label = Label.new()
	_overlay_label.set_anchors_preset(Control.PRESET_CENTER)
	_overlay_label.position = Vector2(-700, -80)
	_overlay_label.size = Vector2(1400, 160)
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.add_theme_font_size_override("font_size", 130)
	_overlay_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_overlay_label.add_theme_constant_override("outline_size", 18)
	_overlay_label.modulate.a = 0.0
	_overlay.add_child(_overlay_label)


func _label(pos: Vector2, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	add_child(l)
	return l


func set_game(g: Game) -> void:
	game = g
	_minimap.game = g


func set_prompt(text: String) -> void:
	if _prompt.text != text:
		_prompt.text = text
	_prompt.visible = text != ""


func show_banner(text: String) -> void:
	_banner.text = text
	_banner_time = 4.0


func show_message(text: String) -> void:
	_message.text = text
	_message_t = 2.5


func show_overlay(text: String, color: Color) -> void:
	_overlay_label.text = text
	_overlay_label.add_theme_color_override("font_color", color)
	var tw := create_tween()
	tw.tween_property(_overlay, "color", Color(0, 0, 0, 0.55), 1.0)
	tw.parallel().tween_property(_overlay_label, "modulate:a", 1.0, 0.8)


func hide_overlay() -> void:
	var tw := create_tween()
	tw.tween_property(_overlay, "color", Color(0, 0, 0, 0), 0.6)
	tw.parallel().tween_property(_overlay_label, "modulate:a", 0.0, 0.4)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fps"):
		toggle_fps()
		get_viewport().set_input_as_handled()


func toggle_fps() -> void:
	_fps_label.visible = not _fps_label.visible


func _process(delta: float) -> void:
	if _fps_label.visible:
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	if _banner_time > 0.0:
		_banner_time -= delta
		_banner.modulate.a = clampf(minf(_banner_time, 4.0 - _banner_time) * 2.0, 0.0, 1.0)
	if _message_t > 0.0:
		_message_t -= delta
		_message.modulate.a = clampf(_message_t * 2.0, 0.0, 1.0)
	if game == null or game.hero == null:
		return
	var hero := game.hero
	_star_blink += delta
	_stars.queue_redraw()
	_health_bar.value = hero.health
	var fill := _health_bar.get_theme_stylebox("fill") as StyleBoxFlat
	fill.bg_color = Color(0.25, 0.85, 0.35) if hero.health > 35.0 else Color(0.95, 0.25, 0.2)
	_weapon_label.text = Hero.WEAPON_NAMES[hero.current]
	if hero.reloading > 0.0:
		_ammo_label.text = "ПЕРЕЗАРЯДКА"
	else:
		_ammo_label.text = hero.ammo_text()
	if game.driving:
		_speed_label.text = "%d км/ч" % int(absf(game.driving.speed) * 3.6)
		_speed_label.visible = true
	else:
		_speed_label.visible = false
	_crosshair.visible = hero.aiming and game.driving == null
	if _crosshair.visible:
		_crosshair.queue_redraw()


func _draw_stars() -> void:
	var level: int = game.wanted.level if game else 0
	var fading: bool = game.wanted.fading if game else false
	var show_active := not fading or int(_star_blink * 3.0) % 2 == 0
	for i in 5:
		var center := Vector2(310 - 30 - i * 60, 30)
		var pts := PackedVector2Array()
		for k in 10:
			var r := 26.0 if k % 2 == 0 else 11.0
			var a := -PI / 2 + k * PI / 5
			pts.append(center + Vector2(cos(a), sin(a)) * r)
		var active := (4 - i) < level
		var col := Color(1.0, 0.85, 0.2) if active and show_active else Color(0.15, 0.15, 0.15, 0.55)
		_stars.draw_colored_polygon(pts, col)
		pts.append(pts[0])
		_stars.draw_polyline(pts, Color(0, 0, 0), 2.5)


func _draw_crosshair() -> void:
	var c := Vector2(20, 20)
	var col := Color(1, 1, 1, 0.9)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		_crosshair.draw_line(c + d * 5.0, c + d * 14.0, Color(0, 0, 0, 0.8), 4.0)
		_crosshair.draw_line(c + d * 5.0, c + d * 14.0, col, 2.0)
	_crosshair.draw_circle(c, 2.0, col)
