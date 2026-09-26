extends CharacterBody3D
class_name PlayerController

# Coordinator: First-person player controller delegating to modular components
# Components: Movement (PlayerMovement), Skills (PlayerSkills), Combat (PlayerTagger),
#             View (PlayerCamera), Sound (PlayerAudio)

# Node References
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var mesh_body: MeshInstance3D = $MeshInstance3D
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var tag_cast: ShapeCast3D = $Head/TagCast
@onready var reach_hand: Node3D = $Head/ReachHand
@onready var name_label: Label3D = $NameLabel

# Component Script Preloads
const PlayerMovementScript := preload("res://src/entities/player/components/player_movement.gd")
const PlayerSkillsScript := preload("res://src/entities/player/components/player_skills.gd")
const PlayerTaggerScript := preload("res://src/entities/player/components/player_tagger.gd")
const PlayerCameraScript := preload("res://src/entities/player/components/player_camera.gd")
const PlayerAudioScript := preload("res://src/entities/player/components/player_audio.gd")

# Components (Composition over inheritance)
var movement_comp: Node
var skills_comp: Node
var tagger_comp: Node
var camera_comp: Node
var audio_comp: Node

# Replicated / Public State
@export var peer_id: int = 1
@export var player_name: String = "Player"
@export var role: NetworkManager.Role = NetworkManager.Role.RUNNER
@export var is_patotot_on_spine: bool = false
@export var is_sliding: bool = false
@export var stamina: float = 100.0:
	get:
		return skills_comp.stamina if skills_comp else 100.0
	set(val):
		if skills_comp:
			skills_comp.stamina = val

var is_sprinting: bool = false
var is_crouching: bool = false

# Delegated skill properties for HUD / systems
var slide_cooldown: float:
	get: return skills_comp.slide_cooldown if skills_comp else 0.0
var juke_cooldown: float:
	get: return skills_comp.juke_cooldown if skills_comp else 0.0
var spine_burst_timer: float:
	get: return skills_comp.spine_burst_timer if skills_comp else 0.0
var spine_burst_cooldown: float:
	get: return skills_comp.spine_burst_cooldown if skills_comp else 0.0
var SLIDE_STAMINA_COST: float:
	get: return PlayerSkillsScript.SLIDE_STAMINA_COST
var JUKE_STAMINA_COST: float:
	get: return PlayerSkillsScript.JUKE_STAMINA_COST

# Delegated combat properties for HUD / systems
var is_charging_tag: bool:
	get: return tagger_comp.is_charging_tag if tagger_comp else false
var tag_charge_time: float:
	get: return tagger_comp.tag_charge_time if tagger_comp else 0.0
var MAX_TAG_CHARGE: float:
	get: return tagger_comp.MAX_TAG_CHARGE if tagger_comp else 0.55
var tag_recovery_stun: float:
	get: return tagger_comp.tag_recovery_stun if tagger_comp else 0.0
	set(val):
		if tagger_comp:
			tagger_comp.tag_recovery_stun = val

func _ready() -> void:
	floor_snap_length = 0.2
	floor_constant_speed = true
	floor_stop_on_slope = true
	collision_layer = 2 # Player/Guard layer
	collision_mask = 1 # Ground/World layer (non-contact rules)
	
	if name.is_valid_int():
		peer_id = name.to_int()
	set_multiplayer_authority(peer_id)
	
	if NetworkManager.players.has(peer_id):
		var info: Dictionary = NetworkManager.players[peer_id]
		player_name = info.get("name", "Player")
		role = info.get("role", NetworkManager.Role.RUNNER)
	
	name_label.text = "%s\n[%s]" % [player_name, NetworkManager.get_role_name(role)]
	_apply_role_appearance()
	_initialize_components()
	
	if is_multiplayer_authority():
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mesh_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		name_label.visible = false
		_spawn_at_role_position()
	else:
		camera.current = false
		reach_hand.visible = false

func _initialize_components() -> void:
	camera_comp = PlayerCameraScript.new()
	add_child(camera_comp)
	camera_comp.setup(self, head, camera)
	
	skills_comp = PlayerSkillsScript.new()
	add_child(skills_comp)
	skills_comp.setup(self, collision_shape, mesh_body, camera_comp)
	
	movement_comp = PlayerMovementScript.new()
	add_child(movement_comp)
	movement_comp.setup(self, skills_comp)
	
	tagger_comp = PlayerTaggerScript.new()
	add_child(tagger_comp)
	tagger_comp.setup(self, head, tag_cast, reach_hand)
	
	audio_comp = PlayerAudioScript.new()
	add_child(audio_comp)
	audio_comp.setup(self)

func _exit_tree() -> void:
	if audio_comp:
		audio_comp.cleanup()

func _unhandled_input(event: InputEvent) -> void:
	if camera_comp:
		camera_comp.handle_input(event)
	
	if is_multiplayer_authority() and role == NetworkManager.Role.PATOTOT:
		if event.is_action_pressed("switch_axis"):
			movement_comp.toggle_patotot_axis()

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	
	skills_comp.update_skills(delta)
	movement_comp.process_movement(delta)
	tagger_comp.update_tagger(delta)
	camera_comp.update_look_and_dynamics(delta)
	audio_comp.update_audio(delta)
	
	# Keep replicated is_sliding in sync
	is_sliding = skills_comp.is_sliding

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
			global_position = Vector3(0, 0.9, -3.5)
			rotation.y = deg_to_rad(180)
		NetworkManager.Role.PATOTOT:
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

func on_tagged() -> void:
	if role == NetworkManager.Role.RUNNER:
		if skills_comp and skills_comp.is_sliding:
			skills_comp.stop_slide()
		global_position = Vector3(0, 0.9, -3.5)
		velocity = Vector3.ZERO
		stamina = 100.0
		AudioManager.set_low_stamina_active(false, 0.0)

func reset_defender_position() -> void:
	if role == NetworkManager.Role.RUNNER:
		return
	velocity = Vector3.ZERO
	if tagger_comp:
		tagger_comp.tag_cooldown = 0.6
		tagger_comp.tag_recovery_stun = 0.0
	is_patotot_on_spine = false
	_spawn_at_role_position()
