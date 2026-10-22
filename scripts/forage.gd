extends Node3D
## Things to pick up around the island: food growing wild (mushrooms,
## raspberry and blueberry bushes, and the odd apple tree), plus fallen
## branches and loose stones lying about for wood and stone. Where they grow comes from the world seed,
## so every peer places them in the same spots without sending them over the
## network, and each kind only grows in the biomes that suit it.
##
## What has been picked is the server's to decide. A player close enough
## presses E on a plant: the client asks the server, which checks the player is
## near it and that it still has something on it, puts the food in their
## inventory (dropping at their feet whatever doesn't fit) and tells every
## client what is left. A picked plant grows back after a while: an apple tree
## holds a few apples and grows them back one at a time. What's been picked is
## forgotten when the server restarts.
##
## The plants are drawn on every peer that draws anything, with every copy of
## a mesh in a region drawn at once (GPU instancing, see _build_plants). A
## dedicated server only keeps where they are and what's left on them. Apple trees have solid
## trunks on every peer, like the other trees (see harvestables.gd).

const WorldGen := preload("res://scripts/world_gen.gd")
const TreeMeshes := preload("res://scripts/tree_meshes.gd")
const Items := preload("res://scripts/items.gd")
const Sparkle := preload("res://scripts/sparkle.gd")
const Biome := WorldGen.Biome

## Meters per side of the grid cells plants are scattered in. At most one
## plant grows in each cell.
const CELL := 12.0
## Keep plants off the spawn, where the test chest and items are.
const SPAWN_CLEARING := 13.0
## Seconds between the server's checks for plants growing back.
const REGROW_CHECK_SECONDS := 1.0

## Each kind of plant: the item it gives, how many picks it holds when fully
## grown (apple trees vary between the two numbers), how many items each pick
## gives, and the seconds for one pick to grow back.
const KINDS := {
	"mushroom": { "item": "mushroom", "picks": Vector2i(1, 1), "yield": 1, "regrow": 300.0,
		"prompt": "Pick the mushroom" },
	"raspberry_bush": { "item": "berries", "picks": Vector2i(1, 1), "yield": 4, "regrow": 240.0,
		"prompt": "Pick raspberries" },
	"blueberry_bush": { "item": "blueberries", "picks": Vector2i(1, 1), "yield": 3, "regrow": 360.0,
		"prompt": "Pick blueberries" },
	"apple_tree": { "item": "apple", "picks": Vector2i(3, 6), "yield": 1, "regrow": 120.0,
		"prompt": "Pick an apple" },
	"branches": { "item": "wood", "picks": Vector2i(1, 1), "yield": 2, "regrow": 300.0,
		"prompt": "Pick up branches" },
	"loose_stones": { "item": "stone", "picks": Vector2i(1, 1), "yield": 2, "regrow": 360.0,
		"prompt": "Pick up stones" },
}
## Chance per cell of each kind, by biome. Mushrooms and raspberries are
## common, blueberries less so, apple trees rare. Branches lie where trees
## grow, loose stones where the ground is rocky. New kinds go at the end of a
## biome's list, so the plants already there stay where they are.
const DENSITY := {
	Biome.MEADOWS: { "raspberry_bush": 0.1, "mushroom": 0.04, "blueberry_bush": 0.03, "apple_tree": 0.02,
		"branches": 0.05, "loose_stones": 0.04 },
	Biome.BLACK_FOREST: { "mushroom": 0.14, "blueberry_bush": 0.05, "raspberry_bush": 0.03,
		"branches": 0.07, "loose_stones": 0.03 },
	Biome.SWAMP: { "mushroom": 0.06, "branches": 0.05 },
	Biome.PLAINS: { "raspberry_bush": 0.04, "apple_tree": 0.006, "branches": 0.02, "loose_stones": 0.06 },
	Biome.MOUNTAINS: { "blueberry_bush": 0.02, "loose_stones": 0.08 },
}
## The highest total chance in DENSITY. Cells that roll above it can't grow
## anything, so they're skipped without looking up their biome.
const MAX_ODDS := 0.32
## Apple trees' solid trunks: radius, height, and physics layer (the same as
## the other trees in harvestables.gd).
const TRUNK_RADIUS := 0.28
const TRUNK_HEIGHT := 2.6
const TRUNK_LAYER := 2
## Plants stop drawing this far from the camera, fading out over the last
## FADE_LENGTH meters.
const SMALL_VISIBLE := 90.0
const TREE_VISIBLE := 220.0
const FADE_LENGTH := 10.0
## How far the glints over things on the ground are seen (the shader fades
## each one out before this, see shaders/sparkle.gdshader).
const SPARKLE_VISIBLE := 50.0
## Meters per side of the regions plants are drawn in. Every plant in a region
## that shares a mesh is drawn together, in one MultiMesh.
const REGION := 128.0

## Server side: picks grew back or were taken. Client side: the server said so.
signal picks_changed(index: int, left: int)

## Server side: the world, for finding players and dropping what doesn't fit.
var world: Node
## Every plant on the island, in a fixed order:
## { "kind", "position": Vector3, "picks": int, "turn": float, "size": float }.
var spots: Array = []
## Plants that aren't fully grown: spot index -> picks left on it.
var left := {}
var _cells := {}  # Vector2i -> spot index
var _plants := {}  # spot index -> Plant, on peers that draw them
## On peers that draw: spot index -> part name -> [MultiMesh, instance number,
## its transform when showing, whether it's showing].
var _parts := {}
## Server side: spot index -> Time.get_ticks_msec() when its next pick grows back.
var _regrow_at := {}
## Server side: peers that have the plants and want to hear what's picked.
var _watchers := {}
var _since_check := 0.0

static var _meshes := {}
static var _materials := {}


## Something E can be pressed on: one plant, drawn on peers that draw anything.
class Plant extends Node3D:
	var forage: Node
	var index := 0

	func prompt() -> String:
		return forage.prompt_for(index)

	func interact() -> void:
		forage.pick(index)


## Places the plants from `gen`'s seed. `surface_height` is where drawn plants
## stand (the drawn ground); pass an empty Callable on a peer that draws
## nothing. `blocked`(x, z, margin) says where something solid already stands
## (see harvestables.gd), so nothing grows inside it.
func setup(gen: WorldGen, surface_height: Callable = Callable(), blocked: Callable = Callable()) -> void:
	spots = scatter(gen, blocked)
	_cells.clear()
	for i in spots.size():
		_cells[_cell_of(spots[i]["position"])] = i
	_build_trunks()
	if surface_height.is_valid():
		_build_plants(surface_height)
	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(func(peer: int) -> void: _watchers.erase(peer))
	elif multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_request_state.rpc_id(1)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_since_check += delta
	if _since_check >= REGROW_CHECK_SECONDS:
		_since_check = 0.0
		regrow(Time.get_ticks_msec())


## Every plant the seed grows, in a fixed order. Same answer for the same seed
## (and `blocked`).
static func scatter(gen: WorldGen, blocked: Callable = Callable()) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = gen.seed_number ^ 0xF0A6E
	var result := []
	var cells := int(WorldGen.SIZE / CELL)
	for j in cells:
		for i in cells:
			# Every cell draws the same numbers whatever grows there, so one
			# cell can't shift what grows in the next.
			var jitter := Vector2(rng.randf(), rng.randf())
			var roll := rng.randf()
			var turn := rng.randf() * TAU
			var size := rng.randf()
			var picks_roll := rng.randf()
			if roll >= MAX_ODDS:
				continue
			var x := (i + jitter.x) * CELL - WorldGen.SIZE * 0.5
			var z := (j + jitter.y) * CELL - WorldGen.SIZE * 0.5
			if Vector2(x, z).length() < SPAWN_CLEARING:
				continue
			var h := gen.height_at(x, z)
			var odds: Dictionary = DENSITY.get(gen.biome_for(x, z, h), {})
			for kind in odds:
				if roll >= odds[kind]:
					roll -= odds[kind]
					continue
				if h < WorldGen.SEA_LEVEL + 0.3 or _steep(gen, x, z, h) \
						or (blocked.is_valid() and blocked.call(x, z, 0.8)):
					break
				var picks: Vector2i = KINDS[kind]["picks"]
				result.append({ "kind": kind, "position": Vector3(x, h, z), "turn": turn,
					"size": lerpf(0.85, 1.2, size),
					"picks": picks.x + int(picks_roll * (picks.y - picks.x + 1)) })
				break
	return result


static func _steep(gen: WorldGen, x: float, z: float, h: float) -> bool:
	var dx := gen.height_at(x + 1.0, z) - h
	var dz := gen.height_at(x, z + 1.0) - h
	return dx * dx + dz * dz > 0.6


## How many picks are on a plant right now.
func picks_left(index: int) -> int:
	return left.get(index, spots[index]["picks"])


## The nearest plant within `max_distance` of `point` with something on it,
## or -1.
func nearest(point: Vector3, max_distance: float) -> int:
	var best := -1
	var best_distance := max_distance
	var cell := _cell_of(point)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var index: int = _cells.get(cell + Vector2i(dx, dz), -1)
			if index < 0 or picks_left(index) == 0:
				continue
			var distance: float = spots[index]["position"].distance_to(point)
			if distance <= best_distance:
				best = index
				best_distance = distance
	return best


## The drawn plant nearest `point` that E would pick, or null.
func nearest_plant(point: Vector3, max_distance: float) -> Node3D:
	return _plants.get(nearest(point, max_distance))


## What pressing E on a plant does, for the on-screen prompt.
func prompt_for(index: int) -> String:
	var kind: Dictionary = KINDS[spots[index]["kind"]]
	var text: String = kind["prompt"]
	if spots[index]["picks"] > 1:
		text += " (%d left)" % picks_left(index)
	return text


## Client side: ask the server to pick a plant.
func pick(index: int) -> void:
	_request_pick.rpc_id(1, index)


## Server side: takes one pick off a plant and starts it growing back.
## Returns how many items the pick gives, or 0 if there was nothing on it.
func take(index: int, now_msec: int) -> int:
	var have := picks_left(index)
	if have <= 0:
		return 0
	_set_picks(index, have - 1)
	if not _regrow_at.has(index):
		_regrow_at[index] = now_msec + _regrow_msec(index)
	return KINDS[spots[index]["kind"]]["yield"]


## Server side: grows back every pick that's due by `now_msec`.
func regrow(now_msec: int) -> void:
	for index in _regrow_at.keys():
		if _regrow_at[index] > now_msec:
			continue
		var have := picks_left(index) + 1
		_set_picks(index, have)
		if have >= spots[index]["picks"]:
			_regrow_at.erase(index)
		else:
			_regrow_at[index] += _regrow_msec(index)


func _regrow_msec(index: int) -> int:
	return int(KINDS[spots[index]["kind"]]["regrow"] * 1000.0)


func _set_picks(index: int, count: int) -> void:
	if count >= spots[index]["picks"]:
		left.erase(index)
	else:
		left[index] = count
	_show(index)
	picks_changed.emit(index, count)
	if multiplayer.is_server():
		for peer in _watchers:
			_set_left.rpc_id(peer, index, count)


func _cell_of(point: Vector3) -> Vector2i:
	return Vector2i(floori((point.x + WorldGen.SIZE * 0.5) / CELL),
		floori((point.z + WorldGen.SIZE * 0.5) / CELL))


# --- Network ----------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func _request_pick(index) -> void:
	if not multiplayer.is_server() or not index is int or index < 0 or index >= spots.size():
		return
	var peer := multiplayer.get_remote_sender_id()
	# Looked up rather than named, so tests can load this without autoloads.
	var session := get_node("/root/Session")
	var inventory = session.inventory_of(peer)
	if inventory == null or world == null or not world.is_near(peer, spots[index]["position"]):
		return
	var count := take(index, Time.get_ticks_msec())
	if count == 0:
		return
	var item: String = KINDS[spots[index]["kind"]]["item"]
	var spare: int = inventory.add(item, count)
	if spare > 0:
		world.drop_item(peer, item, spare)
	session.inventory_updated(peer)


## A client has built the plants: send it everything that's been picked, and
## what's picked from now on.
@rpc("any_peer", "reliable")
func _request_state() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	_watchers[peer] = true
	_set_state.rpc_id(peer, left)


@rpc("authority", "reliable")
func _set_state(state: Dictionary) -> void:
	for index in left.keys():
		left.erase(index)
		_show(index)
	for index in state:
		if index is int and index >= 0 and index < spots.size():
			left[index] = int(state[index])
			_show(index)


@rpc("authority", "reliable")
func _set_left(index: int, count: int) -> void:
	if index < 0 or index >= spots.size():
		return
	if count >= spots[index]["picks"]:
		left.erase(index)
	else:
		left[index] = count
	_show(index)
	picks_changed.emit(index, count)


# --- Solid trunks -----------------------------------------------------------

func _build_trunks() -> void:
	var shape := CylinderShape3D.new()
	shape.radius = TRUNK_RADIUS
	shape.height = TRUNK_HEIGHT
	for i in spots.size():
		if spots[i]["kind"] != "apple_tree":
			continue
		var body := StaticBody3D.new()
		body.name = "Trunk_%d" % i
		body.collision_layer = TRUNK_LAYER
		body.collision_mask = 0
		body.position = spots[i]["position"] + Vector3.UP * TRUNK_HEIGHT * 0.5
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		add_child(body)


# --- Drawing ----------------------------------------------------------------

func _build_plants(surface_height: Callable) -> void:
	var regions := {}  # Vector2i -> mesh name -> [[spot index, part, Transform3D], ...]
	for i in spots.size():
		var spot: Dictionary = spots[i]
		var at: Vector3 = spot["position"]
		var plant := Plant.new()
		plant.forage = self
		plant.index = i
		plant.name = "%s_%d" % [spot["kind"].to_pascal_case(), i]
		plant.position = Vector3(at.x, surface_height.call(at.x, at.z) - 0.03, at.z)
		plant.rotation.y = spot["turn"]
		plant.scale = Vector3.ONE * spot["size"]
		_plants[i] = plant
		add_child(plant)
		var key := Vector2i(floori((at.x + WorldGen.SIZE * 0.5) / REGION),
			floori((at.z + WorldGen.SIZE * 0.5) / REGION))
		if not regions.has(key):
			regions[key] = {}
		var parts := []  # [mesh name, part, offset from the plant]
		match spot["kind"]:
			"raspberry_bush":
				parts = [["raspberry_bush", "Body", Vector3.ZERO], ["raspberries", "Fruit", Vector3.ZERO]]
			"blueberry_bush":
				parts = [["blueberry_bush", "Body", Vector3.ZERO], ["blueberries", "Fruit", Vector3.ZERO]]
			"apple_tree":
				parts = [["apple_tree", "Body", Vector3.ZERO]]
				for n in spot["picks"]:
					var a: float = n * TAU / spot["picks"] + 0.4
					parts.append(["apple", "Apple%d" % n, Vector3(cos(a) * 1.5, 2.45 + (n % 2) * 0.35, sin(a) * 1.5)])
			"mushroom":
				parts = [["mushrooms", "Body", Vector3.ZERO]]
			_:
				parts = [[spot["kind"], "Body", Vector3.ZERO]]
		if spot["kind"] in ["mushroom", "branches", "loose_stones"]:
			# Things lying on the ground glint, so they stand out from the
			# scenery (see scripts/sparkle.gd).
			parts.append(["sparkle", "Sparkle", Vector3.UP * Sparkle.HEIGHT])
		for part in parts:
			if not regions[key].has(part[0]):
				regions[key][part[0]] = []
			regions[key][part[0]].append([i, part[1], plant.transform * Transform3D(Basis(), part[2])])
	for key in regions:
		var center := (Vector3(key.x, 0.0, key.y) + Vector3(0.5, 0.0, 0.5)) * REGION \
			- Vector3(WorldGen.SIZE * 0.5, 0.0, WorldGen.SIZE * 0.5)
		var region := Node3D.new()
		region.name = "Plants_%d_%d" % [key.x, key.y]
		region.position = center
		for mesh_name in regions[key]:
			region.add_child(_make_instances(mesh_name, regions[key][mesh_name], center))
		add_child(region)
	for i in spots.size():
		_show(i)


## One MultiMeshInstance3D drawing `mesh_name` for every [spot index, part,
## transform] in `placed`, positioned relative to `center`.
func _make_instances(mesh_name: String, placed: Array, center: Vector3) -> MultiMeshInstance3D:
	var tree := mesh_name == "apple_tree"
	var sparkle := mesh_name == "sparkle"
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _mesh(mesh_name, TREE_VISIBLE if tree else SMALL_VISIBLE)
	multimesh.instance_count = placed.size()
	for n in placed.size():
		var spot: int = placed[n][0]
		var local: Transform3D = placed[n][2]
		local.origin -= center
		if not _parts.has(spot):
			_parts[spot] = {}
		_parts[spot][placed[n][1]] = [multimesh, n, local, true]
		multimesh.set_instance_transform(n, local)
	var instance := MultiMeshInstance3D.new()
	instance.name = mesh_name.to_pascal_case()
	instance.multimesh = multimesh
	# Each plant fades out on its own (see _material); this just stops drawing
	# whole regions once every plant in them has faded.
	instance.visibility_range_end = (TREE_VISIBLE if tree else SMALL_VISIBLE) + REGION * 0.75
	if sparkle:
		instance.visibility_range_end = SPARKLE_VISIBLE + REGION * 0.75
	if not tree:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


## Whether a part of a drawn plant ("Body", "Fruit", "Sparkle" or "Apple0".."Apple5") is
## showing.
func is_shown(index: int, part: String) -> bool:
	if not _parts.has(index) or not _parts[index].has(part):
		return false
	return _parts[index][part][3]


func _set_shown(index: int, part: String, shown: bool) -> void:
	var slot: Array = _parts[index][part]
	slot[3] = shown
	var local: Transform3D = slot[2]
	if not shown:
		local.basis = local.basis.scaled(Vector3.ZERO)
	slot[0].set_instance_transform(slot[1], local)


## Shows what's left on a drawn plant: mushrooms vanish when picked, bushes
## lose their berries, and apple trees show one apple per pick left.
func _show(index: int) -> void:
	if not _parts.has(index):
		return
	var have := picks_left(index)
	match spots[index]["kind"]:
		"mushroom", "branches", "loose_stones":
			_set_shown(index, "Body", have > 0)
			_set_shown(index, "Sparkle", have > 0)
		"apple_tree":
			for n in spots[index]["picks"]:
				_set_shown(index, "Apple%d" % n, n < have)
		_:
			_set_shown(index, "Fruit", have > 0)


## A plant's mesh, made of one surface per color, fading out by `fade_end`
## meters from the camera.
static func _mesh(mesh_name: String, fade_end: float) -> Mesh:
	var key := "%s@%d" % [mesh_name, fade_end]
	if _meshes.has(key):
		return _meshes[key]
	var mesh := ArrayMesh.new()
	match mesh_name:
		"sparkle":
			return Sparkle.mesh()
		"mushrooms":
			# A little cluster of brown caps on pale stems.
			var stems := []
			var caps := []
			for m in [[Vector3.ZERO, 1.0], [Vector3(0.18, 0.0, 0.08), 0.7], [Vector3(-0.08, 0.0, 0.16), 0.55]]:
				var at: Vector3 = m[0]
				var s: float = m[1]
				stems.append([_cylinder(0.035, 0.05, 0.2), Transform3D(Basis().scaled(Vector3.ONE * s), at + Vector3.UP * 0.1 * s)])
				caps.append([_cap(0.14, 0.12), Transform3D(Basis().scaled(Vector3.ONE * s), at + Vector3.UP * 0.18 * s)])
			_add_surface(mesh, stems, Color(0.92, 0.88, 0.78), fade_end)
			_add_surface(mesh, caps, Color(0.6, 0.38, 0.2), fade_end)
		"raspberry_bush", "blueberry_bush":
			var raspberry := mesh_name == "raspberry_bush"
			var r := 0.55 if raspberry else 0.42
			var parts := []
			for n in 4:
				var a := n * TAU / 3.0
				var at := Vector3.UP * r * 0.9 if n == 3 else Vector3(cos(a) * r * 0.5, r * 0.7, sin(a) * r * 0.5)
				parts.append([_ball(r * (0.8 if n == 3 else 0.7)), Transform3D(Basis(), at)])
			_add_surface(mesh, parts, Color(0.27, 0.5, 0.2) if raspberry else Color(0.2, 0.36, 0.22), fade_end)
		"raspberries", "blueberries":
			var raspberry := mesh_name == "raspberries"
			var r := 0.55 if raspberry else 0.42
			var rng := RandomNumberGenerator.new()
			rng.seed = 7 if raspberry else 11
			var parts := []
			for n in 18:
				var a := rng.randf() * TAU
				var up := rng.randf_range(0.15, 0.85)
				var dir := Vector3(cos(a) * (1.0 - up * 0.6), up, sin(a) * (1.0 - up * 0.6)).normalized()
				parts.append([_ball(0.045 if raspberry else 0.035), Transform3D(Basis(), Vector3.UP * r * 0.7 + dir * r * 0.95)])
			_add_surface(mesh, parts, Color(0.85, 0.1, 0.22) if raspberry else Color(0.2, 0.25, 0.75), fade_end)
		"apple_tree":
			# Painted like the other trees (see scripts/tree_meshes.gd), and
			# shrinking away where the apples fade.
			mesh = TreeMeshes.mesh("apple", fade_end - FADE_LENGTH, fade_end)
		"apple":
			_add_surface(mesh, [[_ball(0.11), Transform3D()]], Color(0.82, 0.12, 0.1), fade_end)
		"branches":
			# A few sticks lying crossed on the ground.
			var sticks := []
			for b in [[0.0, 0.9, 0.035], [1.1, 0.75, 0.03], [2.3, 0.6, 0.025]]:
				var lie := Basis(Vector3.UP, b[0]) * Basis(Vector3.FORWARD, PI * 0.5)
				sticks.append([_cylinder(b[2], b[2] * 1.3, b[1]), Transform3D(lie, Vector3.UP * b[2])])
			_add_surface(mesh, sticks, Color(0.45, 0.3, 0.17), fade_end)
		"loose_stones":
			# A small pile of flattened grey stones.
			var stones := []
			for p in [[Vector3.ZERO, 0.16], [Vector3(0.22, 0.0, 0.08), 0.11], [Vector3(-0.12, 0.0, 0.18), 0.09]]:
				var r: float = p[1]
				stones.append([_ball(r), Transform3D(Basis().scaled(Vector3(1.0, 0.6, 0.9)), p[0] + Vector3.UP * r * 0.4)])
			_add_surface(mesh, stones, Color(0.56, 0.56, 0.58), fade_end)
	_meshes[key] = mesh
	return mesh


## Joins `parts` ([PrimitiveMesh, Transform3D] pairs) into one surface of
## `mesh` in one color, fading out by `fade_end` (see _material).
static func _add_surface(mesh: ArrayMesh, parts: Array, color: Color, fade_end: float) -> void:
	var st := SurfaceTool.new()
	for part in parts:
		st.append_from(part[0], 0, part[1])
	st.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, _material(color, fade_end))


## A plain material in `color`. Each plant dithers away over the last
## FADE_LENGTH meters before `fade_end` from the camera, so plants that share
## one MultiMesh still disappear one at a time.
static func _material(color: Color, fade_end: float) -> StandardMaterial3D:
	var key := "%s@%d" % [color.to_html(), fade_end]
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.85
		material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
		# Reversed (min past max), so it fades out with distance.
		material.distance_fade_min_distance = fade_end
		material.distance_fade_max_distance = fade_end - FADE_LENGTH
		_materials[key] = material
	return _materials[key]


static func _ball(radius: float) -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 5
	return sphere


static func _cap(radius: float, height: float) -> SphereMesh:
	var cap := SphereMesh.new()
	cap.radius = radius
	cap.height = height
	cap.is_hemisphere = true
	cap.radial_segments = 8
	cap.rings = 3
	return cap


static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = top
	cylinder.bottom_radius = bottom
	cylinder.height = height
	cylinder.radial_segments = 6
	cylinder.rings = 1
	return cylinder
