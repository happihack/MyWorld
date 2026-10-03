class_name DrinkStep
extends ActionStep
## Drink from the water one is standing beside.
##   {"type": "drink", "minutes": float, "elapsed": float, "at": Vector2i (the water)}

const TYPE := &"drink"
## Nobody drinks from further away than this (tiles).
const REACH := 2.5


static func make(water: Vector2i) -> Dictionary:
	return {"type": String(TYPE), "minutes": Config.needs.drink_minutes, "elapsed": 0.0, "at": water}


func begin(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	person.pose = PersonData.Pose.EAT
	if typeof(step.get("at")) == TYPE_VECTOR2I:
		ctx.face(person, middle(step["at"]))


func update(ctx: AiContext, person: PersonData, step: Dictionary, minutes: float) -> Status:
	var water: Variant = step.get("at")
	# The water has to be there, and within reach (it may have drained away,
	# or the way may have ended short of it).
	if typeof(water) != TYPE_VECTOR2I or middle(water).distance_to(person.world2d()) > REACH:
		return Status.FAILED
	# (Water to drink, or a well: M12.1.)
	var well := ctx.props.prop_at(water) if ctx.props != null else null
	if ctx.world.get_water(water) <= 0.0 and (well == null or well.kind != PropData.Kind.WELL):
		return Status.FAILED
	Needs.satisfy(person.needs, Needs.Need.THIRST, minutes / Config.needs.drink_minutes)
	var time_up := tick(step, minutes)
	var full := Needs.value(person.needs, Needs.Need.THIRST) >= 0.999 and may_end_early(step)
	if time_up or full:
		Health.drank(person, ctx, water)
		return Status.DONE
	return Status.RUNNING
