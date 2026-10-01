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
const LOG_KNOCK := &"log_knock"
const NUDGE := &"nudge"
const TREE_UPROOT := &"tree_uproot"
const INSPECT := &"inspect"
## A person was touched. (How they take it is theirs to show: M5.3.)
const PERSON_TOUCH := &"person_touch"

var action: Action = Action.TAP
var effect: StringName = DUST
## What touching the target does (same as `effect` for a tap; kept when the
## action itself is something else, e.g. a long press).
var touch_effect: StringName = DUST
## Where the effect happens: the touched point for ground/water, the base of
## the prop for entities.
var position := Vector3.ZERO
var tile := Vector2i.ZERO
var entity_id := 0
## PropData.Kind of the touched prop, or -1.
var prop_kind := -1
var prop_variant := 0
## LooseObject.Kind of the touched loose object, or -1.
var loose_kind := -1
## Id of the touched person, or 0 (then also `entity_id`).
var person_id := 0
## Height and radius of the touched body (entities only).
var body := Vector2.ZERO
## How strongly the target gives way to a touch: 1 = an ordinary rock; a
## boulder barely stirs, a pebble jumps.
var strength := 1.0
## Terrain type under the touch (ChunkData.Terrain), for tinting.
var terrain := 0
## Ids of loose objects this touch brought into the world (fruit shaken from
## a tree, the log of an uprooted one).
var dropped: Array[int] = []
## Short human-readable description ("TREE at (7, -4)").
var description := ""


func is_entity() -> bool:
	return entity_id != 0
