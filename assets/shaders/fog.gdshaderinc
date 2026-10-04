// Fog of knowledge (M13.4, bible §8.7): land nobody knows — neither the
// player (seen close up) nor anyone in the world (been there, or seen it) —
// is drawn dimmed and greyed, never black: the diorama stays beautiful.
// `fog_map`: one texel per tile, red = known (0 … 1); without one, all is known.
uniform sampler2D fog_map : filter_linear, repeat_disable, hint_default_white;
// The tiles the map covers: x, z of its corner, its width and depth.
uniform vec4 fog_rect = vec4(-32.0, -32.0, 64.0, 64.0);
uniform float fog_strength : hint_range(0.0, 1.0) = 0.0;

float fog_known(vec2 xz) {
	if (fog_strength <= 0.0) {
		return 1.0;
	}
	vec2 uv = (xz - fog_rect.xy) / fog_rect.zw;
	return textureLod(fog_map, uv, 0.0).r;
}

vec3 fog_apply(vec3 color, float known) {
	float grey = dot(color, vec3(0.3, 0.59, 0.11));
	vec3 dim = mix(vec3(grey), color, 0.35) * 0.72;
	return mix(color, dim, (1.0 - known) * fog_strength);
}
