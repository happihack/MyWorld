class_name RestStep
extends ActionStep
## Stay where one is for a while: at home, at the fire, looking at a new place.
##   {"type": "rest", "minutes": float, "elapsed": float, "look": Vector2i (optional)}

const TYPE := &"rest"


static func make(minutes: float, look_at: Variant = null) -> Dictionary:
	var step := {"type": String(TYPE), "minutes": minutes, "elapsed": 0.0}
	if typeof(look_at) == TYPE_VECTOR2I:
		step["look"] = look_at
	return step


func begin(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	person.pose = PersonData.Pose.IDLE
	if typeof(step.get("look")) == TYPE_VECTOR2I:
		ctx.face(person, middle(step["look"]))


func update(_ctx: AiContext, _person: PersonData, step: Dictionary, minutes: float) -> Status:
	return Status.DONE if tick(step, minutes) else Status.RUNNING


func patience(_step: Dictionary) -> int:
	return 4
