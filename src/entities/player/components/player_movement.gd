extends Node
class_name PlayerMovement

# Component: Player locomotion and physics execution
# Free 3D Agility for Runners, 1D locked sliding for Line Guards, and Dual-Axis rails for Patotot
# godot-physics / physics-tuning

const WALK_SPEED: float = 5.2
const SPRINT_SPEED: float = 8.6
const CROUCH_SPEED: float = 2.8
const JUMP_VELOCITY: float = 5.2
const GUARD_SLIDE_SPEED: float = 5.6
const GRAVITY: float = 15.0
const COURT_HALF_WIDTH: float = 5.3

const LINE_Z_POSITIONS: Dictionary = {
	NetworkManager.Role.PATOTOT: 0.0,
	NetworkManager.Role.LINE_GUARD_1: 5.0,
	NetworkManager.Role.LINE_GUARD_2: 10.0,
	NetworkManager.Role.LINE_GUARD_BACK: 15.0
}

var player: CharacterBody3D
var skills_comp: Node

var is_sprinting: bool = false
var is_crouching: bool = false

func setup(p: CharacterBody3D, skills: Node) -> void:
	player = p
	skills_comp = skills

func _has_authority() -> bool:
	if not is_instance_valid(player):
		return false
	return player.is_multiplayer_authority() if multiplayer.has_multiplayer_peer() else true

func process_movement(delta: float) -> void:
	if not _has_authority():
		return
	if player.is_tagged_falling:
		return
	
	match player.role:
		NetworkManager.Role.RUNNER:
			_physics_runner(delta)
		NetworkManager.Role.PATOTOT:
			_physics_patotot(delta)
		_:
			_physics_line_guard(delta)
	
	player.move_and_slide()

# --- RUNNER MOVEMENT (Free 3D Agility) ---
func _physics_runner(delta: float) -> void:
	if not player.is_on_floor():
		player.velocity.y -= GRAVITY * delta
	
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (player.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	is_sprinting = Input.is_action_pressed("sprint") and skills_comp.stamina > 0.0 and input_dir.y < 0
	is_crouching = Input.is_action_pressed("crouch")
	player.is_sprinting = is_sprinting
	player.is_crouching = is_crouching
	
	if Input.is_action_just_pressed("jump") and player.is_on_floor() and not skills_comp.is_sliding:
		player.velocity.y = JUMP_VELOCITY
	
	if skills_comp.try_start_slide(direction):
		return
	if skills_comp.is_sliding:
		return
	
	skills_comp.try_juke()
	
	var speed: float = WALK_SPEED
	if is_crouching:
		speed = CROUCH_SPEED
	elif is_sprinting:
		speed = SPRINT_SPEED
	
	if direction != Vector3.ZERO:
		player.velocity.x = direction.x * speed
		player.velocity.z = direction.z * speed
	else:
		player.velocity.x = move_toward(player.velocity.x, 0, speed)
		player.velocity.z = move_toward(player.velocity.z, 0, speed)

# --- LINE GUARD MOVEMENT (Horizontal line slide) ---
func _physics_line_guard(delta: float) -> void:
	if player.tag_recovery_stun > 0.0:
		player.velocity.x = 0.0
		player.velocity.y = 0.0
		return
	
	var target_z: float = LINE_Z_POSITIONS.get(player.role, 0.0)
	player.global_position.z = move_toward(player.global_position.z, target_z, 0.1)
	player.velocity.z = 0.0
	
	if not player.is_on_floor():
		player.velocity.y -= GRAVITY * delta
	else:
		player.velocity.y = 0.0
	
	var slide_dir: float = _get_line_slide_direction(Vector3.RIGHT)
	player.velocity.x = slide_dir * GUARD_SLIDE_SPEED
	
	if (player.global_position.x <= -COURT_HALF_WIDTH and player.velocity.x < 0) or (player.global_position.x >= COURT_HALF_WIDTH and player.velocity.x > 0):
		player.velocity.x = 0.0

# --- PATOTOT MOVEMENT (Front Line X vs Center Spine Z) ---
func _physics_patotot(delta: float) -> void:
	if player.tag_recovery_stun > 0.0:
		player.velocity.x = 0.0
		player.velocity.z = 0.0
		return
	
	if not player.is_on_floor():
		player.velocity.y -= GRAVITY * delta
	else:
		player.velocity.y = 0.0
	
	var cur_speed: float = GUARD_SLIDE_SPEED
	
	if player.is_patotot_on_spine:
		skills_comp.try_spine_burst()
		var burst_speed: float = skills_comp.update_spine_burst(delta)
		if burst_speed > 0.0:
			cur_speed = burst_speed
		
		# Locked to Center Spine (X = 0, Z = 0 to 15)
		player.global_position.x = move_toward(player.global_position.x, 0.0, 0.2)
		player.velocity.x = 0.0
		
		var slide_dir: float = _get_line_slide_direction(Vector3.BACK)
		player.velocity.z = slide_dir * cur_speed
		
		if (player.global_position.z <= 0.0 and player.velocity.z < 0) or (player.global_position.z >= 15.0 and player.velocity.z > 0):
			player.velocity.z = 0.0
	else:
		# Locked to Front Line (Z = 0, X = -5.3 to +5.3)
		player.global_position.z = move_toward(player.global_position.z, 0.0, 0.2)
		player.velocity.z = 0.0
		
		var slide_dir: float = _get_line_slide_direction(Vector3.RIGHT)
		player.velocity.x = slide_dir * GUARD_SLIDE_SPEED
		
		if (player.global_position.x <= -COURT_HALF_WIDTH and player.velocity.x < 0) or (player.global_position.x >= COURT_HALF_WIDTH and player.velocity.x > 0):
			player.velocity.x = 0.0

func _get_line_slide_direction(line_forward: Vector3) -> float:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	if input_dir == Vector2.ZERO:
		return 0.0
	var wish_dir := (player.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	return wish_dir.dot(line_forward)

func toggle_patotot_axis() -> void:
	if not player.is_patotot_on_spine:
		if abs(player.global_position.x) <= 2.0:
			player.is_patotot_on_spine = true
			player.global_position.x = 0.0
	else:
		if player.global_position.z <= 2.5:
			player.is_patotot_on_spine = false
			player.global_position.z = 0.0
