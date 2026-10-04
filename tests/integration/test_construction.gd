extends TestCase
## Building (M12.1, bible §17.2): the settlement decides what to build from
## what it needs (homes, storage, water) and where (open, dry, even ground
## near the fire); builders bring the materials from the stores and build
## as far as those allow; buildings are damaged by floods and storms and
## repaired; homes nobody lives in fall into ruin; all of it is saved.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440
const V23_FIXTURE := "res://tests/fixtures/saves/v23_world.sav"
const V23_ID := "w1791020207_bcddec02"

var session: WorldSession
var construction: ConstructionSystem
var planner: SettlementPlanner
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
	construction = session.construction
	planner = session.planner
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


## Everything but `need` is satisfied as far as the planner can tell.
func _only(need: StringName) -> void:
	_knob(Config.construction, &"homes_spare_least", -1000 if need != &"home" else 1000)
	_knob(Config.construction, &"storage_room_least", -1000 if need != &"storage" else 1_000_000)
	_knob(Config.construction, &"spoiled_from", 1_000_000)
	_knob(Config.construction, &"well_from", 1_000_000 if need != &"water" else -1)
	_knob(Config.construction, &"cut_off_least", 1_000_000 if need != &"bridge" else 12)


## A building of `def_id` put up at once (materials brought, work done).
func _build(def_id: StringName) -> PropData:
	var tile: Variant = planner.site_for(session.buildings.get_def(def_id))
	assert_not_null(tile, "there is ground for a %s" % def_id)
	var p := construction.start(def_id, tile, session.clock.tick)
	for resource: StringName in construction.still_needed(p):
		construction.deliver(p, resource, int(construction.still_needed(p)[resource]))
	var builder := session.people.all_people()[0]
	while not construction.work(p, builder, 60.0, session.clock.tick):
		pass
	return session.props.prop_at(tile)


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


func test_the_buildings_are_defined() -> void:
	var library := session.buildings
	assert_eq(library.ids(), [&"bridge", &"hut", &"storehouse", &"well", &"workshop"] as Array[StringName])
	for id in library.ids():
		var def := library.get_def(id)
		assert_eq(def.validate(), PackedStringArray(), "%s is well formed" % id)
		assert_true(PropData.BUILDINGS.has(def.prop_kind))
		assert_true(MemoryText.has("BUILDING_" + String(id).to_upper()), "%s can be named" % id)
	assert_eq(library.with_tag("home")[0].id, &"hut")
	assert_eq(library.of_kind(PropData.Kind.WELL).id, &"well")
	assert_eq(library.get_def(&"workshop").tech, &"toolmaking", "not before toolmaking is known (M12.4)")
	assert_eq(UIText.prop_name(PropData.Kind.STOREHOUSE), "Storehouse")
	assert_eq(UIText.prop_name(PropData.Kind.SITE), "Building site")


func test_construction_consumes_materials() -> void:
	var stockpile := session.settlement.stockpile
	var tile: Variant = planner.site_for(session.buildings.get_def(&"hut"))
	assert_not_null(tile)
	var huts_before := session.start.hut_ids.size()
	var p := construction.start(&"hut", tile, session.clock.tick)
	assert_false(p.is_empty())
	var site := session.props.prop_at(tile)
	assert_eq([site.kind, site.variant], [PropData.Kind.SITE, ConstructionSystem.STAKES], "staked out")
	assert_eq(construction.still_needed(p), {&"wood": 12})
	assert_false(construction.can_work(p), "nothing to build with yet")
	assert_eq(session.events.count_of(&"building_begun"), 1)
	# A builder fetches the wood from the stores: it leaves them.
	stockpile.add(&"wood", 20)
	var wood := stockpile.amount(&"wood")
	var builder := session.people.all_people()[0]
	builder.carrying = &""
	builder.carrying_amount = 0
	var handler := BuildStep.new()
	var fetch := BuildStep.fetch(&"wood", 8)
	assert_eq(handler.update(session.behavior.ctx, builder, fetch, 10.0), ActionStep.Status.DONE)
	var carried := builder.carrying_amount
	assert_true(carried > 0 and carried <= 8)
	assert_eq(stockpile.amount(&"wood"), wood - carried, "taken out of the stores")
	var deliver := BuildStep.deliver(int(p["id"]), tile)
	assert_eq(handler.update(session.behavior.ctx, builder, deliver, 10.0), ActionStep.Status.DONE)
	assert_eq(builder.carrying_amount, 0)
	assert_eq(int(p["delivered"]["wood"]), carried)
	# The work goes as far as what has been brought.
	while construction.can_work(p):
		construction.work(p, builder, 30.0, session.clock.tick)
	assert_near(construction.progress(p), float(carried) / 12.0, 0.001)
	assert_eq(construction.deliver(p, &"wood", 100), 12 - carried, "no more than is needed")
	assert_eq(construction.deliver(p, &"stone", 5), 0, "nor what is not")
	var finished := false
	while not finished:
		finished = construction.work(p, builder, 30.0, session.clock.tick)
		if construction.progress(p) >= ConstructionSystem.FRAME_FROM and not finished:
			assert_eq(session.props.prop_at(tile).variant, ConstructionSystem.FRAME, "the frame stands")
	var hut := session.props.prop_at(tile)
	assert_eq(hut.kind, PropData.Kind.HUT, "it stands")
	assert_eq(hut.condition, PropData.SOUND)
	assert_eq(session.start.hut_ids.size(), huts_before + 1, "a home for a household")
	assert_true(session.start.hut_ids.has(hut.id))
	assert_true(construction.projects().is_empty())
	assert_near(float(builder.skills.get("builder", 0.0)), Config.construction.skill_per_building, 0.0001)
	var built := session.events.of_type(&"building_built")
	assert_eq(built.size(), 1)
	assert_eq(built[0].participants, PackedInt64Array([builder.id]))
	assert_eq(built[0].causes.size(), 1, "because it was begun")
	assert_eq(EventText.text(built[0], session.people, session.events),
		"The first hut stands, built by %s" % builder.given_name)
	assert_false(session.pathfinder.can_stand(tile), "nobody walks through a wall")


func test_planner_proposes_storage_when_overflow() -> void:
	_only(&"")
	assert_eq(planner.needs(session.clock.tick), [] as Array[StringName], "nothing called for")
	assert_true(planner.plan(session.clock.tick).is_empty())
	# The stores fill up.
	Config.construction.storage_room_least = 8
	session.settlement.stockpile.add(&"berries", session.settlement.stockpile.room(&"berries"))
	assert_true(session.settlement.stockpile.room(&"berries") < 8)
	assert_eq(planner.needs(session.clock.tick), [&"storage"] as Array[StringName])
	var p := planner.plan(session.clock.tick)
	assert_eq(str(p.get("def", "")), "storehouse")
	assert_true(planner.plan(session.clock.tick).is_empty(), "one building at a time")
	Config.construction.homes_spare_least = 1000
	var home := planner.plan(session.clock.tick)
	assert_eq(str(home.get("def", "")), "hut", "but a home does not wait")
	assert_true(planner.plan(session.clock.tick).is_empty(), "(one home at a time)")
	construction.projects().erase(home)
	session.props.remove(int(home["site"]))
	Config.construction.homes_spare_least = -1000
	var tile: Vector2i = p["tile"]
	var fire := session.settlement.fire().tile
	var distance := Vector2(tile - fire).length()
	assert_true(distance >= Config.construction.site_nearest and distance <= Config.construction.site_farthest,
		"near the fire, not on it (%.1f)" % distance)
	assert_true(session.world.get_height(tile) * session.world.height_step > session.settlement.flood_level,
		"above where the water has been")
	# Food going bad calls for one too.
	construction.projects().clear()
	session.props.remove(int(p["site"]))
	Config.construction.storage_room_least = -1000
	Config.construction.spoiled_from = 5
	session.settlement.spoiled.emit(&"berries", 6)
	assert_eq(planner.needs(session.clock.tick), [&"storage"] as Array[StringName])
	# A storehouse stands: room for more in the stores, food keeps better.
	var room := session.settlement.stockpile.room(&"berries")
	var store := _build(&"storehouse")
	assert_eq(store.kind, PropData.Kind.STOREHOUSE)
	assert_eq(session.settlement.stockpile.room(&"berries"), room + session.buildings.get_def(&"storehouse").capacity)
	assert_eq(planner.needs(session.clock.tick), [] as Array[StringName], "enough for a band this size")


func test_a_hut_when_the_homes_are_full_and_a_well_when_water_is_far() -> void:
	_only(&"home")
	assert_true(planner.homes_short())
	var p := planner.plan(session.clock.tick)
	assert_eq(str(p.get("def", "")), "hut")
	construction.projects().clear()
	session.props.remove(int(p["site"]))
	Config.construction.homes_spare_least = 1
	# Someone without a roof.
	var roofed := session.people.all_people()[0]
	var home := roofed.home_building_id
	roofed.home_building_id = 0
	assert_true(planner.homes_short())
	roofed.home_building_id = home
	_only(&"water")
	assert_true(planner.water_far())
	p = planner.plan(session.clock.tick)
	assert_eq(str(p.get("def", "")), "well")
	_build(&"well")
	assert_false(planner.water_far(), "a well is water near")
	var well := session.props.get_prop(construction.standing(PropData.Kind.WELL)[0])
	assert_eq(session.settlement.places().water_tile(well.tile + Vector2i(1, 0)), well.tile, "to drink from")
	# The workshop waits for toolmaking.
	_only(&"")
	assert_true(planner.plan(session.clock.tick).is_empty())


func test_the_planner_weighs_once_a_day_by_daylight() -> void:
	_only(&"home")
	var now := session.clock.tick
	var midnight := now + DAY - Config.time.minute_of_day(now)
	planner.advance_to(midnight + 3 * 60)
	assert_true(construction.builds().is_empty(), "not in the night")
	planner.advance_to(midnight + 9 * 60)
	assert_eq(construction.builds().size(), 1)


func test_building_damage_repair() -> void:
	var hut := _build(&"hut")
	construction.damage(hut.id, Config.construction.storm_damage, &"storm", session.clock.tick)
	assert_eq(hut.condition, PropData.SOUND - Config.construction.storm_damage)
	assert_true(construction.projects().is_empty(), "a little wear is not mended yet")
	construction.damage(hut.id, Config.construction.flood_damage, &"flood", session.clock.tick)
	var p := construction.project_at(hut.id)
	assert_false(p.is_empty(), "now it is")
	assert_eq(str(p["kind"]), ConstructionSystem.REPAIR)
	assert_true(int(p["needed"]["wood"]) < 12, "less than to build it")
	assert_true(int(p["labor"]) < 180)
	assert_eq(session.events.count_of(&"building_damaged"), 1, "the wear that needs mending, not every storm's")
	var damaged := session.events.of_type(&"building_damaged")
	assert_eq(EventText.text(damaged[-1], session.people, session.events), "The flood has damaged the hut")
	var builder := session.people.all_people()[1]
	construction.deliver(p, &"wood", 100)
	while not construction.work(p, builder, 30.0, session.clock.tick):
		pass
	assert_eq(hut.condition, PropData.SOUND, "mended")
	assert_eq(session.props.prop_at(hut.tile).kind, PropData.Kind.HUT)
	assert_eq(session.events.count_of(&"building_repaired"), 1)
	# Worn through: a ruin.
	construction.damage(hut.id, PropData.SOUND, &"flood", session.clock.tick)
	assert_null(session.props.get_prop(hut.id))
	assert_eq(session.props.prop_at(hut.tile).kind, PropData.Kind.RUIN)
	assert_false(session.start.hut_ids.has(hut.id))
	assert_eq(session.events.count_of(&"building_ruined"), 1)
	assert_true(construction.projects().is_empty())
	# A lived-in home falls: they move in where there is room, or wait for a new roof.
	var home := session.props.get_prop(session.start.hut_ids[0])
	var living := session.people.living_in(home.id)
	assert_false(living.is_empty())
	construction.damage(home.id, PropData.SOUND, &"flood", session.clock.tick)
	assert_null(session.props.get_prop(home.id))
	for person in living:
		if person.home_building_id == home.id:
			assert_true(planner.homes_short(), "someone without a roof")
		else:
			assert_true(session.start.hut_ids.has(person.home_building_id), "%s found room elsewhere" % person.given_name)
	_build(&"hut")
	for person in living:
		assert_true(session.start.hut_ids.has(person.home_building_id), "%s has a roof again" % person.given_name)


func test_a_crowded_household_moves_into_a_new_home() -> void:
	var households := session.households
	var ids := households.ids()
	assert_true(ids.size() >= 2)
	# Two households under one roof.
	var first := ids[0]
	var second := ids[1]
	var shared := households.home_of(first)
	var left := households.home_of(second)
	var crowd := func(household: int, home: int) -> void:
		households._records[household]["home"] = home
		for person in households.members(household):
			person.home_building_id = home
	crowd.call(second, shared)
	_only(&"")
	assert_false(planner.homes_short(), "(a home stands empty now)")
	# The empty home is lived in again (the planner sees to it each day).
	assert_eq(households.settle_empty_homes(), 1)
	assert_false(session.people.living_in(left).is_empty())
	# It falls; they crowd in together again — and when the roof has no room
	# left for a child, a home is called for.
	var back := first if households.home_of(first) == left else second
	crowd.call(back, shared)
	construction.damage(left, PropData.SOUND, &"flood", session.clock.tick)
	var arrivals := 0
	while households.room(shared) > 0 and arrivals < 12:
		arrivals += 1
		households._move_in(session.spawn_person(session.settlement.fire().tile), back, session.clock.tick)
	Config.construction.homes_spare_least = -1000
	assert_ne(households.mover(0, true), 0)
	assert_true(planner.homes_short(), "two households under a full roof")
	var hut := _build(&"hut")
	var moved := [first, second].filter(func(id: int) -> bool: return households.home_of(id) == hut.id)
	assert_eq(moved.size(), 1, "one of them has moved in")
	for person in households.members(moved[0]):
		assert_eq(person.home_building_id, hut.id)
	assert_false(session.people.living_in(hut.id).is_empty())
	# A home for nobody in particular: nobody moves.
	var another := _build(&"hut")
	assert_true(session.people.living_in(another.id).is_empty())


func test_an_empty_home_falls_into_ruin() -> void:
	var hut := _build(&"hut")
	assert_true(session.people.living_in(hut.id).is_empty())
	var now := session.clock.tick
	construction.advance_to(now + DAY)
	construction.advance_to(now + Config.construction.empty_home_days * DAY)
	assert_eq(hut.condition, PropData.SOUND, "a while empty, it still stands as it was")
	var days := 1
	while session.props.get_prop(hut.id) != null and days < 60:
		construction.advance_to(now + (Config.construction.empty_home_days + days) * DAY)
		days += 1
	assert_null(session.props.get_prop(hut.id), "fallen in")
	assert_eq(session.props.prop_at(hut.tile).kind, PropData.Kind.RUIN)
	assert_eq(EventText.text(session.events.of_type(&"building_ruined")[0], session.people, session.events),
		"An empty hut has fallen into ruin")
	# A home people live in does not.
	var lived := session.props.get_prop(session.start.hut_ids[0])
	assert_eq(lived.condition, PropData.SOUND)


func test_building_is_saved() -> void:
	_only(&"home")
	var built := _build(&"storehouse")
	built.condition = 640
	var p := planner.plan(session.clock.tick)
	construction.deliver(p, &"wood", 5)
	construction.work(p, session.people.all_people()[0], 3.0, session.clock.tick)
	session.settlement.spoiled.emit(&"berries", 4)
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	assert_true(loaded.ok, loaded.error)
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(loaded.world))
	again.set_process(false)
	assert_eq(again.props.get_prop(built.id).kind, PropData.Kind.STOREHOUSE)
	assert_eq(again.props.get_prop(built.id).condition, 640, "worn as it was")
	assert_eq(again.construction.projects().size(), 1)
	var kept := again.construction.projects()[0]
	assert_eq([kept["def"], kept["tile"], kept["site"]], [p["def"], p["tile"], p["site"]])
	assert_eq(int(kept["delivered"]["wood"]), 5)
	assert_near(float(kept["done"]), float(p["done"]), 0.001)
	assert_eq(again.props.get_prop(int(kept["site"])).kind, PropData.Kind.SITE)
	assert_eq(again.planner.to_dict(), planner.to_dict())
	assert_eq(again.settlement.stockpile.extra_room, session.buildings.get_def(&"storehouse").capacity, "the storehouse holds")
	again.queue_free()


func test_the_band_builds_what_was_begun() -> void:
	_only(&"")
	session.settlement.stockpile.add(&"wood", 30)
	var p := planner.plan(session.clock.tick) # (nothing called for)
	assert_true(p.is_empty())
	var tile: Variant = planner.site_for(session.buildings.get_def(&"hut"))
	p = construction.start(&"hut", tile, session.clock.tick)
	var minutes := 0
	while session.props.prop_at(tile).kind == PropData.Kind.SITE and minutes < 4 * DAY:
		_run(60)
		minutes += 60
	assert_eq(session.props.prop_at(tile).kind, PropData.Kind.HUT, "built in %d minutes" % minutes)
	assert_true(minutes <= 3 * DAY, "within a few days (%d minutes)" % minutes)
	var built := session.events.of_type(&"building_built")
	assert_false(built[0].participants.is_empty(), "by someone")
	for person in session.people.all_people():
		assert_true(session.pathfinder.can_stand(person.position), "nobody stands inside it")


func test_stone_lying_about_is_brought_to_the_site() -> void:
	_only(&"")
	var stones := func() -> int:
		var n := 0
		for object in session.loose.all_objects():
			if BuildStep.STONES.has(object.kind):
				n += 1
		return n
	var before: int = stones.call()
	assert_true(before > 0)
	assert_eq(session.settlement.stockpile.amount(&"stone"), 0, "none in the stores")
	var tile: Variant = planner.site_for(session.buildings.get_def(&"storehouse"))
	var p := construction.start(&"storehouse", tile, session.clock.tick)
	construction.deliver(p, &"wood", 16)
	var minutes := 0
	while session.props.prop_at(tile).kind == PropData.Kind.SITE and minutes < 5 * DAY:
		_run(60)
		minutes += 60
	assert_eq(session.props.prop_at(tile).kind, PropData.Kind.STOREHOUSE, "built in %d minutes" % minutes)
	assert_true(stones.call() < before, "with stones that lay about (%d of %d left)" % [stones.call(), before])


func test_stone_is_broken_from_rocky_ground_once_none_lies_about() -> void:
	# Every stone lying about has been taken.
	for object in session.loose.all_objects():
		if BuildStep.STONES.has(object.kind):
			session.loose.remove(object.id)
	var tile: Variant = planner.site_for(session.buildings.get_def(&"storehouse"))
	var ctx := session.behavior.ctx
	var steps := Planner._stone_steps(tile, ctx)
	assert_eq(steps.size(), 2)
	assert_eq(steps[1]["type"], "break", "stone from rocky ground")
	var rock: Vector2i = steps[1]["at"]
	assert_eq(session.world.get_terrain(rock), ChunkData.Terrain.ROCK)
	# Breaking it gives a load of stone.
	var person := session.people.all_people()[0]
	person.carrying = &""
	person.carrying_amount = 0
	var handler := BuildStep.new()
	var step: Dictionary = steps[1]
	var status := ActionStep.Status.RUNNING
	while status == ActionStep.Status.RUNNING:
		status = handler.update(ctx, person, step, 5.0)
	assert_eq(status, ActionStep.Status.DONE)
	assert_eq(person.carrying, &"stone")
	assert_eq(person.carrying_amount, ctx.carry_capacity(&"stone"))


func test_version_23_save_loads() -> void:
	# Written by M11.4 (80e2a02): before anything was built.
	var dir := SaveManager.world_dir(V23_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V23_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 23)
	var loaded := SaveManager.load_world(V23_ID)
	assert_true(loaded.ok, loaded.error)
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	assert_true(s.construction.projects().is_empty())
	assert_eq(s.settlement.stockpile.extra_room, 0)
	for prop in s.props.all_props():
		assert_eq(prop.condition, PropData.SOUND)
	assert_not_null(s.planner.site_for(s.buildings.get_def(&"hut")), "it can build")
	assert_true(SaveManager.save_world(s, &"test"))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	s.queue_free()
	assert_true(SaveManager.SAVE_VERSION >= 24)
	var data := {"world": {"world_state": {"people": []}}}
	assert_eq(SaveMigrations._v23_to_v24(data)["world"]["world_state"]["construction"], {})
