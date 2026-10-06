class_name LooseObjectSystem
extends Node
## Moves the loose objects that are not at rest (bible §10, §31.3). Lives in
## the WorldSession and works on its LooseObjectRegistry.
##
## A small integrator of its own rather than the physics engine: it knows the
## world is made of blocks, costs nothing for objects at rest, and behaves the
## same on every device. Fixed time step; only moving objects are stepped.
##
##  - In the air: gravity. On landing: a bounce (by kind), or rest.
##  - On the ground: friction slows it; a slope speeds a moving object up, so a
##    rock set rolling on a hillside tumbles down the steps to the bottom. An
##    object at rest stays at rest unless the slope is steep.
##  - Blocks: a higher neighbouring block is a wall (bounce back); a lower one
##    is a drop (fall off the edge). The box's walls keep everything inside.
##  - Things in the way: huts, the campfire, ruins, tree trunks and other loose
##    objects are circles; a moving object bounces off them, and a heavy one
##    knocks a light one away (their weights decide who moves how much).
##
## Objects in hand (HELD) are left alone and pass through everything.

## An object hit the ground at `impact_speed` (tiles/s). Bounces too gentle to
## hear are not reported.
signal landed(id: int, impact_speed: float)
## An object ran into a wall, a prop or another object at `speed`.
signal bumped(id: int, speed: float)
## An object came to rest.
signal settled(id: int)

## Simulation steps per second, and the most steps one frame may run.
const STEP_SECONDS := 1.0 / 60.0
const MAX_STEPS_PER_FRAME := 4
## Tiles per second squared. Stronger than life-size gravity would be at this
## scale, so drops feel quick and weighty rather than floaty.
const GRAVITY := 22.0
const MAX_SPEED := 14.0
## Landings slower than this do not bounce; slower than IMPACT_MIN are silent.
const BOUNCE_MIN := 1.2
const IMPACT_MIN := 1.5
## Share of the sideways speed kept through a landing: a thrown stone lands
## and soon stops, rather than sliding on across the field (the owner,
## 2026-10-06: small rocks slid much too far).
const LANDING_GRIP := 0.35
## Share of the speed kept when bouncing off a wall, a prop or another object.
const WALL_BOUNCE := 0.35
const BUMP_BOUNCE := 0.3
## Bumps slower than this are not reported.
const BUMP_MIN := 0.8
## An object on the ground cannot climb onto a block higher than this.
const CLIMB := 0.02
## Downhill pull per unit of slope (slope = height lost per tile).
const SLOPE_ACCEL := 14.0
## A resting object only starts to slide if the downhill pull exceeds this:
## with the usual 0.4 height step, a drop of one level holds, two do not.
const STATIC_HOLD := 6.5
## Slower than this on level ground, an object comes to rest.
const REST_SPEED := 0.15
## Water slows things down: speed lost per second, and the fastest sinking.
const WATER_DRAG := 4.0
const SINK_SPEED := 2.2
const GROUND_EPS := 0.0005
## How quickly something afloat takes up the speed of the water (tiles/s per second).
const FLOAT_GRIP := 2.5
## Carried by a current, an object that moved less than this far in this many
## steps has run aground and comes to rest.
const AGROUND_STEPS := 45
const AGROUND_DISTANCE := 0.06
## Kinds of props a loose object can run into.
const PROP_KINDS := SpatialIndex.KIND_BUILDING | SpatialIndex.KIND_MYSTERY | SpatialIndex.KIND_RESOURCE_NODE

var _world: WorldData
var _registry: LooseObjectRegistry
var _props: PropRegistry
## Optional: Callable(tile: Vector2i) -> Vector2, the water's current there.
var _current: Callable
var _moving: Dictionary = {} # id -> true
## For things carried by a current: where each was a while ago, to notice when
## it has run aground and may rest. id -> [position, steps since]
var _anchors: Dictionary = {}
var _time_bank := 0.0
## Time the last frame's stepping took, microseconds (debug overlay).
var last_step_usec := 0


## The world is paused: nothing falls, rolls or drifts until it goes on.
var frozen := false


func bind(world: WorldData, registry: LooseObjectRegistry, props: PropRegistry = null,
		current: Callable = Callable()) -> void:
	_world = world
	_registry = registry
	_props = props
	_current = current
	_moving.clear()
	_anchors.clear()
	# What was saved while afloat and moving was saved lying on the bed:
	# let everything that floats find the surface again.
	on_water_changed()
	_time_bank = 0.0


# --- what others ask for ----------------------------------------------------------------

## Takes an object in hand: it stops moving and stays where it is put.
func hold(id: int) -> bool:
	var object := _object(id)
	if object == null:
		return false
	_moving.erase(id)
	object.state = LooseObject.State.HELD
	object.velocity = Vector3.ZERO
	return true


## Lets an object go, optionally with a velocity (a throw): it falls, bounces,
## rolls and comes to rest.
func drop(id: int, velocity: Vector3 = Vector3.ZERO) -> bool:
	var object := _object(id)
	if object == null or not _is_finite(velocity):
		return false
	object.state = LooseObject.State.FALLING
	object.velocity = velocity.limit_length(MAX_SPEED)
	_moving[id] = true
	return true


## Sets a resting (or moving) object in motion with an added velocity.
func push(id: int, velocity: Vector3) -> bool:
	var object := _object(id)
	if object == null or object.state == LooseObject.State.HELD or not _is_finite(velocity):
		return false
	object.velocity = (object.velocity + velocity).limit_length(MAX_SPEED)
	if object.state == LooseObject.State.RESTING:
		object.state = LooseObject.State.SLIDING
	_moving[id] = true
	return true


## The water changed on `tiles`: what floats rises and falls with it, and
## what lay on a tile that ran dry settles on the ground.
func on_water_changed(_tiles: Array[Vector2i] = []) -> void:
	if _registry == null or _world == null:
		return
	for object in _registry.all_objects():
		if object.state != LooseObject.State.RESTING or not object.floats():
			continue
		if absf(object.height_offset - _float_lift(object, object.tile())) > 0.004:
			object.state = LooseObject.State.FALLING
			_moving[object.id] = true


func is_moving(id: int) -> bool:
	return _moving.has(id)


## Kept for callers that only care about objects in the air or rolling.
func is_falling(id: int) -> bool:
	return _moving.has(id)


func moving_count() -> int:
	return _moving.size()


## Height above the ground at which an object rests on its tile: on the ground,
## or on the water if it floats.
func rest_height(object: LooseObject) -> float:
	return _float_lift(object, object.tile())


## Advances time. Called every frame; tests call it directly. Time is consumed
## in fixed steps, so the motion is the same whatever the frame rate.
func step(delta: float) -> void:
	if _moving.is_empty() or _registry == null or _world == null:
		_time_bank = 0.0
		last_step_usec = 0
		return
	var started := Time.get_ticks_usec()
	_time_bank = minf(_time_bank + delta, STEP_SECONDS * MAX_STEPS_PER_FRAME)
	while _time_bank >= STEP_SECONDS - 0.000001:
		_time_bank -= STEP_SECONDS
		_step_all(STEP_SECONDS)
		if _moving.is_empty():
			_time_bank = 0.0
			break
	last_step_usec = Time.get_ticks_usec() - started


func _process(delta: float) -> void:
	if not frozen:
		step(delta)


# --- one step ---------------------------------------------------------------------------

func _step_all(dt: float) -> void:
	var ids: Array = _moving.keys()
	ids.sort() # the same order every time
	for id: int in ids:
		var object := _registry.get_object(id)
		if object == null or object.state == LooseObject.State.HELD or object.state == LooseObject.State.RESTING:
			_moving.erase(id) # removed, picked up, or put to rest by someone else
			continue
		_advance(object, dt)


func _advance(object: LooseObject, dt: float) -> void:
	var step_height := _world.height_step
	var tile := object.tile()
	var terrain_y := _world.get_height(tile) * step_height
	var support := terrain_y + _float_lift(object, tile)
	var y := terrain_y + object.height_offset
	var sideways := Vector2(object.velocity.x, object.velocity.z)
	var vy := object.velocity.y
	var spec := object.spec()
	var grounded := y <= support + GROUND_EPS and vy <= 0.0

	if grounded:
		y = support
		vy = 0.0
		if support > terrain_y + GROUND_EPS and _current.is_valid():
			# Afloat: the water carries it along.
			var stream: Vector2 = _current.call(tile)
			sideways = sideways.move_toward(stream, FLOAT_GRIP * dt)
		else:
			var slope_pull := _downhill(tile) * SLOPE_ACCEL * float(spec.get("roll", 1.0))
			# A slope keeps a moving object moving; from rest only a steep one starts it.
			if sideways.length() > REST_SPEED or slope_pull.length() > STATIC_HOLD:
				sideways += slope_pull * dt
			sideways = sideways.move_toward(Vector2.ZERO, float(spec.get("friction", 4.0)) * dt)
	else:
		vy -= GRAVITY * dt

	var depth := _world.get_water(tile)
	if depth > WaterMesher.MIN_DEPTH and y < terrain_y + depth - GROUND_EPS:
		# Under water: everything is slower, and sinking is gentle.
		sideways *= maxf(1.0 - WATER_DRAG * dt, 0.0)
		vy = maxf(vy, -SINK_SPEED)

	sideways = sideways.limit_length(MAX_SPEED)
	var position := object.position
	var bump := 0.0
	var inner := Rect2(_world.bounds).grow(-minf(object.radius(), 0.45))
	for axis in 2:
		var travel: float = sideways[axis] * dt
		if travel == 0.0:
			continue
		var next := position
		next[axis] += travel
		# The walls of the box.
		var low: float = inner.position[axis]
		var high: float = inner.end[axis]
		if next[axis] < low or next[axis] > high:
			next[axis] = clampf(next[axis], low, high)
			bump = maxf(bump, absf(sideways[axis]))
			sideways[axis] = -sideways[axis] * WALL_BOUNCE
		var next_tile := WorldCoords.world2d_to_tile(next)
		if next_tile != tile:
			var next_terrain := _world.get_height(next_tile) * step_height
			var next_support := next_terrain + _float_lift(object, next_tile)
			if next_support > y + CLIMB:
				# A higher block: a wall. Bounce back, stay on this side.
				bump = maxf(bump, absf(sideways[axis]))
				sideways[axis] = -sideways[axis] * WALL_BOUNCE
				continue
			tile = next_tile # level ground, or a drop (it is now above its support)
			terrain_y = next_terrain
			support = next_support
		position = next

	y += vy * dt
	var impact := 0.0
	if y <= support:
		y = support
		if vy < 0.0:
			impact = -vy
			if impact >= BOUNCE_MIN:
				vy = impact * float(spec.get("bounce", 0.2))
				sideways *= LANDING_GRIP
			else:
				vy = 0.0

	object.velocity = Vector3(sideways.x, vy, sideways.y)
	object.state = LooseObject.State.FALLING if y > support + GROUND_EPS or vy > 0.0 else LooseObject.State.SLIDING
	_registry.move(object.id, position, y - terrain_y)

	bump = maxf(bump, _collide(object))

	if impact >= IMPACT_MIN:
		landed.emit(object.id, impact)
	if bump >= BUMP_MIN:
		bumped.emit(object.id, bump)

	# Come to rest: on the ground, nearly still, and not on a slope too steep to
	# hold. Something carried by a current rests once it has run aground.
	sideways = Vector2(object.velocity.x, object.velocity.z)
	var may_rest := false
	if object.state == LooseObject.State.SLIDING and object.velocity.y == 0.0:
		# (Asked where it ended up this step, not where it started.)
		var now_tile := object.tile()
		var afloat := _float_lift(object, now_tile) > GROUND_EPS and _current.is_valid()
		if afloat and (_current.call(now_tile) as Vector2).length() > REST_SPEED:
			may_rest = _has_run_aground(object)
		else:
			_anchors.erase(object.id)
			may_rest = sideways.length() < REST_SPEED \
				and (_downhill(object.tile()) * SLOPE_ACCEL * float(spec.get("roll", 1.0))).length() <= STATIC_HOLD
	if may_rest:
		object.velocity = Vector3.ZERO
		object.state = LooseObject.State.RESTING
		_moving.erase(object.id)
		_anchors.erase(object.id)
		settled.emit(object.id)


## True once an object in a current has hardly moved for a while (it is up
## against a bank, the wall of the box or something in the water).
func _has_run_aground(object: LooseObject) -> bool:
	var anchor: Array = _anchors.get(object.id, [])
	if anchor.is_empty():
		_anchors[object.id] = [object.position, 0]
		return false
	anchor[1] = int(anchor[1]) + 1
	if int(anchor[1]) < AGROUND_STEPS:
		return false
	var held := object.position.distance_to(anchor[0]) < AGROUND_DISTANCE
	_anchors[object.id] = [object.position, 0]
	return held


# --- things in the way ------------------------------------------------------------------

## Everything near the object that it can run into: other loose objects and
## the solid parts of props. Returns the speed of the hardest hit.
func _collide(object: LooseObject) -> float:
	var index := _registry.spatial_index
	if index == null:
		return 0.0
	var hardest := 0.0
	var shared := _props != null and _props.spatial_index == index
	var mask := SpatialIndex.KIND_LOOSE_OBJECT
	if shared:
		mask |= PROP_KINDS # one search finds both
	for id in index.query_radius(object.position, object.radius() + 0.9, mask):
		if id == object.id:
			continue
		var other := _registry.get_object(id)
		if other != null:
			hardest = maxf(hardest, _collide_with_object(object, other))
		elif shared:
			hardest = maxf(hardest, _collide_with_prop(object, _props.get_prop(id)))
	if _props != null and not shared and _props.spatial_index != null:
		for id in _props.spatial_index.query_radius(object.position, object.radius() + 0.9, PROP_KINDS):
			hardest = maxf(hardest, _collide_with_prop(object, _props.get_prop(id)))
	return hardest


func _collide_with_prop(object: LooseObject, prop: PropData) -> float:
	if prop == null:
		return 0.0
	var reach := prop.collision_radius()
	if reach <= 0.0:
		return 0.0
	# Flying over it is fine.
	var prop_top := _world.get_height(prop.tile) * _world.height_step + prop.pick_shape().x
	if _base_y(object) >= prop_top:
		return 0.0
	return _bounce_off(object, prop.position2d(), reach)


## Circle against a fixed circle: move out, reflect the approach.
func _bounce_off(object: LooseObject, center: Vector2, reach: float) -> float:
	var away := object.position - center
	var distance := away.length()
	var gap := object.radius() + reach - distance
	if gap <= 0.0:
		return 0.0
	var normal := away / distance if distance > 0.0001 else Vector2.RIGHT
	_shift(object, normal * gap)
	var sideways := Vector2(object.velocity.x, object.velocity.z)
	var approach := sideways.dot(normal)
	if approach >= 0.0:
		return 0.0
	sideways -= normal * approach * (1.0 + BUMP_BOUNCE)
	object.velocity = Vector3(sideways.x, object.velocity.y, sideways.y)
	return -approach


## Circle against another loose object: separate them and share the momentum
## by weight, waking the other if it was at rest.
func _collide_with_object(object: LooseObject, other: LooseObject) -> float:
	if other.state == LooseObject.State.HELD:
		return 0.0
	var away := object.position - other.position
	var distance := away.length()
	var gap := object.radius() + other.radius() - distance
	if gap <= 0.0:
		return 0.0
	# One passing over the other does not touch it.
	if absf(_base_y(object) - _base_y(other)) >= maxf(object.height(), other.height()):
		return 0.0
	var normal := away / distance if distance > 0.0001 else Vector2.RIGHT
	var mass := object.mass()
	var other_mass := other.mass()
	# Apart, the lighter one giving way more. What one cannot move (a wall
	# behind it), the other makes up for.
	var moved := _shift(other, -normal * gap * (mass / (mass + other_mass)))
	_shift(object, normal * (gap - moved))
	var relative := Vector2(object.velocity.x - other.velocity.x, object.velocity.z - other.velocity.z)
	var approach := relative.dot(normal)
	if approach >= 0.0:
		return 0.0
	var impulse := -(1.0 + BUMP_BOUNCE) * approach / (1.0 / mass + 1.0 / other_mass)
	var push_self := normal * (impulse / mass)
	var push_other := -normal * (impulse / other_mass)
	object.velocity += Vector3(push_self.x, 0.0, push_self.y)
	other.velocity = (other.velocity + Vector3(push_other.x, 0.0, push_other.y)).limit_length(MAX_SPEED)
	if other.state == LooseObject.State.RESTING:
		other.state = LooseObject.State.SLIDING
	_moving[other.id] = true
	return -approach


## Moves an object sideways by `delta` if the ground allows it (never into a
## higher block or out of the box). Returns how far it actually moved.
func _shift(object: LooseObject, delta: Vector2) -> float:
	if delta == Vector2.ZERO:
		return 0.0
	var inner := Rect2(_world.bounds).grow(-minf(object.radius(), 0.45))
	var target := object.position + delta
	target = Vector2(clampf(target.x, inner.position.x, inner.end.x), clampf(target.y, inner.position.y, inner.end.y))
	var tile := object.tile()
	var target_tile := WorldCoords.world2d_to_tile(target)
	var terrain_y := _world.get_height(tile) * _world.height_step
	var y := terrain_y + object.height_offset
	if target_tile != tile:
		var target_terrain := _world.get_height(target_tile) * _world.height_step
		if target_terrain + _float_lift(object, target_tile) > y + CLIMB:
			return 0.0
		terrain_y = target_terrain
	var moved := object.position.distance_to(target)
	var above := maxf(y - terrain_y, 0.0)
	_registry.move(object.id, target, above)
	if above > _float_lift(object, target_tile) + GROUND_EPS and object.state == LooseObject.State.RESTING:
		# Pushed off an edge while at rest: it has to fall.
		object.state = LooseObject.State.FALLING
		_moving[object.id] = true
	return moved


# --- helpers ----------------------------------------------------------------------------

## Which way is downhill from `tile`, and how steeply (height lost per tile).
## Only lower neighbours count: a higher block next door is a wall, not a
## slope, and must not push things away before they touch it.
func _downhill(tile: Vector2i) -> Vector2:
	var here := _world.get_height(tile)
	var east := maxi(here - _height_or(tile + Vector2i(1, 0), here), 0)
	var west := maxi(here - _height_or(tile + Vector2i(-1, 0), here), 0)
	var south := maxi(here - _height_or(tile + Vector2i(0, 1), here), 0)
	var north := maxi(here - _height_or(tile + Vector2i(0, -1), here), 0)
	return Vector2(east - west, south - north) * _world.height_step


func _height_or(tile: Vector2i, fallback: int) -> int:
	return _world.get_height(tile) if _world.is_in_bounds(tile) else fallback


## How far above the ground of `tile` the object is held up by water.
func _float_lift(object: LooseObject, tile: Vector2i) -> float:
	if _world == null or not object.floats():
		return 0.0
	var depth := _world.get_water(tile)
	return depth if depth > WaterMesher.MIN_DEPTH else 0.0


func _base_y(object: LooseObject) -> float:
	return _world.get_height(object.tile()) * _world.height_step + object.height_offset


func _object(id: int) -> LooseObject:
	return _registry.get_object(id) if _registry != null else null


static func _is_finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)
