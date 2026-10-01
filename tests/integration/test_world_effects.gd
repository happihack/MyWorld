extends TestCase
## WorldEffects: the visual answers to touches (shakes, rings, particle bursts).

const SHADER := preload("res://assets/shaders/prop.gdshader")

var effects: WorldEffects
var material: ShaderMaterial


func before_each() -> void:
	material = ShaderMaterial.new()
	material.shader = SHADER
	effects = WorldEffects.new()
	add_child(effects)
	effects.set_process(false) # tests advance time themselves
	effects.setup(material)


func after_each() -> void:
	effects.queue_free()
	await wait_frames(1)


func _response(effect: StringName, id: int = 0, at: Vector3 = Vector3(2, 1, 3), body: Vector2 = Vector2(1.5, 0.4)) -> InteractionResponse:
	var r := InteractionResponse.new()
	r.effect = effect
	r.entity_id = id
	r.position = at
	r.body = body if id != 0 else Vector2.ZERO
	return r


## Largest lean of an entity while time advances by `seconds`.
func _peak_lean(id: int, seconds: float) -> float:
	var peak := 0.0
	var steps := int(seconds * 240.0)
	for i in steps:
		effects.advance(1.0 / 240.0)
		var o := effects.impulse_offset(id)
		peak = maxf(peak, Vector2(o.x, o.z).length())
	return peak


func test_a_tapped_tree_shakes_then_comes_to_rest() -> void:
	effects.play(_response(InteractionResponse.TREE_SHAKE, 7))
	assert_true(effects.is_shaking(7))
	assert_eq(effects.active_impulse_count(), 1)
	var spec: Dictionary = WorldEffects.SHAKES[InteractionResponse.TREE_SHAKE]
	var early := _peak_lean(7, 0.4)
	assert_true(early > float(spec["lean"]) * 0.4 and early <= float(spec["lean"]), "leans visibly (%.3f)" % early)
	var late := _peak_lean(7, float(spec["seconds"]) - 0.6)
	assert_true(late < early, "the shake dies down")
	_peak_lean(7, 0.3)
	assert_false(effects.is_shaking(7), "and stops")
	assert_eq(effects.active_impulse_count(), 0)
	assert_eq(effects.impulse_offset(7), Vector3.ZERO)


func test_shake_reaches_the_prop_shader() -> void:
	effects.play(_response(InteractionResponse.TREE_SHAKE, 7, Vector3(2, 1, 3), Vector2(1.5, 0.4)))
	effects.advance(0.08)
	var origins: PackedFloat32Array = material.get_shader_parameter(&"impulse_origin")
	var offsets: PackedFloat32Array = material.get_shader_parameter(&"impulse_offset")
	assert_eq(origins.size(), WorldEffects.MAX_IMPULSES * 4)
	assert_eq(offsets.size(), WorldEffects.MAX_IMPULSES * 4)
	assert_eq(Vector3(origins[0], origins[1], origins[2]), Vector3(2, 1, 3), "base of the prop")
	assert_near(origins[3], 0.4 * 1.5, 0.0001, "radius reaches past the canopy")
	assert_true(Vector2(offsets[0], offsets[1]).length() > 0.01, "leaning")
	assert_near(offsets[3], 1.0 / 1.5, 0.0001, "1 / body height")
	assert_near(origins[7], 0.0, 0.0, "other slots are unused")
	# At rest the slot is released again.
	for i in 400:
		effects.advance(1.0 / 60.0)
	origins = material.get_shader_parameter(&"impulse_origin")
	assert_near(origins[3], 0.0, 0.0)


func test_tapping_the_same_prop_again_restarts_its_shake() -> void:
	effects.play(_response(InteractionResponse.TREE_SHAKE, 7))
	_peak_lean(7, 1.2)
	effects.play(_response(InteractionResponse.TREE_SHAKE, 7))
	assert_eq(effects.active_impulse_count(), 1, "same slot")
	assert_true(_peak_lean(7, 0.4) > 0.06, "strong again")


func test_more_shakes_than_slots_replace_the_one_closest_to_rest() -> void:
	for id in [1, 2, 3, 4]:
		effects.play(_response(InteractionResponse.TREE_SHAKE, id, Vector3(id * 3, 0, 0)))
		effects.advance(0.2)
	assert_eq(effects.active_impulse_count(), WorldEffects.MAX_IMPULSES)
	effects.play(_response(InteractionResponse.ROCK_WOBBLE, 5, Vector3(20, 0, 0), Vector2(0.24, 0.26)))
	assert_eq(effects.active_impulse_count(), WorldEffects.MAX_IMPULSES)
	assert_true(effects.is_shaking(5))
	assert_false(effects.is_shaking(1), "the oldest gave up its slot")
	assert_true(effects.is_shaking(2) and effects.is_shaking(3) and effects.is_shaking(4))


func test_rock_hops_and_hut_barely_moves() -> void:
	effects.play(_response(InteractionResponse.ROCK_WOBBLE, 1, Vector3.ZERO, Vector2(0.24, 0.26)))
	effects.play(_response(InteractionResponse.BUILDING_KNOCK, 2, Vector3(5, 0, 0), Vector2(0.94, 0.5)))
	var hop := 0.0
	var hut_lean := 0.0
	for i in 60:
		effects.advance(1.0 / 240.0)
		hop = maxf(hop, effects.impulse_offset(1).y)
		var o := effects.impulse_offset(2)
		hut_lean = maxf(hut_lean, Vector2(o.x, o.z).length())
		assert_near(o.y, 0.0, 0.0, "huts do not jump")
	assert_true(hop > 0.02, "the rock hops (%.3f)" % hop)
	assert_true(hut_lean > 0.005 and hut_lean < 0.03, "a knock is a tiny shake (%.3f)" % hut_lean)


func test_a_boulder_stirs_less_than_a_rock() -> void:
	var rock := _response(InteractionResponse.ROCK_WOBBLE, 1, Vector3.ZERO, Vector2(0.24, 0.26))
	var boulder := _response(InteractionResponse.ROCK_WOBBLE, 2, Vector3(5, 0, 0), Vector2(0.44, 0.42))
	boulder.strength = 0.27
	effects.play(rock)
	effects.play(boulder)
	var rock_hop := 0.0
	var boulder_hop := 0.0
	for i in 60:
		effects.advance(1.0 / 240.0)
		rock_hop = maxf(rock_hop, effects.impulse_offset(1).y)
		boulder_hop = maxf(boulder_hop, effects.impulse_offset(2).y)
	assert_near(boulder_hop, rock_hop * 0.27, 0.002, "%.3f vs %.3f" % [boulder_hop, rock_hop])
	assert_true(boulder_hop > 0.0, "but it does answer")


func test_reduced_motion_weakens_shakes() -> void:
	effects.play(_response(InteractionResponse.TREE_SHAKE, 1))
	var normal := _peak_lean(1, 0.4)
	effects.reduced_motion = true
	effects.play(_response(InteractionResponse.TREE_SHAKE, 2))
	var reduced := _peak_lean(2, 0.4)
	assert_near(reduced, normal * WorldEffects.REDUCED_MOTION_SCALE, 0.01)


func test_water_ripples_and_fades() -> void:
	effects.play(_response(InteractionResponse.RIPPLE, 0, Vector3(4, 1.3, -2)))
	assert_eq(effects.active_ring_count(), 1)
	var ring: MeshInstance3D = effects.get_node("Ring0")
	assert_true(ring.visible)
	assert_near(ring.position.y, 1.3 + WorldEffects.RING_LIFT, 0.0001, "just above the surface")
	assert_near(ring.position.x, 4.0, 0.0001)
	effects.advance(0.5)
	var progress: float = (ring.material_override as ShaderMaterial).get_shader_parameter(&"progress")
	assert_near(progress, 0.5, 0.01)
	effects.advance(0.6)
	assert_eq(effects.active_ring_count(), 0)
	assert_false(ring.visible)
	assert_eq(effects.active_impulse_count(), 0, "water does not shake props")


func test_rings_are_pooled() -> void:
	for i in WorldEffects.RING_POOL + 3:
		effects.ring(Vector3(i, 0, 0), 1.0, 5.0, Color.WHITE)
	assert_eq(effects.active_ring_count(), WorldEffects.RING_POOL, "never more than the pool")
	var ring: MeshInstance3D = effects.get_node("Ring2")
	assert_near(ring.position.x, WorldEffects.RING_POOL + 2.0, 0.0001, "the oldest ring was reused")


func test_every_effect_plays_its_particles() -> void:
	var expected := {
		InteractionResponse.DUST: WorldEffects.Burst.DUST,
		InteractionResponse.RIPPLE: WorldEffects.Burst.DUST,
		InteractionResponse.TREE_SHAKE: WorldEffects.Burst.LEAVES,
		InteractionResponse.BUSH_RUSTLE: WorldEffects.Burst.LEAVES,
		InteractionResponse.ROCK_WOBBLE: WorldEffects.Burst.DUST,
		InteractionResponse.BUILDING_KNOCK: WorldEffects.Burst.DUST,
		InteractionResponse.FIRE_FLARE: WorldEffects.Burst.SPARKS,
		InteractionResponse.RUIN_HUM: WorldEffects.Burst.MOTES,
	}
	var id := 1
	for effect: StringName in expected:
		var kind: WorldEffects.Burst = expected[effect]
		var before := effects.burst_count(kind)
		var entity := 0 if effect in [InteractionResponse.DUST, InteractionResponse.RIPPLE] else id
		effects.play(_response(effect, entity, Vector3(id, 1, 0)))
		assert_eq(effects.burst_count(kind), before + 1, String(effect))
		assert_near(effects.last_burst_position(kind).x, float(id), 0.0001, String(effect))
		assert_eq(effects.played[effect], 1)
		id += 1


func test_leaves_fall_from_the_canopy_and_particles_are_emitted() -> void:
	effects.play(_response(InteractionResponse.TREE_SHAKE, 3, Vector3(0, 1, 0), Vector2(1.5, 0.4)))
	var at := effects.last_burst_position(WorldEffects.Burst.LEAVES)
	assert_true(at.y > 1.0 + 0.8 and at.y < 1.0 + 1.5, "inside the canopy (%.2f)" % at.y)
	var emitter: CPUParticles3D = effects.get_node("Leaves0")
	assert_true(emitter.emitting)
	assert_true(emitter.one_shot)
	assert_eq(emitter.position, at)


func test_ruin_hums_with_a_ring_and_motes() -> void:
	effects.play(_response(InteractionResponse.RUIN_HUM, 9, Vector3(1, 0.5, 1), Vector2(0.7, 0.42)))
	assert_eq(effects.active_ring_count(), 1)
	assert_true(effects.is_shaking(9))
	assert_eq(effects.burst_count(WorldEffects.Burst.MOTES), 1)
	var hum := _peak_lean(9, 0.3)
	assert_true(hum > 0.0 and hum < 0.012, "a faint vibration (%.4f)" % hum)


func test_inspect_and_null_show_nothing() -> void:
	effects.play(null)
	effects.play(_response(InteractionResponse.INSPECT, 4))
	assert_eq(effects.active_impulse_count(), 0)
	assert_eq(effects.active_ring_count(), 0)
	for kind: WorldEffects.Burst in WorldEffects.Burst.values():
		assert_eq(effects.burst_count(kind), 0)


func test_clear_stops_everything() -> void:
	effects.play(_response(InteractionResponse.TREE_SHAKE, 1))
	effects.play(_response(InteractionResponse.RIPPLE))
	effects.clear()
	assert_eq(effects.active_impulse_count(), 0)
	assert_eq(effects.active_ring_count(), 0)
	var origins: PackedFloat32Array = material.get_shader_parameter(&"impulse_origin")
	assert_near(origins[3], 0.0, 0.0)
	assert_false((effects.get_node("Leaves0") as CPUParticles3D).emitting)


func test_dust_takes_the_colour_of_the_ground() -> void:
	var grass := WorldEffects.dust_color(ChunkData.Terrain.GRASS)
	var sand := WorldEffects.dust_color(ChunkData.Terrain.SAND)
	assert_true(grass.g > grass.r, "greenish over grass")
	assert_true(sand.r > sand.b + 0.1, "warm over sand")
	assert_ne(grass, sand)
