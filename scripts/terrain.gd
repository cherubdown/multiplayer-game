extends Node3D
## The generated island: ground collision on every peer, plus the ground mesh
## colored by biome, the sea, and trees and rocks on peers that draw anything.
## build() makes it from a seed string; the same seed gives the same world.

const WorldGen := preload("res://scripts/world_gen.gd")

## Meters between terrain vertices. The ground is (SIZE / STEP + 1)^2 points.
const STEP := 4.0

var gen: WorldGen
## Heights on the vertex grid, row by row (z), then column (x).
var _heights := PackedFloat32Array()
var _cells := 0


## Replaces whatever was built before. `visuals` is false on a dedicated
## server, which only needs something to stand on.
func build(seed_text: String, visuals: bool = true) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	gen = WorldGen.new(seed_text)
	var started := Time.get_ticks_msec()
	_sample_heights()
	_build_collision()
	if visuals:
		_build_ground_mesh()
		_build_sea()
		_build_decorations()
	print("Built the world from seed \"%s\" in %d ms" % [seed_text, Time.get_ticks_msec() - started])


## Height of the ground at (x, z), matching the collision shape.
func ground_height(x: float, z: float) -> float:
	return gen.height_at(x, z) if gen else 0.0


func _sample_heights() -> void:
	_cells = int(WorldGen.SIZE / STEP)
	var points := _cells + 1
	_heights.resize(points * points)
	for j in points:
		for i in points:
			_heights[j * points + i] = gen.height_at(_grid_x(i), _grid_x(j))


func _grid_x(i: int) -> float:
	return i * STEP - WorldGen.SIZE * 0.5


func _build_collision() -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = _cells + 1
	shape.map_depth = _cells + 1
	shape.map_data = _heights
	var body := StaticBody3D.new()
	body.name = "Ground"
	var collision := CollisionShape3D.new()
	collision.shape = shape
	# A HeightMapShape3D has one point per meter; stretch it to STEP.
	collision.scale = Vector3(STEP, 1.0, STEP)
	body.add_child(collision)
	add_child(body)


func _build_ground_mesh() -> void:
	var points := _cells + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	vertices.resize(points * points)
	normals.resize(points * points)
	colors.resize(points * points)
	for j in points:
		for i in points:
			var k := j * points + i
			var x := _grid_x(i)
			var z := _grid_x(j)
			var h := _heights[k]
			vertices[k] = Vector3(x, h, z)
			var left := _heights[k - 1] if i > 0 else h
			var right := _heights[k + 1] if i < _cells else h
			var up := _heights[k - points] if j > 0 else h
			var down := _heights[k + points] if j < _cells else h
			normals[k] = Vector3(left - right, 2.0 * STEP, up - down).normalized()
			var color: Color = WorldGen.BIOME_COLORS[gen.biome_for(x, z, h)]
			# Steep slopes show bare rock.
			color = color.lerp(Color(0.3, 0.28, 0.26), smoothstep(0.75, 0.55, normals[k].y))
			# Snow on the peaks.
			colors[k] = color.lerp(Color(0.92, 0.94, 0.97), smoothstep(68.0, 76.0, h) * smoothstep(0.5, 0.7, normals[k].y))
	var indices := PackedInt32Array()
	indices.resize(_cells * _cells * 6)
	var n := 0
	for j in _cells:
		for i in _cells:
			var a := j * points + i
			var b := a + 1
			var c := a + points
			var d := c + 1
			for index in [a, b, c, b, d, c]:
				indices[n] = index
				n += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = "GroundMesh"
	instance.mesh = mesh
	add_child(instance)


func _build_sea() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * WorldGen.SIZE * 4.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.3, 0.5, 0.75)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.1
	material.metallic = 0.3
	plane.material = material
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	sea.mesh = plane
	sea.position.y = WorldGen.SEA_LEVEL
	add_child(sea)


# --- Trees and rocks --------------------------------------------------------
# Scattered from the seed so every player sees them in the same places. They
# are only scenery for now: nothing collides with them.

## Chance per 8 m cell of each kind of decoration, by biome.
const DECOR_DENSITY := {
	WorldGen.Biome.MEADOWS: { "leafy": 0.12, "pine": 0.03, "rock": 0.02 },
	WorldGen.Biome.BLACK_FOREST: { "pine": 0.6, "rock": 0.05 },
	WorldGen.Biome.SWAMP: { "dead": 0.25 },
	WorldGen.Biome.PLAINS: { "leafy": 0.02, "rock": 0.04 },
	WorldGen.Biome.MOUNTAINS: { "pine": 0.05, "rock": 0.15 },
}
const DECOR_CELL := 8.0


func _build_decorations() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = gen.seed_number
	var placed := {}  # kind -> Array[Transform3D]
	var cells := int(WorldGen.SIZE / DECOR_CELL)
	for j in cells:
		for i in cells:
			# Draw the same random numbers for every cell so one cell's
			# biome doesn't shift what every later cell gets.
			var jitter := Vector2(rng.randf(), rng.randf())
			var roll := rng.randf()
			var size := rng.randf_range(0.7, 1.4)
			var turn := rng.randf() * TAU
			var x := (i + jitter.x) * DECOR_CELL - WorldGen.SIZE * 0.5
			var z := (j + jitter.y) * DECOR_CELL - WorldGen.SIZE * 0.5
			var h := gen.height_at(x, z)
			var odds: Dictionary = DECOR_DENSITY.get(gen.biome_for(x, z, h), {})
			for kind in odds:
				if roll < odds[kind]:
					var basis := Basis(Vector3.UP, turn).scaled(Vector3.ONE * size)
					if not placed.has(kind):
						placed[kind] = []
					placed[kind].append(Transform3D(basis, Vector3(x, h, z)))
					break
				roll -= odds[kind]
	for kind in placed:
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _decor_mesh(kind)
		multimesh.instance_count = placed[kind].size()
		for n in placed[kind].size():
			multimesh.set_instance_transform(n, placed[kind][n])
		var instance := MultiMeshInstance3D.new()
		instance.name = kind.capitalize() + "s"
		instance.multimesh = multimesh
		add_child(instance)


## A simple low-poly stand-in for each kind of decoration, standing on y = 0.
func _decor_mesh(kind: String) -> Mesh:
	match kind:
		"pine":
			return _tree_mesh(_cone(2.2, 7.0), Color(0.12, 0.28, 0.14), 4.5)
		"leafy":
			var crown := SphereMesh.new()
			crown.radius = 2.4
			crown.height = 4.0
			crown.radial_segments = 8
			crown.rings = 4
			return _tree_mesh(crown, Color(0.3, 0.5, 0.18), 4.5)
		"dead":
			return _tree_mesh(null, Color.BLACK, 5.0)
		_:
			var rock := SphereMesh.new()
			rock.radius = 1.3
			rock.height = 1.6
			rock.radial_segments = 6
			rock.rings = 3
			rock.material = _material(Color(0.5, 0.5, 0.52))
			return rock


## Joins a trunk with an optional crown centered crown_y above the ground.
func _tree_mesh(crown: PrimitiveMesh, crown_color: Color, crown_y: float) -> Mesh:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.2
	trunk.bottom_radius = 0.35
	trunk.height = crown_y if crown else 5.0
	trunk.radial_segments = 6
	var tool := SurfaceTool.new()
	var mesh := ArrayMesh.new()
	tool.append_from(trunk, 0, Transform3D(Basis(), Vector3.UP * trunk.height * 0.5))
	tool.commit(mesh)
	mesh.surface_set_material(0, _material(Color(0.3, 0.2, 0.12) if crown else Color(0.25, 0.22, 0.18)))
	if crown:
		tool = SurfaceTool.new()
		tool.append_from(crown, 0, Transform3D(Basis(), Vector3.UP * crown_y))
		tool.commit(mesh)
		mesh.surface_set_material(1, _material(crown_color))
	return mesh


func _cone(radius: float, height: float) -> CylinderMesh:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = radius
	cone.height = height
	cone.radial_segments = 7
	return cone


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material
