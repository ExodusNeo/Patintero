extends Node
class_name PlayerSkills

# Component: Player skills and special abilities
# Sprint-Slide (Ctrl/B), Lateral Juke (Q/E), Patotot Spine Burst (Shift), and Stamina system
# godot-physics / physics-tuning / input-systems

const SLIDE_DURATION: float = 0.65
const SLIDE_INITIAL_SPEED: float = 11.2
const SLIDE_STAMINA_COST: float = 20.0
const SLIDE_COOLDOWN_TIME: float = 1.3

const JUKE_COOLDOWN_TIME: float = 1.3
const JUKE_STAMINA_COST: float = 15.0
const JUKE_IMPULSE: float = 6.2

const SPINE_BURST_DURATION: float = 2.0
const SPINE_BURST_COOLDOWN_TIME: float = 6.0
const SPINE_BURST_SPEED: float = 9.8

var player: CharacterBody3D
var collision_shape: CollisionShape3D
var mesh_body: MeshInstance3D
var camera_comp: Node

# States (mirrored on player for HUD / external systems)
var stamina: float = 100.0
var is_sliding: bool = false
var slide_timer: float = 0.0
var slide_cooldown: float = 0.0
var slide_direction: Vector3 = Vector3.ZERO

var juke_cooldown: float = 0.0

var spine_burst_timer: float = 0.0
var spine_burst_cooldown: float = 0.0

func setup(p: CharacterBody3D, col: CollisionShape3D, mesh: MeshInstance3D, cam: Node) -> void:
	player = p
	collision_shape = col
	mesh_body = mesh
	camera_comp = cam

func update_skills(delta: float) -> void:
	if slide_cooldown > 0.0:
		slide_cooldown -= delta
	if juke_cooldown > 0.0:
		juke_cooldown -= delta
	if spine_burst_cooldown > 0.0:
		spine_burst_cooldown -= delta
	
	_update_stamina(delta)
	
	if is_sliding:
		_process_slide(delta)

func _update_stamina(delta: float) -> void:
	if player.role != NetworkManager.Role.RUNNER:
		return
	
	if player.is_sprinting:
		stamina = max(stamina - 25.0 * delta, 0.0)
	elif not is_sliding:
		stamina = min(stamina + 15.0 * delta, 100.0)

func try_start_slide(direction: Vector3) -> bool:
	var moving_fast: bool = player.velocity.length() > 4.5 or player.is_sprinting
	if not is_sliding and player.is_on_floor() and slide_cooldown <= 0.0 and stamina >= SLIDE_STAMINA_COST:
		if moving_fast and Input.is_action_just_pressed("crouch"):
			_start_slide(direction)
			return true
	return false

func _start_slide(dir: Vector3) -> void:
	is_sliding = true
	player.is_sliding = true
	slide_timer = SLIDE_DURATION
	slide_cooldown = SLIDE_COOLDOWN_TIME
	stamina = max(stamina - SLIDE_STAMINA_COST, 0.0)
	slide_direction = dir if dir != Vector3.ZERO else -player.transform.basis.z
	
	_apply_slide_collision(true)
	AudioManager.play_slide_skid()
	AudioManager.play_juke_whoosh()

func _process_slide(delta: float) -> void:
	slide_timer -= delta
	var progress: float = 1.0 - clamp(slide_timer / SLIDE_DURATION, 0.0, 1.0)
	var cur_speed: float = lerp(SLIDE_INITIAL_SPEED, 3.2, ease(progress, 2.0))
	player.velocity.x = slide_direction.x * cur_speed
	player.velocity.z = slide_direction.z * cur_speed
	
	if slide_timer <= 0.0 or not player.is_on_floor() or Input.is_action_just_pressed("jump"):
		stop_slide()

func stop_slide() -> void:
	is_sliding = false
	player.is_sliding = false
	_apply_slide_collision(false)

func _apply_slide_collision(active: bool) -> void:
	var capsule: CapsuleShape3D = collision_shape.shape as CapsuleShape3D
	if active:
		if capsule:
			capsule.height = 0.9
		collision_shape.position.y = -0.45
		mesh_body.scale.y = 0.5
		mesh_body.position.y = -0.45
	else:
		if capsule:
			capsule.height = 1.8
		collision_shape.position.y = 0.0
		mesh_body.scale.y = 1.0
		mesh_body.position.y = 0.0

func try_juke() -> void:
	if is_sliding or juke_cooldown > 0.0 or stamina < JUKE_STAMINA_COST:
		return
	
	if Input.is_action_just_pressed("juke_left"):
		_perform_juke(-1.0)
	elif Input.is_action_just_pressed("juke_right"):
		_perform_juke(1.0)

func _perform_juke(dir_lateral: float) -> void:
	juke_cooldown = JUKE_COOLDOWN_TIME
	stamina = max(stamina - JUKE_STAMINA_COST, 0.0)
	var lateral_dir: Vector3 = (player.transform.basis * Vector3(dir_lateral, 0, 0)).normalized()
	player.velocity += lateral_dir * JUKE_IMPULSE
	camera_comp.apply_juke_tilt(dir_lateral)
	AudioManager.play_juke_whoosh()
	_notify_guards_of_juke(dir_lateral)

func _notify_guards_of_juke(dir_lateral: float) -> void:
	var feinted_count: int = 0
	var all_players: Array[Node] = player.get_tree().get_nodes_in_group("players")
	for p in all_players:
		if p != player and "role" in p and p.role != NetworkManager.Role.RUNNER:
			var d: float = player.global_position.distance_to(p.global_position)
			var dz: float = abs(player.global_position.z - p.global_position.z)
			if d < 4.8 and dz < 3.6:
				if p.has_method("on_feinted_by_runner"):
					p.on_feinted_by_runner(dir_lateral, player)
					feinted_count += 1
	if feinted_count > 0:
		GameManager.add_runner_points(1, "ANKLE BREAKER: Baited defender! (+1 Runner)")
		GameManager.show_combat_banner("⚡ ANKLE BREAKER! DEFENDER BITES FAKE! (+1 PT)", Color(1.0, 0.85, 0.2))

func try_spine_burst() -> void:
	if Input.is_action_pressed("sprint") and spine_burst_cooldown <= 0.0 and spine_burst_timer <= 0.0:
		spine_burst_timer = SPINE_BURST_DURATION
		AudioManager.play_juke_whoosh()

func update_spine_burst(delta: float) -> float:
	if spine_burst_timer > 0.0:
		spine_burst_timer -= delta
		if spine_burst_timer <= 0.0:
			spine_burst_cooldown = SPINE_BURST_COOLDOWN_TIME
		return SPINE_BURST_SPEED
	return 0.0
