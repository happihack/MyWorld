// Soft darkening toward the screen corners: a cheap "looking into a small
// world" cue (bible §28.2). Full-screen ColorRect on a CanvasLayer under the UI.
shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.38;
uniform float inner : hint_range(0.0, 1.5) = 0.55;
uniform float outer : hint_range(0.0, 2.0) = 1.05;

void fragment() {
	float d = length((UV - vec2(0.5)) * 1.42);
	COLOR = vec4(0.0, 0.0, 0.0, smoothstep(inner, outer, d) * strength);
}
