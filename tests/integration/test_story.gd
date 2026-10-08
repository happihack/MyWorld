extends TestCase
## M19: strife between settlements (each step naming what caused it), and the
## stories history tells of chains of causes — found, scored, named, put in
## words, never told twice; reinterpreted by historians.

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var session: WorldSession


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


## A fixture history: a drought → a failed harvest → a hungry season → people
## leaving → a new settlement; and things that led nowhere.
func _fixture(log: EventLog) -> Array[WorldEvent]:
	var chain: Array[WorldEvent] = []
	var drought := log.record(&"drought", {"tick": 100})
	chain.append(drought)
	log.record(&"person_born", {"tick": 150})
	var failed := log.record(&"crop_failure", {"tick": 300}, [drought])
	chain.append(failed)
	var hungry := log.record(&"food_shortage", {"tick": 500}, [failed])
	chain.append(hungry)
	log.record(&"weather_changed", {"tick": 520})
	var leaving := log.record(&"migration", {"tick": 900}, [hungry])
	chain.append(leaving)
	var founded := log.record(&"settlement_founded", {"tick": 1500, "place": "Northwatch"}, [leaving])
	chain.append(founded)
	return chain


func _engine(log: EventLog) -> StoryEngine:
	var engine := StoryEngine.new()
	engine.bind(log, session.people, 0)
	return engine


func test_chain_detection_on_fixture_graph() -> void:
	var log := EventLog.new()
	log.library = session.events.library
	var chain := _fixture(log)
	var engine := _engine(log)
	var told := engine.mine(2000)
	assert_eq(told.size(), 1, "one story in it")
	var ids: Array = []
	for event in chain:
		ids.append(event.id)
	assert_eq(told[0]["events"], ids, "the whole chain, the cause first")
	assert_eq(told[0]["type"], "drought")
	assert_false(told[0]["player"])


func test_summary_template_filling() -> void:
	var log := EventLog.new()
	log.library = session.events.library
	_fixture(log)
	var engine := _engine(log)
	var story: Dictionary = engine.mine(2000)[0]
	assert_eq(story["summary"], engine.summary(story), "its words, kept as told")
	# (Worded anew, as for a lower and a higher score.)
	story.erase("summary")
	story.erase("name")
	story["score"] = 2.0
	assert_eq(engine.summary(story), "The Drought of Year 1 caused a failed harvest and eventually led to the founding of Northwatch.")
	story["score"] = 9.0
	assert_eq(engine.name_of(story), "the Great Drought", "a great story, a great name")
	# Three events: "…, which led to …".
	var short := {"id": 99, "events": [story["events"][1], story["events"][2], story["events"][3]], "type": "crop_failure",
		"year": 1, "score": 3.0}
	assert_eq(engine.summary(short), "The Failed Harvest of Year 1 caused a hungry season, which led to people leaving to find new land.")
	# A line for the list.
	assert_has(engine.line(story), "YEAR 1")


func test_no_duplicate_story() -> void:
	var log := EventLog.new()
	log.library = session.events.library
	var chain := _fixture(log)
	var engine := _engine(log)
	assert_eq(engine.mine(2000).size(), 1)
	assert_eq(engine.mine(3000).size(), 0, "told once")
	# More of the same (the new settlement's first leader): mostly a retelling.
	var leader := log.record(&"leadership", {"tick": 1600, "place": "Northwatch"}, [chain[-1]])
	assert_eq(engine.mine(3000).size(), 0, "not told again for one more step")
	# Something new, from the same drought: a story of its own.
	var withered := log.record(&"tree_withered", {"tick": 400}, [chain[0]])
	var gone := log.record(&"forage_depleted", {"tick": 600}, [withered])
	log.record(&"migration", {"tick": 700}, [gone])
	assert_eq(engine.mine(4000).size(), 1, "a new story")
	# Saved: what was told stays told.
	var again := StoryEngine.new()
	again.bind(log, session.people, 0)
	again.from_dict(bytes_to_var(var_to_bytes(engine.to_dict())))
	assert_eq(again.stories.size(), 2)
	assert_eq(again.mine(5000).size(), 0)
	assert_true(leader.id > 0)


## A second settlement, founded by a group from the first (the walk skipped).
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
	return session.migration.found(journey, session.clock.tick)


func test_weight_and_repetition() -> void:
	var log := EventLog.new()
	log.library = session.events.library
	var engine := _engine(log)
	# A quarrel, a fight, a falling-out: nothing weighty — no story.
	var a := log.record(&"fell_out", {"tick": 10, "significance": 0.45})
	var b := log.record(&"fight", {"tick": 20, "significance": 0.6}, [a])
	log.record(&"became_enemies", {"tick": 30, "significance": 0.55}, [b])
	assert_eq(engine.mine(100).size(), 0, "not weighty enough")
	# Hunger that came to nothing in particular: no story.
	var x0 := log.record(&"food_spoiled", {"tick": 500})
	var y0 := log.record(&"food_shortage", {"tick": 550, "significance": 0.8}, [x0])
	log.record(&"shortage_over", {"tick": 600}, [y0])
	assert_eq(engine.mine(700).size(), 0, "no outcome, no story")
	# The same shape, again and again (hunger → people leaving): told once, not again soon.
	var told := 0
	for n in 4:
		var t := 1000 + n * 400
		var x := log.record(&"food_spoiled", {"tick": t})
		var y := log.record(&"food_shortage", {"tick": t + 50, "significance": 0.8}, [x])
		log.record(&"migration", {"tick": t + 100}, [y])
		told += engine.mine(t + 200).size()
	assert_eq(told, 1, "the same story is not told every season")
	# Its words stay as they were told.
	var story: Dictionary = engine.stories[0]
	var words := engine.line(story)
	for id: Variant in story["events"]:
		log.get_event(int(id)).text_params["place"] = "elsewhere"
	assert_eq(engine.line(story), words)


func test_war_chain_records_causes() -> void:
	var first := session.settlement
	var second := _second()
	assert_not_null(second)
	var conflicts := session.conflicts
	# Both hungry and near: a shortage told, then tension, a dispute, raids, war.
	session.events.record(&"food_shortage", {"settlement": first.id})
	first.shortage = Settlement.Shortage.EMPTY
	second.shortage = Settlement.Shortage.NONE
	first.stockpile.add(&"berries", 1)
	second.stockpile.add(&"berries", 40)
	# A fierce leader leads the hungry.
	session.governance.weigh(first, session.clock.tick)
	var leader := session.people.get_person(session.governance.leader_of(first.id))
	assert_not_null(leader)
	leader.traits[Traits.Axis.AGGRESSION] = 1.0
	var day := Config.time.day_index(session.clock.tick)
	var record := conflicts.pair(first.id, second.id)
	session.walking_raids = false # (the chain as it is reckoned: raids at once — walked ones are FC5's)
	for d in 400:
		record["tension"] = maxf(float(record["tension"]), ConflictSystem.WAR_AT + 0.05)
		conflicts.each_day((day + d + 1) * TimeConfig.MINUTES_PER_DAY)
		if conflicts.at_war(first.id, second.id) or session.events.count_of(&"peace") > 0:
			break
	var disputes := session.events.of_type(&"dispute")
	var raids := session.events.of_type(&"raid")
	var wars := session.events.of_type(&"war_begun")
	assert_eq(disputes.size(), 1, "a dispute first")
	assert_true(raids.size() >= ConflictSystem.WAR_RAIDS, "then raids")
	assert_eq(wars.size(), 1, "then war")
	assert_true(Array(disputes[0].causes).size() >= 1, "the dispute names the shortage")
	assert_true(Array(raids[0].causes).has(disputes[0].id), "a raid names the dispute")
	assert_eq(raids[0].participants[0], leader.id, "the raider's name")
	for raid in raids:
		assert_true(Array(wars[0].causes).has(raid.id), "the war names the raids")
	assert_has(EventText.text(wars[0], session.people), "War has broken out between")
	# Battles and peace.
	for d in range(400, 1000):
		conflicts.each_day((day + d + 1) * TimeConfig.MINUTES_PER_DAY)
		if session.events.count_of(&"peace") > 0:
			break
	var peace := session.events.of_type(&"peace")
	assert_eq(peace.size(), 1)
	assert_true(Array(peace[0].causes).has(wars[0].id), "the peace names the war")
	assert_true(bool(conflicts.pair(first.id, second.id)["border"]), "a border")
	for battle in session.events.of_type(&"battle"):
		assert_true(Array(battle.causes).has(wars[0].id), "each battle is of the war")
	for death in session.events.of_type(&"person_died"):
		if str(death.text_params.get("cause", "")) == "war":
			assert_eq(session.events.get_event(death.causes[0]).type, &"battle", "the fallen died of a battle")
	# And history tells of it.
	session.stories.mine(session.clock.tick)
	assert_true(session.stories.stories.any(func(s: Dictionary) -> bool:
		return (s["events"] as Array).any(func(id: int) -> bool: return session.events.get_event(id).type == &"war_begun")),
		"a story of the war")


func test_revolution_and_historians() -> void:
	var own := session.settlement
	session.governance.weigh(own, session.clock.tick)
	var leader := session.governance.leader_of(own.id)
	assert_ne(leader, 0)
	session.governance.depose(own.id, session.clock.tick)
	assert_ne(session.governance.leader_of(own.id), leader, "overthrown")
	var led := session.events.of_type(&"leadership")
	assert_eq(str(led[-1].text_params["kind"]), "overthrown")
	# A historian takes up an old story.
	var log := session.events
	var drought := log.record(&"drought", {"tick": 10})
	var failed := log.record(&"crop_failure", {"tick": 20}, [drought])
	log.record(&"migration", {"tick": 30}, [failed])
	session.stories.mine(40)
	assert_false(session.stories.stories.is_empty())
	session.stories.historian = func() -> int: return own.members()[0].id
	var later := 40 + (StoryEngine.OLD_YEARS + 1) * Config.time.ticks_per_year()
	for y in 40:
		session.stories._year = 22 + y
		session.stories.reinterpret(later + y * Config.time.ticks_per_year())
		if session.events.count_of(&"reinterpreted") > 0:
			break
	var re := session.events.of_type(&"reinterpreted")
	assert_eq(re.size(), 1)
	assert_has(EventText.text(re[0], session.people), "has proposed a new explanation for the")
