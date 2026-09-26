extends Node3D
## Flat test world. On the server, spawns a player for every peer that has
## logged in and picked a character (see the Session autoload), and removes it
## when they leave. MultiplayerSpawner replicates those spawns to every client.

const PLAYER_SCENE := preload("res://scenes/player.tscn")

@onready var players: Node3D = $Players


func _ready() -> void:
	if not multiplayer.is_server():
		return
	Session.player_entered.connect(_add_player)
	Session.player_left.connect(_remove_player)
	var in_world := Session.players_in_world()
	for id in in_world:
		_add_player(id, in_world[id])


func _add_player(id: int, character_name: String) -> void:
	var player := PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.character_name = character_name
	# Spread spawns out so players don't start inside each other.
	var angle := randf() * TAU
	player.position = Vector3(cos(angle), 0.0, sin(angle)) * 3.0 + Vector3.UP
	players.add_child(player, true)


func _remove_player(id: int) -> void:
	var player := players.get_node_or_null(str(id))
	if player:
		player.queue_free()
