// Shared by the hand painted shaders: shaders/hand_painted.gdshader (the
// characters) and shaders/painted_tree.gdshader (the trees). Noise to paint
// brush strokes with, and light that falls in a couple of broad painted bands
// instead of smooth photographic falloff.

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
