extends Node3D

@onready var players_container: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var hud: CanvasLayer = $HUD

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const BOT_SCENE := preload("res://scenes/bot_player.tscn")

func _ready() -> void:
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

func _spawn_local_player(id: int) -> void:
	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.peer_id = id
	player.role = NetworkManager.local_role
	player.player_name = NetworkManager.local_name
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
	players_container.add_child(bot)

func _spawn_network_player(id: int) -> void:
	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.peer_id = id
	var info: Dictionary = NetworkManager.players.get(id, {})
	player.player_name = info.get("name", "Player %d" % id)
	player.role = info.get("role", NetworkManager.Role.RUNNER)
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
			if child is CharacterBody3D and child.is_multiplayer_authority():
				hud.set_local_player(child)
				break
