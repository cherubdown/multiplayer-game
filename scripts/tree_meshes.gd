extends RefCounted
## The trees: pines, leafy trees and dead trees (scripts/harvestables.gd),
## birches (scripts/foliage.gd) and apple trees (scripts/forage.gd).
##
## Made in the same old-school style as the characters
## (scripts/character_model.gd): chunky low-poly shapes with exaggerated
## silhouettes (flared roots, crooked trunks, big lumpy crowns and stacked,
## drooping tiers of pine boughs) so they read from far off, with the bark,
## leaves and needles painted on by shaders/painted_tree.gdshader.
##
## Each mesh stands on y = 0 and is drawn through MultiMeshes. It has a bark
## surface and, except for dead trees, a crown surface. UV.x is how open to the
## sky a vertex is (0 deep inside a crown) and UV.y how much it sways.

const SHADER := preload("res://shaders/painted_tree.gdshader")
## The patterns the shader paints (see shaders/painted_tree.gdshader).
enum { BARK, BIRCH_BARK, LEAVES, NEEDLES }

## Kind -> [height its sway is measured up to, sway at that height].
const SWAY := {
	"pine": [8.6, 0.04], "leafy": [7.0, 0.06], "dead": [5.5, 0.0], "birch": [7.6, 0.12], "apple": [4.6, 0.05],
}
## Kind -> [bark pattern, bark color, moss, crown pattern, crown color].
const PAINT := {
	"pine": [BARK, Color(0.36, 0.24, 0.16), 0.4, NEEDLES, Color(0.19, 0.36, 0.22)],
	"leafy": [BARK, Color(0.4, 0.29, 0.19), 0.5, LEAVES, Color(0.29, 0.44, 0.17)],
	"dead": [BARK, Color(0.42, 0.38, 0.33), 0.2, LEAVES, Color.BLACK],
	"birch": [BIRCH_BARK, Color(0.9, 0.88, 0.82), 0.0, LEAVES, Color(0.46, 0.6, 0.24)],
	"apple": [BARK, Color(0.36, 0.25, 0.16), 0.3, LEAVES, Color(0.27, 0.46, 0.18)],
}
const MOSS_COLOR := Color(0.32, 0.44, 0.16)
## Shadows are painted cooler, and lights warmer, than the color itself.
const SHADOW_HUE := Color(0.1, 0.12, 0.26)
const LIGHT_HUE := Color(1.0, 0.94, 0.7)

static var _meshes := {}


## A vertex sink for one surface of a tree that knows how tall the tree is,
## for its sway.
class Surface:
	var st := SurfaceTool.new()
	var top := 1.0

	func _init(p_top: float) -> void:
		top = p_top
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func vertex(position: Vector3, normal: Vector3, sky: float) -> void:
		st.set_normal(normal)
		st.set_uv(Vector2(sky, clampf(position.y / top, 0.0, 1.0)))
		st.add_vertex(position)


## The mesh for a kind of tree ("pine", "leafy", "dead", "birch" or "apple").
## It shrinks away between `fade_start` and `fade_end` meters from the camera,
## or never when `fade_end` is 0.
static func mesh(kind: String, fade_start := 0.0, fade_end := 0.0) -> ArrayMesh:
	var key := "%s@%d-%d" % [kind, fade_start, fade_end]
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var top: float = SWAY[kind][0]
	var bark := Surface.new(top)
	var crown := Surface.new(top)
	match kind:
		"pine":
			_pine(bark, crown, rng)
		"leafy":
			_leafy(bark, crown, rng)
		"dead":
			_dead(bark, rng)
		"birch":
			_birch(bark, crown, rng)
		"apple":
			_apple(bark, crown, rng)
	var paint: Array = PAINT[kind]
	var result := ArrayMesh.new()
	bark.st.commit(result)
	result.surface_set_material(0, _material(kind, paint[0], paint[1], paint[2], fade_start, fade_end))
	if kind != "dead":
		crown.st.commit(result)
		result.surface_set_material(1, _material(kind, paint[3], paint[4], 0.0, fade_start, fade_end))
	_meshes[key] = result
	return result


static func _material(kind: String, pattern: int, color: Color, moss: float,
		fade_start: float, fade_end: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("pattern", pattern)
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("shade_color", color.darkened(0.6).lerp(SHADOW_HUE, 0.3))
	material.set_shader_parameter("light_color", color.lightened(0.4).lerp(LIGHT_HUE, 0.3))
	material.set_shader_parameter("moss", moss)
	material.set_shader_parameter("moss_color", MOSS_COLOR)
	material.set_shader_parameter("sway", SWAY[kind][1])
	material.set_shader_parameter("fade_start", fade_start)
	material.set_shader_parameter("fade_end", fade_end)
	return material


# --- Trees ------------------------------------------------------------------

## A tall, straight trunk in four tiers of drooping, star-shaped boughs.
static func _pine(bark: Surface, crown: Surface, rng: RandomNumberGenerator) -> void:
	_tube(bark, [Vector3.ZERO, Vector3(0.0, 1.2, 0.0), Vector3(0.04, 3.0, 0.0), Vector3(0.0, 5.5, 0.03),
		Vector3(0.0, 8.0, 0.0)], [0.46, 0.31, 0.26, 0.16, 0.0], 6, rng, 0.6, 5, Vector2(1.0, 0.3))
	var turn := rng.randf() * TAU
	for tier in [[1.4, 4.6, 2.7, 7], [2.7, 6.0, 2.2, 7], [4.0, 7.3, 1.7, 6], [5.3, 8.7, 1.15, 5]]:
		turn += rng.randf_range(0.6, 1.4)
		_tier(crown, tier[0], tier[1], tier[2], tier[3], turn, rng)


## A stout, crooked trunk forking into three boughs under a big crown of
## leafy clumps.
static func _leafy(bark: Surface, crown: Surface, rng: RandomNumberGenerator) -> void:
	var trunk := [Vector3.ZERO, Vector3(0.06, 0.8, 0.0), Vector3(-0.12, 1.8, 0.08), Vector3(0.06, 2.8, -0.05),
		Vector3(0.0, 3.7, 0.0), Vector3(0.0, 4.6, 0.0)]
	_tube(bark, trunk, [0.52, 0.37, 0.31, 0.28, 0.2, 0.0], 7, rng, 0.55, 4, Vector2(1.0, 0.3))
	var middle := Vector3(0.0, 5.0, 0.0)
	var size := Vector3(2.9, 2.1, 2.9)
	var start := rng.randf() * TAU
	for n in 3:
		var a := start + n * TAU / 3.0 + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0.0, sin(a))
		var from := _along(trunk, rng.randf_range(0.5, 0.6))
		_tube(bark, [from, from + out * 0.9 + Vector3.UP * 0.9, from + out * 1.7 + Vector3.UP * 1.7],
			[0.17, 0.1, 0.0], 5, rng, 0.0, 0, Vector2(0.7, 0.3))
	_clump(crown, middle + Vector3.UP * 0.4, Vector3(2.0, 1.55, 2.0), 8, 5, rng, middle, size)
	for n in 5:
		var a := start + 0.5 + n * TAU / 5.0 + rng.randf_range(-0.2, 0.2)
		var at := Vector3(cos(a) * 1.65, rng.randf_range(4.3, 4.9), sin(a) * 1.65)
		var r := rng.randf_range(1.25, 1.45)
		_clump(crown, at, Vector3(r, r * 0.82, r), 7, 4, rng, middle, size)
	_clump(crown, Vector3(0.3, 6.4, -0.2), Vector3(1.25, 1.0, 1.25), 7, 4, rng, middle, size)


## A bare, twisted trunk with a broken top and crooked, forking branches.
static func _dead(bark: Surface, rng: RandomNumberGenerator) -> void:
	var trunk := [Vector3.ZERO, Vector3(0.1, 1.0, 0.05), Vector3(-0.16, 2.2, 0.2), Vector3(0.1, 3.3, 0.1),
		Vector3(0.36, 4.3, -0.1), Vector3(0.3, 5.1, -0.16)]
	_tube(bark, trunk, [0.52, 0.4, 0.33, 0.27, 0.21, 0.16], 6, rng, 0.7, 4, Vector2.ONE, true)
	var start := rng.randf() * TAU
	for n in 5:
		var a := start + n * TAU / 5.0 * 1.3 + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-out.z, 0.0, out.x)
		var from := _along(trunk, 0.4 + n * 0.11)
		var reach := rng.randf_range(1.5, 2.2) * (1.0 - n * 0.1)
		var kink := from + out * reach * 0.5 + Vector3.UP * reach * 0.2 + side * rng.randf_range(-0.25, 0.25)
		var tip := from + out * reach + Vector3.UP * rng.randf_range(0.5, 1.0) * reach
		_tube(bark, [from, kink, tip], [0.18 * (1.0 - n * 0.1), 0.1, 0.0], 5, rng)
		if n % 2 == 0:
			# A twig forking off the kink.
			_tube(bark, [kink, kink + side * 0.5 + Vector3.UP * 0.55], [0.07, 0.0], 4, rng)


## A slim, white trunk under tall, narrow clumps of pale leaves.
static func _birch(bark: Surface, crown: Surface, rng: RandomNumberGenerator) -> void:
	var trunk := [Vector3.ZERO, Vector3(0.05, 1.5, 0.0), Vector3(0.12, 3.5, 0.05), Vector3(0.1, 5.5, 0.0),
		Vector3(0.05, 7.1, 0.0)]
	_tube(bark, trunk, [0.27, 0.2, 0.17, 0.12, 0.0], 6, rng, 0.35, 3, Vector2(1.0, 0.4))
	var middle := Vector3(0.1, 5.6, 0.0)
	var size := Vector3(1.7, 2.3, 1.7)
	for n in 2:
		var a := n * PI + rng.randf()
		var from := _along(trunk, 0.55 + n * 0.1)
		_tube(bark, [from, from + Vector3(cos(a) * 0.7, 0.9, sin(a) * 0.7)], [0.07, 0.0], 4, rng)
	var start := rng.randf() * TAU
	for n in 4:
		var a := start + n * TAU / 4.0 + rng.randf_range(-0.3, 0.3)
		var at := Vector3(cos(a) * 0.7, rng.randf_range(4.6, 6.1), sin(a) * 0.7)
		_clump(crown, at, Vector3(1.05, 1.45, 1.05), 7, 4, rng, middle, size)
	_clump(crown, Vector3(0.1, 6.9, 0.0), Vector3(0.85, 1.2, 0.85), 7, 4, rng, middle, size)


## A short, gnarled trunk under a wide, round crown. Its apples hang at the
## edge of the crown (see scripts/forage.gd).
static func _apple(bark: Surface, crown: Surface, rng: RandomNumberGenerator) -> void:
	var trunk := [Vector3.ZERO, Vector3(0.08, 0.9, 0.0), Vector3(-0.06, 1.8, 0.05), Vector3(0.05, 2.5, 0.0),
		Vector3(0.0, 3.2, 0.0)]
	_tube(bark, trunk, [0.38, 0.27, 0.23, 0.2, 0.0], 6, rng, 0.5, 4, Vector2(1.0, 0.4))
	for a in [0.4, 2.5, 4.4]:
		var from := _along(trunk, 0.55)
		var out := Vector3(cos(a), 0.0, sin(a))
		_tube(bark, [from, from + out * 0.6 + Vector3.UP * 0.5, from + out * 1.1 + Vector3.UP * 0.8],
			[0.11, 0.07, 0.0], 5, rng, 0.0, 0, Vector2(0.7, 0.3))
	var middle := Vector3(0.0, 3.1, 0.0)
	var size := Vector3(2.0, 1.4, 2.0)
	for c in [[Vector3(0.0, 3.4, 0.0), 1.5], [Vector3(0.8, 3.0, 0.3), 1.0], [Vector3(-0.7, 3.1, -0.4), 1.0],
			[Vector3(0.1, 2.9, -0.9), 0.95], [Vector3(-0.2, 3.0, 0.9), 0.95]]:
		var r: float = c[1]
		_clump(crown, c[0], Vector3(r, r * 0.8, r), 7, 4, rng, middle, size, 0.08)


# --- Shapes -----------------------------------------------------------------

## A tube along `path` (bottom first) with a radius per point, open at the
## bottom. A last radius of 0 ends it in a point; `capped` closes a blunt end.
## `flare` swells the bottom into `lobes` roots. `sky` is how open to the sky
## it is at the bottom and the top.
static func _tube(s: Surface, path: Array, radii: Array, sides: int, rng: RandomNumberGenerator,
		flare := 0.0, lobes := 0, sky := Vector2.ONE, capped := false) -> void:
	var rows := []
	var normals := []
	var skies := []
	var along: Vector3 = (path[1] - path[0]).normalized()
	var u := along.cross(Vector3.FORWARD if absf(along.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var root_turn := rng.randf() * TAU
	for i in path.size():
		var a: Vector3 = path[maxi(i - 1, 0)]
		var b: Vector3 = path[mini(i + 1, path.size() - 1)]
		along = (b - a).normalized()
		# Carry the ring's frame along the bend so the tube doesn't twist.
		u = (u - along * u.dot(along)).normalized()
		var v := along.cross(u)
		var row := []
		var row_normals := []
		for k in sides:
			var angle := k * TAU / sides
			var d := u * cos(angle) + v * sin(angle)
			var r: float = radii[i] * rng.randf_range(0.9, 1.1)
			if i < 2 and flare > 0.0:
				r *= 1.0 + pow(maxf(cos(angle * lobes + root_turn), 0.0), 2.0) * flare * (1.0 if i == 0 else 0.3)
			row.append(path[i] + d * r)
			row_normals.append(d)
		rows.append(row)
		normals.append(row_normals)
		skies.append(lerpf(sky.x, sky.y, float(i) / (path.size() - 1)))
	if capped:
		var end: Vector3 = path[-1]
		rows.append(_repeat(end, sides))
		normals.append(_repeat(along, sides))
		skies.append(sky.y)
	_rows(s, rows, normals, skies)


## One tier of pine boughs: a low cone whose rim droops into `lobes` points,
## thick at the trunk and thin at the rim, like a heavy bough of needles.
static func _tier(s: Surface, y0: float, y1: float, radius: float, lobes: int, turn: float,
		rng: RandomNumberGenerator) -> void:
	var mid := []
	var rim := []
	var under := []
	var mid_normals := []
	var rim_normals := []
	var under_normals := []
	var rim_sky := []
	for k in lobes * 2:
		var angle := turn + k * PI / lobes
		var point := k % 2 == 0
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var r := radius * (1.0 if point else 0.68) * rng.randf_range(0.9, 1.1)
		mid.append(out * r * 0.58 + Vector3.UP * lerpf(y0, y1, 0.45))
		rim.append(out * r + Vector3.UP * (y0 + (-0.25 if point else 0.3)))
		mid_normals.append((out * 0.7 + Vector3.UP).normalized())
		rim_normals.append((out + Vector3.UP * 0.25).normalized())
		under.append(out * r * 0.5 + Vector3.UP * (y0 + (0.1 if point else 0.4)))
		under_normals.append((out + Vector3.DOWN * 0.6).normalized())
		rim_sky.append(0.9 if point else 0.6)
	var n := lobes * 2
	# Rows from the tip down: tip, halfway, rim, then the underside back in
	# to the trunk, which is painted dark.
	var rows := [_repeat(Vector3.UP * y1, n), mid, rim, under, _repeat(Vector3.UP * (y0 + 0.9), n)]
	var normals := [_repeat(Vector3.UP, n), mid_normals, rim_normals, under_normals, _repeat(Vector3.DOWN, n)]
	var skies := [1.0, 0.95, rim_sky, 0.45, 0.3]
	_rows(s, rows, normals, skies)


## A lumpy, low-poly ellipsoid of leaves. Its vertices are darker the deeper
## they are in a crown around `middle`, `size` across.
static func _clump(s: Surface, center: Vector3, radii: Vector3, segments: int, rings: int,
		rng: RandomNumberGenerator, middle: Vector3, size: Vector3, lump := 0.1) -> void:
	var rows := []
	var normals := []
	var skies := []
	for r in rings + 1:
		var lat := PI * 0.5 - PI * r / rings
		# Every other ring is turned half a step, for a faceted, gem-cut look.
		var offset := (r % 2) * PI / segments
		var row := []
		var row_normals := []
		var row_sky := []
		for k in segments:
			var lon := k * TAU / segments + offset
			var unit := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			var bump := 1.0 if r == 0 or r == rings else 1.0 + rng.randf_range(-lump, lump)
			var point := center + unit * radii * bump
			row.append(point)
			# Tilted up, so leafy clumps aren't dark underneath.
			row_normals.append((unit + Vector3.UP * 0.5).normalized())
			var depth := ((point - middle) / (size * 0.5)).length()
			row_sky.append(clampf(inverse_lerp(0.35, 1.0, depth), 0.0, 1.0))
		rows.append(row)
		normals.append(row_normals)
		skies.append(row_sky)
	_rows(s, rows, normals, skies)


## Joins each row of points to the next with a strip of triangles. Rows wrap
## around and run from the top down (or, for tubes, along the tube). Normals
## and skies are given per row, as one value or one per point.
static func _rows(s: Surface, rows: Array, normals: Array, skies: Array) -> void:
	for r in rows.size() - 1:
		var count: int = rows[r].size()
		for k in count:
			var k1 := (k + 1) % count
			for q in [[r, k], [r, k1], [r + 1, k1], [r, k], [r + 1, k1], [r + 1, k]]:
				var normal: Vector3 = normals[q[0]][q[1]] if normals[q[0]] is Array else normals[q[0]]
				var sky: float = skies[q[0]][q[1]] if skies[q[0]] is Array else skies[q[0]]
				s.vertex(rows[q[0]][q[1]], normal, sky)


## The point `t` of the way along `path`, by its points.
static func _along(path: Array, t: float) -> Vector3:
	var f := t * (path.size() - 1)
	var i := mini(int(f), path.size() - 2)
	return path[i].lerp(path[i + 1], f - i)


static func _repeat(value: Variant, count: int) -> Array:
	var result := []
	result.resize(count)
	result.fill(value)
	return result
