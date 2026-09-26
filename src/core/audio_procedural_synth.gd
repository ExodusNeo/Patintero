extends RefCounted
class_name AudioProceduralSynth

# Lightweight procedural PCM synthesis helper for authentic sports sounds
# Whistle trill, asphalt slipper steps, and physical exhaustion breathing
# godot-audio / audio-design

static func generate_whistle() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.28
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples)
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var trill := sin(2.0 * PI * 35.0 * t) * 150.0
		var wave := (sin(2.0 * PI * (2600.0 + trill) * t) + 0.7 * sin(2.0 * PI * (2900.0 + trill) * t)) * 0.5
		var env := (t / 0.02) if t < 0.02 else ((0.28 - t) / 0.06 if t > 0.22 else 1.0)
		data[i] = int(clamp((wave * env * 0.45 + 0.5) * 255.0, 0, 255))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	return wav

static func generate_footstep() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.07
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples)
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var wave := (sin(2.0 * PI * 75.0 * t) * 0.8 + randf_range(-0.4, 0.4) * 0.3) * exp(-50.0 * t)
		data[i] = int(clamp((wave * 0.4 + 0.5) * 255.0, 0, 255))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	return wav

static func generate_panting() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.75
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples)
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var wave := 0.0
		if t < 0.32:
			wave = randf_range(-0.6, 0.6) * sin(PI * (t / 0.32)) * 0.7
		elif t >= 0.38 and t < 0.72:
			var env := sin(PI * ((t - 0.38) / 0.34))
			wave = (randf_range(-0.8, 0.8) + sin(2.0 * PI * 85.0 * t) * 0.25) * env * 0.9
		data[i] = int(clamp((wave * 0.35 + 0.5) * 255.0, 0, 255))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = total_samples
	wav.data = data
	return wav

static func generate_heartbeat() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.65
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples)
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var wave := 0.0
		if t < 0.16:
			wave = sin(2.0 * PI * 65.0 * t) * exp(-26.0 * t) * 1.3
		elif t >= 0.18 and t < 0.34:
			wave = sin(2.0 * PI * 55.0 * (t - 0.18)) * exp(-28.0 * (t - 0.18)) * 1.0
		data[i] = int(clamp((wave * 0.45 + 0.5) * 255.0, 0, 255))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = total_samples
	wav.data = data
	return wav
