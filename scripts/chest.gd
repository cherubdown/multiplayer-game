extends StaticBody3D
## A chest players can put items in and take them out of. It's part of the
## world on every peer (see scripts/test_world.gd), but only the server knows
## what's inside: it saves the contents in the accounts database and sends them
## to whoever has the chest open.
##
## A player close enough presses E to open it. While it's open, the client asks
## the server to move whole stacks between its inventory and the chest; the
## server checks the player is still nearby, moves what fits, and sends the new
## contents to everyone looking in.

const Inventory := preload("res://scripts/inventory.gd")

const SLOTS := 20

## Client side: the server sent this chest's contents, because it was opened
## or something in it changed.
signal contents_changed(slots: Array)
## Client side: the chest was closed (here or by the server).
signal closed

## Names the chest in the database, so its contents survive a restart.
var chest_id := "chest"
## Client side: the contents last sent by the server, while the chest is open.
var contents: Array = []
var is_open := false

## Server side: the world, for finding players.
var world: Node
var _inventory: Inventory
var _viewers := {}  # peer id -> true, for every peer with the chest open


func _ready() -> void:
	add_to_group("interactable")
	if multiplayer.is_server():
		_inventory = Inventory.new(SLOTS)
		_inventory.load_array(Session.accounts().load_chest(chest_id))
		Session.player_left.connect(func(peer: int) -> void: _viewers.erase(peer))


func prompt() -> String:
	return "Open chest"


# --- Client API -------------------------------------------------------------

func interact() -> void:
	_request_open.rpc_id(1)


func close() -> void:
	if is_open:
		is_open = false
		_request_close.rpc_id(1)
		closed.emit()


## Moves the stack in slot `slot` of the player's inventory into the chest.
func store(slot: int) -> void:
	_request_store.rpc_id(1, slot)


## Moves the stack in slot `slot` of the chest into the player's inventory.
func take(slot: int) -> void:
	_request_take.rpc_id(1, slot)


# --- Server side requests ---------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func _request_open() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if Session.inventory_of(peer) == null or not world.is_near(peer, global_position):
		return
	_viewers[peer] = true
	_show.rpc_id(peer, _inventory.to_array())


@rpc("any_peer", "call_local", "reliable")
func _request_close() -> void:
	if multiplayer.is_server():
		_viewers.erase(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_local", "reliable")
func _request_store(slot) -> void:
	var peer := _viewer()
	if peer != 0 and slot is int and Session.inventory_of(peer).move_to(slot, _inventory) > 0:
		_changed()
		Session.inventory_updated(peer)


@rpc("any_peer", "call_local", "reliable")
func _request_take(slot) -> void:
	var peer := _viewer()
	if peer != 0 and slot is int and _inventory.move_to(slot, Session.inventory_of(peer)) > 0:
		_changed()
		Session.inventory_updated(peer)


## The id of the peer that sent the current RPC if it has the chest open and
## is still next to it, else 0. Closes the chest for a peer that walked away.
func _viewer() -> int:
	if not multiplayer.is_server():
		return 0
	var peer := multiplayer.get_remote_sender_id()
	if not _viewers.has(peer):
		return 0
	if Session.inventory_of(peer) == null or not world.is_near(peer, global_position):
		_viewers.erase(peer)
		if Session.inventory_of(peer) != null:
			_closed.rpc_id(peer)
		return 0
	return peer


func _changed() -> void:
	var slots := _inventory.to_array()
	Session.accounts().save_chest(chest_id, slots)
	for peer in _viewers:
		_show.rpc_id(peer, slots)


# --- Client side answers ----------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _show(slots: Array) -> void:
	contents = slots
	is_open = true
	contents_changed.emit(slots)


@rpc("authority", "call_local", "reliable")
func _closed() -> void:
	is_open = false
	closed.emit()
