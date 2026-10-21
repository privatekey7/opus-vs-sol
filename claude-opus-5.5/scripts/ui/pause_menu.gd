class_name PauseMenu
extends CanvasLayer
## Esc toggles pause: shows the cursor and «Продолжить» / «Выйти».

var enabled := false   # becomes true once the world is loaded
var _panel: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_panel = ColorRect.new()
	_panel.color = Color(0.05, 0.02, 0.12, 0.6)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.visible = false
	add_child(_panel)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-200, -150)
	box.size = Vector2(400, 300)
	box.add_theme_constant_override("separation", 24)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "ПАУЗА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(1.0, 0.45, 0.75))
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.0, 0.2))
	title.add_theme_constant_override("outline_size", 12)
	box.add_child(title)

	var resume := _make_button("Продолжить")
	resume.pressed.connect(set_paused.bind(false))
	box.add_child(resume)
	var quit := _make_button("Выйти")
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(400, 64)
	b.add_theme_font_size_override("font_size", 30)
	return b


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event.is_action_pressed("pause"):
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif not get_tree().paused and event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func set_paused(p: bool) -> void:
	get_tree().paused = p
	_panel.visible = p
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p else Input.MOUSE_MODE_CAPTURED
	if p:
		(_panel.find_children("*", "Button", true, false)[0] as Button).grab_focus()
