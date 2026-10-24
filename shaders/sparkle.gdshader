shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// A glint over something that can be picked up (see scripts/sparkle.gd): a
// little four-pointed star, painted in two flat tones like the rest of the
// art, that flares up now and then at a new spot around the item and fades
// back to a small, softly pulsing star. It's one quad drawn unshaded, and a
// whole region of them is one MultiMesh (see scripts/forage.gd).
//
// Every glint is worked out here from the time and where the item lies, so
// nothing is updated from script and no two items blink together.

uniform vec3 color : source_color = vec3(1.0, 0.88, 0.55);
uniform vec3 core_color : source_color = vec3(1.0, 0.98, 0.9);
// Meters across at its brightest.
uniform float size = 0.4;
// Seconds between one item's glints, and how much of that it's showing.
uniform float period = 1.8;
uniform float shown = 0.45;
// How far around the item a glint can appear, in meters.
uniform vec3 spread = vec3(0.22, 0.16, 0.22);
// A one-off flare, 0 to 1, set per item from script: a freshly dropped item
// (see scripts/item_pickup.gd) shines big and bright right over itself while
// it lands, settling back to its usual glints as this goes back to 0.
instance uniform float burst = 0.0;
// Glints fade out between these distances from the camera.
uniform float fade_start = 40.0;
uniform float fade_end = 50.0;

varying float glint;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	// A hidden instance is scaled to nothing (see forage.gd's _set_shown).
	float scale = length(MODEL_MATRIX[0].xyz);
	float seed = hash(floor(origin * 8.0));
	// Each item's glints come at a slightly different pace, so they drift
	// apart instead of falling into step.
	float t = TIME / (period * (0.8 + 0.4 * seed)) + seed * 13.0;
	float cycle = fract(t) / shown;
	// Between flares a small star stays lit, gently pulsing, so every item
	// is marked all the time.
	float idle = 0.35 + 0.1 * sin(TIME * 3.0 + seed * TAU);
	glint = max(cycle < 1.0 ? sin(cycle * PI) : 0.0, idle);
	float n = floor(t);
	vec3 at = origin + (vec3(hash(vec3(n, seed, 1.0)), hash(vec3(seed, n, 2.0)), hash(vec3(3.0, n, seed))) * 2.0 - 1.0) * spread * scale;
	// A flare sits right on the item, bright and up to two and a half times as big.
	at = mix(at, origin, burst);
	glint = max(glint, burst);
	glint *= 1.0 - smoothstep(fade_start, fade_end, distance(at, CAMERA_POSITION_WORLD));
	// Face the camera, growing with the glint.
	vec2 corner = (UV - 0.5) * vec2(1.0, -1.0) * size * scale * glint * (1.0 + 1.5 * burst);
	vec3 world = at + INV_VIEW_MATRIX[0].xyz * corner.x + INV_VIEW_MATRIX[1].xyz * corner.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	// A star with four thin points and a brighter heart, in a faint round
	// halo so it reads against bright ground too.
	// The resting star is small but still bright enough to catch the eye.
	float bright = min(glint * 1.8, 1.0);
	vec2 p = abs(UV - 0.5) * 2.0;
	float star = 1.0 - (sqrt(p.x) + sqrt(p.y));
	if (star < 0.0) {
		if (length(p) > 0.42) {
			discard;
		}
		ALBEDO = color;
		ALPHA = 0.35 * bright;
	} else {
		bool heart = star > 0.4;
		ALBEDO = heart ? core_color : color;
		ALPHA = bright;
	}
}
