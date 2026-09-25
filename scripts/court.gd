extends Node3D
class_name PatinteroCourt

signal runner_reached_back(runner_id: int)
signal runner_scored_home(runner_id: int)
signal out_of_bounds_triggered(runner_id: int)
signal runner_entered_box(runner_id: int, box_id: int)

# Track runner progress: peer_id -> bool (has reached back line)
var runners_reached_back: Dictionary = {}
var runner_current_box: Dictionary = {}

func _ready() -> void:
	$BackZone.body_entered.connect(_on_back_zone_entered)
	$HomeZone.body_entered.connect(_on_home_zone_entered)
	$OutOfBoundsLeft.body_entered.connect(_on_out_of_bounds_entered)
	$OutOfBoundsRight.body_entered.connect(_on_out_of_bounds_entered)
	
	# Connect Box Quadrant Triggers
	for i in range(1, 7):
		var box_node := get_node_or_null("Boxes/Box%d" % i)
		if box_node is Area3D:
			box_node.body_entered.connect(_on_box_entered.bind(i))

func _is_runner(body: Node3D) -> bool:
	return "role" in body and body.role == NetworkManager.Role.RUNNER

func _get_runner_id(body: Node3D) -> int:
	if "peer_id" in body and body.peer_id != 0:
		return body.peer_id
	return body.get_instance_id()

func _on_box_entered(body: Node3D, box_id: int) -> void:
	if _is_runner(body):
		var pid := _get_runner_id(body)
		runner_current_box[pid] = box_id
		runner_entered_box.emit(pid, box_id)

func _on_back_zone_entered(body: Node3D) -> void:
	if _is_runner(body):
		var pid := _get_runner_id(body)
		if not runners_reached_back.get(pid, false):
			runners_reached_back[pid] = true
			runner_reached_back.emit(pid)

func _on_home_zone_entered(body: Node3D) -> void:
	if _is_runner(body):
		var pid := _get_runner_id(body)
		if runners_reached_back.get(pid, false):
			runners_reached_back[pid] = false
			runner_scored_home.emit(pid)

func _on_out_of_bounds_entered(body: Node3D) -> void:
	if _is_runner(body):
		if body.global_position.z >= -0.5 and body.global_position.z <= 12.5:
			var pid := _get_runner_id(body)
			out_of_bounds_triggered.emit(pid)
			var p_name: String = body.player_name if "player_name" in body else "Runner"
			NetworkManager.trigger_foul(pid, "%s Stepped Out of Bounds!" % p_name)
