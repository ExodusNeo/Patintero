extends Node
class_name BotTagger

# Component: Bot combat, tag shapecasting, slide evasion, and stumble state
# Spawns TagHitEffect on contact
# game-ai / godot-physics

const TAG_HIT_EFFECT := preload("res://src/vfx/combat/tag_hit_effect.tscn")

var bot: CharacterBody3D
var tag_cast: ShapeCast3D
var reach_hand: Node3D
var mesh_body: MeshInstance3D

var tag_cooldown: float = 0.0
var is_tagging: bool = false
var feint_override_timer: float = 0.0
var feint_override_dir: float = 0.0
var feint_stumble_timer: float = 0.0

func setup(b: CharacterBody3D, tc: ShapeCast3D, rh: Node3D, mb: MeshInstance3D) -> void:
	bot = b
	tag_cast = tc
	reach_hand = rh
	mesh_body = mb

func update_timers(delta: float) -> void:
	if tag_cooldown > 0.0:
		tag_cooldown -= delta
	if feint_override_timer > 0.0:
		feint_override_timer -= delta
	if feint_stumble_timer > 0.0:
		feint_stumble_timer -= delta

func is_stumbled() -> bool:
	return feint_override_timer > 0.0 or feint_stumble_timer > 0.0

func on_feinted_by_runner(juke_dir: float) -> void:
	if bot.role == NetworkManager.Role.RUNNER:
		return
	feint_override_timer = 0.55
	feint_override_dir = -juke_dir
	feint_stumble_timer = 0.45
	tag_cooldown = max(tag_cooldown, 0.9)
	AudioManager.play_slide_skid()
	
	var tween := create_tween()
	tween.tween_property(mesh_body, "rotation:z", deg_to_rad(-juke_dir * 18.0), 0.12)
	tween.tween_property(mesh_body, "rotation:z", 0.0, 0.25)

func attempt_tag(target_runner: Node3D) -> void:
	if tag_cooldown > 0.0 or is_tagging or feint_stumble_timer > 0.0:
		return
	
	tag_cooldown = 0.85
	is_tagging = true
	
	var tween := create_tween()
	reach_hand.visible = true
	reach_hand.position = Vector3(0.2, 0.4, -0.3)
	tween.tween_property(reach_hand, "position", Vector3(0.0, 0.5, -1.15), 0.13)
	tween.tween_property(reach_hand, "position", Vector3(0.2, 0.4, -0.3), 0.15)
	await tween.finished
	reach_hand.visible = false
	is_tagging = false
	
	var tagged := false
	tag_cast.target_position = Vector3(0, 0, -1.25)
	tag_cast.force_shapecast_update()
	if tag_cast.is_colliding():
		for i in range(tag_cast.get_collision_count()):
			var c := tag_cast.get_collider(i)
			if c != bot and "role" in c and c.role == NetworkManager.Role.RUNNER:
				var is_falling: bool = c.is_tagged_falling if "is_tagged_falling" in c else false
				if is_falling:
					continue
				
				var is_sliding: bool = c.is_sliding if "is_sliding" in c else false
				if is_sliding:
					tag_cooldown = 0.85
					AudioManager.play_juke_whoosh()
					GameManager.add_runner_points(1, "AGILITY DODGE: Slid under tag! (+1 Runner)")
					GameManager.show_combat_banner("🏃 SLID UNDER TAG! (+1 AGILITY)", Color(0.3, 1.0, 0.5))
					continue
				
				_spawn_hit_spark(c.global_position)
				var runner_name: String = c.player_name if "player_name" in c else c.bot_name if "bot_name" in c else "Runner"
				NetworkManager.trigger_tag(c.peer_id if "peer_id" in c else 0, bot.peer_id, runner_name, bot.player_name)
				tagged = true
				break
	
	if not tagged and target_runner and is_instance_valid(target_runner):
		var target_falling: bool = target_runner.is_tagged_falling if "is_tagged_falling" in target_runner else false
		if target_falling:
			return
		
		var target_sliding: bool = target_runner.is_sliding if "is_sliding" in target_runner else false
		if target_sliding:
			tag_cooldown = 0.85
			AudioManager.play_juke_whoosh()
			GameManager.add_runner_points(1, "AGILITY DODGE: Slid under tag! (+1 Runner)")
			GameManager.show_combat_banner("🏃 SLID UNDER TAG! (+1 AGILITY)", Color(0.3, 1.0, 0.5))
		elif bot.global_position.distance_to(target_runner.global_position) <= 1.35:
			_spawn_hit_spark(target_runner.global_position)
			var runner_name: String = target_runner.player_name if "player_name" in target_runner else target_runner.bot_name if "bot_name" in target_runner else "Runner"
			NetworkManager.trigger_tag(target_runner.peer_id if "peer_id" in target_runner else 0, bot.peer_id, runner_name, bot.player_name)

func _spawn_hit_spark(pos: Vector3) -> void:
	var fx: Node3D = TAG_HIT_EFFECT.instantiate()
	bot.get_tree().root.add_child(fx)
	fx.global_position = pos + Vector3(0, 0.8, 0)

func reset_tagger() -> void:
	tag_cooldown = 0.6
	is_tagging = false
	feint_override_timer = 0.0
	feint_override_dir = 0.0
	feint_stumble_timer = 0.0
	reach_hand.visible = false
	mesh_body.rotation.z = 0.0
