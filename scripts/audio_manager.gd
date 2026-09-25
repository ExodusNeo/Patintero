extends Node

# Autoload: AudioManager
# Implements procedural game sound effects (godot-audio / audio-design)

var whistle_stream: AudioStreamWAV
var tag_stream: AudioStreamWAV
var step_stream: AudioStreamWAV
var score_stream: AudioStreamWAV
var foul_stream: AudioStreamWAV

var player_pool: Array[AudioStreamPlayer] = []
const POOL_SIZE := 8

func _ready() -> void:
	_generate_audio_assets()
	_create_player_pool()
	
	# Connect to NetworkManager signals
	NetworkManager.player_tagged.connect(func(_r, _t): play_tag_sequence())
	NetworkManager.player_foul.connect(func(_p, _r): play_whistle(true))

func _create_player_pool() -> void:
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		player_pool.append(p)

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

func _gen_whistle() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.28
	var total_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total_samples)
	
	for i in range(total_samples):
		var t := float(i) / float(sample_rate)
		# Dual frequency referee whistle with flutter/trill
		var trill := sin(2.0 * PI * 35.0 * t) * 150.0
		var freq1 := 2600.0 + trill
		var freq2 := 2900.0 + trill
		var wave := (sin(2.0 * PI * freq1 * t) + 0.7 * sin(2.0 * PI * freq2 * t)) * 0.5
		
		# Envelope: fast attack, slight pulse, decay
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
		# Percussive white noise + low thump
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
	
	# Arpeggio: C5 (523Hz), E5 (659Hz), G5 (784Hz), C6 (1046Hz)
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
		# Low buzzing square wave
		var wave := 1.0 if sin(2.0 * PI * 130.0 * t) > 0 else -1.0
		var decay := 1.0 if t < 0.28 else (0.35 - t) / 0.07
		var sample := int(clamp((wave * decay * 0.25 + 0.5) * 255.0, 0, 255))
		data[i] = sample
	
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
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
	# Punchy slap followed immediately by referee whistle!
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
