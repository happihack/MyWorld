extends TestCase
## Wild food (the owner, 2026-10-06): mushrooms on damp ground by the woods,
## roots in the meadows, nuts under the broadleaf trees in autumn — foraged
## like berries, kept like food, marked as remedies for later; in worlds
## made before, too.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const V28_FIXTURE := "res://tests/fixtures/saves/v28_world.sav"

var session: WorldSession
var ctx: AiContext


func before_each() -> void:
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.behavior.enabled = false
	ctx = session.behavior.ctx


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


func _of_kind(kind: PropData.Kind) -> Array[PropData]:
	var out: Array[PropData] = []
	for prop in session.props.all_props():
		if prop.kind == kind:
			out.append(prop)
	return out


func _forager() -> PersonData:
	for person in session.people.all_people():
		if ctx.stage_of(person) == PersonData.LifeStage.ADULT:
			person.occupation_id = &"forager"
			person.carrying = &""
			person.carrying_amount = 0
			return person
	return null


func test_the_foods() -> void:
	for id: StringName in [&"mushrooms", &"roots", &"nuts"]:
		var def := session.resources.get_def(id)
		assert_not_null(def, "%s is defined" % id)
		assert_true(def.is_food(), "%s is food" % id)
		assert_true(MemoryText.has("RES_" + String(id).to_upper()), "%s has a name" % id)
		assert_true(LooseObject.PILE_RESOURCES.has(id), "%s is piled in the stores" % id)
	var mushrooms := session.resources.get_def(&"mushrooms")
	var roots := session.resources.get_def(&"roots")
	var nuts := session.resources.get_def(&"nuts")
	assert_true(mushrooms.spoil_days < roots.spoil_days and roots.spoil_days < nuts.spoil_days, "nuts keep longest, mushrooms least")
	assert_true(mushrooms.remedy and roots.remedy, "for herb lore, later")
	assert_false(nuts.remedy)
	assert_eq(UIText.prop_name(PropData.Kind.MUSHROOM), "Mushrooms")
	assert_eq(UIText.prop_name(PropData.Kind.ROOTS), "Wild roots")


func test_they_grow_in_the_world() -> void:
	var mushrooms := _of_kind(PropData.Kind.MUSHROOM)
	var roots := _of_kind(PropData.Kind.ROOTS)
	var bushes := _of_kind(PropData.Kind.BUSH)
	print("    forage: %d bushes, %d mushrooms, %d roots" % [bushes.size(), mushrooms.size(), roots.size()])
	assert_true(mushrooms.size() >= 3, "mushrooms (%d)" % mushrooms.size())
	assert_true(roots.size() >= 3, "roots (%d)" % roots.size())
	for prop in mushrooms + roots:
		assert_eq(session.world.get_water(prop.tile), 0.0, "on dry ground")
		var terrain := session.world.get_terrain(prop.tile)
		assert_true(terrain == ChunkData.Terrain.GRASS or terrain == ChunkData.Terrain.DIRT, "on open ground")
		assert_true(session.pathfinder.can_stand(prop.tile), "walked over, like grass")
	assert_eq(ResourceNodes.resource_for(mushrooms[0]), &"mushrooms")
	assert_eq(ResourceNodes.resource_for(roots[0]), &"roots")


func test_by_the_seasons() -> void:
	var nodes := session.nodes
	var mushroom := _of_kind(PropData.Kind.MUSHROOM)[0]
	var root := _of_kind(PropData.Kind.ROOTS)[0]
	var year := Config.time.ticks_per_year()
	var season := year / Config.time.seasons_per_year
	var winter := (session.clock.tick / year + 1) * year + 3 * season + 10
	nodes.settle(winter)
	assert_eq(nodes.available(mushroom), 0, "no mushrooms in winter")
	assert_true(nodes.available(root) > 0, "roots are dug all the year round")
	nodes.settle(winter + season) # (spring)
	assert_true(nodes.available(mushroom) > 0, "mushrooms again in spring")


func test_foragers_gather_them() -> void:
	var forager := _forager()
	# Nothing but roots near: roots it is.
	for prop in _of_kind(PropData.Kind.BUSH) + _of_kind(PropData.Kind.MUSHROOM):
		session.props.remove(prop.id)
	var place := ctx.places.work_place(forager, &"bush", ctx.rng)
	assert_false(place.is_empty(), "somewhere to forage")
	assert_eq(session.props.get_prop(int(place["id"])).kind, PropData.Kind.ROOTS)
	assert_eq(ctx.gatherable(int(place["id"])), &"roots", "carried home as roots")
	var steps := Planner.plan(&"work", forager, ctx)
	assert_eq(str(steps[1]["type"]), "work")


func test_nuts_fall_in_autumn_and_are_gathered() -> void:
	var year := Config.time.ticks_per_year()
	var season := year / Config.time.seasons_per_year
	session.clock.tick = (session.clock.tick / year + 1) * year + season + 10 # (summer)
	session._let_nuts_fall()
	assert_eq(_nuts().size(), 0, "not in summer")
	session.clock.tick += season # (autumn)
	for day in 10:
		session._let_nuts_fall()
	var nuts := _nuts()
	assert_true(nuts.size() > 0, "nuts under the trees")
	assert_true(nuts.size() <= WorldSession.NUTS_LYING_MOST, "but not without end (%d)" % nuts.size())
	for nut in nuts:
		assert_eq(nut.variant, LooseObject.NUT_VARIANT)
	# Picked up as nuts.
	for n in 300:
		session.loose_system.step(0.05)
	var forager := _forager()
	var lying := nuts[0]
	assert_true(WorkStep.is_fallen_fruit(lying))
	var picked := WorkStep.pick_fruit(ctx, forager, Vector2i(lying.position.floor()))
	assert_true(picked >= 1)
	assert_eq(forager.carrying, &"nuts")


func _nuts() -> Array[LooseObject]:
	var out: Array[LooseObject] = []
	for object in session.loose.all_objects():
		if object.kind == LooseObject.Kind.FRUIT and object.resource == &"nuts":
			out.append(object)
	return out


func test_in_a_world_made_before() -> void:
	# A world saved before there were mushrooms and roots: they grow there too,
	# on empty ground only — what was built stands where it stood.
	var header := SaveContainer.read_header(V28_FIXTURE)
	assert_true(header.ok)
	var world_id := str(header.header.get("world_id", ""))
	DirAccess.make_dir_recursive_absolute(SaveManager.world_dir(world_id))
	var copy := FileAccess.open(SaveManager.world_dir(world_id).path_join(SaveManager.SAVE_FILE), FileAccess.WRITE)
	copy.store_buffer(FileAccess.get_file_as_bytes(V28_FIXTURE))
	copy.close()
	var loaded := SaveManager.load_world(world_id)
	assert_true(loaded.ok, loaded.error)
	var old: WorldSession = SessionScript.new()
	add_child(old)
	assert_true(old.load_from(loaded.world))
	old.set_process(false)
	var huts := 0
	var forage := 0
	var tiles := {}
	for prop in old.props.all_props():
		assert_false(tiles.has(prop.tile), "one thing to a tile (%s)" % prop.tile)
		tiles[prop.tile] = true
		if prop.kind == PropData.Kind.HUT:
			huts += 1
		elif prop.kind == PropData.Kind.MUSHROOM or prop.kind == PropData.Kind.ROOTS:
			forage += 1
	assert_true(huts > 0, "its huts stand")
	assert_true(forage > 0, "and wild food has come up")
	old.queue_free()
