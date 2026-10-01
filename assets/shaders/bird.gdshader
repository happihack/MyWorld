// Ambient birds (bible §28.2). A tiny two-wing mesh; the wing tips flap.
// Mesh: UV.x = 1 at wing tips, 0 at the body. MultiMesh custom data .x = phase.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 bird_color : source_color = vec3(0.16, 0.17, 0.20);
uniform float flap_speed = 9.0;
uniform float flap_height = 0.22;

void vertex() {
	VERTEX.y += UV.x * sin(TIME * flap_speed + INSTANCE_CUSTOM.x) * flap_height;
}

void fragment() {
	ALBEDO = bird_color;
}
