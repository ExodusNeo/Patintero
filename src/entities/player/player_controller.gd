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
@onready var viewmodel: TsinelasViewmodel = $Head/Viewmodel
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
var is_tagged_falling: bool = false

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

func has_authority() -> bool:
	return is_multiplayer_authority() if multiplayer.has_multiplayer_peer() else true

func _ready() -> void:
	floor_snap_length = 0.2
	floor_constant_speed = true
	floor_stop_on_slope = true
	collision_layer = 2 # Player/Guard layer
	collision_mask = 1 # Ground/World layer (non-contact rules)
	
	if name.is_valid_int():
		peer_id = name.to_int()
	if multiplayer.has_multiplayer_peer():
		set_multiplayer_authority(peer_id)
	
	if NetworkManager.players.has(peer_id):
		var info: Dictionary = NetworkManager.players[peer_id]
		player_name = info.get("name", "Player")
		role = info.get("role", NetworkManager.Role.RUNNER)
	
	name_label.text = "%s\n[%s]" % [player_name, NetworkManager.get_role_name(role)]
	_apply_role_appearance()
	_initialize_components()
	
	if has_authority():
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mesh_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		name_label.visible = false
		if viewmodel:
			viewmodel.configure_role(role)
		_spawn_at_role_position()
	else:
		camera.current = false
		if viewmodel:
			viewmodel.visible = false

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
	tagger_comp.setup(self, head, tag_cast, viewmodel)
	
	audio_comp = PlayerAudioScript.new()
	add_child(audio_comp)
	audio_comp.setup(self)

func _exit_tree() -> void:
	if audio_comp:
		audio_comp.cleanup()

func _unhandled_input(event: InputEvent) -> void:
	if camera_comp:
		camera_comp.handle_input(event)
	
	if has_authority() and role == NetworkManager.Role.PATOTOT:
		if event.is_action_pressed("switch_axis"):
			movement_comp.toggle_patotot_axis()

func _physics_process(delta: float) -> void:
	if not has_authority():
		return
	
	if is_tagged_falling:
		if not is_on_floor():
			velocity.y -= 18.0 * delta
		else:
			# Decelerate stumble velocity realistically with ground friction
			velocity.x = move_toward(velocity.x, 0.0, 7.5 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 7.5 * delta)
		move_and_slide()
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
	var z_map := { NetworkManager.Role.RUNNER: -3.5, NetworkManager.Role.PATOTOT: 0.0, NetworkManager.Role.LINE_GUARD_1: 5.0, NetworkManager.Role.LINE_GUARD_2: 10.0, NetworkManager.Role.LINE_GUARD_BACK: 15.0 }
	global_position = Vector3(0, 0.9, z_map.get(role, 0.0))
	rotation.y = deg_to_rad(180) if role == NetworkManager.Role.RUNNER else 0.0

func on_tagged() -> void:
	if role != NetworkManager.Role.RUNNER or is_tagged_falling:
		return
	
	is_tagged_falling = true
	is_sprinting = false
	if movement_comp:
		movement_comp.is_sprinting = false
	if skills_comp and skills_comp.is_sliding:
		skills_comp.stop_slide()
	AudioManager.set_low_stamina_active(false, 0.0)
	
	var hud: Node = get_tree().root.find_child("HUD", true, false)
	if hud and hud.has_method("play_tagged_impact_flash"):
		hud.play_tagged_impact_flash()
	
	# --- PHASE 1: STUMBLE & LOSS OF BALANCE (0.0s - 0.38s) ---
	# Runner staggers backward/off-balance with ground friction
	var stagger_dir := -transform.basis.z * 3.0
	velocity = stagger_dir
	AudioManager.play_footstep(1.3)
	if viewmodel:
		viewmodel.play_stumble()
	
	# Stumble camera dynamics: head jolts back, tilts unsteadily, knees buckle
	var stumble_tw := create_tween().set_parallel(true)
	stumble_tw.tween_property(head, "position:y", 0.48, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	stumble_tw.tween_property(head, "position:z", 0.12, 0.22)
	stumble_tw.tween_property(camera, "rotation:z", deg_to_rad(-16.0), 0.22).set_trans(Tween.TRANS_QUAD)
	stumble_tw.tween_property(head, "rotation:x", deg_to_rad(10.0), 0.20)
	
	await get_tree().create_timer(0.38).timeout
	
	# --- PHASE 2: LOSS OF FOOTING & ASPHALT COLLAPSE (0.38s - 0.86s) ---
	# Knees give out completely, 3D body & camera plunge to the pavement
	var fall_tw := create_tween().set_parallel(true)
	fall_tw.tween_property(mesh_body, "rotation:z", deg_to_rad(85.0), 0.48).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	fall_tw.tween_property(mesh_body, "position:y", -0.45, 0.48)
	fall_tw.tween_property(head, "position:y", -0.36, 0.44).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	fall_tw.tween_property(camera, "rotation:z", deg_to_rad(76.0), 0.46).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fall_tw.tween_property(head, "rotation:x", deg_to_rad(-15.0), 0.42)
	fall_tw.tween_property(head, "position:z", 0.0, 0.35)
	if viewmodel:
		viewmodel.play_knockdown()
	
	# Heavy pavement impact thud right as cheek/body hits the asphalt
	get_tree().create_timer(0.30).timeout.connect(func(): AudioManager.play_knockdown_thud())
	await fall_tw.finished
	
	# --- PHASE 3: DAZED ON ASPHALT & SMOOTH FADE TO PITCH BLACK ---
	# Lying flat on pavement for a brief beat before vision plunges to black
	await get_tree().create_timer(0.30).timeout
	if hud and hud.has_method("fade_to_black"):
		await hud.fade_to_black(0.50)
	else:
		await get_tree().create_timer(0.50).timeout
	
	# --- PHASE 4: SILENT RESPAWN UNDER 100% PITCH BLACK OPAQUE CURTAIN ---
	# The screen is now GUARANTEED 100% pitch black. Zero visibility.
	global_position = Vector3(0.0, 0.9, -3.5)
	rotation.y = deg_to_rad(180.0)
	velocity = Vector3.ZERO
	stamina = 100.0
	
	# Cleanly reset camera and body transforms upright in complete darkness
	mesh_body.rotation.z = 0.0
	mesh_body.position.y = 0.0
	head.position = Vector3(0.0, 0.65, 0.0)
	camera.rotation = Vector3.ZERO
	head.rotation = Vector3.ZERO
	if viewmodel:
		viewmodel.reset_from_knockdown_instant()
	
	# Generous pause in pure blackness (0.45s) to guarantee camera is settled upright
	await get_tree().create_timer(0.45).timeout
	
	# --- PHASE 5: FADE IN FROM BLACK & RESTORE CONTROLS ---
	# Smoothly reveal the arena only after everything is already standing upright
	if hud and hud.has_method("fade_from_black"):
		await hud.fade_from_black(0.65)
	else:
		await get_tree().create_timer(0.65).timeout
	
	# Once vision has fully returned, restore player locomotion
	velocity = Vector3.ZERO
	is_tagged_falling = false

func reset_defender_position() -> void:
	if role == NetworkManager.Role.RUNNER:
		return
	velocity = Vector3.ZERO
	if tagger_comp:
		tagger_comp.tag_cooldown = 0.6
		tagger_comp.tag_recovery_stun = 0.0
	is_patotot_on_spine = false
	_spawn_at_role_position()
