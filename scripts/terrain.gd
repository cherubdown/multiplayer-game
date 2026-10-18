extends Node3D
## The generated island: ground collision on every peer, plus the ground mesh
## colored by biome, the sea and plants (see foliage.gd) on peers that draw
## anything. Trees and rocks are in harvestables.gd.
## build() makes it from a seed string; the same seed gives the same world.

const WorldGen := preload("res://scripts/world_gen.gd")
const Foliage := preload("res://scripts/foliage.gd")

## Meters between terrain vertices. The ground is (SIZE / STEP + 1)^2 points.
const STEP := 4.0

var gen: WorldGen
## Heights on the vertex grid, row by row (z), then column (x).
var _heights := PackedFloat32Array()
## Biome at each vertex, laid out like _heights. Only filled on peers that
## draw the world.
var _biomes := PackedByteArray()
var _cells := 0


## Replaces whatever was built before. `visuals` is false on a dedicated
## server, which only needs something to stand on.
func build(seed_text: String, visuals: bool = true) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	gen = WorldGen.new(seed_text)
	_biomes = PackedByteArray()
	var started := Time.get_ticks_msec()
	_sample_heights()
	_build_collision()
	if visuals:
		_build_ground_mesh()
		_build_sea()
		var foliage := Foliage.new()
		foliage.name = "Foliage"
		add_child(foliage)
		foliage.setup(gen.seed_number, surface_height, biome_near)
	print("Built the world from seed \"%s\" in %d ms" % [seed_text, Time.get_ticks_msec() - started])


## Height of the ground at (x, z), matching the collision shape.
func ground_height(x: float, z: float) -> float:
	return gen.height_at(x, z) if gen else 0.0


## Height of the drawn ground mesh at (x, z), which is flat between its
## vertices. Much cheaper than ground_height(), so it's what plants stand on.
func surface_height(x: float, z: float) -> float:
	var points := _cells + 1
	var gx := clampf((x + WorldGen.SIZE * 0.5) / STEP, 0.0, _cells - 0.001)
	var gz := clampf((z + WorldGen.SIZE * 0.5) / STEP, 0.0, _cells - 0.001)
	var i := int(gx)
	var j := int(gz)
	var fx := gx - i
	var fz := gz - j
	var a := _heights[j * points + i]
	var b := _heights[j * points + i + 1]
	var c := _heights[(j + 1) * points + i]
	var d := _heights[(j + 1) * points + i + 1]
	# Same two triangles per cell as the mesh: a-b-c and b-d-c.
	if fx + fz <= 1.0:
		return a + (b - a) * fx + (c - a) * fz
	return d + (c - d) * (1.0 - fx) + (b - d) * (1.0 - fz)


## Biome of the ground mesh vertex nearest (x, z).
func biome_near(x: float, z: float) -> WorldGen.Biome:
	if _biomes.is_empty():
		return gen.biome_at(x, z)
	var points := _cells + 1
	var i := clampi(roundi((x + WorldGen.SIZE * 0.5) / STEP), 0, _cells)
	var j := clampi(roundi((z + WorldGen.SIZE * 0.5) / STEP), 0, _cells)
	return _biomes[j * points + i] as WorldGen.Biome


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
	_biomes.resize(points * points)
	# Soft patches of lighter and darker ground, so it isn't one flat color.
	var patches := FastNoiseLite.new()
	patches.seed = int(gen.seed_number & 0x7FFFFFFF) ^ 0x6A7
	patches.frequency = 1.0 / 30.0
	patches.fractal_octaves = 2
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
			var biome := gen.biome_for(x, z, h)
			_biomes[k] = biome
			var color: Color = WorldGen.BIOME_COLORS[biome]
			var patch := patches.get_noise_2d(x, z)
			color = color.lerp(color * Color(1.15, 1.12, 0.85) if patch > 0.0 else color * 0.82, absf(patch) * 1.2)
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
