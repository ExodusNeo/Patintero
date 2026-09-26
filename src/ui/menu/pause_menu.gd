extends CanvasLayer

# In-Game Pause & Settings Menu
# godot-ui-control / input-systems / godot-audio

@onready var resume_btn: Button = %ResumeButton
@onready var quit_btn: Button = %QuitButton
@onready var mouse_sens_slider: HSlider = %MouseSensSlider
@onready var mouse_sens_val: Label = %MouseSensVal
@onready var joy_sens_slider: HSlider = %JoySensSlider
@onready var joy_sens_val: Label = %JoySensVal
@onready var invert_y_check: CheckBox = %InvertYCheck
@onready var fov_slider: HSlider = %FovSlider
@onready var fov_val: Label = %FovVal

@onready var volume_slider: HSlider = %VolumeSlider
@onready var volume_val: Label = %VolumeVal
@onready var mute_btn: Button = %MuteBtn
@onready var vu_meter: ProgressBar = %VuMeter
@onready var display_dropdown: OptionButton = %DisplayDropdown
@onready var controls_panel: PanelContainer = %ControlsPanel
@onready var toggle_controls_btn: Button = %ToggleControlsBtn

var is_paused: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	
	resume_btn.pressed.connect(resume_game)
	quit_btn.pressed.connect(_on_quit_pressed)
	toggle_controls_btn.pressed.connect(_toggle_controls_view)
	
	_setup_settings_ui()
	_load_current_values()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if is_paused:
			resume_game()
		else:
			pause_game()
		get_viewport().set_input_as_handled()

func open_as_dialog() -> void:
	visible = true
	is_paused = false
	quit_btn.visible = false
	resume_btn.text = "✔ SAVE & CLOSE"
	_load_current_values()
	resume_btn.grab_focus()

func pause_game() -> void:
	is_paused = true
	visible = true
	quit_btn.visible = true
	resume_btn.text = "▶ RESUME"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	if NetworkManager.is_solo_test:
		get_tree().paused = true
	
	_load_current_values()
	resume_btn.grab_focus()

func _get_settings() -> Node:
	return get_node_or_null("/root/SettingsManager") if is_inside_tree() else null

func resume_game() -> void:
	AudioManager.play_ui_click()
	is_paused = false
	visible = false
	controls_panel.visible = false
	var s: Node = _get_settings()
	if s and s.has_method("save_settings"):
		s.save_settings()
	
	if get_tree().current_scene and get_tree().current_scene.name == "World":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if NetworkManager.is_solo_test:
			get_tree().paused = false
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _setup_settings_ui() -> void:
	for slider in [mouse_sens_slider, joy_sens_slider]:
		slider.min_value = 0.2
		slider.max_value = 3.0
		slider.step = 0.05
	mouse_sens_slider.value_changed.connect(_on_mouse_sens_changed)
	joy_sens_slider.value_changed.connect(_on_joy_sens_changed)
	invert_y_check.toggled.connect(_on_invert_y_toggled)
	
	fov_slider.min_value = 70.0
	fov_slider.max_value = 110.0
	fov_slider.step = 1.0
	fov_slider.value_changed.connect(_on_fov_changed)
	
	volume_slider.min_value = 0.0
	volume_slider.max_value = 100.0
	volume_slider.step = 1.0
	volume_slider.value_changed.connect(_on_volume_changed)
	mute_btn.pressed.connect(_on_mute_pressed)
	
	display_dropdown.clear()
	display_dropdown.add_item("Windowed", 0)
	display_dropdown.add_item("Borderless Fullscreen", 1)
	display_dropdown.add_item("Exclusive Fullscreen", 2)
	display_dropdown.item_selected.connect(_on_display_selected)

func _load_current_values() -> void:
	var s: Node = _get_settings()
	var mouse_s: float = s.mouse_sensitivity if (s and "mouse_sensitivity" in s) else 1.0
	mouse_sens_slider.value = mouse_s
	mouse_sens_val.text = "%d%%" % int(mouse_s * 100.0)
	
	var joy_s: float = s.joypad_sensitivity if (s and "joypad_sensitivity" in s) else 1.0
	joy_sens_slider.value = joy_s
	joy_sens_val.text = "%d%%" % int(joy_s * 100.0)
	
	invert_y_check.button_pressed = s.invert_y if (s and "invert_y" in s) else false
	
	var base_fov: float = s.base_fov if (s and "base_fov" in s) else 85.0
	fov_slider.value = base_fov
	fov_val.text = "%d°" % int(base_fov)
	
	volume_slider.value = AudioManager.master_volume * 100.0
	volume_val.text = "%d%%" % int(volume_slider.value)
	mute_btn.text = "🔇" if AudioManager.is_muted else "🔊"
	display_dropdown.selected = s.display_mode if (s and "display_mode" in s) else 0

func _process(delta: float) -> void:
	if visible:
		var peak := AudioManager.get_peak_volume()
		vu_meter.value = lerp(vu_meter.value, peak * 100.0, 18.0 * delta)

func _on_mouse_sens_changed(val: float) -> void:
	var s: Node = _get_settings()
	if s and s.has_method("set_mouse_sensitivity"):
		s.set_mouse_sensitivity(val)
	mouse_sens_val.text = "%d%%" % int(val * 100.0)

func _on_joy_sens_changed(val: float) -> void:
	var s: Node = _get_settings()
	if s and s.has_method("set_joypad_sensitivity"):
		s.set_joypad_sensitivity(val)
	joy_sens_val.text = "%d%%" % int(val * 100.0)

func _on_invert_y_toggled(enabled: bool) -> void:
	var s: Node = _get_settings()
	if s and s.has_method("set_invert_y"):
		s.set_invert_y(enabled)

func _on_fov_changed(val: float) -> void:
	var s: Node = _get_settings()
	if s and s.has_method("set_base_fov"):
		s.set_base_fov(val)
	fov_val.text = "%d°" % int(val)

func _on_volume_changed(val: float) -> void:
	AudioManager.set_master_volume(val / 100.0)
	var s: Node = _get_settings()
	if s:
		s.master_volume = val / 100.0
	volume_val.text = "%d%%" % int(val)

func _on_mute_pressed() -> void:
	var muted := AudioManager.toggle_mute()
	var s: Node = _get_settings()
	if s:
		s.is_muted = muted
	mute_btn.text = "🔇" if muted else "🔊"

func _on_display_selected(index: int) -> void:
	var s: Node = _get_settings()
	if s and s.has_method("set_display_mode"):
		s.set_display_mode(index)

func _toggle_controls_view() -> void:
	AudioManager.play_ui_click()
	controls_panel.visible = not controls_panel.visible
	toggle_controls_btn.text = "📖 HIDE CONTROLS GUIDE" if controls_panel.visible else "📖 SHOW CONTROLS GUIDE"

func _on_quit_pressed() -> void:
	AudioManager.play_ui_click()
	resume_game()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	NetworkManager.is_solo_test = false
	NetworkManager.players.clear()
	get_tree().change_scene_to_file("res://src/ui/menu/main_menu.tscn")
