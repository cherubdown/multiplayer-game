extends Node
## Autoload for logging in and picking a character.
##
## The server (host or dedicated) owns the accounts in an AccountStore. After
## connecting, a client registers or logs in, manages its characters, then asks
## to enter the world with one of them. The server only spawns a player for a
## peer once that peer has entered the world.
##
## Requests go to peer 1 and answers come back to the asking peer. Every RPC is
## call_local so the host, which is peer 1 itself, uses the same path.

## Client side: the server answered a register or login request.
signal login_finished(ok: bool, message: String)
## Client side: the character list changed, with an error message if a
## request failed.
signal characters_changed(characters: Array, message: String)
## Client side: the server put this client in the world, or took it out.
signal entered_world(character_name: String)
signal left_world
## Every peer: the characters currently in the world, keyed by peer id.
signal roster_changed(roster: Dictionary)
## Client side: about to ask the server to leave the world. The local player
## stops syncing its input so none arrives after the server despawns it.
signal leaving_world

## Server side: spawn or despawn this peer's player.
signal player_entered(peer_id: int, character_name: String)
signal player_left(peer_id: int)

# Preloaded rather than a class_name so it resolves on a fresh checkout that
# hasn't been imported in the editor (no global class cache yet).
const AccountStore := preload("res://scripts/account_store.gd")
const MAX_FAILED_LOGINS := 5

## Client side state.
var username := ""
var characters: Array = []
var character_name := ""
var roster := {}

## Server side state.
var _store: AccountStore
var _usernames := {}          # peer id -> logged in username (lowercase)
var _in_world := {}           # peer id -> character name
var _failed_logins := {}      # peer id -> count


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func is_logged_in() -> bool:
	return username != ""


## Server side: every peer currently in the world, keyed by peer id.
func players_in_world() -> Dictionary:
	return _in_world.duplicate()


## Forgets everything, on both sides. Called when leaving a game.
func reset() -> void:
	username = ""
	characters = []
	character_name = ""
	roster = {}
	_usernames.clear()
	_in_world.clear()
	_failed_logins.clear()


# --- Client API -------------------------------------------------------------

func register(p_username: String, password: String) -> void:
	_request_register.rpc_id(1, p_username, password)


func login(p_username: String, password: String) -> void:
	_request_login.rpc_id(1, p_username, password)


func logout() -> void:
	_request_logout.rpc_id(1)
	username = ""
	characters = []
	character_name = ""


func create_character(p_name: String) -> void:
	_request_create_character.rpc_id(1, p_name)


func delete_character(p_name: String) -> void:
	_request_delete_character.rpc_id(1, p_name)


func enter_world(p_name: String) -> void:
	_request_enter_world.rpc_id(1, p_name)


## Back to character select without disconnecting.
func leave_world() -> void:
	if character_name == "":
		return
	leaving_world.emit()
	# Give input packets already on the wire time to land first.
	await get_tree().create_timer(0.25).timeout
	_request_leave_world.rpc_id(1)


# --- Server side requests ---------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func _request_register(p_username, password) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if _usernames.has(peer) or not (p_username is String and password is String):
		return
	var err := _accounts().register(p_username, password)
	if err != "":
		_login_result.rpc_id(peer, false, err, "", [])
		return
	print("Account %s created by peer %d" % [p_username, peer])
	_finish_login(peer, p_username)


@rpc("any_peer", "call_local", "reliable")
func _request_login(p_username, password) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if _usernames.has(peer) or not (p_username is String and password is String):
		return
	var err := _accounts().verify(p_username, password)
	if err == "" and p_username.to_lower() in _usernames.values():
		err = "That account is already logged in."
	if err != "":
		_failed_logins[peer] = _failed_logins.get(peer, 0) + 1
		_login_result.rpc_id(peer, false, err, "", [])
		if _failed_logins[peer] >= MAX_FAILED_LOGINS and peer != 1:
			print("Disconnecting peer %d after %d failed logins" % [peer, MAX_FAILED_LOGINS])
			multiplayer.multiplayer_peer.disconnect_peer(peer)
		return
	_finish_login(peer, p_username)


@rpc("any_peer", "call_local", "reliable")
func _request_logout() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	_remove_from_world(peer)
	_usernames.erase(peer)


@rpc("any_peer", "call_local", "reliable")
func _request_create_character(p_name) -> void:
	var peer := _logged_in_sender()
	if peer == 0 or not p_name is String:
		return
	var account: String = _usernames[peer]
	var err := _accounts().create_character(account, p_name)
	_characters_result.rpc_id(peer, _accounts().list_characters(account), err)


@rpc("any_peer", "call_local", "reliable")
func _request_delete_character(p_name) -> void:
	var peer := _logged_in_sender()
	if peer == 0 or not p_name is String:
		return
	var account: String = _usernames[peer]
	var err := ""
	if _in_world.get(peer, "").to_lower() == p_name.to_lower():
		err = "Leave the world before deleting that character."
	else:
		err = _accounts().delete_character(account, p_name)
	_characters_result.rpc_id(peer, _accounts().list_characters(account), err)


@rpc("any_peer", "call_local", "reliable")
func _request_enter_world(p_name) -> void:
	var peer := _logged_in_sender()
	if peer == 0 or not p_name is String or _in_world.has(peer):
		return
	var account: String = _usernames[peer]
	if not _accounts().has_character(account, p_name):
		_characters_result.rpc_id(peer, _accounts().list_characters(account), "No character called %s." % p_name)
		return
	for character in _accounts().list_characters(account):
		if str(character["name"]).to_lower() == p_name.to_lower():
			p_name = character["name"]
	_in_world[peer] = p_name
	print("Peer %d entered the world as %s" % [peer, p_name])
	_entered_world.rpc_id(peer, p_name)
	player_entered.emit(peer, p_name)
	_broadcast_roster()


@rpc("any_peer", "call_local", "reliable")
func _request_leave_world() -> void:
	var peer := _logged_in_sender()
	if peer == 0 or not _in_world.has(peer):
		return
	_remove_from_world(peer)
	_left_world.rpc_id(peer)


# --- Client side answers ----------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _login_result(ok: bool, message: String, p_username: String, p_characters: Array) -> void:
	if ok:
		username = p_username
		characters = p_characters
	login_finished.emit(ok, message)
	if ok:
		characters_changed.emit(characters, "")


@rpc("authority", "call_local", "reliable")
func _characters_result(p_characters: Array, message: String) -> void:
	characters = p_characters
	characters_changed.emit(characters, message)


@rpc("authority", "call_local", "reliable")
func _entered_world(p_name: String) -> void:
	character_name = p_name
	entered_world.emit(p_name)


@rpc("authority", "call_local", "reliable")
func _left_world() -> void:
	character_name = ""
	left_world.emit()


@rpc("authority", "call_local", "reliable")
func _set_roster(p_roster: Dictionary) -> void:
	roster = p_roster
	roster_changed.emit(roster)


# --- Server helpers ---------------------------------------------------------

## Server side: opens the accounts database, creating it if it's new, so
## problems show up when the server starts rather than at the first login.
func open_accounts() -> void:
	_accounts()


func _accounts() -> AccountStore:
	if _store == null:
		# --accounts=<path> keeps accounts somewhere else, e.g. for tests.
		var path := AccountStore.DEFAULT_PATH
		for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
			if arg.begins_with("--accounts="):
				path = arg.get_slice("=", 1)
		_store = AccountStore.new(path)
		if _store.is_open():
			print("Accounts are saved in %s" % ProjectSettings.globalize_path(_store.path))
	return _store


## The id of the peer that sent the current RPC if it is logged in, else 0.
func _logged_in_sender() -> int:
	if not multiplayer.is_server():
		return 0
	var peer := multiplayer.get_remote_sender_id()
	return peer if _usernames.has(peer) else 0


func _finish_login(peer: int, p_username: String) -> void:
	var key := p_username.to_lower()
	_usernames[peer] = key
	_failed_logins.erase(peer)
	print("Peer %d logged in as %s" % [peer, _accounts().display_name(key)])
	_login_result.rpc_id(peer, true, "", _accounts().display_name(key), _accounts().list_characters(key))
	_set_roster.rpc_id(peer, _in_world)


func _remove_from_world(peer: int) -> void:
	if not _in_world.has(peer):
		return
	print("Peer %d (%s) left the world" % [peer, _in_world[peer]])
	_in_world.erase(peer)
	player_left.emit(peer)
	_broadcast_roster()


func _broadcast_roster() -> void:
	# Only peers that have logged in hear about who is playing.
	for peer in _usernames:
		_set_roster.rpc_id(peer, _in_world)


func _on_peer_disconnected(peer: int) -> void:
	if not multiplayer.is_server():
		return
	_remove_from_world(peer)
	_usernames.erase(peer)
	_failed_logins.erase(peer)
