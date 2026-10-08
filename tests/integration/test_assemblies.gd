extends TestCase
## FC7: disputes and revolutions, seen. A dispute: the leaders (each with one
## of their own) meet halfway, talk, argue, go home — staged the next
## morning, let go if long missed. A revolution: a crowd at the fire round
## the deposed leader, yelling; the new one steps forward.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440

var session: WorldSession
var assemblies: Assemblies


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	assemblies = session.assemblies
	for person in session.people.all_people():
		person.set_flag(PersonData.FLAG_INDOORS, false)
		person.pose = PersonData.Pose.IDLE


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


func _second() -> Settlement:
	var first := session.settlement
	var fire := first.fire().tile
	for dy in range(-28, 29, 2):
		for dx in range(-28, 29, 2):
			first.places().mark_visited(fire + Vector2i(dx, dy))
	while first.member_count() < 14:
		var a := session.spawn_person(fire + Vector2i(1, 1))
		var b := session.spawn_person(fire + Vector2i(1, 1))
		a.sex = PersonData.Sex.MALE
		b.sex = PersonData.Sex.FEMALE
		session.households.form_couple(a, b, session.clock.tick, session.ids.next_id())
	var journey := session.migration.depart(first, session.clock.tick)
	assert_false(journey.is_empty())
	var second := session.migration.found(journey, session.clock.tick)
	for person in session.people.all_people():
		person.set_flag(PersonData.FLAG_INDOORS, false)
		person.pose = PersonData.Pose.IDLE
	return second


func _at_hour(hour: float, day: int = 1) -> void:
	session.clock.tick = day * DAY + roundi((hour - Config.time.start_hour) * 60.0)
	assemblies._last = -1_000_000


func test_a_dispute_is_staged_in_the_morning() -> void:
	var second := _second()
	var first := session.settlement
	_at_hour(1.0)
	assemblies.dispute(first.id, second.id, session.clock.tick)
	assemblies.advance_to(session.clock.tick)
	assert_eq(assemblies.pending().size(), 1, "not in the night")
	_at_hour(9.0)
	assemblies.advance_to(session.clock.tick)
	assert_eq(assemblies.pending().size(), 0, "staged in the morning")
	var went := 0
	var argued := false
	for person in session.people.all_people():
		if str(person.current_action.get("reason")) == String(Assemblies.REASON):
			went += 1
			for step: Dictionary in person.current_action["steps"]:
				argued = argued or str(step.get("emote", "")) == String(Signs.ANGRY)
	assert_true(went >= 2 and went <= 4, "a few from each side (%d)" % went)
	assert_true(argued, "and they argue")


func test_long_missed_is_let_go() -> void:
	var second := _second()
	_at_hour(1.0)
	assemblies.dispute(session.settlement.id, second.id, session.clock.tick)
	_at_hour(9.0, 4)
	assemblies.advance_to(session.clock.tick)
	assert_eq(assemblies.pending().size(), 0)
	for person in session.people.all_people():
		assert_ne(str(person.current_action.get("reason")), String(Assemblies.REASON), "nobody goes out over it")


func test_a_revolution_is_a_crowd_at_the_fire() -> void:
	var own := session.settlement
	var deposed := own.members()[0]
	var crowd := assemblies.stage_revolution(own.id, deposed.id)
	assert_true(crowd.size() >= 2, "a crowd (%d)" % crowd.size())
	for person in crowd:
		var steps: Array = person.current_action["steps"]
		assert_eq(int(steps[-1]["pose"]), int(PersonData.Pose.YELL))
		assert_eq(str(steps[-1]["emote"]), String(Signs.ANGRY))
	assert_eq(int((deposed.current_action["steps"] as Array)[-1]["pose"]), int(PersonData.Pose.SHRUG), "the deposed shrugs")


func test_saved_and_restored() -> void:
	assemblies.dispute(3, 4, 100)
	var again := Assemblies.new()
	again.from_dict(assemblies.to_dict())
	assert_eq(again.pending().size(), 1)
	assert_eq(again.pending()[0][0], Assemblies.DISPUTE)
