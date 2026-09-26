extends Control
## Entry scene. Reads command-line flags to pick a launch mode, otherwise shows
## a menu to host or join.
##
##   godot --headless --server [--port=7777]   dedicated server
##   godot --host [--port=7777]                host and play (listen server)
##   godot --join=127.0.0.1 [--port=7777]      client
##
## Flags may also be passed after "--" (user args), e.g. "godot -- --host".
##
## After hosting or joining, players log in (or create an account) and then pick,
## create or delete characters before entering the world. Accounts and
## characters live on the server; see the Session autoload.
##
## The test world is loaded under this node on every peer as soon as a game
## starts (same path everywhere, so MultiplayerSpawner can replicate players
## into it). Once in the world, the menu becomes an overlay toggled with Esc.

const WORLD_SCENE := preload("res://scenes/test_world.tscn")
const AccountStore := preload("res://scripts/account_store.gd")

@onready var _menu: Control = %Menu
@onready var _login: Control = %Login
@onready var _character_select: Control = %CharacterSelect
@onready var _lobby: Control = %Lobby
@onready var _address: LineEdit = %Address
@onready var _port: SpinBox = %Port
@onready var _username: LineEdit = %Username
@onready var _password: LineEdit = %Password
@onready var _character_list: ItemList = %CharacterList
@onready var _new_character_name: LineEdit = %NewCharacterName
@onready var _delete_confirm: ConfirmationDialog = %DeleteConfirm
@onready var _status: Label = %Status
@onready var _players: Label = %Players
@onready var _overlay: Control = $Center

var _world: Node
## True while a login or register request is waiting for the server.
var _login_pending := false


func _ready() -> void:
	Network.status_changed.connect(_on_status_changed)
	Session.login_finished.connect(_on_login_finished)
	Session.characters_changed.connect(_on_characters_changed)
	Session.entered_world.connect(_on_entered_world)
	Session.left_world.connect(_on_left_world)
	Session.roster_changed.connect(_on_roster_changed)
	%HostButton.pressed.connect(_on_host_pressed)
	%JoinButton.pressed.connect(_on_join_pressed)
	%LoginButton.pressed.connect(_on_login_pressed)
	%RegisterButton.pressed.connect(_on_register_pressed)
	%DisconnectButton.pressed.connect(_on_leave_pressed)
	_password.text_submitted.connect(func(_text: String) -> void: _on_login_pressed())
	%CreateCharacterButton.pressed.connect(_on_create_character_pressed)
	_new_character_name.text_submitted.connect(func(_text: String) -> void: _on_create_character_pressed())
	%PlayButton.pressed.connect(_on_play_pressed)
	_character_list.item_activated.connect(func(_index: int) -> void: _on_play_pressed())
	_character_list.item_selected.connect(func(_index: int) -> void: _update_character_buttons())
	%DeleteCharacterButton.pressed.connect(_on_delete_character_pressed)
	_delete_confirm.confirmed.connect(_on_delete_confirmed)
	%LogoutButton.pressed.connect(_on_logout_pressed)
	%CharacterSelectButton.pressed.connect(Session.leave_world)
	%LeaveButton.pressed.connect(_on_leave_pressed)
	_port.value = Network.DEFAULT_PORT
	_address.text = Network.DEFAULT_ADDRESS
	_show(_menu)
	_launch_from_args(_parse_args())


func _parse_args() -> Dictionary:
	var args := {}
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		var key: String = arg.lstrip("-")
		var value := ""
		if "=" in key:
			value = key.get_slice("=", 1)
			key = key.get_slice("=", 0)
		args[key] = value
	return args


func _launch_from_args(args: Dictionary) -> void:
	var port := int(args["port"]) if args.get("port", "").is_valid_int() else Network.DEFAULT_PORT
	var headless := DisplayServer.get_name() == "headless"

	if args.has("host"):
		if Network.host(port) == OK:
			_start_game()
	elif args.has("join"):
		var address: String = args["join"] if args["join"] != "" else Network.DEFAULT_ADDRESS
		if Network.join(address, port) == OK:
			_start_game()
	elif args.has("server") or OS.has_feature("dedicated_server") or headless:
		if not args.has("server"):
			print("No launch flag given in a headless or server build; starting a dedicated server.")
		if Network.start_dedicated_server(port) != OK:
			get_tree().quit(1)
			return
		_start_game()


func _on_host_pressed() -> void:
	if Network.host(int(_port.value)) == OK:
		_start_game()


func _on_join_pressed() -> void:
	var address := _address.text.strip_edges()
	if address.is_empty():
		address = Network.DEFAULT_ADDRESS
	if Network.join(address, int(_port.value)) == OK:
		_start_game()


func _on_leave_pressed() -> void:
	Network.disconnect_from_game()


func _on_status_changed(text: String) -> void:
	_status.text = text
	if Network.mode == Network.Mode.OFFLINE:
		_leave_game()
	_update_login_buttons()


# --- Login ------------------------------------------------------------------

func _on_login_pressed() -> void:
	if _can_submit_login():
		_login_pending = true
		_update_login_buttons()
		_status.text = "Logging in..."
		Session.login(_username.text.strip_edges(), _password.text)


func _on_register_pressed() -> void:
	if _can_submit_login():
		_login_pending = true
		_update_login_buttons()
		_status.text = "Creating account..."
		Session.register(_username.text.strip_edges(), _password.text)


func _can_submit_login() -> bool:
	if _login_pending or not _is_connected():
		return false
	if _username.text.strip_edges().is_empty() or _password.text.is_empty():
		_status.text = "Enter a username and password."
		return false
	return true


func _on_login_finished(ok: bool, message: String) -> void:
	_login_pending = false
	_update_login_buttons()
	if not ok:
		_status.text = message
		return
	_password.clear()
	_status.text = "Logged in as %s" % Session.username
	%AccountLabel.text = "%s's characters" % Session.username
	_show(_character_select)


func _update_login_buttons() -> void:
	var disabled := _login_pending or not _is_connected()
	%LoginButton.disabled = disabled
	%RegisterButton.disabled = disabled


func _is_connected() -> bool:
	var peer := multiplayer.multiplayer_peer
	return Network.mode != Network.Mode.OFFLINE and peer != null \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


# --- Character select -------------------------------------------------------

func _on_characters_changed(characters: Array, message: String) -> void:
	var previous := _selected_character()
	_character_list.clear()
	for character in characters:
		var index := _character_list.add_item(character["name"])
		if character["name"] == previous:
			_character_list.select(index)
	if not _character_list.is_anything_selected() and _character_list.item_count > 0:
		_character_list.select(_character_list.item_count - 1)
	if message != "":
		_status.text = message
	elif characters.is_empty():
		_status.text = "Create a character to start playing."
	_update_character_buttons()


func _on_create_character_pressed() -> void:
	var character_name := _new_character_name.text.strip_edges()
	if character_name.is_empty():
		_status.text = "Type a name for the new character."
		return
	_new_character_name.clear()
	Session.create_character(character_name)


func _on_play_pressed() -> void:
	var character_name := _selected_character()
	if character_name != "":
		_status.text = "Entering the world as %s..." % character_name
		Session.enter_world(character_name)


func _on_delete_character_pressed() -> void:
	var character_name := _selected_character()
	if character_name != "":
		_delete_confirm.dialog_text = "Delete %s? This can't be undone." % character_name
		_delete_confirm.popup_centered()


func _on_delete_confirmed() -> void:
	var character_name := _selected_character()
	if character_name != "":
		Session.delete_character(character_name)
		_status.text = "Deleted %s" % character_name


func _on_logout_pressed() -> void:
	Session.logout()
	_status.text = "Logged out"
	_show(_login)


func _selected_character() -> String:
	var selected := _character_list.get_selected_items()
	return _character_list.get_item_text(selected[0]) if not selected.is_empty() else ""


func _update_character_buttons() -> void:
	var has_selection := _selected_character() != ""
	%PlayButton.disabled = not has_selection
	%DeleteCharacterButton.disabled = not has_selection
	%CreateCharacterButton.disabled = _character_list.item_count >= AccountStore.MAX_CHARACTERS


# --- In the world -----------------------------------------------------------

func _on_entered_world(character_name: String) -> void:
	_status.text = "Playing as %s" % character_name
	_show(_lobby)
	# Let clicks fall through to the game instead of being eaten by the menu.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_overlay_visible(false)


func _on_left_world() -> void:
	_status.text = "Logged in as %s" % Session.username
	mouse_filter = Control.MOUSE_FILTER_STOP
	_set_overlay_visible(true)
	_show(_character_select)


func _on_roster_changed(roster: Dictionary) -> void:
	var lines: PackedStringArray = []
	var ids := roster.keys()
	ids.sort()
	for id in ids:
		var tag := " (you)" if id == multiplayer.get_unique_id() else ""
		if id == 1:
			tag += " (host)"
		lines.append("%s%s" % [roster[id], tag])
	_players.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if Session.character_name == "":
		return
	if event.is_action_pressed("ui_cancel"):
		_set_overlay_visible(not _overlay.visible)
	elif event is InputEventMouseButton and event.pressed and _overlay.visible:
		_set_overlay_visible(false)


## Loads the test world and shows the login screen. Clients load the world as
## soon as they start connecting so it already exists when the server's spawner
## replicates players into it.
func _start_game() -> void:
	if _world == null:
		_world = WORLD_SCENE.instantiate()
		add_child(_world)
	if Network.is_dedicated_server():
		return
	_login_pending = false
	_password.clear()
	_update_login_buttons()
	_show(_login)
	_username.grab_focus.call_deferred()


func _leave_game() -> void:
	if _world:
		_world.queue_free()
		_world = null
	Session.reset()
	_login_pending = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_set_overlay_visible(true)
	_show(_menu)


func _set_overlay_visible(value: bool) -> void:
	_overlay.visible = value
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED


## Shows one screen of the menu panel and hides the others.
func _show(screen: Control) -> void:
	for child: Control in [_menu, _login, _character_select, _lobby]:
		child.visible = child == screen
