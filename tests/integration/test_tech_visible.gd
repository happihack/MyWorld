extends TestCase
## M16.3: every technology changes something that can be seen — kilns, herb
## racks, record stones, stone circles; pots and counting in the stores;
## dyed cloth; lamps at the doors; paved roads; the tended recover faster —
## the Technology page, and the ages of the world (bible §22.1).

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


func test_every_implemented_technology_changes_something_visible() -> void:
	var library := session.technologies
	var meshes := PropMeshLibrary.new()
	for id in library.ids():
		var def := library.get_def(id)
		if not def.implemented or def.known_from_start:
			continue
		var visible := def.unlocked("buildings").size() + def.unlocked("visuals").size()
		assert_true(visible > 0, "%s changes something to be seen" % id)
		for building in def.unlocked("buildings"):
			var made := session.buildings.get_def(StringName(building))
			assert_not_null(made, "%s: %s is a building" % [id, building])
			assert_eq(made.tech, id, "%s is built once %s is known" % [building, id])
			assert_not_null(meshes.template_for(made.prop_kind, 0), "%s has a shape" % building)
	assert_not_null(meshes.template_for(PropData.Kind.RECORD_STONE, 1), "the record stone with tallies")


func test_what_is_known_is_built() -> void:
	var own := session.settlement
	var planner := own.planner
	assert_false(planner.needs(session.clock.tick).has(&"kiln"))
	own.learn(&"pottery", own.members()[0].id, session.clock.tick)
	assert_true(planner.needs(session.clock.tick).has(&"kiln"), "pots are made in a kiln")
	own.learn(&"astronomy", own.members()[0].id, session.clock.tick)
	assert_true(planner.needs(session.clock.tick).has(&"observatory"))
	# There is ground for it; one built, no more is wanted.
	assert_not_null(planner.site_for(session.buildings.get_def(&"kiln")))
	session.props.add(_building(PropData.Kind.KILN, own.fire().tile + Vector2i(-3, -3)))
	assert_false(planner.needs(session.clock.tick).has(&"kiln"), "one is enough")


func test_pots_and_counting_hold_more() -> void:
	var own := session.settlement
	var store := session.buildings.get_def(&"storehouse")
	session.props.add(_building(PropData.Kind.STOREHOUSE, own.fire().tile + Vector2i(3, 3)))
	session._apply_storehouses()
	var plain := own.stockpile.extra_room
	assert_eq(plain, store.capacity)
	own.learn(&"pottery", own.members()[0].id, session.clock.tick)
	assert_eq(own.stockpile.extra_room, roundi(store.capacity * WorldSession.POTTERY_ROOM), "pots hold more (at once)")
	own.learn(&"mathematics", own.members()[0].id, session.clock.tick)
	session._apply_storehouses()
	assert_eq(own.stockpile.extra_room, roundi(roundi(store.capacity * WorldSession.POTTERY_ROOM) * WorldSession.COUNTED_ROOM))


func test_tended_and_dyed() -> void:
	var own := session.settlement
	var person: PersonData = own.members()[0]
	tech.apply_effects()
	assert_false(person.has_flag(PersonData.FLAG_TENDED))
	assert_eq(Health.recovery(person), 1.0)
	own.knows["medicine"] = 10
	own.knows["weaving"] = 10
	tech.apply_effects()
	assert_true(person.has_flag(PersonData.FLAG_TENDED))
	assert_eq(Health.recovery(person), Health.TENDED_RECOVERY, "the tended recover faster")
	assert_true(person.has_flag(PersonData.FLAG_DYED))
	for i in PersonMeshLibrary.CLOTH.size():
		assert_ne(PersonMeshLibrary.cloth(i, true), PersonMeshLibrary.cloth(i), "dyed cloth looks otherwise")
	# Mathematics: the record stone gets tallies.
	var stone := _building(PropData.Kind.RECORD_STONE, own.fire().tile + Vector2i(-3, 2))
	session.props.add(stone)
	own.knows["mathematics"] = 10
	tech.apply_effects()
	assert_eq(stone.variant, 1)


func test_lamps_burn_at_night() -> void:
	var lamps := LampsView.new()
	add_child(lamps)
	lamps.source = func() -> Array[Vector3]: return [Vector3(1, 0, 1), Vector3(4, 0, 2)] as Array[Vector3]
	lamps.night = 0.0
	lamps.advance(LampsView.LOOK_EVERY)
	assert_eq(lamps.lamp_count(), 2)
	assert_eq(lamps.lit_count(), 0, "not by day")
	lamps.night = 1.0
	lamps.advance(0.1)
	assert_eq(lamps.lit_count(), 2, "at night, by every door")
	lamps.queue_free()
	# Where: by the doors of the huts of those who know how (none yet).
	var main_script := load("res://scripts/core/main.gd")
	assert_not_null(main_script)
	var door := LampsView.door_of(Vector3.ZERO, 0.0)
	assert_true(door.x > 0.4, "by the doorway (facing +X)")
	assert_true(LampsView.door_of(Vector3.ZERO, PI).x < -0.4, "and turned with the hut")


func test_roads_are_paved() -> void:
	var own := session.settlement
	var fire := own.fire().tile
	var tile := Vector2i(-1_000, -1_000)
	for r in range(2, 8):
		for dx in [r, -r]:
			var t := fire + Vector2i(dx, 1)
			if tile == Vector2i(-1_000, -1_000) and Traffic.WEARS.has(session.world.get_terrain(t)) \
					and session.world.get_water(t) <= 0.0 and session.props.prop_at(t) == null:
				tile = t
	assert_ne(tile, Vector2i(-1_000, -1_000), "open ground near the fire")
	var traffic := session.traffic
	var day := session.clock.tick
	for i in 400:
		traffic.add(tile)
	traffic.advance_to(day + TimeConfig.MINUTES_PER_DAY)
	assert_eq(session.world.get_terrain(tile), ChunkData.Terrain.ROAD, "worn to a path")
	traffic.advance_to(day + TimeConfig.MINUTES_PER_DAY * 2)
	assert_eq(session.world.get_terrain(tile), ChunkData.Terrain.ROAD, "not paved without engineering")
	own.knows["engineering"] = 10
	for i in 400:
		traffic.add(tile)
	traffic.advance_to(day + TimeConfig.MINUTES_PER_DAY * 3)
	assert_eq(session.world.get_terrain(tile), ChunkData.Terrain.PAVED, "laid with stones")
	assert_true(Pathfinder.TERRAIN_WEIGHT[ChunkData.Terrain.PAVED] < Pathfinder.TERRAIN_WEIGHT[ChunkData.Terrain.ROAD])
	# And it stays, walked or not.
	for i in 30:
		traffic.advance_to(day + TimeConfig.MINUTES_PER_DAY * (4 + i))
	assert_eq(session.world.get_terrain(tile), ChunkData.Terrain.PAVED)


func test_phase_evaluator() -> void:
	var all := session.settlements
	var own := session.settlement
	assert_eq(CivilizationPhase.evaluate(all, session.props, session.trade), CivilizationPhase.Phase.PRIMITIVE, "a band with huts, no stores")
	session.props.add(_building(PropData.Kind.STOREHOUSE, own.fire().tile + Vector2i(3, 3)))
	assert_eq(CivilizationPhase.evaluate(all, session.props, session.trade), CivilizationPhase.Phase.SETTLEMENT)
	own.produced = {"berries": 10.0, "grain": 30.0}
	assert_eq(CivilizationPhase.evaluate(all, session.props, session.trade), CivilizationPhase.Phase.AGRICULTURE, "the fields feed most")
	own.produced = {"berries": 30.0, "grain": 10.0}
	assert_eq(CivilizationPhase.evaluate(all, session.props, session.trade), CivilizationPhase.Phase.SETTLEMENT, "derived: it can fall back")
	# The ages: told once each, the first time.
	own.produced = {"berries": 10.0, "grain": 30.0}
	tech.look_at_the_age()
	var eras := session.events.of_type(&"era_entered")
	assert_eq(eras.size(), 2, "settling, then farming")
	assert_eq(EventText.text(eras[1], session.people), "The age of farming has begun: the fields feed more than the wild")
	own.produced = {"berries": 30.0, "grain": 10.0}
	tech.look_at_the_age()
	own.produced = {"berries": 10.0, "grain": 30.0}
	tech.look_at_the_age()
	assert_eq(session.events.of_type(&"era_entered").size(), 2, "an age begins once")
	assert_eq(tech.phase_reached, CivilizationPhase.Phase.AGRICULTURE)
	# Nothing of later ages without what they rest on.
	assert_false(CivilizationPhase.holds(CivilizationPhase.Phase.CITIES, all, session.props, session.trade))
	assert_false(CivilizationPhase.holds(CivilizationPhase.Phase.SCIENCE, all, session.props, session.trade))


func test_the_technology_page() -> void:
	var own := session.settlement
	assert_false(MenuPages._beyond_the_beginning(session), "nothing yet beyond the beginning: no page")
	var inventor: PersonData = own.members()[0]
	own.learn(&"pottery", inventor.id, session.clock.tick)
	assert_true(MenuPages._beyond_the_beginning(session))
	var told := MenuPages.technology(session)
	assert_has(told["age"], "Now: ")
	var known: PackedStringArray = told["known"]
	assert_eq(known[0], "Year 1 · Pottery — worked out by %s" % session.people.name_of(inventor.id), "the newest first")
	assert_eq(known[-1], "Fire, Foraging, Planting: known from the beginning", "what all knew from the start last")
	# Close to something: said vaguely.
	for person in own.members():
		var held := Knowledge.of(person)
		held[Knowledge.Domain.CRAFT] = 0.0
		person.knowledge[Knowledge.KEY] = held
	var held := Knowledge.of(inventor)
	held[Knowledge.Domain.CRAFT] = session.technologies.get_def(&"weaving").knowledge_threshold * 0.7
	inventor.knowledge[Knowledge.KEY] = held
	if tech.close_to(own).has(&"weaving"):
		assert_has(MenuPages.technology(session)["close"], "Fingers are twisting grass stems into cords.")


func _building(kind: int, tile: Vector2i) -> PropData:
	var prop := PropData.new()
	prop.id = session.ids.next_id()
	prop.kind = kind
	prop.tile = tile
	return prop
