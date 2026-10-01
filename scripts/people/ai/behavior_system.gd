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
## Stepped every frame with fractions of game minutes, but each person lives
## in whole game minutes (bible 9.3: needs and actions progress per sim tick),
## and not all in the same frame: at normal speed that is each person twice a
## second, one or two people per frame. Walking itself is the MovementSystem's
## and stays smooth. How often who thinks, and within what budget, becomes the
## SimulationManager's business in M4.5; here everyone who is busy looks up
## from what they are doing every THINK_MINUTES.

## A person's activity changed (&"" = nothing to do).
signal activity_changed(person_id: int, activity: StringName)
## A stroke of work that can be seen and heard: kind is "tree", "bush", "fire".
signal worked(person_id: int, kind: StringName, target_id: int)

## People live in steps of this many game minutes.
const TICK_MINUTES := 1.0
## Someone busy reconsiders this often (game minutes).
const THINK_MINUTES := 15.0
## Something that turned out not to be possible is not tried again for this long.
const BARRED_MINUTES := 30
## A person with nothing they can do stands about for this long before
## thinking again.
const IDLE_MINUTES := 10.0
## Being called (see call_to) keeps someone at the spot for this long.
const CALLED_MINUTES := 12.0

const ACTIVITY_CALLED := &"called"
const ACTIVITY_IDLE := &"idle"

## Off = everyone stands where they are (the debug "freeze AI").
var enabled := true
var ctx: AiContext
## For the debug overlay.
var decisions := 0
var last_step_usec := 0
## Smoothed over about a second of frames.
var average_step_usec := 0.0

var _steps: Dictionary = {} # step type (String) -> ActionStep
var _begun: Dictionary = {} # person id -> the step Dictionary begin() was called for
var _since_think: Dictionary = {} # person id -> game minutes since they last thought
var _pending: Dictionary = {} # person id -> game minutes not yet lived
var _barred: Dictionary = {} # person id -> {activity id -> tick until which it is not tried}
var _last: Dictionary = {} # person id -> Brain.Decision


func _init() -> void:
	for step: Array in [[WalkToStep.TYPE, WalkToStep.new()], [EatStep.TYPE, EatStep.new()],
			[DrinkStep.TYPE, DrinkStep.new()], [SleepStep.TYPE, SleepStep.new()], [WorkStep.TYPE, WorkStep.new()],
			[SocializeStep.TYPE, SocializeStep.new()], [RestStep.TYPE, RestStep.new()]]:
		_steps[String(step[0])] = step[1]


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


func unbind() -> void:
	if ctx != null:
		ctx.movement.arrived.disconnect(_on_arrived)
		ctx.movement.blocked.disconnect(_on_blocked)
		ctx.people.person_removed.disconnect(_on_person_removed)
	ctx = null
	_begun.clear()
	_since_think.clear()
	_pending.clear()
	_barred.clear()
	_last.clear()


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

## Lets `minutes` of game time pass for everyone.
func step(minutes: float) -> void:
	if ctx == null or not enabled or minutes < 0.0:
		return
	var started := Time.get_ticks_usec()
	for person in ctx.people.all_people():
		var due := float(_pending.get(person.id, _phase(person.id))) + minutes
		if due < TICK_MINUTES:
			_pending[person.id] = due
			continue
		_pending[person.id] = 0.0
		_live(person, due)
	for stroke: Array in ctx.strokes:
		worked.emit(stroke[0], stroke[1], stroke[2])
	ctx.strokes.clear()
	last_step_usec = Time.get_ticks_usec() - started
	average_step_usec = lerpf(average_step_usec, float(last_step_usec), 0.03)


## Makes a person decide now (dropping what they are doing if something else
## wins). Returns the decision.
func think(person: PersonData) -> Brain.Decision:
	return _think(person, activity_of(person))


## Gives a person something to do, in place of whatever they were doing.
## `score` is how much spoke for it (what something else has to beat for the
## person to drop it).
func set_plan(person: PersonData, activity: StringName, reason: StringName, steps: Array, score: float = 0.0) -> void:
	_drop(person)
	person.current_action = {"activity": String(activity), "reason": String(reason), "since": ctx.now(),
		"score": score, "steps": steps, "index": 0}
	_since_think[person.id] = 0.0
	activity_changed.emit(person.id, activity)
	_carry_on(person, 0.0)


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

func _live(person: PersonData, minutes: float) -> void:
	if person.needs.size() != Needs.COUNT:
		person.needs = Needs.sanitized(person.needs, person.id)
	var step_now := current_step(person)
	var handler := _handler(step_now)
	Needs.decay(person, minutes, Config.needs, ctx.stage_of(person),
		handler.needs_state(step_now) if handler != null else Needs.State.AWAKE)
	if handler == null:
		_think(person, &"")
		return
	# Busy people look up from what they are doing now and then.
	_since_think[person.id] = float(_since_think.get(person.id, _stagger(person.id))) + minutes
	if _since_think[person.id] >= THINK_MINUTES:
		var before := activity_of(person)
		if before != ACTIVITY_CALLED:
			_think(person, before)
			if activity_of(person) != before:
				return # something else now: it has been started
	_carry_on(person, minutes)


## Carries the current step on; moves to the next when it is done; decides
## anew when the plan is finished or has failed.
func _carry_on(person: PersonData, minutes: float) -> void:
	var step_now := current_step(person)
	var handler := _handler(step_now)
	if handler == null:
		return
	if not is_same(_begun.get(person.id), step_now):
		_begun[person.id] = step_now
		handler.begin(ctx, person, step_now)
	match handler.update(ctx, person, step_now, minutes):
		ActionStep.Status.DONE:
			handler.end(ctx, person, step_now)
			_begun.erase(person.id)
			person.current_action["index"] = int(person.current_action.get("index", 0)) + 1
			if current_step(person).is_empty():
				_finish(person)
			else:
				_carry_on(person, 0.0) # begin the next step at once (set off, sit down)
		ActionStep.Status.FAILED:
			var failed := activity_of(person)
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
	person.mood = Needs.mood(person.needs)
	person.stress = Needs.stress(person.needs)
	# What they are doing counts as "current" only if it is something the
	# brain knows (not standing idle, not a plan that has just ended).
	var keeping := current if ctx.activities.get_def(current) != null and not current_step(person).is_empty() else &""
	var commitment := 0.0
	if keeping != &"":
		var step_now := current_step(person)
		commitment = float(person.current_action.get("score", 0.0)) + _handler(step_now).reluctance(step_now)
	var decision := Brain.decide(person, ctx, keeping, _barred_now(person.id), commitment)
	decisions += 1
	# Try what was decided; if it cannot be planned after all, the next best.
	for attempt in ctx.activities.size() + 1:
		_last[person.id] = decision
		if decision.activity == &"" or (keeping != &"" and decision.activity == keeping):
			break
		var steps := Planner.plan(decision.activity, person, ctx)
		if not steps.is_empty():
			set_plan(person, decision.activity, decision.reason, steps, decision.score_of(decision.activity))
			return decision
		_bar(person.id, decision.activity)
		decision = Brain.decide(person, ctx, keeping, _barred_now(person.id), commitment)
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


## Where in the tick a person lives (0 … TICK_MINUTES): spreads the band
## over the frames of a tick.
func _phase(person_id: int) -> float:
	return float(((person_id * 2654435761) >> 4) & 0xFF) / 256.0 * TICK_MINUTES


## So that a band does not all look up in the same minute.
func _stagger(person_id: int) -> float:
	return float((person_id * 2654435761) & 0xFF) / 255.0 * THINK_MINUTES


func _on_arrived(person_id: int) -> void:
	ctx.note_walk(person_id, &"arrived")


func _on_blocked(person_id: int) -> void:
	ctx.note_walk(person_id, &"blocked")


func _on_person_removed(person_id: int) -> void:
	_begun.erase(person_id)
	_since_think.erase(person_id)
	_pending.erase(person_id)
	_barred.erase(person_id)
	_last.erase(person_id)
	ctx.forget(person_id)
