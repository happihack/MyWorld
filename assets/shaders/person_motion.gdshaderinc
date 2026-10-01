// How people move without a skeleton (bible §28.4): walking, breathing,
// working, an elder's stoop — all in the vertex shader. Shared by the body
// (person.gdshader) and its outline (person_outline.gdshader), so that the
// outline moves exactly as the body does.
//
// Mesh data from PersonMeshLibrary (the body is 1 unit tall, facing +X):
//   UV.x = limb side: +1 / -1 swing opposite ways, 0 = not a limb
//   UV.y = how far along the limb (0 at the hip or shoulder, 1 at the end)

// 0 standing … 1 walking.
instance uniform float walk = 0.0;
// So that people do not breathe and step in unison.
instance uniform float phase = 0.0;
// How far an elder bends forward.
instance uniform float stoop = 0.0;
// 0 standing about … 1 hard at work: the arms go, the back bends.
instance uniform float busy = 0.0;

// 1 = full motion; lower with "reduced motion".
uniform float motion = 1.0;
uniform float stride_speed = 9.0;

// Where a vertex of the resting body is right now.
vec3 person_motion(vec3 vertex, vec2 uv, float time) {
	float h = clamp(vertex.y, 0.0, 1.0);
	float upper = smoothstep(0.3, 1.0, h);
	float stride = time * stride_speed + phase;
	float going = walk * motion;
	// Breathing: the chest rises a little.
	vertex.y += sin(time * 1.7 + phase) * 0.006 * upper * motion;
	// Walking: a bob at every step, a slight roll, limbs swinging.
	vertex.y += abs(sin(stride)) * 0.035 * going;
	vertex.z += sin(stride) * 0.02 * going * upper;
	vertex.x += sin(stride) * uv.x * uv.y * 0.17 * going;
	vertex.y += abs(sin(stride)) * abs(uv.x) * uv.y * 0.03 * going;
	// At work: both arms swing forward and up together, the body dips with them.
	float doing = busy * motion;
	float swing = 0.5 + 0.5 * sin(time * 6.5 + phase);
	float arm = step(0.3, h) * abs(uv.x) * uv.y;
	vertex.x += swing * arm * 0.26 * doing;
	vertex.y += swing * arm * 0.12 * doing;
	vertex.y -= swing * 0.015 * upper * doing;
	// Leaning: into the walk, into the work, and with age.
	float lean = going * 0.06 + stoop + doing * (0.04 + swing * 0.03);
	vertex.x += lean * h * h;
	vertex.y -= stoop * 0.35 * h * h;
	return vertex;
}
