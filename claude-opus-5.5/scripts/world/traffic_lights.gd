class_name TrafficLights
extends Node
## Drives every traffic light in the city from one shared cycle.
## Axis 0 = traffic along Z (north/south), axis 1 = traffic along X (east/west).

enum Light { RED, YELLOW, GREEN }

const GREEN_TIME := 12.0
const YELLOW_TIME := 3.0
const ALL_RED_TIME := 1.5

# Lens centres in trafficlight.glb local space. The head hangs at -X and has lenses on
# both faces: a flat face at -Z and a hooded face at +Z.
const LAMP_X := -2.935
const LAMP_Z := [-0.31, 0.31]
const LAMP_Y := [3.335, 2.78, 2.225] # red, yellow, green

var _heads := [[], []] # per axis: array of lamps; lamp = [MeshInstance3D front, back]
var _mat_on := {}
var _time := 0.0
var _phase := -1

func _init() -> void:
	var colors := {Light.RED: Color(1.0, 0.12, 0.08), Light.YELLOW: Color(1.0, 0.7, 0.1), Light.GREEN: Color(0.15, 1.0, 0.4)}
	for s in colors:
		var m := StandardMaterial3D.new()
		m.albedo_color = colors[s]
		m.emission_enabled = true
		m.emission = colors[s]
		m.emission_energy_multiplier = 2.2
		m.roughness = 0.15
		_mat_on[s] = m


## Adds glowing glass caps over the lenses of a placed trafficlight model. Only the lit
## lamp is shown; unlit lamps keep the model's own glass.
func register(model: Node3D, axis: int, lamp_mesh: Mesh, visibility_end: float) -> void:
	var lamps := []
	for i in 3:
		var pair := []
		for side in 2:
			var mi := MeshInstance3D.new()
			mi.mesh = lamp_mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = visibility_end
			mi.position = Vector3(LAMP_X, LAMP_Y[i], LAMP_Z[side])
			mi.rotation.x = PI / 2   # flatten the dome along Z
			mi.material_override = _mat_on[i]
			mi.visible = false
			model.add_child(mi)
			pair.append(mi)
		lamps.append(pair)
	_heads[axis].append(lamps)


func _process(delta: float) -> void:
	_time = fmod(_time + delta, 2.0 * (GREEN_TIME + YELLOW_TIME + ALL_RED_TIME))
	var half := GREEN_TIME + YELLOW_TIME + ALL_RED_TIME
	var t := fmod(_time, half)
	var active_axis := 0 if _time < half else 1
	var sig := Light.GREEN if t < GREEN_TIME else (Light.YELLOW if t < GREEN_TIME + YELLOW_TIME else Light.RED)
	var phase := active_axis * 3 + sig
	if phase == _phase:
		return
	_phase = phase
	for axis in 2:
		var s: int = sig if axis == active_axis else Light.RED
		for lamps in _heads[axis]:
			for i in 3:
				for mi in lamps[i]:
					mi.visible = (i == s)


## Current signal for traffic moving along the given axis (for future AI traffic).
func get_signal(axis: int) -> int:
	var half := GREEN_TIME + YELLOW_TIME + ALL_RED_TIME
	var active_axis := 0 if _time < half else 1
	if axis != active_axis:
		return Light.RED
	var t := fmod(_time, half)
	return Light.GREEN if t < GREEN_TIME else (Light.YELLOW if t < GREEN_TIME + YELLOW_TIME else Light.RED)
