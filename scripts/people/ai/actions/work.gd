class_name WorkStep
extends ActionStep
## Work at something: chop at a tree, pick from a bush, keep the fire — or,
## for children, play, which is their work. Work gives purpose; work at a
## resource node also yields what the node holds ("gather": the worker takes
## it up as they go, and stops when their arms are full or nothing is left).
##   {"type": "work", "kind": String, "target": int (prop id), "at": Vector2i,
##    "minutes": float, "elapsed": float, "strokes": int,
##    "gather": bool (optional), "effort": int (strokes towards the next unit)}

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
	var prop := ctx.props.get_prop(target) if target != 0 else null
	if target != 0 and prop == null:
		return Status.DONE
	Needs.satisfy(person.needs, Needs.Need.PURPOSE, minutes / Config.needs.full_work_minutes)
	var time_up := tick(step, minutes)
	# (One stroke per turn at most: a turn that covers several is still one
	# thing seen and heard.)
	var strokes := int(float(step["elapsed"]) / STROKE_MINUTES)
	if strokes > int(step.get("strokes", 0)):
		var made := strokes - int(step.get("strokes", 0))
		step["strokes"] = strokes
		ctx.strokes.append([person.id, StringName(str(step.get("kind"))), target])
		if bool(step.get("gather", false)) and gather(ctx, person, step, prop, made):
			return Status.DONE
	return Status.DONE if time_up else Status.RUNNING


## `strokes` of work at a node: every so many yield a unit, taken up by the
## worker. True when there is no point going on: their arms are full, or the
## node has nothing left.
static func gather(ctx: AiContext, person: PersonData, step: Dictionary, prop: PropData, strokes: int) -> bool:
	if ctx.nodes == null or prop == null:
		return false
	var resource := ctx.nodes.resource_of(prop)
	if resource == &"":
		return false
	if person.carrying_amount > 0 and person.carrying != resource:
		return true # their arms are full of something else
	var capacity := ctx.carry_capacity(resource)
	var per_unit := ctx.nodes.strokes_per_unit(prop)
	var effort := int(step.get("effort", 0)) + strokes
	while effort >= per_unit and person.carrying_amount < capacity:
		if ctx.nodes.take(prop.id, 1, ctx.now()) <= 0:
			break
		effort -= per_unit
		person.carrying = resource
		person.carrying_amount += 1
	step["effort"] = mini(effort, per_unit)
	return person.carrying_amount >= capacity or ctx.nodes.available(prop) <= 0


func needs_state(_step: Dictionary) -> Needs.State:
	return Needs.State.WORKING


func patience(_step: Dictionary) -> int:
	return int(STROKE_MINUTES) # a turn for every stroke
