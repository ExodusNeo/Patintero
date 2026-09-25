extends CharacterBody3D
class_name PatinteroPlayer

# Node References
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var tag_cast: ShapeCast3D = $Head/TagCast
@onready var mesh_body: MeshInstance3D = $MeshInstance3D
@onready var name_label: Label3D = $NameLabel
@onready var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var reach_hand: Node3D = $Head/ReachHand

# Movement Tunables
const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.5
const CROUCH_SPEED := 2.8
const GUARD_SLIDE_SPEED := 7.0
const JUMP_VELOCITY := 4.5
const GRAVITY := 15.0
const MOUSE_SENSITIVITY := 0.0025

# Head Bobbing & Feel Tunables (godot-animation / 3d essentials)
const HEAD_BASE_Y := 0.65
const BOB_AMP := 0.04
var bob_time: float = 0.0

# Court Bounds & Line Positions
const COURT_HALF_WIDTH := 3.8 # X axis: -3.8 to +3.8
const LINE_Z_POSITIONS := {
	NetworkManager.Role.PATOTOT: 0.0,
	NetworkManager.Role.LINE_GUARD_1: 4.0,
	NetworkManager.Role.LINE_GUARD_2: 8.0,
	NetworkManager.Role.LINE_GUARD_BACK: 12.0
}

# Player State
@export var peer_id: int = 1
@export var player_name: String = "Player"
@export var role: NetworkManager.Role = NetworkManager.Role.RUNNER
@export var is_patotot_on_spine: bool = false
@export var stamina: float = 100.0
@export var is_crouching: bool = false

var is_tagging: bool = false
var tag_cooldown: float = 0.0

func _ready() -> void:
	# godot-physics: set up robust floor snapping and collision masks
	floor_snap_length = 0.2
	floor_constant_speed = true
	floor_stop_on_slope = true
	collision_layer = 2 # Player layer
	collision_mask = 1 | 2 # Collide with World (1) and Players (2)
	
	if name.is_valid_int():
		peer_id = name.to_int()
	set_multiplayer_authority(peer_id)
	
	if NetworkManager.players.has(peer_id):
		var info: Dictionary = NetworkManager.players[peer_id]
		player_name = info.get("name", "Player")
		role = info.get("role", NetworkManager.Role.RUNNER)
	
	name_label.text = "%s\n[%s]" % [player_name, NetworkManager.get_role_name(role)]
	_apply_role_appearance()
	
	if is_multiplayer_authority():
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mesh_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		name_label.visible = false
		_spawn_at_role_position()
	else:
		camera.current = false
		reach_hand.visible = false

func _apply_role_appearance() -> void:
	var mat := StandardMaterial3D.new()
	match role:
		NetworkManager.Role.RUNNER:
			mat.albedo_color = Color(0.2, 0.85, 0.35) # Emerald Green
		NetworkManager.Role.PATOTOT:
			mat.albedo_color = Color(1.0, 0.85, 0.15) # Gold
		_:
			mat.albedo_color = Color(0.9, 0.2, 0.2) # Defender Crimson
	mat.roughness = 0.5
	mesh_body.material_override = mat

func _spawn_at_role_position() -> void:
	match role:
		NetworkManager.Role.RUNNER:
			# Start outside entrance line, facing into court (+Z)
			global_position = Vector3(0, 0.9, -3.0)
			rotation.y = deg_to_rad(180)
		NetworkManager.Role.PATOTOT:
			# Front line, facing runners outside (-Z)
			global_position = Vector3(0, 0.9, 0.0)
			rotation.y = 0.0
		NetworkManager.Role.LINE_GUARD_1:
			global_position = Vector3(0, 0.9, 4.0)
			rotation.y = 0.0
		NetworkManager.Role.LINE_GUARD_2:
			global_position = Vector3(0, 0.9, 8.0)
			rotation.y = 0.0
		NetworkManager.Role.LINE_GUARD_BACK:
			global_position = Vector3(0, 0.9, 12.0)
			rotation.y = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	
	# Mouse look
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-80), deg_to_rad(80))
	
	# Toggle mouse cursor
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Patotot switch between Front Line and Center Spine
	if event.is_action_pressed("switch_axis") and role == NetworkManager.Role.PATOTOT:
		_toggle_patotot_axis()
	
	# Tag action (Defenders only)
	if (event.is_action_pressed("tag") or event.is_action_pressed("tag_key")) and role != NetworkManager.Role.RUNNER:
		_attempt_tag()

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	
	if tag_cooldown > 0.0:
		tag_cooldown -= delta
	
	if role == NetworkManager.Role.RUNNER:
		_physics_runner(delta)
	elif role == NetworkManager.Role.PATOTOT:
		_physics_patotot(delta)
	else:
		_physics_line_guard(delta)
	
	move_and_slide()
	
	# godot-animation: First-person camera bobbing and lean
	_handle_camera_bob_and_lean(delta)

# Helper to calculate camera-relative movement projected onto a line axis
func _get_line_slide_direction(line_axis: Vector3) -> float:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	if input_dir == Vector2.ZERO:
		return 0.0
	
	# Desired 3D movement direction in world space based on where the player is looking
	var desired_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Project intended direction onto the line's axis
	var projection := desired_dir.dot(line_axis)
	
	# If there is a clear intent along the line, slide
	if abs(projection) > 0.15:
		return sign(projection)
	return 0.0

# --- RUNNER PHYSICS (Free 3D Movement) ---
func _physics_runner(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY
	
	var is_sprinting := Input.is_action_pressed("sprint") and stamina > 5.0
	is_crouching = Input.is_action_pressed("crouch")
	
	var speed := WALK_SPEED
	if is_crouching:
		speed = CROUCH_SPEED
	elif is_sprinting:
		speed = SPRINT_SPEED
		stamina = max(stamina - 25.0 * delta, 0.0)
	else:
		stamina = min(stamina + 15.0 * delta, 100.0)
	
	# Dynamic sprint FOV (godot-animation)
	var target_fov := 94.0 if is_sprinting and velocity.length() > 2.0 else 85.0
	camera.fov = lerp(camera.fov, target_fov, 8.0 * delta)
	
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

# --- LINE GUARD PHYSICS (Locked to assigned horizontal line) ---
func _physics_line_guard(delta: float) -> void:
	var target_z: float = LINE_Z_POSITIONS.get(role, 0.0)
	# Snap / constrain Z position strictly to the chalk line
	global_position.z = move_toward(global_position.z, target_z, 0.1)
	velocity.z = 0
	
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	
	var slide_dir := _get_line_slide_direction(Vector3.RIGHT)
	velocity.x = slide_dir * GUARD_SLIDE_SPEED
	
	if (global_position.x <= -COURT_HALF_WIDTH and velocity.x < 0) or (global_position.x >= COURT_HALF_WIDTH and velocity.x > 0):
		velocity.x = 0

# --- PATOTOT PHYSICS (Dual Axis: Front Line OR Center Spine) ---
func _physics_patotot(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	
	if is_patotot_on_spine:
		# Locked to Center Spine (X = 0, moving along World Z axis from 0 to 12)
		global_position.x = move_toward(global_position.x, 0.0, 0.2)
		velocity.x = 0
		
		var slide_dir := _get_line_slide_direction(Vector3.BACK)
		velocity.z = slide_dir * GUARD_SLIDE_SPEED
		
		if (global_position.z <= 0.0 and velocity.z < 0) or (global_position.z >= 12.0 and velocity.z > 0):
			velocity.z = 0
	else:
		# Locked to Front Line (Z = 0, moving along World X axis from -3.8 to +3.8)
		global_position.z = move_toward(global_position.z, 0.0, 0.2)
		velocity.z = 0
		
		var slide_dir := _get_line_slide_direction(Vector3.RIGHT)
		velocity.x = slide_dir * GUARD_SLIDE_SPEED
		
		if (global_position.x <= -COURT_HALF_WIDTH and velocity.x < 0) or (global_position.x >= COURT_HALF_WIDTH and velocity.x > 0):
			velocity.x = 0

func _toggle_patotot_axis() -> void:
	if not is_patotot_on_spine:
		if abs(global_position.x) <= 1.5:
			is_patotot_on_spine = true
			global_position.x = 0.0
	else:
		if global_position.z <= 2.0:
			is_patotot_on_spine = false
			global_position.z = 0.0

# --- FIRST-PERSON FEEL & ANIMATION (godot-animation) ---
func _handle_camera_bob_and_lean(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.5 and is_on_floor():
		var prev_bob := sin(bob_time)
		bob_time += delta * horizontal_speed * 1.8
		var new_bob := sin(bob_time)
		# Footstep triggers when the foot contacts the ground (bob zero-crossing)
		if prev_bob < 0.0 and new_bob >= 0.0:
			var is_sprint := Input.is_action_pressed("sprint") and stamina > 5.0
			var vol := 1.1 if is_sprint else 0.65
			AudioManager.play_footstep(vol)
		
		head.position.y = HEAD_BASE_Y + new_bob * BOB_AMP
		head.position.x = cos(bob_time * 0.5) * (BOB_AMP * 0.5)
	else:
		head.position.y = move_toward(head.position.y, HEAD_BASE_Y, delta * 0.5)
		head.position.x = move_toward(head.position.x, 0.0, delta * 0.5)
	
	# Camera Lean (Q/E) for guards & runners to peek corners
	var lean_target := 0.0
	if Input.is_key_pressed(KEY_Q):
		lean_target = deg_to_rad(6.0)
	elif Input.is_key_pressed(KEY_E) and role != NetworkManager.Role.PATOTOT:
		lean_target = deg_to_rad(-6.0)
	camera.rotation.z = lerp_angle(camera.rotation.z, lean_target, 10.0 * delta)

func _attempt_tag() -> void:
	if tag_cooldown > 0.0 or is_tagging:
		return
	
	tag_cooldown = 0.4
	is_tagging = true
	_animate_tag_reach()
	
	# Check Shapecast for runners
	tag_cast.force_shapecast_update()
	if tag_cast.is_colliding():
		for i in range(tag_cast.get_collision_count()):
			var collider := tag_cast.get_collider(i)
			if collider != self and "role" in collider:
				if collider.role == NetworkManager.Role.RUNNER:
					# Tag verified!
					var target_name: String = collider.player_name if "player_name" in collider else collider.bot_name if "bot_name" in collider else "Runner"
					NetworkManager.trigger_tag(collider.peer_id if "peer_id" in collider else 0, peer_id, target_name, player_name)
					break

func _animate_tag_reach() -> void:
	var tween := create_tween().set_parallel(true)
	reach_hand.visible = true
	reach_hand.position = Vector3(0.3, -0.3, -0.4)
	
	# Punch forward and return
	tween.tween_property(reach_hand, "position", Vector3(0.0, -0.1, -1.25), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(head, "position:z", -0.15, 0.12)
	
	await tween.finished
	var return_tween := create_tween().set_parallel(true)
	return_tween.tween_property(reach_hand, "position", Vector3(0.3, -0.3, -0.4), 0.16)
	return_tween.tween_property(head, "position:z", 0.0, 0.16)
	
	await return_tween.finished
	is_tagging = false
	if not is_multiplayer_authority():
		reach_hand.visible = false
