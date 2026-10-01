class_name InteractionResponse
extends RefCounted
## What the world does in answer to a player touch (bible §14, §23). Produced
## by InteractionManager; consumed by the visual effects now, and by audio,
## haptics, the player history and inhabitants' perception later.

enum Action { TAP, LONG_PRESS, DOUBLE_TAP }

## Effect ids (StringNames so new ones never need a central enum change).
const DUST := &"dust"
const RIPPLE := &"ripple"
const TREE_SHAKE := &"tree_shake"
const BUSH_RUSTLE := &"bush_rustle"
const ROCK_WOBBLE := &"rock_wobble"
const BUILDING_KNOCK := &"building_knock"
const FIRE_FLARE := &"fire_flare"
const RUIN_HUM := &"ruin_hum"
const INSPECT := &"inspect"

var action: Action = Action.TAP
var effect: StringName = DUST
## Where the effect happens: the touched point for ground/water, the base of
## the prop for entities.
var position := Vector3.ZERO
var tile := Vector2i.ZERO
var entity_id := 0
## PropData.Kind of the touched prop, or -1.
var prop_kind := -1
## Height and radius of the touched body (entities only).
var body := Vector2.ZERO
## Terrain type under the touch (ChunkData.Terrain), for tinting.
var terrain := 0
## Short human-readable description ("TREE at (7, -4)").
var description := ""


func is_entity() -> bool:
	return entity_id != 0
