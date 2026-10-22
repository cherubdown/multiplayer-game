extends Node3D
## Some of an item lying on the ground. The server spawns pickups (see
## scripts/test_world.gd) and ItemSpawner replicates them to every client.
## A player close enough presses E to pick it up: the client asks the server,
## which moves as much as fits into the player's inventory and removes the
## pickup once it's all gone.

const Items := preload("res://scripts/items.gd")
const Sparkle := preload("res://scripts/sparkle.gd")

## Server side: everything here was picked up, just before it's removed.
signal taken

## Set by the server before spawning; replicated at spawn time.
@export var item := "wood"
## Replicated whenever it changes (part of it can be picked up).
@export var count := 1:
	set(value):
		count = value
		if is_node_ready():
			_update_label()

## Server side: the world, for finding players.
var world: Node


func _ready() -> void:
	add_to_group("interactable")
	$Mesh.mesh = Items.mesh(item)
	$Sparkle.mesh = Sparkle.mesh()
	_update_label()


func _process(delta: float) -> void:
	$Mesh.rotate_y(delta)


## What pressing E does, for the on-screen prompt.
func prompt() -> String:
	return "Pick up %s" % _label_text()


## Client side: ask the server to pick this up.
func interact() -> void:
	_request_pick_up.rpc_id(1)


func _update_label() -> void:
	$Label.text = _label_text()


func _label_text() -> String:
	return Items.display_name(item) + (" x%d" % count if count > 1 else "")


@rpc("any_peer", "call_local", "reliable")
func _request_pick_up() -> void:
	if not multiplayer.is_server() or count <= 0:
		return
	var peer := multiplayer.get_remote_sender_id()
	var inventory = Session.inventory_of(peer)
	if inventory == null or not world.is_near(peer, global_position):
		return
	var left: int = inventory.add(item, count)
	if left == count:
		return  # No room.
	count = left
	Session.inventory_updated(peer)
	if count == 0:
		taken.emit()
		queue_free()
