// Props: trees, bushes, rocks, huts, grass (bible §28.2). Vertex colours only.
//
// Mesh data from PropMesher:  COLOR.rgb = colour (sRGB)
//                             COLOR.a   = wind-sway weight (0 rigid .. 1 treetop;
//                                         above 1 for the campfire flame)
// Works on the Mobile and Compatibility renderers.
shader_type spatial;
render_mode world_vertex_coords, cull_back;

#include "res://assets/shaders/clouds.gdshaderinc"

uniform float sway_amplitude = 0.055;
uniform float sway_speed = 1.3;
uniform vec2 wind_direction = vec2(1.0, 0.35);

varying vec3 v_color;

void vertex() {
	// With world_vertex_coords, VERTEX is already in world space, so the wind
	// blows the same way for every prop regardless of its own rotation.
	float weight = COLOR.a;
	float phase = VERTEX.x * 0.35 + VERTEX.z * 0.45;
	float t = TIME * sway_speed;
	float gust = sin(t + phase) + 0.5 * sin(t * 2.3 + phase * 1.7);
	VERTEX.xz += normalize(wind_direction) * gust * sway_amplitude * weight;
	// Palette colours are authored in sRGB. Mobile/Forward+ light in linear
	// space, so convert there; the Compatibility renderer already works in
	// sRGB (OUTPUT_IS_SRGB), where converting would darken everything twice.
	v_color = COLOR.rgb;
	if (!OUTPUT_IS_SRGB) {
		v_color = pow(COLOR.rgb, vec3(2.2));
	}
	v_color *= cloud_light(VERTEX.xz, TIME);
}

void fragment() {
	ALBEDO = v_color;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}
