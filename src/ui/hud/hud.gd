extends CanvasLayer

# Phase 3: HUD with Live Match Scoreboard, Inning Clock & Palarong Pambansa Rules

@onready var role_label: Label = %RoleLabel
@onready var objective_label: Label = %ObjectiveLabel
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var notification_label: Label = %NotificationLabel
@onready var patotot_indicator: Label = %PatototIndicator
@onready var zone_label: Label = %ZoneLabel
@onready var flash_overlay: ColorRect = %FlashOverlay

# Volume Controls
@onready var mute_btn: Button = %MuteButton
@onready var volume_slider: HSlider = %VolumeSlider
@onready var volume_label: Label = %VolumeLabel
@onready var vu_meter: ProgressBar = %VUMeter

# Scoreboard & Timer
@onready var runners_score_label: Label = %RunnersScoreLabel
@onready var defenders_score_label: Label = %DefendersScoreLabel
@onready var timer_label: Label = %TimerLabel

# Match Summary Modal
@onready var match_summary_modal: PanelContainer = %MatchSummaryModal
@onready var summary_title: Label = %SummaryTitle
@onready var summary_score_label: Label = %SummaryScoreLabel
@onready var summary_detail_label: Label = %SummaryDetailLabel
@onready var summary_button: Button = %SummaryButton

@onready var stamina_warning_label: Label = %StaminaWarningLabel
@onready var ability1_label: Label = %Ability1Label
@onready var ability2_label: Label = %Ability2Label
@onready var dot: ColorRect = $Crosshair/Dot

var local_player: CharacterBody3D = null
var current_box_num: int = 0
var has_turned_around: bool = false
signal tagged_blackout_finished

func _ready() -> void:
	NetworkManager.player_tagged.connect(_on_player_tagged)
	NetworkManager.player_foul.connect(_on_player_foul)
	_setup_role_ui()
	_setup_volume_ui()
	_setup_scoreboard_ui()
	
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
			objective_label.text = "Sprint through 6 boxes to back line, then return home! [Shift] Sprint, [Ctrl/B] Slide, [Q/E] Juke."
			stamina_bar.visible = true
			patotot_indicator.visible = false
		NetworkManager.Role.PATOTOT:
			role_label.modulate = Color(1.0, 0.85, 0.2)
			objective_label.text = "Guard Front Line. [E] near center to switch to Center Spine! Hold [Shift] on spine for BURST! [L-Click/R2] Tag."
			stamina_bar.visible = false
			patotot_indicator.visible = true
		_:
			role_label.modulate = Color(1.0, 0.3, 0.3)
			objective_label.text = "Slide along line with [A/D]. Tap [L-Click/R2] Quick Tag, or Hold to CHARGE Wide Sweep! [Q/E] Lean."
			stamina_bar.visible = false
			patotot_indicator.visible = false

func _setup_volume_ui() -> void:
	volume_slider.value = AudioManager.master_volume * 100.0
	volume_label.text = "%d%%" % int(volume_slider.value)
	volume_slider.value_changed.connect(_on_volume_slider_changed)
	mute_btn.pressed.connect(_on_mute_btn_pressed)
	AudioManager.volume_changed.connect(_on_audio_volume_changed)

func _setup_scoreboard_ui() -> void:
	GameManager.score_updated.connect(_on_score_updated)
	GameManager.match_timer_updated.connect(_on_match_timer_updated)
	GameManager.point_event_triggered.connect(_on_point_event_triggered)
	GameManager.halftime_reached.connect(_on_halftime_reached)
	GameManager.match_completed.connect(_on_match_completed)
	GameManager.combat_banner_triggered.connect(func(txt: String, col: Color): _show_notification(txt, col))
	summary_button.pressed.connect(_on_summary_button_pressed)
	_on_score_updated(GameManager.runner_score, GameManager.defender_score)

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

func _on_score_updated(r_pts: int, d_pts: int) -> void:
	runners_score_label.text = "🏃 RUNNERS: %d" % r_pts
	defenders_score_label.text = "🛡 DEFENSE: %d" % d_pts

func _on_match_timer_updated(time_left: float) -> void:
	var mins: int = int(time_left / 60.0)
	var secs: int = int(time_left) % 60
	var round_tag := "R%d" % GameManager.current_round
	timer_label.text = "⏱ %02d:%02d [%s]" % [mins, secs, round_tag]
	if time_left <= 30.0:
		timer_label.modulate = Color(1.0, 0.3, 0.3) if fmod(time_left, 1.0) < 0.5 else Color(1.0, 0.85, 0.2)
	else:
		timer_label.modulate = Color(1.0, 0.9, 0.3)

func _on_point_event_triggered(team: String, _points: int, reason: String) -> void:
	var color := Color(0.3, 1.0, 0.4)
	if team == "DEFENDERS":
		color = Color(1.0, 0.35, 0.35)
	elif team == "ALERT":
		color = Color(1.0, 0.85, 0.2)
	_show_notification(reason, color)

func _on_halftime_reached(round_num: int) -> void:
	AudioManager.play_milestone()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	summary_title.text = "⏱ HALFTIME (ROUND %d FINISHED)" % round_num
	summary_score_label.text = "RUNNERS: %d pts  |  DEFENSE: %d pts" % [GameManager.runner_score, GameManager.defender_score]
	summary_detail_label.text = "Switch sides or prepare for Round 2!"
	summary_button.text = "Start Round 2 ▶"
	match_summary_modal.visible = true

func _on_match_completed(winner_team: String, r_score: int, d_score: int) -> void:
	AudioManager.play_game_over()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	summary_title.text = "🏆 MATCH OVER - %s WIN!" % winner_team
	summary_score_label.text = "FINAL SCORE:\nRUNNERS: %d pts  |  DEFENSE: %d pts" % [r_score, d_score]
	summary_detail_label.text = "Palarong Pambansa Championship Complete!"
	summary_button.text = "Play Again ↻"
	match_summary_modal.visible = true

func _on_summary_button_pressed() -> void:
	AudioManager.play_ui_click()
	match_summary_modal.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if GameManager.current_state == GameManager.MatchState.HALFTIME:
		GameManager.start_round(2)
	else:
		GameManager.start_match()

func _process(delta: float) -> void:
	# Live Audio VU Meter updating smoothly
	var peak := AudioManager.get_peak_volume()
	vu_meter.value = lerp(vu_meter.value, peak * 100.0, 18.0 * delta)
	
	if is_instance_valid(local_player):
		if "role" in local_player and local_player.role == NetworkManager.Role.RUNNER:
			_process_runner_hud()
		elif "role" in local_player and local_player.role == NetworkManager.Role.PATOTOT:
			_process_patotot_hud()
		else:
			_process_guard_hud()

func _process_runner_hud() -> void:
	stamina_bar.value = local_player.stamina
	_update_runner_zone_text()
	
	# Low Stamina Warning Pulse
	if local_player.stamina < 25.0:
		stamina_warning_label.visible = true
		stamina_warning_label.modulate.a = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		stamina_bar.modulate = Color(1.0, 0.35, 0.35)
	else:
		stamina_warning_label.visible = false
		stamina_bar.modulate = Color(1.0, 1.0, 1.0)
	
	# Slide status
	var slide_cost: float = local_player.get("SLIDE_STAMINA_COST") if local_player.get("SLIDE_STAMINA_COST") != null else 20.0
	if local_player.is_sliding:
		ability1_label.text = "⚡ SLIDING..."
		ability1_label.modulate = Color(0.3, 1.0, 0.5)
	elif local_player.slide_cooldown > 0.0:
		ability1_label.text = "⏳ SLIDE CD: %.1fs" % local_player.slide_cooldown
		ability1_label.modulate = Color(0.7, 0.7, 0.7)
	elif local_player.stamina < slide_cost:
		ability1_label.text = "❌ SLIDE: LOW STAMINA"
		ability1_label.modulate = Color(0.8, 0.4, 0.4)
	else:
		ability1_label.text = "✔ SLIDE [CTRL/B]: READY"
		ability1_label.modulate = Color(0.4, 1.0, 0.5)
	
	# Juke status
	var juke_cost: float = local_player.get("JUKE_STAMINA_COST") if local_player.get("JUKE_STAMINA_COST") != null else 15.0
	if local_player.juke_cooldown > 0.0:
		ability2_label.text = "⏳ JUKE CD: %.1fs" % local_player.juke_cooldown
		ability2_label.modulate = Color(0.7, 0.7, 0.7)
	elif local_player.stamina < juke_cost:
		ability2_label.text = "❌ JUKE: LOW STAMINA"
		ability2_label.modulate = Color(0.8, 0.4, 0.4)
	else:
		ability2_label.text = "✔ JUKE [Q/E | LB/RB]: READY"
		ability2_label.modulate = Color(0.4, 1.0, 0.5)

func _process_patotot_hud() -> void:
	stamina_warning_label.visible = false
	if local_player.is_patotot_on_spine:
		patotot_indicator.text = "CURRENT AXIS: [CENTER SPINE (Z)] - Press [E] to return to Front Line"
		patotot_indicator.modulate = Color(1.0, 0.4, 0.2)
		
		# Spine burst status
		if local_player.spine_burst_timer > 0.0:
			ability1_label.text = "⚡ BURST ACTIVE: %.1fs" % local_player.spine_burst_timer
			ability1_label.modulate = Color(1.0, 0.5, 0.1)
		elif local_player.spine_burst_cooldown > 0.0:
			ability1_label.text = "⏳ BURST CD: %.1fs" % local_player.spine_burst_cooldown
			ability1_label.modulate = Color(0.7, 0.7, 0.7)
		else:
			ability1_label.text = "✔ SPINE BURST [SHIFT/L3]: READY"
			ability1_label.modulate = Color(1.0, 0.85, 0.2)
	else:
		patotot_indicator.text = "CURRENT AXIS: [FRONT LINE (X)] - Press [E] near center to switch to Spine"
		patotot_indicator.modulate = Color(1.0, 0.85, 0.2)
		ability1_label.text = "LINE SLIDE: [A / D]"
		ability1_label.modulate = Color(0.85, 0.85, 0.85)
	
	_update_tag_hud_ability(ability2_label)

func _process_guard_hud() -> void:
	stamina_warning_label.visible = false
	_update_tag_hud_ability(ability1_label)
	ability2_label.text = "PEEK LEAN: [Q / E]"
	ability2_label.modulate = Color(0.7, 0.8, 1.0)

func _update_tag_hud_ability(target_label: Label) -> void:
	if local_player.tag_recovery_stun > 0.0:
		target_label.text = "⚠️ WHIFF STUNNED (%.1fs)" % local_player.tag_recovery_stun
		target_label.modulate = Color(1.0, 0.2, 0.2)
		dot.color = Color(1.0, 0.2, 0.2, 0.9)
	elif local_player.is_charging_tag:
		var max_charge: float = local_player.get("MAX_TAG_CHARGE") if local_player.get("MAX_TAG_CHARGE") != null else 0.55
		var pct: int = int(clamp(local_player.tag_charge_time / max_charge, 0.0, 1.0) * 100.0)
		target_label.text = "🔥 CHARGING SWEEP: %d%%" % pct
		target_label.modulate = Color(1.0, 0.5, 0.1)
		dot.color = Color(1.0, 0.5, 0.1, 1.0)
		dot.custom_minimum_size = Vector2(9, 9)
	else:
		target_label.text = "TAG [L-CLICK/R2]: TAP OR CHARGE"
		target_label.modulate = Color(0.9, 0.9, 0.9)
		dot.color = Color(1.0, 1.0, 1.0, 0.8)
		dot.custom_minimum_size = Vector2(5, 5)

func _update_runner_zone_text() -> void:
	var z := local_player.global_position.z
	if z < 0.0:
		zone_label.text = "ZONE: ENTRANCE (SAFE)"
		zone_label.modulate = Color(0.4, 0.9, 1.0)
	elif z > 15.0:
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

func _on_runner_scored_home(runner_id: int) -> void:
	if is_instance_valid(local_player) and local_player.peer_id == runner_id:
		has_turned_around = false
		AudioManager.play_home_run()
		_flash_screen(Color(0.2, 1.0, 0.4, 0.4))

func _on_player_tagged(runner_name: String, tagger_name: String) -> void:
	if is_instance_valid(local_player) and local_player.role == NetworkManager.Role.RUNNER:
		var lp_name: String = local_player.player_name if "player_name" in local_player else ""
		if lp_name == runner_name or runner_name.contains(lp_name) or lp_name.contains(runner_name) or runner_name == "Runner":
			_show_notification("💥 TAYA! Tagged by %s!" % tagger_name, Color(1.0, 0.25, 0.25))
		else:
			_show_notification("💥 %s was tagged by %s!" % [runner_name, tagger_name], Color(1.0, 0.4, 0.4))
	else:
		_flash_screen(Color(1.0, 0.1, 0.1, 0.45))
		_show_notification("🎯 TAGGED! %s was tagged by %s!" % [runner_name, tagger_name], Color(0.3, 1.0, 0.5))

func play_tagged_impact_flash() -> void:
	flash_overlay.color = Color(0.85, 0.12, 0.12, 0.55)
	flash_overlay.visible = true
	var tw := create_tween()
	tw.tween_property(flash_overlay, "color", Color(0.35, 0.05, 0.05, 0.20), 0.38).set_trans(Tween.TRANS_QUAD)

func fade_to_black(duration: float = 0.45) -> void:
	flash_overlay.visible = true
	var tw := create_tween()
	tw.tween_property(flash_overlay, "color", Color(0.01, 0.01, 0.02, 1.0), duration).set_trans(Tween.TRANS_QUAD)
	await tw.finished

func fade_from_black(duration: float = 0.60) -> void:
	var tw := create_tween()
	tw.tween_property(flash_overlay, "color:a", 0.0, duration).set_trans(Tween.TRANS_QUAD)
	await tw.finished
	flash_overlay.visible = false
	tagged_blackout_finished.emit()

func play_tagged_blackout() -> void:
	play_tagged_impact_flash()

func _on_player_foul(_player_name: String, _reason: String) -> void:
	AudioManager.play_foul()
	_flash_screen(Color(1.0, 0.5, 0.1, 0.3))

func _flash_screen(color: Color) -> void:
	flash_overlay.color = color
	flash_overlay.visible = true
	var tween := create_tween()
	tween.tween_property(flash_overlay, "color:a", 0.0, 0.45)
	await tween.finished
	flash_overlay.visible = false

func _show_notification(msg: String, color: Color) -> void:
	AudioManager.play_ui_notification()
	notification_label.text = msg
	notification_label.modulate = color
	notification_label.visible = true
	var tween := create_tween()
	notification_label.scale = Vector2(1.25, 1.25)
	tween.tween_property(notification_label, "scale", Vector2.ONE, 0.18)
	tween.tween_interval(2.5)
	tween.tween_property(notification_label, "modulate:a", 0.0, 0.4)
	await tween.finished
	notification_label.visible = false
	notification_label.modulate.a = 1.0
