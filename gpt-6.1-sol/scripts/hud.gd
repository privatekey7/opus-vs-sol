extends CanvasLayer

var hero: CharacterBody3D
var fps: Label
var pause_panel: Control
var location: Label
var minimap: Control
var elapsed := 0.0
var help: Label
var prompt: Label
var driving: Label
var wanted_label: Label
var health_bar: ProgressBar
var health_label: Label
var weapon_label: Label
var state_panel: Control
var state_title: Label
var overlay: Control

func label_at(text: String, pos: Vector2, size: int, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.04, 0.08, 0.12, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.add_child(label_at("НЕОНОВЫЙ ПРИЛИВ", Vector2(42, 26), 27, Color("ffdbb1")))
	root.add_child(label_at("Л А С - Б Р И С А С    /    1 9 8 7", Vector2(44, 62), 15))
	location = label_at("ОУШЕН-ДРАЙВ", Vector2(44, 96), 18, Color("82e5df"))
	root.add_child(location)
	driving = label_at("", Vector2(44, 128), 22, Color("ffdbb1"))
	root.add_child(driving)
	prompt = label_at("", Vector2(650, 945), 23, Color("a4ffc6"))
	root.add_child(prompt)
	help = label_at("", Vector2.ZERO, 18)
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.position = Vector2(42, -48)
	root.add_child(help)
	fps = label_at("", Vector2(1740, 32), 23, Color("a4ffc6"))
	fps.visible = false
	root.add_child(fps)
	wanted_label = label_at("☆☆☆☆☆", Vector2(1470, 72), 36, Color("ffda8b"))
	root.add_child(wanted_label)
	health_bar = ProgressBar.new()
	health_bar.position = Vector2(1474, 122)
	health_bar.size = Vector2(340, 16)
	health_bar.show_percentage = false
	health_bar.value = 100
	var health_background := StyleBoxFlat.new()
	health_background.bg_color = Color("243842")
	health_background.set_corner_radius_all(4)
	health_bar.add_theme_stylebox_override("background", health_background)
	var health_fill := StyleBoxFlat.new()
	health_fill.bg_color = Color("7cdda4")
	health_fill.set_corner_radius_all(4)
	health_bar.add_theme_stylebox_override("fill", health_fill)
	root.add_child(health_bar)
	health_label = label_at("ЗДОРОВЬЕ  100", Vector2(1474, 145), 18, Color("a8efc1"))
	root.add_child(health_label)
	weapon_label = label_at("БЕЗ ОРУЖИЯ", Vector2(1474, 178), 21, Color("ffe3b5"))
	root.add_child(weapon_label)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(draw_overlay)
	root.add_child(overlay)
	minimap = Control.new()
	minimap.position = Vector2(44, 780)
	minimap.custom_minimum_size = Vector2(220, 220)
	minimap.draw.connect(_draw_map)
	root.add_child(minimap)
	root.add_child(label_at("N ↑   /   ПОБЕРЕЖЬЕ", Vector2(44, 750), 14, Color("f8dbb9")))
	state_panel = Control.new()
	state_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	state_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(state_panel)
	var state_shade := ColorRect.new()
	state_shade.color = Color(0.02, 0.04, 0.065, 0.78)
	state_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	state_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state_panel.add_child(state_shade)
	state_title = label_at("", Vector2(510, 415), 76, Color("f2949b"))
	state_title.size.x = 900
	state_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_panel.add_child(state_title)
	var returning := label_at("ЛАС-БРИСАС  •  Возвращение…", Vector2(510, 525), 25)
	returning.size.x = 900
	returning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_panel.add_child(returning)
	state_panel.hide()
	pause_panel = Control.new()
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(pause_panel)
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.055, 0.09, 0.9)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(shade)
	var column := VBoxContainer.new()
	column.position = Vector2(740, 300)
	column.size = Vector2(440, 450)
	column.add_theme_constant_override("separation", 24)
	pause_panel.add_child(column)
	var title := label_at("ПАУЗА", Vector2.ZERO, 56, Color("ffc7ad"))
	column.add_child(title)
	var subtitle := label_at("Лас-Брисас подождёт.", Vector2.ZERO, 24)
	column.add_child(subtitle)
	for caption in ["Продолжить", "Выйти"]:
		var button := Button.new()
		button.text = caption
		button.custom_minimum_size = Vector2(440, 64)
		button.add_theme_font_size_override("font_size", 25)
		column.add_child(button)
		if caption == "Продолжить":
			button.pressed.connect(toggle_pause)
		else:
			button.pressed.connect(func(): get_tree().quit())
	pause_panel.hide()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("show_fps"):
		fps.visible = not fps.visible

func toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	pause_panel.visible = get_tree().paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED
	if get_tree().paused:
		pause_panel.find_children("*", "Button", true, false)[0].grab_focus()
	else:
		var combat = hero.get_parent().life.combat
		combat.cooldown = maxf(combat.cooldown, 0.2)

func _process(delta: float) -> void:
	if overlay != null:
		overlay.queue_redraw()
	elapsed += delta
	if elapsed > 0.2:
		elapsed = 0
		fps.text = "%d FPS" % Engine.get_frames_per_second()
		if is_instance_valid(hero):
			var city = hero.get_parent().life
			var combat = city.combat
			wanted_label.text = "★".repeat(city.wanted) + "☆".repeat(5 - city.wanted)
			wanted_label.modulate.a = 0.55 if city.wanted > 0 and city.unseen > 3 and int(Time.get_ticks_msec() / 450) % 2 == 0 else 1.0
			health_bar.value = city.health
			health_label.text = "ЗДОРОВЬЕ  %d" % city.health
			weapon_label.text = "БЕЗ ОРУЖИЯ" if combat.selected < 0 else combat.NAMES[combat.selected]
			if combat.selected > 0:
				weapon_label.text += "  %d / %d" % [combat.loaded[combat.selected], combat.reserve[combat.selected]]
			if combat.reloading > 0:
				weapon_label.text += "\nПЕРЕЗАРЯДКА…"
			state_panel.visible = city.outcome != ""
			state_title.text = city.outcome
			state_title.modulate = Color("9ecfff") if city.outcome == "АРЕСТОВАН" else Color("f2949b")
			var p := hero.position
			location.text = "ПЛЯЖ БРИСА" if p.x > 113 else ("ОУШЕН-ДРАЙВ" if p.x > 64 else ("МОТЕЛЬ «ПАЛЬМЫ»" if p.z < -80 else "ЦЕНТР / ЛАС-БРИСАС"))
			if hero.vehicle != null:
				var car = hero.vehicle
				driving.text = "%s  •  %03d км/ч  •  %d об/мин" % [car.DATA[car.kind][4], maxf(absf(car.speed), car.planar_velocity.length()) * 3.6, car.rpm]
				help.text = "W  газ     S  тормоз / задний ход     A/D  руль     ПРОБЕЛ  ручник     E  выйти     МЫШЬ  камера     F3  FPS     ESC  пауза"
				prompt.text = "Останавливаемся для выхода…" if car.exit_requested else "E  — выйти из машины"
			else:
				driving.text = ""
				help.text = "WASD  движение     МЫШЬ  камера     SHIFT  бег     ПРОБЕЛ  прыжок     E  сесть     F3  FPS     ESC  пауза"
				if combat.selected >= 0:
					help.text = "WASD  движение   SHIFT  бег   ПРОБЕЛ  прыжок   E  сесть   ПКМ  прицел   ЛКМ  атака   R  перезарядка   1/2/3, колесо  оружие   ESC  пауза"
				var car = hero.get_parent().nearest_vehicle()
				prompt.text = ("E  — вытащить водителя: " if car.ai_driver else "E  — сесть: ") + car.DATA[car.kind][4] if car != null else ""
			if hero.notice_time > 0:
				prompt.text = hero.notice
		minimap.queue_redraw()

func map_point(p: Vector3) -> Vector2:
	return Vector2((p.x + 220) * 0.5 + 10, (p.z + 200) * 0.5 + 10)

func _draw_map() -> void:
	minimap.draw_style_box(map_style(), Rect2(0, 0, 220, 220))
	minimap.draw_rect(Rect2(176, 10, 34, 200), Color("326978"))
	minimap.draw_rect(Rect2(177, 10, 16, 200), Color("c9b78f"))
	for x in [-180, -100, -20, 60]:
		var p := map_point(Vector3(x, 0, -200))
		minimap.draw_line(p, p + Vector2(0, 200), Color("657c86"), 5)
	for z in [-160, -80, 0, 80, 160]:
		var p := map_point(Vector3(-220, 0, z))
		minimap.draw_line(p, p + Vector2(165, 0), Color("657c86"), 5)
	if is_instance_valid(hero):
		var city = hero.get_parent().life
		for pickup in city.combat.pickups:
			if pickup.visible:
				minimap.draw_circle(map_point(pickup.global_position), 2.5, Color("ffcf78"))
		for car in get_tree().get_nodes_in_group("vehicles"):
			minimap.draw_rect(Rect2(map_point(car.global_position) - Vector2.ONE * 1.5, Vector2.ONE * 3), Color("ee7a91") if car.police_ai else Color("9db8bc"))
		for person in get_tree().get_nodes_in_group("cops"):
			if not person.fallen:
				minimap.draw_circle(map_point(person.global_position), 2, Color("80aaff"))
		var p := map_point(hero.position)
		var angle: float = hero.visual.rotation.y if hero.vehicle == null else hero.vehicle.rotation.y + PI
		var dir := Vector2(sin(angle), cos(angle))
		var right := Vector2(-dir.y, dir.x)
		minimap.draw_colored_polygon(PackedVector2Array([p + dir * 8, p - dir * 5 + right * 5, p - dir * 3, p - dir * 5 - right * 5]), Color("fff0b4"))

func draw_overlay() -> void:
	if not is_instance_valid(hero):
		return
	var city = hero.get_parent().life
	var combat = city.combat
	if city.hurt > 0 or city.impact_flash > 0:
		overlay.draw_rect(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size), Color(0.7, 0.12, 0.1, maxf(city.hurt, city.impact_flash) * 0.22))
	if hero.vehicle != null or city.outcome != "" or combat.selected < 0:
		return
	var center := get_viewport().get_visible_rect().size * 0.5
	var spread := 5.0 if combat.aiming else 10.0
	for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		overlay.draw_line(center + direction * spread, center + direction * (spread + 6), Color("fff1d7"), 2, true)
	if combat.hit_time > 0:
		for direction in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			overlay.draw_line(center + direction * 5, center + direction * 10, Color("ff8f86"), 2.5, true)

func map_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.08, 0.11, 0.88)
	style.set_border_width_all(1)
	style.border_color = Color("80c6c6")
	return style
