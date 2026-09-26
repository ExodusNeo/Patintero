extends CharacterBody3D
class_name PatinteroPlayer

# Node References
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var tag_cast: ShapeCast3D = $Head/TagCast
@onready var mesh_body: MeshInstance3D = $MeshInstance3D
@onready var name_label: Label3D = $NameLabel
@onready var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var reach_hand: Node3D = $Head/ReachHand

# Movement Tunables
const WALK_SPEED: float = 5.0
const SPRINT_SPEED: float = 8.5
const CROUCH_SPEED: float = 2.8
const GUARD_SLIDE_SPEED: float = 7.0
const JUMP_VELOCITY: float = 4.5
const GRAVITY: float = 15.0
const MOUSE_SENSITIVITY: float = 0.0025
const GAMEPAD_SENSITIVITY: float = 3.2

# Head Bobbing & Feel Tunables (godot-animation / 3d essentials)
const HEAD_BASE_Y: float = 0.65
const BOB_AMP: float = 0.04
var bob_time: float = 0.0

# Court Bounds & Line Positions
const COURT_HALF_WIDTH: float = 5.3 # X axis: -5.3 to +5.3
const LINE_Z_POSITIONS: Dictionary = {
	NetworkManager.Role.PATOTOT: 0.0,
	NetworkManager.Role.LINE_GUARD_1: 5.0,
	NetworkManager.Role.LINE_GUARD_2: 10.0,
	NetworkManager.Role.LINE_GUARD_BACK: 15.0
}

# Player State
@export var peer_id: int = 1
@export var player_name: String = "Player"
@export var role: NetworkManager.Role = NetworkManager.Role.RUNNER
@export var is_patotot_on_spine: bool = false
@export var stamina: float = 100.0
@export var is_crouching: bool = false
@export var is_sliding: bool = false

# Phase 4 Ability Tunables & States
# 1. Runner Sprint-Slide
var slide_timer: float = 0.0
var slide_cooldown: float = 0.0
var slide_direction: Vector3 = Vector3.ZERO
const SLIDE_DURATION: float = 0.65
const SLIDE_INITIAL_SPEED: float = 11.2
const SLIDE_STAMINA_COST: float = 20.0

# 2. Runner Lateral Juke
var juke_cooldown: float = 0.0
const JUKE_COOLDOWN_TIME: float = 1.3
const JUKE_STAMINA_COST: float = 15.0
const JUKE_IMPULSE: float = 6.2

# 3. Defender Spine Burst
var spine_burst_timer: float = 0.0
var spine_burst_cooldown: float = 0.0
const SPINE_BURST_DURATION: float = 2.0
const SPINE_BURST_COOLDOWN_TIME: float = 6.0
const SPINE_BURST_SPEED: float = 9.8

# 4. Defender Charged Tag & Whiff Recovery
var is_tagging: bool = false
var tag_cooldown: float = 0.0
var is_charging_tag: bool = false
var tag_charge_time: float = 0.0
var tag_recovery_stun: float = 0.0
const MAX_TAG_CHARGE: float = 0.55
const MIN_CHARGED_THRESHOLD: float = 0.28

func _ready() -> void:
	# godot-physics: set up robust floor snapping and collision masks
	floor_snap_length = 0.2
	floor_constant_speed = true
	floor_stop_on_slope = true
	collision_layer = 2 # Player/Guard layer
	collision_mask = 1 # Ground/World only (non-contact rules prevent wedging & wall blocking)
	
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

func _exit_tree() -> void:
	if is_multiplayer_authority() and role == NetworkManager.Role.RUNNER:
		AudioManager.set_low_stamina_active(false, 0.0)

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
			global_position = Vector3(0, 0.9, -3.5)
			rotation.y = deg_to_rad(180)
		NetworkManager.Role.PATOTOT:
			# Front line, facing runners outside (-Z)
			global_position = Vector3(0, 0.9, 0.0)
			rotation.y = 0.0
		NetworkManager.Role.LINE_GUARD_1:
			global_position = Vector3(0, 0.9, 5.0)
			rotation.y = 0.0
		NetworkManager.Role.LINE_GUARD_2:
			global_position = Vector3(0, 0.9, 10.0)
			rotation.y = 0.0
		NetworkManager.Role.LINE_GUARD_BACK:
			global_position = Vector3(0, 0.9, 15.0)
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
	
	# Tag action (Defenders only: Press to start charging, Release to strike)
	if role != NetworkManager.Role.RUNNER:
		if event.is_action_pressed("tag") or event.is_action_pressed("tag_key"):
			if tag_cooldown <= 0.0 and tag_recovery_stun <= 0.0 and not is_tagging and not is_charging_tag:
				is_charging_tag = true
				tag_charge_time = 0.0
		elif event.is_action_released("tag") or event.is_action_released("tag_key"):
			if is_charging_tag:
				_release_tag()

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		# Sync visual slide representation for non-authoritative clients
		if is_sliding and mesh_body.scale.y > 0.6:
			_apply_slide_mesh(true)
		elif not is_sliding and mesh_body.scale.y < 0.9:
			_apply_slide_mesh(false)
		return
	
	# Gamepad Right-Stick Camera Look (input-systems)
	var rx: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if abs(rx) > 0.18:
		rotate_y(-rx * GAMEPAD_SENSITIVITY * delta)
	if abs(ry) > 0.18:
		head.rotate_x(-ry * GAMEPAD_SENSITIVITY * delta)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-80), deg_to_rad(80))
	
	# Process tag cooldowns & charging
	if tag_cooldown > 0.0:
		tag_cooldown -= delta
	
	if is_charging_tag:
		tag_charge_time += delta
		reach_hand.visible = true
		reach_hand.position = Vector3(0.3, -0.3, -0.4 + clamp(tag_charge_time * 0.4, 0.0, 0.22))
		if tag_charge_time >= MAX_TAG_CHARGE:
			_release_tag()
	
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
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	if input_dir == Vector2.ZERO:
		return 0.0
	
	# Desired 3D movement direction in world space based on where the player is looking
	var desired_dir: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Project intended direction onto the line's axis
	var projection: float = desired_dir.dot(line_axis)
	
	# If there is a clear intent along the line, slide
	if abs(projection) > 0.15:
		return sign(projection)
	return 0.0

# --- RUNNER PHYSICS (Free 3D Movement with Sprint-Slide & Juke) ---
func _physics_runner(delta: float) -> void:
	if slide_cooldown > 0.0:
		slide_cooldown -= delta
	if juke_cooldown > 0.0:
		juke_cooldown -= delta

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("jump") and not is_sliding:
		velocity.y = JUMP_VELOCITY
	
	var is_sprinting: bool = Input.is_action_pressed("sprint") and stamina > 5.0 and not is_sliding
	is_crouching = Input.is_action_pressed("crouch") and not is_sliding
	
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# 1. Sprint-Slide Trigger (Crouch while sprinting or moving fast)
	var moving_fast: bool = velocity.length() > 4.5 or is_sprinting
	if not is_sliding and is_on_floor() and slide_cooldown <= 0.0 and stamina >= SLIDE_STAMINA_COST:
		if moving_fast and Input.is_action_just_pressed("crouch"):
			_start_slide(direction)

	# 2. Slide Physics execution
	if is_sliding:
		slide_timer -= delta
		var slide_progress: float = 1.0 - clamp(slide_timer / SLIDE_DURATION, 0.0, 1.0)
		var cur_slide_speed: float = lerp(SLIDE_INITIAL_SPEED, CROUCH_SPEED, ease(slide_progress, 2.0))
		velocity.x = slide_direction.x * cur_slide_speed
		velocity.z = slide_direction.z * cur_slide_speed
		camera.rotation.z = lerp_angle(camera.rotation.z, deg_to_rad(-6.0), 10.0 * delta)
		
		if slide_timer <= 0.0 or not is_on_floor() or Input.is_action_just_pressed("jump"):
			_stop_slide()
		return

	# 3. Lateral Juke / Quick Feint
	if not is_sliding and juke_cooldown <= 0.0 and stamina >= JUKE_STAMINA_COST:
		if Input.is_action_just_pressed("juke_left"):
			_perform_juke(-1.0)
		elif Input.is_action_just_pressed("juke_right"):
			_perform_juke(1.0)

	# 4. Standard Runner Speed & Stamina
	var speed: float = WALK_SPEED
	if is_crouching:
		speed = CROUCH_SPEED
	elif is_sprinting:
		speed = SPRINT_SPEED
		stamina = max(stamina - 25.0 * delta, 0.0)
	else:
		stamina = min(stamina + 15.0 * delta, 100.0)
	
	# Low Stamina Procedural Audio Feedback
	if stamina < 25.0:
		var intensity: float = (25.0 - stamina) / 25.0
		AudioManager.set_low_stamina_active(true, intensity)
	else:
		AudioManager.set_low_stamina_active(false, 0.0)
	
	# Dynamic sprint FOV (godot-animation)
	var target_fov: float = 94.0 if is_sprinting and velocity.length() > 2.0 else 85.0
	camera.fov = lerp(camera.fov, target_fov, 8.0 * delta)
	
	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

func _start_slide(dir: Vector3) -> void:
	is_sliding = true
	slide_timer = SLIDE_DURATION
	slide_cooldown = 1.3
	stamina = max(stamina - SLIDE_STAMINA_COST, 0.0)
	slide_direction = dir if dir != Vector3.ZERO else -transform.basis.z
	
	_apply_slide_mesh(true)
	head.position.y = -0.15
	
	AudioManager.play_slide_skid()
	AudioManager.play_juke_whoosh()

func _stop_slide() -> void:
	is_sliding = false
	_apply_slide_mesh(false)
	head.position.y = HEAD_BASE_Y

func _apply_slide_mesh(active: bool) -> void:
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

func _perform_juke(dir_lateral: float) -> void:
	juke_cooldown = JUKE_COOLDOWN_TIME
	stamina = max(stamina - JUKE_STAMINA_COST, 0.0)
	var lateral_dir: Vector3 = (transform.basis * Vector3(dir_lateral, 0, 0)).normalized()
	velocity += lateral_dir * JUKE_IMPULSE
	camera.rotation.z = deg_to_rad(dir_lateral * -8.0)
	AudioManager.play_juke_whoosh()
	_notify_guards_of_juke(dir_lateral)

func _notify_guards_of_juke(dir_lateral: float) -> void:
	var feinted_count: int = 0
	var all_players: Array[Node] = get_tree().get_nodes_in_group("players")
	for p in all_players:
		if p != self and "role" in p and p.role != NetworkManager.Role.RUNNER:
			var d: float = global_position.distance_to(p.global_position)
			var dz: float = abs(global_position.z - p.global_position.z)
			if d < 4.8 and dz < 3.6:
				if p.has_method("on_feinted_by_runner"):
					p.on_feinted_by_runner(dir_lateral, self)
					feinted_count += 1
	if feinted_count > 0:
		GameManager.add_runner_points(1, "ANKLE BREAKER: Baited defender! (+1 Runner)")
		GameManager.show_combat_banner("⚡ ANKLE BREAKER! DEFENDER BITES FAKE! (+1 PT)", Color(1.0, 0.85, 0.2))

# --- LINE GUARD PHYSICS (Locked to assigned horizontal line) ---
func _physics_line_guard(delta: float) -> void:
	if tag_recovery_stun > 0.0:
		tag_recovery_stun -= delta
		velocity.x = 0.0
		velocity.y = 0.0
		return
	
	var target_z: float = LINE_Z_POSITIONS.get(role, 0.0)
	# Snap / constrain Z position strictly to the chalk line
	global_position.z = move_toward(global_position.z, target_z, 0.1)
	velocity.z = 0
	
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	
	var slide_dir: float = _get_line_slide_direction(Vector3.RIGHT)
	velocity.x = slide_dir * GUARD_SLIDE_SPEED
	
	if (global_position.x <= -COURT_HALF_WIDTH and velocity.x < 0) or (global_position.x >= COURT_HALF_WIDTH and velocity.x > 0):
		velocity.x = 0

# --- PATOTOT PHYSICS (Dual Axis: Front Line OR Center Spine with Spine Burst) ---
func _physics_patotot(delta: float) -> void:
	if tag_recovery_stun > 0.0:
		tag_recovery_stun -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		return
	
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	
	if spine_burst_cooldown > 0.0:
		spine_burst_cooldown -= delta
	
	var cur_guard_speed: float = GUARD_SLIDE_SPEED
	
	if is_patotot_on_spine:
		# Patotot Spine Burst activation
		if Input.is_action_pressed("sprint") and spine_burst_cooldown <= 0.0 and spine_burst_timer <= 0.0:
			spine_burst_timer = SPINE_BURST_DURATION
			AudioManager.play_juke_whoosh()
		
		if spine_burst_timer > 0.0:
			spine_burst_timer -= delta
			cur_guard_speed = SPINE_BURST_SPEED
			camera.fov = lerp(camera.fov, 96.0, 10.0 * delta)
			if spine_burst_timer <= 0.0:
				spine_burst_cooldown = SPINE_BURST_COOLDOWN_TIME
		else:
			camera.fov = lerp(camera.fov, 85.0, 8.0 * delta)

		# Locked to Center Spine (X = 0, moving along World Z axis from 0 to 12)
		global_position.x = move_toward(global_position.x, 0.0, 0.2)
		velocity.x = 0
		
		var slide_dir: float = _get_line_slide_direction(Vector3.BACK)
		velocity.z = slide_dir * cur_guard_speed
		
		if (global_position.z <= 0.0 and velocity.z < 0) or (global_position.z >= 15.0 and velocity.z > 0):
			velocity.z = 0
	else:
		camera.fov = lerp(camera.fov, 85.0, 8.0 * delta)
		# Locked to Front Line (Z = 0, moving along World X axis from -COURT_HALF_WIDTH to +COURT_HALF_WIDTH)
		global_position.z = move_toward(global_position.z, 0.0, 0.2)
		velocity.z = 0
		
		var slide_dir: float = _get_line_slide_direction(Vector3.RIGHT)
		velocity.x = slide_dir * GUARD_SLIDE_SPEED
		
		if (global_position.x <= -COURT_HALF_WIDTH and velocity.x < 0) or (global_position.x >= COURT_HALF_WIDTH and velocity.x > 0):
			velocity.x = 0

func _toggle_patotot_axis() -> void:
	if not is_patotot_on_spine:
		if abs(global_position.x) <= 2.0:
			is_patotot_on_spine = true
			global_position.x = 0.0
	else:
		if global_position.z <= 2.5:
			is_patotot_on_spine = false
			global_position.z = 0.0

# --- FIRST-PERSON FEEL & ANIMATION (godot-animation) ---
func _handle_camera_bob_and_lean(delta: float) -> void:
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.5 and is_on_floor() and not is_sliding:
		var prev_bob: float = sin(bob_time)
		bob_time += delta * horizontal_speed * 1.8
		var new_bob: float = sin(bob_time)
		# Footstep triggers when the foot contacts the ground (bob zero-crossing)
		if prev_bob < 0.0 and new_bob >= 0.0:
			var is_sprint: bool = Input.is_action_pressed("sprint") and stamina > 5.0
			var vol: float = 1.1 if is_sprint else 0.65
			AudioManager.play_footstep(vol)
		
		head.position.y = HEAD_BASE_Y + new_bob * BOB_AMP
		head.position.x = cos(bob_time * 0.5) * (BOB_AMP * 0.5)
	elif not is_sliding:
		head.position.y = move_toward(head.position.y, HEAD_BASE_Y, delta * 0.5)
		head.position.x = move_toward(head.position.x, 0.0, delta * 0.5)
	
	# Camera Roll / Lean handling:
	# - Defenders lean with Q/E to peek down lines
	# - Runners lean slightly during slides, and smoothly restore to 0 after jukes!
	var target_roll: float = 0.0
	if role != NetworkManager.Role.RUNNER:
		if Input.is_key_pressed(KEY_Q):
			target_roll = deg_to_rad(6.0)
		elif Input.is_key_pressed(KEY_E) and role != NetworkManager.Role.PATOTOT:
			target_roll = deg_to_rad(-6.0)
	elif is_sliding:
		target_roll = deg_to_rad(-6.0)
	
	# Smoothly return camera rotation.z to target_roll (prevents juke tilt from getting stuck!)
	camera.rotation.z = lerp_angle(camera.rotation.z, target_roll, 8.0 * delta)

# --- DEFENDER TAGGING (Quick Tag vs Charged Sweep) ---
func _release_tag() -> void:
	if not is_charging_tag:
		return
	is_charging_tag = false
	var is_charged: bool = tag_charge_time >= MIN_CHARGED_THRESHOLD
	tag_charge_time = 0.0
	_execute_tag(is_charged)

func _execute_tag(is_charged: bool) -> void:
	if tag_cooldown > 0.0 or is_tagging or tag_recovery_stun > 0.0:
		return
	
	is_tagging = true
	var sphere: SphereShape3D = tag_cast.shape as SphereShape3D
	
	if is_charged:
		AudioManager.play_charged_swing()
		if sphere:
			sphere.radius = 0.65
		tag_cast.target_position = Vector3(0, 0, -1.85)
		_animate_charged_sweep()
	else:
		AudioManager.play_juke_whoosh()
		if sphere:
			sphere.radius = 0.38
		tag_cast.target_position = Vector3(0, 0, -1.35)
		_animate_quick_tag()
	
	# Shapecast collision check
	tag_cast.force_shapecast_update()
	var hit_runner: bool = false
	if tag_cast.is_colliding():
		for i in range(tag_cast.get_collision_count()):
			var collider: Object = tag_cast.get_collider(i)
			if collider != self and "role" in collider:
				if collider.role == NetworkManager.Role.RUNNER:
					# Check slide duck evasion:
					# If runner is sliding, an un-aimed quick tag misses unless defender aims downward (head.rotation.x < -0.15) OR it was a charged sweep!
					var runner_sliding: bool = collider.is_sliding if "is_sliding" in collider else false
					if runner_sliding and not is_charged and head.rotation.x > deg_to_rad(-12.0):
						# Evaded! Low slide slipped underneath high standing tag!
						GameManager.show_combat_banner("🏃 SLID UNDER TAG!", Color(0.3, 1.0, 0.5))
						AudioManager.play_juke_whoosh()
						continue
					
					var target_name: String = collider.player_name if "player_name" in collider else collider.bot_name if "bot_name" in collider else "Runner"
					NetworkManager.trigger_tag(collider.peer_id if "peer_id" in collider else 0, peer_id, target_name, player_name)
					hit_runner = true
					break
	
	if not hit_runner:
		if is_charged:
			# Missed charged sweep penalty: 0.75s stun!
			tag_recovery_stun = 0.75
			tag_cooldown = 0.9
		else:
			tag_cooldown = 0.4
	else:
		tag_cooldown = 0.5
	
	# Restore standard shape after sweep
	if sphere:
		sphere.radius = 0.38
	tag_cast.target_position = Vector3(0, 0, -1.35)

func _animate_quick_tag() -> void:
	var tween := create_tween().set_parallel(true)
	reach_hand.visible = true
	reach_hand.position = Vector3(0.3, -0.3, -0.4)
	
	# Punch forward and return
	tween.tween_property(reach_hand, "position", Vector3(0.0, -0.1, -1.25), 0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(head, "position:z", -0.15, 0.11)
	
	await tween.finished
	var return_tween := create_tween().set_parallel(true)
	return_tween.tween_property(reach_hand, "position", Vector3(0.3, -0.3, -0.4), 0.14)
	return_tween.tween_property(head, "position:z", 0.0, 0.14)
	
	await return_tween.finished
	is_tagging = false
	if not is_multiplayer_authority():
		reach_hand.visible = false

func _animate_charged_sweep() -> void:
	var tween := create_tween().set_parallel(true)
	reach_hand.visible = true
	reach_hand.position = Vector3(0.55, -0.1, -0.3)
	
	# Wide sweeping arc across the screen
	tween.tween_property(reach_hand, "position", Vector3(-0.55, -0.15, -1.6), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(head, "position:z", -0.22, 0.18)
	
	await tween.finished
	var return_tween := create_tween().set_parallel(true)
	return_tween.tween_property(reach_hand, "position", Vector3(0.3, -0.3, -0.4), 0.22)
	return_tween.tween_property(head, "position:z", 0.0, 0.22)
	
	await return_tween.finished
	is_tagging = false
	if not is_multiplayer_authority():
		reach_hand.visible = false

func on_tagged() -> void:
	if role == NetworkManager.Role.RUNNER:
		if is_sliding:
			_stop_slide()
		global_position = Vector3(0, 0.9, -3.5)
		velocity = Vector3.ZERO
		stamina = 100.0
		AudioManager.set_low_stamina_active(false, 0.0)

func reset_defender_position() -> void:
	if role == NetworkManager.Role.RUNNER:
		return
	velocity = Vector3.ZERO
	tag_cooldown = 0.6
	tag_recovery_stun = 0.0
	is_patotot_on_spine = false
	_spawn_at_role_position()
