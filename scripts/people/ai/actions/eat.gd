class_name EatStep
extends ActionStep
## Eat (at the fire, where the band's food is, until there are stores).
##   {"type": "eat", "minutes": float, "elapsed": float, "at": Vector2i, "meal": bool (optional),
##    "bush": int (optional: eaten straight off this bush, not from the stores)}
## A meal (breakfast, lunch, dinner: the hour for it) lasts its time even
## for someone who is soon full, and eating with others is company.

const TYPE := &"eat"
## Others eating within this many tiles are at the same meal.
const TABLE := 3.0
## What a meal in company is worth as company, relative to a conversation.
const COMPANY_SHARE := 0.6


static func make(at: Vector2i, meal: bool = false, bush_id: int = 0) -> Dictionary:
	var step := {"type": String(TYPE), "minutes": Config.needs.meal_minutes, "elapsed": 0.0, "at": at}
	if meal:
		step["meal"] = true
	if bush_id != 0:
		step["bush"] = bush_id
	return step


func begin(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	person.pose = PersonData.Pose.EAT
	if typeof(step.get("at")) == TYPE_VECTOR2I:
		ctx.face(person, middle(step["at"]))


func update(ctx: AiContext, person: PersonData, step: Dictionary, minutes: float) -> Status:
	var bite := minutes / Config.needs.meal_minutes
	if ctx.settlement == null and not step.has("bush"):
		# (No stores to eat from: food is simply there, as before there were any.)
		Needs.satisfy(person.needs, Needs.Need.HUNGER, bite)
	elif Needs.value(person.needs, Needs.Need.HUNGER) < 0.999:
		# Food is real: what is eaten is taken, a unit at a time, from the
		# settlement's stores (or straight off the bush) — and what is left
		# of a unit is kept for the next meal.
		if person.food_in_hand <= 0.0:
			var from_stores := not step.has("bush") and ctx.settlement != null
			if from_stores and not ctx.settlement.serves(person.id):
				step["empty"] = true
				return Status.DONE # rationing: they have had their share for today
			person.food_in_hand = serve(ctx, step)
			if person.food_in_hand <= 0.0:
				step["empty"] = true
				return Status.DONE # nothing left to eat
			if from_stores:
				ctx.settlement.note_served(person.id, person.food_in_hand)
		bite = minf(bite, person.food_in_hand)
		person.food_in_hand -= bite
		Needs.satisfy(person.needs, Needs.Need.HUNGER, bite)
	if company(ctx, person) > 0:
		Needs.satisfy(person.needs, Needs.Need.SOCIAL, minutes / Config.needs.full_company_minutes * COMPANY_SHARE)
	var time_up := tick(step, minutes)
	var full := Needs.value(person.needs, Needs.Need.HUNGER) >= 0.999 and may_end_early(step) \
		and not bool(step.get("meal", false))
	return Status.DONE if time_up or full else Status.RUNNING


## Takes the next unit of food: off the bush they stand at, or out of the
## settlement's stores. Returns what it feeds, in bellies (0 = there was none).
static func serve(ctx: AiContext, step: Dictionary) -> float:
	var resource: StringName = &""
	var bush := int(step.get("bush", 0))
	if bush != 0:
		var prop := ctx.props.get_prop(bush) if ctx.props != null else null
		if ctx.nodes != null and prop != null and ctx.nodes.take(bush, 1, ctx.now()) > 0:
			resource = ctx.nodes.resource_of(prop)
	elif ctx.settlement != null:
		resource = ctx.settlement.stockpile.take_food()
	var def := ctx.resources.get_def(resource) if ctx.resources != null and resource != &"" else null
	return def.nutrition if def != null else 0.0


## How many others are eating at the same fire.
static func company(ctx: AiContext, person: PersonData) -> int:
	if ctx.people.spatial_index == null:
		return 0
	var count := 0
	for id in ctx.people.spatial_index.query_radius(person.world2d(), TABLE, SpatialIndex.KIND_PERSON):
		if id == person.id:
			continue
		var other := ctx.people.get_person(id)
		if other != null and other.pose == PersonData.Pose.EAT:
			count += 1
	return count


func patience(_step: Dictionary) -> int:
	return 2
