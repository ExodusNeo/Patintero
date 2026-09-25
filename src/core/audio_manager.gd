extends Node

# Autoload: AudioManager
# Implements procedural game sound effects (godot-audio / audio-design)

var whistle_stream: AudioStreamWAV
var tag_stream: AudioStreamWAV
var step_stream: AudioStreamWAV
var score_stream: AudioStreamWAV
var foul_stream: AudioStreamWAV
var slide_stream: AudioStreamWAV
var whoosh_stream: AudioStreamWAV
var charged_whoosh_stream: AudioStreamWAV
var panting_stream: AudioStreamWAV
var heartbeat_stream: AudioStreamWAV
var ambient_stream: AudioStreamWAV

var player_pool: Array[AudioStreamPlayer] = []
const POOL_SIZE := 8

var panting_player: AudioStreamPlayer
var heartbeat_player: AudioStreamPlayer
var ambient_player: AudioStreamPlayer

var master_volume: float = 0.8
var is_muted: bool = false
signal volume_changed(new_linear_volume: float, is_muted: bool)

func _ready() -> void:
	_generate_audio_assets()
	_create_player_pool()
	_create_special_players()
	set_master_volume(0.8)
	
	# Connect to NetworkManager signals
	NetworkManager.player_tagged.connect(func(_r, _t): play_tag_sequence())
	NetworkManager.player_foul.connect(func(_p, _r): play_whistle(true))

func set_master_volume(linear_val: float) -> void:
	master_volume = clamp(linear_val, 0.0, 1.0)
	var bus := AudioServer.get_bus_index("Master")
	if master_volume <= 0.01 or is_muted:
		AudioServer.set_bus_mute(bus, true)
	else:
		AudioServer.set_bus_mute(bus, false)
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.0001)))
	volume_changed.emit(master_volume, is_muted)

func toggle_mute() -> bool:
	is_muted = not is_muted
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, is_muted or master_volume <= 0.01)
	volume_changed.emit(master_volume, is_muted)
	return is_muted

func get_peak_volume() -> float:
	var bus := AudioServer.get_bus_index("Master")
	if is_muted or master_volume <= 0.01:
		return 0.0
	var peak_db := AudioServer.get_bus_peak_volume_left_db(bus, 0)
	if peak_db < -55.0:
		return 0.0
	return clamp(db_to_linear(peak_db), 0.0, 1.0)

func _create_player_pool() -> void:
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		player_pool.append(p)

func _create_special_players() -> void:
	panting_player = AudioStreamPlayer.new()
	panting_player.bus = "Master"
	panting_player.stream = panting_stream
	add_child(panting_player)

	heartbeat_player = AudioStreamPlayer.new()
	heartbeat_player.bus = "Master"
	heartbeat_player.stream = heartbeat_stream
	add_child(heartbeat_player)

	ambient_player = AudioStreamPlayer.new()
	ambient_player.bus = "Master"
	ambient_player.stream = ambient_stream
	ambient_player.volume_db = -18.0
	add_child(ambient_player)
	ambient_player.play()

func _get_available_player() -> AudioStreamPlayer:
	for p in player_pool:
		if not p.playing:
			return p
	return player_pool[0]

# --- AUDIO GENERATION (Clean procedural PCM WAVs) ---
func _generate_audio_assets() -> void:
	whistle_stream = _gen_whistle()
	tag_stream = _gen_tag_slap()
	step_stream = _gen_footstep()
	score_stream = _gen_score_jingle()
	foul_stream = _gen_foul_buzzer()
	slide_stream = _gen_slide_skid()
	whoosh_stream = _gen_whoosh()
	charged_whoosh_stream = _gen_charged_whoosh()
	panting_stream = _gen_panting()
	heartbeat_stream = _gen_heartbeat()
	ambient_stream = _gen_ambient_loop()

func _gen_whistle() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.28
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples)
	
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var trill := sin(2.0 * PI * 35.0 * t) * 150.0
		var freq1 := 2600.0 + trill
		var freq2 := 2900.0 + trill
		var wave := (sin(2.0 * PI * freq1 * t) + 0.7 * sin(2.0 * PI * freq2 * t)) * 0.5
		
		var env := 1.0
		if t < 0.02:
			env = t / 0.02
		elif t > 0.22:
			env = (0.28 - t) / 0.06
		
		var sample := int(clamp((wave * env * 0.45 + 0.5) * 255.0, 0, 255))
		data[i] = sample
	
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	return wav

func _gen_tag_slap() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.14
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples)
	
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var noise := randf_range(-1.0, 1.0)
		var thump := sin(2.0 * PI * 110.0 * t) * 1.5
		var decay := exp(-28.0 * t)
		var wave := (noise * 0.7 + thump * 0.3) * decay
		
		var sample := int(clamp((wave * 0.5 + 0.5) * 255.0, 0, 255))
		data[i] = sample
	
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	return wav

func _gen_footstep() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.07
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples)
	
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var noise := randf_range(-0.4, 0.4)
		var thump := sin(2.0 * PI * 75.0 * t) * 0.8
		var decay := exp(-50.0 * t)
		var wave := (thump + noise * 0.3) * decay
		
		var sample := int(clamp((wave * 0.4 + 0.5) * 255.0, 0, 255))
		data[i] = sample
	
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	return wav

func _gen_score_jingle() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.55
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples)
	
	var notes := [523.25, 659.25, 783.99, 1046.5]
	var note_dur := duration / float(notes.size())
	
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var note_idx := int(t / note_dur)
		note_idx = clamp(note_idx, 0, notes.size() - 1)
		var note_t := fmod(t, note_dur)
		
		var freq: float = notes[note_idx]
		var wave := sin(2.0 * PI * freq * note_t) * exp(-5.0 * note_t)
		var sample := int(clamp((wave * 0.35 + 0.5) * 255.0, 0, 255))
		data[i] = sample
	
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	return wav

func _gen_foul_buzzer() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.35
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples)
	
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var wave := 1.0 if sin(2.0 * PI * 130.0 * t) > 0 else -1.0
		var decay := 1.0 if t < 0.28 else (0.35 - t) / 0.07
		var sample := int(clamp((wave * decay * 0.25 + 0.5) * 255.0, 0, 255))
		data[i] = sample
	
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	return wav

func _gen_slide_skid() -> AudioStreamWAV:
	# Athletic rubber sneaker skid on street concrete / asphalt
	var sample_rate := 22050
	var duration := 0.32
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples)
	
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var noise := randf_range(-0.85, 0.85)
		var screech_freq := 950.0 - 450.0 * (t / duration)
		var screech := sin(2.0 * PI * screech_freq * t) * 0.35
		var decay := exp(-9.0 * t)
		var wave := (noise * 0.65 + screech) * decay
		
		var sample := int(clamp((wave * 0.45 + 0.5) * 255.0, 0, 255))
		data[i] = sample
	
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	return wav

func _gen_whoosh() -> AudioStreamWAV:
	# Quick aerodynamic whoosh for jukes / quick swings
	var sample_rate := 22050
	var duration := 0.18
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples)
	
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var p := t / duration
		var noise := randf_range(-0.7, 0.7)
		var f := 320.0 + 380.0 * sin(PI * p)
		var tone := sin(2.0 * PI * f * t) * 0.5
		var env := sin(PI * p)
		var wave := (noise * 0.45 + tone * 0.55) * env
		
		var sample := int(clamp((wave * 0.4 + 0.5) * 255.0, 0, 255))
		data[i] = sample
	
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	return wav

func _gen_charged_whoosh() -> AudioStreamWAV:
	# Heavy, bass-heavy swoosh for charged sweep tag
	var sample_rate := 22050
	var duration := 0.35
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples)
	
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var p := t / duration
		var f := 160.0 + 360.0 * (1.0 - p)
		var noise := randf_range(-0.6, 0.6)
		var rumble := sin(2.0 * PI * f * t)
		var env := sin(PI * pow(p, 0.65))
		var wave := (rumble * 0.7 + noise * 0.3) * env
		
		var sample := int(clamp((wave * 0.5 + 0.5) * 255.0, 0, 255))
		data[i] = sample
	
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	return wav

func _gen_panting() -> AudioStreamWAV:
	# Heavy breathing loop for runner when exhausted
	var sample_rate := 22050
	var duration := 0.75
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples)
	
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var wave := 0.0
		# Inhale (0.0 to 0.32s)
		if t < 0.32:
			var env := sin(PI * (t / 0.32))
			wave = randf_range(-0.6, 0.6) * env * 0.7
		# Exhale (0.38 to 0.72s)
		elif t >= 0.38 and t < 0.72:
			var env := sin(PI * ((t - 0.38) / 0.34))
			var low_undertone := sin(2.0 * PI * 85.0 * t) * 0.25
			wave = (randf_range(-0.8, 0.8) + low_undertone) * env * 0.9
		
		var sample := int(clamp((wave * 0.35 + 0.5) * 255.0, 0, 255))
		data[i] = sample
	
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = total_samples
	wav.data = data
	return wav

func _gen_heartbeat() -> AudioStreamWAV:
	# Muffled bass heartbeat "lub-dub" double thump loop
	var sample_rate := 22050
	var duration := 0.65
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples)
	
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		var wave := 0.0
		# Beat 1 (t = 0.0 to 0.16s)
		if t < 0.16:
			var decay := exp(-26.0 * t)
			wave = sin(2.0 * PI * 65.0 * t) * decay * 1.3
		# Beat 2 (t = 0.18 to 0.34s)
		elif t >= 0.18 and t < 0.34:
			var t2 := t - 0.18
			var decay := exp(-28.0 * t2)
			wave = sin(2.0 * PI * 55.0 * t2) * decay * 1.0
		
		var sample := int(clamp((wave * 0.45 + 0.5) * 255.0, 0, 255))
		data[i] = sample
	
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = total_samples
	wav.data = data
	return wav

# --- PUBLIC PLAY FUNCTIONS (godot-audio pitch variation) ---
func play_whistle(is_double: bool = false) -> void:
	var p := _get_available_player()
	p.stream = whistle_stream
	p.pitch_scale = randf_range(0.97, 1.03)
	p.volume_db = -4.0
	p.play()
	
	if is_double:
		get_tree().create_timer(0.2).timeout.connect(func():
			var p2 := _get_available_player()
			p2.stream = whistle_stream
			p2.pitch_scale = 1.05
			p2.volume_db = -4.0
			p2.play()
		)

func play_tag_sequence() -> void:
	var p := _get_available_player()
	p.stream = tag_stream
	p.pitch_scale = randf_range(0.95, 1.05)
	p.volume_db = 0.0
	p.play()
	
	get_tree().create_timer(0.12).timeout.connect(func():
		play_whistle(true)
	)

func play_footstep(volume_scale: float = 1.0) -> void:
	var p := _get_available_player()
	p.stream = step_stream
	p.pitch_scale = randf_range(0.9, 1.15)
	p.volume_db = linear_to_db(clamp(volume_scale * 0.35, 0.001, 1.0))
	p.play()

func play_slide_skid() -> void:
	var p := _get_available_player()
	p.stream = slide_stream
	p.pitch_scale = randf_range(0.95, 1.08)
	p.volume_db = -2.0
	p.play()

func play_juke_whoosh() -> void:
	var p := _get_available_player()
	p.stream = whoosh_stream
	p.pitch_scale = randf_range(0.96, 1.12)
	p.volume_db = -4.0
	p.play()

func play_charged_swing() -> void:
	var p := _get_available_player()
	p.stream = charged_whoosh_stream
	p.pitch_scale = randf_range(0.92, 1.04)
	p.volume_db = -1.0
	p.play()

func set_low_stamina_active(active: bool, intensity: float = 1.0) -> void:
	if not is_instance_valid(panting_player) or not is_instance_valid(heartbeat_player):
		return
	
	if active and not is_muted and master_volume > 0.01:
		var target_vol_linear: float = clamp(intensity * 0.85, 0.001, 1.0)
		var vol_db: float = linear_to_db(target_vol_linear)
		
		panting_player.volume_db = vol_db - 4.0
		heartbeat_player.volume_db = vol_db - 2.0
		
		if not panting_player.playing:
			panting_player.play()
		if not heartbeat_player.playing:
			heartbeat_player.play()
	else:
		if panting_player.playing:
			panting_player.stop()
		if heartbeat_player.playing:
			heartbeat_player.stop()

func play_home_run() -> void:
	var p := _get_available_player()
	p.stream = score_stream
	p.pitch_scale = 1.0
	p.volume_db = -2.0
	p.play()

func play_foul() -> void:
	var p := _get_available_player()
	p.stream = foul_stream
	p.pitch_scale = 1.0
	p.volume_db = -3.0
	p.play()
	get_tree().create_timer(0.15).timeout.connect(func(): play_whistle(true))

func _gen_ambient_loop() -> AudioStreamWAV:
	# 4.0 second loopable soft street air / neighborhood breeze ambiance
	var sample_rate := 22050
	var duration := 4.0
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	
	var last_val := 0.0
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		# Filtered pink noise (breeze) + subtle low-frequency air
		var white := randf_range(-1.0, 1.0)
		last_val = lerpf(last_val, white, 0.08)
		var air_swell: float = (sin(t * 1.5) * 0.3 + sin(t * 0.7) * 0.2)
		var val: float = (last_val * (0.6 + air_swell)) * 0.12
		
		# Smooth loop fade at edges (first and last 0.25s)
		if t < 0.25:
			val *= (t / 0.25)
		elif t > (duration - 0.25):
			val *= ((duration - t) / 0.25)
		
		var sample := int(clamp(val * 32767.0, -32768.0, 32767.0))
		data.encode_s16(i * 2, sample)
	
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = num_samples
	stream.data = data
	return stream

