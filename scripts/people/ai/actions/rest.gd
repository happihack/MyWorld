class_name RestStep
extends ActionStep
## Stay where one is for a while: at home, at the fire, looking at a new place.
##   {"type": "rest", "minutes": float, "elapsed": float, "look": Vector2i (optional),
##    "shelter": what they have gone in from ("rain", "storm", "snow", "cold"; optional),
##    "kneel": bool (optional: at a grave), "grave_of": the id of whom it is the grave of (optional)}
## Someone taking shelter is indoors (there, but not to be seen) if they are
## at their hut.

const TYPE := &"rest"


static func make(minutes: float, look_at: Variant = null, shelter: StringName = &"") -> Dictionary:
	var step := {"type": String(TYPE), "minutes": minutes, "elapsed": 0.0}
	if typeof(look_at) == TYPE_VECTOR2I:
		step["look"] = look_at
	if shelter != &"":
		step["shelter"] = String(shelter)
	return step


func begin(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	person.pose = PersonData.Pose.KNEEL if bool(step.get("kneel", false)) else PersonData.Pose.IDLE
	if typeof(step.get("look")) == TYPE_VECTOR2I:
		ctx.face(person, middle(step["look"]))
	if step.has("shelter"):
		person.set_flag(PersonData.FLAG_INDOORS, ctx.places != null and ctx.places.is_at_home(person))


func end(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	if step.has("shelter"):
		person.set_flag(PersonData.FLAG_INDOORS, false)
	super.end(ctx, person, step)


func update(_ctx: AiContext, _person: PersonData, step: Dictionary, minutes: float) -> Status:
	return Status.DONE if tick(step, minutes) else Status.RUNNING


func patience(_step: Dictionary) -> int:
	return 4
