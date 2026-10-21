shader_type spatial;

#include "res://shaders/painted.gdshaderinc"
// The trees (see scripts/tree_meshes.gd), painted to match the characters
// (shaders/hand_painted.gdshader): chunky low-poly shapes with bark fissures,
// leaf dabs and needles painted on from the mesh's own coordinates, in meters.
// There are no texture files.
//
// Drawn through MultiMeshes, so the paint is shifted a little for every tree,
// by where it stands, so no two trees in a forest look stamped out.
//   UV.x: how open to the sky a vertex is, 0 deep inside a crown, painted dark.
//   UV.y: how much a vertex sways in the wind, 0 at the root.

const int BARK = 0;
const int BIRCH_BARK = 1;
const int LEAVES = 2;
const int NEEDLES = 3;

uniform int pattern = 0;
uniform vec3 base_color : source_color = vec3(0.4, 0.28, 0.18);
// Painted on the undersides and in the dark strokes, and on the tops and the
// light strokes. Shadows lean cool, lights warm, as in a painting.
uniform vec3 shade_color : source_color = vec3(0.15, 0.1, 0.1);
uniform vec3 light_color : source_color = vec3(0.7, 0.6, 0.4);
// Moss creeping up from the roots of bark, 0 for none.
uniform float moss = 0.0;
uniform vec3 moss_color : source_color = vec3(0.3, 0.42, 0.15);
uniform float sway = 0.0;
// Trees shrink into the ground between these distances from the camera, so
// they don't pop out of sight. Measured from the player's camera even when
// drawing shadows. fade_end 0 draws them at any distance.
uniform float fade_start = 0.0;
uniform float fade_end = 0.0;

varying vec3 local_pos;
varying vec3 local_normal;
varying float open_sky;
varying float tree_seed;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	open_sky = UV.x;
	vec3 root = MODEL_MATRIX[3].xyz;
	tree_seed = hash(floor(root * 2.0) + 0.5);
	if (fade_end > 0.0) {
		VERTEX *= 1.0 - smoothstep(fade_start, fade_end, distance(root, MAIN_CAM_INV_VIEW_MATRIX[3].xyz));
	}
	float weight = UV.y * UV.y * sway;
	vec2 wind = vec2(
		sin(TIME * 0.9 + root.x * 0.15 + root.z * 0.1) + 0.3 * sin(TIME * 2.3 + root.z * 0.7),
		cos(TIME * 0.7 + root.z * 0.12 - root.x * 0.05)) * weight;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(wind.x, 0.0, wind.y);
}

void fragment() {
	vec3 p = local_pos + vec3(tree_seed * 31.0, 0.0, tree_seed * 17.0);
	vec3 n = normalize(local_normal);

	// Painted light: lit from above, darker deep inside the crown.
	float lit = clamp(dot(n, normalize(vec3(0.2, 1.0, -0.3))) * 0.5 + 0.5, 0.0, 1.0);
	lit *= mix(0.35, 1.0, open_sky);
	vec3 base = base_color;
	vec3 shade = shade_color;
	vec3 light_c = light_color;
	if (pattern >= LEAVES) {
		// Every tree leans a little greener, bluer or more golden.
		vec3 tint = mix(vec3(0.9, 1.02, 1.0), vec3(1.1, 1.0, 0.82), tree_seed);
		base *= tint;
		light_c *= tint;
	}
	vec3 color = mix(shade, base, smoothstep(0.0, 0.55, lit));
	color = mix(color, light_c, smoothstep(0.65, 1.0, lit) * 0.55);
	float wash = fbm(p * 1.3);

	if (pattern == BARK) {
		// Long vertical fissures between lighter plates of bark.
		float grain = fbm(vec3(p.x * 7.0, p.y * 0.9, p.z * 7.0));
		float fissure = 1.0 - smoothstep(0.0, 0.07, abs(grain - 0.5));
		color = mix(color, light_c, smoothstep(0.62, 0.8, grain) * smoothstep(0.3, 0.8, lit) * 0.45);
		color = mix(color, shade * 0.55, fissure * 0.65);
		color = mix(color, shade, smoothstep(0.55, 0.8, wash) * 0.25);
		if (moss > 0.0) {
			float creep = smoothstep(1.2, 0.1, local_pos.y) + smoothstep(0.6, 0.95, n.y) * 0.6;
			float patch = smoothstep(0.45, 0.6, fbm(p * 3.0 + 4.0));
			vec3 green = mix(moss_color * 0.6, moss_color * 1.2, lit);
			color = mix(color, green, clamp(creep * patch, 0.0, 1.0) * moss);
		}
	} else if (pattern == BIRCH_BARK) {
		// Chalky white with black dashes running around the trunk, and dark
		// rough patches near the roots.
		float dashes = noise(vec3(p.x * 4.0, p.y * 18.0, p.z * 4.0));
		float marks = smoothstep(0.7, 0.76, dashes) * smoothstep(0.35, 0.55, noise(p * 6.0));
		float rough = smoothstep(1.4, 0.2, local_pos.y) * smoothstep(0.45, 0.6, fbm(p * 4.0));
		color = mix(color, shade, smoothstep(0.5, 0.75, wash) * 0.2);
		color = mix(color, vec3(0.08, 0.07, 0.07), max(marks, rough * 0.85));
	} else if (pattern == LEAVES) {
		// Big masses of foliage, dabbed over with light leaves where the sun
		// catches them and dark gaps where it doesn't.
		float dabs = fbm(p * 4.5 + 2.0);
		float gaps = fbm(p * 3.4 + 9.0);
		color = mix(color, shade, smoothstep(0.5, 0.75, wash) * 0.3);
		color = mix(color, light_c, smoothstep(0.58, 0.66, dabs) * smoothstep(0.35, 0.8, lit) * 0.45);
		color = mix(color, shade * 0.6, smoothstep(0.6, 0.68, gaps) * smoothstep(0.85, 0.3, lit) * 0.7);
		color = mix(color, light_c * vec3(1.1, 1.0, 0.6), smoothstep(0.74, 0.8, noise(p * 9.0)) * lit * 0.35);
	} else if (pattern == NEEDLES) {
		// Boughs of needles in streaks that run out and down from the trunk.
		float around = atan(local_pos.z, local_pos.x);
		vec3 s = vec3(around * 3.0, local_pos.y * 2.0 + length(local_pos.xz) * 1.5, 0.0);
		float streaks = fbm(s * vec3(4.0, 1.5, 1.0) + tree_seed * 9.0);
		color = mix(color, shade, smoothstep(0.5, 0.75, wash) * 0.3);
		color = mix(color, light_c, smoothstep(0.6, 0.72, streaks) * smoothstep(0.4, 0.85, lit) * 0.5);
		color = mix(color, shade * 0.55, smoothstep(0.4, 0.28, streaks) * 0.5);
	}

	// A dark painted edge where the surface turns away, like an inked line.
	float edge = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	color = mix(color, shade * 0.55, smoothstep(0.55, 0.95, edge) * 0.3);

	ALBEDO = color;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
