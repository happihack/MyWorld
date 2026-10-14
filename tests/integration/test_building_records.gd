extends TestCase
## Buildings & villagers F5: building records. Every building but the homes
## has one: when it went up and who built it, who worked there, what it
## weathered and when it was mended, when it fell (the ruin keeps it). It
## comes to have a name — the First Storehouse, Asha's Bridge, the Old
## Workshop — and its card tells all of it. Saved with the world.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440

var session: WorldSession
var records: BuildingRecords


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	records = session.building_records


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


## `def` built at once where the planner would put it, by `builder`.
func _build(def: StringName, builder: PersonData) -> PropData:
	var planner := session.settlement.planner
	var tile: Variant = planner.site_for(session.buildings.get_def(def))
	assert_not_null(tile)
	var p := session.construction.start(def, tile, session.clock.tick)
	for resource: StringName in session.construction.still_needed(p):
		session.construction.deliver(p, resource, int(session.construction.still_needed(p)[resource]))
	while not session.construction.work(p, builder, 60.0, session.clock.tick):
		pass
	return session.props.prop_at(tile)


func test_a_building_is_remembered() -> void:
	var builder := session.people.all_people()[0]
	var store := _build(&"storehouse", builder)
	assert_true(records.has_record(store.id), "a record of it")
	assert_eq(records.name_of(store.id, session.clock.tick), "the First Storehouse")
	var lines := records.lines_of(store.id, session.clock.tick)
	assert_eq(lines[0], ["Called", "The First Storehouse"])
	assert_eq(lines[1], ["Built", "this year by %s" % builder.given_name])
	# A second: just a storehouse — until it is old.
	var second := _build(&"storehouse", builder)
	assert_eq(records.name_of(second.id, session.clock.tick), "")
	var later := session.clock.tick + BuildingRecords.OLD_YEARS * Config.time.ticks_per_year()
	assert_eq(records.name_of(second.id, later), "the Old Storehouse")
	# What it weathered, and its mending.
	session.construction.damage(store.id, 400, &"flood", session.clock.tick)
	records.on_event(store.id, &"repaired", session.clock.tick)
	lines = records.lines_of(store.id, session.clock.tick)
	assert_true(lines.has(["Weathered", "a flood"]), str(lines))
	assert_true(lines.has(["Mended", "once"]), str(lines))
	# Homes are not recorded.
	var hut := _build(&"hut", builder)
	assert_false(records.has_record(hut.id))


func test_a_ruin_keeps_the_record_and_it_is_saved() -> void:
	var builder := session.people.all_people()[0]
	var store := _build(&"storehouse", builder)
	var tile := store.tile
	session.construction.damage(store.id, PropData.SOUND, &"flood", session.clock.tick)
	var ruin := session.props.prop_at(tile)
	assert_eq(ruin.kind, PropData.Kind.RUIN, "fallen")
	assert_true(records.has_record(ruin.id), "the ruin keeps it")
	var lines := records.lines_of(ruin.id, session.clock.tick)
	assert_true(lines.has(["Fell", "this year"]), str(lines))
	# Saved and read back.
	var again := BuildingRecords.new()
	assert_eq(again.from_dict(bytes_to_var(var_to_bytes(records.to_dict()))), 0)
	assert_eq(again.size(), records.size())
	assert_eq(again.record_of(ruin.id)["def"], "storehouse")
	assert_eq(again.from_dict({"records": {"x": 1, "7": "no"}}), 2, "nonsense dropped")


func test_who_worked_there() -> void:
	var own := session.settlement
	own.learn(&"toolmaking", 0, session.clock.tick)
	var builder := session.people.all_people()[0]
	var shop := _build(&"workshop", builder)
	var maker := session.people.all_people()[1]
	maker.occupation_id = &"toolmaker"
	for day in 3:
		records.each_day(session.settlements)
	var lines := records.lines_of(shop.id, session.clock.tick)
	assert_true(lines.has(["Worked by", "one person"]), str(lines))
	# It shows on its card.
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = shop.id
	target.entity_kind = SpatialIndex.KIND_BUILDING
	target.tile = shop.tile
	var report := session.interactions.inspect(target)
	assert_true(report.history_lines.has(["Worked by", "one person"]), "told on its card: %s" % str(report.history_lines))


func test_an_old_building_comes_to_a_name() -> void:
	var builder := session.people.all_people()[0]
	_build(&"storehouse", builder)
	var second := _build(&"storehouse", builder)
	records._names_now(session.clock.tick)
	assert_eq(session.events.count_of(&"building_named"), 0, "not yet")
	records._names_now(session.clock.tick + BuildingRecords.OLD_YEARS * Config.time.ticks_per_year())
	assert_eq(session.events.count_of(&"building_named"), 1, "the second, grown old (the first had its name from the start)")
	assert_has(EventText.text(session.events.latest(&"building_named"), session.people, session.events), "the Old Storehouse")
	records._names_now(session.clock.tick + BuildingRecords.OLD_YEARS * Config.time.ticks_per_year())
	assert_eq(session.events.count_of(&"building_named"), 1, "told once")
	assert_true(records.has_record(second.id))
