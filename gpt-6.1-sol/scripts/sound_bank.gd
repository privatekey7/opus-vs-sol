extends RefCounted

static var cache: Dictionary = {}

static func sound(id: String) -> AudioStreamWAV:
	if cache.has(id):
		return cache[id]
	var duration := 0.3
	if id in ["siren", "engine"]:
		duration = 2.0
	var rate := 22050
	var samples := int(duration * rate)
	var data := PackedByteArray()
	data.resize(samples * 2)
	var phase := 0.0
	var noise := 0.0
	for i in samples:
		var t := float(i) / rate
		var wave := 0.0
		noise = noise * 0.65 + randf_range(-1, 1) * 0.35
		match id:
			"siren":
				phase += (720 + 280 * sin(t * TAU * 0.5)) / rate
				wave = sin(phase * TAU) * 0.4 + sin(phase * TAU * 3) * 0.08
			"engine":
				wave = sin(t * TAU * 70) * 0.27 + sin(t * TAU * 140) * 0.12
			"pistol":
				wave = (noise * 1.5 + sin(t * 720) * 0.3) * exp(-t * 35)
			"shotgun":
				wave = (noise * 1.6 + sin(t * 420) * 0.6) * exp(-t * 17)
			"impact":
				wave = (noise * 1.5 + sin(t * 360) * 0.7) * exp(-t * 12)
			"bat":
				wave = (noise * 0.8 + sin(t * 540) * 0.4) * exp(-t * 23)
			"reload":
				wave = noise * exp(-fmod(t, 0.1) * 85) * 0.45
		var value := int(clampf(wave, -0.98, 0.98) * 32767)
		data.encode_s16(i * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	if id in ["siren", "engine"]:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = samples
	cache[id] = stream
	return stream
