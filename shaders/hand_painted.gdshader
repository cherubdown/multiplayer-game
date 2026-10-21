shader_type spatial;
// The "hand painted" look of the character models (see
// scripts/character_model.gd): low-poly shapes whose detail is painted on,
// like the textures of old-school MMOs. There are no texture files. Every
// pattern is painted here from the mesh's own coordinates, in meters, so it
// stays the same size on every race.
//
// Light and shade are painted in too: the tops of shapes get the light color
// and the undersides the shade color, the way an illustrator would, with
// hue-shifted brush strokes over them. The real lights are softened into a
// couple of broad bands so they don't fight the paint.
//
// A head (face = true) also has its eyes, brows, mouth and cheeks painted on.

const int SKIN = 0;
const int LINEN = 1;
const int WOOL = 2;
const int LEATHER = 3;
const int HAIR = 4;
const int METAL = 5;
const int ROPE = 6;

uniform int pattern = 0;
uniform vec3 base_color : source_color = vec3(0.8);
// Painted on the undersides and in the dark strokes, and on the tops and the
// light strokes. Shadows lean cool and red, lights warm, as in a painting.
uniform vec3 shade_color : source_color = vec3(0.4);
uniform vec3 light_color : source_color = vec3(1.0);
// Which way strands, folds and grain run, in the mesh's coordinates.
uniform vec3 grain = vec3(0.0, 1.0, 0.0);

// Faces, in units of the head's half width (see CharacterModel._build_head).
uniform bool face = false;
uniform float head_r = 0.14;
uniform float jaw = 1.0;
uniform float eye_size = 1.0;
uniform float brow_tilt = 0.0;
uniform float lid = 0.0;
// Above 0 the corners of the mouth turn up, below 0 down.
uniform float smile = 0.3;
uniform float stubble = 0.0;
uniform vec3 hair_color : source_color = vec3(0.3, 0.2, 0.1);
uniform vec3 iris_color : source_color = vec3(0.25, 0.4, 0.55);
uniform vec3 lip_color : source_color = vec3(0.6, 0.3, 0.28);

varying vec3 local_pos;
varying vec3 local_normal;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

float fbm(vec3 p) {
	return noise(p) * 0.55 + noise(p * 2.03 + 7.1) * 0.28 + noise(p * 4.1 + 3.3) * 0.17;
}

// Noise stretched along the grain: long strokes, strands or folds.
float strokes(vec3 p, float along, float across) {
	vec3 g = normalize(grain);
	float a = dot(p, g);
	vec3 rest = p - g * a;
	return fbm(rest * across + g * a * along);
}

// 1 inside an ellipse centered on c with half sizes r, softly edged.
float blob(vec2 p, vec2 c, vec2 r, float soft) {
	vec2 d = (p - c) / r;
	return 1.0 - smoothstep(1.0 - soft, 1.0 + soft, length(d));
}

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void paint_face(vec3 q, inout vec3 color) {
	// q is in head half widths, y up from the chin, -z the front.
	float front = smoothstep(-0.25, -0.6, q.z);
	if (front <= 0.0) {
		return;
	}
	vec2 p = q.xy;
	vec2 m = vec2(abs(p.x), p.y);
	vec3 shade = shade_color;

	// Painted planes of the face: shadowed sockets and under the brow, a
	// shadow under the nose and the lip, a lit forehead and cheekbones.
	color = mix(color, mix(color, shade, 0.55), blob(m, vec2(0.36, 1.1), vec2(0.27, 0.2), 0.6) * front);
	color = mix(color, mix(color, shade, 0.6), blob(p, vec2(0.0, 0.66), vec2(0.17, 0.07), 0.7) * front);
	color = mix(color, mix(color, shade, 0.45), blob(p, vec2(0.0, 0.37), vec2(0.2 * jaw, 0.05), 0.8) * front);
	color = mix(color, mix(color, light_color, 0.45), blob(p, vec2(0.0, 1.55), vec2(0.6, 0.25), 0.8) * front);
	color = mix(color, mix(color, light_color, 0.35), blob(m, vec2(0.45, 0.82), vec2(0.18, 0.1), 0.8) * front);
	// Ruddy cheeks and nose.
	vec3 blush = mix(color, vec3(0.78, 0.33, 0.3), 0.32);
	color = mix(color, blush, blob(m, vec2(0.52, 0.72), vec2(0.2, 0.14), 0.9) * front);
	color = mix(color, blush, blob(p, vec2(0.0, 0.8), vec2(0.1, 0.12), 0.9) * front * 0.6);

	if (stubble > 0.0) {
		// A shadow of beard on the jaw and upper lip.
		float jawline = smoothstep(0.82, 0.55, p.y) * (1.0 - blob(m, vec2(0.0, 0.75), vec2(0.16, 0.12), 0.5));
		float grains = noise(q * 60.0);
		vec3 shadow = mix(color, mix(hair_color, shade, 0.4), 0.45);
		color = mix(color, shadow, jawline * stubble * (0.7 + 0.3 * grains) * front);
	}

	// Eyes: an almond of white, a colored iris, a dark pupil with a glint,
	// and a heavy upper lid line. `lid` closes the eye from the top.
	vec2 eye_c = vec2(0.36, 1.05);
	vec2 e = (m - eye_c) / eye_size;
	float almond = blob(e, vec2(0.0), vec2(0.17, 0.085 - 0.025 * e.x / 0.17), 0.18);
	float top = 0.085 * (1.0 - 1.7 * lid);
	float open = almond * smoothstep(top + 0.01, top - 0.01, e.y);
	vec3 eye = vec3(0.92, 0.89, 0.82);
	eye = mix(eye, iris_color, blob(e, vec2(-0.015, 0.0), vec2(0.075), 0.2));
	eye = mix(eye, iris_color * 0.5, blob(e, vec2(-0.015, 0.03), vec2(0.075, 0.04), 0.4) * 0.6);
	eye = mix(eye, vec3(0.04), blob(e, vec2(-0.015, 0.0), vec2(0.035), 0.25));
	eye = mix(eye, vec3(1.0), blob(e, vec2(-0.04, 0.025), vec2(0.016), 0.3));
	color = mix(color, mix(color, shade, 0.3), almond * (1.0 - open) * front);
	color = mix(color, eye, open * front);
	float line = blob(e, vec2(0.0, 0.01), vec2(0.2, 0.105), 0.15) * (1.0 - open);
	line *= smoothstep(-0.03, 0.0, e.y) * smoothstep(top + 0.04, top + 0.02, e.y);
	color = mix(color, shade * 0.35, line * 0.9 * front);

	// Brows: thick, tapering, painted strokes in the hair color.
	float tilt = brow_tilt + 0.15;
	vec2 b = m - vec2(0.36, 1.3);
	b.y -= b.x * tilt;
	float taper = mix(1.0, 0.45, smoothstep(-0.18, 0.2, b.x));
	float brow = blob(b, vec2(0.0), vec2(0.21, 0.06 * taper), 0.3);
	brow *= 0.75 + 0.25 * noise(vec3(q.x * 40.0, q.y * 8.0, 0.0));
	color = mix(color, hair_color * 0.8, brow * front);

	// Mouth: a dark parting line with a fuller lower lip under it.
	float mouth_w = 0.17 * jaw;
	vec2 mp = p - vec2(0.0, 0.47);
	mp.y -= mp.x * mp.x * smile * 3.0;
	color = mix(color, lip_color, blob(mp, vec2(0.0, -0.035), vec2(mouth_w * 0.85, 0.04), 0.5) * front);
	color = mix(color, lip_color * 0.4, blob(mp, vec2(0.0), vec2(mouth_w, 0.014), 0.4) * front);
	color = mix(color, mix(color, light_color, 0.4), blob(mp, vec2(0.0, -0.06), vec2(mouth_w * 0.4, 0.015), 0.8) * front);
}

void fragment() {
	vec3 p = local_pos;
	vec3 n = normalize(local_normal);

	// Painted light: lit from above and a little in front.
	float lit = clamp(dot(n, normalize(vec3(0.15, 1.0, -0.35))) * 0.5 + 0.5, 0.0, 1.0);
	vec3 color = mix(shade_color, base_color, smoothstep(0.0, 0.55, lit));
	color = mix(color, light_color, smoothstep(0.65, 1.0, lit) * 0.6);

	// Loose brush strokes all over, pushing the color toward the shade or
	// the light rather than just darker or lighter.
	float wash = fbm(p * 7.0 + vec3(3.0));
	float rough = 0.0;
	if (pattern == SKIN) {
		float s = strokes(p, 6.0, 26.0);
		color = mix(color, shade_color, smoothstep(0.55, 0.85, wash) * 0.25);
		color = mix(color, light_color, smoothstep(0.55, 0.8, s) * 0.18);
		color = mix(color, vec3(0.75, 0.35, 0.3) * base_color * 1.4, smoothstep(0.5, 0.8, fbm(p * 4.0)) * 0.12);
		rough = 0.7;
	} else if (pattern == LINEN) {
		// Coarse weave, folds and old stains.
		float weave = sin(p.x * 900.0 + p.z * 900.0) * sin(p.y * 900.0);
		float folds = strokes(p, 3.0, 22.0);
		color *= 1.0 + weave * 0.035;
		color = mix(color, shade_color, smoothstep(0.5, 0.85, folds) * 0.45);
		color = mix(color, light_color, smoothstep(0.45, 0.15, folds) * 0.3);
		color = mix(color, shade_color * vec3(1.05, 0.95, 0.75), smoothstep(0.68, 0.8, wash) * 0.25);
		rough = 0.95;
	} else if (pattern == WOOL) {
		// Heavy cloth hanging in long folds, with darker wear.
		float folds = strokes(p, 4.0, 30.0);
		float hatch = noise(p * vec3(160.0, 40.0, 160.0));
		color = mix(color, shade_color, smoothstep(0.45, 0.85, folds) * 0.55);
		color = mix(color, light_color, smoothstep(0.42, 0.2, folds) * 0.35);
		color *= 0.93 + hatch * 0.12;
		rough = 0.95;
	} else if (pattern == LEATHER) {
		// Mottled hide, scuffed lighter, with dark creases.
		float mottle = fbm(p * 18.0);
		float creases = 1.0 - smoothstep(0.0, 0.06, abs(strokes(p, 2.0, 40.0) - 0.5));
		color = mix(color, shade_color, smoothstep(0.45, 0.75, mottle) * 0.5);
		color = mix(color, light_color, smoothstep(0.72, 0.85, wash) * 0.45);
		color = mix(color, shade_color * 0.6, creases * 0.4);
		rough = 0.6;
	} else if (pattern == HAIR) {
		// Clumps of strands with a painted shine across them. Strands run
		// down from the top of each piece, like meridians on a globe.
		float around = atan(p.z, p.x) * 0.1;
		vec3 h = vec3(around, p.y, 0.0);
		float clumps = fbm(h * vec3(45.0, 5.0, 1.0));
		float strands = fbm(h * vec3(220.0, 12.0, 1.0) + vec3(0.0, 0.0, 1.7));
		color = mix(color, shade_color, smoothstep(0.4, 0.75, clumps) * 0.6);
		color = mix(color, light_color, smoothstep(0.62, 0.85, strands) * 0.45);
		color = mix(color, shade_color * 0.7, smoothstep(0.4, 0.25, strands) * 0.4);
		float shine = smoothstep(0.55, 0.85, lit) * smoothstep(0.98, 0.8, lit);
		color = mix(color, light_color, shine * smoothstep(0.35, 0.7, strands) * 0.6);
		rough = 0.55;
	} else if (pattern == METAL) {
		// Bold bands of reflected light, as metal is painted.
		float band = smoothstep(0.45, 0.6, lit) - smoothstep(0.8, 0.95, lit) * 0.6;
		color = mix(shade_color * 0.7, light_color, band);
		color = mix(color, vec3(1.0), smoothstep(0.88, 0.98, lit) * 0.7);
		color = mix(color, shade_color * 0.5, smoothstep(0.6, 0.8, wash) * 0.3);
		rough = 0.35;
	} else if (pattern == ROPE) {
		// Twisted strands.
		float twist = sin(dot(p, normalize(grain)) * 260.0 + atan(p.z, p.x) * 3.0);
		color = mix(color, mix(shade_color, color, 0.5), twist * 0.5 + 0.5);
		color = mix(color, light_color, smoothstep(0.7, 1.0, twist) * smoothstep(0.5, 0.9, lit) * 0.5);
		rough = 0.95;
	}

	if (face) {
		paint_face(p / head_r, color);
	}

	// A dark painted edge where the surface turns away, like an inked line.
	float edge = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	color = mix(color, shade_color * 0.55, smoothstep(0.55, 0.95, edge) * 0.35);

	ALBEDO = color;
	ROUGHNESS = 0.5 + rough * 0.5;
}

void light() {
	// Wrapped, softly banded diffuse light: broad painted planes rather than
	// smooth photographic falloff.
	float ndl = dot(NORMAL, LIGHT);
	float wrapped = clamp((ndl + 0.4) / 1.4, 0.0, 1.0);
	float banded = mix(wrapped, smoothstep(0.3, 0.5, wrapped) * 0.75 + 0.25 * wrapped, 0.6);
	DIFFUSE_LIGHT += banded * ATTENUATION * LIGHT_COLOR / PI;
	// A crisp painted glint on the shinier materials (leather, hair, metal).
	float shine = clamp((0.85 - ROUGHNESS) * 4.0, 0.0, 1.0);
	if (shine > 0.0) {
		vec3 h = normalize(LIGHT + VIEW);
		float glint = smoothstep(0.93, 0.97, dot(NORMAL, h));
		SPECULAR_LIGHT += glint * shine * ATTENUATION * LIGHT_COLOR * 0.15;
	}
}
