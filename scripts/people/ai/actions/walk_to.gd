class_name WalkToStep
extends ActionStep
## Walk to a tile (or, if it cannot be stood on, to beside it).
##   {"type": "walk_to", "target": Vector2i, "offset": Vector2 (optional)}
## Only the destination is saved: the way is found again after a load.

const TYPE := &"walk_to"


static func make(target: Vector2i, offset: Vector2 = Vector2(0.5, 0.5)) -> Dictionary:
	return {"type": String(TYPE), "target": target, "offset": offset}


func begin(ctx: AiContext, person: PersonData, _step: Dictionary) -> void:
	person.pose = PersonData.Pose.IDLE
	ctx.take_walk_result(person.id) # whatever an earlier walk left behind is not this one's


func update(ctx: AiContext, person: PersonData, step: Dictionary, _minutes: float) -> Status:
	var result := ctx.take_walk_result(person.id)
	if result == &"arrived":
		return Status.DONE
	if result == &"blocked":
		return Status.FAILED
	if ctx.movement.is_walking(person.id):
		return Status.RUNNING
	var target: Variant = step.get("target")
	if typeof(target) != TYPE_VECTOR2I:
		return Status.FAILED
	if person.position == target:
		return Status.DONE
	var offset: Variant = step.get("offset")
	if not ctx.movement.walk_to(person.id, target, offset if typeof(offset) == TYPE_VECTOR2 else Vector2(0.5, 0.5)):
		return Status.FAILED
	return Status.RUNNING


func end(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	ctx.movement.stop(person.id)
	ctx.take_walk_result(person.id)
	super.end(ctx, person, step)
