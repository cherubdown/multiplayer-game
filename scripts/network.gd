extends Node
## Autoload that owns the ENet peer and exposes the three launch modes:
## listen server (host and play), client, and headless dedicated server.

signal status_changed(text: String)
signal peers_changed(peer_ids: Array[int])

enum Mode { OFFLINE, HOST, CLIENT, DEDICATED_SERVER }

const DEFAULT_PORT := 7777
const DEFAULT_ADDRESS := "127.0.0.1"
const MAX_PLAYERS := 10

var mode: Mode = Mode.OFFLINE
var port: int = DEFAULT_PORT

## Set by the server over RPC so clients know whether peer 1 is a player.
var _server_is_dedicated := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Starts a listen server: this instance is the server and also a player.
func host(p_port: int = DEFAULT_PORT) -> Error:
	var err := _create_server(p_port)
	if err == OK:
		mode = Mode.HOST
		_set_status("Hosting on port %d" % p_port)
		_emit_peers()
	return err


## Starts a headless dedicated server: no local player, no rendering.
func start_dedicated_server(p_port: int = DEFAULT_PORT) -> Error:
	var err := _create_server(p_port)
	if err == OK:
		mode = Mode.DEDICATED_SERVER
		_set_status("Dedicated server listening on port %d" % p_port)
	return err


func join(address: String = DEFAULT_ADDRESS, p_port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, p_port)
	if err != OK:
		_set_status("Could not connect to %s:%d (%s)" % [address, p_port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	port = p_port
	_set_status("Connecting to %s:%d..." % [address, p_port])
	return OK


func disconnect_from_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE
	_server_is_dedicated = false
	_set_status("Offline")
	peers_changed.emit([] as Array[int])


func is_dedicated_server() -> bool:
	return mode == Mode.DEDICATED_SERVER


## Every peer taking part as a player. A dedicated server (id 1) is not a player.
func player_ids() -> Array[int]:
	var ids: Array[int] = []
	if mode == Mode.OFFLINE:
		return ids
	if mode != Mode.DEDICATED_SERVER:
		ids.append(multiplayer.get_unique_id())
	for id in multiplayer.get_peers():
		if id == 1 and mode == Mode.CLIENT and _server_is_dedicated:
			continue
		ids.append(id)
	ids.sort()
	return ids


@rpc("authority", "call_remote", "reliable")
func _set_server_is_dedicated(value: bool) -> void:
	_server_is_dedicated = value
	_emit_peers()


func _create_server(p_port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(p_port, MAX_PLAYERS)
	if err != OK:
		_set_status("Could not listen on port %d (%s)" % [p_port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	port = p_port
	return OK


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_set_server_is_dedicated.rpc_id(id, mode == Mode.DEDICATED_SERVER)
		print("Peer %d connected" % id)
	_emit_peers()


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		print("Peer %d disconnected" % id)
	_emit_peers()


func _on_connected_to_server() -> void:
	_set_status("Connected as peer %d" % multiplayer.get_unique_id())
	_emit_peers()


func _on_connection_failed() -> void:
	disconnect_from_game()
	_set_status("Connection failed")


func _on_server_disconnected() -> void:
	disconnect_from_game()
	_set_status("Server closed the connection")


func _emit_peers() -> void:
	peers_changed.emit(player_ids())


func _set_status(text: String) -> void:
	print(text)
	status_changed.emit(text)
