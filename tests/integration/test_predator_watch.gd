extends TestCase
## PR2: seen and feared. Whoever sees a big predator — and anyone it is close
## to — runs for the fire, shouting; the first sighting of a beast is told to
## the player; while it is about the children and the old are called back;
## it is seen from further by day than by night; and if it goes back to the
## wilds after being seen, that is told too.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440

var session: WorldSession
var watch: PredatorWatch
var fauna: AnimalSystem
var own: Settlement


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	watch = session.predators
	fauna = session.fauna
	own = session.settlement


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


## Noon (or `hour`) of a spring day in the third year.
func _at_hour(hour: float) -> void:
	session.clock.tick = Config.time.ticks_per_year() * 2 + 2 * DAY + roundi((hour - Config.time.start_hour) * 60.0)
	fauna.last_tick = session.clock.tick


## Someone grown, out of doors, `distance` tiles from the fire (the others indoors).
func _out_there(distance: float) -> PersonData:
	var out: PersonData = null
	for person in own.members():
		if out == null and session.behavior.ctx.stage_of(person) == PersonData.LifeStage.ADULT:
			out = person
		else:
			person.set_flag(PersonData.FLAG_INDOORS, true)
	out.set_flag(PersonData.FLAG_INDOORS, false)
	var tile := own.fire().tile + Vector2i(roundi(distance), 0)
	var ground := session.pathfinder.standable_near(tile, 1, 4)
	session.people.move(out.id, ground[0] if not ground.is_empty() else tile)
	return out


func _look() -> void:
	watch.advance_to(session.clock.tick + PredatorWatch.CHECK_MINUTES)


func test_seen_feared_and_told() -> void:
	_at_hour(12.0)
	var person := _out_there(14.0)
	var told := []
	watch.spotted.connect(func(kind: StringName, _group: int, _at: Vector2, by_id: int, _sid: int) -> void: told.append([kind, by_id]))
	var bear: AnimalData = fauna.bring(&"bear", person.world2d() + Vector2(6.0, 0.0), session.clock.tick)[0]
	_look()
	assert_eq(told, [[&"bear", person.id]], "seen, by them")
	assert_eq(str(person.current_action.get("reason")), String(PredatorWatch.REASON_RUN), "running")
	var steps: Array = person.current_action["steps"]
	assert_eq(str(steps[-1]["type"]), "walk_to")
	assert_true(Vector2(steps[-1]["target"] - own.fire().tile).length() <= 2.0, "for the fire")
	assert_near(float(steps[-1].get("pace", 1.0)), PredatorWatch.RUN_PACE, 0.001)
	assert_true(watch.alarm(own.id), "the alarm is up")
	# Told to the player, once.
	var events := session.events.of_type(Chronicler.TYPE_PREDATOR_SPOTTED)
	assert_eq(events.size(), 1)
	assert_eq(EventText.text(events[0]), "A bear has been seen near %s — a hunting party is gathering" % own.display_name())
	session.clock.tick += 30
	_look()
	assert_eq(told.size(), 1, "not told again")
	assert_true(DayLogText.text(session.day_log.of(person.id)[-1]).contains("bear"), "in their day")
	assert_true(bear != null)


func test_seen_from_further_by_day() -> void:
	_at_hour(12.0)
	var person := _out_there(14.0)
	fauna.bring(&"wolf", person.world2d() + Vector2(PredatorWatch.SIGHT_NIGHT + 3.0, 0.0), session.clock.tick)
	var told := []
	watch.spotted.connect(func(_k: StringName, _g: int, _a: Vector2, _b: int, _s: int) -> void: told.append(1))
	_at_hour(23.0)
	_look()
	assert_eq(told.size(), 0, "not seen in the dark")
	_at_hour(12.0)
	session.clock.tick += DAY
	_look()
	assert_eq(told.size(), 1, "seen by day")


func test_the_children_are_called_back() -> void:
	_at_hour(12.0)
	var person := _out_there(14.0)
	fauna.bring(&"lion", person.world2d() + Vector2(5.0, 0.0), session.clock.tick)
	var child: PersonData = null
	for other in own.members():
		if session.behavior.ctx.stage_of(other) == PersonData.LifeStage.CHILD:
			child = other
	if child == null:
		child = session.spawn_person(own.fire().tile, PersonData.LifeStage.CHILD)
	child.set_flag(PersonData.FLAG_INDOORS, false)
	var far: Array[Vector2i] = []
	for way: Vector2i in [Vector2i(0, -16), Vector2i(0, 16), Vector2i(-16, 0), Vector2i(16, 0), Vector2i(12, 12), Vector2i(-12, -12)]:
		far = session.pathfinder.standable_near(own.fire().tile + way, 1, 4)
		if not far.is_empty():
			break
	assert_false(far.is_empty(), "somewhere out there to be")
	session.people.move(child.id, far[0])
	_look()
	assert_eq(str(child.current_action.get("reason")), String(PredatorWatch.REASON_KEEP_NEAR), "called back near the fire")


func test_gone_back_to_the_wilds_is_told() -> void:
	_at_hour(12.0)
	var person := _out_there(14.0)
	var boar: AnimalData = fauna.bring(&"boar", person.world2d() + Vector2(6.0, 0.0), session.clock.tick)[0]
	_look()
	var until := fauna.stays_until(boar.group)
	while fauna.count(&"boar") > 0 and session.clock.tick <= until + 3 * DAY:
		session.clock.tick += DAY
		fauna.skip_to(session.clock.tick)
	assert_eq(fauna.count(&"boar"), 0)
	assert_eq(session.events.of_type(Chronicler.TYPE_PREDATOR_GONE).size(), 1, "told it has gone")
	_look()
	assert_false(watch.alarm(own.id), "and the alarm is down")


func test_saved_and_restored() -> void:
	_at_hour(12.0)
	var person := _out_there(14.0)
	var bear: AnimalData = fauna.bring(&"bear", person.world2d() + Vector2(6.0, 0.0), session.clock.tick)[0]
	_look()
	var again := PredatorWatch.new()
	again.from_dict(watch.to_dict())
	assert_eq(again.known(bear.group).get("species"), &"bear")
	assert_eq(int(again.known(bear.group)["by"]), person.id)


# --- attacks (PR3) ---------------------------------------------------------------------------------

func test_an_attack_wounds_and_is_told() -> void:
	_at_hour(12.0)
	var person := _out_there(14.0)
	var bear: AnimalData = fauna.bring(&"bear", person.world2d() + Vector2(5.0, 0.0), session.clock.tick)[0]
	var health := person.health
	var heard := []
	watch.attacked.connect(func(id: int, kind: StringName, severity: float, killed: bool, _sid: int) -> void:
		heard.append([id, kind, severity, killed]))
	watch.attack(bear, person, session.clock.tick)
	assert_eq(heard.size(), 1)
	assert_eq(heard[0][0], person.id)
	assert_true(person.health < health, "hurt")
	assert_eq(str((person.injuries[-1] as Dictionary)["kind"]), String(Health.MAULED))
	if not bool(heard[0][3]):
		assert_eq(str(person.current_action.get("reason")), String(PredatorWatch.REASON_RUN), "and running for the fire")
	assert_eq(bear.state, AnimalData.State.FLEE, "it makes off")
	var told := session.events.of_type(Chronicler.TYPE_MAULED)
	assert_eq(told.size(), 1)
	assert_eq(EventText.text(told[0], session.people), "%s was attacked by a bear near %s" % [person.given_name, own.display_name()])
	assert_true(watch.alarm(own.id), "and now they know of it")


func test_only_the_lone_are_gone_for() -> void:
	_at_hour(12.0)
	var person := _out_there(14.0)
	var wolf: AnimalData = fauna.bring(&"wolf", person.world2d() + Vector2(6.0, 0.0), session.clock.tick)[0]
	assert_eq(watch._lone_one_near(wolf), person, "alone")
	var friend: PersonData = null
	for other in own.members():
		if other != person and session.behavior.ctx.stage_of(other) == PersonData.LifeStage.ADULT:
			friend = other
			break
	friend.set_flag(PersonData.FLAG_INDOORS, false)
	session.people.move(friend.id, person.position)
	assert_null(watch._lone_one_near(wolf), "not two together")
	assert_true(PredatorWatch.hour_factor(&"wolf", 23.0) > PredatorWatch.hour_factor(&"wolf", 12.0), "wolves by night")
	assert_true(PredatorWatch.hour_factor(&"lion", 18.0) > PredatorWatch.hour_factor(&"lion", 12.0), "the lion at dusk")


func test_killed_by_a_beast_is_told_so() -> void:
	_at_hour(12.0)
	var person := _out_there(14.0)
	var name := person.given_name
	var lion: AnimalData = fauna.bring(&"lion", person.world2d() + Vector2(5.0, 0.0), session.clock.tick)[0]
	watch.attack(lion, person, session.clock.tick)
	# (Gravely hurt by a beast, they may die of it: of the beast.)
	person.injuries = [{"kind": String(Health.MAULED), "severity": 0.95, "initial": 0.95, "took": 0.4, "since": session.clock.tick}]
	var odds: Array = session.lifecycle.death_chance(person, session.clock.tick)
	assert_true((odds[1] as Dictionary).has(Lifecycle.CAUSE_MAULED), "of the beast's wounds")
	if session.people.has_person(person.id):
		session.lifecycle.die(person, Lifecycle.CAUSE_MAULED, session.clock.tick)
	var died := session.events.of_type(Chronicler.TYPE_DIED)
	assert_eq(EventText.text(died[-1], session.people), "%s was killed by a mountain lion" % name)


func test_drowned_is_told_so() -> void:
	var person := own.members()[0]
	var name := person.given_name
	session.lifecycle.die(person, Lifecycle.CAUSE_DROWNED, session.clock.tick)
	assert_eq(EventText.text(session.events.of_type(Chronicler.TYPE_DIED)[-1], session.people), "%s has drowned" % name)
