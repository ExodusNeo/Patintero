extends Node
class_name PlayerTagger

# Component: Combat, Tag Shapecasting, Charged Sweep, and Whiff Penalties
# Drives TsinelasViewmodel animations and TagHitEffect contact juice
# godot-physics / audio-design / input-systems

const MAX_TAG_CHARGE: float = 0.55
const TAG_RECOVERY_STUN_TIME: float = 0.75
const TAG_HIT_EFFECT := preload("res://src/vfx/combat/tag_hit_effect.tscn")

var player: CharacterBody3D
var head: Node3D
var tag_cast: ShapeCast3D
var viewmodel: TsinelasViewmodel

var is_tagging: bool = false
var tag_cooldown: float = 0.0
var is_charging_tag: bool = false
var tag_charge_time: float = 0.0
var tag_recovery_stun: float = 0.0

func setup(p: CharacterBody3D, h: Node3D, tc: ShapeCast3D, vm: Node3D) -> void:
	player = p
	head = h
	tag_cast = tc
	viewmodel = vm as TsinelasViewmodel

func _has_authority() -> bool:
	if not is_instance_valid(player):
		return false
	return player.is_multiplayer_authority() if multiplayer.has_multiplayer_peer() else true

func update_tagger(delta: float) -> void:
	if tag_recovery_stun > 0.0:
		tag_recovery_stun -= delta
	if tag_cooldown > 0.0:
		tag_cooldown -= delta
	
	if viewmodel and _has_authority():
		viewmodel.update_viewmodel(
			delta,
			player.velocity,
			player.is_sprinting,
			player.is_sliding,
			is_charging_tag,
			tag_charge_time / MAX_TAG_CHARGE,
			tag_recovery_stun
		)
	
	if player.role != NetworkManager.Role.RUNNER:
		_process_tag_input(delta)

func _process_tag_input(delta: float) -> void:
	if not _has_authority():
		return
	
	if tag_recovery_stun > 0.0 or is_tagging or tag_cooldown > 0.0:
		is_charging_tag = false
		tag_charge_time = 0.0
		return
	
	var tag_held: bool = Input.is_action_pressed("tag") or Input.is_action_pressed("tag_key")
	var tag_just_released: bool = Input.is_action_just_released("tag") or Input.is_action_just_released("tag_key")
	
	if tag_held:
		is_charging_tag = true
		tag_charge_time = min(tag_charge_time + delta, MAX_TAG_CHARGE)
	elif is_charging_tag and tag_just_released:
		var was_charged: bool = tag_charge_time >= (MAX_TAG_CHARGE * 0.75)
		is_charging_tag = false
		tag_charge_time = 0.0
		_execute_tag(was_charged)

func _execute_tag(is_charged: bool) -> void:
	is_tagging = true
	var sphere: SphereShape3D = tag_cast.shape as SphereShape3D
	
	if is_charged:
		AudioManager.play_charged_swing()
		if sphere:
			sphere.radius = 0.65
		tag_cast.target_position = Vector3(0, 0, -1.85)
		if viewmodel:
			viewmodel.play_charged_sweep()
		_animate_head_lunge(0.18, -0.22)
	else:
		AudioManager.play_juke_whoosh()
		if sphere:
			sphere.radius = 0.38
		tag_cast.target_position = Vector3(0, 0, -1.35)
		if viewmodel:
			viewmodel.play_quick_slap()
		_animate_head_lunge(0.11, -0.15)
	
	tag_cast.force_shapecast_update()
	var hit_runner: bool = false
	if tag_cast.is_colliding():
		for i in range(tag_cast.get_collision_count()):
			var collider: Object = tag_cast.get_collider(i)
			if collider != player and "role" in collider and collider.role == NetworkManager.Role.RUNNER:
				var runner_falling: bool = collider.is_tagged_falling if "is_tagged_falling" in collider else false
				if runner_falling:
					continue
				
				var runner_sliding: bool = collider.is_sliding if "is_sliding" in collider else false
				if runner_sliding and not is_charged and head.rotation.x > deg_to_rad(-12.0):
					# Evaded! Low slide slipped underneath high standing tag
					GameManager.add_runner_points(1, "AGILITY DODGE: Slid under tag! (+1 Runner)")
					GameManager.show_combat_banner("🏃 SLID UNDER TAG! (+1 AGILITY)", Color(0.3, 1.0, 0.5))
					AudioManager.play_juke_whoosh()
					continue
				
				# Spawn crunchy impact hit effect!
				if collider is Node3D:
					var hit_vfx := TAG_HIT_EFFECT.instantiate()
					player.get_tree().root.add_child(hit_vfx)
					hit_vfx.global_position = collider.global_position + Vector3(0, 0.8, 0)
				
				var target_name: String = collider.player_name if "player_name" in collider else collider.bot_name if "bot_name" in collider else "Runner"
				NetworkManager.trigger_tag(collider.peer_id if "peer_id" in collider else 0, player.peer_id, target_name, player.player_name)
				hit_runner = true
				break
	
	tag_cooldown = 0.5 if hit_runner else (0.9 if is_charged else 0.4)
	if not hit_runner and is_charged:
		tag_recovery_stun = TAG_RECOVERY_STUN_TIME
	
	if sphere:
		sphere.radius = 0.38
	tag_cast.target_position = Vector3(0, 0, -1.35)
	
	get_tree().create_timer(0.25).timeout.connect(func(): is_tagging = false)

func _animate_head_lunge(duration: float, z_depth: float) -> void:
	var tw := create_tween()
	tw.tween_property(head, "position:z", z_depth, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(head, "position:z", 0.0, duration + 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
