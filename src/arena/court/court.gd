extends Node3D
class_name PatinteroCourt

# Phase 3: Palarong Pambansa Standard Court Rules & Point Verification
# Spawns white chalk powder bursts on line crossings
# godot-3d-essentials / godot-signals-groups

signal runner_reached_back(runner_id: int)
signal runner_scored_home(runner_id: int)
signal out_of_bounds_triggered(runner_id: int)
signal runner_entered_box(runner_id: int, box_id: int)
signal runner_line_passed(runner_id: int, points: int, line_name: String)

const CHALK_PUFF_SCENE := preload("res://src/vfx/dust/chalk_puff.tscn")

var runner_progress: Dictionary = {}

func _ready() -> void:
	$BackZone.body_entered.connect(_on_back_zone_entered)
	$HomeZone.body_entered.connect(_on_home_zone_entered)
	$OutOfBoundsLeft.body_entered.connect(_on_out_of_bounds_entered)
	$OutOfBoundsRight.body_entered.connect(_on_out_of_bounds_entered)
	
	for i in range(1, 7):
		var box_node := get_node_or_null("Boxes/Box%d" % i)
		if box_node is Area3D:
			box_node.body_entered.connect(_on_box_entered.bind(i))
	
	NetworkManager.player_tagged.connect(_on_player_tagged_reset)

func _spawn_chalk_burst(pos: Vector3) -> void:
	var puff := CHALK_PUFF_SCENE.instantiate()
	add_child(puff)
	puff.global_position = pos
	puff.burst()

func _is_runner(body: Node3D) -> bool:
	return "role" in body and body.role == NetworkManager.Role.RUNNER

func _get_runner_id(body: Node3D) -> int:
	if "peer_id" in body and body.peer_id != 0:
		return body.peer_id
	return body.get_instance_id()

func _get_runner_name(body: Node3D) -> String:
	return body.player_name if "player_name" in body else body.bot_name if "bot_name" in body else "Runner"

func _get_or_create_progress(pid: int) -> Dictionary:
	if not runner_progress.has(pid):
		runner_progress[pid] = { "outbound_tier": 0, "inbound_tier": 0, "has_reached_back": false }
	return runner_progress[pid]

func _on_box_entered(body: Node3D, box_id: int) -> void:
	if not _is_runner(body):
		return
	
	var pid := _get_runner_id(body)
	var rname := _get_runner_name(body)
	var prog := _get_or_create_progress(pid)
	runner_entered_box.emit(pid, box_id)
	
	if not prog["has_reached_back"]:
		if (box_id == 1 or box_id == 2) and prog["outbound_tier"] < 1:
			prog["outbound_tier"] = 1
			GameManager.add_runner_points(1, "%s crossed Line 1 (+1 pt)" % rname)
			runner_line_passed.emit(pid, 1, "LINE 1")
			_spawn_chalk_burst(Vector3(body.global_position.x, 0.05, 0.0))
		elif (box_id == 3 or box_id == 4) and prog["outbound_tier"] < 2:
			prog["outbound_tier"] = 2
			GameManager.add_runner_points(2, "%s crossed Line 2 (+2 pts)" % rname)
			runner_line_passed.emit(pid, 2, "LINE 2")
			_spawn_chalk_burst(Vector3(body.global_position.x, 0.05, 5.0))
		elif (box_id == 5 or box_id == 6) and prog["outbound_tier"] < 3:
			prog["outbound_tier"] = 3
			GameManager.add_runner_points(3, "%s crossed Line 3 (+3 pts)" % rname)
			runner_line_passed.emit(pid, 3, "LINE 3")
			_spawn_chalk_burst(Vector3(body.global_position.x, 0.05, 10.0))
	else:
		if (box_id == 5 or box_id == 6) and prog["inbound_tier"] < 1:
			prog["inbound_tier"] = 1
			GameManager.add_runner_points(3, "%s returning: passed Back Line (+3 pts)" % rname)
			runner_line_passed.emit(pid, 3, "BACK RETURN")
			_spawn_chalk_burst(Vector3(body.global_position.x, 0.05, 15.0))
		elif (box_id == 3 or box_id == 4) and prog["inbound_tier"] < 2:
			prog["inbound_tier"] = 2
			GameManager.add_runner_points(4, "%s returning: passed Mid Line (+4 pts)" % rname)
			runner_line_passed.emit(pid, 4, "MID RETURN")
			_spawn_chalk_burst(Vector3(body.global_position.x, 0.05, 10.0))
		elif (box_id == 1 or box_id == 2) and prog["inbound_tier"] < 3:
			prog["inbound_tier"] = 3
			GameManager.add_runner_points(5, "%s returning: passed Front Line (+5 pts)" % rname)
			runner_line_passed.emit(pid, 5, "FRONT RETURN")
			_spawn_chalk_burst(Vector3(body.global_position.x, 0.05, 5.0))

func _physics_process(_delta: float) -> void:
	var players_node := get_node_or_null("../Players")
	if not players_node:
		return
	for child in players_node.get_children():
		if child is CharacterBody3D and _is_runner(child):
			var z_pos: float = child.global_position.z
			var x_pos: float = child.global_position.x
			if z_pos >= -0.2 and z_pos <= 15.2:
				if abs(x_pos) > 5.4:
					child.global_position.x = clamp(child.global_position.x, -5.35, 5.35)
					child.velocity.x = 0.0
			elif abs(x_pos) > 7.0:
				child.global_position.x = clamp(child.global_position.x, -6.8, 6.8)
				child.velocity.x = 0.0

func _on_back_zone_entered(body: Node3D) -> void:
	if not _is_runner(body):
		return
	var pid := _get_runner_id(body)
	var rname := _get_runner_name(body)
	var prog := _get_or_create_progress(pid)
	
	if not prog["has_reached_back"]:
		if prog["outbound_tier"] < 3:
			GameManager.show_combat_banner("⚠️ Must cross all boxes to reach the back!", Color(1.0, 0.6, 0.2))
			return
		prog["has_reached_back"] = true
		prog["outbound_tier"] = 4
		GameManager.add_runner_points(5, "★ %s REACHED THE BACK LINE! (+5 pts) ★" % rname)
		runner_reached_back.emit(pid)
		_spawn_chalk_burst(Vector3(body.global_position.x, 0.05, 15.0))

func _on_home_zone_entered(body: Node3D) -> void:
	if not _is_runner(body):
		return
	var pid := _get_runner_id(body)
	var rname := _get_runner_name(body)
	var prog := _get_or_create_progress(pid)
	
	if prog["has_reached_back"]:
		if prog["inbound_tier"] < 3:
			GameManager.show_combat_banner("⚠️ Must return through all boxes to score home!", Color(1.0, 0.6, 0.2))
			return
		prog["has_reached_back"] = false
		prog["outbound_tier"] = 0
		prog["inbound_tier"] = 0
		GameManager.add_runner_points(20, "🎉 %s SCORED A HOME RUN (PUNTOS)! (+20 pts) 🎉" % rname)
		runner_scored_home.emit(pid)
		_spawn_chalk_burst(Vector3(body.global_position.x, 0.05, 0.0))

func _on_out_of_bounds_entered(body: Node3D) -> void:
	if not _is_runner(body):
		return
	body.global_position.x = clamp(body.global_position.x, -5.35, 5.35)
	body.velocity.x = 0.0

func _on_player_tagged_reset(_runner_name: String, _tagger: String) -> void:
	for pid in runner_progress.keys():
		runner_progress[pid] = { "outbound_tier": 0, "inbound_tier": 0, "has_reached_back": false }
