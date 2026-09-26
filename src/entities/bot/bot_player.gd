extends CharacterBody3D
class_name BotPlayer

# Coordinator: Autonomous Bot Player delegating to modular AI components
# Components: Runner AI (BotRunnerAI), Guard AI (BotGuardAI), Combat (BotTagger)

# Node References
@onready var mesh_body: MeshInstance3D = $MeshInstance3D
@onready var name_label: Label3D = $NameLabel
@onready var tag_cast: ShapeCast3D = $TagCast
@onready var reach_hand: Node3D = $ReachHand

# Component Script Preloads
const BotRunnerAIScript := preload("res://src/entities/bot/components/bot_runner_ai.gd")
const BotGuardAIScript := preload("res://src/entities/bot/components/bot_guard_ai.gd")
const BotTaggerScript := preload("res://src/entities/bot/components/bot_tagger.gd")

# Components (Composition over inheritance)
var runner_ai: Node
var guard_ai: Node
var tagger: Node

@export var role: NetworkManager.Role = NetworkManager.Role.LINE_GUARD_1
@export var bot_name: String = "Bot"
@export var player_name: String = "Bot"
@export var peer_id: int = 0

var is_patotot_on_spine: bool:
	get: return guard_ai.is_patotot_on_spine if guard_ai else false
	set(val):
		if guard_ai: guard_ai.is_patotot_on_spine = val

func _ready() -> void:
	floor_snap_length = 0.2
	floor_constant_speed = true
	floor_stop_on_slope = true
	
	if peer_id == 0:
		peer_id = get_instance_id()
	player_name = "🤖 %s" % bot_name
	collision_layer = 2 # Player/Guard layer
	collision_mask = 1 # Ground/World only (non-contact rules)
	name_label.text = "%s\n[%s]" % [player_name, NetworkManager.get_role_name(role)]
	
	_apply_role_appearance()
	_initialize_components()
	_spawn_at_role_position()

func _initialize_components() -> void:
	tagger = BotTaggerScript.new()
	add_child(tagger)
	tagger.setup(self, tag_cast, reach_hand, mesh_body)
	
	guard_ai = BotGuardAIScript.new()
	add_child(guard_ai)
	guard_ai.setup(self, tagger)
	
	runner_ai = BotRunnerAIScript.new()
	add_child(runner_ai)
	runner_ai.setup(self)

func _physics_process(delta: float) -> void:
	tagger.update_timers(delta)
	
	if role == NetworkManager.Role.RUNNER:
		runner_ai.process_runner(delta)
	elif role == NetworkManager.Role.PATOTOT:
		guard_ai.process_patotot(delta)
	else:
		guard_ai.process_line_guard(delta)
	
	move_and_slide()

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
			var start_x: float = -2.75 if randf() < 0.5 else 2.75
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

func on_tagged() -> void:
	if role == NetworkManager.Role.RUNNER and runner_ai:
		runner_ai.on_tagged()

func on_feinted_by_runner(juke_dir: float, _runner: Node3D) -> void:
	if tagger:
		tagger.on_feinted_by_runner(juke_dir)

func reset_defender_position() -> void:
	if role == NetworkManager.Role.RUNNER:
		return
	velocity = Vector3.ZERO
	if tagger:
		tagger.reset_tagger()
	if guard_ai:
		guard_ai.is_patotot_on_spine = false
	_spawn_at_role_position()
