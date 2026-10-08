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
## Children at odds (FC2): voices, never blows.
const SQUABBLE := &"squabble"
const ALL: Array[StringName] = [CONVERSE, HELP, GIFT, TEACH, FLIRT, ARGUE, FIGHT, SQUABBLE]
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


## What draws two people to each other beyond how alike they are: the same
## for the pair always (from their ids), 0 … 1.
static func chemistry(a: PersonData, b: PersonData) -> float:
	return float(HashNoise.hash2(mini(a.id, b.id), maxi(a.id, b.id), 0x6C6F7665) & 0xFFFF) / 65535.0


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
	# Two grown-ups, both free, drawn to each other (who like each other, or
	# simply are drawn: chemistry).
	var drawn := chemistry(a, b)
	if may_flirt(a, b, ctx) and (feeling > 0.15 or drawn >= Config.relationships.chemistry_from) and feeling > -0.2:
		out[FLIRT] = 0.15 + 0.3 * maxf(Traits.value(a.traits, Traits.Axis.SOCIABILITY), 0.0) + 0.4 * drawn \
			+ 0.5 * (record.romance if record != null else 0.0)
	# A quarrel: between those unlike each other, under strain, who do not much like each other
	# (never with a child).
	var strain := (1.0 - fit) * 1.0 + a.stress * 0.5 + maxf(aggressive, 0.0) * 0.3 - feeling * 0.6 - (0.3 if kin else 0.0)
	if strain > 0.2 and may_quarrel(a, b, ctx):
		out[ARGUE] = (strain - 0.2) * 1.5
	# Two children at odds squabble (FC2).
	if strain > 0.35 and ctx.stage_of(a) == PersonData.LifeStage.CHILD and ctx.stage_of(b) == PersonData.LifeStage.CHILD:
		out[SQUABBLE] = (strain - 0.35) * 1.0
	return out


## May these two quarrel: neither is a child.
static func may_quarrel(a: PersonData, b: PersonData, ctx: AiContext) -> bool:
	return ctx.stage_of(a) != PersonData.LifeStage.CHILD and ctx.stage_of(b) != PersonData.LifeStage.CHILD


## May a quarrel between them come to blows: both grown up (not a child, not
## the young — their quarrels stay words).
static func may_fight(a: PersonData, b: PersonData, ctx: AiContext) -> bool:
	for person: PersonData in [a, b]:
		var stage := ctx.stage_of(person)
		if stage == PersonData.LifeStage.CHILD or stage == PersonData.LifeStage.ADOLESCENT:
			return false
	return true


## May these two flirt: both grown up, neither with a partner, not of one
## family, not of one sex (partnership as M10.2 knows it).
static func may_flirt(a: PersonData, b: PersonData, ctx: AiContext) -> bool:
	if ctx.stage_of(a) != PersonData.LifeStage.ADULT or ctx.stage_of(b) != PersonData.LifeStage.ADULT:
		return false
	if a.partner_id != 0 or b.partner_id != 0 or a.sex == b.sex:
		return false
	return ctx.relationships == null or not (ctx.relationships.is_family(a.id, b.id) or ctx.relationships.close_kin(a.id, b.id))


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
	# (Children are not drawn into quarrels: with a child, it is a talk.)
	if (what == ARGUE or what == FIGHT) and not may_quarrel(a, b, ctx):
		what = CONVERSE
	match what:
		CONVERSE:
			# (Talk brings those who suit each other closer — and wears on those who do not.)
			deltas["affinity"] = config.talk_affinity * (fit - config.talk_suits_from) * 3.0
			# (With a child it never wears: a child does not fall out with anyone over talk.)
			if not may_quarrel(a, b, ctx):
				deltas["affinity"] = maxf(float(deltas["affinity"]), 0.0)
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
			Knowledge.teach(a, b) # (and what they know best: M16.1)
			deltas["respect"] = config.teach_respect * good
			deltas["affinity"] = config.talk_affinity * good
		FLIRT:
			deltas["romance"] = config.flirt_romance * (0.5 + chemistry(a, b))
			deltas["affinity"] = config.talk_affinity * good
			Signs.flash(a, Signs.LOVE, now) # (FC3: seen)
			Signs.flash(b, Signs.LOVE, now)
		ARGUE:
			var record := store.between(a.id, b.id) if store != null else null
			var feeling := record.affinity if record != null else 0.0
			# A quarrel between those who already dislike each other may come to blows.
			if may_fight(a, b, ctx) and feeling <= config.fight_below and maxf(Traits.value(a.traits, Traits.Axis.AGGRESSION), Traits.value(b.traits, Traits.Axis.AGGRESSION)) > 0.3 \
					and ctx.rng.randf() < config.fight_chance:
				what = FIGHT
				deltas["affinity"] = -config.fight_affinity * bad
				deltas["trust"] = -config.fight_affinity * 0.6 * bad
				for person: PersonData in [a, b]:
					Health.injure(person, Health.FIGHT, Config.life.fight_injury * bad, now)
					person.stress = minf(person.stress + 0.25, 1.0)
			else:
				deltas["affinity"] = -config.argue_affinity * bad
				deltas["trust"] = -config.argue_affinity * 0.4 * bad
				for person: PersonData in [a, b]:
					person.stress = minf(person.stress + 0.1, 1.0)
		SQUABBLE:
			deltas["affinity"] = -config.argue_affinity * 0.3 * bad
	if store != null:
		store.acts[what] = int(store.acts.get(what, 0)) + 1
	# Whatever else, unless they quarrel they talk — and tell of what is on their mind.
	if what != ARGUE and what != FIGHT and what != SQUABBLE:
		Gossip.share(ctx, a, b)
	var event_id := 0
	if what == FIGHT:
		ctx.social_events.append([FIGHT, a.id, b.id])
	# (Seen: FC2.)
	if what == ARGUE or what == FIGHT or what == SQUABBLE:
		ctx.scenes.append([what, a.id, b.id])
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
