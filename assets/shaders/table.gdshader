// The surface the box stands on (bible §7.1, §28.2): a soft pool of tabletop
// that fades into the background, with a contact shadow around the box.
// Unshaded, so its edge blends exactly into the background colour.
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec3 table_color : source_color = vec3(0.26, 0.21, 0.19);
uniform vec3 background_color : source_color = vec3(0.1137, 0.1412, 0.1882);
// Centre and half-size of the box footprint (world XZ).
uniform vec2 box_center = vec2(0.0);
uniform vec2 box_half = vec2(34.0);
uniform float fade_start = 40.0;
uniform float fade_end = 110.0;
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.55;
uniform float shadow_reach = 5.0;

varying vec2 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = v_world - box_center;
	// Distance outside the box footprint (0 underneath it).
	float outside = length(max(abs(p) - box_half, vec2(0.0)));
	float shadow = 1.0 - shadow_strength * exp(-outside / shadow_reach);
	float fade = smoothstep(fade_start, fade_end, length(p));
	ALBEDO = mix(table_color * shadow, background_color, fade);
}
