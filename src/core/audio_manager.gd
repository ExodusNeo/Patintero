extends Node

# Autoload: AudioManager
# Integrates high-fidelity studio sound effects from Sound FX Starter Pack Vol. 1
# and procedural sports synthesis (godot-audio / audio-design)

const TAG_SLAP_WAV := preload("res://Sound FX Starter Pack Vol. 1/Hollywood/Karate Punch.wav")
const TAG_HEAVY_WAV := preload("res://Sound FX Starter Pack Vol. 1/Hollywood/Deathpunch.wav")
const WHOOSH_WAV := preload("res://Sound FX Starter Pack Vol. 1/Medieval/Weapon Whoosh.wav")
const CHARGED_SWEEP_WAV := preload("res://Sound FX Starter Pack Vol. 1/Motions and Impacts/Whoosh Medieval.wav")
const SLIDE_WAV := preload("res://Sound FX Starter Pack Vol. 1/Retro/Slide.wav")
const HOME_RUN_WAV := preload("res://Sound FX Starter Pack Vol. 1/Jingles & Stingers/Success.wav")
const MILESTONE_WAV := preload("res://Sound FX Starter Pack Vol. 1/Jingles & Stingers/Milestone.wav")
const FOUL_WAV := preload("res://Sound FX Starter Pack Vol. 1/UI & Menus/Error.wav")
const GAME_OVER_WAV := preload("res://Sound FX Starter Pack Vol. 1/Jingles & Stingers/Game Over.wav")
const HEALTH_LOW_WAV := preload("res://Sound FX Starter Pack Vol. 1/Jingles & Stingers/Health Low.wav")
const AMBIENT_TRAFFIC_WAV := preload("res://Sound FX Starter Pack Vol. 1/Environment/Suburb Ext Distant Traffic Loop.wav")
const UI_CLICK_WAV := preload("res://Sound FX Starter Pack Vol. 1/UI & Menus/Click Bounce.wav")
const UI_START_WAV := preload("res://Sound FX Starter Pack Vol. 1/UI & Menus/Start.wav")
const UI_NOTIF_WAV := preload("res://Sound FX Starter Pack Vol. 1/UI & Menus/Notification.wav")
const IMPACT_FALL_WAV := preload("res://Sound FX Starter Pack Vol. 1/Motions and Impacts/Impact Redwood.wav")

var whistle_stream: AudioStreamWAV
var step_stream: AudioStreamWAV
var panting_stream: AudioStreamWAV
var heartbeat_stream: AudioStreamWAV

var player_pool: Array[AudioStreamPlayer] = []
const POOL_SIZE := 8

var panting_player: AudioStreamPlayer
var heartbeat_player: AudioStreamPlayer
var ambient_player: AudioStreamPlayer

var master_volume: float = 0.8
var is_muted: bool = false
signal volume_changed(new_linear_volume: float, is_muted: bool)

func _ready() -> void:
	_init_streams()
	_create_player_pool()
	_create_special_players()
	set_master_volume(0.8)
	
	NetworkManager.player_tagged.connect(func(_r, _t): play_tag_sequence())
	NetworkManager.player_foul.connect(func(_p, _r): play_whistle(true))

func _init_streams() -> void:
	whistle_stream = AudioProceduralSynth.generate_whistle()
	step_stream = AudioProceduralSynth.generate_footstep()
	panting_stream = AudioProceduralSynth.generate_panting()
	heartbeat_stream = AudioProceduralSynth.generate_heartbeat()

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
	return 0.0 if peak_db < -55.0 else clamp(db_to_linear(peak_db), 0.0, 1.0)

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
	ambient_player.stream = AMBIENT_TRAFFIC_WAV
	ambient_player.volume_db = -24.0
	add_child(ambient_player)
	ambient_player.play()

func _play_stream(stream: AudioStream, vol_db: float = 0.0, pitch_var: float = 0.05) -> void:
	for p in player_pool:
		if not p.playing:
			p.stream = stream
			p.volume_db = vol_db
			p.pitch_scale = randf_range(1.0 - pitch_var, 1.0 + pitch_var)
			p.play()
			return
	player_pool[0].stream = stream
	player_pool[0].volume_db = vol_db
	player_pool[0].play()

func play_whistle(is_double: bool = false) -> void:
	_play_stream(whistle_stream, -4.0, 0.03)
	if is_double:
		get_tree().create_timer(0.2).timeout.connect(func(): _play_stream(whistle_stream, -4.0, 0.03))

func play_tag_sequence() -> void:
	_play_stream(TAG_SLAP_WAV, 2.0, 0.06)
	get_tree().create_timer(0.12).timeout.connect(func(): play_whistle(true))

func play_footstep(volume_scale: float = 1.0) -> void:
	var vol_db := linear_to_db(clamp(volume_scale * 0.35, 0.001, 1.0))
	_play_stream(step_stream, vol_db, 0.12)

func play_slide_skid() -> void:
	_play_stream(SLIDE_WAV, -2.0, 0.06)

func play_knockdown_thud() -> void:
	_play_stream(IMPACT_FALL_WAV, 1.0, 0.08)

func play_juke_whoosh() -> void:
	_play_stream(WHOOSH_WAV, -3.0, 0.08)

func play_charged_swing() -> void:
	_play_stream(CHARGED_SWEEP_WAV, 0.0, 0.05)

func play_home_run() -> void:
	_play_stream(HOME_RUN_WAV, 0.0, 0.0)

func play_milestone() -> void:
	_play_stream(MILESTONE_WAV, -2.0, 0.0)

func play_foul() -> void:
	_play_stream(FOUL_WAV, -2.0, 0.0)
	get_tree().create_timer(0.15).timeout.connect(func(): play_whistle(true))

func play_game_over() -> void:
	_play_stream(GAME_OVER_WAV, 0.0, 0.0)

func play_ui_click() -> void:
	_play_stream(UI_CLICK_WAV, -3.0, 0.04)

func play_ui_start() -> void:
	_play_stream(UI_START_WAV, -1.0, 0.0)

func play_ui_notification() -> void:
	_play_stream(UI_NOTIF_WAV, -2.0, 0.0)

func set_low_stamina_active(active: bool, intensity: float = 1.0) -> void:
	if not is_instance_valid(panting_player) or not is_instance_valid(heartbeat_player):
		return
	if active and not is_muted and master_volume > 0.01:
		var vol_db := linear_to_db(clamp(intensity * 0.85, 0.001, 1.0))
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
