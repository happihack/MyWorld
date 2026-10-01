// People (bible §28.4): one small mesh for everyone, told apart by colour,
// size and bearing. No skeleton: walking, breathing and an elder's stoop are
// done here, in the vertex shader.
//
// Mesh data from PersonMeshLibrary (the body is 1 unit tall, facing +X):
//   COLOR.rgb = how much of the cloth / skin / hair colour (black where none)
//   COLOR.a   = shade (darker trousers, lighter tunic)
//   UV.x      = limb side: +1 / -1 swing opposite ways, 0 = not a limb
//   UV.y      = how far along the limb (0 at the hip or shoulder, 1 at the end)
// Works on the Mobile and Compatibility renderers.
shader_type spatial;
render_mode cull_back;

#include "res://assets/shaders/clouds.gdshaderinc"

instance uniform vec3 cloth_color : source_color = vec3(0.70, 0.30, 0.22);
instance uniform vec3 skin_color : source_color = vec3(0.80, 0.60, 0.45);
instance uniform vec3 hair_color : source_color = vec3(0.20, 0.14, 0.10);
// 0 standing … 1 walking.
instance uniform float walk = 0.0;
// So that people do not breathe and step in unison.
instance uniform float phase = 0.0;
// How far an elder bends forward.
instance uniform float stoop = 0.0;

// 1 = full motion; lower with "reduced motion".
uniform float motion = 1.0;
uniform float stride_speed = 9.0;

varying vec3 v_mask;
varying float v_light;

void vertex() {
	float h = clamp(VERTEX.y, 0.0, 1.0);
	float upper = smoothstep(0.3, 1.0, h);
	float stride = TIME * stride_speed + phase;
	float going = walk * motion;
	// Breathing: the chest rises a little.
	VERTEX.y += sin(TIME * 1.7 + phase) * 0.006 * upper * motion;
	// Walking: a bob at every step, a slight roll, limbs swinging.
	VERTEX.y += abs(sin(stride)) * 0.035 * going;
	VERTEX.z += sin(stride) * 0.02 * going * upper;
	VERTEX.x += sin(stride) * UV.x * UV.y * 0.17 * going;
	VERTEX.y += abs(sin(stride)) * abs(UV.x) * UV.y * 0.03 * going;
	// Leaning: into the walk, and with age.
	float lean = going * 0.06 + stoop;
	VERTEX.x += lean * h * h;
	VERTEX.y -= stoop * 0.35 * h * h;

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
