extends MeshInstance3D
## A weapon swing is a wide horizontal slash: it hits every living enemy
## within REACH of the character, anywhere in the half circle in front of
## them (180 degrees, centred on the way they're looking), so a swarm of
## frogs can be cut through several at a time. Tools (axes, pickaxes) still
## hit one tree or rock at a time (see scripts/harvestables.gd).
##
## The server works out who's hit with targets() (see Player.slash()), and
## every peer sees the slash as a pale crescent that sweeps from the
## character's right to their left and fades, made here in code so there's
## nothing to import.

const CharacterModel := preload("res://scripts/character_model.gd")
const Slash := preload("res://scripts/slash.gd")

## How far past an enemy's edge a slash reaches, measured from the middle of
## the character, across the ground.
const REACH := 2.4
## How far behind the line through the character's shoulders an enemy's
## middle can be and still get hit, so one pressed right up against their
## side isn't missed.
const SIDE_GRACE := 0.3
## Seconds between slashes.
const SECONDS_BETWEEN := 0.6
## Seconds after the swing starts that the crescent appears, and seconds it
## takes to sweep across and fade.
const DELAY := 0.1
const SECONDS := 0.3
## Its inner and outer radius, and how high off the ground it is as a
## fraction of the character's height.
const INNER := 0.55
const OUTER := REACH + 0.2
const HEIGHT := 0.55
const SEGMENTS := 24

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// 0 to 1 over the slash: where its leading edge is along the arc.
uniform float progress = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.97, 0.88, 1.0);

void fragment() {
	// UV.x runs from the character's right (0) to their left (1), UV.y from
	// the inner edge (0) to the outer edge (1).
	float lead = progress * 1.4;
	float behind = lead - UV.x;
	float trail = step(0.0, behind) * (1.0 - clamp(behind / 0.55, 0.0, 1.0));
	float edge = pow(UV.y, 1.5) * (1.0 - smoothstep(0.82, 1.0, UV.y));
	float fade = 1.0 - smoothstep(0.7, 1.0, progress);
	ALBEDO = tint.rgb;
	ALPHA = clamp(trail * edge * fade * 1.6, 0.0, 0.9);
}
"""

static var _mesh: ArrayMesh
static var _shader: Shader


## Of `enemies`, the living ones a slash from `origin` towards `yaw` hits:
## within `reach` of their edge, and not behind the character. `yaw` is a
## facing as in Node3D.rotation.y (looking down -Z at 0).
static func targets(enemies: Array, origin: Vector3, yaw: float, reach := REACH) -> Array:
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var hit := []
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		if enemy.gap_to(origin) > reach:
			continue
		var at := Vector2(enemy.global_position.x - origin.x, enemy.global_position.z - origin.z)
		if at.dot(forward) >= -SIDE_GRACE:
			hit.append(enemy)
	return hit


## Shows a slash by `by` towards `yaw`, on a peer that draws anything.
static func play(by: Node3D, yaw: float, height: float) -> void:
	if not CharacterModel.can_show_models() or not by.is_inside_tree():
		return
	var slash: MeshInstance3D = Slash.new()
	slash.top_level = true
	by.add_child(slash)
	slash.global_position = by.global_position + Vector3.UP * height * HEIGHT
	slash.rotation = Vector3(0.0, yaw, 0.0)


func _ready() -> void:
	if _mesh == null:
		_mesh = _build_mesh()
		_shader = Shader.new()
		_shader.code = SHADER
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = _shader
	material_override = material
	var tween := create_tween()
	# Waits for the arm to draw back, so the crescent follows the blade.
	tween.tween_interval(DELAY)
	tween.tween_method(func(t: float) -> void: material.set_shader_parameter("progress", t),
		0.0, 1.0, SECONDS)
	tween.tween_callback(queue_free)


## A flat half ring, lying on the ground, from the right (+X) round the front
## (-Z) to the left (-X).
static func _build_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in SEGMENTS + 1:
		var t := float(i) / SEGMENTS
		var angle := PI * t
		var dir := Vector3(cos(angle), 0.0, -sin(angle))
		verts.append(dir * INNER)
		uvs.append(Vector2(t, 0.0))
		verts.append(dir * OUTER)
		uvs.append(Vector2(t, 1.0))
		if i > 0:
			var a := (i - 1) * 2
			indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return built
