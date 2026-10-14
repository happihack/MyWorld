extends TestCase
## Buildings & villagers F4: the planner. Needs are scored — each its weight,
## more with its materials in store or what the settlement values leaning to
## it; how many of a building a settlement keeps and how big it must be come
## from the data; two buildings go up at once once there are builders or
## people enough for two; an upgrade is built in place of the building it
## upgrades, which works on until it is done, keeps its record, and is told.

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var session: WorldSession
var planner: SettlementPlanner


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	planner = session.settlement.planner


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


func _grow_to(people: int) -> void:
	var own := session.settlement
	while own.member_count() < people:
		session.spawn_person(own.fire().tile + Vector2i(1, 1))


func _finish(p: Dictionary) -> void:
	for resource: StringName in session.construction.still_needed(p):
		session.construction.deliver(p, resource, int(session.construction.still_needed(p)[resource]))
	while not session.construction.work(p, session.people.all_people()[0], 60.0, session.clock.tick):
		pass


func test_limits_and_sizes_come_from_the_data() -> void:
	var own := session.settlement
	var kiln := session.buildings.get_def(&"kiln")
	own.learn(&"pottery", 0, session.clock.tick)
	assert_eq(kiln.min_population, 6)
	_grow_to(6)
	assert_true(planner.big_enough(kiln))
	assert_true(planner.landmark_wanted("kiln"))
	_finish(session.construction.start(&"kiln", planner.site_for(kiln), session.clock.tick))
	assert_true(planner.at_limit(kiln), "one is enough")
	assert_false(planner.landmark_wanted("kiln"))
	# One for so many people, if the data says so.
	kiln.per_people = 3
	assert_false(planner.at_limit(kiln), "%d people: two" % own.member_count())
	kiln.per_people = 0


func test_needs_are_scored() -> void:
	var own := session.settlement
	own.learn(&"pottery", 0, session.clock.tick)
	own.learn(&"medicine", 0, session.clock.tick)
	_grow_to(8)
	var listed := planner.needs(session.clock.tick)
	assert_true(listed.has(&"kiln") and listed.has(&"herbs"), str(listed))
	assert_true(listed.find(&"kiln") < listed.find(&"herbs"), "listed: the kiln first")
	# The herb rack's wood in store, the kiln's not: the herb rack comes first.
	for resource: StringName in own.stockpile.amounts().keys():
		own.stockpile.take(resource, own.stockpile.amount(resource))
	own.stockpile.add(&"wood", int(session.buildings.get_def(&"herb_rack").materials[&"wood"]))
	var scored := planner.scored_needs(session.clock.tick)
	assert_true(scored.find(&"herbs") < scored.find(&"kiln"), "what can be built at once, first: %s" % str(scored))


func test_two_at_once_with_people_enough() -> void:
	assert_eq(planner.builds_at_once(), 1, "a band: one at a time")
	_grow_to(SettlementPlanner.TWO_BUILDS_FROM)
	assert_eq(planner.builds_at_once(), 2)


func test_an_upgrade_is_built_in_place() -> void:
	var own := session.settlement
	var store := session.buildings.get_def(&"storehouse")
	_finish(session.construction.start(&"storehouse", planner.site_for(store), session.clock.tick))
	var old := session.props.get_prop(planner.standing_near(PropData.Kind.STOREHOUSE)[0])
	# (A granary-to-be, for the test: built on the storehouse.)
	var better := BuildingDef.new()
	better.id = &"test_granary"
	better.prop_kind = PropData.Kind.WOODSHED
	better.materials = {&"wood": 2}
	better.labor = 30
	better.tags = PackedStringArray(["test_upgrade"])
	better.category = PackedStringArray(["storage"])
	better.upgrade_of = &"storehouse"
	session.buildings._defs[better.id] = better
	var p := planner._upgrade(better, session.clock.tick)
	assert_false(p.is_empty(), "begun")
	assert_eq(str(p["kind"]), ConstructionSystem.UPGRADE)
	assert_eq(int(p["site"]), old.id, "on the old one")
	assert_eq(old.kind, PropData.Kind.STOREHOUSE, "which works on meanwhile")
	assert_true(planner._upgrade(better, session.clock.tick).is_empty(), "one at a time")
	_finish(p)
	var now := session.props.get_prop(old.id)
	assert_not_null(now, "the same building")
	assert_eq(now.kind, PropData.Kind.WOODSHED, "built anew")
	assert_eq(now.condition, PropData.SOUND)
	assert_eq(session.props.of_kind(PropData.Kind.WOODSHED).has(now), true, "kept by its new kind")
	assert_eq(session.building_records.record_of(old.id)["def"], "test_granary", "its record carried over")
	assert_eq(session.events.count_of(&"building_upgraded"), 1, "told")
	assert_has(EventText.text(session.events.latest(&"building_upgraded"), session.people, session.events), "storehouse")
