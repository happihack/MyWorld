// The outline of the selected person (bible §28.4 "a subtle ring and
// outline"): the same body, a little larger, drawn inside out in one flat
// colour behind the body itself. A second pass on the selected person's
// material only — nobody else pays for it.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

#include "res://assets/shaders/person_motion.gdshaderinc"

uniform vec4 outline_color : source_color = vec4(1.0, 0.86, 0.45, 1.0);
// How much larger than the body, as a fraction of its height.
uniform float thickness = 0.055;

void vertex() {
	vec3 moved = person_motion(VERTEX, UV, TIME);
	// Outwards from the body's own axis (the mesh is flat-shaded: pushing
	// along the normals would pull its faces apart), and a little taller.
	vec2 away = moved.xz;
	float reach = length(away);
	if (reach > 0.0001) {
		moved.xz += away / reach * thickness;
	}
	moved.y += (moved.y - 0.45) * thickness * 1.4;
	VERTEX = moved;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
