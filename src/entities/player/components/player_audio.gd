extends Node
class_name PlayerAudio

# Component: Player footsteps, breathing cadence, and stamina audio
# godot-audio / audio-design

var player: CharacterBody3D
var footstep_timer: float = 0.0

func setup(p: CharacterBody3D) -> void:
	player = p

func update_audio(delta: float) -> void:
	if not player.is_multiplayer_authority():
		return
	
	_handle_footsteps(delta)
	_handle_stamina_audio()

func _handle_footsteps(delta: float) -> void:
	var horizontal_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	if player.is_on_floor() and horizontal_speed > 0.5 and not player.is_sliding:
		var interval: float = 0.44
		if player.is_sprinting:
			interval = 0.28
		elif player.is_crouching:
			interval = 0.62
		
		footstep_timer += delta
		if footstep_timer >= interval:
			footstep_timer = 0.0
			AudioManager.play_footstep()
	else:
		footstep_timer = 0.0

func _handle_stamina_audio() -> void:
	if player.role != NetworkManager.Role.RUNNER:
		return
	
	if player.stamina < 25.0:
		var intensity: float = (25.0 - player.stamina) / 25.0
		AudioManager.set_low_stamina_active(true, intensity)
	else:
		AudioManager.set_low_stamina_active(false, 0.0)

func cleanup() -> void:
	if player.is_multiplayer_authority() and player.role == NetworkManager.Role.RUNNER:
		AudioManager.set_low_stamina_active(false, 0.0)
