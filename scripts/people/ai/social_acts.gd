class_name SocialActs
extends RefCounted
## What happens when two people are together (bible §16.1, M10.1): a talk
## (and with it the news on their mind — see Gossip), a hand at the other's
## work, a gift, a lesson, a flirt — or a quarrel, and rarely a fight. Which
## one comes of it depends on who they are (their natures, and how alike they
## are), on what they are to each other, and on the moment (the other at
## work, a child to teach, someone with food in hand). What it does to them
## depends on the same.

const CONVERSE := &"converse"
const HELP := &"help"
const GIFT := &"gift"
const TEACH := &"teach"
const FLIRT := &"flirt"
const ARGUE := &"argue"
const FIGHT := &"fight"
const ALL: Array[StringName] = [CONVERSE, HELP, GIFT, TEACH, FLIRT, ARGUE, FIGHT]
## The bipolar axes on which being alike makes people get on.
const KINDRED: Array[int] = [Traits.Axis.CURIOSITY, Traits.Axis.GENEROSITY, Traits.Axis.SOCIABILITY, Traits.Axis.SPIRITUALITY,
	Traits.Axis.AGGRESSION, Traits.Axis.SUSPICION, Traits.Axis.ADVENTURE]
## Food given in a gift, in bellies (at most what they have in hand).
const GIFT_FOOD := 0.5


## How alike two people are, 0 (as unlike as can be) … 1 (the same), with a
## little extra for the easy-going (generous, peaceful) and a little less for
## the touchy (aggressive, suspicious).
static func compatibility(a: PersonData, b: PersonData) -> float:
	var apart := 0.0
	for axis in KINDRED:
		apart += absf(Traits.value(a.traits, axis) - Traits.value(b.traits, axis)) / 2.0
	var alike := 1.0 - apart / KINDRED.size()
	var easy := 0.0
	for person: PersonData in [a, b]:
		easy += 0.05 * Traits.value(person.traits, Traits.Axis.GENEROSITY) - 0.06 * Traits.value(person.traits, Traits.Axis.AGGRESSION) \
			- 0.04 * Traits.value(person.traits, Traits.Axis.SUSPICION)
	return clampf(alike + easy, 0.0, 1.0)


## How much speaks for each act of `a` towards `b` now (act -> weight; acts
## that cannot be are left out).
static func weights(a: PersonData, b: PersonData, ctx: AiContext) -> Dictionary:
	var store := ctx.relationships
	var record := store.between(a.id, b.id) if store != null else null
	var feeling := record.affinity if record != null else 0.0
	var kin := store != null and store.is_family(a.id, b.id)
	var fit := compatibility(a, b)
	var generous := Traits.value(a.traits, Traits.Axis.GENEROSITY)
	var aggressive := Traits.value(a.traits, Traits.Axis.AGGRESSION)
	var out := {CONVERSE: 1.0}
	# A hand at their work (family above all).
	if b.pose == PersonData.Pose.WORK:
		out[HELP] = maxf(0.25 + 0.35 * generous + (0.5 if kin else 0.0) + 0.3 * feeling, 0.0)
	# Something to eat, for someone one likes (not in a shortage: then the stores ration it).
	if a.food_in_hand >= 0.1 and feeling > 0.1 and (ctx.settlement == null or not ctx.settlement.is_short()):
		out[GIFT] = maxf(0.2 + 0.4 * generous + 0.3 * feeling, 0.0)
	# What one knows, for someone who knows less (a child above all).
	var teacher := ctx.stage_of(a) != PersonData.LifeStage.CHILD
	var trade := String(a.occupation_id)
	var knows := float(a.skills.get(trade, 0.0)) if trade != "" else 0.0
	if teacher and trade != "" and (ctx.stage_of(b) == PersonData.LifeStage.CHILD or knows > float(b.skills.get(trade, 0.0)) + 0.2):
		out[TEACH] = 0.2 + 0.4 * Traits.value(a.traits, Traits.Axis.INTELLIGENCE) + (0.3 if kin else 0.0)
	# Two grown-ups, both free, drawn to each other.
	if may_flirt(a, b, ctx) and feeling > 0.15:
		out[FLIRT] = 0.15 + 0.3 * maxf(Traits.value(a.traits, Traits.Axis.SOCIABILITY), 0.0) + 0.5 * (record.romance if record != null else 0.0)
	# A quarrel: between those unlike each other, under strain, who do not much like each other.
	var strain := (1.0 - fit) * 1.0 + a.stress * 0.5 + maxf(aggressive, 0.0) * 0.3 - feeling * 0.6 - (0.3 if kin else 0.0)
	if strain > 0.2:
		out[ARGUE] = (strain - 0.2) * 1.5
	return out


## May these two flirt: both grown up, neither with a partner, not of one
## family, not of one sex (partnership as M10.2 knows it).
static func may_flirt(a: PersonData, b: PersonData, ctx: AiContext) -> bool:
	if ctx.stage_of(a) != PersonData.LifeStage.ADULT or ctx.stage_of(b) != PersonData.LifeStage.ADULT:
		return false
	if a.partner_id != 0 or b.partner_id != 0 or a.sex == b.sex:
		return false
	return ctx.relationships == null or not ctx.relationships.is_family(a.id, b.id)


## `a` (who came to `b`) and `b` are together: something comes of it.
## Returns what it was.
static func act(ctx: AiContext, a: PersonData, b: PersonData) -> StringName:
	var options := weights(a, b, ctx)
	var choice := _draw(options, ctx.rng)
	return carry_out(ctx, a, b, choice)


## Does `what` between `a` and `b`: what it changes, the news told, what is
## written in their days and (for what is notable) in the chronicle.
static func carry_out(ctx: AiContext, a: PersonData, b: PersonData, what: StringName) -> StringName:
	var config := Config.relationships
	var store := ctx.relationships
	var now := ctx.now()
	var fit := compatibility(a, b)
	var good := 0.5 + fit # (how well a good thing goes down)
	var bad := 1.5 - fit # (how badly a bad thing goes)
	var deltas := {"familiarity": config.familiarity_per_talk}
	match what:
		CONVERSE:
			# (Talk brings those who suit each other closer — and wears on those who do not.)
			deltas["affinity"] = config.talk_affinity * (fit - config.talk_suits_from) * 3.0
		HELP:
			deltas["affinity"] = config.help_affinity * good
			deltas["trust"] = config.help_affinity * good
			Needs.satisfy(b.needs, Needs.Need.SOCIAL, 0.1)
			Needs.satisfy(a.needs, Needs.Need.PURPOSE, 0.1)
		GIFT:
			var given := minf(a.food_in_hand, GIFT_FOOD)
			a.food_in_hand -= given
			b.food_in_hand += given
			deltas["affinity"] = config.gift_affinity * good
			deltas["trust"] = config.gift_affinity * 0.5 * good
		TEACH:
			var trade := String(a.occupation_id)
			b.skills[trade] = clampf(float(b.skills.get(trade, 0.0)) + config.teach_skill, 0.0, 1.0)
			deltas["respect"] = config.teach_respect * good
			deltas["affinity"] = config.talk_affinity * good
		FLIRT:
			deltas["romance"] = config.flirt_romance * good
			deltas["affinity"] = config.talk_affinity * good
		ARGUE:
			var record := store.between(a.id, b.id) if store != null else null
			var feeling := record.affinity if record != null else 0.0
			# A quarrel between those who already dislike each other may come to blows.
			if feeling <= config.fight_below and maxf(Traits.value(a.traits, Traits.Axis.AGGRESSION), Traits.value(b.traits, Traits.Axis.AGGRESSION)) > 0.3 \
					and ctx.rng.randf() < config.fight_chance:
				what = FIGHT
				deltas["affinity"] = -config.fight_affinity * bad
				deltas["trust"] = -config.fight_affinity * 0.6 * bad
				for person: PersonData in [a, b]:
					person.health = maxf(person.health - config.fight_health, Config.needs.sick_health_floor)
					person.stress = minf(person.stress + 0.25, 1.0)
			else:
				deltas["affinity"] = -config.argue_affinity * bad
				deltas["trust"] = -config.argue_affinity * 0.4 * bad
				for person: PersonData in [a, b]:
					person.stress = minf(person.stress + 0.1, 1.0)
	if store != null:
		store.acts[what] = int(store.acts.get(what, 0)) + 1
	# Whatever else, unless they quarrel they talk — and tell of what is on their mind.
	if what != ARGUE and what != FIGHT:
		Gossip.share(ctx, a, b)
	var event_id := 0
	if what == FIGHT:
		ctx.social_events.append([FIGHT, a.id, b.id])
	if store != null:
		store.modify(a.id, b.id, deltas, event_id, now)
	if ctx.day_log != null and what != CONVERSE:
		ctx.day_log.note(a.id, now, "social", String(what), b.id)
		ctx.day_log.note(b.id, now, "social", String(what) + "_by", a.id)
	return what


static func _draw(options: Dictionary, rng: RandomNumberGenerator) -> StringName:
	var total := 0.0
	for act: StringName in options:
		total += maxf(float(options[act]), 0.0)
	if total <= 0.0:
		return CONVERSE
	var roll := (rng.randf() if rng != null else 0.0) * total
	for act: StringName in ALL:
		if not options.has(act):
			continue
		roll -= maxf(float(options[act]), 0.0)
		if roll <= 0.0:
			return act
	return CONVERSE
