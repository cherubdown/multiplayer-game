extends Node
## Autoload that owns the ENet peer and exposes the three launch modes:
## listen server (host and play), client, and headless dedicated server.
##
## A server can have a password. Every client sends one (maybe empty) during
## SceneMultiplayer's authentication step, before it counts as connected, so a
## client with the wrong password never gets to send RPCs or log in.

signal status_changed(text: String)
signal peers_changed(peer_ids: Array[int])

enum Mode { OFFLINE, HOST, CLIENT, DEDICATED_SERVER }

const DEFAULT_PORT := 7777
const DEFAULT_ADDRESS := "127.0.0.1"
const MAX_PLAYERS := 10
## What the server answers a client's password with.
const AUTH_OK := "ok"
const AUTH_WRONG_PASSWORD := "wrong_password"

## Sent when a client is turned away for a wrong server password.
signal wrong_password

var mode: Mode = Mode.OFFLINE
var port: int = DEFAULT_PORT

## Set by the server over RPC so clients know whether peer 1 is a player.
var _server_is_dedicated := false
## Server: the password clients must send, or "" to let anyone in.
## Client: the password to send.
var _password := ""
var _rejected := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_authenticating.connect(_on_peer_authenticating)
	multiplayer.peer_authentication_failed.connect(_on_peer_authentication_failed)
	multiplayer.auth_callback = _on_auth_data


## Starts a listen server: this instance is the server and also a player.
## Only clients that send `password` can join; "" lets anyone in.
func host(p_port: int = DEFAULT_PORT, password: String = "") -> Error:
	var err := _create_server(p_port, password)
	if err == OK:
		mode = Mode.HOST
		_set_status("Hosting on port %d%s" % [p_port, _password_note()])
		_emit_peers()
	return err


## Starts a headless dedicated server: no local player, no rendering.
func start_dedicated_server(p_port: int = DEFAULT_PORT, password: String = "") -> Error:
	var err := _create_server(p_port, password)
	if err == OK:
		mode = Mode.DEDICATED_SERVER
		_set_status("Dedicated server listening on port %d%s" % [p_port, _password_note()])
	return err


## `password` is the server's password, or "" if it has none.
func join(address: String = DEFAULT_ADDRESS, p_port: int = DEFAULT_PORT, password: String = "") -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, p_port)
	if err != OK:
		_set_status("Could not connect to %s:%d (%s)" % [address, p_port, error_string(err)])
		return err
	_password = password
	_rejected = false
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
	_password = ""
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


func _create_server(p_port: int, password: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(p_port, MAX_PLAYERS)
	if err != OK:
		_set_status("Could not listen on port %d (%s)" % [p_port, error_string(err)])
		return err
	_password = password
	multiplayer.multiplayer_peer = peer
	port = p_port
	return OK


func _password_note() -> String:
	return " (password required)" if _password != "" else ""


# --- Server password --------------------------------------------------------

func _on_peer_authenticating(id: int) -> void:
	# The client speaks first; the server waits for its password.
	if not multiplayer.is_server():
		multiplayer.send_auth(id, _password.to_utf8_buffer())
		multiplayer.complete_auth(id)


func _on_auth_data(id: int, data: PackedByteArray) -> void:
	if not multiplayer.is_server():
		_rejected = data.get_string_from_utf8() == AUTH_WRONG_PASSWORD
		return
	if _password == "" or _hashes_match(data, _password.to_utf8_buffer()):
		multiplayer.send_auth(id, AUTH_OK.to_utf8_buffer())
		multiplayer.complete_auth(id)
		return
	print("Peer %d sent a wrong server password" % id)
	multiplayer.send_auth(id, AUTH_WRONG_PASSWORD.to_utf8_buffer())
	# Give the answer time to arrive before hanging up.
	await get_tree().create_timer(0.5).timeout
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer and id in multiplayer.get_authenticating_peers():
		multiplayer.disconnect_peer(id)


func _on_peer_authentication_failed(id: int) -> void:
	if multiplayer.is_server() or id != 1:
		return
	var rejected := _rejected
	# Swapping the peer while it is still emitting this signal crashes Godot.
	await get_tree().process_frame
	disconnect_from_game()
	if rejected:
		_set_status("Wrong server password")
		wrong_password.emit()
	else:
		_set_status("Connection failed")


## Compares SHA-256 digests so the time taken doesn't depend on how much of
## the password matched.
func _hashes_match(a: PackedByteArray, b: PackedByteArray) -> bool:
	var ha := _sha256(a)
	var hb := _sha256(b)
	var diff := 0
	for i in ha.size():
		diff |= ha[i] ^ hb[i]
	return diff == 0


func _sha256(data: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	if not data.is_empty():
		ctx.update(data)
	return ctx.finish()


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
