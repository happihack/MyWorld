class_name FireStoryStep
extends ActionStep
## Stories by the fire (the owner, 2026-10-06): one stands and tells, those
## sitting round the fire listen. A little way into the telling each listener
## hears what the teller has to tell — second hand, as in a talk (Gossip) —
## so what one saw goes round the village of an evening.
##   {"type": "fire_story", "role": "tell" | "listen", "teller": int,
##    "minutes": float, "elapsed": float, "told": bool}
## The teller is known to the others while telling (AiContext.fire_tellers).

const TYPE := &"fire_story"
const TELL := "tell"
const LISTEN := "listen"
## Further from the teller than this (tiles) a listener hears nothing.
const EARSHOT := 4.5
## How far into the telling (game minutes) the story is told.
const TOLD_AFTER := 6.0


static func tell(minutes: float) -> Dictionary:
	return {"type": String(TYPE), "role": TELL, "minutes": minutes, "elapsed": 0.0, "told": false}


static func listen(teller_id: int, minutes: float) -> Dictionary:
	return {"type": String(TYPE), "role": LISTEN, "teller": teller_id, "minutes": minutes, "elapsed": 0.0}


func patience(_step: Dictionary) -> int:
	return 2


func begin(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	if str(step.get("role", "")) == TELL:
		person.pose = PersonData.Pose.TALK
		person.emote = &"speech"
		ctx.fire_tellers[person.settlement_id] = [person.id, ctx.now() + int(ceilf(float(step.get("minutes", 0.0))))]
		var fire := ctx.settlement.fire() if ctx.settlement != null else null
		if fire != null:
			ctx.face(person, fire.position2d())
	else:
		person.pose = PersonData.Pose.KNEEL
		var teller := ctx.people.get_person(int(step.get("teller", 0)))
		if teller != null:
			ctx.face(person, teller.world2d())


func update(ctx: AiContext, person: PersonData, step: Dictionary, minutes: float) -> Status:
	Needs.satisfy(person.needs, Needs.Need.SOCIAL, minutes / Config.needs.full_company_minutes)
	if str(step.get("role", "")) == TELL:
		var over := tick(step, minutes)
		if not bool(step.get("told", false)) and float(step.get("elapsed", 0.0)) >= TOLD_AFTER:
			step["told"] = true
			for listener in listeners(ctx, person):
				Gossip.share(ctx, person, listener)
				if ctx.day_log != null:
					ctx.day_log.note(listener.id, ctx.now(), "social", "heard_story", person.id)
			if ctx.day_log != null:
				ctx.day_log.note(person.id, ctx.now(), "social", "told_story")
		return Status.DONE if over else Status.RUNNING
	var teller := ctx.people.get_person(int(step.get("teller", 0)))
	if teller == null or not is_telling(ctx, teller) or teller.world2d().distance_to(person.world2d()) > EARSHOT:
		# (Over, once they have listened a while; not told at all when they came:
		# failed — chosen again at once, it went round and round in one moment,
		# deeper and deeper, until the engine's stack broke: soaks, 2026-10-09.)
		return Status.DONE if float(step.get("elapsed", 0.0)) > 0.0 else Status.FAILED
	ctx.face(person, teller.world2d())
	return Status.DONE if tick(step, minutes) else Status.RUNNING


func end(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	if str(step.get("role", "")) == TELL:
		var telling: Variant = ctx.fire_tellers.get(person.settlement_id)
		if typeof(telling) == TYPE_ARRAY and int(telling[0]) == person.id:
			ctx.fire_tellers.erase(person.settlement_id)
	person.emote = &""
	person.pose = PersonData.Pose.IDLE


## Is `teller` telling a story by the fire now?
static func is_telling(ctx: AiContext, teller: PersonData) -> bool:
	var telling: Variant = ctx.fire_tellers.get(teller.settlement_id)
	return typeof(telling) == TYPE_ARRAY and int(telling[0]) == teller.id and int(telling[1]) >= ctx.now()


## Who sits listening to `teller` (within earshot, there for the stories).
static func listeners(ctx: AiContext, teller: PersonData) -> Array[PersonData]:
	var out: Array[PersonData] = []
	for other in ctx.people.all_people():
		if other.id == teller.id or other.world2d().distance_to(teller.world2d()) > EARSHOT:
			continue
		if BehaviorSystem.activity_of(other) == &"storytelling":
			out.append(other)
	return out
