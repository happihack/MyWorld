class_name EatStep
extends ActionStep
## Eat (at the fire, where the band's food is, until there are stores).
##   {"type": "eat", "minutes": float, "elapsed": float, "at": Vector2i}

const TYPE := &"eat"


static func make(at: Vector2i) -> Dictionary:
	return {"type": String(TYPE), "minutes": Config.needs.meal_minutes, "elapsed": 0.0, "at": at}


func begin(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	person.pose = PersonData.Pose.EAT
	if typeof(step.get("at")) == TYPE_VECTOR2I:
		ctx.face(person, middle(step["at"]))


func update(_ctx: AiContext, person: PersonData, step: Dictionary, minutes: float) -> Status:
	Needs.satisfy(person.needs, Needs.Need.HUNGER, minutes / Config.needs.meal_minutes)
	var time_up := tick(step, minutes)
	var full := Needs.value(person.needs, Needs.Need.HUNGER) >= 0.999 and may_end_early(step)
	return Status.DONE if time_up or full else Status.RUNNING
