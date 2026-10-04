class_name WorldEffects
extends Node3D
## Plays what the world does when it is touched (bible §23, §28.2): puffs of
## dust, ripples on water, a shaken tree shedding leaves, a wobbling rock.
## Purely visual — it reads InteractionResponses and never changes the world.
##
## Everything is pooled: a fixed number of particle emitters, rings and shake
## slots exist from the start, so touching the world never allocates.
##
## Shaking: props are merged into one mesh per chunk, so one prop cannot be
## moved as a node. Instead the prop shader gets a few "impulses" — vertices
## standing around a prop's base lean with it (see prop.gdshader).

enum Burst { DUST, LEAVES, SPARKS, MOTES }

## Shake slots in the prop shader (must match IMPULSE_COUNT in prop.gdshader).
const MAX_IMPULSES := 4
const RING_POOL := 6
## Emitters per burst kind: this many bursts of one kind can overlap.
const BURST_POOL := 4
const RING_SHADER := preload("res://assets/shaders/ring.gdshader")
## Rings float this far above the surface they spread on.
const RING_LIFT := 0.04
## Shakes are this much weaker when the player asked for reduced motion.
const REDUCED_MOTION_SCALE := 0.35

const WATER_RING := Color(0.93, 0.98, 1.0, 0.85)
## A drop of the player's rain on dry ground: a small dark splash (VS.5).
const DROP_RING := Color(0.35, 0.40, 0.50, 0.55)
const RUIN_RING := Color(0.62, 0.95, 0.90, 0.75)
const PERSON_RING := Color(1.0, 0.90, 0.62, 0.8)
## The warm motes a touched person gives off (VS.5).
const PERSON_MOTE := Color(1.0, 0.86, 0.52)
## What came down this heavily (LooseObject.give below it) sends a ring of dust out.
const HEAVY_GIVE := 0.5
## Key in `played` for the first touch of anyone, ever.
const FIRST_TOUCH := &"first_touch"
const RUIN_MOTE := Color(0.70, 1.0, 0.92)
const SPLASH := Color(0.90, 0.96, 1.0)
const SPARK := Color(1.0, 0.62, 0.18)
const DUST_BASE := Color(0.90, 0.86, 0.78)
## Key in `played` for landings (which are not InteractionResponses).
const LANDING := &"landing"
## Falling leaves are lighter than the canopy so they show against it.
const LEAF_FALL := Color(0.66, 0.84, 0.38)

## How each prop reacts: lean at the top (tiles), lift (tiles), oscillations
## per second, seconds, and the shaken radius as a multiple of the body radius.
const SHAKES := {
	InteractionResponse.TREE_SHAKE: {"lean": 0.16, "lift": 0.0, "hz": 3.0, "seconds": 1.5, "reach": 1.5},
	InteractionResponse.BUSH_RUSTLE: {"lean": 0.07, "lift": 0.0, "hz": 5.0, "seconds": 0.8, "reach": 1.4},
	InteractionResponse.ROCK_WOBBLE: {"lean": 0.03, "lift": 0.05, "hz": 7.0, "seconds": 0.5, "reach": 1.3},
	InteractionResponse.BUILDING_KNOCK: {"lean": 0.022, "lift": 0.0, "hz": 11.0, "seconds": 0.4, "reach": 1.5},
	InteractionResponse.FIRE_FLARE: {"lean": 0.04, "lift": 0.0, "hz": 8.0, "seconds": 0.5, "reach": 1.3},
	InteractionResponse.RUIN_HUM: {"lean": 0.010, "lift": 0.0, "hz": 14.0, "seconds": 1.4, "reach": 1.5},
	InteractionResponse.LOG_KNOCK: {"lean": 0.02, "lift": 0.0, "hz": 10.0, "seconds": 0.35, "reach": 1.3},
	InteractionResponse.NUDGE: {"lean": 0.03, "lift": 0.04, "hz": 8.0, "seconds": 0.4, "reach": 1.4},
}


class Impulse:
	extends RefCounted
	var entity_id := 0
	var origin := Vector3.ZERO
	var radius := 0.0
	var height := 1.0
	var direction := Vector2.RIGHT
	var lean := 0.0
	var lift := 0.0
	var hz := 1.0
	var seconds := 1.0
	var age := 0.0

	func is_active() -> bool:
		return radius > 0.0

	## Displacement now: x/z = lean at the top, y = lift.
	func offset() -> Vector3:
		if not is_active():
			return Vector3.ZERO
		var envelope := 1.0 - clampf(age / seconds, 0.0, 1.0)
		envelope *= envelope
		var swing := sin(TAU * hz * age) * lean * envelope
		var hop := absf(sin(PI * hz * age)) * lift * envelope
		return Vector3(direction.x * swing, hop, direction.y * swing)


class Ring:
	extends RefCounted
	var node: MeshInstance3D
	var material: ShaderMaterial
	var seconds := 1.0
	var age := 0.0
	var active := false


var reduced_motion := false
## How many effects of each kind were played (debug overlay, tests).
var played: Dictionary = {} # effect id -> count

var _prop_material: ShaderMaterial
var _impulses: Array[Impulse] = []
var _rings: Array[Ring] = []
var _next_ring := 0
var _bursts: Dictionary = {} # Burst -> Array[CPUParticles3D]
var _next_burst: Dictionary = {} # Burst -> index
var _last_burst_position: Dictionary = {} # Burst -> Vector3
var _burst_counts: Dictionary = {} # Burst -> count


func _init() -> void:
	for i in MAX_IMPULSES:
		_impulses.append(Impulse.new())
	_build_rings()
	for kind: Burst in Burst.values():
		var pool: Array[CPUParticles3D] = []
		for i in BURST_POOL:
			var emitter := _make_emitter(kind)
			emitter.name = "%s%d" % [Burst.keys()[kind].capitalize(), i]
			add_child(emitter)
			pool.append(emitter)
		_bursts[kind] = pool
		_next_burst[kind] = 0
		_burst_counts[kind] = 0


## `prop_material`: the shared prop material that receives the shake impulses.
func setup(prop_material: ShaderMaterial) -> void:
	_prop_material = prop_material
	_push_impulses()


## Stops everything (a different world is about to be shown).
func clear() -> void:
	for impulse in _impulses:
		impulse.radius = 0.0
		impulse.entity_id = 0
	for ring in _rings:
		ring.active = false
		ring.node.visible = false
	for pool: Array in _bursts.values():
		for emitter: CPUParticles3D in pool:
			emitter.emitting = false
	_push_impulses()


## Plays the visual answer to a touch. Hook for InteractionManager.responded.
func play(response: InteractionResponse) -> void:
	if response == null:
		return
	played[response.effect] = int(played.get(response.effect, 0)) + 1
	var at := response.position
	var height := response.body.x
	match response.effect:
		InteractionResponse.DUST:
			burst(Burst.DUST, at + Vector3(0.0, 0.05, 0.0), dust_color(response.terrain))
		InteractionResponse.RIPPLE:
			ring(at, 0.95, 1.0, WATER_RING)
			burst(Burst.DUST, at + Vector3(0.0, 0.05, 0.0), SPLASH)
		InteractionResponse.TREE_SHAKE:
			_shake(response)
			burst(Burst.LEAVES, at + Vector3(0.0, height * 0.68, 0.0), LEAF_FALL)
		InteractionResponse.BUSH_RUSTLE:
			_shake(response)
			burst(Burst.LEAVES, at + Vector3(0.0, height * 0.6, 0.0), LEAF_FALL)
		InteractionResponse.ROCK_WOBBLE:
			_shake(response)
			burst(Burst.DUST, at + Vector3(0.0, 0.04, 0.0), dust_color(ChunkData.Terrain.ROCK))
		InteractionResponse.BUILDING_KNOCK:
			_shake(response)
			# A little thatch dust drops from the eaves.
			burst(Burst.DUST, at + Vector3(0.0, height * 0.45, 0.0), PropMeshLibrary.THATCH.lerp(DUST_BASE, 0.4))
		InteractionResponse.FIRE_FLARE:
			_shake(response)
			burst(Burst.SPARKS, at + Vector3(0.0, 0.2, 0.0), SPARK)
		InteractionResponse.LOG_KNOCK, InteractionResponse.NUDGE:
			_shake(response)
		InteractionResponse.TREE_UPROOT:
			# The tree is gone at once; what is seen is its leaves coming down
			# and the earth it was torn from.
			burst(Burst.LEAVES, at + Vector3(0.0, height * 0.7, 0.0), LEAF_FALL)
			burst(Burst.LEAVES, at + Vector3(0.0, height * 0.4, 0.0), LEAF_FALL)
			burst(Burst.DUST, at + Vector3(0.0, 0.08, 0.0), dust_color(ChunkData.Terrain.DIRT))
		InteractionResponse.PERSON_TOUCH:
			# The touch itself, made visible; what the person makes of it is theirs.
			ring(at, 0.55, 0.7, PERSON_RING)
			burst(Burst.MOTES, at + Vector3(0.0, maxf(height, 0.4) * 0.6, 0.0), PERSON_MOTE)
		InteractionResponse.RUIN_HUM:
			_shake(response)
			ring(at, 1.5, 1.6, RUIN_RING)
			burst(Burst.MOTES, at + Vector3(0.0, 0.25, 0.0), RUIN_MOTE)


## Something came down at `at`: dust from the ground it hit, or a splash and
## ripples if it fell into water. `size` is the radius of what landed; `give`
## how light it is (LooseObject.give): what is heavy sends dust out in a ring.
func play_landing(at: Vector3, terrain: int, on_water: bool, size: float = 0.25, give: float = 1.0) -> void:
	played[LANDING] = int(played.get(LANDING, 0)) + 1
	var heavy := give < HEAVY_GIVE
	if on_water:
		ring(at, 0.6 + size * 1.5 + (0.6 if heavy else 0.0), 0.9, WATER_RING)
		burst(Burst.DUST, at + Vector3(0.0, 0.05, 0.0), SPLASH)
	else:
		burst(Burst.DUST, at + Vector3(0.0, 0.05, 0.0), dust_color(terrain))
		if heavy:
			var dust := dust_color(terrain)
			ring(at, 1.0 + size * 2.0, 0.6, Color(dust, 0.75))
			burst(Burst.DUST, at + Vector3(0.0, 0.12, 0.0), dust)


## The first time the player ever touches anyone: more of it (VS.5).
func play_first_touch(at: Vector3, height: float) -> void:
	played[FIRST_TOUCH] = int(played.get(FIRST_TOUCH, 0)) + 1
	ring(at, 1.4, 1.3, PERSON_RING)
	burst(Burst.MOTES, at + Vector3(0.0, maxf(height, 0.4) * 0.9, 0.0), PERSON_MOTE)


## Advances shakes and rings. Called every frame; tests call it directly.
func advance(delta: float) -> void:
	var shaking := false
	for impulse in _impulses:
		if not impulse.is_active():
			continue
		shaking = true
		impulse.age += delta
		if impulse.age >= impulse.seconds:
			impulse.radius = 0.0
			impulse.entity_id = 0
	if shaking:
		_push_impulses()
	for r in _rings:
		if not r.active:
			continue
		r.age += delta
		if r.age >= r.seconds:
			r.active = false
			r.node.visible = false
		else:
			r.material.set_shader_parameter(&"progress", r.age / r.seconds)


func _process(delta: float) -> void:
	advance(delta)


# --- pieces (also usable directly) ----------------------------------------------------

## A ring spreading to `radius` tiles over `seconds` on the surface at `center`.
func ring(center: Vector3, radius: float, seconds: float, color: Color) -> void:
	var r := _rings[_next_ring]
	_next_ring = (_next_ring + 1) % _rings.size()
	r.age = 0.0
	r.seconds = maxf(seconds, 0.05)
	r.active = true
	r.node.position = center + Vector3(0.0, RING_LIFT, 0.0)
	r.node.scale = Vector3(radius, 1.0, radius)
	r.material.set_shader_parameter(&"ring_color", color)
	r.material.set_shader_parameter(&"progress", 0.0)
	r.node.visible = true


## One burst of particles of `kind` at `at`, tinted `color`.
func burst(kind: Burst, at: Vector3, color: Color) -> void:
	var pool: Array = _bursts[kind]
	var index: int = _next_burst[kind]
	_next_burst[kind] = (index + 1) % pool.size()
	var emitter: CPUParticles3D = pool[index]
	# Move first, then start: particles are born where the emitter is.
	emitter.emitting = false
	emitter.position = at
	emitter.color = color
	emitter.restart()
	emitter.emitting = true
	_last_burst_position[kind] = at
	_burst_counts[kind] = int(_burst_counts[kind]) + 1


## Dust takes the colour of the ground it rises from.
static func dust_color(terrain: int) -> Color:
	return Config.terrain_palette.top(terrain).lerp(DUST_BASE, 0.45)


# --- queries (debug, tests) ------------------------------------------------------------

func active_impulse_count() -> int:
	var count := 0
	for impulse in _impulses:
		if impulse.is_active():
			count += 1
	return count


## The shake of an entity right now (x/z lean, y lift); zero if it is at rest.
func impulse_offset(entity_id: int) -> Vector3:
	for impulse in _impulses:
		if impulse.is_active() and impulse.entity_id == entity_id:
			return impulse.offset()
	return Vector3.ZERO


func is_shaking(entity_id: int) -> bool:
	for impulse in _impulses:
		if impulse.is_active() and impulse.entity_id == entity_id:
			return true
	return false


func active_ring_count() -> int:
	var count := 0
	for r in _rings:
		if r.active:
			count += 1
	return count


func burst_count(kind: Burst) -> int:
	return _burst_counts[kind]


## Where the latest burst of `kind` was played (Vector3.INF if never).
func last_burst_position(kind: Burst) -> Vector3:
	return _last_burst_position.get(kind, Vector3.INF)


# --- internals --------------------------------------------------------------------------

func _shake(response: InteractionResponse) -> void:
	var spec: Dictionary = SHAKES.get(response.effect, {})
	if spec.is_empty() or response.body.x <= 0.0:
		return
	var slot := _slot_for(response.entity_id)
	var angle := randf() * TAU # which way it leans first is only for looks
	var motion := (REDUCED_MOTION_SCALE if reduced_motion else 1.0) * response.strength
	slot.entity_id = response.entity_id
	slot.origin = response.position
	slot.radius = response.body.y * float(spec["reach"])
	slot.height = response.body.x
	slot.direction = Vector2(cos(angle), sin(angle))
	slot.lean = float(spec["lean"]) * motion
	slot.lift = float(spec["lift"]) * motion
	slot.hz = float(spec["hz"])
	slot.seconds = float(spec["seconds"])
	slot.age = 0.0
	_push_impulses()


## The slot already shaking this entity, else a free one, else the one closest
## to finishing.
func _slot_for(entity_id: int) -> Impulse:
	var best: Impulse = null
	var best_left := INF
	for impulse in _impulses:
		if impulse.is_active() and impulse.entity_id == entity_id:
			return impulse
	for impulse in _impulses:
		if not impulse.is_active():
			return impulse
		var left := 1.0 - impulse.age / impulse.seconds
		if left < best_left:
			best_left = left
			best = impulse
	return best


func _push_impulses() -> void:
	if _prop_material == null:
		return
	var origins := PackedFloat32Array()
	var offsets := PackedFloat32Array()
	for impulse in _impulses:
		var o := impulse.offset()
		origins.append_array([impulse.origin.x, impulse.origin.y, impulse.origin.z, impulse.radius])
		offsets.append_array([o.x, o.z, o.y, 1.0 / maxf(impulse.height, 0.01)])
	_prop_material.set_shader_parameter(&"impulse_origin", origins)
	_prop_material.set_shader_parameter(&"impulse_offset", offsets)


func _build_rings() -> void:
	var quad := PlaneMesh.new()
	quad.size = Vector2(2.0, 2.0) # radius 1, scaled per ring
	for i in RING_POOL:
		var r := Ring.new()
		r.material = ShaderMaterial.new()
		r.material.shader = RING_SHADER
		# Drawn after the water it spreads on (both are transparent).
		r.material.render_priority = 1
		r.node = MeshInstance3D.new()
		r.node.name = "Ring%d" % i
		r.node.mesh = quad
		r.node.material_override = r.material
		r.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		r.node.visible = false
		add_child(r.node)
		_rings.append(r)


static func _particle_material(soft: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true # tints are authored in sRGB
	material.render_priority = 2
	if soft:
		material.albedo_texture = AmbientLife.soft_dot()
	return material


static func _fade(points: Array) -> Gradient:
	# points: [offset, alpha] pairs; colour stays white (the emitter tints it).
	var gradient := Gradient.new()
	gradient.set_offset(0, points[0][0])
	gradient.set_color(0, Color(1, 1, 1, points[0][1]))
	gradient.set_offset(1, points[points.size() - 1][0])
	gradient.set_color(1, Color(1, 1, 1, points[points.size() - 1][1]))
	for i in range(1, points.size() - 1):
		gradient.add_point(points[i][0], Color(1, 1, 1, points[i][1]))
	return gradient


static func _grow(from: float, to: float) -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, from))
	curve.add_point(Vector2(1.0, to))
	return curve


static func _make_emitter(kind: Burst) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	p.one_shot = true
	p.emitting = false
	# Everything at once. (Below 1, particles still waiting to be born show up
	# as dark specks at the emitter.)
	p.explosiveness = 1.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match kind:
		Burst.DUST:
			quad.size = Vector2(0.24, 0.24)
			quad.material = _particle_material(true)
			p.amount = 8
			p.lifetime = 0.6
			p.direction = Vector3.UP
			p.spread = 55.0
			p.initial_velocity_min = 0.45
			p.initial_velocity_max = 1.0
			p.gravity = Vector3(0.0, -1.6, 0.0)
			p.scale_amount_curve = _grow(0.5, 1.5)
			p.color_ramp = _fade([[0.0, 0.75], [1.0, 0.0]])
		Burst.LEAVES:
			quad.size = Vector2(0.09, 0.09)
			quad.material = _particle_material(false)
			p.amount = 9
			p.lifetime = 1.4
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 0.3
			p.direction = Vector3(0.0, -1.0, 0.0)
			p.spread = 180.0
			p.initial_velocity_min = 0.15
			p.initial_velocity_max = 0.5
			p.gravity = Vector3(0.25, -1.1, 0.1) # drifts on the wind as it falls
			p.angle_min = 0.0
			p.angle_max = 360.0
			p.angular_velocity_min = -220.0
			p.angular_velocity_max = 220.0
			p.color_ramp = _fade([[0.0, 1.0], [0.75, 1.0], [1.0, 0.0]])
		Burst.SPARKS:
			quad.size = Vector2(0.07, 0.07)
			quad.material = _particle_material(true)
			p.amount = 10
			p.lifetime = 0.7
			p.direction = Vector3.UP
			p.spread = 26.0
			p.initial_velocity_min = 1.2
			p.initial_velocity_max = 2.2
			p.gravity = Vector3(0.0, -1.5, 0.0)
			p.scale_amount_curve = _grow(1.2, 0.3)
			p.color_ramp = _fade([[0.0, 1.0], [0.6, 0.9], [1.0, 0.0]])
		Burst.MOTES:
			quad.size = Vector2(0.09, 0.09)
			quad.material = _particle_material(true)
			p.amount = 6
			p.lifetime = 1.8
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 0.38
			p.direction = Vector3.UP
			p.spread = 18.0
			p.initial_velocity_min = 0.25
			p.initial_velocity_max = 0.5
			p.gravity = Vector3.ZERO
			p.color_ramp = _fade([[0.0, 0.0], [0.2, 0.9], [1.0, 0.0]])
	p.mesh = quad
	return p
