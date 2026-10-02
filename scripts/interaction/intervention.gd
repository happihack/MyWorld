class_name Intervention
extends RefCounted
## One thing the player does to the world (bible §14.6, §23.4): a touch, a
## moved rock, an uprooted tree, poured water. Every such act is described by
## an Intervention and goes through InteractionManager.apply_intervention() —
## the one place where the player changes the world — which validates it,
## carries it out, and writes it into the player's history.

enum Severity { GENTLE, MODERATE, MAJOR }

## Kinds of intervention that exist so far.
const TOUCH := &"touch"
const GRAB := &"grab"
const MOVE_OBJECT := &"move_object"
const UPROOT := &"uproot"
const SCOOP_WATER := &"scoop_water"
const POUR_WATER := &"pour_water"
## The powers over weather and water (M9.5).
const MAKE_RAIN := &"make_rain"
const MAKE_WIND := &"make_wind"
const CARVE := &"carve"

## Acts that go on for a while (rain while a finger is held, a channel
## carved tile by tile) come in phases: they take effect as they go, and
## are one entry in the history when they end.
const PHASE_BEGIN := &"begin"
const PHASE_MORE := &"more"
const PHASE_END := &"end"

# --- what is asked for (filled in by whoever creates it) ---
var type: StringName = TOUCH
## The tool it was done with.
var tool: StringName = &"hand"
## What was under the finger, for interventions aimed with it.
var target: Picker.Result
var target_id := 0
var tile := Vector2i.ZERO
var position := Vector3.ZERO
## How much: distance moved (tiles), water moved (depth), ... 1 where it has no measure.
var magnitude := 1.0
## Anything else the kind needs (a release velocity, ...).
var params: Dictionary = {}

# --- what came of it (filled in by apply_intervention) ---
## Number in the player's history (0 until applied and recorded).
var id := 0
var tick := 0
var applied := false
## Why it was refused (&"" if it was not).
var rejected: StringName = &""
var severity: Severity = Severity.GENTLE
## What it was done to: "tree", "water", "rock", "ground", ...
var subject: StringName = &""
## False for acts that are part of a longer one and are not history on their
## own (picking something up; the move is recorded when it is put down).
var recorded := true
## What the world did in answer (for interventions that are touches).
var response: InteractionResponse


static func create(kind: StringName, with_tool: StringName = &"hand", at: Picker.Result = null) -> Intervention:
	var iv := Intervention.new()
	iv.type = kind
	iv.tool = with_tool
	iv.target = at
	if at != null:
		iv.tile = at.tile
		iv.position = at.position
		iv.target_id = at.entity_id
	return iv


## "touch:tree", "move_object:boulder", ... — what the history counts by.
func key() -> String:
	return "%s:%s" % [type, subject] if subject != &"" else String(type)


## The lasting record of this intervention (player history).
func to_record() -> Dictionary:
	return {
		"id": id, "type": String(type), "subject": String(subject), "tool": String(tool),
		"tick": tick, "tile": tile, "target_id": target_id, "magnitude": magnitude,
		"severity": severity,
	}
