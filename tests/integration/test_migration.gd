extends TestCase
## Migration and new settlements (M12.3, bible §17.1): what drives people
## away; who goes; where (only what has been explored); the journey; the
## founding — a settlement like the first, with its own fire, homes, stores,
## jobs and plans; its people live there; tiers; history; saving.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440
const V25_FIXTURE := "res://tests/fixtures/saves/v25_world.sav"
const V25_ID := "w1791046405_a1b497b3"

var session: WorldSession
var migration: Migration
var _knobs: Array = []


func before_each() -> void:
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	migration = session.migration
	for knob: StringName in [&"base_death_per_year", &"infant_death_per_year", &"old_age_death_per_year",
			&"accident_per_work_day", &"crowding_chance_per_day", &"partner_chance_per_day", &"conceive_chance_per_day",
			&"starve_chance_per_day", &"illness_death_per_day", &"injury_death_per_day", &"newcomer_chance_per_day"]:
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


## The band has explored all around (and further than it would by itself).
func _explore(reach: int = 28) -> void:
	var fire := session.settlement.fire().tile
	for dy in range(-reach, reach + 1, 2):
		for dx in range(-reach, reach + 1, 2):
			session.settlement.places().mark_visited(fire + Vector2i(dx, dy))


## More people come to live in the first settlement (couples of their own).
func _grow(total: int) -> void:
	var fire := session.settlement.fire().tile
	while session.settlement.member_count() < total:
		var a := session.spawn_person(fire + Vector2i(1, 1))
		var b := session.spawn_person(fire + Vector2i(1, 1))
		a.sex = PersonData.Sex.MALE
		b.sex = PersonData.Sex.FEMALE
		session.households.form_couple(a, b, session.clock.tick, session.ids.next_id())


## The world runs for `minutes` game minutes, as in the soak.
func _run(minutes: int) -> void:
	var minute := Config.time.real_seconds_per_game_minute
	var frame := Config.time.max_frame_delta_s
	for i in minutes:
		var seconds := minute
		while seconds > 0.000001:
			var piece := minf(seconds, frame)
			session.clock.advance(piece)
			seconds -= piece
		session.behavior.step(1.0)
		session.pathfinder.serve(1000000)
		session.movement.step(1.0)
		if session.nodes.due(session.clock.tick):
			session.nodes.settle(session.clock.tick)


## A group sets out and founds a settlement (returns it).
func _found() -> Settlement:
	_explore()
	_grow(14)
	var journey := migration.depart(session.settlement, session.clock.tick)
	assert_false(journey.is_empty(), "a group sets out")
	var minutes := 0
	while session.settlements.size() < 2 and minutes < Config.migration.longest_journey + 60:
		_run(10)
		minutes += 10
	assert_eq(session.settlements.size(), 2, "founded after %d minutes" % minutes)
	return session.settlements.all()[1]


func test_what_drives_people_away() -> void:
	var first := session.settlement
	assert_eq(float(migration.pressure(first, session.clock.tick)["total"]), 0.0, "a band this small sends nobody")
	_grow(17)
	var push := migration.pressure(first, session.clock.tick)
	assert_true(float(push["crowding"]) > 0.0, "the roofs are full (%s)" % push)
	assert_true(float(push["adventure"]) > 0.0)
	assert_eq(float(push["scarcity"]), 0.0)
	# Hungry for days on end.
	first.shortage = Settlement.Shortage.SHORT
	first._low_since = session.clock.tick
	session.clock.tick += (Config.migration.scarce_days + 1) * DAY
	assert_eq(float(migration.pressure(first, session.clock.tick)["scarcity"]), Config.migration.scarcity)
	# Strife.
	var people := first.members()
	var record := session.relationships.ensure(people[0].id, people[1].id)
	record.kinds |= Relationship.Kind.ENEMY
	assert_true(float(migration.pressure(first, session.clock.tick)["conflict"]) > 0.0)
	# Somebody has just set out from here: not again so soon.
	_explore()
	assert_false(migration.depart(first, session.clock.tick).is_empty())
	assert_eq(float(migration.pressure(first, session.clock.tick)["total"]), 0.0, "one group at a time")


func test_who_goes_and_where() -> void:
	_grow(14)
	var group := migration.choose_group(session.settlement, session.clock.tick)
	assert_false(group.is_empty())
	var going: Array = group["members"]
	assert_true(going.size() >= Config.migration.group_least)
	assert_true(session.settlement.member_count() - going.size() >= Config.migration.stay_least, "enough stay behind")
	assert_true(going.has(group["leader"]))
	# Only where someone has been.
	assert_null(migration.destination(session.settlement), "nowhere explored far enough")
	_explore()
	var to: Variant = migration.destination(session.settlement)
	assert_not_null(to, "somewhere explored")
	var fire := session.settlement.fire().tile
	var away := Vector2(to - fire).length()
	assert_true(away >= Config.migration.nearest_settlement and away <= Config.migration.farthest_journey, "%.1f tiles away" % away)
	assert_true(session.pathfinder.is_reachable(fire + Vector2i(1, 0), to))
	assert_eq(session.world.get_water(to), 0.0)
	assert_eq(Migration.direction(Vector2i(0, 0), Vector2i(0, -9)), "north")
	assert_eq(Migration.direction(Vector2i(0, 0), Vector2i(7, 7)), "south-east")


func test_migration_founds_settlement() -> void:
	var first := session.settlement
	var food_before := first.stockpile.food_units()
	_explore()
	_grow(14)
	var journey := migration.depart(first, session.clock.tick)
	var going: Array = (journey["members"] as Array).duplicate()
	assert_true(first.stockpile.food_units() < food_before, "they took food along")
	for id: int in going:
		assert_true(migration.travelling(id))
		assert_eq(BehaviorSystem.activity_of(session.people.get_person(id)), Migration.ACTIVITY)
	var set_out := session.events.of_type(&"migration")
	assert_eq(set_out.size(), 1)
	assert_has(EventText.text(set_out[0], session.people, session.events), "to find new land")
	# The journey: on foot, nothing else on their minds.
	var minutes := 0
	while session.settlements.size() < 2 and minutes < Config.migration.longest_journey + 60:
		_run(10)
		minutes += 10
	assert_eq(session.settlements.size(), 2, "founded after %d minutes" % minutes)
	var own := session.settlements.all()[1]
	assert_eq(own.start_info().settlement_tile, journey["to"])
	assert_eq(session.props.get_prop(own.start_info().campfire_id).kind, PropData.Kind.CAMPFIRE)
	assert_eq(own.start_info().hut_ids.size(), 1, "a first shelter")
	var hut := own.start_info().hut_ids[0]
	for id: int in going:
		var person := session.people.get_person(id)
		assert_eq(person.settlement_id, own.id)
		assert_eq(person.home_building_id, hut)
		assert_false(migration.travelling(id))
	assert_eq(own.member_count(), going.size())
	assert_eq(first.member_count(), 14 - going.size())
	assert_true(own.stockpile.food_units() > 0, "with the food they brought")
	assert_eq(own.founders.size(), going.size())
	assert_eq(own.founded_from, first.id)
	assert_eq(own.tier(), Settlements.Tier.CAMP)
	# History: the founding, because they set out.
	var founded := session.events.of_type(&"settlement_founded")
	var founding := founded[-1]
	assert_eq(founding.causes, PackedInt64Array([set_out[0].id]), "because they set out")
	var leader := session.people.get_person(int(journey["leader"]))
	assert_eq(EventText.text(founding, session.people, session.events), "%s has founded %s's camp" % [leader.given_name, leader.given_name])
	assert_eq(own.display_name(), "%s's camp" % leader.given_name)
	assert_eq(founding.participants[0], leader.id, "the founder first")


func test_each_settlement_lives_on_its_own() -> void:
	var own := _found()
	var first := session.settlement
	var fire := own.fire().tile
	# Its people use its stores, and the first's people theirs.
	var person := own.members()[0]
	var ctx := session.behavior.ctx
	ctx.enter(person)
	assert_eq(ctx.settlement, own)
	assert_eq(ctx.places.storage_tile(&"wood"), own.places().storage_tile(&"wood"))
	assert_true(Vector2(ctx.places.storage_tile(&"wood") - fire).length() < 4.0, "their stores are by their fire")
	ctx.enter(first.members()[0])
	assert_eq(ctx.settlement, first)
	# They see to their own homes: a hut near their fire, by their own builder.
	assert_true(own.planner.homes_short() or own.member_count() <= Config.life.home_room)
	var p := own.planner.plan(session.clock.tick)
	if not p.is_empty():
		assert_eq(session.construction.settlement_of(p), own.id)
		assert_true(Vector2(p["tile"] - fire).length() <= SettlementPlanner.NEAR_REACH, "built at home")
	# The fields: near their own fire.
	session.farming.use_start(own.start_info())
	var plot: Variant = session.farming.next_plot()
	if plot != null:
		assert_true(Vector2(plot - fire).length() <= Config.farming.site_max_distance + 0.5)
	# Their dead lie near their fire.
	var dying := own.members()[-1]
	session.kill_person(dying.id, Lifecycle.CAUSE_OLD_AGE)
	var record := session.archive.get_record(dying.id)
	var grave := session.props.get_prop(record.grave_id)
	assert_not_null(grave)
	assert_true(Vector2(grave.tile - fire).length() <= Graves.GRAVEYARD_REACH, "buried at home")
	# A day of both settlements.
	_run(DAY)
	for someone in own.members():
		assert_eq(someone.settlement_id, own.id)
	assert_true(session.settlements.debug_text().contains("camp"))


func test_a_settlement_nobody_is_left_at_is_abandoned() -> void:
	var own := _found()
	var hut := own.start_info().hut_ids[0]
	var fire := own.fire()
	var p := own.planner.plan(session.clock.tick)
	for person in own.members():
		session.kill_person(person.id, Lifecycle.CAUSE_OLD_AGE)
	assert_eq(own.member_count(), 0)
	migration._abandon_empty()
	assert_eq(session.settlements.size(), 1, "abandoned")
	assert_null(session.settlements.get_settlement(own.id))
	assert_eq(fire.stock, 0, "its fire is cold")
	assert_true(session.construction.projects_of(own.id).is_empty(), "nothing is built there any more")
	if not p.is_empty() and str(p["def"]) != "bridge":
		assert_null(session.props.get_prop(int(p["site"])), "its site is gone")
	assert_true(session.construction.abandoned_homes.has(hut), "its hut is nobody's: it will fall in")
	var gone := session.events.of_type(&"settlement_abandoned")
	assert_eq(EventText.text(gone[0], session.people, session.events), "Nobody is left at %s: it has been abandoned" % own.display_name())
	# The first is never abandoned.
	for person in session.settlement.members():
		session.kill_person(person.id, Lifecycle.CAUSE_OLD_AGE)
	migration._abandon_empty()
	assert_eq(session.settlements.size(), 1)


func test_tiers_and_the_fire_says_whose_it_is() -> void:
	assert_eq(Settlements.tier_for(4), Settlements.Tier.CAMP)
	assert_eq(Settlements.tier_for(10), Settlements.Tier.HAMLET)
	assert_eq(Settlements.tier_for(30), Settlements.Tier.VILLAGE)
	assert_eq(Settlements.tier_for(100), Settlements.Tier.TOWN)
	assert_eq(Settlements.tier_for(500), Settlements.Tier.CITY)
	assert_eq(Settlements.tier_name(Settlements.Tier.HAMLET), "Hamlet")
	var own := _found()
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = own.start_info().campfire_id
	target.tile = own.start_info().settlement_tile
	var report := session.interactions.inspect(target)
	assert_eq(report.settlement_name, own.display_name())
	assert_eq(report.settlement_people, own.member_count())
	target.entity_id = session.settlement.start_info().campfire_id
	assert_eq(session.interactions.inspect(target).settlement_name, "the first camp")


func test_settlements_are_saved() -> void:
	var own := _found()
	var name := own.display_name()
	var hut := own.start_info().hut_ids[0]
	own.stockpile.add(&"stone", 3)
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	assert_true(loaded.ok, loaded.error)
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(loaded.world))
	again.set_process(false)
	assert_eq(again.settlements.size(), 2)
	var kept := again.settlements.all()[1]
	assert_eq(kept.id, own.id)
	assert_eq(kept.display_name(), name)
	assert_eq(kept.start_info().hut_ids, [hut] as Array[int])
	assert_eq(kept.member_count(), own.member_count())
	assert_eq(kept.founders, own.founders)
	assert_eq(kept.stockpile.amount(&"stone"), 3)
	assert_not_null(kept.planner)
	assert_true(kept.places().visited_count() > 0, "they know the land the first know")
	again.queue_free()


func test_a_journey_under_way_is_saved() -> void:
	_explore()
	_grow(14)
	var journey := migration.depart(session.settlement, session.clock.tick)
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(loaded.world))
	again.set_process(false)
	assert_eq(again.migration.journeys.size(), 1)
	assert_true(again.migration.travelling(int(journey["leader"])))
	again.queue_free()


func test_version_25_save_loads() -> void:
	# Written by M12.2 (1b946ce): one settlement only.
	var dir := SaveManager.world_dir(V25_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V25_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 25)
	var loaded := SaveManager.load_world(V25_ID)
	assert_true(loaded.ok, loaded.error)
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	assert_eq(s.settlements.size(), 1)
	assert_eq(s.settlements.primary(), s.settlement)
	assert_eq(s.migration.journeys.size(), 0)
	assert_true(SaveManager.save_world(s, &"test"))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	s.queue_free()
	assert_true(SaveManager.SAVE_VERSION >= 26)
	var data := {"world": {"world_state": {"people": []}}}
	assert_eq(SaveMigrations._v25_to_v26(data)["world"]["world_state"]["settlements"], [])
