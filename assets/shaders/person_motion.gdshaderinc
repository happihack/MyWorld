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

// What the body is showing (PersonView.ACT): 0 nothing, 1 startled, 2 kneeling,
// 3 waving, 4 jumping, 5 crouching, 6 crying out, 7 shrugging.
instance uniform float act = 0.0;

// 1 = full motion; lower with "reduced motion".
uniform float motion = 1.0;
uniform float stride_speed = 9.0;

// 1 while `act` is `which`, else 0.
float acting(float which) {
	return 1.0 - step(0.5, abs(act - which));
}

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
	// What they are showing. Poses hold with reduced motion; only what
	// swings and bounces in them is calmed.
	if (act > 0.5) {
		float side = sign(vertex.z);          // which side of the body (arms hang at its sides)
		float along = arm;                    // 0 at the shoulder … 1 at the hand
		float above_legs = smoothstep(0.0, 0.3, h);
		float knee = 1.0 - clamp(abs(h - 0.15) / 0.15, 0.0, 1.0);
		float beat = sin(time * 9.0 + phase);
		// Startled: back on the heels, hands half up, stock still.
		float startled = acting(1.0);
		lean -= startled * 0.09;
		vertex.y += startled * along * 0.16;
		vertex.z += startled * along * side * 0.05;
		// Kneeling: down on the knees, bowed, hands together before the chest.
		float kneeling = acting(2.0);
		vertex.y -= kneeling * 0.17 * above_legs;
		vertex.x += kneeling * 0.10 * knee;
		lean += kneeling * (0.14 + 0.04 * sin(time * 1.6 + phase) * motion);
		vertex.x += kneeling * along * 0.20;
		vertex.y += kneeling * along * 0.22;
		vertex.z -= kneeling * along * side * 0.13;
		// Waving: one arm up, swinging from side to side.
		float waving = acting(3.0) * step(0.0, uv.x);
		vertex.y += waving * along * 0.50;
		vertex.z += waving * along * (0.08 + beat * 0.10 * motion);
		vertex.x += waving * along * 0.04;
		// Jumping for joy: up and down, both arms in the air.
		float jumping = acting(4.0);
		vertex.y += jumping * abs(sin(time * 6.5 + phase)) * 0.17 * motion;
		vertex.y += jumping * along * (0.44 + 0.06 * beat * motion);
		vertex.z += jumping * along * side * 0.06;
		// Crouching: low, bent over what is there, a hand out to it.
		float crouching = acting(5.0);
		vertex.y -= crouching * 0.13 * above_legs;
		vertex.x += crouching * 0.07 * knee;
		lean += crouching * 0.22;
		vertex.x += crouching * along * step(0.0, uv.x) * 0.24;
		vertex.y += crouching * along * step(0.0, uv.x) * 0.06;
		// Crying out: arms thrown up and shaking, leaning into it.
		float crying = acting(6.0);
		vertex.y += crying * along * 0.46;
		vertex.z += crying * along * side * (0.10 + 0.03 * beat * motion);
		vertex.x += crying * along * 0.05 * beat * motion;
		lean += crying * 0.06;
		// Shrugging: shoulders and hands up a little, and down again.
		float shrugging = acting(7.0);
		float shrug = 0.5 + 0.5 * sin(time * 3.2 + phase) * motion;
		vertex.y += shrugging * shrug * (along * 0.12 + upper * 0.012);
		vertex.z += shrugging * shrug * along * side * 0.07;
	}
	vertex.x += lean * h * h;
	vertex.y -= stoop * 0.35 * h * h;
	return vertex;
}
