class_name Interpretation
extends RefCounted
## What a person makes of something they have noticed (bible §14.3): each
## possible interpretation is scored — by what people like them believe, by
## their nature, by what they have made of things before, by what those close
## to them believe, by the circumstances — and one is drawn, the likelier the
## higher it scored. The same event means different things to different people.


class Result:
	extends RefCounted
	var choice: StringName = ReactionTable.NATURAL
	## Interpretation -> score, for those that could occur to the person.
	var scores: Dictionary = {}


## A person's convictions, one per interpretation (0 … 1), whatever was saved.
static func beliefs_of(person: PersonData) -> PackedFloat32Array:
	var count := ReactionTable.INTERPRETATIONS.size()
	if person.beliefs.size() != count:
		var fixed := PackedFloat32Array()
		fixed.resize(count)
		for i in mini(count, person.beliefs.size()):
			fixed[i] = clampf(person.beliefs[i], 0.0, 1.0) if is_finite(person.beliefs[i]) else 0.0
		person.beliefs = fixed
	return person.beliefs


## How often the person has experienced this kind of thing before.
static func familiarity(person: PersonData, type: StringName) -> int:
	var seen: Variant = person.knowledge.get("experienced")
	return int((seen as Dictionary).get(String(type), 0)) if typeof(seen) == TYPE_DICTIONARY else 0


## Notes that the person has experienced this kind of thing (once more).
static func note_experience(person: PersonData, type: StringName) -> void:
	var seen: Variant = person.knowledge.get("experienced")
	if typeof(seen) != TYPE_DICTIONARY:
		seen = {}
		person.knowledge["experienced"] = seen
	(seen as Dictionary)[String(type)] = int((seen as Dictionary).get(String(type), 0)) + 1


## The circumstances, each 0 … 1 (see ReactionTable.interpretation_context).
static func features(person: PersonData, stimulus: Stimulus, direct: bool, witnesses: int, ctx: AiContext,
		table: ReactionTable) -> Dictionary:
	var kind := stimulus.about if stimulus.type == Stimulus.TOLD and stimulus.about != &"" else stimulus.type
	var times := familiarity(person, kind)
	return {
		&"ordinary": 0.0 if stimulus.anomalous else 1.0,
		&"large": 1.0 if stimulus.large else 0.0,
		&"local": 0.0 if stimulus.large else 1.0,
		&"weatherlike": 1.0 if stimulus.weatherlike else 0.0,
		&"intense": smoothstep(0.5, 0.9, stimulus.intensity),
		&"faint": 1.0 - smoothstep(0.15, 0.4, stimulus.intensity),
		&"direct": 1.0 if direct else 0.0,
		&"alone": 1.0 if witnesses <= 1 else 0.0,
		&"tired": 1.0 - smoothstep(0.1, 0.35, Needs.value(person.needs, Needs.Need.SLEEP)) if person.needs.size() == Needs.COUNT else 0.0,
		&"familiar": clampf(float(times) / float(maxi(table.familiarity_cap, 1)), 0.0, 1.0),
		&"child": 1.0 if ctx.stage_of(person) == PersonData.LifeStage.CHILD else 0.0,
		&"asleep": 1.0 if person.pose == PersonData.Pose.SLEEP else 0.0,
	}


## Could this interpretation occur to the person at all?
static func available(person: PersonData, interpretation: StringName, ctx: AiContext, table: ReactionTable) -> bool:
	var gate := str(table.interpretation_gates.get(interpretation, "never"))
	match gate:
		"":
			return true
		"never":
			return false
		"death":
			return knows_death(person, ctx)
		"asleep":
			return person.pose == PersonData.Pose.SLEEP
	return person.knowledge.has(gate)


## Has someone of theirs died (a parent, a partner, a child who is no longer
## in the world)?
static func knows_death(person: PersonData, ctx: AiContext) -> bool:
	if person.partner_id != 0 and not ctx.people.has_person(person.partner_id):
		return true
	for id in person.parents:
		if id != 0 and not ctx.people.has_person(id):
			return true
	for id in person.children:
		if id != 0 and not ctx.people.has_person(id):
			return true
	return false


## The score of every interpretation that could occur to the person.
static func scores(person: PersonData, stimulus: Stimulus, circumstances: Dictionary, ctx: AiContext,
		table: ReactionTable) -> Dictionary:
	var out := {}
	var beliefs := beliefs_of(person)
	var child := float(circumstances.get(&"child", 0.0)) > 0.5
	var prior_factor := table.child_prior_factor if child else 1.0
	var close := _close_ones(person, ctx)
	for index in ReactionTable.INTERPRETATIONS.size():
		var interpretation := ReactionTable.INTERPRETATIONS[index]
		if not available(person, interpretation, ctx, table):
			continue
		var score := float(table.interpretation_base.get(interpretation, 0.0))
		# What people like me believe.
		score += table.culture_prior(ctx.world_seed, person.settlement_id, interpretation) * prior_factor
		# My nature.
		var weights: Dictionary = table.interpretation_traits.get(interpretation, {})
		for axis: int in weights:
			score += float(weights[axis]) * ReactionTable.lean(person.traits, axis)
		# What I have made of things before.
		score += beliefs[index] * table.evidence_weight * prior_factor
		# What those close to me believe.
		if not close.is_empty():
			var shared := 0.0
			for other: PersonData in close:
				shared += beliefs_of(other)[index]
			score += shared / close.size() * table.social_weight
		# The circumstances.
		var context: Dictionary = table.interpretation_context.get(interpretation, {})
		for feature: StringName in context:
			score += float(context[feature]) * float(circumstances.get(feature, 0.0))
		# What I am told it was (the suspicious take less on trust).
		if stimulus.type == Stimulus.TOLD and stimulus.interpretation == interpretation:
			score += table.told_weight * (1.0 - 0.5 * maxf(ReactionTable.lean(person.traits, Traits.Axis.SUSPICION), 0.0))
		out[interpretation] = score
	return out


## Scores everything and draws one (weighted: p ∝ exp(score / temperature)).
static func choose(person: PersonData, stimulus: Stimulus, circumstances: Dictionary, ctx: AiContext,
		table: ReactionTable) -> Result:
	var result := Result.new()
	result.scores = scores(person, stimulus, circumstances, ctx, table)
	if result.scores.is_empty():
		return result
	var heat := table.interpretation_temperature * lerpf(0.7, 1.4, Traits.value(person.traits, Traits.Axis.CREATIVITY))
	result.choice = draw(result.scores, heat, ctx.rng)
	return result


## Weighted draw from id -> score. The order of the ids does not depend on
## how the Dictionary was built, so the same dice give the same answer.
static func draw(scored: Dictionary, heat: float, rng: RandomNumberGenerator) -> StringName:
	var ids: Array = scored.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var best := -INF
	for id: StringName in ids:
		best = maxf(best, float(scored[id]))
	var weights := PackedFloat32Array()
	var total := 0.0
	for id: StringName in ids:
		var weight := exp((float(scored[id]) - best) / maxf(heat, 0.001))
		weights.append(weight)
		total += weight
	var roll := (rng.randf() if rng != null else 0.0) * total
	for i in ids.size():
		roll -= weights[i]
		if roll <= 0.0:
			return ids[i]
	return ids[-1]


## An experience moves the person's convictions: what they made of it grows,
## the rest fades a little (bible §14: "belief update").
static func update_beliefs(person: PersonData, interpretation: StringName, weight: float, table: ReactionTable) -> void:
	var beliefs := beliefs_of(person)
	var chosen := ReactionTable.INTERPRETATIONS.find(interpretation)
	for index in beliefs.size():
		if index == chosen:
			beliefs[index] = clampf(beliefs[index] + table.belief_gain * weight * (1.0 - beliefs[index]), 0.0, 1.0)
		else:
			beliefs[index] = clampf(beliefs[index] * (1.0 - table.belief_fade * weight), 0.0, 1.0)
	person.beliefs = beliefs


## What the person is most convinced of (&"" if of nothing yet).
static func conviction(person: PersonData) -> StringName:
	var beliefs := beliefs_of(person)
	var best := -1
	for index in beliefs.size():
		if beliefs[index] > 0.05 and (best < 0 or beliefs[index] > beliefs[best]):
			best = index
	return ReactionTable.INTERPRETATIONS[best] if best >= 0 else &""


## Partner and parents who are in the world.
static func _close_ones(person: PersonData, ctx: AiContext) -> Array[PersonData]:
	var out: Array[PersonData] = []
	var partner := ctx.people.get_person(person.partner_id) if person.partner_id != 0 else null
	if partner != null:
		out.append(partner)
	for id in person.parents:
		var parent := ctx.people.get_person(id)
		if parent != null:
			out.append(parent)
	return out
