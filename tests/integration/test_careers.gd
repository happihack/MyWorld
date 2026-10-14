extends TestCase
## Buildings & villagers F3: careers. Levels are bands over the skill there
## is; experts and masters come to less harm and teach more. An adolescent is
## taken on by a mentor of a trade the settlement can use (their parent's if
## it is one), gains skill with them, and grown, the trade is theirs; a mentor
## who dies is replaced. Elders keep the trades kept into old age; the rest
## give theirs up, and it is remembered.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440

var session: WorldSession
var life
var _knobs: Array = []


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	life = session.lifecycle
	for knob: StringName in [&"base_death_per_year", &"infant_death_per_year", &"old_age_death_per_year",
			&"accident_per_work_day", &"crowding_chance_per_day", &"partner_chance_per_day", &"conceive_chance_per_day",
			&"starve_chance_per_day", &"illness_death_per_day", &"injury_death_per_day", &"newcomer_chance_per_day",
			&"marry_out_chance_per_day", &"gathering_romance"]:
		_knob(Config.life, knob, 0.0)


func after_each() -> void:
	_knobs.reverse()
	for knob: Array in _knobs:
		(knob[0] as Resource).set(knob[1], knob[2])
	_knobs.clear()
	session.queue_free()
	await wait_frames(1)


func _knob(resource: Resource, knob: StringName, value: Variant) -> void:
	_knobs.append([resource, knob, resource.get(knob)])
	resource.set(knob, value)


func _make_age(person: PersonData, years: int) -> void:
	person.birth_tick = session.clock.tick - years * Config.time.ticks_per_year() - DAY


func _grown(occupation: StringName, skill: float) -> PersonData:
	var person := session.spawn_person(session.settlement.fire().tile + Vector2i(1, 1))
	_make_age(person, 30)
	person.occupation_id = occupation
	person.skills[String(occupation)] = skill
	return person


func test_levels_are_bands_over_the_skill() -> void:
	assert_eq(Careers.level(0.0), Careers.Level.NOVICE)
	assert_eq(Careers.level(0.2), Careers.Level.TRAINED)
	assert_eq(Careers.level(0.5), Careers.Level.SKILLED)
	assert_eq(Careers.level(0.8), Careers.Level.EXPERT)
	assert_eq(Careers.level(0.95), Careers.Level.MASTER)
	var master := _grown(&"woodcutter", 0.95)
	var novice := _grown(&"woodcutter", 0.05)
	assert_eq(Careers.accident_factor(master), 0.5, "a master comes to harm half as often")
	assert_eq(Careers.accident_factor(novice), 1.0)
	assert_eq(Careers.teach_factor(master), 2.0, "and teaches twice as much")


func test_an_apprentice_grows_into_a_trade() -> void:
	var own := session.settlement
	var parent := _grown(&"woodcutter", 0.6)
	var young := session.spawn_person(own.fire().tile + Vector2i(1, 1))
	_make_age(young, 13)
	young.occupation_id = &"forager"
	life._grow(young, session.clock.tick) # (seen as the adolescent they are)
	young.parents = PackedInt64Array([parent.id])
	assert_true(Careers.open_trades(own, session.occupations, session.clock.tick).has(&"woodcutter"), "gathering trades are open")
	life._apprentices(session.people.all_people(), session.clock.tick)
	assert_eq(young.apprentice_trade, &"woodcutter", "their parent's trade")
	assert_eq(young.mentor_id, parent.id, "taught by the most skilled at it")
	var skill := Careers.skill_of(young, &"woodcutter")
	assert_true(skill > 0.0, "a day's learning")
	# The mentor dies: another of the trade takes them on.
	assert_true(session.kill_person(parent.id))
	life._apprentices(session.people.all_people(), session.clock.tick)
	var other := session.people.get_person(young.mentor_id)
	assert_not_null(other, "another takes them on")
	assert_true(other.id != parent.id and other.occupation_id == &"woodcutter", "another woodcutter")
	assert_true(Careers.skill_of(young, &"woodcutter") > skill)
	# Grown: the trade is theirs.
	_make_age(young, 16)
	life._grow(young, session.clock.tick)
	assert_eq(young.occupation_id, &"woodcutter")
	assert_eq(young.mentor_id, 0)
	assert_eq(young.apprentice_trade, &"")
	# The new fields are saved.
	young.mentor_id = other.id
	young.former_occupation = &"hunter"
	var back := PersonData.from_dict(young.to_dict())
	assert_eq([back.mentor_id, back.former_occupation], [other.id, &"hunter"])


func test_nobody_is_trained_for_a_trade_already_full() -> void:
	var own := session.settlement
	_grown(&"trader", 0.8)
	assert_false(Careers.open_trades(own, session.occupations, session.clock.tick).has(&"trader"),
		"no trade to carry: no trader wanted")


func test_elders_keep_some_trades() -> void:
	var forager := _grown(&"forager", 0.4)
	var woodcutter := _grown(&"woodcutter", 0.4)
	for person in [forager, woodcutter]:
		life._grow(person, session.clock.tick) # (grown, as they are)
		_make_age(person, 50)
		life._grow(person, session.clock.tick)
	assert_eq(forager.occupation_id, &"forager", "kept into old age")
	assert_eq(forager.former_occupation, &"")
	assert_ne(woodcutter.occupation_id, &"woodcutter", "too heavy for an elder")
	assert_eq(woodcutter.former_occupation, &"woodcutter", "remembered")


func test_careers_are_told() -> void:
	var own := session.settlement
	var events := session.events
	# The first apprentice of a trade in a settlement — not every one after.
	var parent := _grown(&"woodcutter", 0.6)
	var young := session.spawn_person(own.fire().tile + Vector2i(1, 1))
	_make_age(young, 13)
	young.occupation_id = &"forager"
	young.parents = PackedInt64Array([parent.id])
	life._apprentices(session.people.all_people(), session.clock.tick)
	assert_eq(events.count_of(&"apprenticed"), 1)
	var told := EventText.text(events.latest(&"apprenticed"), session.people, events)
	assert_has(told, young.given_name)
	assert_has(told, "woodcutter")
	var second := session.spawn_person(own.fire().tile + Vector2i(1, 1))
	_make_age(second, 13)
	second.parents = PackedInt64Array([parent.id])
	life._apprentices(session.people.all_people(), session.clock.tick)
	assert_eq(events.count_of(&"apprenticed"), 1, "the second is no news")
	# A master made: told once.
	parent.skills["woodcutter"] = 0.95
	life._masters(session.people.all_people())
	life._masters(session.people.all_people())
	assert_eq(events.count_of(&"trade_mastered"), 1)
	assert_has(EventText.text(events.latest(&"trade_mastered"), session.people, events), "master woodcutter")
	# The last who knew a staffed trade dies, with nobody learning it: it is lost.
	var trader := _grown(&"trader", 0.6)
	for person in own.members():
		if person.id != trader.id and person.occupation_id == &"trader":
			person.occupation_id = &"forager"
	life.die(trader, &"old_age", session.clock.tick)
	assert_eq(events.count_of(&"trade_lost"), 1)
	assert_has(EventText.text(events.latest(&"trade_lost"), session.people, events), "trader")


func test_the_inspector_tells_a_career() -> void:
	# (F8) The inspector's line, its buttons, and the settlement's staffing.
	var own := session.settlement
	var parent := _grown(&"woodcutter", 0.95)
	parent.mastered.append("woodcutter")
	var young := session.spawn_person(own.fire().tile + Vector2i(1, 1))
	_make_age(young, 13)
	young.parents = PackedInt64Array([parent.id])
	assert_not_null(AiInspector.apprentice_now(session, young.id), "taken on")
	var line := AiInspector.career_line(session, parent)
	assert_has(line, "woodcutter master 0.95")
	assert_has(line, "teaching %s" % young.given_name)
	assert_has(line, "master of woodcutter")
	assert_has(AiInspector.career_line(session, young), "learning woodcutter from")
	var was := parent.occupation_id
	assert_ne(AiInspector.next_trade(session, parent.id), was, "another trade")
	assert_has(own.staffing_text(session.clock.tick), "farmer ")
