extends Node

# Autoload: SettingsManager
# Centralized settings persistence for input, video, audio, and camera feel
# input-systems / godot-ui-control / godot-audio

signal settings_changed
signal sensitivity_changed(mouse_sens: float, joypad_sens: float, invert_y: bool)
signal fov_changed(new_fov: float)

const SETTINGS_FILE_PATH := "user://settings.cfg"

# Input Settings
var mouse_sensitivity: float = 1.0 # Multiplier (0.2 to 3.0)
var joypad_sensitivity: float = 1.0 # Multiplier (0.2 to 3.0)
var invert_y: bool = false

# Camera / Display Settings
var base_fov: float = 85.0 # Degrees (70.0 to 110.0)
var display_mode: int = 0 # 0: Windowed, 1: Borderless, 2: Exclusive Fullscreen

# Audio Settings
var master_volume: float = 0.8
var is_muted: bool = false

func _ready() -> void:
	load_settings()
	apply_display_mode()
	# Sync volume to AudioManager
	if has_node("/root/AudioManager"):
		var am = get_node("/root/AudioManager")
		am.set_master_volume(master_volume)
		if is_muted and not am.is_muted:
			am.toggle_mute()

func load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_FILE_PATH)
	if err != OK:
		# First launch or no file: use defaults
		return
	
	mouse_sensitivity = config.get_value("controls", "mouse_sensitivity", 1.0)
	joypad_sensitivity = config.get_value("controls", "joypad_sensitivity", 1.0)
	invert_y = config.get_value("controls", "invert_y", false)
	
	base_fov = config.get_value("video", "base_fov", 85.0)
	display_mode = config.get_value("video", "display_mode", 0)
	
	master_volume = config.get_value("audio", "master_volume", 0.8)
	is_muted = config.get_value("audio", "is_muted", false)

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("controls", "joypad_sensitivity", joypad_sensitivity)
	config.set_value("controls", "invert_y", invert_y)
	
	config.set_value("video", "base_fov", base_fov)
	config.set_value("video", "display_mode", display_mode)
	
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "is_muted", is_muted)
	
	config.save(SETTINGS_FILE_PATH)
	settings_changed.emit()

func set_mouse_sensitivity(val: float) -> void:
	mouse_sensitivity = clamp(val, 0.2, 3.0)
	sensitivity_changed.emit(mouse_sensitivity, joypad_sensitivity, invert_y)

func set_joypad_sensitivity(val: float) -> void:
	joypad_sensitivity = clamp(val, 0.2, 3.0)
	sensitivity_changed.emit(mouse_sensitivity, joypad_sensitivity, invert_y)

func set_invert_y(enabled: bool) -> void:
	invert_y = enabled
	sensitivity_changed.emit(mouse_sensitivity, joypad_sensitivity, invert_y)

func set_base_fov(val: float) -> void:
	base_fov = clamp(val, 70.0, 110.0)
	fov_changed.emit(base_fov)

func set_display_mode(mode: int) -> void:
	display_mode = mode
	apply_display_mode()

func apply_display_mode() -> void:
	match display_mode:
		0: # Windowed
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		1: # Borderless Fullscreen
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		2: # Exclusive Fullscreen
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
