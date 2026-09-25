extends CharacterBody3D
class_name BotPlayer

# Node References
@onready var mesh_body: MeshInstance3D = $MeshInstance3D
@onready var name_label: Label3D = $NameLabel
@onready var tag_cast: ShapeCast3D = $TagCast
@onready var reach_hand: Node3D = $ReachHand

# Tunables (game-ai / godot-physics)
const SLIDE_SPEED := 6.2
const RUNNER_SPEED := 5.8
const COURT_HALF_WIDTH := 3.7
const GRAVITY := 15.0

const LINE_Z_POSITIONS := {
	NetworkManager.Role.PATOTOT: 0.0,
	NetworkManager.Role.LINE_GUARD_1: 4.0,
	NetworkManager.Role.LINE_GUARD_2: 8.0,
	NetworkManager.Role.LINE_GUARD_BACK: 12.0
}

@export var role: NetworkManager.Role = NetworkManager.Role.LINE_GUARD_1
@export var bot_name: String = "Bot"
@export var player_name: String = "Bot"
@export var peer_id: int = 0

# AI State
enum BotState { PATROL, TRACK, TAG, ADVANCE, RETREAT }
var current_state: BotState = BotState.PATROL

var is_patotot_on_spine: bool = false
var target_runner: Node3D = null
var patrol_dir: float = 1.0
var state_timer: float = 0.0
var tag_cooldown: float = 0.0
var is_tagging: bool = false
var has_reached_back: bool = false

func _ready() -> void:
	if peer_id == 0:
		peer_id = get_instance_id()
	player_name = "🤖 %s" % bot_name
	collision_layer = 2 # Player layer
	collision_mask = 1 | 2
	name_label.text = "%s\n[%s]" % [player_name, NetworkManager.get_role_name(role)]
	_apply_role_appearance()
	_spawn_at_role_position()

func _apply_role_appearance() -> void:
	var mat := StandardMaterial3D.new()
	match role:
		NetworkManager.Role.RUNNER:
			mat.albedo_color = Color(0.2, 0.7, 0.3)
		NetworkManager.Role.PATOTOT:
			mat.albedo_color = Color(0.95, 0.8, 0.1)
		_:
			mat.albedo_color = Color(0.85, 0.25, 0.25)
	mat.roughness = 0.6
	mesh_body.material_override = mat

func _spawn_at_role_position() -> void:
	match role:
		NetworkManager.Role.RUNNER:
			global_position = Vector3(randf_range(-2.0, 2.0), 1.0, -3.5)
			rotation.y = deg_to_rad(180)
		NetworkManager.Role.PATOTOT:
			global_position = Vector3(0, 1.0, 0.0)
			rotation.y = 0.0
		NetworkManager.Role.LINE_GUARD_1:
			global_position = Vector3(randf_range(-1.5, 1.5), 1.0, 4.0)
			rotation.y = 0.0
		NetworkManager.Role.LINE_GUARD_2:
			global_position = Vector3(randf_range(-1.5, 1.5), 1.0, 8.0)
			rotation.y = 0.0
		NetworkManager.Role.LINE_GUARD_BACK:
			global_position = Vector3(randf_range(-1.5, 1.5), 1.0, 12.0)
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

# --- AI LINE GUARD (Horizontal tracking & lunging) ---
func _ai_line_guard_tick(_delta: float) -> void:
	var target_z: float = LINE_Z_POSITIONS.get(role, 4.0)
	global_position.z = move_toward(global_position.z, target_z, 0.1)
	velocity.z = 0
	velocity.y = 0
	
	target_runner = _find_nearest_runner()
	
	if target_runner and abs(target_runner.global_position.z - target_z) < 3.2:
		# TRACK RUNNER: Mirror runner's X position
		var dx: float = target_runner.global_position.x - global_position.x
		if abs(dx) > 0.3:
			velocity.x = sign(dx) * SLIDE_SPEED
		else:
			velocity.x = 0
		
		# Check if runner is close enough for a tag
		var dist: float = global_position.distance_to(target_runner.global_position)
		if dist < 1.75 and tag_cooldown <= 0.0:
			_attempt_tag()
	else:
		# PATROL: Slide back and forth along line
		if global_position.x >= COURT_HALF_WIDTH - 0.5:
			patrol_dir = -1.0
		elif global_position.x <= -COURT_HALF_WIDTH + 0.5:
			patrol_dir = 1.0
		velocity.x = patrol_dir * (SLIDE_SPEED * 0.6)
	
	# Clamp inside line width
	if (global_position.x <= -COURT_HALF_WIDTH and velocity.x < 0) or (global_position.x >= COURT_HALF_WIDTH and velocity.x > 0):
		velocity.x = 0

# --- AI PATOTOT (Front Line + Center Spine Coordinator) ---
func _ai_patotot_tick(_delta: float) -> void:
	velocity.y = 0
	target_runner = _find_nearest_runner()
	
	# Decision: switch to spine if a runner has penetrated deep into boxes (Z > 3.0)
	if target_runner and target_runner.global_position.z > 3.0 and not is_patotot_on_spine:
		# Head toward center to switch to spine
		if abs(global_position.x) > 0.3:
			velocity.x = -sign(global_position.x) * SLIDE_SPEED
			velocity.z = 0
		else:
			is_patotot_on_spine = true
			global_position.x = 0.0
	elif (not target_runner or target_runner.global_position.z <= 2.0) and is_patotot_on_spine:
		# Return to front line
		if global_position.z > 0.5:
			velocity.z = -SLIDE_SPEED
			velocity.x = 0
		else:
			is_patotot_on_spine = false
			global_position.z = 0.0
	
	if is_patotot_on_spine:
		# Move along spine (Z axis) to cut off runner
		global_position.x = move_toward(global_position.x, 0.0, 0.1)
		velocity.x = 0
		if target_runner:
			var dz: float = target_runner.global_position.z - global_position.z
			if abs(dz) > 0.3:
				velocity.z = sign(dz) * SLIDE_SPEED
			else:
				velocity.z = 0
			if global_position.distance_to(target_runner.global_position) < 1.75:
				_attempt_tag()
		else:
			velocity.z = 0
		if (global_position.z <= 0.0 and velocity.z < 0) or (global_position.z >= 12.0 and velocity.z > 0):
			velocity.z = 0
	else:
		# Guard Front Line (X axis)
		global_position.z = move_toward(global_position.z, 0.0, 0.1)
		velocity.z = 0
		if target_runner and target_runner.global_position.z < 3.0:
			var dx: float = target_runner.global_position.x - global_position.x
			velocity.x = sign(dx) * SLIDE_SPEED
			if global_position.distance_to(target_runner.global_position) < 1.75:
				_attempt_tag()
		else:
			if global_position.x >= COURT_HALF_WIDTH - 0.5:
				patrol_dir = -1.0
			elif global_position.x <= -COURT_HALF_WIDTH + 0.5:
				patrol_dir = 1.0
			velocity.x = patrol_dir * (SLIDE_SPEED * 0.6)
		if (global_position.x <= -COURT_HALF_WIDTH and velocity.x < 0) or (global_position.x >= COURT_HALF_WIDTH and velocity.x > 0):
			velocity.x = 0

# --- AI RUNNER (Feinting, Baiting & Dashing) ---
func _ai_runner_tick(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	
	# Determine target direction: forward to Z=13 or backward to Z=-3
	if global_position.z >= 12.5 and not has_reached_back:
		has_reached_back = true
		state_timer = 0.0
	elif global_position.z <= -1.5 and has_reached_back:
		has_reached_back = false
		state_timer = 0.0
	
	var target_z: float = -3.0 if has_reached_back else 13.5
	var z_dir: float = sign(target_z - global_position.z)
	
	# Avoid nearest defender
	var nearest_guard := _find_nearest_guard()
	var avoid_x := 0.0
	if nearest_guard:
		var dist_z: float = abs(nearest_guard.global_position.z - global_position.z)
		if dist_z < 2.5:
			# Steer away from guard's X
			var dx: float = global_position.x - nearest_guard.global_position.x
			avoid_x = sign(dx) if abs(dx) > 0.2 else (1.0 if global_position.x < 0.0 else -1.0)
	
	velocity.x = avoid_x * RUNNER_SPEED
	velocity.z = z_dir * (RUNNER_SPEED * 0.85)
	
	# Clamp inside court bounds
	global_position.x = clamp(global_position.x, -COURT_HALF_WIDTH, COURT_HALF_WIDTH)
	
	# Look toward movement
	if Vector2(velocity.x, velocity.z).length() > 0.5:
		var target_angle := atan2(velocity.x, velocity.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 8.0 * delta)

func _find_nearest_runner() -> Node3D:
	var closest: Node3D = null
	var min_dist := 9999.0
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	for p in players:
		if p != self and "role" in p and p.role == NetworkManager.Role.RUNNER:
			var d := global_position.distance_to(p.global_position)
			if d < min_dist:
				min_dist = d
				closest = p
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
				closest = p
	return closest

func _attempt_tag() -> void:
	if tag_cooldown > 0.0 or is_tagging:
		return
	tag_cooldown = 0.6
	is_tagging = true
	
	# Lunge hand animation
	var tween := create_tween()
	reach_hand.visible = true
	reach_hand.position = Vector3(0.2, 0.4, -0.3)
	tween.tween_property(reach_hand, "position", Vector3(0.0, 0.5, -1.2), 0.15)
	tween.tween_property(reach_hand, "position", Vector3(0.2, 0.4, -0.3), 0.15)
	await tween.finished
	reach_hand.visible = false
	is_tagging = false
	
	# Raycast check
	tag_cast.force_shapecast_update()
	if tag_cast.is_colliding():
		for i in range(tag_cast.get_collision_count()):
			var c := tag_cast.get_collider(i)
			if c != self and "role" in c and c.role == NetworkManager.Role.RUNNER:
				var runner_name: String = c.player_name if "player_name" in c else c.bot_name if "bot_name" in c else "Runner"
				NetworkManager.report_tag.rpc(c.peer_id if "peer_id" in c else 0, peer_id, runner_name, player_name)
				break
