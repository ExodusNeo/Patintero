extends Node
class_name BotRunnerAI

# Component: Autonomous AI Runner state machine
# Corridor lanes, line probing, fake steps/feinting, and lane dash reflexes
# game-ai / godot-physics

enum RunnerState { STAGING, PROBING, DASHING }

const RUNNER_SPEED: float = 5.2
const RUNNER_SPRINT_SPEED: float = 7.8
const GRAVITY: float = 15.0

const LANE_LEFT_X: float = -2.75
const LANE_RIGHT_X: float = 2.75
const COURT_SAFE_X_MIN: float = -3.8
const COURT_SAFE_X_MAX: float = 3.8

var bot: CharacterBody3D

var runner_state: RunnerState = RunnerState.STAGING
var chosen_lane_x: float = LANE_LEFT_X
var feint_timer: float = 0.0
var feint_offset_x: float = 0.0
var post_turnaround_timer: float = 0.0
var dash_timer: float = 0.0
var has_reached_back: bool = false
var state_timer: float = 0.0

func setup(b: CharacterBody3D) -> void:
	bot = b
	chosen_lane_x = LANE_RIGHT_X if randf() < 0.5 else LANE_LEFT_X

func process_runner(delta: float) -> void:
	state_timer += delta
	if not bot.is_on_floor():
		bot.velocity.y -= GRAVITY * delta
	else:
		bot.velocity.y = 0.0
	
	if bot.global_position.z >= 12.8 and not has_reached_back:
		has_reached_back = true
		runner_state = RunnerState.STAGING
		post_turnaround_timer = 0.9
		chosen_lane_x = LANE_LEFT_X if randf() < 0.5 else LANE_RIGHT_X
	elif bot.global_position.z <= -1.5 and has_reached_back:
		has_reached_back = false
		runner_state = RunnerState.STAGING
		post_turnaround_timer = 0.9
		chosen_lane_x = LANE_LEFT_X if randf() < 0.5 else LANE_RIGHT_X
	
	if post_turnaround_timer > 0.0:
		post_turnaround_timer -= delta
		bot.velocity.x = move_toward(bot.velocity.x, 0.0, 10.0 * delta)
		bot.velocity.z = move_toward(bot.velocity.z, 0.0, 10.0 * delta)
		return
	
	var target_line_z: float = 0.0
	var guard_role: int = -1
	
	if not has_reached_back:
		if bot.global_position.z < -0.3:
			target_line_z = 0.0
			guard_role = NetworkManager.Role.PATOTOT
		elif bot.global_position.z < 4.7:
			target_line_z = 5.0
			guard_role = NetworkManager.Role.LINE_GUARD_1
		elif bot.global_position.z < 9.7:
			target_line_z = 10.0
			guard_role = NetworkManager.Role.LINE_GUARD_2
		elif bot.global_position.z < 14.7:
			target_line_z = 15.0
			guard_role = NetworkManager.Role.LINE_GUARD_BACK
		else:
			target_line_z = 17.5
			guard_role = -1
	else:
		if bot.global_position.z > 10.3:
			target_line_z = 10.0
			guard_role = NetworkManager.Role.LINE_GUARD_2
		elif bot.global_position.z > 5.3:
			target_line_z = 5.0
			guard_role = NetworkManager.Role.LINE_GUARD_1
		elif bot.global_position.z > 0.3:
			target_line_z = 0.0
			guard_role = NetworkManager.Role.PATOTOT
		else:
			target_line_z = -3.5
			guard_role = -1
	
	var z_dist_to_line: float = abs(bot.global_position.z - target_line_z)
	var active_guard: Node3D = _find_guard_for_role(guard_role)
	var guard_x: float = active_guard.global_position.x if active_guard else 0.0
	var lane_clear: bool = abs(guard_x - chosen_lane_x) > 1.3
	
	match runner_state:
		RunnerState.STAGING:
			var staging_z: float = target_line_z - 1.55 if not has_reached_back else target_line_z + 1.55
			var dz: float = staging_z - bot.global_position.z
			var dx: float = chosen_lane_x - bot.global_position.x
			bot.velocity.x = move_toward(bot.velocity.x, clamp(dx * 4.0, -RUNNER_SPEED, RUNNER_SPEED), 15.0 * delta)
			bot.velocity.z = move_toward(bot.velocity.z, clamp(dz * 4.0, -RUNNER_SPEED, RUNNER_SPEED), 15.0 * delta)
			
			if abs(dz) < 0.35 and abs(dx) < 0.35:
				runner_state = RunnerState.PROBING
				state_timer = 0.0
				feint_timer = randf_range(0.3, 0.7)
		
		RunnerState.PROBING:
			feint_timer -= delta
			if feint_timer <= 0.0:
				feint_timer = randf_range(0.4, 0.9)
				feint_offset_x = randf_range(-0.85, 0.85)
				if not lane_clear and randf() < 0.45:
					chosen_lane_x = LANE_RIGHT_X if chosen_lane_x == LANE_LEFT_X else LANE_LEFT_X
			
			var probe_target_x: float = clamp(chosen_lane_x + feint_offset_x, COURT_SAFE_X_MIN, COURT_SAFE_X_MAX)
			var dx: float = probe_target_x - bot.global_position.x
			bot.velocity.x = move_toward(bot.velocity.x, clamp(dx * 4.0, -RUNNER_SPEED * 0.75, RUNNER_SPEED * 0.75), 15.0 * delta)
			
			var safe_z: float = target_line_z - 1.3 if not has_reached_back else target_line_z + 1.3
			var dz: float = safe_z - bot.global_position.z
			bot.velocity.z = move_toward(bot.velocity.z, clamp(dz * 4.0, -RUNNER_SPEED * 0.6, RUNNER_SPEED * 0.6), 15.0 * delta)
			
			if (lane_clear and state_timer > 0.4) or (state_timer > randf_range(2.0, 3.5)):
				runner_state = RunnerState.DASHING
				dash_timer = 0.0
				state_timer = 0.0
		
		RunnerState.DASHING:
			dash_timer += delta
			var dash_dir_z: float = 1.0 if not has_reached_back else -1.0
			bot.velocity.z = move_toward(bot.velocity.z, dash_dir_z * RUNNER_SPRINT_SPEED, 22.0 * delta)
			var dx: float = chosen_lane_x - bot.global_position.x
			bot.velocity.x = move_toward(bot.velocity.x, clamp(dx * 3.5, -RUNNER_SPEED * 0.5, RUNNER_SPEED * 0.5), 14.0 * delta)
			
			if not lane_clear and z_dist_to_line < 1.0 and dash_timer < 0.2:
				runner_state = RunnerState.STAGING
				chosen_lane_x = LANE_RIGHT_X if chosen_lane_x == LANE_LEFT_X else LANE_LEFT_X
			
			var passed_line: bool = (not has_reached_back and bot.global_position.z > target_line_z + 1.35) or (has_reached_back and bot.global_position.z < target_line_z - 1.35)
			if passed_line or dash_timer > 1.25:
				runner_state = RunnerState.STAGING
				state_timer = 0.0
	
	if abs(bot.velocity.z) > 0.1:
		var target_facing: float = 0.0 if bot.velocity.z > 0 else deg_to_rad(180)
		bot.rotation.y = lerp_angle(bot.rotation.y, target_facing, 8.0 * delta)

func reset_after_tag() -> void:
	runner_state = RunnerState.STAGING
	has_reached_back = false
	var start_x: float = -2.75 if randf() < 0.5 else 2.75
	bot.global_position = Vector3(start_x, 0.9, -3.5)
	bot.rotation.y = deg_to_rad(180)
	bot.velocity = Vector3.ZERO
	post_turnaround_timer = 1.0
	chosen_lane_x = LANE_LEFT_X if randf() < 0.5 else LANE_RIGHT_X

func on_tagged() -> void:
	reset_after_tag()

func _find_guard_for_role(g_role: int) -> Node3D:
	if g_role == -1:
		return null
	var players: Array[Node] = bot.get_tree().get_nodes_in_group("players")
	for p in players:
		if p != bot and "role" in p and p.role == g_role:
			return p as Node3D
	return null
