extends CharacterBody3D
class_name BotPlayer

# Node References
@onready var mesh_body: MeshInstance3D = $MeshInstance3D
@onready var name_label: Label3D = $NameLabel
@onready var tag_cast: ShapeCast3D = $TagCast
@onready var reach_hand: Node3D = $ReachHand

# Tunables (game-ai / godot-physics / human-reaction)
const GUARD_TRACK_SPEED: float = 6.0
const GUARD_PATROL_SPEED: float = 3.2
const GUARD_ACCEL: float = 18.0
const RUNNER_SPEED: float = 5.2
const RUNNER_SPRINT_SPEED: float = 7.8
const GRAVITY: float = 15.0

# Lane Anchors: Box centers are at X = ±2.75m. Sidings are ±5.3m.
const LANE_LEFT_X: float = -2.75
const LANE_RIGHT_X: float = 2.75
const COURT_SAFE_X_MIN: float = -3.8
const COURT_SAFE_X_MAX: float = 3.8
const COURT_HALF_WIDTH: float = 5.3

const LINE_Z_POSITIONS: Dictionary = {
	NetworkManager.Role.PATOTOT: 0.0,
	NetworkManager.Role.LINE_GUARD_1: 5.0,
	NetworkManager.Role.LINE_GUARD_2: 10.0,
	NetworkManager.Role.LINE_GUARD_BACK: 15.0
}

@export var role: NetworkManager.Role = NetworkManager.Role.LINE_GUARD_1
@export var bot_name: String = "Bot"
@export var player_name: String = "Bot"
@export var peer_id: int = 0

# Runner AI State Machine
enum RunnerState { STAGING, PROBING, DASHING }
var runner_state: RunnerState = RunnerState.STAGING
var chosen_lane_x: float = LANE_LEFT_X
var feint_timer: float = 0.0
var feint_offset_x: float = 0.0
var post_turnaround_timer: float = 0.0
var dash_timer: float = 0.0

# Defender AI State (Human Reaction Time & Latency)
var is_patotot_on_spine: bool = false
var target_runner: Node3D = null
var patrol_dir: float = 1.0
var state_timer: float = 0.0
var tag_cooldown: float = 0.0
var is_tagging: bool = false
var has_reached_back: bool = false

var guard_reaction_timer: float = 0.0
var perceived_runner_x: float = 0.0
var perceived_runner_z: float = 0.0

# Feint Overcommitment / Ankle Breaker State
var feint_override_timer: float = 0.0
var feint_override_dir: float = 0.0
var feint_stumble_timer: float = 0.0

func _ready() -> void:
	# godot-physics: ground snapping and collision layers
	floor_snap_length = 0.2
	floor_constant_speed = true
	floor_stop_on_slope = true
	
	if peer_id == 0:
		peer_id = get_instance_id()
	player_name = "🤖 %s" % bot_name
	collision_layer = 2 # Player/Guard layer
	collision_mask = 1 # Ground/World only (non-contact rules prevent blocking teammates and sliding runners)
	name_label.text = "%s\n[%s]" % [player_name, NetworkManager.get_role_name(role)]
	_apply_role_appearance()
	_spawn_at_role_position()
	
	# Random initial lane choice for runners
	if randf() < 0.5:
		chosen_lane_x = LANE_RIGHT_X
	else:
		chosen_lane_x = LANE_LEFT_X

func _apply_role_appearance() -> void:
	var mat := StandardMaterial3D.new()
	match role:
		NetworkManager.Role.RUNNER:
			mat.albedo_color = Color(0.2, 0.75, 0.35)
		NetworkManager.Role.PATOTOT:
			mat.albedo_color = Color(0.95, 0.8, 0.1)
		_:
			mat.albedo_color = Color(0.85, 0.25, 0.25)
	mat.roughness = 0.6
	mesh_body.material_override = mat

func _spawn_at_role_position() -> void:
	match role:
		NetworkManager.Role.RUNNER:
			# Start outside entrance line, facing into court (+Z)
			var start_x: float = LANE_LEFT_X if randf() < 0.5 else LANE_RIGHT_X
			global_position = Vector3(start_x, 0.9, -3.5)
			rotation.y = deg_to_rad(180)
		NetworkManager.Role.PATOTOT:
			global_position = Vector3(0, 0.9, 0.0)
			rotation.y = 0.0
		NetworkManager.Role.LINE_GUARD_1:
			global_position = Vector3(randf_range(-2.0, 2.0), 0.9, 5.0)
			rotation.y = 0.0
		NetworkManager.Role.LINE_GUARD_2:
			global_position = Vector3(randf_range(-2.0, 2.0), 0.9, 10.0)
			rotation.y = 0.0
		NetworkManager.Role.LINE_GUARD_BACK:
			global_position = Vector3(randf_range(-2.0, 2.0), 0.9, 15.0)
			rotation.y = 0.0

func _physics_process(delta: float) -> void:
	state_timer += delta
	if tag_cooldown > 0.0:
		tag_cooldown -= delta
	
	if role == NetworkManager.Role.RUNNER:
		_ai_runner_tick(delta)
	elif role == NetworkManager.Role.PATOTOT:
		_ai_patotot_tick(delta)
	else:
		_ai_line_guard_tick(delta)
	
	move_and_slide()


# Called when tagged by a defender
func on_tagged() -> void:
	if role == NetworkManager.Role.RUNNER:
		runner_state = RunnerState.STAGING
		has_reached_back = false
		global_position = Vector3(randf_range(-2.5, 2.5), 0.9, -3.5)
		velocity = Vector3.ZERO
		post_turnaround_timer = 1.0 # 1 second recovery freeze
		chosen_lane_x = LANE_LEFT_X if randf() < 0.5 else LANE_RIGHT_X

func reset_defender_position() -> void:
	if role == NetworkManager.Role.RUNNER:
		return
	velocity = Vector3.ZERO
	tag_cooldown = 0.6
	is_patotot_on_spine = false
	feint_override_timer = 0.0
	feint_stumble_timer = 0.0
	_spawn_at_role_position()

func on_feinted_by_runner(juke_dir: float, _runner: Node3D) -> void:
	if role == NetworkManager.Role.RUNNER:
		return
	# Defender falls for the fake cut (Ankle Breaker!):
	# Runner jukes in juke_dir (+1=right, -1=left), so defender bites in opposite direction (-juke_dir)!
	feint_override_timer = 0.55
	feint_override_dir = -juke_dir
	feint_stumble_timer = 0.45
	tag_cooldown = max(tag_cooldown, 0.9) # Cannot tag while recovering from stumble
	AudioManager.play_slide_skid()
	
	# Visual stumble animation: tilt body away
	var tween := create_tween()
	tween.tween_property(mesh_body, "rotation:z", deg_to_rad(-juke_dir * 18.0), 0.12)
	tween.tween_property(mesh_body, "rotation:z", 0.0, 0.25)

# --- AI LINE GUARD (Horizontal tracking with human reaction time & inertia) ---
func _ai_line_guard_tick(delta: float) -> void:
	var target_z: float = LINE_Z_POSITIONS.get(role, 5.0)
	global_position.z = move_toward(global_position.z, target_z, 0.1)
	velocity.z = 0.0
	
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	
	# Check if currently baited by runner's juke
	if feint_override_timer > 0.0:
		feint_override_timer -= delta
		velocity.x = move_toward(velocity.x, feint_override_dir * (GUARD_TRACK_SPEED * 1.15), GUARD_ACCEL * delta)
		if (global_position.x <= -COURT_HALF_WIDTH and velocity.x < 0) or (global_position.x >= COURT_HALF_WIDTH and velocity.x > 0):
			velocity.x = 0.0
		return
	elif feint_stumble_timer > 0.0:
		feint_stumble_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
		return
	
	target_runner = _find_nearest_runner()
	
	# Human perception latency: responsive athletic tracking
	guard_reaction_timer -= delta
	if guard_reaction_timer <= 0.0:
		guard_reaction_timer = randf_range(0.12, 0.18)
		if target_runner:
			perceived_runner_x = target_runner.global_position.x
	
	# Only track if runner is within active engagement range (3.2m)
	if target_runner and abs(target_runner.global_position.z - target_z) < 3.2:
		var dx: float = perceived_runner_x - global_position.x
		var desired_vx: float = 0.0
		if abs(dx) > 0.25:
			desired_vx = sign(dx) * GUARD_TRACK_SPEED
		velocity.x = move_toward(velocity.x, desired_vx, GUARD_ACCEL * delta)
		
		# Rotate smoothly to face approaching runner
		var look_offset: Vector3 = target_runner.global_position - global_position
		look_offset.y = 0.0
		if look_offset.length() > 0.2:
			rotation.y = lerp_angle(rotation.y, atan2(-look_offset.x, -look_offset.z), 10.0 * delta)
		
		# Tag runner if in reach
		var dist: float = global_position.distance_to(target_runner.global_position)
		if dist < 1.4 and tag_cooldown <= 0.0:
			_attempt_tag()
	else:
		# PATROL: Gentle slide back and forth along line with smooth deceleration
		if global_position.x >= COURT_HALF_WIDTH - 0.8:
			patrol_dir = -1.0
		elif global_position.x <= -COURT_HALF_WIDTH + 0.8:
			patrol_dir = 1.0
		var desired_vx: float = patrol_dir * GUARD_PATROL_SPEED
		velocity.x = move_toward(velocity.x, desired_vx, GUARD_ACCEL * delta)
	
	# Clamp inside line width
	if (global_position.x <= -COURT_HALF_WIDTH and velocity.x < 0) or (global_position.x >= COURT_HALF_WIDTH and velocity.x > 0):
		velocity.x = 0.0

# --- AI PATOTOT (Front Line + Center Spine Coordinator with Reaction Latency) ---
func _ai_patotot_tick(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	
	# Feint handling for Patotot
	if feint_override_timer > 0.0:
		feint_override_timer -= delta
		if is_patotot_on_spine:
			velocity.z = move_toward(velocity.z, feint_override_dir * (GUARD_TRACK_SPEED * 1.15), GUARD_ACCEL * delta)
			if (global_position.z <= 0.0 and velocity.z < 0) or (global_position.z >= 15.0 and velocity.z > 0):
				velocity.z = 0.0
		else:
			velocity.x = move_toward(velocity.x, feint_override_dir * (GUARD_TRACK_SPEED * 1.15), GUARD_ACCEL * delta)
			if (global_position.x <= -COURT_HALF_WIDTH and velocity.x < 0) or (global_position.x >= COURT_HALF_WIDTH and velocity.x > 0):
				velocity.x = 0.0
		return
	elif feint_stumble_timer > 0.0:
		feint_stumble_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 14.0 * delta)
		return
	
	target_runner = _find_nearest_runner()
	
	guard_reaction_timer -= delta
	if guard_reaction_timer <= 0.0:
		guard_reaction_timer = randf_range(0.10, 0.16)
		if target_runner:
			perceived_runner_x = target_runner.global_position.x
			perceived_runner_z = target_runner.global_position.z
	
	# Determine if Patotot should be on the Center Spine or Front Line:
	# If any runner has crossed into the court (Z > 0.6), Captain commands the Center Spine (X = 0)
	var runner_in_court: bool = target_runner != null and perceived_runner_z > 0.6
	
	if runner_in_court:
		# --- CENTER SPINE MODE (Z Axis, X locked to 0) ---
		# 1. Slide smoothly onto Center Spine (X = 0) along Front Line before advancing
		if abs(global_position.x) > 0.15:
			global_position.z = move_toward(global_position.z, 0.0, 0.2)
			velocity.x = move_toward(velocity.x, -sign(global_position.x) * GUARD_TRACK_SPEED, GUARD_ACCEL * delta)
			velocity.z = 0.0
			is_patotot_on_spine = false
		else:
			global_position.x = 0.0
			velocity.x = 0.0
			is_patotot_on_spine = true
			
			# 2. Track runner along spine (Z axis: 0.0 to 15.0)
			if target_runner:
				var dz: float = perceived_runner_z - global_position.z
				var desired_vz: float = 0.0
				if abs(dz) > 0.2:
					desired_vz = clamp(dz * 4.5, -GUARD_TRACK_SPEED, GUARD_TRACK_SPEED)
				velocity.z = move_toward(velocity.z, desired_vz, GUARD_ACCEL * delta)
				
				# Face the runner into whatever lane/box they are currently in
				var look_offset: Vector3 = target_runner.global_position - global_position
				look_offset.y = 0.0
				if look_offset.length() > 0.2:
					rotation.y = lerp_angle(rotation.y, atan2(-look_offset.x, -look_offset.z), 10.0 * delta)
				
				# Tag runner if in reach across the center spine
				var dist: float = global_position.distance_to(target_runner.global_position)
				if dist < 1.45 and tag_cooldown <= 0.0:
					_attempt_tag()
			else:
				velocity.z = move_toward(velocity.z, 0.0, GUARD_ACCEL * delta)
		
		# Clamp inside court spine limits (0.0 to 15.0)
		if (global_position.z <= 0.0 and velocity.z < 0) or (global_position.z >= 15.0 and velocity.z > 0):
			velocity.z = 0.0
			global_position.z = clamp(global_position.z, 0.0, 15.0)
	else:
		# --- FRONT LINE MODE (X Axis, Z locked to 0) ---
		# 1. If returning from spine, move back to Front Line (Z = 0)
		if global_position.z > 0.2:
			velocity.z = move_toward(velocity.z, -GUARD_TRACK_SPEED, GUARD_ACCEL * delta)
			velocity.x = 0.0
		else:
			global_position.z = 0.0
			velocity.z = 0.0
			is_patotot_on_spine = false
			
			# 2. Track runner laterally on Front Line
			if target_runner:
				var dx: float = perceived_runner_x - global_position.x
				var desired_vx: float = 0.0
				if abs(dx) > 0.2:
					desired_vx = clamp(dx * 4.0, -GUARD_TRACK_SPEED, GUARD_TRACK_SPEED)
				velocity.x = move_toward(velocity.x, desired_vx, GUARD_ACCEL * delta)
				
				# Face the runner outside
				var look_offset: Vector3 = target_runner.global_position - global_position
				look_offset.y = 0.0
				if look_offset.length() > 0.2:
					rotation.y = lerp_angle(rotation.y, atan2(-look_offset.x, -look_offset.z), 10.0 * delta)
				
				# Tag runner if in reach
				if global_position.distance_to(target_runner.global_position) < 1.4 and tag_cooldown <= 0.0:
					_attempt_tag()
			else:
				# Patrol front line if no runner active
				if global_position.x >= COURT_HALF_WIDTH - 0.8:
					patrol_dir = -1.0
				elif global_position.x <= -COURT_HALF_WIDTH + 0.8:
					patrol_dir = 1.0
				var desired_vx: float = patrol_dir * GUARD_PATROL_SPEED
				velocity.x = move_toward(velocity.x, desired_vx, GUARD_ACCEL * delta)
		
		# Clamp inside line width
		if (global_position.x <= -COURT_HALF_WIDTH and velocity.x < 0) or (global_position.x >= COURT_HALF_WIDTH and velocity.x > 0):
			velocity.x = 0.0
			global_position.x = clamp(global_position.x, -COURT_HALF_WIDTH, COURT_HALF_WIDTH)

# --- SMART AI RUNNER (Corridor Lanes, Feinting, Baiting & Line Dashing) ---
func _ai_runner_tick(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	
	# Check for Goal Milestones (Back reached vs Home reached)
	if global_position.z >= 12.8 and not has_reached_back:
		has_reached_back = true
		runner_state = RunnerState.STAGING
		post_turnaround_timer = 0.9
		chosen_lane_x = LANE_LEFT_X if randf() < 0.5 else LANE_RIGHT_X
	elif global_position.z <= -2.5 and has_reached_back:
		has_reached_back = false
		runner_state = RunnerState.STAGING
		post_turnaround_timer = 0.9
		chosen_lane_x = LANE_LEFT_X if randf() < 0.5 else LANE_RIGHT_X
	
	# Turnaround celebration / recovery pause
	if post_turnaround_timer > 0.0:
		post_turnaround_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
		return
	
	# 1. Determine target chalk line and its assigned defender
	var target_line_z: float = 0.0
	var z_direction: float = 1.0 if not has_reached_back else -1.0
	var guard_role: int = -1
	
	if not has_reached_back:
		# Outbound: Advancing from Entrance (Z=-3.5) to Back (Z=15)
		if global_position.z < -0.3:
			target_line_z = 0.0
			guard_role = NetworkManager.Role.PATOTOT
		elif global_position.z < 4.7:
			target_line_z = 5.0
			guard_role = NetworkManager.Role.LINE_GUARD_1
		elif global_position.z < 9.7:
			target_line_z = 10.0
			guard_role = NetworkManager.Role.LINE_GUARD_2
		elif global_position.z < 14.7:
			target_line_z = 15.0
			guard_role = NetworkManager.Role.LINE_GUARD_BACK
		else:
			# Past all lines, run into back safe zone
			target_line_z = 17.5
			guard_role = -1
	else:
		# Inbound: Returning from Back (Z=17.5) to Home (Z=-3.5)
		if global_position.z > 10.3:
			target_line_z = 10.0
			guard_role = NetworkManager.Role.LINE_GUARD_2
		elif global_position.z > 5.3:
			target_line_z = 5.0
			guard_role = NetworkManager.Role.LINE_GUARD_1
		elif global_position.z > 0.3:
			target_line_z = 0.0
			guard_role = NetworkManager.Role.PATOTOT
		else:
			# Past Line 0, run into entrance home safe zone
			target_line_z = -3.5
			guard_role = -1
	
	var z_dist_to_line: float = abs(global_position.z - target_line_z)
	var upcoming_guard: Node3D = _find_guard_for_role(guard_role, target_line_z) if guard_role != -1 else null
	var spine_patotot: Node3D = _find_spine_patotot()
	
	# 2. State-Based Navigation
	if runner_state == RunnerState.DASHING:
		dash_timer += delta
		
		# Reflex Check: Check if upcoming guard is directly blocking our path
		var is_directly_obstructed: bool = false
		if is_instance_valid(upcoming_guard):
			var dx_guard: float = abs(upcoming_guard.global_position.x - global_position.x)
			var dz_guard: float = abs(upcoming_guard.global_position.z - global_position.z)
			if dx_guard < 1.15 and dz_guard < 1.35:
				is_directly_obstructed = true
		
		# Abort dash if blocked directly or if dash timed out, to avoid bumping into guard
		if is_directly_obstructed or dash_timer > 1.3:
			runner_state = RunnerState.STAGING
			# Juke to the opposite lane immediately!
			chosen_lane_x = LANE_RIGHT_X if chosen_lane_x == LANE_LEFT_X else LANE_LEFT_X
			feint_timer = 0.0
			var safe_hold_z: float = target_line_z - (z_direction * 1.55)
			velocity.z = clamp((safe_hold_z - global_position.z) * 3.5, -RUNNER_SPEED, RUNNER_SPEED)
			return
		
		# DASH: Full speed sprint through the line into the next box!
		velocity.z = z_direction * RUNNER_SPRINT_SPEED
		var steer_x: float = (chosen_lane_x - global_position.x) * 4.5
		velocity.x = clamp(steer_x, -RUNNER_SPEED, RUNNER_SPEED)
		
		# Check if safely cleared line by 1.2m
		if not has_reached_back and global_position.z >= target_line_z + 1.2:
			runner_state = RunnerState.STAGING
			chosen_lane_x = LANE_LEFT_X if randf() < 0.5 else LANE_RIGHT_X
		elif has_reached_back and global_position.z <= target_line_z - 1.2:
			runner_state = RunnerState.STAGING
			chosen_lane_x = LANE_LEFT_X if randf() < 0.5 else LANE_RIGHT_X
	else:
		# STAGING / PROBING
		if guard_role == -1 or not is_instance_valid(upcoming_guard):
			# No guard on this line! Clear to dash!
			runner_state = RunnerState.DASHING
			dash_timer = 0.0
		elif z_dist_to_line > 2.2:
			# Approaching the line: move toward staging distance
			velocity.z = z_direction * RUNNER_SPEED
			var steer_x: float = (chosen_lane_x - global_position.x) * 3.5
			velocity.x = clamp(steer_x, -RUNNER_SPEED, RUNNER_SPEED)
		else:
			# PROBING / TACTICAL READ: Close to the line (within 2.2m)
			var guard_x: float = upcoming_guard.global_position.x
			var my_lane_clearance: float = abs(guard_x - chosen_lane_x)
			var other_lane_x: float = LANE_RIGHT_X if chosen_lane_x == LANE_LEFT_X else LANE_LEFT_X
			var other_lane_clearance: float = abs(guard_x - other_lane_x)
			
			if my_lane_clearance < 1.55:
				# Guard is blocking our lane!
				# Maintain safe 1.55m buffer so runner never bumps into guard
				var safe_hold_z: float = target_line_z - (z_direction * 1.55)
				velocity.z = clamp((safe_hold_z - global_position.z) * 3.0, -RUNNER_SPEED, RUNNER_SPEED)
				
				# If other lane has a clear opening, switch lanes!
				if other_lane_clearance > 2.3:
					chosen_lane_x = other_lane_x
					feint_timer = 0.0
				else:
					# Guard is in the middle or tracking: perform feint
					feint_timer += delta
					if feint_timer > 0.7:
						feint_timer = 0.0
						feint_offset_x = randf_range(-0.6, 0.6)
					var target_x: float = chosen_lane_x + feint_offset_x
					velocity.x = clamp((target_x - global_position.x) * 3.2, -RUNNER_SPEED, RUNNER_SPEED)
			else:
				# Clearance is open (guard is over 1.55m away)!
				# Check if Spine Captain is blocking near our lane
				var spine_blocking: bool = false
				if is_instance_valid(spine_patotot):
					var dz_spine: float = abs(spine_patotot.global_position.z - global_position.z)
					if dz_spine < 2.0 and abs(chosen_lane_x) < 1.5:
						spine_blocking = true
				
				if spine_blocking:
					# Push wider in our lane to avoid spine tag
					chosen_lane_x = -2.2 if chosen_lane_x < 0 else 2.2
					velocity.x = (chosen_lane_x - global_position.x) * 3.0
					velocity.z = 0.0
				else:
					# Lane is open! DASH THROUGH!
					runner_state = RunnerState.DASHING
					dash_timer = 0.0
	
	# Spine Captain Avoidance: Always keep safe distance from X=0 if spine patotot is nearby
	if is_instance_valid(spine_patotot):
		var dz_spine: float = abs(spine_patotot.global_position.z - global_position.z)
		if dz_spine < 2.2 and abs(global_position.x) < 1.3:
			var push_dir: float = -1.0 if global_position.x <= 0 else 1.0
			velocity.x += push_dir * 3.5
	
	# 3. Sidelines Clamping: NEVER touch outer curbs or walls!
	global_position.x = clamp(global_position.x, COURT_SAFE_X_MIN, COURT_SAFE_X_MAX)
	
	# 4. Turn toward movement
	var horiz_vel := Vector2(velocity.x, velocity.z)
	if horiz_vel.length() > 0.3:
		var target_angle := atan2(velocity.x, velocity.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 8.0 * delta)

func _find_guard_for_role(g_role: int, line_z: float) -> Node3D:
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	var fallback_guard: Node3D = null
	var min_z_diff: float = 999.0
	
	for p in players:
		if p != self and "role" in p:
			if p.role == g_role:
				# If target role is PATOTOT, ensure they aren't on the spine
				if g_role == NetworkManager.Role.PATOTOT and "is_patotot_on_spine" in p and p.is_patotot_on_spine:
					continue
				return p as Node3D
			elif p.role != NetworkManager.Role.RUNNER:
				var z_diff: float = abs(p.global_position.z - line_z)
				if z_diff < min_z_diff:
					min_z_diff = z_diff
					fallback_guard = p as Node3D
	
	if min_z_diff < 2.5:
		return fallback_guard
	return null

func _find_spine_patotot() -> Node3D:
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	for p in players:
		if p != self and "role" in p and p.role == NetworkManager.Role.PATOTOT:
			if "is_patotot_on_spine" in p and p.is_patotot_on_spine:
				return p as Node3D
	return null

func _find_nearest_runner() -> Node3D:
	var closest: Node3D = null
	var min_dist := 9999.0
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	for p in players:
		if p != self and "role" in p and p.role == NetworkManager.Role.RUNNER:
			var d := global_position.distance_to(p.global_position)
			if d < min_dist:
				min_dist = d
				closest = p as Node3D
	return closest

func _find_nearest_guard() -> Node3D:
	var closest: Node3D = null
	var min_dist := 9999.0
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	for p in players:
		if p != self and "role" in p and p.role != NetworkManager.Role.RUNNER:
			var d := global_position.distance_to(p.global_position)
			if d < min_dist:
				min_dist = d
				closest = p as Node3D
	return closest

func _attempt_tag() -> void:
	if tag_cooldown > 0.0 or is_tagging or feint_stumble_timer > 0.0:
		return
	tag_cooldown = 0.85 # Whiff recovery window gives runners time to break through
	is_tagging = true
	
	# Lunge hand animation
	var tween := create_tween()
	reach_hand.visible = true
	reach_hand.position = Vector3(0.2, 0.4, -0.3)
	tween.tween_property(reach_hand, "position", Vector3(0.0, 0.5, -1.15), 0.13)
	tween.tween_property(reach_hand, "position", Vector3(0.2, 0.4, -0.3), 0.15)
	await tween.finished
	reach_hand.visible = false
	is_tagging = false
	
	# Tag check: Shapecast or close distance check
	var tagged := false
	tag_cast.target_position = Vector3(0, 0, -1.25)
	tag_cast.force_shapecast_update()
	if tag_cast.is_colliding():
		for i in range(tag_cast.get_collision_count()):
			var c := tag_cast.get_collider(i)
			if c != self and "role" in c and c.role == NetworkManager.Role.RUNNER:
				var is_sliding: bool = c.is_sliding if "is_sliding" in c else false
				if is_sliding:
					# SLID UNDER TAG: High standing swing passes harmlessly over sliding runner!
					tag_cooldown = 0.85
					AudioManager.play_juke_whoosh()
					GameManager.add_runner_points(1, "AGILITY DODGE: Slid under tag! (+1 Runner)")
					GameManager.show_combat_banner("🏃 SLID UNDER TAG! (+1 AGILITY)", Color(0.3, 1.0, 0.5))
					continue
				var runner_name: String = c.player_name if "player_name" in c else c.bot_name if "bot_name" in c else "Runner"
				NetworkManager.trigger_tag(c.peer_id if "peer_id" in c else 0, peer_id, runner_name, player_name)
				tagged = true
				break
	
	# Fallback distance reach tag
	if not tagged and target_runner and is_instance_valid(target_runner):
		var target_sliding: bool = target_runner.is_sliding if "is_sliding" in target_runner else false
		if target_sliding:
			tag_cooldown = 0.85
			AudioManager.play_juke_whoosh()
			GameManager.add_runner_points(1, "AGILITY DODGE: Slid under tag! (+1 Runner)")
			GameManager.show_combat_banner("🏃 SLID UNDER TAG! (+1 AGILITY)", Color(0.3, 1.0, 0.5))
		elif global_position.distance_to(target_runner.global_position) <= 1.35:
			var runner_name: String = target_runner.player_name if "player_name" in target_runner else target_runner.bot_name if "bot_name" in target_runner else "Runner"
			NetworkManager.trigger_tag(target_runner.peer_id if "peer_id" in target_runner else 0, peer_id, runner_name, player_name)
