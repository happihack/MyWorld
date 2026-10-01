class_name StoreStep
extends ActionStep
## Put down what one is carrying at the settlement's stores: onto the pile
## of it that lies there, or the beginning of a new one.
##   {"type": "store", "minutes": float, "elapsed": float}

const TYPE := &"store"


static func make() -> Dictionary:
	return {"type": String(TYPE), "minutes": Config.resources.store_minutes, "elapsed": 0.0}


func begin(_ctx: AiContext, person: PersonData, _step: Dictionary) -> void:
	person.pose = PersonData.Pose.WORK


func update(ctx: AiContext, person: PersonData, step: Dictionary, minutes: float) -> Status:
	if person.carrying_amount <= 0:
		return Status.DONE # nothing in their arms after all
	if not tick(step, minutes):
		return Status.RUNNING
	if ctx.put_down(person) > 0:
		Needs.satisfy(person.needs, Needs.Need.PURPOSE, Config.resources.load_purpose)
	return Status.DONE


func needs_state(_step: Dictionary) -> Needs.State:
	return Needs.State.WORKING
