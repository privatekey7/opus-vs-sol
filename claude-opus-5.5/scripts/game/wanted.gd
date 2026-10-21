class_name WantedSystem
extends Node
## Wanted level 0–5 driven by "heat" from crimes. Stars fade when no cop has seen the
## player for a while.

signal level_changed(level: int)

const THRESHOLDS := [0.0, 1.0, 4.0, 9.0, 15.0, 24.0]   # heat needed for 0..5 stars
const HEAT := {
	"shots": 1.0, "hit_ped": 1.5, "run_over": 2.0, "kill_ped": 2.5, "carjack": 2.0,
	"attack_cop": 4.0, "hit_cop": 4.0, "kill_cop": 6.0, "ram_police": 2.0,
}
const MIN_LEVEL := {"shots": 1, "carjack": 1, "run_over": 1, "kill_ped": 1, "attack_cop": 2, "hit_cop": 2, "kill_cop": 3, "ram_police": 1}

var level := 0
var heat := 0.0
var unseen_time := 0.0
var fading := false        # stars blink while they are about to go down
var _fade_t := 0.0


func report(crime: String, _pos: Vector3) -> void:
	heat += HEAT.get(crime, 1.0)
	var min_level: int = MIN_LEVEL.get(crime, 1)
	heat = maxf(heat, THRESHOLDS[min_level])
	heat = minf(heat, THRESHOLDS[5] + 6.0)
	unseen_time = 0.0
	_update_level()


func seen() -> void:
	unseen_time = 0.0


func clear() -> void:
	heat = 0.0
	unseen_time = 0.0
	_update_level()


func _update_level() -> void:
	var l := 0
	for i in THRESHOLDS.size():
		if heat >= THRESHOLDS[i] and i > 0:
			l = i
	if l != level:
		level = l
		level_changed.emit(level)


func _process(delta: float) -> void:
	if level == 0:
		fading = false
		return
	unseen_time += delta
	var grace := 7.0 + level * 2.0
	fading = unseen_time > grace
	if fading:
		_fade_t += delta
		if _fade_t > 7.0:
			_fade_t = 0.0
			# Drop one star.
			heat = THRESHOLDS[level - 1] if level > 1 else 0.0
			_update_level()
	else:
		_fade_t = 0.0
