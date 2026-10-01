class_name Reactions
extends RefCounted
## From what a person makes of something to what they do about it (bible
## §14.4): the interpretation, their nature and how strong it was give five
## feelings; the feelings (and who they are) give a reaction; the reaction is
## a short plan of steps like any other (see ActionStep).


## Everything that came of one person noticing one thing.
class Outcome:
	extends RefCounted
	var stimulus: Stimulus
	var direct := false
	var salience := 0.0
	var interpretation: StringName = ReactionTable.NATURAL
	var interpretation_scores: Dictionary = {}
	## One value 0 … 1 per ReactionTable.Emotion.
	var emotions := PackedFloat32Array()
	var reaction: StringName = ReactionTable.LOOK
	var reaction_scores: Dictionary = {}
	## What they do, as plan steps ([] = nothing to be seen).
	var steps: Array = []
	## They go and tell someone afterwards.
	var tells := false


## One perception as plain data (see PerceptionSystem):
##   {"stimulus": Stimulus, "salience": float, "direct": bool, "witnesses": int}
static func respond(person: PersonData, perception: Dictionary, ctx: AiContext, table: ReactionTable) -> Outcome:
	var outcome := Outcome.new()
	var stimulus: Stimulus = perception.get("stimulus")
	outcome.stimulus = stimulus
	outcome.direct = bool(perception.get("direct", false))
	outcome.salience = clampf(float(perception.get("salience", 0.0)), 0.0, 1.0)
	var circumstances := Interpretation.features(person, stimulus, outcome.direct, int(perception.get("witnesses", 1)), ctx, table)
	var made := Interpretation.choose(person, stimulus, circumstances, ctx, table)
	outcome.interpretation = made.choice
	outcome.interpretation_scores = made.scores
	var kind := stimulus.about if stimulus.type == Stimulus.TOLD and stimulus.about != &"" else stimulus.type
	var times := Interpretation.familiarity(person, kind)
	outcome.emotions = emotions(person, outcome.interpretation, stimulus, outcome.salience, outcome.direct, times,
		float(circumstances.get(&"child", 0.0)) > 0.5, table)
	var options := options_for(person, stimulus, outcome.direct, ctx, table)
	# Wonder at the like of it, remembered, draws them closer this time.
	var wonder := ctx.memories.wonder_about(person, kind) if ctx.memories != null else 0.0
	outcome.reaction_scores = reaction_scores(person, outcome.interpretation, outcome.emotions, circumstances,
		outcome.salience, options, table, wonder * Config.memory.wonder_weight)
	var heat := table.reaction_temperature * lerpf(0.7, 1.4, Traits.value(person.traits, Traits.Axis.CREATIVITY))
	outcome.reaction = Interpretation.draw(outcome.reaction_scores, heat, ctx.rng) if not outcome.reaction_scores.is_empty() \
		else ReactionTable.LOOK
	if stimulus.type == Stimulus.TOLD and outcome.reaction == ReactionTable.LOOK:
		outcome.reaction = ReactionTable.LISTEN
	# Someone moved by it may go and tell of it afterwards.
	if options.has(ReactionTable.TELL) and outcome.reaction != ReactionTable.TELL \
			and outcome.reaction != ReactionTable.DISMISS and outcome.reaction != ReactionTable.LOOK:
		var chance := table.tell_after_chance * strongest(outcome.emotions) \
			* clampf(0.6 + 0.6 * ReactionTable.lean(person.traits, Traits.Axis.SOCIABILITY), 0.0, 1.2)
		outcome.tells = ctx.rng != null and ctx.rng.randf() < chance
	outcome.steps = plan(person, outcome, ctx, table)
	return outcome


## The five feelings (bible §14.4), each 0 … 1.
static func emotions(person: PersonData, interpretation: StringName, stimulus: Stimulus, salience: float, direct: bool,
		times_before: int, child: bool, table: ReactionTable) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(ReactionTable.EMOTION_COUNT)
	var base: Array = table.interpretation_emotions.get(interpretation, [0.1, 0.2, 0.0, 0.0, 0.0])
	var novelty := 1.0 / (1.0 + float(times_before) * table.novelty_wear)
	var again := float(mini(times_before, table.familiarity_cap)) * table.familiarity_gain
	var force := lerpf(0.6, 1.25, clampf(stimulus.intensity, 0.0, 1.0))
	for emotion in ReactionTable.EMOTION_COUNT:
		var value := float(base[emotion])
		var nature: Dictionary = table.emotion_traits.get(ReactionTable.EMOTION_NAMES[emotion], {})
		for axis: int in nature:
			value += float(nature[axis]) * ReactionTable.lean(person.traits, axis)
		if child:
			value += table.child_emotions[emotion]
		match emotion:
			ReactionTable.Emotion.FEAR, ReactionTable.Emotion.AWE:
				# What frightens and amazes does so by its force, and less each time.
				value *= force * novelty
			ReactionTable.Emotion.ANNOYANCE:
				# Again and again: the irritable have had enough.
				if direct:
					value += again * (0.5 + maxf(ReactionTable.lean(person.traits, Traits.Axis.AGGRESSION), 0.0) \
						+ maxf(ReactionTable.lean(person.traits, Traits.Axis.SUSPICION), 0.0))
			ReactionTable.Emotion.JOY:
				# ...and the trusting have come to like it.
				value += again * maxf(-ReactionTable.lean(person.traits, Traits.Axis.SUSPICION), 0.0) * 1.5
		out[emotion] = value
	# Joy does not live beside fear.
	out[ReactionTable.Emotion.JOY] *= 1.0 - 0.6 * clampf(out[ReactionTable.Emotion.FEAR], 0.0, 1.0)
	var strength := lerpf(0.45, 1.0, salience) * (table.secondhand_factor if stimulus.type == Stimulus.TOLD else 1.0)
	for emotion in ReactionTable.EMOTION_COUNT:
		out[emotion] = clampf(out[emotion] * strength, 0.0, 1.0)
	return out


static func strongest(felt: PackedFloat32Array) -> float:
	var most := 0.0
	for value in felt:
		most = maxf(most, value)
	return most


## Which reactions are open to the person right now.
static func options_for(person: PersonData, stimulus: Stimulus, direct: bool, ctx: AiContext, table: ReactionTable) -> Array[StringName]:
	if stimulus.type == Stimulus.TOLD:
		# A listener listens (LOOK stands for it), prays or waves it away.
		return [ReactionTable.LOOK, ReactionTable.PRAY, ReactionTable.DISMISS]
	var out: Array[StringName] = []
	for reaction in ReactionTable.REACTIONS:
		match reaction:
			ReactionTable.INVESTIGATE:
				# What happened to oneself is not somewhere to walk to.
				if direct or stimulus.position.distance_to(person.world2d()) < 0.75:
					continue
			ReactionTable.RUN:
				if flee_tile(person, stimulus, ctx, table) == null:
					continue
			ReactionTable.TELL:
				if listener_for(person, ctx, table) == null:
					continue
		out.append(reaction)
	return out


## What speaks for each of `options`: reaction -> score.
static func reaction_scores(person: PersonData, interpretation: StringName, felt: PackedFloat32Array,
		circumstances: Dictionary, salience: float, options: Array[StringName], table: ReactionTable,
		wonder: float = 0.0) -> Dictionary:
	var out := {}
	var by_interpretation: Dictionary = table.reaction_by_interpretation.get(interpretation, {})
	for reaction in options:
		var row: Dictionary = table.reactions.get(reaction, {})
		var score := 0.0
		for key: Variant in row:
			var weight := float(row[key])
			if typeof(key) == TYPE_INT:
				score += weight * ReactionTable.lean(person.traits, key)
				continue
			match str(key):
				"base":
					score += weight
				"strongest":
					score += weight * strongest(felt)
				"intense", "child":
					score += weight * float(circumstances.get(StringName(str(key)), 0.0))
				_:
					var emotion := ReactionTable.EMOTION_NAMES.find(StringName(str(key)))
					if emotion >= 0:
						score += weight * felt[emotion]
		score += float(by_interpretation.get(reaction, 0.0))
		# What they remember of the like: wonder draws closer, dread drives off.
		match reaction:
			ReactionTable.INVESTIGATE:
				score += wonder
			ReactionTable.WAVE:
				score += maxf(wonder, 0.0) * 0.5
			ReactionTable.RUN:
				score -= wonder * 0.5
		# What was barely noticed is not run from or prayed to.
		if salience < 0.3 and reaction != ReactionTable.LOOK and reaction != ReactionTable.DISMISS:
			score -= (0.3 - salience) * 3.0
		out[reaction] = score
	return out


## The steps of a reaction.
static func plan(person: PersonData, outcome: Outcome, ctx: AiContext, table: ReactionTable) -> Array:
	var stimulus := outcome.stimulus
	var at := stimulus.position
	var look: Variant = at if at.distance_to(person.world2d()) > 0.3 else null
	var minutes := table.minutes_for(outcome.reaction)
	var start := ReactStep.make(PersonData.Pose.STARTLE, &"exclaim", table.startle_minutes, look)
	var steps: Array = []
	match outcome.reaction:
		ReactionTable.LOOK:
			steps = [ReactStep.make(PersonData.Pose.IDLE, &"question", minutes, look)]
		ReactionTable.LISTEN:
			steps = [ReactStep.make(PersonData.Pose.TALK, &"question", minutes, look)]
		ReactionTable.INVESTIGATE:
			var spot := Planner._beside(WorldCoords.world2d_to_tile(at), person.position, ctx)
			steps = [ReactStep.make(PersonData.Pose.IDLE, &"question", table.startle_minutes, look),
				WalkToStep.make(spot, Vector2(0.5, 0.5), 1.0, &"question"),
				ReactStep.make(PersonData.Pose.CROUCH, &"question", minutes, at)]
		ReactionTable.FREEZE:
			steps = [ReactStep.make(PersonData.Pose.STARTLE, &"exclaim", minutes, look)]
		ReactionTable.RUN:
			var away: Variant = flee_tile(person, stimulus, ctx, table)
			if away == null:
				steps = [ReactStep.make(PersonData.Pose.STARTLE, &"exclaim", minutes, look)]
			else:
				steps = [start, WalkToStep.make(away, Vector2(0.5, 0.5), table.run_pace, &"exclaim"),
					ReactStep.make(PersonData.Pose.STARTLE, &"exclaim", minutes, at)]
		ReactionTable.YELL:
			steps = [ReactStep.make(PersonData.Pose.YELL, &"exclaim", minutes, look)]
		ReactionTable.LAUGH:
			steps = [ReactStep.make(PersonData.Pose.JUMP, &"note", minutes, look)]
		ReactionTable.WAVE:
			steps = [ReactStep.make(PersonData.Pose.WAVE, &"note", minutes, look)]
		ReactionTable.PRAY:
			steps = [ReactStep.make(PersonData.Pose.KNEEL, &"pray", minutes, look)]
			if stimulus.type != Stimulus.TOLD:
				steps.push_front(start)
		ReactionTable.DISMISS:
			steps = [ReactStep.make(PersonData.Pose.SHRUG, &"dots", minutes, look)]
		ReactionTable.TELL:
			steps = [start]
			steps.append_array(_telling(person, outcome, ctx, table))
			if steps.size() == 1:
				steps = [ReactStep.make(PersonData.Pose.IDLE, &"question", minutes, look)]
	if outcome.tells:
		steps.append_array(_telling(person, outcome, ctx, table))
	return steps


## Going to someone and telling them ([] if there is nobody to tell).
static func _telling(person: PersonData, outcome: Outcome, ctx: AiContext, table: ReactionTable) -> Array:
	var listener := listener_for(person, ctx, table)
	if listener == null:
		return []
	var about := outcome.stimulus.about if outcome.stimulus.type == Stimulus.TOLD else outcome.stimulus.type
	var walk := WalkToStep.make(Planner._beside(listener.position, person.position, ctx), person.sub_tile_offset, 1.3, &"exclaim")
	walk["toward"] = listener.id
	return [walk,
		TellStep.make(listener.id, table.minutes_for(ReactionTable.TELL), about, outcome.interpretation, strongest(outcome.emotions))]


## Where to run to: firm ground some way off, away from what happened (null
## if there is none).
static func flee_tile(person: PersonData, stimulus: Stimulus, ctx: AiContext, table: ReactionTable) -> Variant:
	var from := person.world2d() - stimulus.position
	if from.length_squared() < 0.01:
		# It happened right here: any way is away. (Which one is theirs alone.)
		from = Vector2.RIGHT.rotated(float((person.id * 2654435761) & 0xFFFF) / 65535.0 * TAU)
	var far := person.world2d() + from.normalized() * table.flee_distance
	var found := ctx.pathfinder.standable_near(WorldCoords.world2d_to_tile(far), 1, 3)
	if found.is_empty() or found[0] == person.position:
		return null
	return found[0]


## Whom to tell: the nearest person who is up and about, within reach (null
## if there is nobody). Someone close to them, if they are as near.
static func listener_for(person: PersonData, ctx: AiContext, table: ReactionTable) -> PersonData:
	var best: PersonData = null
	var best_distance := INF
	for id in ctx.people.spatial_index.query_radius(person.world2d(), table.tell_range, SpatialIndex.KIND_PERSON):
		if id == person.id:
			continue
		var other := ctx.people.get_person(id)
		if other == null or other.has_flag(PersonData.FLAG_INDOORS) or other.pose == PersonData.Pose.SLEEP:
			continue
		var distance := other.world2d().distance_to(person.world2d())
		# Family counts as nearer than they are.
		if other.household_id == person.household_id and person.household_id != 0:
			distance *= 0.6
		if distance < best_distance:
			best_distance = distance
			best = other
	return best
