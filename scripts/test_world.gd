extends Node3D
## Flat test world. On the server, spawns a player for every connected peer
## (and for the host itself unless it is a dedicated server). MultiplayerSpawner
## replicates those spawns to every client.

const PLAYER_SCENE := preload("res://scenes/player.tscn")

@onready var players: Node3D = $Players


func _ready() -> void:
	if not multiplayer.is_server():
		return
	multiplayer.peer_connected.connect(_add_player)
	multiplayer.peer_disconnected.connect(_remove_player)
	for id in multiplayer.get_peers():
		_add_player(id)
	if not Network.is_dedicated_server():
		_add_player(1)


func _add_player(id: int) -> void:
	var player := PLAYER_SCENE.instantiate()
	player.name = str(id)
	# Spread spawns out so players don't start inside each other.
	var angle := randf() * TAU
	player.position = Vector3(cos(angle), 0.0, sin(angle)) * 3.0 + Vector3.UP
	players.add_child(player, true)


func _remove_player(id: int) -> void:
	var player := players.get_node_or_null(str(id))
	if player:
		player.queue_free()
