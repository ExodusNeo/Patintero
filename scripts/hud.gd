extends CanvasLayer

@onready var role_label: Label = %RoleLabel
@onready var objective_label: Label = %ObjectiveLabel
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var notification_label: Label = %NotificationLabel
@onready var patotot_indicator: Label = %PatototIndicator
@onready var zone_label: Label = %ZoneLabel
@onready var flash_overlay: ColorRect = %FlashOverlay
@onready var mute_btn: Button = %MuteButton
@onready var volume_slider: HSlider = %VolumeSlider
@onready var volume_label: Label = %VolumeLabel
@onready var vu_meter: ProgressBar = %VUMeter

var local_player: CharacterBody3D = null
var current_box_num: int = 0
var has_turned_around: bool = false

func _ready() -> void:
	NetworkManager.player_tagged.connect(_on_player_tagged)
	NetworkManager.player_foul.connect(_on_player_foul)
	_setup_role_ui()
	_setup_volume_ui()
	
	# Connect to Court signals if court exists in tree
	await get_tree().process_frame
	var court := get_tree().root.find_child("Court", true, false)
	if court:
		court.runner_entered_box.connect(_on_runner_box)
		court.runner_reached_back.connect(_on_runner_reached_back)
		court.runner_scored_home.connect(_on_runner_scored_home)

func set_local_player(player: CharacterBody3D) -> void:
	local_player = player
	_setup_role_ui()

func _setup_role_ui() -> void:
	var role: NetworkManager.Role = NetworkManager.local_role
	role_label.text = NetworkManager.get_role_name(role).to_upper()
	zone_label.text = "ZONE: ENTRANCE"
	
	match role:
		NetworkManager.Role.RUNNER:
			role_label.modulate = Color(0.3, 1.0, 0.4)
			objective_label.text = "Sprint through all 6 boxes to back line, then return home! [Shift] Sprint, [Q/E] Lean."
			stamina_bar.visible = true
			patotot_indicator.visible = false
		NetworkManager.Role.PATOTOT:
			role_label.modulate = Color(1.0, 0.85, 0.2)
			objective_label.text = "Guard Front Line. Press [E] or [Tab] near center to enter the CENTER SPINE rail! [L-Click/F] Tag!"
			stamina_bar.visible = false
			patotot_indicator.visible = true
		_:
			role_label.modulate = Color(1.0, 0.3, 0.3)
			objective_label.text = "Slide along chalk line with [A/D]. Aim crosshair and [Left Click / F] to TAG runners! [Q/E] Lean."
			stamina_bar.visible = false
			patotot_indicator.visible = false

func _setup_volume_ui() -> void:
	volume_slider.value = AudioManager.master_volume * 100.0
	volume_label.text = "%d%%" % int(volume_slider.value)
	volume_slider.value_changed.connect(_on_volume_slider_changed)
	mute_btn.pressed.connect(_on_mute_btn_pressed)
	AudioManager.volume_changed.connect(_on_audio_volume_changed)

func _on_volume_slider_changed(val: float) -> void:
	AudioManager.set_master_volume(val / 100.0)
	volume_label.text = "%d%%" % int(val)

func _on_mute_btn_pressed() -> void:
	var muted := AudioManager.toggle_mute()
	mute_btn.text = "🔇" if muted else "🔊"

func _on_audio_volume_changed(linear_val: float, is_muted: bool) -> void:
	volume_slider.value = linear_val * 100.0
	volume_label.text = "%d%%" % int(linear_val * 100.0)
	mute_btn.text = "🔇" if is_muted else "🔊"

func _process(delta: float) -> void:
	# Live Audio VU Meter updating smoothly
	var peak := AudioManager.get_peak_volume()
	vu_meter.value = lerp(vu_meter.value, peak * 100.0, 18.0 * delta)
	
	if is_instance_valid(local_player):
		if "role" in local_player and local_player.role == NetworkManager.Role.RUNNER:
			stamina_bar.value = local_player.stamina
			_update_runner_zone_text()
		elif "role" in local_player and local_player.role == NetworkManager.Role.PATOTOT:
			if local_player.is_patotot_on_spine:
				patotot_indicator.text = "CURRENT AXIS: [CENTER SPINE (Z)] - Press [E] to return to Front Line"
				patotot_indicator.modulate = Color(1.0, 0.4, 0.2)
			else:
				patotot_indicator.text = "CURRENT AXIS: [FRONT LINE (X)] - Press [E] near center to switch to Spine"
				patotot_indicator.modulate = Color(1.0, 0.85, 0.2)

func _update_runner_zone_text() -> void:
	var z := local_player.global_position.z
	if z < 0.0:
		zone_label.text = "ZONE: ENTRANCE (SAFE)"
		zone_label.modulate = Color(0.4, 0.9, 1.0)
	elif z > 12.0:
		zone_label.text = "ZONE: BACK LINE (HALFWAY REACHED!)"
		zone_label.modulate = Color(1.0, 0.85, 0.2)
	elif current_box_num > 0:
		zone_label.text = "ZONE: BOX %d (%s)" % [current_box_num, "RETURN LEG" if has_turned_around else "ADVANCING"]
		zone_label.modulate = Color(0.9, 0.9, 0.9)

func _on_runner_box(runner_id: int, box_id: int) -> void:
	if is_instance_valid(local_player) and local_player.peer_id == runner_id:
		current_box_num = box_id

func _on_runner_reached_back(runner_id: int) -> void:
	if is_instance_valid(local_player) and local_player.peer_id == runner_id:
		has_turned_around = true
		AudioManager.play_whistle(false)
		_flash_screen(Color(1.0, 0.85, 0.2, 0.35))
		_show_notification("★ REACHED THE BACK! NOW RETURN HOME TO SCORE! ★", Color(1.0, 0.85, 0.2))

func _on_runner_scored_home(runner_id: int) -> void:
	if is_instance_valid(local_player) and local_player.peer_id == runner_id:
		has_turned_around = false
		AudioManager.play_home_run()
		_flash_screen(Color(0.2, 1.0, 0.4, 0.4))
		_show_notification("🎉 HOME RUN! PUNTOS! (+1 POINT) 🎉", Color(0.3, 1.0, 0.4))

func _on_player_tagged(runner_name: String, tagger_name: String) -> void:
	_flash_screen(Color(1.0, 0.1, 0.1, 0.45))
	_show_notification("TAYA! %s tagged %s! TURNOVER!" % [tagger_name, runner_name], Color(1.0, 0.25, 0.25))

func _on_player_foul(player_name: String, reason: String) -> void:
	AudioManager.play_foul()
	_flash_screen(Color(1.0, 0.5, 0.1, 0.3))
	_show_notification("FOUL! %s: %s" % [player_name, reason], Color(1.0, 0.6, 0.1))

func _flash_screen(color: Color) -> void:
	flash_overlay.color = color
	flash_overlay.visible = true
	var tween := create_tween()
	tween.tween_property(flash_overlay, "color:a", 0.0, 0.45)
	await tween.finished
	flash_overlay.visible = false

func _show_notification(msg: String, color: Color) -> void:
	notification_label.text = msg
	notification_label.modulate = color
	notification_label.visible = true
	var tween := create_tween()
	notification_label.scale = Vector2(1.25, 1.25)
	tween.tween_property(notification_label, "scale", Vector2.ONE, 0.2)
	tween.tween_interval(3.0)
	tween.tween_property(notification_label, "modulate:a", 0.0, 0.5)
	await tween.finished
	notification_label.visible = false
	notification_label.modulate.a = 1.0
