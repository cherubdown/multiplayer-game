extends Control
## Entry scene. Reads command-line flags to pick a launch mode, otherwise shows
## a menu to host or join.
##
##   godot --headless --server [--port=7777]   dedicated server
##   godot --host [--port=7777]                host and play (listen server)
##   godot --join=127.0.0.1 [--port=7777]      client
##
## Flags may also be passed after "--" (user args), e.g. "godot -- --host".

@onready var _menu: Control = %Menu
@onready var _lobby: Control = %Lobby
@onready var _address: LineEdit = %Address
@onready var _port: SpinBox = %Port
@onready var _status: Label = %Status
@onready var _players: Label = %Players


func _ready() -> void:
	Network.status_changed.connect(_on_status_changed)
	Network.peers_changed.connect(_on_peers_changed)
	%HostButton.pressed.connect(_on_host_pressed)
	%JoinButton.pressed.connect(_on_join_pressed)
	%LeaveButton.pressed.connect(_on_leave_pressed)
	_port.value = Network.DEFAULT_PORT
	_address.text = Network.DEFAULT_ADDRESS
	_show_menu()
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
			_show_lobby()
	elif args.has("join"):
		var address: String = args["join"] if args["join"] != "" else Network.DEFAULT_ADDRESS
		if Network.join(address, port) == OK:
			_show_lobby()
	elif args.has("server") or OS.has_feature("dedicated_server") or headless:
		if not args.has("server"):
			print("No launch flag given in a headless or server build; starting a dedicated server.")
		if Network.start_dedicated_server(port) != OK:
			get_tree().quit(1)


func _on_host_pressed() -> void:
	if Network.host(int(_port.value)) == OK:
		_show_lobby()


func _on_join_pressed() -> void:
	var address := _address.text.strip_edges()
	if address.is_empty():
		address = Network.DEFAULT_ADDRESS
	if Network.join(address, int(_port.value)) == OK:
		_show_lobby()


func _on_leave_pressed() -> void:
	Network.disconnect_from_game()
	_show_menu()


func _on_status_changed(text: String) -> void:
	_status.text = text
	if Network.mode == Network.Mode.OFFLINE:
		_show_menu()


func _on_peers_changed(peer_ids: Array[int]) -> void:
	var lines: PackedStringArray = []
	for id in peer_ids:
		var tag := " (you)" if id == multiplayer.get_unique_id() else ""
		if id == 1:
			tag += " (host)"
		lines.append("Player %d%s" % [id, tag])
	_players.text = "\n".join(lines)


func _show_menu() -> void:
	_menu.visible = true
	_lobby.visible = false


func _show_lobby() -> void:
	_menu.visible = false
	_lobby.visible = true
