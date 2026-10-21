class_name EngineAudio
extends AudioStreamPlayer3D
## Engine sound synthesised in code: a firing-frequency pulse with harmonics and some
## noise, low-pass filtered. Pitch follows rpm, loudness and brightness follow throttle.

const MIX_RATE := 22050.0

var rpm := 900.0
var throttle := 0.0
var cylinders := 4

var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0
var _lp := 0.0
var _lp2 := 0.0
var _rpm_smooth := 900.0
var _thr_smooth := 0.0
var _running := false
var _level := 0.0          # fades in/out on start/stop
var _rng := RandomNumberGenerator.new()

static var _crash: AudioStreamWAV


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.12
	stream = gen
	unit_size = 8.0
	max_distance = 120.0
	volume_db = -4.0


func set_running(value: bool) -> void:
	_running = value
	if value and not playing:
		play()
		_playback = get_stream_playback()


func _process(delta: float) -> void:
	if not playing:
		return
	if not _running and _level <= 0.001:
		stop()
		_playback = null
		return
	_fill()


func _fill() -> void:
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(frames)
	var target_level := 1.0 if _running else 0.0
	for i in frames:
		# Per-sample smoothing avoids zipper noise when rpm jumps between gears.
		_rpm_smooth += (rpm - _rpm_smooth) * 0.0015
		_thr_smooth += (throttle - _thr_smooth) * 0.0008
		_level += (target_level - _level) * 0.0004
		var fire_hz := _rpm_smooth / 60.0 * cylinders * 0.5
		_phase = fmod(_phase + fire_hz / MIX_RATE, 1.0)
		var p := _phase * TAU
		var s := sin(p) * 0.55 + sin(p * 2.0 + 0.7) * 0.28 + sin(p * 3.0 + 1.3) * (0.1 + 0.2 * _thr_smooth)
		s += sin(p * 0.5) * 0.35                       # sub-harmonic rumble
		s += (_rng.randf() * 2.0 - 1.0) * (0.06 + 0.18 * _thr_smooth)
		# Two one-pole low-pass stages; opening up with throttle.
		var a := 0.12 + 0.25 * _thr_smooth
		_lp += (s - _lp) * a
		_lp2 += (_lp - _lp2) * a
		var v := _lp2 * (0.45 + 0.55 * _thr_smooth) * _level * 0.8
		buf[i] = Vector2(v, v)
	_playback.push_buffer(buf)


static func crash_stream() -> AudioStreamWAV:
	## Short metallic crunch: decaying filtered noise with a low thump, generated once.
	if _crash:
		return _crash
	var rate := 22050
	var n := int(rate * 0.6)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * 9.0)
		var noise := rng.randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.35
		var thump := sin(TAU * 55.0 * t) * exp(-t * 14.0)
		var ring := sin(TAU * 410.0 * t + sin(TAU * 13.0 * t) * 2.0) * exp(-t * 6.0) * 0.25
		var v := clampf((lp * 0.9 + thump * 0.8 + ring) * env, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	_crash = AudioStreamWAV.new()
	_crash.format = AudioStreamWAV.FORMAT_16_BITS
	_crash.mix_rate = rate
	_crash.stereo = false
	_crash.data = data
	return _crash
