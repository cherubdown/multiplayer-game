extends Node3D
## The game world: an island generated from the server's world seed (see
## scripts/terrain.gd). Every peer builds the terrain itself once the Session
## autoload knows the seed. On the server, spawns a player for every peer that
## has logged in and picked a character (see the Session autoload), and removes
## it when they leave. MultiplayerSpawner replicates those spawns to every
## client.

const PLAYER_SCENE := preload("res://scenes/player.tscn")

@onready var players: Node3D = $Players
@onready var terrain: Node3D = $Terrain


func _ready() -> void:
	Session.world_seed_changed.connect(_build_terrain)
	if Session.world_seed != "":
		_build_terrain(Session.world_seed)
	if not multiplayer.is_server():
		return
	Session.player_entered.connect(_add_player)
	Session.player_left.connect(_remove_player)
	var in_world := Session.players_in_world()
	for id in in_world:
		_add_player(id, in_world[id], Session.race_of(id))


func _build_terrain(seed_text: String) -> void:
	if terrain.gen and terrain.gen.seed_text == seed_text:
		return
	# A dedicated server draws nothing, so it only needs the ground's shape.
	terrain.build(seed_text, not Network.is_dedicated_server())


func _add_player(id: int, character_name: String, race: String) -> void:
	var player := PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.character_name = character_name
	player.race = race
	# Spread spawns out around the middle of the Meadows so players don't
	# start inside each other, and drop them onto the ground.
	player.position = terrain.gen.spawn_point(randf() * TAU) + Vector3.UP * 1.5
	players.add_child(player, true)


func _remove_player(id: int) -> void:
	var player := players.get_node_or_null(str(id))
	if player:
		player.queue_free()
