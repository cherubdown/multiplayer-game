extends Node3D
## The trees and big rocks around the island. Where they stand comes from the
## world seed, so every peer places them in the same spots without sending
## them over the network. Players can't walk through them: each has a solid
## trunk or boulder on every peer, the server included, since the server moves
## the players.
##
## Holding the right tool (see scripts/items.gd), a player left-clicks to
## swing at the one in reach: an axe chops trees, a pickaxe breaks rocks. The
## server decides what each swing does. It checks the player holds the right
## tool and is close enough, counts the hit, and after enough hits the tree
## falls (or the rock breaks) and drops its wood (or stone) on the ground for
## anyone to pick up. Everyone sees how it's going: each hit shakes it for
## every player, and once it's down it's gone for everyone until it grows
## back. What's been cut down is forgotten when the server restarts.

const WorldGen := preload("res://scripts/world_gen.gd")
const Items := preload("res://scripts/items.gd")
const TreeMeshes := preload("res://scripts/tree_meshes.gd")
const Biome := WorldGen.Biome

## Meters per side of the grid cells trees and rocks are scattered in. At most
## one grows in each cell.
const CELL := 8.0
## Keep them off the spawn, where players appear and the test chest stands.
const SPAWN_CLEARING := 12.0
## How far past a trunk's or rock's edge a swing reaches. The server allows a
## bit more, since it sees players slightly later.
const REACH := 1.6
const SERVER_REACH := 2.6
## Seconds between swings.
const SWING_SECONDS := 0.6
## Seconds between the server's checks for things growing back.
const RESPAWN_CHECK_SECONDS := 1.0
## Physics layer of trunks and rocks. Players collide with it; the camera
## doesn't, so it doesn't jump in front of every tree in a forest.
const COLLISION_LAYER := 2

## Each kind: the tool type that harvests it, the hits it takes, the item it
## drops and how many (between the two numbers), the seconds it takes to grow
## back, and its solid part (radius and height at size 1, centered `solid_y`
## above the ground). "name" is for the on-screen prompt.
const KINDS := {
	"pine": { "name": "pine", "tool": "axe", "hits": 6, "drop": "wood", "amount": Vector2i(5, 7),
		"respawn": 600.0, "radius": 0.35, "height": 4.5, "solid_y": 2.25 },
	"leafy": { "name": "tree", "tool": "axe", "hits": 5, "drop": "wood", "amount": Vector2i(4, 6),
		"respawn": 600.0, "radius": 0.35, "height": 4.5, "solid_y": 2.25 },
	"dead": { "name": "dead tree", "tool": "axe", "hits": 3, "drop": "wood", "amount": Vector2i(2, 4),
		"respawn": 480.0, "radius": 0.35, "height": 5.0, "solid_y": 2.5 },
	"rock": { "name": "rock", "tool": "pickaxe", "hits": 6, "drop": "stone", "amount": Vector2i(4, 7),
		"respawn": 900.0, "radius": 1.1, "height": 1.6, "solid_y": 0.0 },
}
## Chance per cell of each kind, by biome.
const DENSITY := {
	Biome.MEADOWS: { "leafy": 0.12, "pine": 0.03, "rock": 0.02 },
	Biome.BLACK_FOREST: { "pine": 0.6, "rock": 0.05 },
	Biome.SWAMP: { "dead": 0.25 },
	Biome.PLAINS: { "leafy": 0.02, "rock": 0.04 },
	Biome.MOUNTAINS: { "pine": 0.05, "rock": 0.15 },
}

## Server side: a tree came down or a rock broke, at `at`; the world drops
## what it gives.
signal harvested(index: int, item: String, count: int, at: Vector3)
## Every peer: something was hit, came down or grew back.
signal changed(index: int)

## Server side: the world, for finding players and dropping what comes off.
var world: Node
## Everything on the island, in a fixed order:
## { "kind", "position": Vector3, "turn": float, "size": float }.
var spots: Array = []
## Things that have been hit but are still standing: index -> hits taken.
var hits := {}
## Things that are down: index -> Time.get_ticks_msec() when they grow back
## (the server's clock; clients only use the keys).
var felled := {}

var _cells := {}  # Vector2i -> spot index
var _bodies := {}  # spot index -> physics body RID
var _shapes: Array[RID] = []
## On peers that draw: spot index -> [MultiMesh, instance number].
var _instances := {}
var _shakes := {}  # spot index -> Tween
## Server side: peers that have built the world and want to hear what's cut.
var _watchers := {}
var _last_swing := {}  # peer -> Time.get_ticks_msec() of their last swing
var _since_check := 0.0


## Places everything from `gen`'s seed and builds the solid parts. Draws them
## too when `visuals` is true (not on a dedicated server).
func setup(gen: WorldGen, visuals: bool) -> void:
	spots = scatter(gen)
	_cells.clear()
	for i in spots.size():
		_cells[_cell_of(spots[i]["position"])] = i
	_build_collision()
	if visuals:
		_build_meshes()
	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(func(peer: int) -> void:
			_watchers.erase(peer)
			_last_swing.erase(peer))
	elif multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_request_state.rpc_id(1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for body in _bodies.values():
			PhysicsServer3D.free_rid(body)
		for shape in _shapes:
			PhysicsServer3D.free_rid(shape)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_since_check += delta
	if _since_check >= RESPAWN_CHECK_SECONDS:
		_since_check = 0.0
		regrow(Time.get_ticks_msec())


## Every tree and rock the seed grows, in a fixed order. Same answer for the
## same seed.
static func scatter(gen: WorldGen) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = gen.seed_number
	var result := []
	var cells := int(WorldGen.SIZE / CELL)
	for j in cells:
		for i in cells:
			# Draw the same random numbers for every cell so one cell's
			# biome doesn't shift what every later cell gets.
			var jitter := Vector2(rng.randf(), rng.randf())
			var roll := rng.randf()
			var size := rng.randf_range(0.7, 1.4)
			var turn := rng.randf() * TAU
			var x := (i + jitter.x) * CELL - WorldGen.SIZE * 0.5
			var z := (j + jitter.y) * CELL - WorldGen.SIZE * 0.5
			if Vector2(x, z).length() < SPAWN_CLEARING:
				continue
			var h := gen.height_at(x, z)
			var odds: Dictionary = DENSITY.get(gen.biome_for(x, z, h), {})
			for kind in odds:
				if roll < odds[kind]:
					result.append({ "kind": kind, "position": Vector3(x, h, z), "turn": turn, "size": size })
					break
				roll -= odds[kind]
	return result


## How far from the middle of a spot its solid part reaches.
func radius_of(index: int) -> float:
	return KINDS[spots[index]["kind"]]["radius"] * spots[index]["size"]


## Whether anything stands within `margin` of (x, z), standing or not. Used to
## keep small things from growing inside trunks and rocks.
func occupied(x: float, z: float, margin: float) -> bool:
	var cell := _cell_of(Vector3(x, 0.0, z))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var index: int = _cells.get(cell + Vector2i(dx, dz), -1)
			if index >= 0:
				var at: Vector3 = spots[index]["position"]
				if Vector2(at.x - x, at.z - z).length() < radius_of(index) + margin:
					return true
	return false


## The standing tree or rock whose edge is nearest `point`, within `reach` of
## it, or -1.
func nearest(point: Vector3, reach: float) -> int:
	var best := -1
	var best_gap := reach
	var cell := _cell_of(point)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var index: int = _cells.get(cell + Vector2i(dx, dz), -1)
			if index < 0 or felled.has(index):
				continue
			var gap := gap_to(index, point)
			if gap <= best_gap:
				best = index
				best_gap = gap
	return best


## How far `point` is from the edge of a spot's solid part, across the ground.
func gap_to(index: int, point: Vector3) -> float:
	var at: Vector3 = spots[index]["position"]
	return Vector2(at.x - point.x, at.z - point.z).length() - radius_of(index)


## The tool type that harvests a spot ("axe" or "pickaxe").
func tool_for(index: int) -> String:
	return KINDS[spots[index]["kind"]]["tool"]


## Hits a spot still needs before it comes down.
func hits_left(index: int) -> int:
	return KINDS[spots[index]["kind"]]["hits"] - hits.get(index, 0)


## What the on-screen prompt says about a spot, holding `held` (an item id).
func prompt_for(index: int, held: String) -> String:
	var kind: Dictionary = KINDS[spots[index]["kind"]]
	if Items.tool_type(held) != kind["tool"]:
		if kind["tool"] == "axe":
			return "Hold an axe to chop this %s" % kind["name"]
		return "Hold a pickaxe to break this %s" % kind["name"]
	var left := hits_left(index)
	var verb := "Chop the" if kind["tool"] == "axe" else "Break the"
	return "[Left click] %s %s (%d %s)" % [verb, kind["name"], left, "hit" if left == 1 else "hits"]


## Client side: swing the held tool, at spot `index` (-1 for thin air),
## looking towards `yaw`.
func swing(index: int, yaw: float) -> void:
	_request_swing.rpc_id(1, index, yaw)


## Server side: one hit on a spot with a tool of type `tool_type` that does
## `damage`. Returns whether it counted; when it's the last hit, the spot
## comes down and `harvested` says what it dropped.
func hit(index: int, tool_type: String, damage: int, now_msec: int) -> bool:
	if index < 0 or index >= spots.size() or felled.has(index) or tool_type != tool_for(index):
		return false
	var kind: Dictionary = KINDS[spots[index]["kind"]]
	var taken: int = hits.get(index, 0) + maxi(damage, 1)
	if taken < kind["hits"]:
		hits[index] = taken
		_broadcast(index)
		_shake(index)
		return true
	hits.erase(index)
	felled[index] = now_msec + int(kind["respawn"] * 1000.0)
	_broadcast(index)
	var amount: Vector2i = kind["amount"]
	harvested.emit(index, kind["drop"], randi_range(amount.x, amount.y), spots[index]["position"])
	return true


## Server side: grows back whatever is due by `now_msec`, unless a player is
## standing where it would grow, in which case it waits a little longer.
func regrow(now_msec: int) -> void:
	for index in felled.keys():
		if felled[index] > now_msec:
			continue
		if world != null and world.has_method("player_near") \
				and world.player_near(spots[index]["position"], radius_of(index) + 0.8):
			felled[index] = now_msec + 5000
			continue
		felled.erase(index)
		_broadcast(index)


func _broadcast(index: int) -> void:
	_show(index)
	changed.emit(index)
	if multiplayer.is_server():
		for peer in _watchers:
			_set_spot.rpc_id(peer, index, hits.get(index, 0), felled.has(index))


func _cell_of(point: Vector3) -> Vector2i:
	return Vector2i(floori((point.x + WorldGen.SIZE * 0.5) / CELL),
		floori((point.z + WorldGen.SIZE * 0.5) / CELL))


# --- Network ----------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func _request_swing(index, yaw) -> void:
	if not multiplayer.is_server() or not index is int or not (yaw is float or yaw is int):
		return
	var peer := multiplayer.get_remote_sender_id()
	# Looked up rather than named, so tests can load this without autoloads.
	var session := get_node("/root/Session")
	var body: Node3D = session.body_of(peer)
	var held: String = session.held_of(peer)
	if body == null or not Items.is_tool_item(held):
		return
	var now := Time.get_ticks_msec()
	if now - _last_swing.get(peer, -100000) < int(SWING_SECONDS * 1000.0 * 0.8):
		return
	# Swinging a weapon is an attack, which takes stamina; tools don't.
	if Items.is_weapon(held) and not body.spend_stamina(body.ATTACK_STAMINA):
		return
	_last_swing[peer] = now
	var target: bool = index >= 0 and index < spots.size() and not felled.has(index) \
		and gap_to(index, body.global_position) <= SERVER_REACH
	if target:
		var at: Vector3 = spots[index]["position"] - body.global_position
		yaw = atan2(-at.x, -at.z)
	body.swing(float(yaw))
	if target:
		hit(index, Items.tool_type(held), Items.tool_damage(held), now)


## A client has built the world: send it everything that's been hit or cut
## down, and what happens from now on.
@rpc("any_peer", "reliable")
func _request_state() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	_watchers[peer] = true
	_set_state.rpc_id(peer, hits, felled.keys())


@rpc("authority", "reliable")
func _set_state(state_hits: Dictionary, state_felled: Array) -> void:
	var touched := hits.keys() + felled.keys()
	hits.clear()
	felled.clear()
	for index in state_hits:
		if index is int and index >= 0 and index < spots.size():
			hits[index] = int(state_hits[index])
			touched.append(index)
	for index in state_felled:
		if index is int and index >= 0 and index < spots.size():
			felled[index] = 0
			touched.append(index)
	for index in touched:
		_show(index)
		changed.emit(index)


@rpc("authority", "reliable")
func _set_spot(index: int, taken: int, down: bool) -> void:
	if index < 0 or index >= spots.size():
		return
	var was_hit: bool = taken > hits.get(index, 0)
	if taken > 0:
		hits[index] = taken
	else:
		hits.erase(index)
	if down:
		felled[index] = 0
	else:
		felled.erase(index)
	_show(index)
	if was_hit:
		_shake(index)
	changed.emit(index)


# --- Solid parts ------------------------------------------------------------

func _build_collision() -> void:
	var space := get_world_3d().space
	for i in spots.size():
		var spot: Dictionary = spots[i]
		var kind: Dictionary = KINDS[spot["kind"]]
		var size: float = spot["size"]
		var shape := PhysicsServer3D.cylinder_shape_create()
		PhysicsServer3D.shape_set_data(shape, { "radius": kind["radius"] * size, "height": kind["height"] * size })
		_shapes.append(shape)
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_collision_layer(body, COLLISION_LAYER)
		PhysicsServer3D.body_set_collision_mask(body, 0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(), spot["position"] + Vector3.UP * kind["solid_y"] * size))
		PhysicsServer3D.body_set_space(body, space)
		_bodies[i] = body


## Whether a spot's solid part is in the world (it isn't while it's down).
func is_solid(index: int) -> bool:
	return _bodies.has(index) and PhysicsServer3D.body_get_space(_bodies[index]).is_valid()


# --- Drawing ----------------------------------------------------------------

func _build_meshes() -> void:
	var by_kind := {}  # kind -> Array of spot indexes
	for i in spots.size():
		var kind: String = spots[i]["kind"]
		if not by_kind.has(kind):
			by_kind[kind] = []
		by_kind[kind].append(i)
	for kind in by_kind:
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _mesh(kind)
		multimesh.instance_count = by_kind[kind].size()
		for n in by_kind[kind].size():
			_instances[by_kind[kind][n]] = [multimesh, n]
		var instance := MultiMeshInstance3D.new()
		instance.name = kind.capitalize() + "s"
		instance.multimesh = multimesh
		add_child(instance)
		for index in by_kind[kind]:
			_show(index)


## Shows a spot standing, or gone while it's down, and puts its solid part in
## or out of the world to match.
func _show(index: int, tilt := Vector2.ZERO) -> void:
	var down := felled.has(index)
	if _bodies.has(index):
		var space := RID() if down else get_world_3d().space
		if PhysicsServer3D.body_get_space(_bodies[index]) != space:
			PhysicsServer3D.body_set_space(_bodies[index], space)
	if not _instances.has(index):
		return
	var spot: Dictionary = spots[index]
	var basis := Basis.from_euler(Vector3(tilt.x, 0.0, tilt.y)) * Basis(Vector3.UP, spot["turn"])
	basis = basis.scaled(Vector3.ONE * (0.0 if down else spot["size"]))
	_instances[index][0].set_instance_transform(_instances[index][1], Transform3D(basis, spot["position"]))


## A quick wobble when something is hit, so everyone nearby sees it.
func _shake(index: int) -> void:
	if not _instances.has(index) or not is_inside_tree():
		return
	if _shakes.has(index):
		_shakes[index].kill()
	var tween := create_tween()
	var axis := Vector2.from_angle(randf() * TAU)
	tween.tween_method(func(t: float) -> void:
		if not felled.has(index):
			_show(index, axis * sin(t * 25.0) * (1.0 - t) * 0.06), 0.0, 1.0, 0.4)
	tween.finished.connect(func() -> void: _shakes.erase(index))
	_shakes[index] = tween


## The mesh for each kind, standing on y = 0. Trees are painted in the same
## retro style as the characters (see scripts/tree_meshes.gd).
func _mesh(kind: String) -> Mesh:
	if kind != "rock":
		return TreeMeshes.mesh(kind)
	var rock := SphereMesh.new()
	rock.radius = 1.3
	rock.height = 1.6
	rock.radial_segments = 6
	rock.rings = 3
	rock.material = _material(Color(0.5, 0.5, 0.52))
	return rock


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material
