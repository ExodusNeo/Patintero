extends Node3D
class_name TsinelasViewmodel

# First-Person Viewmodel: Authentic Filipino Tsinelas (Slipper) and Arm
# Handles idle breathing sway, quick slap, charged sweep, whiff stun droop,
# and runner hands locomotion bobbing.
# godot-animation / godot-3d-essentials

@onready var arm_root: Node3D = $ArmRoot
@onready var forearm: MeshInstance3D = $ArmRoot/Forearm
@onready var hand: MeshInstance3D = $ArmRoot/Hand
@onready var slipper: Node3D = $ArmRoot/Slipper
@onready var runner_left_hand: Node3D = $RunnerLeftHand
@onready var runner_right_hand: Node3D = $RunnerRightHand

const REST_POS := Vector3(0.28, -0.28, -0.42)
const REST_ROT := Vector3(-0.08, 0.12, -0.05)

var is_defender: bool = true
var idle_time: float = 0.0
var sway_offset := Vector3.ZERO
var is_animating_attack: bool = false
var charge_shake: float = 0.0

func _ready() -> void:
	arm_root.position = REST_POS
	arm_root.rotation = REST_ROT

func configure_role(role: NetworkManager.Role) -> void:
	is_defender = (role != NetworkManager.Role.RUNNER)
	arm_root.visible = is_defender
	runner_left_hand.visible = not is_defender
	runner_right_hand.visible = not is_defender

func update_viewmodel(delta: float, velocity: Vector3, is_sprinting: bool, is_sliding: bool, is_charging: bool, charge_progress: float, stun_time: float) -> void:
	if is_defender:
		_update_defender_viewmodel(delta, velocity, is_charging, charge_progress, stun_time)
	else:
		_update_runner_viewmodel(delta, velocity, is_sprinting, is_sliding)

func _update_defender_viewmodel(delta: float, vel: Vector3, is_charging: bool, charge_pct: float, stun_time: float) -> void:
	if is_animating_attack:
		return
	
	# Whiff stun: Arm droops limp
	if stun_time > 0.0:
		var droop_pos := REST_POS + Vector3(0.05, -0.22, 0.08)
		var droop_rot := REST_ROT + Vector3(0.35, -0.15, -0.25)
		arm_root.position = arm_root.position.lerp(droop_pos, 8.0 * delta)
		arm_root.rotation = arm_root.rotation.lerp(droop_rot, 8.0 * delta)
		return
	
	# Charging Tag Sweep: Arm winds back to the right and trembles
	if is_charging:
		charge_shake = charge_pct * 0.015
		var shake := Vector3(randf_range(-charge_shake, charge_shake), randf_range(-charge_shake, charge_shake), 0.0)
		var charge_pos := REST_POS + Vector3(0.18, 0.08, 0.12) + shake
		var charge_rot := REST_ROT + Vector3(-0.25, 0.55, 0.35)
		arm_root.position = arm_root.position.lerp(charge_pos, 10.0 * delta)
		arm_root.rotation = arm_root.rotation.lerp(charge_rot, 10.0 * delta)
		return
	
	# Normal Idle & Movement Bobbing
	idle_time += delta * (8.0 if vel.length() > 0.5 else 2.5)
	var bob_x := sin(idle_time * 0.5) * 0.015
	var bob_y := cos(idle_time) * 0.018
	var target_pos := REST_POS + Vector3(bob_x, bob_y, 0.0)
	var target_rot := REST_ROT + Vector3(bob_y * 0.5, bob_x * 0.5, 0.0)
	
	arm_root.position = arm_root.position.lerp(target_pos, 10.0 * delta)
	arm_root.rotation = arm_root.rotation.lerp(target_rot, 10.0 * delta)

func _update_runner_viewmodel(delta: float, vel: Vector3, is_sprinting: bool, is_sliding: bool) -> void:
	if is_sliding:
		# Duck hands down low into the slide
		var slide_left := Vector3(-0.35, -0.45, -0.35)
		var slide_right := Vector3(0.35, -0.45, -0.35)
		runner_left_hand.position = runner_left_hand.position.lerp(slide_left, 12.0 * delta)
		runner_right_hand.position = runner_right_hand.position.lerp(slide_right, 12.0 * delta)
		return
	
	var speed := vel.length()
	var freq := 14.0 if is_sprinting else (10.0 if speed > 1.0 else 3.0)
	idle_time += delta * freq
	
	var swing_amp := 0.07 if is_sprinting else (0.04 if speed > 1.0 else 0.012)
	var left_y := -0.32 + sin(idle_time) * swing_amp
	var right_y := -0.32 - sin(idle_time) * swing_amp
	var left_z := -0.42 + cos(idle_time) * swing_amp * 1.5
	var right_z := -0.42 - cos(idle_time) * swing_amp * 1.5
	
	runner_left_hand.position = runner_left_hand.position.lerp(Vector3(-0.28, left_y, left_z), 12.0 * delta)
	runner_right_hand.position = runner_right_hand.position.lerp(Vector3(0.28, right_y, right_z), 12.0 * delta)

func play_quick_slap() -> void:
	is_animating_attack = true
	var tw := create_tween()
	
	# Windup back
	tw.tween_property(arm_root, "position", REST_POS + Vector3(0.08, 0.12, 0.08), 0.06).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(arm_root, "rotation", REST_ROT + Vector3(-0.35, 0.25, 0.15), 0.06)
	
	# Forward snappy slap strike!
	tw.tween_property(arm_root, "position", Vector3(0.05, -0.08, -0.85), 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(arm_root, "rotation", Vector3(0.35, -0.22, -0.45), 0.09)
	
	# Return to rest
	tw.tween_property(arm_root, "position", REST_POS, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(arm_root, "rotation", REST_ROT, 0.14)
	
	await tw.finished
	is_animating_attack = false

func play_charged_sweep() -> void:
	is_animating_attack = true
	var tw := create_tween()
	
	# Deep coil right
	tw.tween_property(arm_root, "position", REST_POS + Vector3(0.22, 0.15, 0.15), 0.08)
	tw.parallel().tween_property(arm_root, "rotation", REST_ROT + Vector3(-0.4, 0.6, 0.4), 0.08)
	
	# Wide explosive horizontal sweep across from right to left!
	tw.tween_property(arm_root, "position", Vector3(-0.42, -0.12, -0.95), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(arm_root, "rotation", Vector3(0.25, -0.75, -0.65), 0.16)
	
	# Smooth return
	tw.tween_property(arm_root, "position", REST_POS, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(arm_root, "rotation", REST_ROT, 0.22)
	
	await tw.finished
	is_animating_attack = false

func play_stumble() -> void:
	is_animating_attack = true
	var tw := create_tween().set_parallel(true)
	if is_defender:
		tw.tween_property(arm_root, "position", REST_POS + Vector3(-0.06, 0.12, 0.1), 0.25).set_trans(Tween.TRANS_BACK)
		tw.tween_property(arm_root, "rotation", REST_ROT + Vector3(0.25, -0.2, 0.15), 0.25)
	else:
		tw.tween_property(runner_left_hand, "position", Vector3(-0.35, -0.15, -0.32), 0.25).set_trans(Tween.TRANS_BACK)
		tw.tween_property(runner_right_hand, "position", Vector3(0.38, -0.12, -0.30), 0.25).set_trans(Tween.TRANS_BACK)

func play_knockdown() -> void:
	is_animating_attack = true
	var tw := create_tween().set_parallel(true)
	if is_defender:
		tw.tween_property(arm_root, "position", REST_POS + Vector3(0.1, -0.38, 0.1), 0.42).set_trans(Tween.TRANS_BOUNCE)
		tw.tween_property(arm_root, "rotation", REST_ROT + Vector3(0.4, 0.1, -0.3), 0.42)
	else:
		tw.tween_property(runner_left_hand, "position", Vector3(-0.38, -0.58, -0.18), 0.42).set_trans(Tween.TRANS_BOUNCE)
		tw.tween_property(runner_right_hand, "position", Vector3(0.36, -0.58, -0.18), 0.42).set_trans(Tween.TRANS_BOUNCE)

func reset_from_knockdown_instant() -> void:
	if is_defender:
		arm_root.position = REST_POS
		arm_root.rotation = REST_ROT
	else:
		runner_left_hand.position = Vector3(-0.28, -0.32, -0.42)
		runner_right_hand.position = Vector3(0.28, -0.32, -0.42)
	is_animating_attack = false

