extends Node3D
## The game world: an island generated from the server's world seed (see
## scripts/terrain.gd). Every peer builds the terrain itself once the Session
## autoload knows the seed. On the server, spawns a player for every peer that
## has logged in and picked a character (see the Session autoload), and removes
## it when they leave. MultiplayerSpawner replicates those spawns to every
## client. A character comes back where it stood and facing the way it faced
## when it last left the world; a new character starts near the middle.
##
## Next to the spawn there's a test chest (on every peer) and some items on
## the ground to pick up, which the server spawns and ItemSpawner replicates.
## Picked up items come back after a while so there's always something to try.
## Items players drop lie where they fell until someone picks them up (until
## the server restarts).
##
## Mushrooms, berry bushes, apple trees, fallen branches and loose stones are
## scattered around the island from the seed, for players to pick (see
## scripts/forage.gd). Trees and big rocks stand in the way and can be chopped
## or broken with the right tool for wood and stone (see
## scripts/harvestables.gd), which the server drops on the ground here.
##
## Big Frogs live in a few areas of the Meadows picked from the seed (see
## WorldGen.frog_areas() and scripts/big_frog.gd). The server puts a frog in
## each area when the world starts, then every FROG_SPAWN_SECONDS (an hour,
## real time) each area gets another, up to FROG_AREA_MAX at once.
## EnemySpawner replicates them. Players a frog kills come back at the spawn
## with full health.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PICKUP_SCENE := preload("res://scenes/item_pickup.tscn")
const CHEST_SCENE := preload("res://scenes/chest.tscn")
const InventoryUI := preload("res://scripts/inventory_ui.gd")
const Forage := preload("res://scripts/forage.gd")
const Harvestables := preload("res://scripts/harvestables.gd")
const FROG_SCENE := preload("res://scenes/big_frog.tscn")
const HUD := preload("res://scripts/hud.gd")
const WorldGen := preload("res://scripts/world_gen.gd")

## How close a player has to be to pick something up or open a chest. The
## server allows a bit more, since it sees players slightly later.
const INTERACT_RANGE := 2.5
const SERVER_INTERACT_RANGE := 4.0
## Seconds between saves of where every player stands, so a server that is
## stopped (or crashes) without players leaving loses little.
const POSITION_SAVE_SECONDS := 15.0
## Seconds before a picked up test item appears again.
const RESPAWN_SECONDS := 60.0
## Where the test chest stands, as an angle and distance from the middle of
## the Meadows (players spawn 4 m out).
const CHEST_SPOT := Vector2(0.0, 7.0)
## Seconds between frogs turning up in each frog area (an hour), and how many
## can live in one area at once.
const FROG_SPAWN_SECONDS := 3600.0
const FROG_AREA_MAX := 3
## Items lying around the spawn: item, count, angle, distance.
const TEST_ITEMS := [
	["wood", 5, 0.6, 6.0],
	["wood", 3, 1.5, 9.0],
	["stone", 4, 2.3, 6.5],
	["stone", 2, 3.2, 10.0],
	["flint", 2, 3.9, 6.0],
	["berries", 6, 4.7, 7.0],
	["wood", 8, 5.4, 8.0],
	["flint", 1, 5.9, 11.0],
]

@onready var players: Node3D = $Players
@onready var terrain: Node3D = $Terrain
@onready var items: Node3D = $Items
@onready var enemies: Node3D = $Enemies
## The plants to pick, rebuilt with the terrain.
var forage: Forage
## The trees and rocks, rebuilt with the terrain.
var harvestables: Harvestables
## Server side: the middles of the areas Big Frogs live in.
var frog_areas: Array[Vector3] = []
var _frog_timer: Timer


func _ready() -> void:
	if not Network.is_dedicated_server():
		add_child(InventoryUI.new())
		add_child(HUD.new())
	Session.world_seed_changed.connect(_build_terrain)
	if Session.world_seed != "":
		_build_terrain(Session.world_seed)
	if not multiplayer.is_server():
		return
	Session.player_entered.connect(_add_player)
	Session.player_left.connect(_remove_player)
	Session.item_dropped.connect(drop_item)
	var autosave := Timer.new()
	autosave.wait_time = POSITION_SAVE_SECONDS
	autosave.autostart = true
	autosave.timeout.connect(Session.save_positions)
	add_child(autosave)
	var in_world := Session.players_in_world()
	for id in in_world:
		_add_player(id, in_world[id], Session.race_of(id))


func _build_terrain(seed_text: String) -> void:
	if terrain.gen and terrain.gen.seed_text == seed_text:
		return
	# A dedicated server draws nothing, so it only needs the ground's shape.
	terrain.build(seed_text, not Network.is_dedicated_server())
	_place_chest()
	_grow_harvestables()
	_grow_forage()
	if multiplayer.is_server() and items.get_child_count() == 0:
		for spot in TEST_ITEMS:
			_spawn_pickup(spot)
	if multiplayer.is_server():
		frog_areas = terrain.gen.frog_areas()
		if enemies.get_child_count() == 0:
			spawn_frogs()
		if _frog_timer == null:
			_frog_timer = Timer.new()
			_frog_timer.wait_time = FROG_SPAWN_SECONDS
			_frog_timer.autostart = true
			_frog_timer.timeout.connect(spawn_frogs)
			add_child(_frog_timer)


## Server side: whether a peer's player is close enough to `point` to use
## something there.
func is_near(peer: int, point: Vector3) -> bool:
	var player := players.get_node_or_null(str(peer)) as Node3D
	return player != null and player.global_position.distance_to(point) <= SERVER_INTERACT_RANGE


## Server side: whether any player stands within `distance` of `point`,
## across the ground.
func player_near(point: Vector3, distance: float) -> bool:
	for player: Node3D in players.get_children():
		if Vector2(player.global_position.x - point.x, player.global_position.z - point.z).length() < distance:
			return true
	return false


## Server side: puts a stack on the ground just in front of a player.
func drop_item(peer: int, item: String, count: int) -> void:
	var player := players.get_node_or_null(str(peer)) as Node3D
	if player == null:
		return
	spawn_item(item, count, player.global_position + player.global_basis.z * -1.0)


## Server side: puts a stack on the ground at (x, z) of `spot`, for anyone to
## pick up.
func spawn_item(item: String, count: int, spot: Vector3) -> void:
	spot.y = terrain.ground_height(spot.x, spot.z)
	var pickup := PICKUP_SCENE.instantiate()
	pickup.item = item
	pickup.count = count
	pickup.world = self
	pickup.position = spot
	items.add_child(pickup, true)


## Server side: a tree came down or a rock broke. Its wood or stone lands
## just past its edge, on the side the player swung from.
func _on_harvested(index: int, item: String, count: int, at: Vector3) -> void:
	var away := Vector2.from_angle(randf() * TAU)
	for player: Node3D in players.get_children():
		var offset := Vector2(player.global_position.x - at.x, player.global_position.z - at.z)
		if offset.length() < harvestables.radius_of(index) + Harvestables.SERVER_REACH + 1.0:
			away = offset.normalized().rotated(randf_range(-0.6, 0.6))
			break
	var distance := harvestables.radius_of(index) + 0.6
	spawn_item(item, count, at + Vector3(away.x, 0.0, away.y) * distance)


func _grow_harvestables() -> void:
	if harvestables != null:
		# Out of the way first, so the new one gets the same name (and RPC path).
		remove_child(harvestables)
		harvestables.queue_free()
	harvestables = Harvestables.new()
	harvestables.name = "Harvestables"
	harvestables.world = self
	add_child(harvestables)
	harvestables.setup(terrain.gen, not Network.is_dedicated_server())
	if multiplayer.is_server():
		harvestables.harvested.connect(_on_harvested)


func _grow_forage() -> void:
	if forage != null:
		# Out of the way first, so the new one gets the same name (and RPC path).
		remove_child(forage)
		forage.queue_free()
	forage = Forage.new()
	forage.name = "Forage"
	forage.world = self
	add_child(forage)
	forage.setup(terrain.gen, Callable() if Network.is_dedicated_server() else terrain.surface_height,
		harvestables.occupied)


func _place_chest() -> void:
	var chest := get_node_or_null("TestChest")
	if chest == null:
		chest = CHEST_SCENE.instantiate()
		chest.name = "TestChest"
		chest.chest_id = "test"
		chest.world = self
		add_child(chest)
	chest.position = terrain.gen.spawn_point(CHEST_SPOT.x, CHEST_SPOT.y)
	# Face the middle, where players spawn.
	chest.rotation.y = atan2(-chest.position.x, -chest.position.z)


func _spawn_pickup(spot: Array) -> void:
	var pickup := PICKUP_SCENE.instantiate()
	pickup.item = spot[0]
	pickup.count = spot[1]
	pickup.world = self
	pickup.position = terrain.gen.spawn_point(spot[2], spot[3])
	pickup.taken.connect(_respawn_later.bind(spot))
	items.add_child(pickup, true)


func _respawn_later(spot: Array) -> void:
	await get_tree().create_timer(RESPAWN_SECONDS).timeout
	if is_inside_tree() and multiplayer.is_server():
		_spawn_pickup(spot)


## Server side: a new Big Frog in every frog area that has fewer than
## FROG_AREA_MAX alive, each at its own spot in the area, clear of trees and
## rocks.
func spawn_frogs() -> void:
	var alive := {}
	for frog: Node in enemies.get_children():
		if frog.is_alive():
			alive[frog.area] = alive.get(frog.area, 0) + 1
	for area in frog_areas.size():
		if alive.get(area, 0) >= FROG_AREA_MAX:
			continue
		var middle := frog_areas[area]
		var spot := Vector3(middle.x, 0.0, middle.z)
		for attempt in 20:
			var offset := Vector2.from_angle(randf() * TAU) * WorldGen.FROG_AREA_RADIUS * sqrt(randf())
			spot = Vector3(middle.x + offset.x, 0.0, middle.z + offset.y)
			if not harvestables.occupied(spot.x, spot.z, 1.0):
				break
		spot.y = terrain.ground_height(spot.x, spot.z) + 0.5
		var frog := FROG_SCENE.instantiate()
		frog.world = self
		frog.area = area
		frog.position = spot
		frog.home = spot
		enemies.add_child(frog, true)


## Server side: a player died. They come back at the spawn with full health,
## keeping what they carry.
func _respawn_player(player: Node3D) -> void:
	player.velocity = Vector3.ZERO
	player.position = terrain.gen.spawn_point(randf() * TAU) + Vector3.UP * 1.5
	player.restore_health()


func _add_player(id: int, character_name: String, race: String) -> void:
	var player := PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.character_name = character_name
	player.race = race
	player.sex = Session.sex_of(id)
	var saved := Session.saved_spot_of(id)
	if not saved.is_empty():
		# Back where they left off. Lift them a little so they never start
		# inside the ground.
		var spot: Vector3 = saved["position"]
		spot.y = maxf(spot.y, terrain.ground_height(spot.x, spot.z)) + 0.1
		player.position = spot
		player.rotation.y = saved["yaw"]
	else:
		# Spread spawns out around the middle of the Meadows so players don't
		# start inside each other, and drop them onto the ground.
		player.position = terrain.gen.spawn_point(randf() * TAU) + Vector3.UP * 1.5
	if Session.saved_health_of(id) > 0:
		player.health = Session.saved_health_of(id)
	player.killed.connect(func(_by: String) -> void: _respawn_player(player))
	players.add_child(player, true)
	Session.set_player_body(id, player)


func _remove_player(id: int) -> void:
	var player := players.get_node_or_null(str(id))
	if player:
		player.queue_free()
