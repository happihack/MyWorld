extends TestCase
## Getting on through the ages (the 200-year soaks, 2026-10-09: no world got
## past the age of settling). An age reached stays reached and the next needs
## only its own rule; fields feeding a third is farming; the first storehouse
## comes with a few households; what knowing and believing call for is built
## before more bridges; the box's oddities teach the unexplained.

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var session: WorldSession
var own: Settlement


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	own = session.settlement


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


func test_an_age_needs_only_its_own_rule() -> void:
	var tech := session.technology
	tech.phase_reached = CivilizationPhase.Phase.SETTLEMENT
	# No storehouse stands (the settling rule fails now) — but the fields feed them.
	for prop in session.props.of_kind(PropData.Kind.STOREHOUSE).duplicate():
		session.props.remove(prop.id)
	own.produced.clear()
	own.produced["grain"] = 40.0
	own.produced["berries"] = 60.0
	assert_true(CivilizationPhase.farms_feed(own) >= CivilizationPhase.FARMS_FEED, "fields feed a third and more")
	assert_false(CivilizationPhase.holds(CivilizationPhase.Phase.SETTLEMENT, session.settlements, session.props), "(no storehouse)")
	tech.look_at_the_age()
	assert_eq(tech.phase_reached, CivilizationPhase.Phase.AGRICULTURE, "the age of farming all the same")
	# And it is never lost.
	own.produced.clear()
	tech.look_at_the_age()
	assert_eq(tech.phase_reached, CivilizationPhase.Phase.AGRICULTURE, "an age reached stays reached")


func test_the_first_storehouse_comes_with_a_few_households() -> void:
	var planner := own.planner
	var fire := own.fire().tile
	while own.member_count() < SettlementPlanner.FIRST_STORE_FROM:
		session.spawn_person(fire + Vector2i(1, 1))
	assert_true(planner.standing_near(PropData.Kind.STOREHOUSE).is_empty())
	assert_has(planner.needs(session.clock.tick), &"storage", "a storehouse, though the stores are not full")


func test_landmarks_before_more_bridges() -> void:
	var planner := own.planner
	var fire := own.fire().tile
	while own.member_count() < SettlementPlanner.LANDMARK_FROM + 2:
		session.spawn_person(fire + Vector2i(1, 1))
	own.learn(&"astronomy", 0, session.clock.tick)
	var needs := planner.needs(session.clock.tick)
	assert_has(needs, &"observatory", "a stone circle, once they watch the sky")
	if needs.has(&"bridge"):
		assert_true(needs.find(&"observatory") < needs.find(&"bridge"), "before another bridge (%s)" % str(needs))


func test_the_box_teaches_the_unexplained() -> void:
	var finder := own.members()[0]
	var other := own.members()[1]
	var before := Knowledge.points(finder, Knowledge.Domain.ANOMALY)
	var heard := Knowledge.points(other, Knowledge.Domain.ANOMALY)
	session._learn_from_clue(finder.id)
	assert_true(Knowledge.points(finder, Knowledge.Domain.ANOMALY) > before + 10.0, "much, for who found it")
	assert_true(Knowledge.points(other, Knowledge.Domain.ANOMALY) > heard, "a little, for those told at home")
	# A few such finds: the settlement knows enough of it for natural philosophy.
	for i in 4:
		session._learn_from_clue(finder.id)
	var needed := session.technologies.get_def(&"natural_philosophy").knowledge_threshold
	assert_true(session.learning.of_settlement(own, Knowledge.Domain.ANOMALY) >= needed,
		"%.0f of %.0f" % [session.learning.of_settlement(own, Knowledge.Domain.ANOMALY), needed])
