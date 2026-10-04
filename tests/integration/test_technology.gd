extends TestCase
## M16.2: technologies come from conditions, never from the calendar — what
## is known first, what the land offers, people, trades, knowing; someone works
## each out (the inventor); what one settlement knows travels by trade and
## with those who found a new one.

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var session: WorldSession
var tech: TechnologySystem


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	tech = session.technology


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


func _knowing(domain: int, points: float) -> void:
	for person in session.settlement.members():
		var held := Knowledge.of(person)
		held[domain] = points
		person.knowledge[Knowledge.KEY] = held


func test_the_chain_is_whole() -> void:
	var library := session.technologies
	assert_eq(library.problems, PackedStringArray(), "every technology well defined")
	for id: StringName in [&"fire", &"foraging", &"agriculture", &"toolmaking", &"pottery", &"weaving", &"medicine", &"lamps",
			&"writing", &"astronomy", &"mathematics", &"engineering", &"copper_working", &"electricity", &"computing"]:
		assert_true(library.has_def(id), String(id))
	assert_true(library.get_def(&"pottery").order < library.get_def(&"writing").order, "in the order of the chain")
	# Every settlement knows the beginning — and nothing more — from the start.
	var own := session.settlement
	for id: StringName in [&"fire", &"foraging", &"agriculture"]:
		assert_true(own.knows_how(id), String(id))
	assert_false(own.knows_how(&"pottery"))
	assert_eq(session.events.of_type(&"knowledge_learned").size(), 0, "nothing told of what was always known")


func test_tech_requires_conditions() -> void:
	var own := session.settlement
	var pottery := session.technologies.get_def(&"pottery")
	_knowing(Knowledge.Domain.CRAFT, 0.0)
	assert_true(tech.missing(own, pottery).has("knowledge"))
	_knowing(Knowledge.Domain.CRAFT, 100.0)
	var gaps := tech.missing(own, pottery)
	assert_false(gaps.has("knowledge"))
	# What is not in the world never comes, however long: a thousand years of days.
	var copper := session.technologies.get_def(&"copper_working")
	assert_true(tech.missing(own, copper).has("resource:copper"))
	var made := TechnologyDef.new()
	made.id = &"smelting_test"
	made.domain = Knowledge.Domain.CRAFT
	made.required_resources = PackedStringArray(["copper"])
	made.knowledge_threshold = 1.0
	made.base_daily_chance = 1.0
	session.technologies.add(made)
	for day in range(1, 24_000, 7):
		tech.each_day(day, day * TimeConfig.MINUTES_PER_DAY)
	assert_false(own.knows_how(&"smelting_test"), "no copper: never")
	assert_false(own.knows_how(&"copper_working"))
	assert_false(own.knows_how(&"electricity"), "nothing without what comes before it")
	for entry: Array in tech.known_by(own):
		var def := session.technologies.get_def(entry[0])
		for before in def.prerequisites:
			assert_true(own.knows_how(StringName(before)), "%s came after %s" % [entry[0], before])
	# Clay is at hand by the water; without water near, not.
	assert_true(tech.resource_known(own, "clay"), "the river is near the fire")


func test_tech_inventor_attribution() -> void:
	var own := session.settlement
	var made := TechnologyDef.new()
	made.id = &"basketry_test"
	made.domain = Knowledge.Domain.CRAFT
	made.knowledge_threshold = 10.0
	made.base_daily_chance = 1.0
	session.technologies.add(made)
	_knowing(Knowledge.Domain.CRAFT, 0.0)
	assert_false(tech.missing(own, made).is_empty(), "nobody knows enough")
	# One of them knows a great deal: likeliest by far to be the one.
	var adults := own.members().filter(func(p: PersonData) -> bool:
		return session.behavior.ctx.stage_of(p) != PersonData.LifeStage.CHILD)
	var knower: PersonData = adults[0]
	var held := Knowledge.of(knower)
	held[Knowledge.Domain.CRAFT] = 90.0
	knower.knowledge[Knowledge.KEY] = held
	var picked := {}
	for day in 40:
		var who := tech.inventor_for(own, made, day)
		picked[who.id] = int(picked.get(who.id, 0)) + 1
	assert_true(int(picked.get(knower.id, 0)) >= 25, "the one who knows most, mostly (%s)" % picked)
	tech.each_day(5, 5 * TimeConfig.MINUTES_PER_DAY)
	assert_true(own.knows_how(&"basketry_test"))
	var told := session.events.of_type(&"knowledge_learned")
	assert_eq(told.size(), 1)
	assert_eq(str(told[0].text_params["kind"]), "basketry_test")
	assert_eq(told[0].participants.size(), 1)
	assert_eq(told[0].participants[0], tech.inventor_for(own, made, 5).id, "the inventor is remembered")
	assert_eq(tech.discoveries, 1)
	# Known once: not again.
	tech.each_day(6, 6 * TimeConfig.MINUTES_PER_DAY)
	assert_eq(session.events.of_type(&"knowledge_learned").size(), 1)


func test_tech_diffusion() -> void:
	var own := session.settlement
	# Another settlement, as far as what it knows goes (it is not bound to the world).
	var elsewhere := Settlement.new()
	elsewhere.id = 999
	elsewhere.knows = {"fire": 0, "foraging": 0, "agriculture": 0, "pottery": 100, "writing": 200, "copper_working": 300}
	session.settlements.add(elsewhere)
	# A settlement founded from it takes what it knows along.
	var founded := Settlement.new()
	founded.id = 998
	session.settlements.add(founded)
	tech.on_founded(founded, {"from": elsewhere.id})
	assert_true(founded.knows_how(&"pottery"))
	assert_true(founded.knows_how(&"writing"))
	# Loads carried from it to us: sooner or later we know how to make pots —
	# not what we could not use (writing wants pottery first; copper, copper).
	var spread: Array = []
	tech.spread.connect(func(to: int, id: StringName, _by: int, from: int) -> void: spread.append([to, id, from]))
	var loads := 0
	while not own.knows_how(&"pottery") and loads < 500:
		loads += 1
		tech.on_traded({"from": elsewhere.id, "to": own.id, "resource": "wood", "units": loads, "trader": 0})
	assert_true(own.knows_how(&"pottery"), "learned from those who knew")
	assert_true(loads > 1 and loads < 200, "not at once, not never (%d loads)" % loads)
	assert_eq(spread[0], [own.id, &"pottery", elsewhere.id])
	assert_false(own.knows_how(&"copper_working"), "no copper here")
	for more in 300:
		tech.on_traded({"from": elsewhere.id, "to": own.id, "resource": "wood", "units": 1000 + more, "trader": 0})
	assert_true(own.knows_how(&"writing"), "pottery known now: writing can follow")
	assert_false(own.knows_how(&"copper_working"))
	assert_eq(session.events.of_type(&"knowledge_spread").size(), spread.size(), "each told")
	session.settlements.remove(elsewhere)
	session.settlements.remove(founded)
