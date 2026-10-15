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
// How much of its daytime brightness the table has (1 by day, less at night).
uniform float daylight : hint_range(0.0, 1.0) = 1.0;
// The table's planks (an attic table, docs/art_assets.md §5): their width in
// world units, how dark the seam between two is, and how much the grain shows.
uniform float plank_width = 9.0;
uniform float seam_strength : hint_range(0.0, 1.0) = 0.22;
uniform float grain_strength : hint_range(0.0, 0.3) = 0.07;

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
	// Planks run along x; each a shade of its own, a dark seam between, and a
	// wandering grain along it.
	float plank = floor(v_world.y / plank_width);
	float across = fract(v_world.y / plank_width);
	float seam = 1.0 - seam_strength * (1.0 - smoothstep(0.0, 0.06, min(across, 1.0 - across)));
	float own_shade = 1.0 + 0.06 * (fract(sin(plank * 12.9898) * 43758.5453) - 0.5);
	float grain = sin(v_world.x * 0.35 + sin(v_world.y * 0.9 + plank) * 1.7 + across * 6.0);
	vec3 wood = table_color * seam * own_shade * (1.0 + grain_strength * grain);
	ALBEDO = mix(wood * shadow * daylight, background_color, fade);
}
