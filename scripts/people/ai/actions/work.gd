class_name WorkStep
extends ActionStep
## Work at something: chop at a tree, pick from a bush, keep the fire — or,
## for children, play, which is their work. For now work is its own reward
## (it gives purpose); what it yields comes with resources (M9).
##   {"type": "work", "kind": String, "target": int (prop id), "at": Vector2i,
##    "minutes": float, "elapsed": float, "strokes": int}

const TYPE := &"work"
## Game minutes between two strokes of work that can be seen and heard.
const STROKE_MINUTES := 2.0


static func make(kind: StringName, target_id: int, at: Vector2i, minutes: float) -> Dictionary:
	return {"type": String(TYPE), "kind": String(kind), "target": target_id, "at": at,
		"minutes": minutes, "elapsed": 0.0, "strokes": 0}


func begin(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	person.pose = PersonData.Pose.TALK if str(step.get("kind")) == "fire" else PersonData.Pose.WORK
	if typeof(step.get("at")) == TYPE_VECTOR2I:
		ctx.face(person, middle(step["at"]))


func update(ctx: AiContext, person: PersonData, step: Dictionary, minutes: float) -> Status:
	# What was being worked at may be gone (the tree uprooted under the axe).
	var target := int(step.get("target", 0))
	if target != 0 and ctx.props.get_prop(target) == null:
		return Status.DONE
	Needs.satisfy(person.needs, Needs.Need.PURPOSE, minutes / Config.needs.full_work_minutes)
	var time_up := tick(step, minutes)
	# (One stroke per turn at most: a turn that covers several is still one
	# thing seen and heard.)
	var strokes := int(float(step["elapsed"]) / STROKE_MINUTES)
	if strokes > int(step.get("strokes", 0)):
		step["strokes"] = strokes
		ctx.strokes.append([person.id, StringName(str(step.get("kind"))), target])
	return Status.DONE if time_up else Status.RUNNING


func needs_state(_step: Dictionary) -> Needs.State:
	return Needs.State.WORKING


func patience(_step: Dictionary) -> int:
	return int(STROKE_MINUTES) # a turn for every stroke
