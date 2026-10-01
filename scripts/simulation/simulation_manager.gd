class_name SimulationManager
extends Node
## Makes the world's time pass for its people (bible §9.3, §31.6): turns each
## frame into game time, lets everyone live it in whole ticks at the cadence
## of their tier, and keeps all of that inside a budget.
##
## Per frame:
##   1. the clock advances (ticks = game minutes);
##   2. people whose turn it is live the time that has built up for them —
##      needs, actions, and now and then a look up from what they are doing;
##   3. queued path requests are answered;
##   4. whoever is walking is moved on (each walker every few frames; their
##      views glide in between, so walking is smooth).
##
## **Staggered:** people do not all take their turn in the same frame; each
## has their own place in the tick. **Budgeted:** when the time for step 2 is
## used up, those who have not had their turn come first in the next frame.
## Nobody ever loses time — the minutes build up and are lived in one larger
## step — so the simulation degrades to coarser steps, never to slow motion.
##
## The session calls advance() once per frame.

var tiers := TierManager.new()

## For the debug overlay and tests.
var ticks_total := 0
## People who lived in the last frame / who were due but had to wait.
var last_lived := 0
var last_deferred := 0
var deferred_total := 0
## Time the last advance() took, and smoothed over about a second.
var last_usec := 0
var average_usec := 0.0
var worst_usec := 0
## The same average, by part: people living, paths, walking.
var average_live_usec := 0.0
var average_paths_usec := 0.0
var average_move_usec := 0.0

var _clock: GameClock
var _people: PersonRegistry
var _behavior: BehaviorSystem
var _pathfinder: Pathfinder
var _movement: MovementSystem
# Everyone, by id — the order of turns — with, at the same index, the game
# time of their next turn and the game time they have lived up to. (Arrays
# and absolute times: on a frame in which nobody is due, a person costs one
# comparison.)
var _order: Array[int] = []
var _next_turn := PackedFloat64Array()
var _lived_until := PackedFloat64Array()
var _cursor := 0
## Game minutes since the manager was bound.
var _now := 0.0


func bind(clock: GameClock, people: PersonRegistry, behavior: BehaviorSystem, pathfinder: Pathfinder,
		movement: MovementSystem) -> void:
	unbind()
	_clock = clock
	_people = people
	_behavior = behavior
	_pathfinder = pathfinder
	_movement = movement
	if behavior != null:
		behavior.prompted.connect(hurry)
		behavior.activity_changed.connect(_on_activity_changed)
	if people != null:
		people.person_added.connect(_on_person_added)
		people.person_removed.connect(_on_person_removed)
		for person in people.all_people():
			_enrol(person.id)
	tiers.bind(people)
	if not tiers.changed.is_connected(_on_tiers_changed):
		tiers.changed.connect(_on_tiers_changed)
	if not EventBus.person_selected.is_connected(_on_person_selected):
		EventBus.person_selected.connect(_on_person_selected)


func unbind() -> void:
	if _behavior != null:
		_behavior.prompted.disconnect(hurry)
		_behavior.activity_changed.disconnect(_on_activity_changed)
	if _people != null:
		_people.person_added.disconnect(_on_person_added)
		_people.person_removed.disconnect(_on_person_removed)
	tiers.unbind()
	_clock = null
	_people = null
	_behavior = null
	_pathfinder = null
	_movement = null
	_order.clear()
	_next_turn.clear()
	_lived_until.clear()
	_cursor = 0
	_now = 0.0


func _exit_tree() -> void:
	if EventBus.person_selected.is_connected(_on_person_selected):
		EventBus.person_selected.disconnect(_on_person_selected)


## Lets `delta` real seconds pass. Returns the whole ticks that elapsed.
func advance(delta: float) -> int:
	if _clock == null:
		return 0
	var started := Time.get_ticks_usec()
	var ticks := _clock.advance(delta)
	var minutes := _clock.last_advance_minutes
	last_lived = 0
	last_deferred = 0
	if minutes > 0.0:
		ticks_total += ticks
		tiers.refresh()
		_live(minutes, started)
		var lived := Time.get_ticks_usec()
		var whole := int(Config.perf.sim_budget_ms_per_frame * 1000.0)
		_pathfinder.serve(clampi(whole - (lived - started), 0, int(Config.perf.path_budget_ms_per_frame * 1000.0)))
		var served := Time.get_ticks_usec()
		_movement.step_in_turns(minutes)
		average_live_usec = lerpf(average_live_usec, float(lived - started), 0.03)
		average_paths_usec = lerpf(average_paths_usec, float(served - lived), 0.03)
		average_move_usec = lerpf(average_move_usec, float(Time.get_ticks_usec() - served), 0.03)
	last_usec = Time.get_ticks_usec() - started
	average_usec = lerpf(average_usec, float(last_usec), 0.03)
	worst_usec = maxi(worst_usec, last_usec)
	return ticks


## Game minutes that have built up for a person and are not lived yet.
func pending_minutes(person_id: int) -> float:
	var index := _order.find(person_id)
	return _now - _lived_until[index] if index >= 0 else 0.0


func reset_stats() -> void:
	ticks_total = 0
	deferred_total = 0
	worst_usec = 0
	average_usec = 0.0


# --- internals ----------------------------------------------------------------------------------

func _live(minutes: float, started: int) -> void:
	_now += minutes
	if _behavior == null or not _behavior.enabled or _order.is_empty():
		# (Frozen: nobody lives this time, now or later.)
		for i in _lived_until.size():
			_lived_until[i] = _now
		return
	var budget := int(Config.sim.ai_budget_ms_per_frame * 1000.0)
	var count := _order.size()
	var first := _cursor % count
	var out_of_time := false
	for n in count:
		var index := first + n
		if index >= count:
			index -= count
		if _now < _next_turn[index]:
			continue
		if out_of_time:
			last_deferred += 1
			continue
		var person := _people.get_person(_order[index])
		if person == null:
			continue
		var due := _now - _lived_until[index]
		_lived_until[index] = _now
		_behavior.live(person, due, float(Config.sim.think_ticks(person.sim_tier)))
		# The next turn: after the interval of their tier — longer for someone
		# at something steady (a sleeper), never for someone in focus — and at
		# the person's own place in the tick.
		var interval := float(Config.sim.live_ticks(person.sim_tier))
		if Config.sim.patient_steps and person.sim_tier < TierManager.FOCUS:
			interval *= _behavior.patience(person)
		var behind := _now - _next_turn[index]
		_next_turn[index] += interval + floorf(behind)
		last_lived += 1
		_cursor = index + 1 # whoever comes after has the first turn next frame
		# Out of time: the rest wait (at least one person lives every frame).
		if Time.get_ticks_usec() - started >= budget:
			out_of_time = true
	deferred_total += last_deferred
	_behavior.announce()


## Gives a person their place in the order of turns.
func _enrol(id: int) -> void:
	var at := _order.bsearch(id)
	if at < _order.size() and _order[at] == id:
		return
	_order.insert(at, id)
	# Everyone has their own place in the tick, so that a band does not all
	# take its turn in the same frame.
	_next_turn.insert(at, _now + (1.0 - _place_in_tick(id)))
	_lived_until.insert(at, _now)
	if at < _cursor:
		_cursor += 1


## Where in their interval a person takes their turn (0 … 1): spreads people
## over the frames of a tick instead of all living in the same one.
static func _place_in_tick(person_id: int) -> float:
	return float(((person_id * 2654435761) >> 4) & 0xFF) / 256.0


func _on_person_added(id: int) -> void:
	_enrol(id)


func _on_person_removed(id: int) -> void:
	var at := _order.find(id)
	if at < 0:
		return
	_order.remove_at(at)
	_next_turn.remove_at(at)
	_lived_until.remove_at(at)
	if at < _cursor:
		_cursor -= 1


## Makes a person take their turn in the next frame (they have just been
## given something new to do, or something happened to them).
func hurry(person_id: int) -> void:
	var index := _order.find(person_id)
	if index >= 0:
		_next_turn[index] = minf(_next_turn[index], _now)


## Someone who has just been given something else to do (called, woken)
## gets on with it at once, however long their last step let them wait.
func _on_activity_changed(person_id: int, _activity: StringName) -> void:
	hurry(person_id)


## Someone who has come closer to the player is not left waiting out the long
## interval of the tier they were in.
func _on_tiers_changed() -> void:
	if _people == null:
		return
	for index in _order.size():
		var person := _people.get_person(_order[index])
		if person != null:
			_next_turn[index] = minf(_next_turn[index], _now + float(Config.sim.live_ticks(person.sim_tier)))


## The player selected someone (-1: nobody): they are simulated most closely.
func _on_person_selected(person_id: int) -> void:
	if person_id < 0:
		tiers.unfocus()
	else:
		tiers.focus(person_id)
