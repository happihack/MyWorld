// Cloud shadows (bible §28.2): large soft patches of shade drifting across the
// world. Evaluated per vertex (the patches are far bigger than a tile), so the
// cost is negligible. Shared by the terrain, prop and water shaders.

uniform float cloud_strength : hint_range(0.0, 1.0) = 0.2;
// 1 / patch size in tiles.
uniform float cloud_scale = 0.055;
// Drift in noise units per second (x, z).
uniform vec2 cloud_drift = vec2(0.016, 0.006);

float _cloud_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float _cloud_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(_cloud_hash(i), _cloud_hash(i + vec2(1.0, 0.0)), f.x),
			mix(_cloud_hash(i + vec2(0.0, 1.0)), _cloud_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Light factor for a world position: 1 in the sun, lower under a cloud.
float cloud_light(vec2 world_xz, float time) {
	vec2 p = world_xz * cloud_scale + cloud_drift * time;
	float n = _cloud_noise(p) * 0.65 + _cloud_noise(p * 2.1 + vec2(7.3, 1.9)) * 0.35;
	return 1.0 - smoothstep(0.50, 0.72, n) * cloud_strength;
}
