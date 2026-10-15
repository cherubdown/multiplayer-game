// Shared by every foliage mesh (see scripts/foliage.gd), through
// foliage_blades.gdshader (thin, two-sided leaves and blades) and
// foliage_solid.gdshader (closed shapes like bushes and logs).
//   Vertex color: the base color. Its alpha marks the parts that take the
//   instance's tint (INSTANCE_CUSTOM.rgb), like leaves and petals.
//   UV.y: how much a vertex sways in the wind, 0 at the root.

uniform float sway = 0.15;
// Plants shrink into the ground between these distances from the camera, so
// they don't pop in at the edge of where they're drawn. Measured from the
// player's camera even when drawing shadows.
uniform float fade_start = 45.0;
uniform float fade_end = 60.0;
// Lights grass as if it were the ground it grows from, so it doesn't flicker
// as thin blades turn toward and away from the sun.
uniform bool up_normals = false;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	float shrink = 1.0 - smoothstep(fade_start, fade_end, distance(root, MAIN_CAM_INV_VIEW_MATRIX[3].xyz));
	VERTEX *= shrink;
	float weight = UV.y * UV.y * sway;
	vec2 wind = vec2(
		sin(TIME * 1.7 + root.x * 0.35 + root.z * 0.2) + 0.4 * sin(TIME * 4.1 + root.z * 1.3),
		cos(TIME * 1.3 + root.z * 0.3 - root.x * 0.1)) * weight;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(wind.x, 0.0, wind.y);
	if (up_normals) {
		NORMAL = normalize(inverse(mat3(MODEL_MATRIX)) * vec3(0.0, 1.0, 0.0));
	}
	COLOR.rgb *= mix(vec3(1.0), INSTANCE_CUSTOM.rgb, COLOR.a);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
