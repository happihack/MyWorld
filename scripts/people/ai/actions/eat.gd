class_name EatStep
extends ActionStep
## Eat (at the fire, where the band's food is, until there are stores).
##   {"type": "eat", "minutes": float, "elapsed": float, "at": Vector2i, "meal": bool (optional)}
## A meal (breakfast, lunch, dinner: the hour for it) lasts its time even
## for someone who is soon full, and eating with others is company.

const TYPE := &"eat"
## Others eating within this many tiles are at the same meal.
const TABLE := 3.0
## What a meal in company is worth as company, relative to a conversation.
const COMPANY_SHARE := 0.6


static func make(at: Vector2i, meal: bool = false) -> Dictionary:
	var step := {"type": String(TYPE), "minutes": Config.needs.meal_minutes, "elapsed": 0.0, "at": at}
	if meal:
		step["meal"] = true
	return step


func begin(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	person.pose = PersonData.Pose.EAT
	if typeof(step.get("at")) == TYPE_VECTOR2I:
		ctx.face(person, middle(step["at"]))


func update(ctx: AiContext, person: PersonData, step: Dictionary, minutes: float) -> Status:
	Needs.satisfy(person.needs, Needs.Need.HUNGER, minutes / Config.needs.meal_minutes)
	if company(ctx, person) > 0:
		Needs.satisfy(person.needs, Needs.Need.SOCIAL, minutes / Config.needs.full_company_minutes * COMPANY_SHARE)
	var time_up := tick(step, minutes)
	var full := Needs.value(person.needs, Needs.Need.HUNGER) >= 0.999 and may_end_early(step) \
		and not bool(step.get("meal", false))
	return Status.DONE if time_up or full else Status.RUNNING


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
