extends Node3D
## Some of an item lying on the ground. The server spawns pickups (see
## scripts/test_world.gd) and ItemSpawner replicates them to every client.
## A player close enough presses E to pick it up: the client asks the server,
## which moves as much as fits into the player's inventory and removes the
## pickup once it's all gone.
##
## Something that came out of a tree, a rock or a frog has a `launch`: it
## flies out of there in an arc, bounces a few times, squashing as it lands,
## and its sparkle flares up big and bright as it settles. That's all for
## show: every peer plays it itself from where the pickup lies and `launch`
## (see scripts/drop_bounce.gd), and the server clears `launch` once it's
## over, so players who turn up later just see it lying there.

const Items := preload("res://scripts/items.gd")
const Sparkle := preload("res://scripts/sparkle.gd")
const DropBounce := preload("res://scripts/drop_bounce.gd")

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

## Set by the server before spawning: where it flew out of, from where it
## lies (zero for nothing, it's just there). Cleared once it has landed.
@export var launch := Vector3.ZERO

## Server side: the world, for finding players.
var world: Node
## Seconds since it was dropped, while it's still flying or bouncing (-1
## once it's done).
var _age := -1.0
## Where the mesh, sparkle and label sit when it's at rest.
var _rest := {}


func _ready() -> void:
	add_to_group("interactable")
	$Mesh.mesh = Items.mesh(item)
	$Sparkle.mesh = Sparkle.mesh()
	_update_label()
	if launch != Vector3.ZERO:
		_age = 0.0
		for part: Node3D in [$Mesh, $Sparkle, $Label]:
			_rest[part] = part.position
		_play_drop(0.0)
		if multiplayer.is_server():
			get_tree().create_timer(DropBounce.drop_seconds() + 0.5).timeout.connect(func() -> void: launch = Vector3.ZERO)


func _process(delta: float) -> void:
	# Spins faster while it's in the air.
	$Mesh.rotate_y(delta * (6.0 if _age >= 0.0 and _age < DropBounce.FLIGHT_SECONDS else 1.0))
	if _age >= 0.0:
		_age += delta
		_play_drop(_age)


func _play_drop(t: float) -> void:
	var pose = DropBounce.pose(t, launch)
	var offset: Vector3 = pose[0] if pose != null else Vector3.ZERO
	var squash: float = pose[1] if pose != null else 1.0
	for part: Node3D in _rest:
		part.position = _rest[part] + offset
	$Mesh.scale = Vector3(1.0 / sqrt(squash), squash, 1.0 / sqrt(squash))
	# The sparkle flares as it lands and slowly settles back to its usual
	# glint (see shaders/sparkle.gdshader).
	var shine := 0.0
	if t >= DropBounce.FLIGHT_SECONDS:
		shine = 1.0 - clampf((t - DropBounce.FLIGHT_SECONDS) / DropBounce.SHINE_SECONDS, 0.0, 1.0)
	else:
		shine = 0.5 * t / DropBounce.FLIGHT_SECONDS
	$Sparkle.set_instance_shader_parameter("burst", shine * shine)
	if pose == null and t >= DropBounce.FLIGHT_SECONDS + DropBounce.SHINE_SECONDS:
		_age = -1.0


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
