extends TestCase
## M18: the unexplained, recorded only if witnessed; scholars and scientists
## checking for patterns (the player's own hours among them); seeded mysteries
## unfolding clue by clue; the box research, stage by stage.

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var session: WorldSession
var archive: AnomalyArchive
var science: ScienceSystem


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	archive = session.anomaly_archive
	science = session.science


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


func _stimulus(type: StringName = Stimulus.TOUCH) -> Stimulus:
	var stimulus := Stimulus.new()
	stimulus.type = type
	stimulus.origin = Stimulus.Origin.PLAYER
	stimulus.position = session.settlement.fire().position2d() + Vector2(2.0, 0.0)
	stimulus.intervention_id = 1
	return stimulus


## `count` anomalies, at the player's real hours given by `hour_of` (index -> hour).
func _anomalies(count: int, hour_of: Callable) -> void:
	var i := [0]
	archive.real_clock = func() -> Array:
		i[0] += 1
		return [1_800_000_000 + i[0] * 3600, int(hour_of.call(i[0]))]
	for n in count:
		archive.on_stimulus(_stimulus(), 3, session.clock.tick + n * 90)


func _scientist() -> PersonData:
	var own := session.settlement
	var person: PersonData = own.members().filter(func(p: PersonData) -> bool:
		return session.behavior.ctx.stage_of(p) == PersonData.LifeStage.ADULT)[0]
	person.occupation_id = &"scientist"
	return person


func test_anomaly_recorded_only_if_witnessed() -> void:
	assert_true(archive.on_stimulus(_stimulus(), 0, 10).is_empty(), "nobody saw it: not recorded")
	var nature := Stimulus.natural(Stimulus.THUNDERSTORM, Vector2.ZERO, 10, Config.reactions)
	assert_true(archive.on_stimulus(nature, 5, 10).is_empty(), "nature's doing: not an anomaly")
	var seen := archive.on_stimulus(_stimulus(), 2, 10)
	assert_false(seen.is_empty())
	assert_eq(int(seen["witnesses"]), 2)
	assert_eq(int(seen["settlement"]), session.settlement.id)
	assert_false(bool(seen["written"]), "before writing: oral")
	# Through the game: the player touches someone — witnessed by them, at least.
	var person: PersonData = session.settlement.members()[0]
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = person.id
	target.entity_kind = SpatialIndex.KIND_PERSON
	target.tile = person.position
	target.direct = true
	session.interactions.tap(target)
	assert_eq(archive.anomalies.size(), 2, "the touch is recorded")
	assert_eq(str(archive.anomalies[-1]["type"]), "touch")
	# Oral: forgotten in time — unless written down while still remembered.
	var later := 10 + (AnomalyArchive.ORAL_YEARS + 1) * Config.time.ticks_per_year()
	archive.anomalies[-1]["tick"] = later - 100 # (the touch: a recent one)
	archive.keep(later)
	assert_eq(archive.anomalies.size(), 1, "the old one forgotten, the recent one still told")
	session.settlement.knows["writing"] = 100
	archive.keep(later + 1)
	assert_true(bool(archive.anomalies[0]["written"]), "written down")
	archive.keep(later + 100 * Config.time.ticks_per_year())
	assert_eq(archive.anomalies.size(), 1, "and kept")
	# Saved.
	var again := AnomalyArchive.new()
	again.from_dict(bytes_to_var(var_to_bytes(archive.to_dict())))
	assert_eq(again.anomalies.size(), 1)


func test_time_of_day_correlation_detects_pattern() -> void:
	var own := session.settlement
	own.knows["writing"] = 100
	var scientist := _scientist()
	# The player plays in the evenings (20:00, mostly).
	_anomalies(12, func(i: int) -> int: return 20 if i % 6 != 0 else 9)
	science.check(own, scientist, session.clock.tick)
	var held := science.hypothesis_of(own.id, ScienceSystem.Kind.TIME_OF_DAY)
	assert_false(held.is_empty(), "the pattern is noticed")
	assert_eq(str(held["params"]["part"]), "evening")
	assert_eq(int(held["by"]), scientist.id)
	assert_true(float(held["confidence"]) > 0.2)
	var told := session.events.of_type(&"hypothesis").filter(func(e: WorldEvent) -> bool: return str(e.text_params["kind"]) == "time_of_day")
	assert_eq(told.size(), 1)
	assert_eq(told[0].participants[0], scientist.id, "the discoverer is named")
	assert_has(EventText.text(told[0], session.people), "at one time of day")
	assert_has(MenuPages.box_knowledge(session)["hypotheses"][0], "mostly in the evening")
	# At any hour, no pattern.
	var other := ScienceSystem.new()
	other.bind(archive, session.settlements, 0)
	archive.anomalies.clear()
	_anomalies(24, func(i: int) -> int: return i % 24)
	other.check(own, scientist, session.clock.tick)
	assert_true(other.hypothesis_of(own.id, ScienceSystem.Kind.TIME_OF_DAY).is_empty(), "no hour stands out")
	# Rain from a clear sky in droughts: something answers.
	archive.anomalies.clear()
	for n in 10:
		var rain := archive.on_stimulus(_stimulus(Stimulus.RAIN_FROM_CLEAR_SKY), 2, n)
		rain["drought"] = n < 7
	other.check(own, scientist, session.clock.tick)
	assert_false(other.hypothesis_of(own.id, ScienceSystem.Kind.RESPONSIVE_RAIN).is_empty())


func test_mystery_chain_progression() -> void:
	var mysteries := session.mysteries
	assert_eq(mysteries.problems, PackedStringArray())
	assert_eq(mysteries.defs.size(), 7)
	assert_eq(mysteries.placed.size(), 7, "all placed when the world was made")
	# The same world, the same places.
	var other := WorldSession.new()
	add_child(other)
	other.create_new(12345)
	assert_eq(other.mysteries.placed[&"unexplained_ruins"]["tile"], mysteries.placed[&"unexplained_ruins"]["tile"])
	other.queue_free()
	var ruins: Dictionary = mysteries.placed[&"unexplained_ruins"]
	var day := Config.time.day_index(session.clock.tick)
	mysteries.each_day((day + 1) * TimeConfig.MINUTES_PER_DAY)
	assert_eq(int(ruins["found"]), 0, "dormant: nobody has been there")
	# Someone goes there.
	var person: PersonData = session.settlement.members()[0]
	session.people.move(person.id, ruins["tile"] + Vector2i(1, 0))
	mysteries.each_day((day + 2) * TimeConfig.MINUTES_PER_DAY)
	assert_eq(int(ruins["found"]), 1)
	var told := session.events.of_type(&"mystery_clue")
	assert_eq(told.size(), 1)
	assert_eq(told[0].participants[0], person.id, "who found it")
	assert_has(EventText.text(told[0], session.people), "old stones where no one has lived")
	mysteries.each_day((day + 3) * TimeConfig.MINUTES_PER_DAY)
	assert_eq(int(ruins["found"]), 1, "the next clue wants writing")
	session.settlement.knows["writing"] = 100
	mysteries.each_day((day + 4) * TimeConfig.MINUTES_PER_DAY)
	assert_eq(int(ruins["found"]), 2, "one clue a day")
	mysteries.each_day((day + 5) * TimeConfig.MINUTES_PER_DAY)
	assert_eq(int(ruins["found"]), 3, "seen on enough days, and a scholar")
	mysteries.each_day((day + 6) * TimeConfig.MINUTES_PER_DAY)
	assert_eq(int(ruins["found"]), 3, "no more")
	# What later content brings stays dormant.
	assert_true(mysteries.get_def(&"impossible_material").steps[2].has("dormant"))
	# Saved.
	var again := MysterySystem.new()
	again.from_dict(bytes_to_var(var_to_bytes(mysteries.to_dict())))
	assert_eq(int(again.placed[&"unexplained_ruins"]["found"]), 3)


func test_box_research_stage_gates() -> void:
	var own := session.settlement
	assert_eq(science.stage, ScienceSystem.Stage.NONE)
	science.each_day(session.clock.tick)
	assert_eq(science.stage, ScienceSystem.Stage.NONE, "nothing noticed yet")
	archive.on_stimulus(_stimulus(), 2, 10)
	science.each_day(session.clock.tick)
	assert_eq(science.stage, ScienceSystem.Stage.ANOMALY_NOTICED)
	assert_eq(science.stage, ScienceSystem.Stage.ANOMALY_NOTICED, "no pattern without enough to go on")
	own.knows["writing"] = 100
	var scientist := _scientist()
	_anomalies(20, func(i: int) -> int: return 21)
	var year := Config.time.ticks_per_year()
	science.each_day(session.clock.tick + 1440)
	assert_eq(science.stage, ScienceSystem.Stage.ANOMALY_NOTICED, "not so soon after the last")
	science.each_day(session.clock.tick + year + 1440)
	assert_eq(science.stage, ScienceSystem.Stage.PATTERN, "a scholar proposes they are connected")
	# A second pattern, held with confidence: a single force outside.
	for n in 10:
		var rain := archive.on_stimulus(_stimulus(Stimulus.RAIN_FROM_CLEAR_SKY), 2, n)
		rain["drought"] = true
	for h in science.hypotheses:
		h["confidence"] = 0.9
	science.each_day(session.clock.tick + year + 2880)
	assert_eq(science.stage, ScienceSystem.Stage.PATTERN, "a stage at a time")
	science.each_day(session.clock.tick + year * 2 + 4320)
	assert_eq(science.stage, ScienceSystem.Stage.EXTERNAL_FORCE)
	# The Edge, found: an expedition — and back, with what it saw.
	session.knowledge.edge_reached = true
	science.each_day(session.clock.tick + year * 3 + 5760)
	assert_eq(science.stage, ScienceSystem.Stage.EDGE_EXPEDITIONS)
	assert_eq(int(science.expedition["leader"]), scientist.id)
	science.each_day(session.clock.tick + year * 3 + 5760 + (ScienceSystem.EXPEDITION_DAYS + 1) * 1440)
	assert_true(science.expedition.is_empty(), "back")
	var steps := session.events.of_type(&"box_research")
	assert_eq(steps.size(), 5, "four stages and the return")
	assert_has(EventText.text(steps[-1], session.people), "back from the Edge")
	# Saved.
	var again := ScienceSystem.new()
	again.from_dict(bytes_to_var(var_to_bytes(science.to_dict())))
	assert_eq(again.stage, ScienceSystem.Stage.EDGE_EXPEDITIONS)


func test_natural_philosophy_makes_scientists() -> void:
	var own := session.settlement
	assert_true(session.technologies.get_def(&"natural_philosophy").implemented)
	own.learn(&"natural_philosophy", own.members()[0].id, session.clock.tick)
	var scientist := own.ensure_scientist(session.clock.tick)
	assert_not_null(scientist)
	assert_eq(scientist.occupation_id, &"scientist")
	assert_true(scientist.knowledge.has("natural_philosophy"), "PHYSICS can occur to them")
	assert_true(Interpretation.available(scientist, ReactionTable.PHYSICS, session.behavior.ctx, Config.reactions))
	# Their work: to where something strange happened, to look and to write.
	archive.on_stimulus(_stimulus(), 2, 10)
	var steps := Planner.plan(&"work", scientist, session.behavior.ctx)
	assert_eq(steps.size(), 3)
	assert_eq(int(steps[1]["pose"]), PersonData.Pose.CROUCH)
	assert_true(PersonMeshLibrary.ACCESSORIES.has(&"scroll"))
