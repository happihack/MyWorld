// Rain and snow (bible §10.1, §28.2): every drop is an instance of one quad,
// placed and moved here, in the vertex shader — nothing is computed per drop
// on the CPU, and it looks the same on the Mobile and Compatibility renderers.
//
// The drops fill a square around what the camera looks at and wrap around
// in it as it moves; what would fall outside the box is not drawn.
//
// INSTANCE_CUSTOM: x, y = where in the square (0..1), z = when in its fall
// (0..1), w = which share of the drops it belongs to (0..1: drawn while
// `amount` is above it).
shader_type spatial;
render_mode unshaded, skip_vertex_transform, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

// The square: its middle (world x, z) and its side.
uniform vec2 area_center = vec2(0.0);
uniform float area_size = 30.0;
// From where they fall to where they are gone (world y).
uniform float top = 12.0;
uniform float bottom = 0.0;
// World units a second.
uniform float fall_speed = 14.0;
// Where the wind carries them (world x, z, units a second).
uniform vec2 wind = vec2(0.0);
// How many of the drops are drawn (0..1).
uniform float amount : hint_range(0.0, 1.0) = 0.0;
// 0 = rain (streaks), 1 = snow (flakes that sway).
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform float streak_length = 0.9;
uniform float drop_width = 0.035;
uniform float flake_size = 0.11;
uniform vec4 tint : source_color = vec4(0.82, 0.88, 0.95, 0.5);
// The light there is to see them by (0..1).
uniform float daylight = 1.0;
// The box (world x, z): nothing falls outside it.
uniform vec2 box_min = vec2(-1000.0);
uniform vec2 box_max = vec2(1000.0);

varying float v_alpha;
varying vec2 v_uv;

void vertex() {
	vec4 seed = INSTANCE_CUSTOM;
	float height = max(top - bottom, 0.1);
	// Each drop falls a little faster or slower than the others.
	float speed = fall_speed * (0.8 + 0.4 * fract(seed.x * 7.31 + seed.y * 3.17));
	float fallen = fract(seed.z + TIME * speed / height);
	// Where it began this fall: wrapped into the square around the camera.
	vec2 cell = fract(seed.xy - area_center / area_size + 0.5) - 0.5;
	vec2 start = area_center + cell * area_size;
	float seconds = fallen * height / speed;
	vec2 drift = wind * seconds;
	// Snow sways as it comes down.
	float sway = snow * 0.35 * sin(TIME * 1.7 + seed.x * 40.0 + fallen * 9.0);
	vec3 at = vec3(start.x + drift.x + sway, top - fallen * height, start.y + drift.y + sway * 0.6);
	// A streak lies along the way it falls; a flake faces the viewer.
	vec3 along = normalize(vec3(-wind.x, speed, -wind.y));
	vec3 to_camera = normalize(CAMERA_POSITION_WORLD - at);
	vec3 side = normalize(cross(to_camera, along));
	vec3 up = mix(along, normalize(cross(side, to_camera)), snow);
	float wide = mix(drop_width, flake_size, snow);
	float tall = mix(streak_length, flake_size, snow);
	vec3 world = at + side * (VERTEX.x * wide) + up * (VERTEX.y * tall);
	// Not drawn: beyond the share that falls now, or outside the box.
	float shown = step(seed.w, amount) * step(box_min.x, at.x) * step(at.x, box_max.x) * step(box_min.y, at.z) * step(at.z, box_max.y);
	world = mix(at, world, shown);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	// Fading in at the top and out at the bottom, so nothing pops.
	v_alpha = shown * smoothstep(0.0, 0.08, fallen) * (1.0 - smoothstep(0.9, 1.0, fallen));
	v_uv = UV;
}

void fragment() {
	// A streak is soft at its ends and its edges; a flake is a soft dot.
	vec2 p = v_uv * 2.0 - 1.0;
	float streak = (1.0 - abs(p.x)) * (1.0 - p.y * p.y);
	float flake = 1.0 - smoothstep(0.35, 1.0, length(p));
	float shape = mix(streak, flake, snow);
	vec3 color = tint.rgb * mix(0.32, 1.0, daylight);
	if (!OUTPUT_IS_SRGB) {
		color = pow(color, vec3(2.2));
	}
	ALBEDO = color;
	ALPHA = clamp(tint.a * shape * v_alpha * mix(1.0, 1.7, snow), 0.0, 1.0);
}
