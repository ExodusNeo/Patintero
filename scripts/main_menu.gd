extends Control

@onready var name_input: LineEdit = %NameInput
@onready var role_dropdown: OptionButton = %RoleDropdown
@onready var ip_input: LineEdit = %IPInput
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var solo_button: Button = %SoloButton
@onready var start_match_button: Button = %StartMatchButton
@onready var status_label: Label = %StatusLabel
@onready var player_list_label: Label = %PlayerListLabel
@onready var lobby_panel: PanelContainer = %LobbyPanel
@onready var mute_btn: Button = %MuteButton
@onready var volume_slider: HSlider = %VolumeSlider
@onready var volume_label: Label = %VolumeLabel
@onready var vu_meter: ProgressBar = %VUMeter

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_populate_roles()
	_setup_volume_ui()
	
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	solo_button.pressed.connect(_on_solo_pressed)
	start_match_button.pressed.connect(_on_start_match_pressed)
	
	NetworkManager.players_updated.connect(_update_lobby_ui)
	lobby_panel.visible = false

func _setup_volume_ui() -> void:
	volume_slider.value = AudioManager.master_volume * 100.0
	volume_label.text = "%d%%" % int(volume_slider.value)
	volume_slider.value_changed.connect(_on_volume_slider_changed)
	mute_btn.pressed.connect(_on_mute_pressed)
	AudioManager.volume_changed.connect(_on_audio_volume_changed)

func _on_volume_slider_changed(val: float) -> void:
	AudioManager.set_master_volume(val / 100.0)
	volume_label.text = "%d%%" % int(val)

func _on_mute_pressed() -> void:
	var muted := AudioManager.toggle_mute()
	mute_btn.text = "🔇" if muted else "🔊"

func _on_audio_volume_changed(linear_val: float, is_muted: bool) -> void:
	volume_slider.value = linear_val * 100.0
	volume_label.text = "%d%%" % int(linear_val * 100.0)
	mute_btn.text = "🔇" if is_muted else "🔊"

func _process(delta: float) -> void:
	var peak := AudioManager.get_peak_volume()
	vu_meter.value = lerp(vu_meter.value, peak * 100.0, 18.0 * delta)

func _populate_roles() -> void:
	role_dropdown.clear()
	role_dropdown.add_item("Runner (Tawid) - Free 3D Agility", NetworkManager.Role.RUNNER)
	role_dropdown.add_item("Patotot (Captain) - Front Line + Center Spine", NetworkManager.Role.PATOTOT)
	role_dropdown.add_item("Line Guard 1 - Mid Line 2", NetworkManager.Role.LINE_GUARD_1)
	role_dropdown.add_item("Line Guard 2 - Mid Line 3", NetworkManager.Role.LINE_GUARD_2)
	role_dropdown.add_item("Back Guard - Line 4", NetworkManager.Role.LINE_GUARD_BACK)

func _get_player_name() -> String:
	var n := name_input.text.strip_edges()
	return n if n != "" else "Player"

func _get_selected_role() -> NetworkManager.Role:
	return role_dropdown.get_selected_id() as NetworkManager.Role

func _on_solo_pressed() -> void:
	var role := _get_selected_role()
	var pname := _get_player_name()
	NetworkManager.start_solo_test(role, pname)

func _on_host_pressed() -> void:
	var role := _get_selected_role()
	var pname := _get_player_name()
	var err := NetworkManager.host_game(pname, role)
	if err == OK:
		status_label.text = "Hosting server on port %d. Waiting for players..." % NetworkManager.DEFAULT_PORT
		status_label.modulate = Color(0.3, 1.0, 0.4)
		lobby_panel.visible = true
		start_match_button.visible = true
		host_button.disabled = true
		join_button.disabled = true
		solo_button.disabled = true
	else:
		status_label.text = "Failed to host: %s" % str(err)
		status_label.modulate = Color(1.0, 0.3, 0.3)

func _on_join_pressed() -> void:
	var role := _get_selected_role()
	var pname := _get_player_name()
	var ip := ip_input.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	
	var err := NetworkManager.join_game(ip, pname, role)
	if err == OK:
		status_label.text = "Connecting to %s..." % ip
		status_label.modulate = Color(1.0, 0.85, 0.2)
		lobby_panel.visible = true
		start_match_button.visible = false
		host_button.disabled = true
		join_button.disabled = true
		solo_button.disabled = true
	else:
		status_label.text = "Failed to connect: %s" % str(err)
		status_label.modulate = Color(1.0, 0.3, 0.3)

func _on_start_match_pressed() -> void:
	NetworkManager.start_multiplayer_match()

func _update_lobby_ui() -> void:
	var text := "CONNECTED PLAYERS (%d):\n" % NetworkManager.players.size()
	for id in NetworkManager.players.keys():
		var info: Dictionary = NetworkManager.players[id]
		var role_str: String = NetworkManager.get_role_name(info.get("role", NetworkManager.Role.RUNNER))
		text += "• %s - %s (ID: %d)\n" % [info.get("name", "Player"), role_str, id]
	player_list_label.text = text
