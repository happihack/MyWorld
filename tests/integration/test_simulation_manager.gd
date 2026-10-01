extends TestCase
## Time passing for people (M4.5): ticks, turns, tiers and the budget.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const YEAR := 1440 * 24
## One frame at 60 FPS and normal speed is a thirtieth of a game minute.
const FRAME := 1.0 / 60.0

var session: WorldSession
var sim: SimulationManager
var lived: Dictionary = {} # person id -> [minutes lived in each turn]


func before_each() -> void:
	SaveManager.attach(null)
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false) # the tests are the frames
	session.loose_system.set_process(false)
	session.water.set_process(false)
	sim = session.simulation
	lived.clear()


func after_each() -> void:
	Config.sim.patient_steps = true
	Config.sim.ai_budget_ms_per_frame = SimConfig.new().ai_budget_ms_per_frame
	Config.sim.tier3_cap_high = SimConfig.new().tier3_cap_high
	Config.sim.tier3_cap_low = SimConfig.new().tier3_cap_low
	session.queue_free()
	await wait_frames(1)


func _frames(count: int, delta: float = FRAME) -> void:
	for i in count:
		sim.advance(delta)


## Makes the band larger (copies of its people, with needs and natures of their own).
func _crowd(size: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var template := session.people.all_people()
	while session.people.size() < size:
		var like: PersonData = template[session.people.size() % template.size()]
		var p := PersonData.from_dict(like.to_dict())
		p.id = session.ids.next_id()
		p.traits = Traits.generate(rng)
		p.needs = Needs.initial(rng)
		p.current_action = {}
		p.position = session.pathfinder.standable_near(like.position + Vector2i(rng.randi_range(-3, 3), rng.randi_range(-3, 3)), 1)[0]
		session.people.add(p)


## Counts turns by watching hunger fall: it only changes when a person lives.
func _hunger() -> Dictionary:
	var out := {}
	for p in session.people.all_people():
		out[p.id] = p.needs[Needs.Need.HUNGER]
	return out


# --- ticks ----------------------------------------------------------------------------------------

func test_frames_become_ticks() -> void:
	assert_eq(session.clock.tick, 0)
	var ticks := 0
	for i in 61: # a second (and a frame) at normal speed
		ticks += sim.advance(FRAME)
	assert_eq(ticks, 2, "half a second a game minute")
	assert_eq(session.clock.tick, 2)
	assert_eq(sim.ticks_total, 2)
	session.clock.set_speed(GameClock.SPEED_VERY_FAST)
	ticks = 0
	for i in 60:
		ticks += sim.advance(FRAME)
	assert_eq(ticks, 32, "sixteen times as fast")
	assert_near(session.clock.last_advance_minutes, 16.0 / 30.0, 0.0001)
	# Paused: no time, nobody lives, nothing is counted.
	session.clock.set_speed(GameClock.SPEED_PAUSE)
	var before := session.people.to_dict()
	_frames(30)
	assert_eq(session.clock.tick, 34)
	assert_eq(sim.last_lived, 0)
	assert_eq(session.people.to_dict(), before, "the world stands still")
	# A manager that is not bound to anything does nothing.
	var idle := SimulationManager.new()
	assert_eq(idle.advance(1.0), 0)
	idle.free()


func test_everyone_lives_all_of_the_time_that_passes() -> void:
	Config.sim.patient_steps = false # (this test is about the tick: everyone every tick)
	for p in session.people.all_people():
		p.needs = Needs.full()
		session.behavior.set_plan(p, BehaviorSystem.ACTIVITY_CALLED, &"", [RestStep.make(10000.0)]) # (stand still)
	var before := _hunger()
	_frames(30 * 60) # an hour of game time
	var elapsed := session.clock.tick + session.clock.tick_fraction()
	assert_near(elapsed, 60.0, 0.01)
	for p in session.people.all_people():
		var body := Config.needs.body_factor(p.life_stage(session.clock.tick, YEAR, Config.people))
		var passed: float = (float(before[p.id]) - p.needs[Needs.Need.HUNGER]) / (Config.needs.hunger_per_minute * body)
		var total: float = passed + sim.pending_minutes(p.id)
		assert_near(total, elapsed, 0.02, "%s: %.2f minutes lived + %.2f waiting" % [p.given_name, passed, sim.pending_minutes(p.id)])
		assert_true(sim.pending_minutes(p.id) < 1.0, "never more than a tick behind")


func test_people_take_turns_within_a_tick() -> void:
	Config.sim.patient_steps = false
	_crowd(20)
	_frames(40) # let everyone find their place in the tick
	var most := 0
	var turns := {}
	var frames_with_nobody := 0
	for frame in 300: # ten ticks
		var before := _hunger()
		sim.advance(FRAME)
		var this_frame := 0
		for p in session.people.all_people():
			if p.needs[Needs.Need.HUNGER] != before[p.id]:
				this_frame += 1
				turns[p.id] = int(turns.get(p.id, 0)) + 1
		assert_eq(this_frame, sim.last_lived)
		most = maxi(most, this_frame)
		if this_frame == 0:
			frames_with_nobody += 1
	assert_true(most <= 5, "never the whole band in one frame (at most %d of 20)" % most)
	assert_true(frames_with_nobody > 0 and frames_with_nobody < 250, "spread over the frames of the tick")
	for p in session.people.all_people():
		assert_true(turns.get(p.id, 0) >= 9 and turns.get(p.id, 0) <= 11, "%s lived once a tick (%d turns in ten ticks)" % [p.given_name, turns.get(p.id, 0)])
	assert_eq(sim.deferred_total, 0, "nobody had to wait")


func test_at_great_speed_everyone_still_gets_their_turn() -> void:
	_crowd(20)
	session.clock.set_speed(GameClock.SPEED_VERY_FAST)
	for p in session.people.all_people():
		p.needs = Needs.full()
	var before := _hunger()
	_frames(451) # 240 game minutes
	assert_eq(session.clock.tick, 240)
	for p in session.people.all_people():
		assert_true(p.needs[Needs.Need.HUNGER] < before[p.id] or BehaviorSystem.activity_of(p) == &"eat")
		assert_true(sim.pending_minutes(p.id) <= session.behavior.patience(p) + 1.0, "never further behind than their step allows")
		assert_ne(BehaviorSystem.activity_of(p), &"")


# --- the budget -----------------------------------------------------------------------------------

func test_when_time_runs_out_the_rest_wait_and_lose_nothing() -> void:
	Config.sim.patient_steps = false
	_crowd(20)
	for p in session.people.all_people():
		p.needs = Needs.full()
		session.behavior.set_plan(p, BehaviorSystem.ACTIVITY_CALLED, &"", [RestStep.make(10000.0)])
	Config.sim.ai_budget_ms_per_frame = 0.0 # no time at all: one person a frame
	session.clock.set_speed(GameClock.SPEED_VERY_FAST) # and everyone due nearly every frame
	var before := _hunger()
	var worst_wait := 0.0
	for frame in 300:
		sim.advance(FRAME)
		assert_eq(sim.last_lived, 1, "at least one person lives every frame, and with no budget, exactly one")
		for p in session.people.all_people():
			worst_wait = maxf(worst_wait, sim.pending_minutes(p.id))
	assert_true(sim.deferred_total > 1000, "the others waited (%d times)" % sim.deferred_total)
	assert_true(sim.last_deferred >= 10)
	# Everyone had their turn, in turn: nobody waited much longer than a round takes.
	var round_minutes := 20.0 * session.clock.last_advance_minutes
	assert_true(worst_wait < round_minutes * 1.5 + 1.0, "longest wait %.1f game minutes (a round is %.1f)" % [worst_wait, round_minutes])
	# And no time was lost: what passed was lived, or is waiting to be.
	var elapsed := session.clock.tick + session.clock.tick_fraction()
	for p in session.people.all_people():
		var body := Config.needs.body_factor(p.life_stage(session.clock.tick, YEAR, Config.people))
		var passed: float = (float(before[p.id]) - p.needs[Needs.Need.HUNGER]) / (Config.needs.hunger_per_minute * body)
		assert_near(passed + sim.pending_minutes(p.id), elapsed, 0.05, "%s lost no time" % p.given_name)
	# With time to spare again, nobody waits.
	Config.sim.ai_budget_ms_per_frame = 50.0
	_frames(5)
	assert_eq(sim.last_deferred, 0)


func test_the_frame_stays_within_the_budget() -> void:
	# The M4 targets: 20 people, AI under 0.5 ms per frame on average.
	_crowd(20)
	_frames(30 * 30) # everyone gets going
	sim.reset_stats()
	var total := 0
	var over := 0
	var frames := 3000 # fifty seconds at normal speed
	for frame in frames:
		sim.advance(FRAME)
		total += sim.last_usec
		if sim.last_usec > int(Config.perf.sim_budget_ms_per_frame * 1000.0):
			over += 1
	var average_ms := total / float(frames) / 1000.0
	print("    simulation: 20 people, %.3f ms per frame on average, worst %.2f ms, %d frames of %d over the %.1f ms budget, %d waits" % [
		average_ms, sim.worst_usec / 1000.0, over, frames, Config.perf.sim_budget_ms_per_frame, sim.deferred_total])
	assert_true(average_ms < 0.5, "%.3f ms" % average_ms)
	assert_true(over <= frames / 100, "%d frames over budget" % over)
	assert_true(session.movement.walking_count() > 0 or session.behavior.decisions > 20, "and people did live")


# --- tiers ----------------------------------------------------------------------------------------

func test_everyone_is_active_until_someone_is_in_focus() -> void:
	var tiers := sim.tiers
	for p in session.people.all_people():
		assert_eq(p.sim_tier, TierManager.ACTIVE)
	assert_eq(tiers.counts(), {TierManager.ACTIVE: session.people.size()})
	var someone := session.people.all_people()[2]
	var changes := [0]
	tiers.changed.connect(func() -> void: changes[0] += 1)
	assert_true(tiers.focus(someone.id))
	assert_eq(someone.sim_tier, TierManager.FOCUS)
	assert_true(tiers.is_focused(someone.id))
	assert_eq(tiers.counts()[TierManager.ACTIVE], session.people.size() - 1)
	assert_eq(changes[0], 1)
	assert_false(tiers.focus(999_999), "nobody there")
	tiers.unfocus(someone.id)
	assert_eq(someone.sim_tier, TierManager.ACTIVE)
	assert_eq(tiers.focused().size(), 0)


func test_selecting_someone_puts_them_in_focus() -> void:
	var people := session.people.all_people()
	EventBus.person_selected.emit(people[0].id)
	assert_eq(people[0].sim_tier, TierManager.FOCUS)
	# One person is selected at a time; the focus has room for one more (someone followed).
	sim.tiers.focus(people[2].id)
	EventBus.person_selected.emit(people[1].id)
	EventBus.person_selected.emit(people[3].id)
	assert_eq(sim.tiers.focused(), [people[2].id, people[3].id] as Array[int], "whoever was selected is let go; others in focus stay")
	assert_eq(people[0].sim_tier, TierManager.ACTIVE)
	assert_eq(people[1].sim_tier, TierManager.ACTIVE)
	EventBus.person_selected.emit(-1)
	assert_eq(sim.tiers.focused(), [people[2].id] as Array[int])
	sim.tiers.unfocus()
	assert_eq(sim.tiers.focused().size(), 0)
	# Someone in focus who leaves the world leaves the focus.
	sim.tiers.focus(people[4].id)
	session.people.remove(people[4].id)
	assert_false(sim.tiers.is_focused(people[4].id))
	sim.advance(FRAME) # (and nothing trips over them)


func test_someone_in_focus_looks_up_more_often() -> void:
	Config.sim.patient_steps = false
	var people := session.people.all_people()
	var watched := people[0]
	var other := people[1]
	for p in [watched, other]:
		p.needs = Needs.full()
		p.needs[Needs.Need.HUNGER] = 0.4 # something on their mind: no relaxed pace
		session.behavior.set_plan(p, &"work", &"routine", [RestStep.make(10000.0)], 5.0)
	sim.tiers.focus(watched.id)
	session.behavior.looked_up.clear()
	_frames(30 * 30) # thirty ticks
	var often: int = session.behavior.looked_up.get(watched.id, 0)
	var seldom: int = session.behavior.looked_up.get(other.id, 0)
	assert_true(often >= 28 and often <= 31, "in focus: every tick (%d times in 30 ticks)" % often)
	assert_true(seldom >= 9 and seldom <= 11, "otherwise: every third (%d times)" % seldom)
	assert_eq(Config.sim.think_ticks(TierManager.FOCUS), 1)
	assert_eq(Config.sim.think_ticks(TierManager.ACTIVE), 3)
	assert_eq(Config.sim.think_ticks(TierManager.REGIONAL), 15)
	assert_eq(Config.sim.think_ticks(TierManager.DORMANT), 15)
	assert_eq(Config.sim.live_ticks(TierManager.ACTIVE), 1)


func test_a_look_up_is_a_glance_unless_something_has_changed() -> void:
	var person := session.people.all_people()[0]
	var behavior := session.behavior
	person.needs = PackedFloat32Array([0.45, 0.6, 0.9, 0.9, 0.9, 1.0]) # peckish, a little thirsty
	behavior.set_plan(person, &"work", &"routine", [WorkStep.make(&"fire", 0, person.position, 10000.0)], 0.4)
	behavior.think(person) # (weighed up now: this is where the glances start from)
	behavior.looked_up.clear()
	var decisions := behavior.decisions
	for minute in 12: # (only this person lives)
		session.clock.tick += 1
		behavior.live(person, 1.0, 3.0)
	assert_eq(behavior.looked_up.get(person.id, 0), 4, "a look up every third tick")
	assert_eq(behavior.decisions, decisions, "but nothing has changed: no weighing up")
	# Time passes: after a while everything is weighed up again anyway.
	for minute in 9:
		session.clock.tick += 1
		behavior.live(person, 1.0, 3.0)
	assert_eq(behavior.decisions, decisions + 1, "once in %d looks" % Config.sim.relaxed_think_factor)
	# A need suddenly grows louder: weighed up at the very next look.
	decisions = behavior.decisions
	person.needs[Needs.Need.THIRST] = 0.1
	for minute in 3:
		session.clock.tick += 1
		behavior.live(person, 1.0, 3.0)
	assert_true(behavior.decisions > decisions)
	assert_eq(BehaviorSystem.activity_of(person), &"drink")
	# Prompted (something happened to them): weighed up at their next turn.
	behavior.set_plan(person, &"work", &"routine", [WorkStep.make(&"fire", 0, person.position, 10000.0)], 5.0)
	behavior.think(person)
	decisions = behavior.decisions
	behavior.live(person, 1.0, 3.0)
	assert_eq(behavior.decisions, decisions)
	behavior.prompt(person.id)
	behavior.live(person, 1.0, 3.0)
	assert_eq(behavior.decisions, decisions + 1)


func test_beyond_the_cap_the_furthest_are_simulated_more_coarsely() -> void:
	_crowd(12)
	Config.sim.tier3_cap_high = 5
	Config.sim.tier3_cap_low = 3
	var tiers := sim.tiers
	var home := Vector2(session.start.settlement_tile)
	# Move a few people far away.
	var far: Array[int] = []
	var people := session.people.all_people()
	for i in 4:
		var tile := session.pathfinder.standable_near(session.start.settlement_tile + Vector2i(0, 18 + i), 1)[0]
		session.people.move(people[i].id, tile)
		far.append(people[i].id)
	tiers.interest = home
	tiers.focus(people[11].id)
	tiers.unfocus(people[11].id) # (any change makes the tiers be worked out again)
	assert_eq(tiers.counts()[TierManager.ACTIVE], 5)
	assert_eq(tiers.counts()[TierManager.REGIONAL], 7)
	for id in far:
		assert_eq(session.people.get_person(id).sim_tier, TierManager.REGIONAL, "far from where the player looks")
	# The player looks at the far ones: they come into full simulation.
	tiers.look_at(Vector2(people[0].position))
	tiers.refresh()
	for id in far:
		assert_eq(session.people.get_person(id).sim_tier, TierManager.ACTIVE)
	# Someone in focus does not count against the cap.
	tiers.focus(people[10].id)
	assert_eq(tiers.counts()[TierManager.FOCUS], 1)
	assert_eq(tiers.counts()[TierManager.ACTIVE], 5)
	# Low-end devices: a smaller cap.
	tiers.low_end = true
	tiers.unfocus()
	assert_eq(tiers.counts()[TierManager.ACTIVE], 3)
	assert_eq(Config.sim.tier3_cap(true), 3)
	# Looking around with everyone under the cap changes nothing.
	Config.sim.tier3_cap_low = 64
	tiers.unfocus()
	var changes := [0]
	tiers.changed.connect(func() -> void: changes[0] += 1)
	tiers.look_at(Vector2(500, 500))
	tiers.refresh()
	assert_eq(changes[0], 0)


func test_coarser_tiers_live_in_larger_steps_and_lose_nothing() -> void:
	Config.sim.patient_steps = false
	var people := session.people.all_people()
	for p in people:
		p.needs = Needs.full()
		session.behavior.set_plan(p, BehaviorSystem.ACTIVITY_CALLED, &"", [RestStep.make(10000.0)])
	Config.sim.tier3_cap_high = 4
	sim.tiers.interest = Vector2(session.start.settlement_tile)
	sim.tiers.unfocus()
	var coarse: PersonData = null
	var fine: PersonData = null
	for p in people:
		if p.sim_tier == TierManager.REGIONAL:
			coarse = p
		else:
			fine = p
	assert_not_null(coarse)
	var turns := {coarse.id: 0, fine.id: 0}
	var before := _hunger()
	for frame in 30 * 60: # sixty ticks
		var was := {coarse.id: coarse.needs[Needs.Need.HUNGER], fine.id: fine.needs[Needs.Need.HUNGER]}
		sim.advance(FRAME)
		for p: PersonData in [coarse, fine]:
			if p.needs[Needs.Need.HUNGER] != was[p.id]:
				turns[p.id] += 1
	assert_true(turns[fine.id] >= 58, "tier 3: every tick (%d turns)" % turns[fine.id])
	assert_true(turns[coarse.id] >= 3 and turns[coarse.id] <= 5, "tier 2: every fifteen (%d turns)" % turns[coarse.id])
	for p: PersonData in [coarse, fine]:
		var body := Config.needs.body_factor(p.life_stage(session.clock.tick, YEAR, Config.people))
		var passed: float = (float(before[p.id]) - p.needs[Needs.Need.HUNGER]) / (Config.needs.hunger_per_minute * body)
		assert_near(passed + sim.pending_minutes(p.id), session.clock.tick + session.clock.tick_fraction(), 0.05, "the same hour, in fewer steps")


func test_someone_at_something_steady_takes_fewer_larger_turns() -> void:
	var people := session.people.all_people()
	var sleeper := people[0]
	var walker := people[1]
	var watched := people[2]
	for p: PersonData in [sleeper, watched]:
		p.needs = Needs.full()
		p.needs[Needs.Need.SLEEP] = 0.2
		session.behavior.set_plan(p, &"sleep", &"sleep", [SleepStep.make()], 5.0)
	walker.needs = Needs.full()
	session.behavior.set_plan(walker, BehaviorSystem.ACTIVITY_CALLED, &"",
		[WalkToStep.make(session.pathfinder.standable_near(session.start.settlement_tile + Vector2i(0, 14), 1)[0])])
	sim.tiers.focus(watched.id) # (the player is looking at this sleeper)
	var turns := {sleeper.id: 0, walker.id: 0, watched.id: 0}
	var hunger := {}
	for p: PersonData in [sleeper, walker, watched]:
		hunger[p.id] = p.needs[Needs.Need.HUNGER]
	var asleep_from := sleeper.needs[Needs.Need.SLEEP]
	for frame in 30 * 30: # thirty ticks
		var was := {sleeper.id: sleeper.needs[Needs.Need.HUNGER], walker.id: walker.needs[Needs.Need.HUNGER],
			watched.id: watched.needs[Needs.Need.HUNGER]}
		sim.advance(FRAME)
		for p: PersonData in [sleeper, walker, watched]:
			if p.needs[Needs.Need.HUNGER] != was[p.id]:
				turns[p.id] += 1
	assert_true(turns[sleeper.id] >= 2 and turns[sleeper.id] <= 4, "a sleeper: every ten ticks (%d turns in thirty)" % turns[sleeper.id])
	assert_true(turns[walker.id] >= 28, "someone walking: every tick (%d turns)" % turns[walker.id])
	assert_true(turns[watched.id] >= 28, "someone the player watches: every tick, asleep or not (%d turns)" % turns[watched.id])
	# The sleeper's night is the same night: no time lost to the larger steps.
	var elapsed := session.clock.tick + session.clock.tick_fraction()
	var slept: float = (sleeper.needs[Needs.Need.SLEEP] - asleep_from) * Config.needs.full_sleep_minutes
	assert_near(slept + sim.pending_minutes(sleeper.id), elapsed, 0.05)
	assert_true(sim.pending_minutes(sleeper.id) < 10.0)
	assert_eq(session.behavior.patience(sleeper), 10)
	assert_eq(session.behavior.patience(walker), 1)
	# Called while asleep, they are up in the next frame, not ten ticks later.
	var spot := session.pathfinder.standable_near(session.start.settlement_tile + Vector2i(0, 5), 1)[0]
	var ids: Array[int] = [sleeper.id]
	session.behavior.call_to(ids, spot)
	assert_false(sleeper.has_flag(PersonData.FLAG_INDOORS))
	sim.advance(FRAME)
	sim.advance(FRAME)
	assert_true(session.movement.is_walking(sleeper.id), "on their way at once")
	var before := sleeper.world2d()
	_frames(10)
	assert_true(sleeper.world2d() != before)
	# Prompted, a sleeper takes their turn in the next frame too.
	session.behavior.set_plan(sleeper, &"sleep", &"sleep", [SleepStep.make()], 5.0)
	_frames(40)
	var looks: int = session.behavior.looked_up.get(sleeper.id, 0)
	session.behavior.prompt(sleeper.id)
	sim.advance(FRAME)
	assert_eq(session.behavior.looked_up.get(sleeper.id, 0), looks + 1)


func test_nobody_weighs_everything_up_when_nothing_could_matter_more() -> void:
	var library := session.activities
	# The ceiling really is one: no activity scores higher, for anyone, at any hour.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var person := session.people.all_people()[0]
	for i in 300:
		person.traits = Traits.generate(rng)
		person.needs = Needs.initial(rng)
		for need in Needs.COUNT:
			person.needs[need] = rng.randf()
		person.activity_log = {}
		session.clock.tick = rng.randi_range(0, 1439)
		var loudest := ActivityDef.voice(1.0 - person.needs[Needs.most_urgent(person.needs)])
		var decision := Brain.decide(person, session.behavior.ctx)
		for id: StringName in decision.scores:
			if float(decision.scores[id]) > library.ceiling(loudest) + 0.0001:
				fail("%s scores %.2f, above the ceiling %.2f" % [id, decision.scores[id], library.ceiling(loudest)])
	assert_true(library.ceiling(0.0) < 1.0, "with every need quiet, little speaks loudly (%.2f)" % library.ceiling(0.0))
	assert_true(library.ceiling(1.0) > 2.0)
	# A sleeper with nothing pressing does not weigh anything up ...
	session.clock.tick = 17 * 60 # eleven at night
	person.needs = Needs.full()
	person.needs[Needs.Need.SLEEP] = 0.3
	person.needs[Needs.Need.HUNGER] = 0.45 # (below half: they do look up at the quick pace)
	session.behavior.set_plan(person, &"sleep", &"sleep", [SleepStep.make()], 0.9)
	var decisions := session.behavior.decisions
	session.behavior.looked_up.clear()
	for minute in 60: # (only this person lives)
		session.clock.tick += 1
		session.behavior.live(person, 1.0, 3.0)
	assert_true(session.behavior.looked_up.get(person.id, 0) >= 15, "they looked up")
	assert_eq(session.behavior.decisions, decisions, "but had nothing to decide")
	assert_true(session.behavior.skipped >= 15)
	assert_eq(BehaviorSystem.activity_of(person), &"sleep")
	# ... until something does press.
	person.needs[Needs.Need.THIRST] = 0.0
	for minute in 4:
		session.behavior.live(person, 1.0, 3.0)
	assert_eq(BehaviorSystem.activity_of(person), &"drink")
	assert_true(session.behavior.decisions > decisions)


# --- the whole of it ------------------------------------------------------------------------------

func test_walking_is_smooth_whatever_the_turns() -> void:
	var person := session.people.all_people()[0]
	var target := session.pathfinder.standable_near(session.start.settlement_tile + Vector2i(0, 6), 1)[0]
	person.needs = Needs.full()
	session.behavior.set_plan(person, BehaviorSystem.ACTIVITY_CALLED, &"", [WalkToStep.make(target)]) # (the test says who walks)
	sim.advance(FRAME)
	for i in MovementSystem.STRIDE_FRAMES:
		sim.advance(FRAME)
	var from := person.world2d()
	var steps := 0
	var previous := from
	for frame in 60:
		sim.advance(FRAME)
		var moved := person.world2d().distance_to(previous)
		if moved > 0.0:
			steps += 1
			assert_true(moved < 0.06, "small steps (%.3f tiles)" % moved)
		previous = person.world2d()
	# A walker is moved every few frames, by all the time that passed: the
	# same distance as walking every frame, in fewer steps.
	assert_eq(steps, 60 / MovementSystem.STRIDE_FRAMES, "every %d frames" % MovementSystem.STRIDE_FRAMES)
	var speed := session.movement.speed_of(person, person.position)
	assert_near(person.world2d().distance_to(from), speed * 2.0, speed * 0.25, "two game minutes of walking in a second")


func test_the_session_runs_on_the_manager() -> void:
	session.set_process(true)
	session.clock.set_speed(GameClock.SPEED_VERY_FAST)
	await wait_real_ms(600)
	assert_true(session.clock.tick > 5)
	assert_true(sim.ticks_total > 5)
	assert_true(session.behavior.decisions >= session.people.size(), "everyone has decided something")
	for p in session.people.all_people():
		assert_ne(BehaviorSystem.activity_of(p), &"")
	# Freezing the AI freezes the people, not the clock.
	session.behavior.enabled = false
	var before := session.people.to_dict()
	var tick := session.clock.tick
	session.movement.stop_all()
	await wait_real_ms(200)
	assert_true(session.clock.tick > tick)
	assert_eq(session.people.to_dict(), before)
	# A new world in the same session: its own people take the turns.
	session.behavior.enabled = true
	session.create_new(777)
	session.clock.set_speed(GameClock.SPEED_VERY_FAST)
	await wait_real_ms(400)
	for p in session.people.all_people():
		assert_ne(BehaviorSystem.activity_of(p), &"", "%s of the new world lives" % p.given_name)
		assert_eq(p.sim_tier, TierManager.ACTIVE)


func test_sim_config_defaults() -> void:
	var config := SimConfig.new()
	assert_eq(config.validate().size(), 0)
	assert_eq(Config.sim.tier3_cap(false), 64)
	assert_eq(Config.sim.tier3_cap(true), 32)
	assert_eq(Config.sim.tier4_cap, 2)
	assert_near(Config.perf.sim_budget_ms_per_frame, 4.0)
	config.think_ticks_tier4 = 9
	config.tier3_cap_low = 100
	assert_eq(config.validate().size(), 2)
