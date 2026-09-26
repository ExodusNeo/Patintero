extends Node
class_name BotGuardAI

# Component: Line Guard and Patotot Captain AI behaviors
# Athletic tracking, human perception delay, line patrol, and center spine rail coordination
# game-ai / godot-physics

const GUARD_TRACK_SPEED: float = 6.0
const GUARD_PATROL_SPEED: float = 3.2
const GUARD_ACCEL: float = 18.0
const GRAVITY: float = 15.0
const COURT_HALF_WIDTH: float = 5.3

const LINE_Z_POSITIONS: Dictionary = {
	NetworkManager.Role.PATOTOT: 0.0,
	NetworkManager.Role.LINE_GUARD_1: 5.0,
	NetworkManager.Role.LINE_GUARD_2: 10.0,
	NetworkManager.Role.LINE_GUARD_BACK: 15.0
}

var bot: CharacterBody3D
var tagger: Node

var is_patotot_on_spine: bool = false
var patrol_dir: float = 1.0
var guard_reaction_timer: float = 0.0
var perceived_runner_x: float = 0.0
var perceived_runner_z: float = 0.0
var target_runner: Node3D = null

func setup(b: CharacterBody3D, t: Node) -> void:
	bot = b
	tagger = t

# --- LINE GUARD TICK ---
func process_line_guard(delta: float) -> void:
	var target_z: float = LINE_Z_POSITIONS.get(bot.role, 5.0)
	bot.global_position.z = move_toward(bot.global_position.z, target_z, 0.1)
	bot.velocity.z = 0.0
	
	if not bot.is_on_floor():
		bot.velocity.y -= GRAVITY * delta
	else:
		bot.velocity.y = 0.0
	
	# Feint handling
	if tagger.feint_override_timer > 0.0:
		bot.velocity.x = move_toward(bot.velocity.x, tagger.feint_override_dir * (GUARD_TRACK_SPEED * 1.15), GUARD_ACCEL * delta)
		if (bot.global_position.x <= -COURT_HALF_WIDTH and bot.velocity.x < 0) or (bot.global_position.x >= COURT_HALF_WIDTH and bot.velocity.x > 0):
			bot.velocity.x = 0.0
		return
	elif tagger.feint_stumble_timer > 0.0:
		bot.velocity.x = move_toward(bot.velocity.x, 0.0, 14.0 * delta)
		return
	
	target_runner = _find_nearest_runner()
	_update_perception(delta)
	
	# Track runner within active engagement range (4.2m)
	if target_runner and abs(target_runner.global_position.z - target_z) < 4.2:
		var dx: float = perceived_runner_x - bot.global_position.x
		var desired_vx: float = 0.0
		if abs(dx) > 0.2:
			var track_mult: float = 1.15 if abs(target_runner.global_position.z - target_z) < 2.0 else 1.0
			desired_vx = sign(dx) * (GUARD_TRACK_SPEED * track_mult)
		bot.velocity.x = move_toward(bot.velocity.x, desired_vx, GUARD_ACCEL * delta)
		
		_face_target(target_runner.global_position, delta)
		
		if bot.global_position.distance_to(target_runner.global_position) < 1.4:
			tagger.attempt_tag(target_runner)
	else:
		# Patrol along chalk line
		if bot.global_position.x >= COURT_HALF_WIDTH - 0.8:
			patrol_dir = -1.0
		elif bot.global_position.x <= -COURT_HALF_WIDTH + 0.8:
			patrol_dir = 1.0
		var desired_vx: float = patrol_dir * GUARD_PATROL_SPEED
		bot.velocity.x = move_toward(bot.velocity.x, desired_vx, GUARD_ACCEL * delta)
	
	if (bot.global_position.x <= -COURT_HALF_WIDTH and bot.velocity.x < 0) or (bot.global_position.x >= COURT_HALF_WIDTH and bot.velocity.x > 0):
		bot.velocity.x = 0.0

# --- PATOTOT TICK ---
func process_patotot(delta: float) -> void:
	if not bot.is_on_floor():
		bot.velocity.y -= GRAVITY * delta
	else:
		bot.velocity.y = 0.0
	
	if tagger.feint_override_timer > 0.0:
		if is_patotot_on_spine:
			bot.velocity.z = move_toward(bot.velocity.z, tagger.feint_override_dir * (GUARD_TRACK_SPEED * 1.15), GUARD_ACCEL * delta)
			if (bot.global_position.z <= 0.0 and bot.velocity.z < 0) or (bot.global_position.z >= 15.0 and bot.velocity.z > 0):
				bot.velocity.z = 0.0
		else:
			bot.velocity.x = move_toward(bot.velocity.x, tagger.feint_override_dir * (GUARD_TRACK_SPEED * 1.15), GUARD_ACCEL * delta)
			if (bot.global_position.x <= -COURT_HALF_WIDTH and bot.velocity.x < 0) or (bot.global_position.x >= COURT_HALF_WIDTH and bot.velocity.x > 0):
				bot.velocity.x = 0.0
		return
	elif tagger.feint_stumble_timer > 0.0:
		bot.velocity.x = move_toward(bot.velocity.x, 0.0, 14.0 * delta)
		bot.velocity.z = move_toward(bot.velocity.z, 0.0, 14.0 * delta)
		return
	
	target_runner = _find_nearest_runner()
	_update_perception(delta)
	
	var runner_in_court: bool = target_runner != null and perceived_runner_z > 0.6
	
	if runner_in_court:
		# CENTER SPINE MODE
		if abs(bot.global_position.x) > 0.15:
			bot.global_position.z = move_toward(bot.global_position.z, 0.0, 0.2)
			bot.velocity.x = move_toward(bot.velocity.x, -sign(bot.global_position.x) * GUARD_TRACK_SPEED, GUARD_ACCEL * delta)
			bot.velocity.z = 0.0
			is_patotot_on_spine = false
		else:
			bot.global_position.x = 0.0
			bot.velocity.x = 0.0
			is_patotot_on_spine = true
			
			if target_runner:
				var dz: float = perceived_runner_z - bot.global_position.z
				var desired_vz: float = 0.0
				if abs(dz) > 0.2:
					desired_vz = clamp(dz * 4.5, -GUARD_TRACK_SPEED, GUARD_TRACK_SPEED)
				bot.velocity.z = move_toward(bot.velocity.z, desired_vz, GUARD_ACCEL * delta)
				
				_face_target(target_runner.global_position, delta)
				
				if bot.global_position.distance_to(target_runner.global_position) < 1.45:
					tagger.attempt_tag(target_runner)
			else:
				bot.velocity.z = move_toward(bot.velocity.z, 0.0, GUARD_ACCEL * delta)
		
		if (bot.global_position.z <= 0.0 and bot.velocity.z < 0) or (bot.global_position.z >= 15.0 and bot.velocity.z > 0):
			bot.velocity.z = 0.0
			bot.global_position.z = clamp(bot.global_position.z, 0.0, 15.0)
	else:
		# FRONT LINE MODE
		if bot.global_position.z > 0.2:
			bot.velocity.z = move_toward(bot.velocity.z, -GUARD_TRACK_SPEED, GUARD_ACCEL * delta)
			bot.velocity.x = 0.0
		else:
			bot.global_position.z = 0.0
			bot.velocity.z = 0.0
			is_patotot_on_spine = false
			
			if target_runner:
				var dx: float = perceived_runner_x - bot.global_position.x
				var desired_vx: float = 0.0
				if abs(dx) > 0.2:
					desired_vx = clamp(dx * 4.0, -GUARD_TRACK_SPEED, GUARD_TRACK_SPEED)
				bot.velocity.x = move_toward(bot.velocity.x, desired_vx, GUARD_ACCEL * delta)
				_face_target(target_runner.global_position, delta)
				
				if bot.global_position.distance_to(target_runner.global_position) < 1.45:
					tagger.attempt_tag(target_runner)
			else:
				if bot.global_position.x >= COURT_HALF_WIDTH - 0.8:
					patrol_dir = -1.0
				elif bot.global_position.x <= -COURT_HALF_WIDTH + 0.8:
					patrol_dir = 1.0
				var desired_vx: float = patrol_dir * GUARD_PATROL_SPEED
				bot.velocity.x = move_toward(bot.velocity.x, desired_vx, GUARD_ACCEL * delta)
		
		if (bot.global_position.x <= -COURT_HALF_WIDTH and bot.velocity.x < 0) or (bot.global_position.x >= COURT_HALF_WIDTH and bot.velocity.x > 0):
			bot.velocity.x = 0.0
			bot.global_position.x = clamp(bot.global_position.x, -COURT_HALF_WIDTH, COURT_HALF_WIDTH)

func _update_perception(delta: float) -> void:
	guard_reaction_timer -= delta
	if guard_reaction_timer <= 0.0:
		guard_reaction_timer = randf_range(0.10, 0.16)
		if target_runner:
			perceived_runner_x = target_runner.global_position.x
			perceived_runner_z = target_runner.global_position.z

func _face_target(target_pos: Vector3, delta: float) -> void:
	var look_offset: Vector3 = target_pos - bot.global_position
	look_offset.y = 0.0
	if look_offset.length() > 0.2:
		bot.rotation.y = lerp_angle(bot.rotation.y, atan2(-look_offset.x, -look_offset.z), 10.0 * delta)

func _find_nearest_runner() -> Node3D:
	var closest: Node3D = null
	var min_dist := 9999.0
	var players: Array[Node] = bot.get_tree().get_nodes_in_group("players")
	for p in players:
		if p != bot and "role" in p and p.role == NetworkManager.Role.RUNNER:
			var d := bot.global_position.distance_to(p.global_position)
			if d < min_dist:
				min_dist = d
				closest = p as Node3D
	return closest
