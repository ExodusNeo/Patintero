extends Node
class_name PlayerCamera

# Component: First-person camera, mouse look, head bobbing, lean, and dynamic FOV
# godot-animation / input-systems

const MOUSE_SENSITIVITY: float = 0.0022
const JOYPAD_SENSITIVITY: float = 2.8
const HEAD_BASE_Y: float = 0.65
const BOB_FREQUENCY: float = 12.0
const BOB_AMPLITUDE: float = 0.045

var player: CharacterBody3D
var head: Node3D
var camera: Camera3D

var bob_timer: float = 0.0
var target_cam_tilt: float = 0.0

func setup(p: CharacterBody3D, h: Node3D, cam: Camera3D) -> void:
	player = p
	head = h
	camera = cam

func handle_input(event: InputEvent) -> void:
	if not player.is_multiplayer_authority():
		return
	
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-80), deg_to_rad(80))
	
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func update_look_and_dynamics(delta: float) -> void:
	if not player.is_multiplayer_authority():
		return
	
	_handle_joypad_look(delta)
	_handle_head_bob(delta)
	_handle_camera_tilt(delta)
	_handle_dynamic_fov(delta)

func _handle_joypad_look(delta: float) -> void:
	var look_x := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var look_y := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if abs(look_x) > 0.12:
		player.rotate_y(-look_x * JOYPAD_SENSITIVITY * delta)
	if abs(look_y) > 0.12:
		head.rotate_x(-look_y * JOYPAD_SENSITIVITY * delta)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-80), deg_to_rad(80))

func _handle_head_bob(delta: float) -> void:
	if player.is_sliding:
		head.position.y = -0.15
		return
	
	var horizontal_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	if player.is_on_floor() and horizontal_speed > 0.5:
		var speed_mult: float = 1.35 if player.is_sprinting else 1.0
		bob_timer += delta * BOB_FREQUENCY * speed_mult
		var bob_offset: float = sin(bob_timer) * BOB_AMPLITUDE
		head.position.y = HEAD_BASE_Y + bob_offset
	else:
		bob_timer = 0.0
		head.position.y = move_toward(head.position.y, HEAD_BASE_Y, 2.0 * delta)

func _handle_camera_tilt(delta: float) -> void:
	target_cam_tilt = 0.0
	
	if player.is_sliding:
		target_cam_tilt = deg_to_rad(-6.0)
	elif player.role == NetworkManager.Role.LINE_GUARD_1 or player.role == NetworkManager.Role.LINE_GUARD_2 or player.role == NetworkManager.Role.LINE_GUARD_BACK:
		# Defensive leaning
		if Input.is_action_pressed("juke_left"):
			target_cam_tilt = deg_to_rad(7.5)
		elif Input.is_action_pressed("juke_right"):
			target_cam_tilt = deg_to_rad(-7.5)
	
	camera.rotation.z = lerp_angle(camera.rotation.z, target_cam_tilt, 10.0 * delta)

func _handle_dynamic_fov(delta: float) -> void:
	var target_fov: float = 85.0
	if player.is_patotot_on_spine and player.spine_burst_timer > 0.0:
		target_fov = 96.0
	elif player.is_sprinting and player.velocity.length() > 2.0:
		target_fov = 94.0
	
	camera.fov = lerp(camera.fov, target_fov, 8.0 * delta)

func apply_juke_tilt(dir_lateral: float) -> void:
	camera.rotation.z = deg_to_rad(dir_lateral * -8.0)
