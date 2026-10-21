extends Node3D
## Plants that cover the island, scattered from the world seed so every player
## sees them in the same places. Only built on peers that draw anything, and
## only scenery: nothing collides with them.
##
## Two layers:
## - Shrubs (bushes, birches, logs and stumps) are scattered over the whole
##   island once, in regions that stop drawing far from the camera.
## - Ground cover (grass, flowers, ferns and reeds) is far too dense
##   to build for the whole island, so it's built in small chunks around the
##   camera as it moves and freed behind it.
##
## Every mesh is made here from simple shapes and drawn with one shader
## (shaders/foliage.gdshaderinc) that sways it in the wind and tints it per plant.

const WorldGen := preload("res://scripts/world_gen.gd")
const BLADES_SHADER := preload("res://shaders/foliage_blades.gdshader")
const SOLID_SHADER := preload("res://shaders/foliage_solid.gdshader")
const Biome := WorldGen.Biome

## Meters per side of a ground cover chunk, and of the cell each plant is
## jittered inside.
const COVER_CHUNK := 24.0
const COVER_CELL := 0.7
## Ground cover is drawn this far from the camera, shrinking away over the
## last stretch.
const COVER_RADIUS := 64.0
const COVER_FADE_START := 46.0
## Chunks built per frame (about 5 ms each), so walking doesn't hitch.
const CHUNKS_PER_FRAME := 1

const SHRUB_CELL := 4.0
const SHRUB_REGION := 128.0
const SHRUB_FADE_START := 170.0
const SHRUB_FADE_END := 200.0
## Keep shrubs off the spawn, where the test chest and items are.
const SPAWN_CLEARING := 14.0

## Chance per cell of each plant, by biome. Each plant names its mesh and the
## tints it picks from.
const COVER_DENSITY := {
	Biome.MEADOWS: { "grass": 0.8, "flower": 0.09 },
	Biome.BLACK_FOREST: { "fern": 0.1, "forest_grass": 0.3 },
	Biome.SWAMP: { "reeds": 0.1, "swamp_grass": 0.45 },
	Biome.PLAINS: { "dry_grass": 0.55, "plains_flower": 0.02 },
	Biome.MOUNTAINS: { "grass": 0.2 },
}
const SHRUB_DENSITY := {
	Biome.MEADOWS: { "bush": 0.04, "birch": 0.014, "stump": 0.004 },
	Biome.BLACK_FOREST: { "bush": 0.05, "log": 0.02, "stump": 0.015 },
	Biome.SWAMP: { "dead_bush": 0.04, "log": 0.015 },
	Biome.PLAINS: { "shrub": 0.04 },
	Biome.MOUNTAINS: { "shrub": 0.012 },
}
## Plant -> [mesh, scale range, tints].
const PLANTS := {
	"grass": ["tuft", Vector2(0.8, 1.3), [Color(0.5, 0.78, 0.3), Color(0.58, 0.82, 0.32), Color(0.45, 0.7, 0.28)]],
	"forest_grass": ["tuft", Vector2(0.7, 1.1), [Color(0.26, 0.42, 0.2), Color(0.3, 0.45, 0.22)]],
	"swamp_grass": ["tuft", Vector2(0.9, 1.4), [Color(0.4, 0.42, 0.24), Color(0.36, 0.4, 0.2)]],
	"dry_grass": ["tuft", Vector2(1.0, 1.5), [Color(0.78, 0.7, 0.36), Color(0.7, 0.66, 0.32), Color(0.62, 0.62, 0.3)]],
	"flower": ["flower", Vector2(1.0, 1.5), [Color(1, 1, 1), Color(1.0, 0.85, 0.2), Color(0.7, 0.45, 0.95), Color(0.45, 0.6, 1.0)]],
	"plains_flower": ["flower", Vector2(0.8, 1.1), [Color(1.0, 0.75, 0.2), Color(0.95, 0.4, 0.2)]],
	"fern": ["fern", Vector2(0.8, 1.4), [Color(0.2, 0.4, 0.15), Color(0.25, 0.45, 0.17)]],
	"reeds": ["reeds", Vector2(0.8, 1.2), [Color(0.45, 0.5, 0.26), Color(0.5, 0.52, 0.28)]],
	"bush": ["bush", Vector2(0.8, 1.5), [Color(0.3, 0.52, 0.2), Color(0.25, 0.45, 0.18), Color(0.35, 0.55, 0.22)]],
	"birch": ["birch", Vector2(0.8, 1.2), [Color(0.55, 0.72, 0.28), Color(0.62, 0.75, 0.3)]],
	"stump": ["stump", Vector2(0.8, 1.3), [Color(1, 1, 1)]],
	"log": ["log", Vector2(0.8, 1.3), [Color(1, 1, 1)]],
	"dead_bush": ["dead_bush", Vector2(0.8, 1.4), [Color(1, 1, 1)]],
	"shrub": ["bush", Vector2(0.5, 0.9), [Color(0.5, 0.5, 0.26), Color(0.42, 0.45, 0.22)]],
}
## Grass tufts come in three sizes: [share of tufts, scale]. The scale
## multiplies the plant's own range, so large is the full-size tuft.
const TUFT_SIZES := [[0.5, 0.4], [0.32, 0.65], [0.18, 1.0]]
## Thin meshes seen from both sides. The rest are closed shapes.
const TWO_SIDED := ["tuft", "flower", "fern", "reeds"]
## Meshes that cast shadows. Small plants don't, which saves a lot of drawing.
const SHADOWED := ["bush", "birch", "stump", "log", "dead_bush"]
## How far each mesh sways at its top.
const SWAY := { "tuft": 0.12, "flower": 0.1, "fern": 0.06, "reeds": 0.18, "bush": 0.04,
	"birch": 0.15, "dead_bush": 0.03 }

## Ground cover is built from the same seed as the island.
var seed_number := 0
## Callables into the terrain: height(x, z) -> float, biome(x, z) -> Biome.
var _height: Callable
var _biome: Callable
var _meshes := {}
var _materials := {}
var _chunks := {}  # Vector2i -> Node3D


## `height` and `biome` look up the ground at (x, z).
func setup(p_seed_number: int, height: Callable, biome: Callable) -> void:
	seed_number = p_seed_number
	_height = height
	_biome = biome
	_build_shrubs()


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or not _height.is_valid():
		return
	update_cover(camera.global_position)


## Builds the ground cover chunks near `center` that are missing, nearest
## first, and frees the ones that are now too far away.
func update_cover(center: Vector3, max_chunks: int = CHUNKS_PER_FRAME) -> void:
	var here := Vector2(center.x, center.z)
	for key in _chunks.keys():
		if _chunk_center(key).distance_to(here) > COVER_RADIUS + COVER_CHUNK:
			_chunks[key].queue_free()
			_chunks.erase(key)
	var wanted: Array[Vector2i] = []
	var reach := int(ceil(COVER_RADIUS / COVER_CHUNK)) + 1
	var middle := Vector2i(floori(here.x / COVER_CHUNK), floori(here.y / COVER_CHUNK))
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var key := middle + Vector2i(dx, dz)
			if not _chunks.has(key) and _chunk_center(key).distance_to(here) < COVER_RADIUS + COVER_CHUNK * 0.71:
				wanted.append(key)
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_center(a).distance_squared_to(here) < _chunk_center(b).distance_squared_to(here))
	for key in wanted.slice(0, max_chunks):
		var chunk := _make_node(cover_for_chunk(key), Vector3(_chunk_center(key).x, 0.0, _chunk_center(key).y))
		chunk.name = "Cover_%d_%d" % [key.x, key.y]
		_chunks[key] = chunk
		add_child(chunk)


## The ground cover of one chunk: mesh name -> [transforms, tints], with
## transforms relative to the chunk's center. Same answer for the same seed.
func cover_for_chunk(key: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed_number ^ (key.x * 73856093) ^ (key.y * 19349663)) & 0x7FFFFFFFFFFFFFFF
	var origin := Vector2(key) * COVER_CHUNK
	var cells := int(COVER_CHUNK / COVER_CELL)
	var center := origin + Vector2.ONE * COVER_CHUNK * 0.5
	return _scatter(rng, origin, cells, COVER_CELL, COVER_DENSITY, center, 0.0)


## Whether any ground cover is built around the camera right now.
func cover_chunk_count() -> int:
	return _chunks.size()


func _chunk_center(key: Vector2i) -> Vector2:
	return (Vector2(key) + Vector2.ONE * 0.5) * COVER_CHUNK


func _build_shrubs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_number ^ 0x5EED5
	var regions := int(WorldGen.SIZE / SHRUB_REGION)
	var cells := int(SHRUB_REGION / SHRUB_CELL)
	for rz in regions:
		for rx in regions:
			var origin := Vector2(rx, rz) * SHRUB_REGION - Vector2.ONE * WorldGen.SIZE * 0.5
			var center := origin + Vector2.ONE * SHRUB_REGION * 0.5
			var placed := _scatter(rng, origin, cells, SHRUB_CELL, SHRUB_DENSITY, center, SPAWN_CLEARING)
			if placed.is_empty():
				continue
			var region := _make_node(placed, Vector3(center.x, 0.0, center.y))
			region.name = "Shrubs_%d_%d" % [rx, rz]
			for child in region.get_children():
				# Stop drawing whole regions well past where their plants have
				# shrunk away.
				child.visibility_range_end = SHRUB_FADE_END + SHRUB_REGION * 0.75
			add_child(region)


## Scatters plants over a square of cells x cells, one roll per cell, and
## groups them by mesh. Every cell draws the same random numbers whatever
## grows there, so one cell can't shift what grows in the next.
func _scatter(rng: RandomNumberGenerator, origin: Vector2, cells: int, cell: float,
		density: Dictionary, center: Vector2, clearing: float) -> Dictionary:
	var placed := {}
	for j in cells:
		for i in cells:
			var x := origin.x + (i + rng.randf()) * cell
			var z := origin.y + (j + rng.randf()) * cell
			var roll := rng.randf()
			var size := rng.randf()
			var turn := rng.randf() * TAU
			var pick := rng.randf()
			if clearing > 0.0 and Vector2(x, z).length() < clearing:
				continue
			var odds: Dictionary = density.get(_biome.call(x, z), {})
			for plant in odds:
				if roll >= odds[plant]:
					roll -= odds[plant]
					continue
				var h: float = _height.call(x, z)
				if h < WorldGen.SEA_LEVEL + 0.2 or h > 64.0 or _steep(x, z, h):
					break
				var info: Array = PLANTS[plant]
				var scale: Vector2 = info[1]
				var tints: Array = info[2]
				var grow := lerpf(scale.x, scale.y, size)
				if info[0] == "tuft":
					grow = _tuft_scale(scale, size)
				var basis := Basis(Vector3.UP, turn).scaled(Vector3.ONE * grow)
				if not placed.has(info[0]):
					placed[info[0]] = [[], []]
				placed[info[0]][0].append(Transform3D(basis, Vector3(x - center.x, h - 0.05, z - center.y)))
				placed[info[0]][1].append(tints[int(pick * tints.size()) % tints.size()])
				break
	return placed


## Picks a tuft's size from TUFT_SIZES with `size`, then its scale within
## that size from what's left of the same roll.
func _tuft_scale(scale: Vector2, size: float) -> float:
	for tier in TUFT_SIZES:
		if size < tier[0]:
			return lerpf(scale.x, scale.y, size / tier[0]) * tier[1]
		size -= tier[0]
	return scale.y * TUFT_SIZES[-1][1]


func _steep(x: float, z: float, h: float) -> bool:
	var dx: float = _height.call(x + 1.0, z) - h
	var dz: float = _height.call(x, z + 1.0) - h
	return dx * dx + dz * dz > 0.6


## A node holding one MultiMeshInstance3D per mesh in `placed`.
func _make_node(placed: Dictionary, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.position = at
	for mesh_name in placed:
		var transforms: Array = placed[mesh_name][0]
		var tints: Array = placed[mesh_name][1]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		# Unused by the shader, but without it the Compatibility renderer
		# multiplies every vertex color by black.
		multimesh.use_colors = true
		multimesh.mesh = _mesh(mesh_name)
		multimesh.instance_count = transforms.size()
		for n in transforms.size():
			multimesh.set_instance_transform(n, transforms[n])
			multimesh.set_instance_color(n, Color.WHITE)
			multimesh.set_instance_custom_data(n, tints[n])
		var instance := MultiMeshInstance3D.new()
		instance.name = mesh_name.to_pascal_case()
		instance.multimesh = multimesh
		instance.material_override = _material(mesh_name)
		if mesh_name not in SHADOWED:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(instance)
	return node


func _material(mesh_name: String) -> ShaderMaterial:
	if not _materials.has(mesh_name):
		var material := ShaderMaterial.new()
		material.shader = BLADES_SHADER if mesh_name in TWO_SIDED else SOLID_SHADER
		material.set_shader_parameter("sway", SWAY.get(mesh_name, 0.0))
		var shrub: bool = SHRUB_DENSITY.values().any(func(d: Dictionary) -> bool:
			return d.keys().any(func(p: String) -> bool: return PLANTS[p][0] == mesh_name))
		material.set_shader_parameter("fade_start", SHRUB_FADE_START if shrub else COVER_FADE_START)
		material.set_shader_parameter("fade_end", SHRUB_FADE_END if shrub else COVER_RADIUS)
		material.set_shader_parameter("up_normals", mesh_name in TWO_SIDED)
		_materials[mesh_name] = material
	return _materials[mesh_name]


# --- Meshes -----------------------------------------------------------------
# Each stands on y = 0. Vertex color alpha 1 marks the parts that take a
# plant's tint; UV.y is how much a vertex sways.

const STEM_GREEN := Color(0.3, 0.5, 0.18, 0.0)
const BARK := Color(0.32, 0.22, 0.14, 0.0)
const BIRCH_BARK := Color(0.88, 0.86, 0.8, 0.0)


func _mesh(mesh_name: String) -> Mesh:
	if not _meshes.has(mesh_name):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rng := RandomNumberGenerator.new()
		rng.seed = mesh_name.length() * 101 + 7
		call("_shape_" + mesh_name, st, rng)
		_meshes[mesh_name] = st.commit()
	return _meshes[mesh_name]


func _shape_tuft(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	for b in 7:
		var angle := b * TAU / 7.0 + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var height := rng.randf_range(0.3, 0.55)
		var root := out * rng.randf() * 0.1
		var lean := out * rng.randf_range(0.08, 0.22)
		_blade(st, root, root + lean * 0.3 + Vector3.UP * height * 0.55, root + lean + Vector3.UP * height,
			rng.randf_range(0.05, 0.08), Color(0.5, 0.5, 0.5, 1.0), Color(1, 1, 1, 1))


func _shape_flower(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var height := 0.38
	var lean := Vector3(0.03, 0.0, 0.02)
	_blade(st, Vector3.ZERO, lean * 0.4 + Vector3.UP * height * 0.5, lean + Vector3.UP * height,
		0.025, STEM_GREEN, STEM_GREEN)
	for b in 2:
		var out := Vector3(cos(b * PI + 0.5), 0.0, sin(b * PI + 0.5))
		_blade(st, out * 0.02, out * 0.1 + Vector3.UP * 0.1, out * 0.16 + Vector3.UP * 0.12, 0.05,
			STEM_GREEN, STEM_GREEN)
	var top := lean + Vector3.UP * height
	var petals := 5
	for p in petals:
		var a := p * TAU / petals
		var tip := top + Vector3(cos(a), 0.15, sin(a)) * 0.12
		var left := top + Vector3(cos(a - 0.5), 0.08, sin(a - 0.5)) * 0.08
		var right := top + Vector3(cos(a + 0.5), 0.08, sin(a + 0.5)) * 0.08
		_tri(st, [top, left, tip], Color(1, 1, 1, 1), 1.0)
		_tri(st, [top, tip, right], Color(1, 1, 1, 1), 1.0)
	_sphere(st, top + Vector3.UP * 0.015, Vector3(0.022, 0.015, 0.022), Color(0.95, 0.75, 0.1, 0.0), 5, 3, 1.0)


func _shape_fern(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var fronds := 8
	for f in fronds:
		var a := f * TAU / fronds + rng.randf_range(-0.2, 0.2)
		var out := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-out.z, 0.0, out.x)
		var length := rng.randf_range(0.6, 0.85)
		var rise := rng.randf_range(0.35, 0.5)
		# Arches up and out, then droops at the tip.
		var spine := [Vector3.ZERO, out * length * 0.3 + Vector3.UP * rise * 0.8,
			out * length * 0.6 + Vector3.UP * rise, out * length * 0.85 + Vector3.UP * rise * 0.7,
			out * length + Vector3.UP * rise * 0.35]
		var widths := [0.0, 0.12, 0.14, 0.09, 0.0]
		for s in spine.size() - 1:
			var a0: Vector3 = spine[s]
			var a1: Vector3 = spine[s + 1]
			var w0: float = widths[s]
			var w1: float = widths[s + 1]
			var c0 := Color(0.55, 0.55, 0.55, 1.0).lerp(Color(1, 1, 1, 1), s / 4.0)
			var c1 := Color(0.55, 0.55, 0.55, 1.0).lerp(Color(1, 1, 1, 1), (s + 1) / 4.0)
			_quad(st, a0 - side * w0, a0 + side * w0, a1 + side * w1, a1 - side * w1, c0, c1, s / 4.0, (s + 1) / 4.0)


func _shape_reeds(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	for b in 9:
		var a := b * TAU / 9.0 + rng.randf()
		var out := Vector3(cos(a), 0.0, sin(a))
		var root := out * rng.randf() * 0.2
		var height := rng.randf_range(0.9, 1.6)
		var tip := root + out * rng.randf_range(0.05, 0.25) + Vector3.UP * height
		_blade(st, root, root.lerp(tip, 0.5) - out * 0.03, tip, 0.045,
			Color(0.55, 0.55, 0.55, 1.0), Color(1, 1, 1, 1))
		if b % 3 == 0:
			# A cattail head on every third stalk.
			_sphere(st, root.lerp(tip, 0.88), Vector3(0.04, 0.12, 0.04), Color(0.35, 0.22, 0.12, 0.0), 5, 3, 1.0)


func _shape_bush(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	for n in 5:
		var a := n * TAU / 5.0
		var r := 0.0 if n == 0 else 0.45
		var center := Vector3(cos(a) * r, 0.55 + rng.randf_range(-0.1, 0.15) if n else 0.75, sin(a) * r)
		var size := rng.randf_range(0.45, 0.6) if n else 0.65
		var shade := rng.randf_range(0.8, 1.0)
		_sphere(st, center, Vector3(size, size * 0.8, size), Color(shade, shade, shade, 1.0), 7, 5, center.y, false, true)


func _shape_birch(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	_cylinder(st, Vector3.ZERO, Vector3.UP * 6.5, 0.22, 0.12, BIRCH_BARK, 7)
	# Dark marks on the bark.
	for n in 6:
		var y := rng.randf_range(0.6, 5.0)
		var a := rng.randf() * TAU
		var on := Vector3(cos(a) * 0.19, y, sin(a) * 0.19)
		_sphere(st, on, Vector3(0.06, 0.04, 0.06), Color(0.15, 0.13, 0.12, 0.0), 4, 2, 0.0)
	for n in 4:
		var a := n * TAU / 4.0 + rng.randf()
		var center := Vector3(cos(a) * 0.6, rng.randf_range(4.6, 6.2), sin(a) * 0.6)
		_sphere(st, center, Vector3(1.2, 1.6, 1.2), Color(1, 1, 1, 1), 7, 5, center.y / 6.5, false, true)
	_sphere(st, Vector3.UP * 6.8, Vector3(1.0, 1.4, 1.0), Color(1, 1, 1, 1), 7, 5, 1.0, false, true)


func _shape_stump(st: SurfaceTool, _rng: RandomNumberGenerator) -> void:
	_cylinder(st, Vector3.ZERO, Vector3.UP * 0.55, 0.45, 0.38, BARK, 8)
	_disk(st, Vector3.UP * 0.55, 0.36, Color(0.7, 0.55, 0.35, 0.0), 8)


func _shape_log(st: SurfaceTool, _rng: RandomNumberGenerator) -> void:
	var a := Vector3(-1.8, 0.3, 0.0)
	var b := Vector3(1.8, 0.25, 0.1)
	_cylinder(st, a, b, 0.32, 0.28, Color(0.36, 0.26, 0.17, 0.0), 8)
	# A patch of moss along the top.
	_sphere(st, Vector3(-0.3, 0.52, 0.04), Vector3(1.1, 0.1, 0.22), Color(0.25, 0.42, 0.16, 0.0), 6, 3, 0.0)


func _shape_dead_bush(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	for n in 7:
		var a := n * TAU / 7.0 + rng.randf()
		var tip := Vector3(cos(a) * rng.randf_range(0.4, 0.8), rng.randf_range(0.6, 1.2), sin(a) * rng.randf_range(0.4, 0.8))
		_cylinder(st, Vector3.ZERO, tip, 0.04, 0.01, Color(0.3, 0.26, 0.2, 0.0), 4)


# --- Shape helpers ----------------------------------------------------------

## A blade that bends at `mid`: wide at the root, pointed at the tip.
func _blade(st: SurfaceTool, root: Vector3, mid: Vector3, tip: Vector3, width: float,
		root_color: Color, tip_color: Color) -> void:
	var side := (tip - root).cross(Vector3.UP).normalized()
	if side == Vector3.ZERO:
		side = Vector3.RIGHT
	var mid_color := root_color.lerp(tip_color, 0.55)
	_quad(st, root - side * width * 0.5, root + side * width * 0.5, mid + side * width * 0.35,
		mid - side * width * 0.35, root_color, mid_color, 0.0, 0.55)
	_vertex(st, mid - side * width * 0.35, Vector3.UP, mid_color, 0.55)
	_vertex(st, mid + side * width * 0.35, Vector3.UP, mid_color, 0.55)
	_vertex(st, tip, Vector3.UP, tip_color, 1.0)


## A strip segment from edge a0-a1 to edge b0-b1 (a1 and b0 on the same side).
func _quad(st: SurfaceTool, a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3,
		color_a: Color, color_b: Color, sway_a: float, sway_b: float) -> void:
	var normal := (a1 - a0).cross(b1 - a0).normalized()
	if normal.y < 0.0:
		normal = -normal
	for v in [[a0, color_a, sway_a], [a1, color_a, sway_a], [b0, color_b, sway_b],
			[a0, color_a, sway_a], [b0, color_b, sway_b], [b1, color_b, sway_b]]:
		_vertex(st, v[0], normal, v[1], v[2])


func _tri(st: SurfaceTool, points: Array, color: Color, sway: float) -> void:
	var normal: Vector3 = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
	if normal.y < 0.0:
		normal = -normal
	for p in points:
		_vertex(st, p, normal, color, sway)


## A low-poly ellipsoid. `half` keeps only the top half.
## `soft` tilts its normals upward, so leafy clumps aren't dark underneath.
func _sphere(st: SurfaceTool, center: Vector3, radii: Vector3, color: Color, segments: int,
		rings: int, sway: float, half: bool = false, soft: bool = false) -> void:
	var points := []
	for r in rings + 1:
		var lat := PI * 0.5 - (PI * 0.5 if half else PI) * r / rings
		var row := []
		for s in segments:
			var lon := s * TAU / segments
			row.append(Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)))
		points.append(row)
	for r in rings:
		for s in segments:
			var quad := [points[r][s], points[r][(s + 1) % segments], points[r + 1][(s + 1) % segments], points[r + 1][s]]
			for k in [0, 1, 2, 0, 2, 3]:
				var unit: Vector3 = quad[k]
				_vertex(st, center + unit * radii, (unit + Vector3.UP).normalized() if soft else unit, color, sway)
	if half:
		var under: Array = points[rings]
		for s in segments:
			for p in [Vector3.ZERO, under[s], under[(s + 1) % segments]]:
				_vertex(st, center + p * radii, Vector3.DOWN, color, sway)


## A tapered tube from a to b, open at the ends.
func _cylinder(st: SurfaceTool, a: Vector3, b: Vector3, radius_a: float, radius_b: float,
		color: Color, segments: int) -> void:
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3.FORWARD if absf(axis.y) > 0.9 else Vector3.UP).normalized()
	var v := axis.cross(u)
	var sway_a := clampf(a.y / 6.5, 0.0, 1.0)
	var sway_b := clampf(b.y / 6.5, 0.0, 1.0)
	for s in segments:
		var d0 := u * cos(s * TAU / segments) + v * sin(s * TAU / segments)
		var d1 := u * cos((s + 1) * TAU / segments) + v * sin((s + 1) * TAU / segments)
		var quad := [[a + d0 * radius_a, d0, sway_a], [a + d1 * radius_a, d1, sway_a],
			[b + d1 * radius_b, d1, sway_b], [b + d0 * radius_b, d0, sway_b]]
		for k in [0, 1, 2, 0, 2, 3]:
			_vertex(st, quad[k][0], quad[k][1], color, quad[k][2])


func _disk(st: SurfaceTool, center: Vector3, radius: float, color: Color, segments: int) -> void:
	for s in segments:
		var p0 := center + Vector3(cos(s * TAU / segments), 0.0, sin(s * TAU / segments)) * radius
		var p1 := center + Vector3(cos((s + 1) * TAU / segments), 0.0, sin((s + 1) * TAU / segments)) * radius
		for p in [center, p0, p1]:
			_vertex(st, p, Vector3.UP, color, 0.0)


func _vertex(st: SurfaceTool, position: Vector3, normal: Vector3, color: Color, sway: float) -> void:
	st.set_color(color)
	st.set_normal(normal)
	st.set_uv(Vector2(0.0, sway))
	st.add_vertex(position)
