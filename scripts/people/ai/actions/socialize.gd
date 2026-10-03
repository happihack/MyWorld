class_name SocializeStep
extends ActionStep
## Keep someone company: stand with them, turned to each other. Both get
## something out of it — the one who came more.
##   {"type": "socialize", "partner": int, "minutes": float, "elapsed": float,
##    "gossiped": bool}
## A little way into it something comes of it (bible §16.1, see SocialActs):
## mostly a talk — and they tell of what is on their mind (bible §15.3
## "gossip") — sometimes a hand at the other's work, a gift, a lesson, a
## flirt, a quarrel.

const TYPE := &"socialize"
## Further apart than this (tiles) it is no conversation.
const EARSHOT := 3.0
## What the one who was visited gets, relative to the visitor.
const PARTNER_SHARE := 0.6
## How far into the conversation (game minutes) the telling comes.
const GOSSIP_AFTER := 3.0


static func make(partner_id: int, minutes: float) -> Dictionary:
	return {"type": String(TYPE), "partner": partner_id, "minutes": minutes, "elapsed": 0.0}


func patience(_step: Dictionary) -> int:
	return 2


func begin(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	person.pose = PersonData.Pose.TALK
	var partner := ctx.people.get_person(int(step.get("partner", 0)))
	if partner != null:
		ctx.face(person, partner.world2d())


func update(ctx: AiContext, person: PersonData, step: Dictionary, minutes: float) -> Status:
	var partner := ctx.people.get_person(int(step.get("partner", 0)))
	if partner == null or partner.has_flag(PersonData.FLAG_INDOORS) \
			or partner.world2d().distance_to(person.world2d()) > EARSHOT:
		# They left (or went to bed): what was said was said.
		return Status.DONE if may_end_early(step) else Status.FAILED
	var gain := minutes / Config.needs.full_company_minutes
	Needs.satisfy(person.needs, Needs.Need.SOCIAL, gain)
	Needs.satisfy(partner.needs, Needs.Need.SOCIAL, gain * PARTNER_SHARE)
	ctx.face(person, partner.world2d())
	# Someone standing about turns to whoever talks to them; someone busy goes on.
	if partner.pose == PersonData.Pose.IDLE and not ctx.movement.is_walking(partner.id):
		ctx.face(partner, person.world2d())
	if not bool(step.get("gossiped", false)) and float(step.get("elapsed", 0.0)) >= GOSSIP_AFTER:
		step["gossiped"] = true
		step["act"] = String(SocialActs.act(ctx, person, partner))
	var time_up := tick(step, minutes)
	var full := Needs.value(person.needs, Needs.Need.SOCIAL) >= 0.999 and may_end_early(step)
	return Status.DONE if time_up or full else Status.RUNNING
