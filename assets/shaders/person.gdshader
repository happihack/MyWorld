// People (bible §28.4): one small mesh for everyone, told apart by colour,
// size and bearing. No skeleton: the motion is in person_motion.gdshaderinc.
//
// Mesh data from PersonMeshLibrary (the body is 1 unit tall, facing +X):
//   COLOR.rgb = how much of the cloth / skin / hair colour (black where none)
//   COLOR.a   = shade (darker trousers, lighter tunic)
//   UV        = limbs (see person_motion.gdshaderinc)
// Works on the Mobile and Compatibility renderers.
shader_type spatial;
render_mode cull_back;

#include "res://assets/shaders/clouds.gdshaderinc"
#include "res://assets/shaders/person_motion.gdshaderinc"

instance uniform vec3 cloth_color : source_color = vec3(0.70, 0.30, 0.22);
instance uniform vec3 skin_color : source_color = vec3(0.80, 0.60, 0.45);
instance uniform vec3 hair_color : source_color = vec3(0.20, 0.14, 0.10);

varying vec3 v_mask;
varying float v_light;

void vertex() {
	VERTEX = person_motion(VERTEX, UV, TIME);
	v_mask = COLOR.rgb;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_light = COLOR.a * cloud_light(world.xz, TIME);
}

void fragment() {
	ALBEDO = (cloth_color * v_mask.r + skin_color * v_mask.g + hair_color * v_mask.b) * v_light;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}
