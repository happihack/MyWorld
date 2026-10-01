class_name WalkToStep
extends ActionStep
## Walk to a tile (or, if it cannot be stood on, to beside it).
##   {"type": "walk_to", "target": Vector2i, "offset": Vector2 (optional),
##    "pace": float (optional: times walking speed), "emote": String (optional),
##    "toward": int (optional: a person to end up beside, wherever they go meanwhile)}
## Only the destination is saved: the way is found again after a load.

const TYPE := &"walk_to"
## Walking toward someone: this near (tiles) is there; if they have moved
## further than RETARGET from where one is headed, one heads for them anew.
const BESIDE := 1.6
const RETARGET := 2.5


static func make(target: Vector2i, offset: Vector2 = Vector2(0.5, 0.5), pace: float = 1.0, emote: StringName = &"") -> Dictionary:
	var step := {"type": String(TYPE), "target": target, "offset": offset}
	if not is_equal_approx(pace, 1.0):
		step["pace"] = pace
	if emote != &"":
		step["emote"] = String(emote)
	return step


func begin(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	person.pose = PersonData.Pose.IDLE
	person.emote = StringName(str(step.get("emote", "")))
	ctx.take_walk_result(person.id) # whatever an earlier walk left behind is not this one's


func update(ctx: AiContext, person: PersonData, step: Dictionary, _minutes: float) -> Status:
	if step.has("toward"):
		var other := ctx.people.get_person(int(step["toward"]))
		if other == null or other.has_flag(PersonData.FLAG_INDOORS):
			return Status.DONE # gone: whatever comes next finds that out
		if other.world2d().distance_to(person.world2d()) <= BESIDE:
			return Status.DONE
		var heading: Variant = step.get("target")
		if typeof(heading) != TYPE_VECTOR2I or Vector2(other.position - (heading as Vector2i)).length() > RETARGET:
			step["target"] = Planner._beside(other.position, person.position, ctx)
			ctx.movement.stop(person.id)
			ctx.take_walk_result(person.id)
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
	if not ctx.movement.walk_to(person.id, target, offset if typeof(offset) == TYPE_VECTOR2 else Vector2(0.5, 0.5),
			float(step.get("pace", 1.0))):
		return Status.FAILED
	return Status.RUNNING


func end(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	ctx.movement.stop(person.id)
	ctx.take_walk_result(person.id)
	person.emote = &""
	super.end(ctx, person, step)
