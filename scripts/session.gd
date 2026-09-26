extends Node
## Autoload for logging in and picking a character.
##
## The server (host or dedicated) owns the accounts: in PostgreSQL when the
## DATABASE_URL environment variable is set, else in a JSON file. After
## connecting, a client registers or logs in, manages its characters, then asks
## to enter the world with one of them. The server only spawns a player for a
## peer once that peer has entered the world.
##
## Requests go to peer 1 and answers come back to the asking peer. Every RPC is
## call_local so the host, which is peer 1 itself, uses the same path. The
## server checks passwords and reads accounts on a background thread
## (AccountWorker), so request handlers await their answers and re-check that
## the peer is still around before replying.

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
const PostgresAccountStore := preload("res://scripts/postgres_account_store.gd")
const AccountWorker := preload("res://scripts/account_worker.gd")
const MAX_FAILED_LOGINS := 5
const ACCOUNTS_UNAVAILABLE := "The server can't reach its accounts right now. Try again soon."

## Client side state.
var username := ""
var characters: Array = []
var character_name := ""
var roster := {}

## Server side state.
var _store: Variant = null    # AccountStore or PostgresAccountStore (same methods)
var _worker: AccountWorker
var _opening_accounts := false
var _usernames := {}          # peer id -> logged in username (lowercase)
var _in_world := {}           # peer id -> character name
var _failed_logins := {}      # peer id -> count
var _busy := {}               # peer id -> true while its request is being checked


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _exit_tree() -> void:
	if _worker != null:
		_worker.stop()
	if _store != null:
		_store.close()


## Server side: opens the account store if it isn't open yet. Accounts go in
## the PostgreSQL database named by the DATABASE_URL environment variable, or
## without one in a JSON file (user://accounts.json, or --accounts=<path>,
## which also wins over DATABASE_URL). Returns "" or what went wrong.
func open_accounts() -> String:
	while _opening_accounts:
		await get_tree().process_frame
	if _store != null:
		return ""
	_opening_accounts = true
	if _worker == null:
		_worker = AccountWorker.new()
		_worker.name = "AccountWorker"
		add_child(_worker)
	var store: Variant = _make_store()
	var err: String = await _worker.run(store.open)
	_opening_accounts = false
	if err != "":
		push_error("Could not open the accounts in %s: %s" % [store.describe(), err])
		return err
	_store = store
	print("Accounts are saved in %s" % store.describe())
	return ""


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
	_busy.clear()


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
	if _usernames.has(peer) or _busy.has(peer) or not (p_username is String and password is String):
		return
	_busy[peer] = true
	var err: Variant = await _with_accounts(func() -> String: return _store.register(p_username, password))
	_busy.erase(peer)
	if not _is_connected(peer):
		return
	if err == null:
		err = ACCOUNTS_UNAVAILABLE
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
	if _usernames.has(peer) or _busy.has(peer) or not (p_username is String and password is String):
		return
	_busy[peer] = true
	var err: Variant = await _with_accounts(func() -> String: return _store.verify(p_username, password))
	_busy.erase(peer)
	if not _is_connected(peer):
		return
	if err == null:
		err = ACCOUNTS_UNAVAILABLE
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
	var result: Variant = await _with_accounts(func() -> Array:
		return [_store.create_character(account, p_name), _store.list_characters(account)])
	if _usernames.get(peer, "") != account:
		return
	if result == null:
		result = [ACCOUNTS_UNAVAILABLE, []]
	_characters_result.rpc_id(peer, result[1], result[0])


@rpc("any_peer", "call_local", "reliable")
func _request_delete_character(p_name) -> void:
	var peer := _logged_in_sender()
	if peer == 0 or not p_name is String:
		return
	var account: String = _usernames[peer]
	var in_world: bool = _in_world.get(peer, "").to_lower() == p_name.to_lower()
	var result: Variant = await _with_accounts(func() -> Array:
		if in_world:
			return ["Leave the world before deleting that character.", _store.list_characters(account)]
		return [_store.delete_character(account, p_name), _store.list_characters(account)])
	if _usernames.get(peer, "") != account:
		return
	if result == null:
		result = [ACCOUNTS_UNAVAILABLE, []]
	_characters_result.rpc_id(peer, result[1], result[0])


@rpc("any_peer", "call_local", "reliable")
func _request_enter_world(p_name) -> void:
	var peer := _logged_in_sender()
	if peer == 0 or not p_name is String or _in_world.has(peer) or _busy.has(peer):
		return
	var account: String = _usernames[peer]
	_busy[peer] = true
	var list: Variant = await _with_accounts(func() -> Array: return _store.list_characters(account))
	_busy.erase(peer)
	if _usernames.get(peer, "") != account or _in_world.has(peer):
		return
	if list == null:
		_characters_result.rpc_id(peer, [], ACCOUNTS_UNAVAILABLE)
		return
	var found := ""
	for character in list:
		if str(character["name"]).to_lower() == p_name.to_lower():
			found = character["name"]
	if found == "":
		_characters_result.rpc_id(peer, list, "No character called %s." % p_name)
		return
	_in_world[peer] = found
	print("Peer %d entered the world as %s" % [peer, found])
	_entered_world.rpc_id(peer, found)
	player_entered.emit(peer, found)
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

func _make_store() -> Variant:
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with("--accounts="):
			return AccountStore.new(arg.get_slice("=", 1))
	var url := OS.get_environment("DATABASE_URL")
	if url != "":
		return PostgresAccountStore.new(url)
	return AccountStore.new(AccountStore.DEFAULT_PATH)


## Runs job on the account thread once the store is open. Returns what job
## returns, or null if the accounts can't be opened.
func _with_accounts(job: Callable) -> Variant:
	if await open_accounts() != "":
		return null
	return await _worker.run(job)


## True while peer is still connected (the host, peer 1, always is).
func _is_connected(peer: int) -> bool:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return false
	return peer == multiplayer.get_unique_id() or peer in multiplayer.get_peers()


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
	var account: Variant = await _with_accounts(func() -> Array:
		return [_store.display_name(key), _store.list_characters(key)])
	if _usernames.get(peer, "") != key:
		return
	if account == null:
		account = [p_username, []]
	print("Peer %d logged in as %s" % [peer, account[0]])
	_login_result.rpc_id(peer, true, "", account[0], account[1])
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
	_busy.erase(peer)
