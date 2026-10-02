extends RefCounted

## Small deterministic mechanical layers, mixed below the selected weapon sounds.
## Generated once and cached. Private noise never advances the gameplay RNG.
static var _streams: Dictionary = {}

static func stream(kind: String) -> AudioStreamWAV:
	if _streams.has(kind):
		return _streams[kind]
	var rate := 22050
	var duration := 1.0 if kind == "motor" else 0.22 if kind == "servo" else 0.16
	var count := int(rate * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 3741 + kind.hash()
	var filtered := 0.0
	for index in count:
		var time := float(index) / rate
		var progress := float(index) / count
		filtered = lerpf(filtered, random.randf_range(-1.0, 1.0), 0.11 if kind == "concrete" else 0.28)
		var value := 0.0
		if kind == "motor":
			value = (sin(TAU * 72.0 * time) * 0.34 + sin(TAU * 144.0 * time) * 0.16 + filtered * 0.12) * (0.8 + 0.2 * sin(TAU * 4.0 * time))
		elif kind == "servo":
			var phase := TAU * (310.0 * time - 320.0 * time * time)
			value = (sin(phase) * 0.36 + sin(phase * 2.0) * 0.12 + filtered * 0.16) * sin(PI * progress) * (1.0 - progress)
		elif kind == "concrete":
			value = (filtered * 0.75 + sin(TAU * 95.0 * time) * 0.25) * exp(-progress * 6.0)
		else:
			value = (filtered * 0.5 + sin(TAU * 170.0 * time) * 0.30 + sin(TAU * 460.0 * time) * 0.15) * exp(-progress * 8.0)
		if kind != "motor":
			value *= minf(1.0, time / 0.003) * minf(1.0, (duration - time) / 0.01)
		data.encode_s16(index * 2, int(clampf(value, -0.95, 0.95) * 20000.0))
	var result := AudioStreamWAV.new()
	result.format = AudioStreamWAV.FORMAT_16_BITS
	result.mix_rate = rate
	result.data = data
	if kind == "motor":
		result.loop_mode = AudioStreamWAV.LOOP_FORWARD
		result.loop_end = count
	_streams[kind] = result
	return result
