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


func bind(world: WorldData, props: PropRegistry) -> void:
	_world = world
	_props = props
	interaction_count = 0


## A tap on `target`. Returns the response, or null if nothing was touched.
func tap(target: Picker.Result) -> InteractionResponse:
	return _respond(target, InteractionResponse.Action.TAP)


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
	actions.append(ACTION_FOCUS)
	return actions


## The facts about a target (the inspect card). Null for a miss. Looking does
## not touch the world: nothing is announced.
func inspect(target: Picker.Result) -> InspectReport:
	if target == null or not target.is_hit() or _world == null:
		return null
	var report := InspectReport.new()
	var prop: PropData = null
	if target.kind == Picker.Kind.ENTITY and _props != null:
		prop = _props.get_prop(target.entity_id)
	report.tile = prop.tile if prop != null else target.tile
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
	if target.kind == Picker.Kind.ENTITY and _props != null:
		prop = _props.get_prop(target.entity_id)

	if prop != null:
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


func _announce(response: InteractionResponse) -> void:
	interaction_count += 1
	responded.emit(response)
