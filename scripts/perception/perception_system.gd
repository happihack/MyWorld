class_name PerceptionSystem
extends RefCounted
## Who notices what (bible §14.2). A stimulus reaches everyone within its
## radius; each of them takes it in more or less — by how strong it was, how
## near, how much attention they had to spare and how strange it was. What is
## taken in enough is queued for the person (AiContext.perceptions) and they
## consider it at their next turn; a direct touch is always perceived, and at
## once.
##
## What they make of it and do about it is theirs (Interpretation, Reactions,
## carried out by the BehaviorSystem).

## A person noticed a stimulus. `direct`: it happened to them (consider it now).
signal noticed(person_id: int, direct: bool)

var ctx: AiContext
## For the debug overlay.
var emitted := 0
var last: Stimulus
var last_noticed := 0


func bind(context: AiContext) -> void:
	ctx = context
	emitted = 0
	last = null
	last_noticed = 0


## Sends a stimulus out into the world. Returns how many people noticed it.
func emit(stimulus: Stimulus) -> int:
	if ctx == null or stimulus == null:
		return 0
	stimulus.id = ctx.take_stimulus_id()
	if stimulus.tick == 0:
		stimulus.tick = ctx.now()
	emitted += 1
	last = stimulus
	EventBus.stimulus_emitted.emit(stimulus.id)
	var table := Config.reactions
	# Who takes it in: [person id, salience, direct].
	var takers: Array = []
	var target := ctx.people.get_person(stimulus.target_id) if stimulus.target_id != 0 else null
	if target != null:
		takers.append([target.id, maxf(salience(stimulus, 0.0, attention(target, ctx, table), table), table.notice_threshold), true])
	if stimulus.radius > 0.0 and ctx.people.spatial_index != null:
		for id in ctx.people.spatial_index.query_radius(stimulus.position, stimulus.radius, SpatialIndex.KIND_PERSON):
			if id == stimulus.target_id:
				continue
			var person := ctx.people.get_person(id)
			if person == null:
				continue
			var attentive := attention(person, ctx, table)
			var distance := person.world2d().distance_to(stimulus.position)
			# A knock on the wall one sleeps behind is as near as can be.
			if stimulus.building_id != 0 and person.home_building_id == stimulus.building_id \
					and person.has_flag(PersonData.FLAG_INDOORS):
				attentive = minf(attentive * table.own_wall_factor, 1.0)
				distance = 0.0
			var taken := salience(stimulus, distance, attentive, table)
			if taken >= table.notice_threshold:
				takers.append([id, taken, false])
	for taker: Array in takers:
		queue(taker[0], {"stimulus": stimulus, "salience": taker[1], "direct": taker[2], "witnesses": takers.size()})
	last_noticed = takers.size()
	for taker: Array in takers:
		noticed.emit(taker[0], taker[2])
	return takers.size()


## Puts a perception before a person, to be considered at their next turn.
func queue(person_id: int, perception: Dictionary) -> void:
	if not ctx.perceptions.has(person_id):
		ctx.perceptions[person_id] = []
	(ctx.perceptions[person_id] as Array).append(perception)


## How much a stimulus stands out to someone `distance` tiles away who has
## `attentive` (0 … 1) attention to spare: 0 … 1.
static func salience(stimulus: Stimulus, distance: float, attentive: float, table: ReactionTable) -> float:
	var proximity := 1.0
	if stimulus.radius > 0.0:
		proximity = lerpf(1.0, table.edge_proximity, clampf(distance / stimulus.radius, 0.0, 1.0))
	var strangeness := table.anomaly_factor if stimulus.anomalous else table.ordinary_factor
	return clampf(stimulus.intensity * proximity * attentive * strangeness, 0.0, 1.0)


## How much of what happens around them a person takes in right now.
static func attention(person: PersonData, context: AiContext, table: ReactionTable) -> float:
	if person.pose == PersonData.Pose.SLEEP or person.has_flag(PersonData.FLAG_INDOORS):
		return table.attention_asleep
	if BehaviorSystem.activity_of(person) == BehaviorSystem.ACTIVITY_REACT:
		return table.attention_reacting
	if person.pose == PersonData.Pose.WORK:
		return table.attention_working
	if context != null and context.movement != null and context.movement.is_walking(person.id):
		return table.attention_walking
	return 1.0


func debug_text() -> String:
	if last == null:
		return "stimuli 0"
	return "stimuli %d  last: %s  noticed by %d" % [emitted, last.describe(), last_noticed]
