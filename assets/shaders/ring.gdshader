// An expanding ring on a flat quad: ripples on water, the pulse of a ruin
// (bible §23, §28.2). Procedural, no textures; works on the Mobile and
// Compatibility renderers.
//
// The quad's UV runs 0..1; `progress` runs 0 (just touched) .. 1 (gone).
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 ring_color : source_color = vec4(1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float d = length(UV * 2.0 - 1.0); // 0 at the centre .. 1 at the quad's edge
	float width = mix(0.11, 0.05, progress);
	float lead = progress * 0.92;
	float ring = 1.0 - smoothstep(0.0, width, abs(d - lead));
	// A second, fainter ring follows the first.
	float trail = max(progress - 0.30, 0.0) * 0.92;
	float second = (1.0 - smoothstep(0.0, width * 0.8, abs(d - trail))) * step(0.001, trail) * 0.55;
	float fade = (1.0 - progress) * (1.0 - progress);
	ALBEDO = ring_color.rgb;
	ALPHA = clamp(max(ring, second), 0.0, 1.0) * fade * ring_color.a;
}
