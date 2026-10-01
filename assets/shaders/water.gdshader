// Water surface (bible §28.2). Fully procedural: no textures and no screen or
// depth reads, so it behaves the same on the Mobile and Compatibility
// renderers and stays cheap on phones.
//
// Mesh data from WaterMesher:  COLOR.r = depth (0 film .. 1 deep)
//                              COLOR.g = shore (1 at corners touching land)
//                              UV      = world XZ position
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, specular_schlick_ggx;

#include "res://assets/shaders/clouds.gdshaderinc"

uniform vec3 shallow_color : source_color = vec3(0.40, 0.74, 0.86);
uniform vec3 deep_color : source_color = vec3(0.13, 0.40, 0.68);
uniform vec3 foam_color : source_color = vec3(0.95, 0.98, 1.0);
uniform float opacity_shallow : hint_range(0.0, 1.0) = 0.62;
uniform float opacity_deep : hint_range(0.0, 1.0) = 0.90;
uniform float wave_height = 0.02;
uniform float wave_speed = 1.0;
uniform float ripple_strength : hint_range(0.0, 0.2) = 0.045;
uniform float foam_amount : hint_range(0.0, 1.0) = 0.75;

varying float v_depth;
varying float v_shore;
varying float v_cloud;

void vertex() {
	v_depth = COLOR.r;
	v_shore = COLOR.g;
	v_cloud = cloud_light(UV, TIME);
	float t = TIME * wave_speed;
	float wave = sin(UV.x * 1.7 + t * 1.3) + sin(UV.y * 2.1 - t);
	// Open water bobs gently; the shoreline stays put so it never lifts off the bank.
	VERTEX.y += wave * wave_height * (1.0 - v_shore) * step(0.5, NORMAL.y);
}

void fragment() {
	float t = TIME * wave_speed;
	// Three waves travelling in unrelated directions: no visible grid.
	float ripple = (sin(dot(UV, vec2(0.90, 0.44)) * 2.6 + t)
			+ sin(dot(UV, vec2(-0.37, 0.93)) * 3.4 - t * 1.3)
			+ sin(dot(UV, vec2(0.71, -0.70)) * 4.3 + t * 0.8)) / 3.0;

	vec3 color = mix(shallow_color, deep_color, smoothstep(0.0, 1.0, v_depth));
	color += ripple * ripple_strength;

	// Foam: a thin line at the shore whose inner edge wobbles with the ripples.
	float foam = smoothstep(0.72, 0.98, v_shore + ripple * 0.10) * foam_amount;
	color = mix(color, foam_color, foam);

	ALBEDO = color * v_cloud;
	ROUGHNESS = 0.18;
	SPECULAR = 0.5;
	METALLIC = 0.0;
	ALPHA = max(mix(opacity_shallow, opacity_deep, v_depth), foam);
}
