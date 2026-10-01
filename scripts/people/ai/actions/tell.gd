class_name TellStep
extends ActionStep
## Tell someone of what one has experienced (bible §14.4 "tell someone"):
## stand with them and talk. The listener hears of it — second hand, through
## the teller's eyes — and makes something of it in turn.
##   {"type": "tell", "listener": int, "minutes": float, "elapsed": float,
##    "about": String (stimulus type), "interpretation": String, "strength": float,
##    "told": bool}

const TYPE := &"tell"
## Further apart than this (tiles) nothing is heard.
const EARSHOT := 3.0


static func make(listener_id: int, minutes: float, about: StringName, interpretation: StringName, strength: float) -> Dictionary:
	return {"type": String(TYPE), "listener": listener_id, "minutes": minutes, "elapsed": 0.0,
		"about": String(about), "interpretation": String(interpretation), "strength": strength, "told": false}


func begin(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	person.pose = PersonData.Pose.TALK
	person.emote = &"speech"
	var listener := ctx.people.get_person(int(step.get("listener", 0)))
	if listener != null:
		ctx.face(person, listener.world2d())


func update(ctx: AiContext, person: PersonData, step: Dictionary, minutes: float) -> Status:
	var listener := ctx.people.get_person(int(step.get("listener", 0)))
	if listener == null or listener.has_flag(PersonData.FLAG_INDOORS) \
			or listener.world2d().distance_to(person.world2d()) > EARSHOT:
		return Status.DONE # nobody to tell after all
	ctx.face(person, listener.world2d())
	if not bool(step.get("told", false)):
		step["told"] = true
		var about := StringName(str(step.get("about", "")))
		Gossip.tell(ctx, person, listener, about, StringName(str(step.get("interpretation", ""))),
			float(step.get("strength", 0.5)), Gossip.fidelity_of(ctx, person, about, true))
		# Company is company, whatever is said.
		Needs.satisfy(person.needs, Needs.Need.SOCIAL, 0.1)
	return Status.DONE if tick(step, minutes) else Status.RUNNING


func end(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	person.emote = &""
	super.end(ctx, person, step)
