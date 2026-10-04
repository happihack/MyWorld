extends TestCase
## M16.1: what people know — ten domains, held by people, learned from work,
## curiosity, watching, lessons, what goes wrong and the player's doing; a
## settlement knows what its most knowing member does; lost with whoever dies
## untaught (unless written down).

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var session: WorldSession
var learning: Knowledge


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	learning = session.learning


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


func _with(occupation: StringName) -> PersonData:
	for person in session.settlement.members():
		if person.occupation_id == occupation:
			return person
	return null


func _clear_all() -> void:
	for person in session.people.all_people():
		person.knowledge.erase(Knowledge.KEY)


func test_the_day_teaches() -> void:
	_clear_all()
	var now := session.clock.tick
	for day in 24:
		learning.each_day(now + day * TimeConfig.MINUTES_PER_DAY)
	var farmer := _with(&"farmer")
	assert_not_null(farmer)
	assert_true(Knowledge.points(farmer, Knowledge.Domain.AGRICULTURE) > 8.0, "a year of farming teaches growing food")
	assert_true(Knowledge.points(farmer, Knowledge.Domain.AGRICULTURE) > Knowledge.points(farmer, Knowledge.Domain.CONSTRUCTION))
	for person in session.settlement.members():
		assert_true(Knowledge.points(person, Knowledge.Domain.SOCIAL) > 0.0, "everyone learns living together")
	# Children watch their household.
	var child: PersonData = null
	for person in session.settlement.members():
		if session.behavior.ctx.stage_of(person) == PersonData.LifeStage.CHILD and person.household_id != 0:
			child = person
	if child != null:
		assert_true(Knowledge.points(child, Knowledge.Domain.NATURE) > 0.0, "a child learns by watching")
	# Never more than the most, and slower as it is neared.
	var p := PersonData.new()
	Knowledge.add(p, Knowledge.Domain.CRAFT, 500.0)
	assert_true(Knowledge.points(p, Knowledge.Domain.CRAFT) <= Knowledge.MOST)
	var q := PersonData.new()
	assert_near(Knowledge.add(q, Knowledge.Domain.CRAFT, 10.0), 10.0, 0.001)
	assert_true(Knowledge.add(q, Knowledge.Domain.CRAFT, 10.0) < 10.0, "less as more is known")


func test_a_settlement_knows_what_its_most_knowing_member_knows() -> void:
	var a := PersonData.new()
	var b := PersonData.new()
	var c := PersonData.new()
	a.knowledge[Knowledge.KEY] = PackedFloat32Array([40, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	b.knowledge[Knowledge.KEY] = PackedFloat32Array([10, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	c.knowledge[Knowledge.KEY] = PackedFloat32Array([10, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	assert_near(Knowledge.together([a, b, c], Knowledge.Domain.NATURE), 40.0 + 20.0 * Knowledge.OTHERS_SHARE, 0.001)
	assert_eq(Knowledge.together([], Knowledge.Domain.NATURE), 0.0)
	# A lesson: the learner takes some of what the teacher knows best.
	assert_eq(Knowledge.teach(a, b), Knowledge.Domain.NATURE)
	assert_near(Knowledge.points(b, Knowledge.Domain.NATURE), 10.0 + 30.0 * Knowledge.TEACH_SHARE, 0.001)
	assert_eq(Knowledge.teach(b, a), -1, "nothing to teach one who knows more")
	# What is saved is read back clean.
	a.knowledge[Knowledge.KEY] = PackedFloat32Array([NAN, -3, 999])
	assert_eq(Knowledge.of(a), PackedFloat32Array([0, 0, 100, 0, 0, 0, 0, 0, 0, 0]))


func test_knowledge_loss_oral() -> void:
	_clear_all()
	var healer := _with(&"forager")
	healer.knowledge[Knowledge.KEY] = PackedFloat32Array([0, 0, 0, 0, 50, 0, 0, 0, 0, 0])
	assert_near(learning.of_settlement(session.settlement, Knowledge.Domain.MEDICINE), 50.0, 0.001)
	var name := healer.given_name
	assert_true(session.kill_person(healer.id))
	assert_eq(learning.losses, 1)
	var lost := session.events.of_type(&"knowledge_lost")
	assert_eq(lost.size(), 1)
	assert_eq(str(lost[0].text_params["kind"]), "medicine")
	assert_eq(EventText.text(lost[0], session.people), "When %s died, much of what was known of healing went with them" % name)
	assert_eq(learning.of_settlement(session.settlement, Knowledge.Domain.MEDICINE), 0.0, "nobody knows it now")
	# Taught first: kept.
	var teacher := _with(&"woodcutter")
	var student := _with(&"farmer")
	teacher.knowledge[Knowledge.KEY] = PackedFloat32Array([0, 50, 0, 0, 0, 0, 0, 0, 0, 0])
	student.knowledge[Knowledge.KEY] = PackedFloat32Array([0, 45, 0, 0, 0, 0, 0, 0, 0, 0])
	assert_true(session.kill_person(teacher.id))
	assert_eq(session.events.of_type(&"knowledge_lost").size(), 1, "the student knows it: nothing much lost")
	# Written down: half is kept, whoever dies.
	learning.writes = func(_own: Settlement) -> bool: return true
	var last := _with(&"hunter")
	if last == null:
		last = _with(&"forager")
	last.knowledge[Knowledge.KEY] = PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 40])
	learning.each_day(session.clock.tick)
	assert_true(session.kill_person(last.id))
	assert_true(learning.of_settlement(session.settlement, Knowledge.Domain.ANOMALY) >= 20.0 - 0.01, "the records keep half")
	# And saved with the world.
	var again := Knowledge.new()
	again.from_dict(bytes_to_var(var_to_bytes(learning.to_dict())))
	assert_eq(again.records, learning.records)


func test_what_goes_wrong_and_the_player_teach() -> void:
	_clear_all()
	var farmer := _with(&"farmer")
	session.events.record(&"crop_failure", {"settlement": session.settlement.id})
	assert_true(Knowledge.points(farmer, Knowledge.Domain.AGRICULTURE) >= 1.9, "a failed crop teaches the farmers")
	var other := _with(&"woodcutter")
	assert_eq(Knowledge.points(other, Knowledge.Domain.AGRICULTURE), 0.0, "and only them")
	# The player's doing, remembered, feeds what is known of the unexplained.
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = other.id
	target.entity_kind = SpatialIndex.KIND_PERSON
	target.tile = other.position
	target.direct = true
	session.interactions.tap(target)
	session.behavior.step(0.5)
	assert_true(Knowledge.points(other, Knowledge.Domain.ANOMALY) > 0.0, "the touch: something unexplained")
	# Saved with the person.
	var saved := PersonData.from_dict(bytes_to_var(var_to_bytes(other.to_dict())))
	assert_eq(Knowledge.of(saved), Knowledge.of(other))
