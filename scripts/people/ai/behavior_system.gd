class_name BehaviorSystem
extends RefCounted
## People living their days (bible §13.4): needs run down, everyone decides
## what to do about it (Brain), makes a short plan (Planner) and carries it
## out step by step (ActionStep), and decides again when it is done, when it
## fails, or when something more pressing comes up.
##
## What someone is doing is plain data in PersonData.current_action:
##   {"activity": "eat", "reason": "hunger", "since": tick, "score": 0.9,
##    "steps": [ {...}, {...} ], "index": 0}
## so a world saved in the middle of a meal is restored in the middle of it.
##
## Whose turn it is to live, how much time has built up for them, and how
## much of the frame that may take is the SimulationManager's business: it
## calls live() person by person. (step() lets everyone live at once — for
## tests, and wherever there is no frame to keep.) Walking itself is the
## MovementSystem's and stays smooth.

## A person's activity changed (&"" = nothing to do).
signal activity_changed(person_id: int, activity: StringName)
## A person should take their next turn at once (see prompt()).
signal prompted(person_id: int)
## A stroke of work that can be seen and heard: kind is "tree", "bush", "fire".
signal worked(person_id: int, kind: StringName, target_id: int)
## A child has gone to bed for the night (the hook for bedtime stories, M11).
signal bedtime(child_id: int)
## A hunter killed an animal.
signal hunted(person_id: int, species: StringName)
## Someone has fallen ill (`condition`: "hunger" — weak with it), or is
## over it.
signal fell_ill(person_id: int, condition: StringName)
## Something between two people worth telling (a fight).
signal social(act: StringName, person_id: int, other_id: int)
signal recovered(person_id: int, condition: StringName)
## A person reacted to something they noticed (bible §14.4). `stimulus` is the
## kind of thing it was; `direct`: it happened to them.
signal reacted(person_id: int, reaction: StringName, interpretation: StringName, stimulus: StringName, direct: bool)

## A need has to have grown this much louder (see ActivityDef.voice) since a
## person last weighed everything up for a look up to be worth another
## weighing — until enough time has passed anyway (SimConfig.relaxed_think_factor).
const LOUDER := 0.05
## How far (tiles) firm ground is looked for around someone who is stranded.
const STRANDED_SEARCH := 12
## Turns come a hair's breadth short of whole minutes (frames do not divide
## them evenly): "every tick" must not become every second one.
const THINK_SLACK := 0.05
## Something that turned out not to be possible is not tried again for this long.
const BARRED_MINUTES := 30
## A person with nothing they can do stands about for this long before
## thinking again.
const IDLE_MINUTES := 10.0
## Being called (see call_to) keeps someone at the spot for this long.
const CALLED_MINUTES := 12.0

const ACTIVITY_CALLED := &"called"
## Reacting to something noticed: see _consider_perceptions.
const ACTIVITY_REACT := &"react"
const ACTIVITY_IDLE := &"idle"

## Off = everyone stands where they are (the debug "freeze AI").
var enabled := true
var ctx: AiContext
## For the debug overlay.
var decisions := 0
## Looks up that needed no weighing up (nothing could have mattered more).
var skipped := 0
## People who stepped back out of water that rose too deep around them
## (the river does that: no fault), and — below — people moved off ground
## nobody can stand on for any other reason (see _rescue_if_stranded).
var waded_out := 0
var rescues := 0
## How often each person has looked up from what they were doing: id -> count.
var looked_up: Dictionary = {}
## How many times someone has reacted to something (for the overlay).
var reactions := 0

var _steps: Dictionary = {} # step type (String) -> ActionStep
var _begun: Dictionary = {} # person id -> the step Dictionary begin() was called for
var _since_think: Dictionary = {} # person id -> game minutes since they last looked up
var _since_weighed: Dictionary = {} # person id -> game minutes since they last weighed everything up
var _loudest_then: Dictionary = {} # person id -> how loud their loudest need was when they did
var _prompted: Dictionary = {} # person id -> true: weigh everything up at the next turn, whatever
var _barred: Dictionary = {} # person id -> {activity id -> tick until which it is not tried}
var _last: Dictionary = {} # person id -> Brain.Decision
var _outcomes: Dictionary = {} # person id -> Reactions.Outcome: how they took the last thing they noticed
var _reacted: Array = [] # reactions not announced yet: [id, reaction, interpretation, stimulus, direct]
var _ground_version := -1 # the pathfinder's version when everyone's footing was last looked at
var _ground_tick := -1 # the tick the ground was last looked at
## The body's upkeep (hunger, cold, health) is seen to every so many game
## minutes, not at every turn: it changes slowly (person id -> minutes owed).
const UPKEEP_MINUTES := 5.0
var _upkeep: Dictionary = {}
## Each person's needs factors, worked out once a day: person id -> [day, factors].
var _decay_factors: Dictionary = {}
var _day_tick := -1 # (the day, worked out once a tick)
var _today := 0


func _init() -> void:
	for step: Array in [[WalkToStep.TYPE, WalkToStep.new()], [EatStep.TYPE, EatStep.new()],
			[DrinkStep.TYPE, DrinkStep.new()], [SleepStep.TYPE, SleepStep.new()], [WorkStep.TYPE, WorkStep.new()],
			[SocializeStep.TYPE, SocializeStep.new()], [RestStep.TYPE, RestStep.new()],
			[ReactStep.TYPE, ReactStep.new()], [TellStep.TYPE, TellStep.new()], [StoreStep.TYPE, StoreStep.new()],
			[HuntStep.TYPE, HuntStep.new()]]:
		_steps[String(step[0])] = step[1]
	# Building (M12.1): one handler, three kinds of step.
	var build := BuildStep.new()
	for type: StringName in [BuildStep.TYPE, BuildStep.FETCH, BuildStep.DELIVER, BuildStep.QUARRY, BuildStep.BREAK]:
		_steps[String(type)] = build
	var trading := TradeStep.new()
	for type: StringName in [TradeStep.LOAD, TradeStep.UNLOAD, TradeStep.CRAFT]:
		_steps[String(type)] = trading


## Takes charge of the people of a world.
func bind(context: AiContext) -> void:
	unbind()
	ctx = context
	if ctx == null:
		return
	ctx.movement.arrived.connect(_on_arrived)
	ctx.movement.blocked.connect(_on_blocked)
	ctx.people.person_removed.connect(_on_person_removed)
	for person in ctx.people.all_people():
		person.needs = Needs.sanitized(person.needs, person.id)
	# (Looked up now, while the world is being opened, not in the middle of a
	# frame when the first of them gets thirsty.)
	if ctx.start != null:
		ctx.places.water_tile(ctx.start.settlement_tile, ctx.now())


func unbind() -> void:
	if ctx != null:
		ctx.movement.arrived.disconnect(_on_arrived)
		ctx.movement.blocked.disconnect(_on_blocked)
		ctx.people.person_removed.disconnect(_on_person_removed)
	ctx = null
	_begun.clear()
	_since_think.clear()
	_since_weighed.clear()
	_loudest_then.clear()
	_prompted.clear()
	_barred.clear()
	looked_up.clear()
	_last.clear()
	_outcomes.clear()
	_reacted.clear()
	reactions = 0
	_ground_version = -1


# --- saving -------------------------------------------------------------------------------------

## What the behaviour of people keeps about the world, apart from the people
## themselves (their needs and plans are saved with them).
func to_dict() -> Dictionary:
	return {"visited": ctx.places.visited_cells() if ctx != null else []}


## Call after bind().
func from_dict(data: Dictionary) -> void:
	var visited: Variant = data.get("visited")
	if ctx != null and typeof(visited) == TYPE_ARRAY:
		ctx.places.set_visited_cells(visited)


# --- questions ----------------------------------------------------------------------------------

## What the person is doing (&"" = nothing decided).
static func activity_of(person: PersonData) -> StringName:
	return StringName(str(person.current_action.get("activity", "")))


static func reason_of(person: PersonData) -> StringName:
	return StringName(str(person.current_action.get("reason", "")))


## The step being carried out ({} if none).
static func current_step(person: PersonData) -> Dictionary:
	var steps: Variant = person.current_action.get("steps")
	var index := int(person.current_action.get("index", 0))
	if typeof(steps) != TYPE_ARRAY or index < 0 or index >= (steps as Array).size() \
			or typeof((steps as Array)[index]) != TYPE_DICTIONARY:
		return {}
	return (steps as Array)[index]


## How the person's last decision came out (null if they have not decided
## anything in this session). For the inspector.
func last_decision(person_id: int) -> Brain.Decision:
	return _last.get(person_id)


## How the person took the last thing they noticed (null if nothing in this
## session). For the inspector and tests.
func last_outcome(person_id: int) -> Reactions.Outcome:
	return _outcomes.get(person_id)


## How many people are doing what: activity id -> count.
func counts() -> Dictionary:
	var out := {}
	if ctx == null:
		return out
	for person in ctx.people.all_people():
		var activity := activity_of(person)
		out[activity] = int(out.get(activity, 0)) + 1
	return out


# --- running ------------------------------------------------------------------------------------

## Lets `minutes` of game time pass for everyone, now.
func step(minutes: float) -> void:
	if ctx == null or not enabled or minutes < 0.0:
		return
	if ctx.weather != null:
		ctx.weather.advance_to(ctx.now())
	if ctx.settlements != null:
		ctx.settlements.step(ctx.now())
	elif ctx.settlement != null:
		ctx.settlement.step(ctx.now())
	if ctx.fauna != null:
		ctx.fauna.advance_to(ctx.now())
	if ctx.relationships != null:
		ctx.relationships.settle(ctx.now())
	if ctx.lifecycle != null:
		ctx.lifecycle.advance_to(ctx.now())
	if ctx.culture != null:
		ctx.culture.advance_to(ctx.now())
	if ctx.construction != null:
		ctx.construction.advance_to(ctx.now())
	if ctx.planner != null and ctx.settlements == null:
		ctx.planner.advance_to(ctx.now())
	if ctx.traffic != null:
		ctx.traffic.advance_to(ctx.now())
	if ctx.migration != null:
		ctx.migration.advance_to(ctx.now())
	if ctx.trade != null:
		ctx.trade.advance_to(ctx.now())
	if ctx.governance != null:
		ctx.governance.advance_to(ctx.now())
	for person in ctx.people.all_people():
		live(person, minutes)
	announce()


## Lets `minutes` of game time pass for one person: their needs run down,
## what they are doing moves on, and — if they have been at it for
## `think_every` game minutes since they last looked up — they consider
## whether something else is more pressing.
func live(person: PersonData, minutes: float, think_every: float = -1.0) -> void:
	if ctx == null or not enabled:
		return
	ctx.enter(person)
	_live(person, minutes, think_every if think_every > 0.0 else float(Config.sim.think_ticks_tier3))


## How many ticks may pass between two turns of this person without anything
## being missed (see ActionStep.patience).
func patience(person: PersonData) -> int:
	var step_now := current_step(person)
	var handler := _handler(step_now)
	return handler.patience(step_now) if handler != null else 1


## Forgets the strokes of work (and reactions) not announced yet.
func discard_strokes() -> void:
	if ctx != null:
		ctx.strokes.clear()
		ctx.nudges.clear()
		ctx.bedtimes.clear()
	_reacted.clear()


## A person has noticed something (see PerceptionSystem; it is waiting in
## AiContext.perceptions). What happened to them they consider at once;
## anything else at their next turn, which comes at once.
func notice(person_id: int, direct: bool) -> void:
	var person := ctx.people.get_person(person_id) if ctx != null else null
	if person == null:
		return
	if not enabled:
		# Nobody is living: what happens now is not reacted to later.
		ctx.perceptions.erase(person_id)
		return
	if ctx.migration != null and not ctx.migration.journeys.is_empty() and ctx.migration.travelling(person_id):
		ctx.perceptions.erase(person_id)
		return
	if direct:
		ctx.enter(person)
		_consider_perceptions(person)
		_announce_reactions()
	else:
		prompted.emit(person_id)


## Makes a person look up from what they are doing at their next turn,
## whenever they last did (something happened that they should consider: the
## hook for perception, M5).
func prompt(person_id: int) -> void:
	_since_think[person_id] = INF
	_prompted[person_id] = true
	prompted.emit(person_id)


## Tells the world about the strokes of work done since the last call.
func announce() -> void:
	if ctx == null:
		return
	for stroke: Array in ctx.strokes:
		worked.emit(stroke[0], stroke[1], stroke[2])
	ctx.strokes.clear()
	if not ctx.kills.is_empty():
		var killed := ctx.kills.duplicate()
		ctx.kills.clear()
		for kill: Array in killed:
			hunted.emit(kill[0], kill[1])
	if not ctx.social_events.is_empty():
		var happened := ctx.social_events.duplicate()
		ctx.social_events.clear()
		for entry: Array in happened:
			social.emit(entry[0], entry[1], entry[2])
	if not ctx.ailments.is_empty():
		var ailing := ctx.ailments.duplicate()
		ctx.ailments.clear()
		for entry: Array in ailing:
			if entry[2]:
				fell_ill.emit(entry[0], entry[1])
			else:
				recovered.emit(entry[0], entry[1])
	if not ctx.bedtimes.is_empty():
		var asleep := ctx.bedtimes.duplicate()
		ctx.bedtimes.clear()
		for id: int in asleep:
			bedtime.emit(id)
	if not ctx.nudges.is_empty():
		var nudged := ctx.nudges.duplicate()
		ctx.nudges.clear()
		for id: int in nudged:
			prompted.emit(id)
	_announce_reactions()
	if ctx.memories != null:
		ctx.memories.advance(ctx.now())


func _announce_reactions() -> void:
	if _reacted.is_empty():
		return
	var told := _reacted.duplicate()
	_reacted.clear()
	for entry: Array in told:
		reacted.emit(entry[0], entry[1], entry[2], entry[3], entry[4])


## Makes a person decide now (dropping what they are doing if something else
## wins). Returns the decision.
func think(person: PersonData) -> Brain.Decision:
	ctx.enter(person)
	return _think(person, activity_of(person))


## Gives a person something to do, in place of whatever they were doing.
## `score` is how much spoke for it (what something else has to beat for the
## person to drop it).
func set_plan(person: PersonData, activity: StringName, reason: StringName, steps: Array, score: float = 0.0) -> void:
	ctx.enter(person)
	_note_change(person, activity, steps, reason)
	_drop(person)
	person.current_action = {"activity": String(activity), "reason": String(reason), "since": ctx.now(),
		"score": score, "steps": steps, "index": 0}
	_since_think[person.id] = 0.0
	activity_changed.emit(person.id, activity)
	_carry_on(person, 0.0)


## Writes what a person turns to into their day (see DayLog). Reactions are
## written by whoever knows what they are reacting to.
func _note_change(person: PersonData, activity: StringName, steps: Array, reason: StringName = &"") -> void:
	if ctx.day_log == null:
		return
	var now := ctx.now()
	var was_asleep := person.pose == PersonData.Pose.SLEEP
	var to_bed := false
	var detail := ""
	var other := 0
	for step: Variant in steps:
		if typeof(step) != TYPE_DICTIONARY:
			continue
		match str((step as Dictionary).get("type", "")):
			"sleep":
				to_bed = true
			"rest":
				if (step as Dictionary).has("shelter"):
					detail = "shelter_" + str((step as Dictionary)["shelter"])
				if (step as Dictionary).has("grave_of"):
					other = int((step as Dictionary)["grave_of"])
			"socialize":
				other = int((step as Dictionary).get("partner", 0))
			"work":
				if activity == &"work":
					detail = str((step as Dictionary).get("kind", ""))
			"eat":
				if bool((step as Dictionary).get("meal", false)):
					detail = "meal"
				elif (step as Dictionary).has("bush"):
					detail = "bush"
			"hunt":
				detail = "game"
			"store":
				if detail == "":
					detail = "haul" # only carrying something home
	if was_asleep and to_bed:
		return # (sleeping on)
	if was_asleep:
		ctx.day_log.note(person.id, now, DayLog.WAKE)
	if to_bed:
		# (Going home at night is going to bed — called to it or not.)
		var hour := ctx.clock.hour() if ctx.clock != null else 12.0
		ctx.day_log.note(person.id, now, "sleep", "" if SleepStep.is_bedtime_for(person, hour) else "nap")
		return
	if activity == ACTIVITY_REACT or activity == ACTIVITY_CALLED:
		return
	if activity == &"go_home" and reason == Brain.REASON_UNWELL:
		detail = "unwell" # (home to rest, hurt or ill)
	ctx.day_log.note(person.id, now, String(activity), detail, other)


## Calls people to stand around a spot (the debug call tool). Returns how many
## were given a place.
func call_to(ids: Array[int], tile: Vector2i) -> int:
	var places := ctx.pathfinder.standable_near(tile, ids.size())
	var called := 0
	for i in mini(ids.size(), places.size()):
		var person := ctx.people.get_person(ids[i])
		if person == null:
			continue
		set_plan(person, ACTIVITY_CALLED, ACTIVITY_CALLED,
			[WalkToStep.make(places[i], person.sub_tile_offset), RestStep.make(CALLED_MINUTES, tile)])
		called += 1
	return called


# --- internals ----------------------------------------------------------------------------------

func _live(person: PersonData, minutes: float, think_every: float) -> void:
	if person.needs.size() != Needs.COUNT:
		person.needs = Needs.sanitized(person.needs, person.id)
	var step_now := current_step(person)
	var handler := _handler(step_now)
	var config := Config.needs
	Needs.decay_by(person, minutes, config, _factors_of(person, config),
		handler.needs_state(step_now) if handler != null else Needs.State.AWAKE)
	# The ground changed (the water rose): whoever stands in water too deep steps
	# out of it at once. (Looked at once a tick, and whenever something changed.)
	if ctx.pathfinder != null and ctx.world != null:
		var tick := ctx.now()
		if tick != _ground_tick or ctx.pathfinder.dirty_count() > 0:
			_ground_tick = tick
			ctx.pathfinder.refresh_dirty()
			if ctx.pathfinder.version != _ground_version:
				_ground_version = ctx.pathfinder.version
				_step_out_of_water()
	var owed := float(_upkeep.get(person.id, 0.0)) + minutes
	if owed >= UPKEEP_MINUTES:
		_upkeep[person.id] = 0.0
		Hardship.live(person, ctx, owed)
		Exposure.live(person, ctx, owed)
		Health.live(person, ctx, owed)
	else:
		_upkeep[person.id] = owed
	# On the way to new land: nothing else takes their attention (M12.3).
	if ctx.migration != null and not ctx.migration.journeys.is_empty() and ctx.migration.travelling(person.id):
		_carry_on(person, minutes, step_now, handler)
		return
	# Whatever they have noticed comes before everything else.
	if not ctx.perceptions.is_empty() and _consider_perceptions(person):
		return
	if handler == null:
		_think(person, &"")
		return
	# Busy people look up from what they are doing now and then.
	_since_think[person.id] = float(_since_think.get(person.id, 0.0)) + minutes
	_since_weighed[person.id] = float(_since_weighed.get(person.id, 0.0)) + minutes
	if _since_think[person.id] >= think_every - THINK_SLACK:
		var before := activity_of(person)
		looked_up[person.id] = int(looked_up.get(person.id, 0)) + 1
		var prompted := _prompted.erase(person.id)
		# Someone called, or in the middle of reacting, is not asked what else they might do.
		var held := before == ACTIVITY_CALLED or before == ACTIVITY_REACT
		# Looking up, they may come upon something that was not there before.
		if not held and person.pose != PersonData.Pose.SLEEP and not person.has_flag(PersonData.FLAG_INDOORS) \
				and Discovery.look_around(person, ctx) and _consider_perceptions(person):
			return
		if not held and not prompted and ctx.activities.get_def(before) != null \
				and (_nothing_has_changed(person, think_every) or _nothing_could_matter_more(person, step_now, handler)):
			# A glance is enough: no need to weigh everything up.
			_since_think[person.id] = 0.0
			skipped += 1
		elif not held:
			_think(person, before)
			if activity_of(person) != before:
				return # something else now: it has been started
			_carry_on(person, minutes) # (what they do may have been planned anew)
			return
	_carry_on(person, minutes, step_now, handler)


## A person's needs factors (see Needs.factors), worked out once a game day.
func _factors_of(person: PersonData, config: NeedsConfig) -> PackedFloat32Array:
	var tick := ctx.now()
	if tick != _day_tick:
		_day_tick = tick
		_today = Config.time.day_index(tick)
	var day := _today
	var known: Variant = _decay_factors.get(person.id)
	if known != null and int(known[0]) == day:
		return known[1]
	var factor := Needs.factors(person, config, ctx.stage_of(person))
	_decay_factors[person.id] = [day, factor]
	return factor


## Since this person last weighed everything up: has too little time passed
## for the hour to matter, and has no need grown noticeably louder? Then the
## answer would be the same.
func _nothing_has_changed(person: PersonData, think_every: float) -> bool:
	if not _loudest_then.has(person.id) \
			or float(_since_weighed.get(person.id, INF)) >= think_every * Config.sim.relaxed_think_factor - THINK_SLACK:
		return false
	var loudest := ActivityDef.voice(1.0 - person.needs[Needs.most_urgent(person.needs)])
	return loudest < float(_loudest_then[person.id]) + LOUDER


## Could anything at all make this person drop what they are doing? Not if
## even the most that could speak for any activity, with their loudest need
## as loud as it is, stays below what it takes.
func _nothing_could_matter_more(person: PersonData, step_now: Dictionary, handler: ActionStep) -> bool:
	var loudest := ActivityDef.voice(1.0 - person.needs[Needs.most_urgent(person.needs)])
	var bar := float(person.current_action.get("score", 0.0)) + handler.reluctance(step_now) + Brain.HYSTERESIS
	# The routine's push goes to what is due — if that is what they are at
	# (or nothing is due), nothing else gets one.
	var due: StringName = Brain.due_now(person, ctx, ctx.clock.hour() if ctx.clock != null else 12.0)[0]
	return ctx.activities.ceiling(loudest, due != &"" and due != activity_of(person)) <= bar


## The person takes in what they have noticed (bible §14): the most striking
## of it is interpreted, felt, and reacted to — in place of whatever they
## were doing. Returns true if they are now reacting to it.
func _consider_perceptions(person: PersonData) -> bool:
	var pending: Variant = ctx.perceptions.get(person.id)
	if typeof(pending) != TYPE_ARRAY:
		return false
	ctx.perceptions.erase(person.id)
	var chosen: Dictionary = {}
	for perception: Dictionary in pending:
		if chosen.is_empty() or _outranks(perception, chosen):
			chosen = perception
	if chosen.is_empty():
		return false
	var table := Config.reactions
	var stimulus: Stimulus = chosen["stimulus"]
	# In the middle of reacting to something at least as striking, they do
	# not start over (but what happens to them always gets through).
	var busy_reacting := activity_of(person) == ACTIVITY_REACT and not bool(chosen.get("direct", false)) \
		and float(chosen.get("salience", 0.0)) <= float(person.current_action.get("salience", 0.0))
	var outcome: Reactions.Outcome = null
	if not busy_reacting:
		outcome = Reactions.respond(person, chosen, ctx, table)
	var second_hand := stimulus.type == Stimulus.TOLD
	var times_before := Interpretation.familiarity(person, stimulus.about if second_hand and stimulus.about != &"" else stimulus.type)
	# Each of them is an experience (counted after responding: "before" means before).
	for perception: Dictionary in pending:
		var seen: Stimulus = perception["stimulus"]
		Interpretation.note_experience(person, seen.about if seen.type == Stimulus.TOLD and seen.about != &"" else seen.type)
		# Whoever saw a thing lifted or land does not "find" it later.
		if seen.object_id != 0 and ctx.loose != null:
			var object := ctx.loose.get_object(seen.object_id)
			if object != null:
				Discovery.note(object, person.id)
	if outcome == null:
		return false
	# What was made of it is remembered (bible §15).
	if ctx.memories != null:
		var memory := MemoryStore.from_outcome(person, outcome, ctx.stage_of(person), times_before, ctx.now())
		if memory != null and outcome.recalled != null:
			Recognition.note(memory, outcome.recalled,
				Recognition.where_key(outcome.recalled.location, ctx.world, ctx.props, ctx.settlements))
		if memory != null:
			ctx.memories.remember(person, memory)
	# (A dream is no evidence of anything: it leaves convictions as they were.)
	if outcome.interpretation != ReactionTable.DREAM:
		Interpretation.update_beliefs(person, outcome.interpretation,
			lerpf(0.4, 1.0, outcome.salience) * (table.secondhand_factor if second_hand else 1.0), table)
	_outcomes[person.id] = outcome
	reactions += 1
	if outcome.steps.is_empty():
		if outcome.reaction == ReactionTable.STIR and ctx.day_log != null:
			ctx.day_log.note(person.id, ctx.now(), DayLog.STIR)
		return false
	set_plan(person, ACTIVITY_REACT, outcome.interpretation, outcome.steps)
	if ctx.day_log != null:
		# Whom they go to tell, or who told them.
		var with := stimulus.told_by if second_hand else 0
		for step: Variant in outcome.steps:
			if typeof(step) == TYPE_DICTIONARY and str((step as Dictionary).get("type", "")) == "tell":
				with = int((step as Dictionary).get("listener", 0))
		ctx.day_log.note(person.id, ctx.now(), DayLog.REACT,
			"%s:%s" % [outcome.reaction, "" if second_hand else String(stimulus.type)], with)
	person.current_action["reaction"] = String(outcome.reaction)
	person.current_action["stimulus"] = String(stimulus.about if second_hand else stimulus.type)
	person.current_action["salience"] = outcome.salience
	person.current_action["emotions"] = outcome.emotions.duplicate()
	if outcome.recalled != null:
		person.current_action["recalls"] = true
	if stimulus.type == Stimulus.TOUCH:
		person.set_flag(PersonData.FLAG_TOUCHED_BY_PLAYER, true)
	_reacted.append([person.id, outcome.reaction, outcome.interpretation,
		StringName(str(person.current_action["stimulus"])), outcome.direct])
	return true


## Is perception `a` more to the person than `b`? What happened to them comes
## first, then what stood out most.
static func _outranks(a: Dictionary, b: Dictionary) -> bool:
	var a_direct := bool(a.get("direct", false))
	if a_direct != bool(b.get("direct", false)):
		return a_direct
	return float(a.get("salience", 0.0)) > float(b.get("salience", 0.0))


## Is the person reacting to something of the player's they know again (VS.5)?
static func recognizes(person: PersonData) -> bool:
	return activity_of(person) == ACTIVITY_REACT and bool(person.current_action.get("recalls", false))


## What the person is doing about something they noticed (&"" if nothing).
static func reaction_of(person: PersonData) -> StringName:
	return StringName(str(person.current_action.get("reaction", ""))) if activity_of(person) == ACTIVITY_REACT else &""


## Carries the current step on; moves to the next when it is done; decides
## anew when the plan is finished or has failed.
func _carry_on(person: PersonData, minutes: float, known_step: Variant = null, known_handler: ActionStep = null) -> void:
	# (The step and its handler, when the caller has just looked them up.)
	var step_now: Dictionary = known_step if known_step != null else current_step(person)
	var handler := known_handler if known_step != null else _handler(step_now)
	if handler == null:
		return
	if not is_same(_begun.get(person.id), step_now):
		_begun[person.id] = step_now
		handler.begin(ctx, person, step_now)
	match handler.update(ctx, person, step_now, minutes):
		ActionStep.Status.DONE:
			handler.end(ctx, person, step_now)
			_begun.erase(person.id)
			if ctx.day_log != null and str(step_now.get("type", "")) == "sleep":
				ctx.day_log.note(person.id, ctx.now(), DayLog.WAKE) # (slept out)
			person.current_action["index"] = int(person.current_action.get("index", 0)) + 1
			if current_step(person).is_empty():
				_finish(person)
			else:
				_carry_on(person, 0.0) # begin the next step at once (set off, sit down)
		ActionStep.Status.FAILED:
			var failed := activity_of(person)
			# No way there: it is not chosen again for a while (nor set out for, and turned back from, over and over).
			if str(step_now.get("type", "")) == String(WalkToStep.TYPE) and typeof(step_now.get("target")) == TYPE_VECTOR2I \
					and not step_now.has("toward") and ctx.places != null:
				ctx.places.note_out_of_reach(step_now["target"])
			_drop(person)
			_bar(person.id, failed)
			_think(person, &"")


## The plan has run its course.
func _finish(person: PersonData) -> void:
	var activity := activity_of(person)
	if activity != &"":
		person.activity_log[String(activity)] = ctx.now()
	if StringName(activity) == &"explore":
		ctx.places.mark_visited(person.position)
	person.current_action = {}
	_think(person, &"")


func _think(person: PersonData, current: StringName) -> Brain.Decision:
	_since_think[person.id] = 0.0
	_since_weighed[person.id] = 0.0
	_loudest_then[person.id] = ActivityDef.voice(1.0 - person.needs[Needs.most_urgent(person.needs)]) \
		if person.needs.size() == Needs.COUNT else 0.0
	person.mood = Needs.mood(person.needs)
	person.stress = Needs.stress(person.needs)
	# Grief weighs on them (M10.3).
	if ctx.lifecycle != null and not person.conditions.is_empty():
		var grief := ctx.lifecycle.grief_of(person, ctx.now())
		person.mood = maxf(person.mood - Config.life.grief_mood * grief, 0.0)
		person.stress = maxf(person.stress, 0.3 * grief)
	# What they are doing counts as "current" only if it is something the
	# brain knows (not standing idle, not a plan that has just ended).
	var keeping := current if ctx.activities.get_def(current) != null and not current_step(person).is_empty() else &""
	var commitment := 0.0
	var reluctance := 0.0
	if keeping != &"":
		var step_now := current_step(person)
		commitment = float(person.current_action.get("score", 0.0))
		reluctance = _handler(step_now).reluctance(step_now)
	var decision := Brain.decide(person, ctx, keeping, _barred_now(person.id), commitment, reluctance)
	decisions += 1
	# Try what was decided; if it cannot be planned after all, the next best.
	for attempt in ctx.activities.size() + 1:
		_last[person.id] = decision
		if decision.activity == &"" or (keeping != &"" and decision.activity == keeping):
			break
		var steps := Planner.plan(decision.activity, person, ctx)
		if not steps.is_empty():
			set_plan(person, decision.activity, decision.reason, steps, decision.commitment_of(decision.activity))
			return decision
		_bar(person.id, decision.activity)
		decision = Brain.decide(person, ctx, keeping, _barred_now(person.id), commitment, reluctance)
	if keeping != &"":
		return decision # nothing better came of it: carry on
	# Nothing can be done: stand about for a while.
	if current_step(person).is_empty():
		set_plan(person, ACTIVITY_IDLE, &"routine", [RestStep.make(IDLE_MINUTES)])
	return decision


## Ends what the person is doing, leaving nothing behind.
func _drop(person: PersonData) -> void:
	var step_now := current_step(person)
	var handler := _handler(step_now)
	if handler != null:
		handler.end(ctx, person, step_now)
	_begun.erase(person.id)
	ctx.forget(person.id)
	person.current_action = {}
	person.pose = PersonData.Pose.IDLE
	person.emote = &""


func _handler(step_now: Dictionary) -> ActionStep:
	return _steps.get(str(step_now.get("type", ""))) if not step_now.is_empty() else null


func _bar(person_id: int, activity: StringName) -> void:
	if activity == &"":
		return
	if not _barred.has(person_id):
		_barred[person_id] = {}
	(_barred[person_id] as Dictionary)[activity] = ctx.now() + BARRED_MINUTES


func _barred_now(person_id: int) -> Dictionary:
	var out := {}
	var mine: Dictionary = _barred.get(person_id, {})
	for activity: StringName in mine.keys():
		if int(mine[activity]) > ctx.now():
			out[activity] = true
		else:
			mine.erase(activity)
	return out


func _on_arrived(person_id: int) -> void:
	ctx.note_walk(person_id, &"arrived")


func _on_blocked(person_id: int) -> void:
	ctx.note_walk(person_id, &"blocked")
	_rescue_if_stranded(person_id)


## Someone who cannot get anywhere because they stand where nobody can stand
## (the water rose around them, something was built on them) is put on the
## nearest ground that can be stood on. Rising water does that now and then
## (the river: M9.3) — they step back out of it; anything else should not
## happen, and is logged as a fault. Nobody is left standing there for ever.
func _rescue_if_stranded(person_id: int) -> void:
	var person := ctx.people.get_person(person_id)
	if person == null or ctx.pathfinder.can_stand(person.position):
		return
	var ground := ctx.pathfinder.standable_near(person.position, 1, STRANDED_SEARCH)
	if ground.is_empty():
		return
	if ctx.world != null and ctx.world.get_water(person.position) > Pathfinder.WADE_DEPTH * ctx.world.height_step:
		waded_out += 1
	else:
		Log.warn(Log.Category.AI, "Someone was stranded and has been moved to firm ground",
			{"person": person.full_name(), "from": person.position, "to": ground[0]})
		rescues += 1
	ctx.people.move(person_id, ground[0], Vector2(0.5, 0.5), person.facing)


## The water rose around people who stood still (drinking at the shore,
## working, waiting): they step out of it — at once, not when they next look up.
func _step_out_of_water() -> void:
	var deep := Pathfinder.WADE_DEPTH * ctx.world.height_step
	for person in ctx.people.all_people():
		if not person.has_flag(PersonData.FLAG_INDOORS) and ctx.world.get_water(person.position) > deep:
			_rescue_if_stranded(person.id)


func _on_person_removed(person_id: int) -> void:
	if ctx != null and ctx.day_log != null:
		ctx.day_log.forget(person_id)
	_begun.erase(person_id)
	_upkeep.erase(person_id)
	_decay_factors.erase(person_id)
	_since_think.erase(person_id)
	_since_weighed.erase(person_id)
	_loudest_then.erase(person_id)
	_prompted.erase(person_id)
	_barred.erase(person_id)
	looked_up.erase(person_id)
	_last.erase(person_id)
	_outcomes.erase(person_id)
	ctx.perceptions.erase(person_id)
	ctx.forget(person_id)
