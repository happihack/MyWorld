class_name InteractionManager
extends Node
## Decides what a player touch means (bible §10, §14.6, §23). Lives in the
## WorldSession: it knows the world, not the screen. The view layer picks what
## is under the finger and hands the result here; this node answers with an
## InteractionResponse and announces it through `responded`.
##
## v0 (M2.3): touches only produce feedback. This is the seed of the single
## choke point for player interventions — world changes, the player history
## and stimuli for inhabitants are added here in M3.6.

signal responded(response: InteractionResponse)

## Things the player can choose to do with a target (context menu).
const ACTION_INSPECT := &"inspect"
const ACTION_TOUCH := &"touch"
const ACTION_FOCUS := &"focus"
const ACTION_REMOVE := &"remove"

## The first shake of a tree only rustles it; each further shake drops one of
## what it bears with this chance.
const SHAKE_DROP_CHANCE := 0.6
## A touch on water pushes floating things within this many tiles, the
## nearest by this speed (tiles/s).
const RIPPLE_REACH := 1.6
const RIPPLE_PUSH := 1.6
## Random stream for what touches bring about (which shake drops a fruit).
const RNG_STREAM := &"interaction"

const _PROP_EFFECTS := {
	PropData.Kind.TREE: InteractionResponse.TREE_SHAKE,
	PropData.Kind.BUSH: InteractionResponse.BUSH_RUSTLE,
	PropData.Kind.ROCK: InteractionResponse.ROCK_WOBBLE,
	PropData.Kind.HUT: InteractionResponse.BUILDING_KNOCK,
	PropData.Kind.CAMPFIRE: InteractionResponse.FIRE_FLARE,
	PropData.Kind.RUIN: InteractionResponse.RUIN_HUM,
}

## Touches since this world was opened (not saved yet; player history is M3.6).
var interaction_count := 0

var _world: WorldData
var _props: PropRegistry
var _loose: LooseObjectRegistry
var _motion: LooseObjectSystem
var _ids: IdAllocator
var _rng: RngStreams
var _shakes: Dictionary = {} # tree id -> shakes since the world was opened


## `motion`, `ids` and `rng` let touches bring new things into the world
## (fruit from a shaken tree); without them touches only produce feedback.
func bind(world: WorldData, props: PropRegistry, loose: LooseObjectRegistry = null,
		motion: LooseObjectSystem = null, ids: IdAllocator = null, rng: RngStreams = null) -> void:
	_world = world
	_props = props
	_loose = loose
	_motion = motion
	_ids = ids
	_rng = rng
	_shakes.clear()
	interaction_count = 0


## A tap on `target`. Returns the response, or null if nothing was touched.
func tap(target: Picker.Result) -> InteractionResponse:
	var response := _respond(target, InteractionResponse.Action.TAP, false)
	if response == null:
		return null
	if response.prop_kind == PropData.Kind.TREE:
		_shake_tree(response)
	elif response.effect == InteractionResponse.RIPPLE:
		_disturb_water(response)
	_announce(response)
	return response


## Uproots the tree at `target`: the tree is gone for good and its trunk is
## left lying as a log. Null if the target is not a tree.
func uproot(target: Picker.Result) -> InteractionResponse:
	var response := _respond(target, InteractionResponse.Action.TAP, false)
	if response == null or response.prop_kind != PropData.Kind.TREE or _props == null:
		return null
	var tree := _props.get_prop(response.entity_id)
	response.effect = InteractionResponse.TREE_UPROOT
	response.description = "TREE uprooted at %s" % tree.tile
	var size := tree.scale_percent
	_props.remove(tree.id)
	if can_spawn():
		var rng := _rng.stream(RNG_STREAM)
		var heading := rng.randf() * TAU
		var log := _spawn(LooseObject.Kind.LOG, Vector2(response.position.x, response.position.z), 0.35, size)
		log.yaw = heading
		_motion.drop(log.id, Vector3(cos(heading), 0.0, sin(heading)) * 0.9)
		response.dropped.append(log.id)
	_announce(response)
	return response


## True if touches can bring new loose objects into the world.
func can_spawn() -> bool:
	return _loose != null and _motion != null and _ids != null and _rng != null


## How often a tree has been shaken since the world was opened.
func shakes_of(tree_id: int) -> int:
	return int(_shakes.get(tree_id, 0))


## A long press: asks to inspect the target (the context panel arrives in M2.4).
func long_press(target: Picker.Result) -> InteractionResponse:
	var response := _respond(target, InteractionResponse.Action.LONG_PRESS, false)
	if response != null:
		response.effect = InteractionResponse.INSPECT
		_announce(response)
	return response


## Describes what a target is without touching it (double tap, UI).
func describe(target: Picker.Result) -> InteractionResponse:
	return _respond(target, InteractionResponse.Action.DOUBLE_TAP, false)


## What the player can do with a target right now, in menu order (bible §26.6
## lists more per target; an action appears here once it works). Empty for a miss.
func actions_for(target: Picker.Result) -> Array[StringName]:
	var actions: Array[StringName] = []
	if target == null or not target.is_hit() or _world == null:
		return actions
	actions.append(ACTION_INSPECT)
	actions.append(ACTION_TOUCH)
	if target.kind == Picker.Kind.ENTITY and _props != null:
		var prop := _props.get_prop(target.entity_id)
		if prop != null and prop.kind == PropData.Kind.TREE:
			actions.append(ACTION_REMOVE)
	actions.append(ACTION_FOCUS)
	return actions


## The facts about a target (the inspect card). Null for a miss. Looking does
## not touch the world: nothing is announced.
func inspect(target: Picker.Result) -> InspectReport:
	if target == null or not target.is_hit() or _world == null:
		return null
	var report := InspectReport.new()
	var prop: PropData = null
	var object: LooseObject = null
	if target.kind == Picker.Kind.ENTITY:
		prop = _props.get_prop(target.entity_id) if _props != null else null
		object = _loose.get_object(target.entity_id) if _loose != null and prop == null else null
	report.tile = target.tile
	if prop != null:
		report.tile = prop.tile
	elif object != null:
		report.tile = object.tile()
	var chunk := _world.chunk_at_tile(report.tile)
	if chunk == null:
		return null
	var i := _world.index_at_tile(report.tile)
	report.terrain = chunk.terrain[i]
	report.height_level = chunk.height[i]
	report.moisture = chunk.moisture[i]
	report.fertility = chunk.fertility[i]
	report.vegetation = chunk.vegetation[i]
	report.water_depth = chunk.water[i]
	if prop != null:
		report.subject = InspectReport.Subject.PROP
		report.entity_id = prop.id
		report.prop_kind = prop.kind
		report.prop_variant = prop.variant
		report.scale_percent = prop.scale_percent
		report.generated = prop.is_generated()
		if prop.kind == PropData.Kind.TREE:
			report.bears = prop.bears()
			report.bears_left = prop.bears_left()
	elif object != null:
		report.subject = InspectReport.Subject.LOOSE
		report.entity_id = object.id
		report.loose_kind = object.kind
		report.scale_percent = object.scale_percent
		report.generated = object.is_generated()
		report.mass = object.mass()
		report.moved_count = object.moved_count
		report.placed_by_player = object.placed_by_player
	elif target.kind == Picker.Kind.WATER:
		report.subject = InspectReport.Subject.WATER
	return report


func _respond(target: Picker.Result, action: InteractionResponse.Action, announce: bool = true) -> InteractionResponse:
	if target == null or not target.is_hit() or _world == null:
		return null
	var response := InteractionResponse.new()
	response.action = action
	response.tile = target.tile
	response.position = target.position
	response.terrain = _world.get_terrain(target.tile)

	var prop: PropData = null
	var object: LooseObject = null
	if target.kind == Picker.Kind.ENTITY:
		prop = _props.get_prop(target.entity_id) if _props != null else null
		object = _loose.get_object(target.entity_id) if _loose != null and prop == null else null

	if object != null:
		response.entity_id = object.id
		response.loose_kind = object.kind
		response.strength = object.give()
		response.body = object.pick_shape()
		response.tile = object.tile()
		response.terrain = _world.get_terrain(response.tile)
		response.position = object.world_position(_world)
		if object.is_stone():
			response.effect = InteractionResponse.ROCK_WOBBLE
		elif object.kind == LooseObject.Kind.LOG:
			response.effect = InteractionResponse.LOG_KNOCK
		else:
			response.effect = InteractionResponse.NUDGE
		response.description = "%s at %s" % [LooseObject.Kind.keys()[object.kind], response.tile]
	elif prop != null:
		var at := prop.position2d()
		response.entity_id = prop.id
		response.prop_kind = prop.kind
		response.prop_variant = prop.variant
		response.body = prop.pick_shape()
		response.tile = prop.tile
		response.position = Vector3(at.x, _world.get_height(prop.tile) * _world.height_step, at.y)
		response.effect = _PROP_EFFECTS.get(prop.kind, InteractionResponse.DUST)
		response.description = "%s at %s" % [PropData.Kind.keys()[prop.kind], prop.tile]
	elif target.kind == Picker.Kind.WATER:
		response.effect = InteractionResponse.RIPPLE
		# On the surface, even if the finger caught the side of the water.
		response.position.y = _world.get_height(target.tile) * _world.height_step + _world.get_water(target.tile)
		response.description = "WATER at %s  depth %.2f" % [target.tile, _world.get_water(target.tile)]
	else:
		# Plain ground — also where a picked entity has vanished in the meantime.
		response.effect = InteractionResponse.DUST
		response.description = "%s at %s  height %d" % [
			ChunkData.Terrain.keys()[response.terrain], target.tile, _world.get_height(target.tile)]

	response.touch_effect = response.effect
	if announce:
		_announce(response)
	return response


## A shaken tree may let go of what it bears: never on the first shake, then
## by chance, until nothing is left.
func _shake_tree(response: InteractionResponse) -> void:
	var tree := _props.get_prop(response.entity_id)
	if tree == null:
		return
	var shakes := shakes_of(tree.id) + 1
	_shakes[tree.id] = shakes
	if shakes < 2 or tree.bears_left() <= 0 or not can_spawn():
		return
	var rng := _rng.stream(RNG_STREAM)
	if rng.randf() >= SHAKE_DROP_CHANCE:
		return
	tree.taken += 1
	_props.touch(tree.id)
	# It lets go somewhere in the crown and falls a little outward.
	var body := tree.pick_shape()
	var angle := rng.randf() * TAU
	var outward := Vector2(cos(angle), sin(angle))
	var kind := LooseObject.Kind.SEED if tree.is_conifer() else LooseObject.Kind.FRUIT
	var at := tree.position2d() + outward * body.y * rng.randf_range(0.45, 0.85)
	var fruit := _spawn(kind, at, body.x * rng.randf_range(0.5, 0.75), 100 + rng.randi_range(0, 30))
	var speed := rng.randf_range(0.3, 1.1)
	_motion.drop(fruit.id, Vector3(outward.x * speed, 0.0, outward.y * speed))
	response.dropped.append(fruit.id)


## A touch on water pushes what floats nearby away from the finger.
func _disturb_water(response: InteractionResponse) -> void:
	if _loose == null or _motion == null or _loose.spatial_index == null:
		return
	var center := Vector2(response.position.x, response.position.z)
	for id in _loose.spatial_index.query_radius(center, RIPPLE_REACH, SpatialIndex.KIND_LOOSE_OBJECT):
		var object := _loose.get_object(id)
		if object == null or _motion.rest_height(object) <= 0.0:
			continue # not afloat
		var away := object.position - center
		var distance := away.length()
		var direction := away / distance if distance > 0.001 else Vector2.RIGHT
		var strength := RIPPLE_PUSH * (1.0 - distance / RIPPLE_REACH) * clampf(object.give(), 0.3, 1.5)
		_motion.push(id, Vector3(direction.x, 0.0, direction.y) * strength)


## A new loose object at `at`, `height` above the ground.
func _spawn(kind: LooseObject.Kind, at: Vector2, height: float, scale_percent: int) -> LooseObject:
	var object := LooseObject.new()
	object.id = _ids.next_id()
	object.kind = kind
	object.scale_percent = scale_percent
	# Inside the box, whatever the tree's crown overhangs.
	var inner := Rect2(_world.bounds).grow(-0.1)
	object.position = Vector2(clampf(at.x, inner.position.x, inner.end.x), clampf(at.y, inner.position.y, inner.end.y))
	object.height_offset = maxf(height, 0.0)
	_loose.add(object)
	return object


func _announce(response: InteractionResponse) -> void:
	interaction_count += 1
	responded.emit(response)
