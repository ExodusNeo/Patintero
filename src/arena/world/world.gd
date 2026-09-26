extends Node3D

@onready var players_container: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var hud: CanvasLayer = $HUD

const PLAYER_SCENE := preload("res://src/entities/player/player.tscn")
const BOT_SCENE := preload("res://src/entities/bot/bot_player.tscn")

func _ready() -> void:
	NetworkManager.player_tagged.connect(_on_player_tagged)
	NetworkManager.player_foul.connect(_on_player_foul)
	if NetworkManager.is_solo_test:
		_spawn_local_player(1)
		_spawn_practice_bots()
	else:
		if multiplayer.is_server():
			multiplayer.peer_connected.connect(_spawn_network_player)
			multiplayer.peer_disconnected.connect(_despawn_network_player)
			# Spawn server host player
			_spawn_network_player(1)
			# Spawn already connected peers if any
			for peer_id in NetworkManager.players.keys():
				if peer_id != 1:
					_spawn_network_player(peer_id)
		
		# Allow a frame for replication, then find our local player
		get_tree().create_timer(0.2).timeout.connect(_link_hud_to_local_player)

func _on_player_tagged(runner_name: String, _tagger_name: String) -> void:
	for child in players_container.get_children():
		if child is CharacterBody3D:
			if "role" in child and child.role == NetworkManager.Role.RUNNER:
				var c_name: String = child.player_name if "player_name" in child else child.bot_name if "bot_name" in child else ""
				if c_name == runner_name or runner_name.contains(c_name) or c_name.contains(runner_name) or runner_name == "Runner":
					var is_falling: bool = child.is_tagged_falling if "is_tagged_falling" in child else false
					if not is_falling and child.has_method("on_tagged"):
						child.on_tagged()
			elif "role" in child and child.role != NetworkManager.Role.RUNNER:
				if child.has_method("reset_defender_position"):
					child.reset_defender_position()

func _on_player_foul(_runner_name: String, _reason: String) -> void:
	# Fouls award points to defense, but do NOT teleport runner back to start
	pass

func _get_initial_role_position(r: NetworkManager.Role) -> Vector3:
	match r:
		NetworkManager.Role.RUNNER:
			return Vector3(0.0, 0.9, -3.5)
		NetworkManager.Role.PATOTOT:
			return Vector3(0.0, 0.9, 0.0)
		NetworkManager.Role.LINE_GUARD_1:
			return Vector3(randf_range(-2.0, 2.0), 0.9, 5.0)
		NetworkManager.Role.LINE_GUARD_2:
			return Vector3(randf_range(-2.0, 2.0), 0.9, 10.0)
		NetworkManager.Role.LINE_GUARD_BACK:
			return Vector3(randf_range(-2.0, 2.0), 0.9, 15.0)
		_:
			return Vector3(0.0, 0.9, 0.0)

func _spawn_local_player(id: int) -> void:
	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.peer_id = id
	player.role = NetworkManager.local_role
	player.player_name = NetworkManager.local_name
	player.position = _get_initial_role_position(player.role)
	players_container.add_child(player)
	hud.set_local_player(player)

func _spawn_practice_bots() -> void:
	var user_role := NetworkManager.local_role
	if user_role == NetworkManager.Role.RUNNER:
		# User is Runner: Spawn full 4-defender gauntlet
		_create_bot("Patotot (Captain)", NetworkManager.Role.PATOTOT)
		_create_bot("Line Guard 1", NetworkManager.Role.LINE_GUARD_1)
		_create_bot("Line Guard 2", NetworkManager.Role.LINE_GUARD_2)
		_create_bot("Back Guard", NetworkManager.Role.LINE_GUARD_BACK)
	else:
		# User is a Defender: Spawn 2 AI Runners + AI teammates on empty lines
		_create_bot("Dodong", NetworkManager.Role.RUNNER)
		_create_bot("Jun-jun", NetworkManager.Role.RUNNER)
		
		var defender_roles := [
			NetworkManager.Role.PATOTOT,
			NetworkManager.Role.LINE_GUARD_1,
			NetworkManager.Role.LINE_GUARD_2,
			NetworkManager.Role.LINE_GUARD_BACK
		]
		for gr in defender_roles:
			if gr != user_role:
				_create_bot(NetworkManager.get_role_name(gr), gr)

func _create_bot(b_name: String, b_role: NetworkManager.Role) -> void:
	var bot: CharacterBody3D = BOT_SCENE.instantiate()
	bot.bot_name = b_name
	bot.role = b_role
	bot.position = _get_initial_role_position(b_role)
	players_container.add_child(bot)

func _spawn_network_player(id: int) -> void:
	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.peer_id = id
	var info: Dictionary = NetworkManager.players.get(id, {})
	player.player_name = info.get("name", "Player %d" % id)
	player.role = info.get("role", NetworkManager.Role.RUNNER)
	player.position = _get_initial_role_position(player.role)
	players_container.add_child(player)

func _despawn_network_player(id: int) -> void:
	var p := players_container.get_node_or_null(str(id))
	if p:
		p.queue_free()

func _link_hud_to_local_player() -> void:
	var my_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var local_p := players_container.get_node_or_null(str(my_id))
	if local_p is CharacterBody3D:
		hud.set_local_player(local_p)
	else:
		for child in players_container.get_children():
			var has_auth: bool = child.is_multiplayer_authority() if multiplayer.has_multiplayer_peer() else true
			if child is CharacterBody3D and has_auth:
				hud.set_local_player(child)
				break
