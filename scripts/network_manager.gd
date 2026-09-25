extends Node

# Autoload: NetworkManager

enum Role {
	RUNNER,
	PATOTOT,       # Front Line (Z=0) + Center Spine (X=0)
	LINE_GUARD_1,  # Mid Line 1 (Z=4)
	LINE_GUARD_2,  # Mid Line 2 (Z=8)
	LINE_GUARD_BACK # Back Line (Z=12)
}

const DEFAULT_PORT := 7000
const MAX_PLAYERS := 10

signal players_updated
signal player_tagged(runner_name: String, tagger_name: String)
signal player_foul(player_name: String, reason: String)
signal game_started

var players: Dictionary = {} # id -> { "name": String, "role": Role }
var local_name: String = "Boyet"
var local_role: Role = Role.RUNNER
var is_solo_test: bool = false

func _ready() -> void:
	_setup_default_inputs()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _setup_default_inputs() -> void:
	_add_key_action("move_forward", [KEY_W, KEY_UP])
	_add_key_action("move_backward", [KEY_S, KEY_DOWN])
	_add_key_action("move_left", [KEY_A, KEY_LEFT])
	_add_key_action("move_right", [KEY_D, KEY_RIGHT])
	_add_key_action("sprint", [KEY_SHIFT])
	_add_key_action("jump", [KEY_SPACE])
	_add_key_action("crouch", [KEY_CTRL, KEY_C])
	_add_key_action("switch_axis", [KEY_E, KEY_TAB])
	_add_mouse_action("tag", MOUSE_BUTTON_LEFT)
	_add_key_action("tag_key", [KEY_F, KEY_SPACE])

func _add_key_action(action_name: String, keys: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		for k in keys:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action_name, ev)

func _add_mouse_action(action_name: String, button_index: MouseButton) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		var ev := InputEventMouseButton.new()
		ev.button_index = button_index
		InputMap.action_add_event(action_name, ev)

func host_game(player_name: String, role: Role, port: int = DEFAULT_PORT) -> Error:
	is_solo_test = false
	local_name = player_name
	local_role = role
	
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("Failed to host on port %d: %s" % [port, err])
		return err
	
	multiplayer.multiplayer_peer = peer
	players[1] = {
		"name": local_name,
		"role": local_role
	}
	players_updated.emit()
	return OK

func join_game(ip: String, player_name: String, role: Role, port: int = DEFAULT_PORT) -> Error:
	is_solo_test = false
	local_name = player_name
	local_role = role
	
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		push_error("Failed to connect to %s:%d: %s" % [ip, port, err])
		return err
	
	multiplayer.multiplayer_peer = peer
	return OK

func start_solo_test(selected_role: Role, player_name: String = "SoloTester") -> void:
	is_solo_test = true
	local_name = player_name
	local_role = selected_role
	players[1] = {
		"name": local_name,
		"role": local_role
	}
	game_started.emit()
	get_tree().change_scene_to_file("res://scenes/world.tscn")

func start_multiplayer_match() -> void:
	if multiplayer.is_server():
		load_world.rpc()

@rpc("authority", "call_local", "reliable")
func load_world() -> void:
	game_started.emit()
	get_tree().change_scene_to_file("res://scenes/world.tscn")

func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	players.erase(id)
	players_updated.emit()

func _on_connected_to_server() -> void:
	print("Connected to server! Registering...")
	register_player.rpc_id(1, {
		"name": local_name,
		"role": local_role
	})

func _on_connection_failed() -> void:
	push_error("Connection failed!")
	multiplayer.multiplayer_peer = null

func _on_server_disconnected() -> void:
	print("Server disconnected.")
	players.clear()
	multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

@rpc("any_peer", "reliable")
func register_player(info: Dictionary) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	players[sender_id] = info
	# Sync full roster to all peers
	sync_players.rpc(players)
	players_updated.emit()

@rpc("authority", "reliable")
func sync_players(roster: Dictionary) -> void:
	players = roster
	players_updated.emit()

@rpc("any_peer", "call_local", "reliable")
func report_tag(runner_id: int, tagger_id: int, runner_fallback: String = "Runner", tagger_fallback: String = "Guard") -> void:
	var r_name: String = players.get(runner_id, {}).get("name", runner_fallback)
	var t_name: String = players.get(tagger_id, {}).get("name", tagger_fallback)
	player_tagged.emit(r_name, t_name)

@rpc("any_peer", "call_local", "reliable")
func report_foul(player_id: int, reason: String) -> void:
	var p_name: String = players.get(player_id, {}).get("name", "Player")
	player_foul.emit(p_name, reason)

func get_role_name(role: Role) -> String:
	match role:
		Role.RUNNER:
			return "Runner (Tawid)"
		Role.PATOTOT:
			return "Patotot (Captain / Center Spine)"
		Role.LINE_GUARD_1:
			return "Line Guard 1 (Line 2)"
		Role.LINE_GUARD_2:
			return "Line Guard 2 (Line 3)"
		Role.LINE_GUARD_BACK:
			return "Back Guard (Line 4)"
		_:
			return "Unknown"
