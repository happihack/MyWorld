// Props: trees, bushes, rocks, huts, grass (bible §28.2). Vertex colours only.
//
// Mesh data from PropMesher:  COLOR.rgb = colour (sRGB)
//                             COLOR.a   = wind-sway weight (0 rigid .. 1 treetop)
//                             UV.x      = what glows: 0 nothing, 1 a window or
//                                         doorway (lit at night), 2 a flame
// Works on the Mobile and Compatibility renderers.
shader_type spatial;
render_mode world_vertex_coords, cull_back;

#include "res://assets/shaders/clouds.gdshaderinc"

uniform float sway_amplitude = 0.055;
uniform float sway_speed = 1.3;
uniform vec2 wind_direction = vec2(1.0, 0.35);

// Touch impulses (WorldEffects): props are merged per chunk, so a single prop
// is shaken by moving the vertices standing around its base.
//   impulse_origin: xyz = base of the shaken prop, w = radius (0 = unused slot)
//   impulse_offset: xy = lean at the top (world XZ), z = lift, w = 1 / body height
const int IMPULSE_COUNT = 4;
uniform vec4 impulse_origin[4];
uniform vec4 impulse_offset[4];

// Day and night (DayNight): how brightly windows are lit (0 by day) and how
// strongly flames shine.
uniform float night_glow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.74, 0.36);
uniform float flame_glow = 0.6;
// Houses whose lights are out (everyone in them is asleep, or nobody lives
// there): xyz = the house's base, w = radius (0 = unused slot).
const int DARK_COUNT = 8;
uniform vec4 lights_out[8];

varying vec3 v_color;
varying float v_glow;

void vertex() {
	v_glow = UV.x;
	if (v_glow > 0.5 && v_glow < 1.5) {
		for (int i = 0; i < DARK_COUNT; i++) {
			float reach = lights_out[i].w;
			if (reach > 0.0 && distance(VERTEX.xz, lights_out[i].xz) < reach) {
				v_glow = 0.0;
			}
		}
	}
	// With world_vertex_coords, VERTEX is already in world space, so the wind
	// blows the same way for every prop regardless of its own rotation.
	vec3 rest = VERTEX;
	float weight = COLOR.a;
	float phase = rest.x * 0.35 + rest.z * 0.45;
	float t = TIME * sway_speed;
	float gust = sin(t + phase) + 0.5 * sin(t * 2.3 + phase * 1.7);
	VERTEX.xz += normalize(wind_direction) * gust * sway_amplitude * weight;
	for (int i = 0; i < IMPULSE_COUNT; i++) {
		float radius = impulse_origin[i].w;
		if (radius <= 0.0) {
			continue;
		}
		vec3 rel = rest - impulse_origin[i].xyz;
		float inside = (1.0 - smoothstep(radius * 0.75, radius, length(rel.xz))) * step(-0.05, rel.y);
		// Bends like a stem: the base stays planted, the top moves most.
		float up = clamp(rel.y * impulse_offset[i].w, 0.0, 1.2);
		VERTEX.xz += impulse_offset[i].xy * inside * up * up;
		VERTEX.y += impulse_offset[i].z * inside;
	}
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
	float window = clamp(v_glow, 0.0, 1.0) * (1.0 - step(1.5, v_glow)) * night_glow;
	float flame = step(1.5, v_glow);
	ALBEDO = mix(v_color, glow_color, window);
	EMISSION = glow_color * window * 1.4 + v_color * flame * flame_glow;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}
