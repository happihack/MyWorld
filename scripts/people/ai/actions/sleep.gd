class_name SleepStep
extends ActionStep
## Sleep at home, until rested — and, once asleep at night, until morning.
## The sleeper is indoors: there, but not seen.
##   {"type": "sleep", "elapsed": float}

const TYPE := &"sleep"
const RESTED := 0.97
## Nobody who is asleep gets up between these hours just because they are
## rested; everyone has their own hour to rise, within RISE_SPREAD of dawn.
const NIGHT_FROM := 20.0
const DAWN := 5.0
const RISE_SPREAD := 1.5


static func make() -> Dictionary:
	return {"type": String(TYPE), "elapsed": 0.0}


func begin(_ctx: AiContext, person: PersonData, _step: Dictionary) -> void:
	person.pose = PersonData.Pose.SLEEP
	person.set_flag(PersonData.FLAG_INDOORS, true)


func update(ctx: AiContext, person: PersonData, step: Dictionary, minutes: float) -> Status:
	Needs.satisfy(person.needs, Needs.Need.SLEEP, minutes / Config.needs.full_sleep_minutes)
	tick(step, minutes)
	if Needs.value(person.needs, Needs.Need.SLEEP) < RESTED or not may_end_early(step):
		return Status.RUNNING
	return Status.RUNNING if is_night_for(person, ctx.clock.hour() if ctx.clock != null else 12.0) else Status.DONE


## Is it still night for this person (early risers and late ones)?
static func is_night_for(person: PersonData, hour: float) -> bool:
	return hour >= NIGHT_FROM or hour < rise_hour(person)


static func rise_hour(person: PersonData) -> float:
	return DAWN + float(((person.id * 2654435761) >> 8) & 0xFF) / 255.0 * RISE_SPREAD


func end(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	person.set_flag(PersonData.FLAG_INDOORS, false)
	super.end(ctx, person, step)


func reluctance(_step: Dictionary) -> float:
	return 0.5


func needs_state(_step: Dictionary) -> Needs.State:
	return Needs.State.SLEEPING
