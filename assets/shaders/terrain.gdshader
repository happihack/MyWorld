// Terrain blocks (bible §28.2): vertex colours from TerrainMesher plus drifting
// cloud shadows. Works on the Mobile and Compatibility renderers.
shader_type spatial;
render_mode world_vertex_coords, cull_back;

#include "res://assets/shaders/clouds.gdshaderinc"

// How wet the ground is from rain (0..1): wet earth is darker.
uniform float wetness : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_color;

void vertex() {
	// Palette colours are sRGB; convert unless the renderer already works in
	// sRGB (Compatibility), where converting would darken everything twice.
	vec3 color = COLOR.rgb;
	if (!OUTPUT_IS_SRGB) {
		color = pow(color, vec3(2.2));
	}
	color *= mix(vec3(1.0), vec3(0.74, 0.78, 0.84), wetness);
	v_color = color * cloud_light(VERTEX.xz, TIME);
}

void fragment() {
	ALBEDO = v_color;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}
