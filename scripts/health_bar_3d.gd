extends MeshInstance3D
## A small health bar that floats in the world and always faces the camera,
## drawn over everything like the nameplates. Shows above enemies (see
## scripts/big_frog.gd) and other players. Set `fraction` (0 to 1) to fill it.

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled;

uniform float fraction = 1.0;
uniform vec4 fill_color : source_color = vec4(0.85, 0.15, 0.12, 1.0);
uniform vec4 empty_color : source_color = vec4(0.1, 0.1, 0.1, 0.75);

void vertex() {
	// Billboard: keep the bar's position and scale, but face the camera.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz),
		MODEL_MATRIX[3]);
}

void fragment() {
	// A thin dark border around the bar.
	vec2 edge = min(UV, 1.0 - UV) * vec2(1.0, 8.0);
	bool border = min(edge.x, edge.y) < 0.02;
	vec4 c = border ? vec4(0.0, 0.0, 0.0, 0.9) : (UV.x <= fraction ? fill_color : empty_color);
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
"""

static var _shader: Shader

## How full the bar is, 0 to 1.
var fraction := 1.0:
	set(value):
		fraction = clampf(value, 0.0, 1.0)
		if _material != null:
			_material.set_shader_parameter("fraction", fraction)

var _material: ShaderMaterial


func _init(width := 0.8, height := 0.1) -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	mesh = quad
	_material = ShaderMaterial.new()
	_material.shader = _shader
	_material.render_priority = 1
	_material.set_shader_parameter("fraction", fraction)
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
