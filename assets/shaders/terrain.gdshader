// Terrain blocks (bible §28.2): vertex colours from TerrainMesher plus drifting
// cloud shadows. Works on the Mobile and Compatibility renderers.
shader_type spatial;
render_mode world_vertex_coords, cull_back;

#include "res://assets/shaders/clouds.gdshaderinc"
#include "res://assets/shaders/fog.gdshaderinc"

// How wet the ground is from rain (0..1): wet earth is darker.
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
// The seasons (WeatherFx): what the green of the ground turns towards and
// how far, and how much snow lies (0..1: everything white).
uniform vec3 season_ground : source_color = vec3(0.40, 0.66, 0.28);
uniform float season_strength : hint_range(0.0, 1.0) = 0.0;
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 snow_color : source_color = vec3(0.93, 0.95, 0.98);

varying vec3 v_color;

void vertex() {
	// Palette colours are sRGB; convert unless the renderer already works in
	// sRGB (Compatibility), where converting would darken everything twice.
	vec3 color = COLOR.rgb;
	// What is green turns with the seasons (earth and rock do not).
	float green = clamp((color.g - max(color.r, color.b)) * 5.0, 0.0, 1.0);
	float light = dot(color, vec3(0.3, 0.59, 0.11)) / max(dot(season_ground, vec3(0.3, 0.59, 0.11)), 0.05);
	color = mix(color, season_ground * light, season_strength * green);
	// Snow: in patches at first, on what faces up (a little on the sides).
	float patches = _cloud_noise(VERTEX.xz * 0.37 + vec2(3.1, 8.7));
	float lying = smoothstep(1.0 - snow * 1.3, 1.15 - snow * 1.3, patches) * step(0.01, snow);
	color = mix(color, snow_color, lying * mix(0.25, 1.0, step(0.5, NORMAL.y)));
	if (!OUTPUT_IS_SRGB) {
		color = pow(color, vec3(2.2));
	}
	color *= mix(vec3(1.0), vec3(0.74, 0.78, 0.84), wetness);
	v_color = fog_apply(color * cloud_light(VERTEX.xz, TIME), fog_known(VERTEX.xz));
}

void fragment() {
	ALBEDO = v_color;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}
