class_name Stimulus
extends RefCounted
## Something that happens in the world and can be noticed (bible §14.1): a
## touch, a rock that rises into the air, a tree that shakes with no wind.
## Every intervention of the player emits one; inhabitants never learn where
## it came from — they perceive it, and make of it what they will.

enum Origin { PLAYER, NATURE, PERSON }

## A person was touched (target_id).
const TOUCH := &"touch"
## The ground, a rock, a bush — something small stirred.
const GROUND_TOUCHED := &"ground_touched"
## A knock on something built.
const KNOCK := &"knock"
const TREE_SHAKEN := &"tree_shaken"
const TREE_UPROOTED := &"tree_uprooted"
const WATER_DISTURBED := &"water_disturbed"
## Something rose into the air / came down somewhere else.
const OBJECT_LIFTED := &"object_lifted"
const OBJECT_MOVED := &"object_moved"
## Water vanished from where it lay / fell from a clear sky.
const WATER_TAKEN := &"water_taken"
const WATER_POURED := &"water_poured"
## Something the player moved, come upon where it now lies (see Discovery).
const OBJECT_FOUND := &"object_found"
## Someone tells of what they experienced (origin PERSON; see `told_by`).
const TOLD := &"told"

const TYPES: Array[StringName] = [TOUCH, GROUND_TOUCHED, KNOCK, TREE_SHAKEN, TREE_UPROOTED, WATER_DISTURBED,
	OBJECT_LIFTED, OBJECT_MOVED, WATER_TAKEN, WATER_POURED, OBJECT_FOUND, TOLD]

## Number within this session (0 until emitted; see PerceptionSystem).
var id := 0
var type: StringName = TOUCH
var origin: Origin = Origin.PLAYER
## Does it go against what people expect of the world?
var anomalous := true
## Where it happened (world X/Z) and how far it can be noticed (tiles).
var position := Vector2.ZERO
var radius := 0.0
## 0 … 1.
var intensity := 0.5
var tick := 0
## For direct contact: who was touched.
var target_id := 0
## The intervention it came from (0 = none).
var intervention_id := 0
## Large and far-reaching rather than small and local.
var large := false
## Of the kind weather does (water from above, wind in the trees).
var weatherlike := false
## The loose object it is about (lifted, moved, found), 0 otherwise.
var object_id := 0

# --- for TOLD -------------------------------------------------------------------------------
## Who tells it, what it was about (a stimulus type) and what they make of it.
var told_by := 0
var about: StringName = &""
var interpretation: StringName = &""
## How true to what happened the teller's account is (1 = they were there
## and remember it well).
var fidelity := 1.0


## The stimulus an intervention gives off (null if it gives off none).
static func from_intervention(iv: Intervention, table: ReactionTable) -> Stimulus:
	if iv == null or not iv.applied:
		return null
	var kind := type_for(iv)
	if kind == &"":
		return null
	var stimulus := Stimulus.new()
	stimulus.type = kind
	stimulus.origin = Origin.PLAYER
	stimulus.position = Vector2(iv.position.x, iv.position.z)
	stimulus.tick = iv.tick
	stimulus.intervention_id = iv.id
	stimulus.target_id = iv.target_id if kind == TOUCH else 0
	stimulus.object_id = iv.target_id if kind == OBJECT_LIFTED or kind == OBJECT_MOVED else 0
	table.describe(stimulus, strength_of(iv))
	return stimulus


## Which stimulus an intervention is (&"" = none).
static func type_for(iv: Intervention) -> StringName:
	match iv.type:
		Intervention.TOUCH:
			match iv.subject:
				&"person":
					return TOUCH
				&"tree":
					return TREE_SHAKEN
				&"water":
					return WATER_DISTURBED
				&"hut", &"ruin", &"campfire":
					return KNOCK
			return GROUND_TOUCHED
		Intervention.UPROOT:
			return TREE_UPROOTED
		Intervention.GRAB:
			return OBJECT_LIFTED
		Intervention.MOVE_OBJECT:
			return OBJECT_MOVED
		Intervention.SCOOP_WATER:
			return WATER_TAKEN
		Intervention.POUR_WATER:
			return WATER_POURED
	return &""


## How much of it there was, 0 … 1 beyond the least: a boulder is more than a
## pebble, a flood more than a handful.
static func strength_of(iv: Intervention) -> float:
	match iv.type:
		Intervention.GRAB, Intervention.MOVE_OBJECT:
			match iv.subject:
				&"boulder":
					return 1.0
				&"log", &"rock", &"strange_object":
					return 0.6
			return 0.2
		Intervention.SCOOP_WATER, Intervention.POUR_WATER:
			return clampf(iv.magnitude / 1.5, 0.0, 1.0)
	return 0.0


## Someone telling a listener of what they experienced.
static func telling(teller: PersonData, what: StringName, as_what: StringName, strength: float, tick_now: int,
		how_true: float = 1.0) -> Stimulus:
	var stimulus := Stimulus.new()
	stimulus.type = TOLD
	stimulus.origin = Origin.PERSON
	stimulus.anomalous = true # (what is told of was strange, or it would not be told)
	stimulus.position = teller.world2d()
	stimulus.radius = 0.0
	stimulus.intensity = clampf(strength, 0.0, 1.0)
	stimulus.tick = tick_now
	stimulus.told_by = teller.id
	stimulus.about = what
	stimulus.interpretation = as_what
	stimulus.fidelity = clampf(how_true, 0.0, 1.0)
	return stimulus


func describe() -> String:
	return "%s #%d at (%.1f, %.1f) r %.1f i %.2f%s" % [type, id, position.x, position.y, radius, intensity,
		" -> #%d" % target_id if target_id != 0 else ""]
