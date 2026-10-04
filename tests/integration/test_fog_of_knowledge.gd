extends TestCase
## The fog of knowledge (M13.4, bible §8.7): what the player has seen, what
## the world has explored (been, or seen from there), what it has mapped;
## the regions of the box, found by explorers; the Edge; the fog drawn.

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var session: WorldSession
var knowledge: FogOfKnowledge


func before_each() -> void:
	SaveManager.attach(null)
	SaveManager.open_next = {}
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	knowledge = session.knowledge


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


## A tile far from home that nobody knows, out of doors, someone can stand on.
func _far_tile() -> Vector2i:
	var fire := session.start.settlement_tile
	var best := Vector2i.MAX
	for y in range(-30, 30):
		for x in range(-30, 30):
			var tile := Vector2i(x, y)
			if knowledge.is_known(tile) or not session.pathfinder.can_stand(tile):
				continue
			if best == Vector2i.MAX or Vector2(tile - fire).length() > Vector2(best - fire).length():
				best = tile
	return best


func test_fog_layers() -> void:
	var fire := session.start.settlement_tile
	assert_true(knowledge.is_explored(fire), "home is known from the start")
	assert_false(knowledge.is_seen(fire), "(not yet shown to the player close up)")
	var far := _far_tile()
	assert_ne(far, Vector2i.MAX)
	assert_false(knowledge.is_explored(far) or knowledge.is_seen(far) or knowledge.is_mapped(far))
	# Someone goes there and looks about: explored, all round as far as they see.
	var walker := session.people.all_people()[0]
	walker.flags &= ~PersonData.FLAG_INDOORS
	session.people.move(walker.id, far, Vector2(0.5, 0.5), 0.0)
	var changed := knowledge.look_about()
	assert_false(changed.is_empty(), "the chunks that changed are told")
	assert_true(knowledge.is_explored(far))
	assert_true(knowledge.is_explored(far + Vector2i(FogOfKnowledge.SIGHT - 1, 0)) or not session.world.is_in_bounds(far + Vector2i(FogOfKnowledge.SIGHT - 1, 0)),
		"what they saw from there")
	assert_false(knowledge.is_seen(far), "the world's knowledge is not the player's")
	# The player looks close up: seen.
	var other := Vector2i(-fire.x, -fire.y)
	var before := _already_seen(other)
	assert_eq(knowledge.mark_seen(Rect2i(other, Vector2i(3, 3))), 9 - before)
	assert_true(knowledge.is_seen(other))
	assert_eq(knowledge.mark_seen(Rect2i(other, Vector2i(3, 3))), 0, "seen once is seen")
	assert_false(knowledge.is_mapped(far), "nothing is mapped (cartography: M18)")
	# Saved with the world.
	assert_true(SaveManager.save_world(session, &"test"))
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(SaveManager.load_world(session.world_id).world))
	again.set_process(false)
	assert_true(again.knowledge.is_explored(far))
	assert_true(again.knowledge.is_seen(other))
	assert_eq(again.knowledge.discovered, knowledge.discovered)
	again.queue_free()


func _already_seen(at: Vector2i) -> int:
	var seen := 0
	for y in 3:
		for x in 3:
			if knowledge.is_seen(at + Vector2i(x, y)):
				seen += 1
	return seen


func test_the_regions_of_the_box() -> void:
	var regions := knowledge.regions.regions
	assert_true(regions.size() >= 3, "%d regions" % regions.size())
	var names := {}
	var river := false
	for region in regions:
		assert_false(names.has(region.name), "each its own name (%s)" % region.name)
		names[region.name] = true
		assert_true(region.blocks.size() >= Regions.LEAST_BLOCKS, "no crumbs")
		if region.name == "the river":
			river = true
			assert_eq(region.kind, Regions.Kind.WATER)
	assert_true(river, "the river: %s" % [names.keys()])
	# Every tile of the box belongs to one.
	for y in range(-32, 32, 5):
		for x in range(-32, 32, 5):
			assert_not_null(knowledge.regions.region_at(Vector2i(x, y)))
	# Named by where they lie.
	for region in regions:
		var east := region.centre.x > 12.0 and absf(region.centre.y) < 6.0
		if east and region.kind != Regions.Kind.WATER:
			assert_true(region.name.contains("east"), "%s lies east" % region.name)
	assert_eq(Regions._direction(Vector2(0, -10)), "northern")
	assert_eq(Regions._direction(Vector2(10, 10)), "south-eastern")


func test_explorers_find_regions() -> void:
	var found := knowledge.discovered.size()
	assert_true(found >= 1, "home's own region is known from the start")
	var far := _far_tile()
	var region := knowledge.regions.region_at(far)
	if knowledge.discovered.has(region.id):
		return # (already known: nothing to find there)
	var walker := session.people.all_people()[0]
	walker.flags &= ~PersonData.FLAG_INDOORS
	session.people.move(walker.id, far, Vector2(0.5, 0.5), 0.0)
	knowledge.look_about()
	assert_true(knowledge.discovered.has(region.id))
	var events := session.events.of_type(&"region_found")
	assert_false(events.is_empty())
	assert_eq(EventText.text(events[-1], session.people, session.events), "%s has found %s" % [walker.given_name, region.name])


func test_the_edge() -> void:
	assert_false(knowledge.edge_reached)
	var walker := session.people.all_people()[0]
	walker.flags &= ~PersonData.FLAG_INDOORS
	var wall := Vector2i(session.world.bounds.end.x - 1, session.start.settlement_tile.y)
	session.people.move(walker.id, wall, Vector2(0.5, 0.5), 0.0)
	knowledge.look_about()
	assert_true(knowledge.edge_reached)
	assert_true(session.settlement.knows_how(&"the_edge"), "the first thing the world knows of the box")
	var learned := session.events.of_type(&"knowledge_learned")
	assert_eq(EventText.text(learned[-1], session.people, session.events),
		"%s has come to the Edge: the land ends at a wall nobody can pass" % walker.given_name)
	var count := learned.size()
	session.people.move(walker.id, wall + Vector2i(0, 2), Vector2(0.5, 0.5), 0.0)
	knowledge.look_about()
	assert_eq(session.events.of_type(&"knowledge_learned").size(), count, "once")


func test_the_adventurous_go_further() -> void:
	var walker := session.people.all_people()[0]
	var places := session.settlement.places()
	var rng := RandomNumberGenerator.new()
	var furthest := {}
	for adventure in [0.0, 1.0]:
		walker.traits[Traits.Axis.ADVENTURE] = adventure
		rng.seed = 7
		var most := 0.0
		for i in 300:
			var tile: Variant = places.explore_tile(walker, PersonData.LifeStage.ADULT, rng)
			if tile != null:
				most = maxf(most, Vector2(tile - places.home_tile(walker)).length())
		furthest[adventure] = most
	assert_true(furthest[1.0] > furthest[0.0] + 4.0, "the adventurous go further (%.1f vs %.1f)" % [furthest[1.0], furthest[0.0]])


func test_the_fog_is_drawn() -> void:
	var view: WorldView = preload("res://scripts/rendering/world_view.gd").new()
	add_child(view)
	view.show_world(session.world, session.props, session.start)
	view.show_knowledge(knowledge)
	var fire := session.start.settlement_tile
	var far := _far_tile()
	assert_eq(view.fog_at(fire), 1.0, "home: known")
	assert_eq(view.fog_at(far), 0.0, "far: in the fog")
	assert_near(float(view.terrain_material().get_shader_parameter(&"fog_strength")), Config.world.fog_strength, 0.001)
	knowledge.mark_seen(Rect2i(far, Vector2i(1, 1)))
	view._step_fog(0.0)
	assert_eq(view.fog_at(far), 1.0, "seen: out of the fog")
	view.queue_free()
	await wait_frames(1)


func test_after_the_box_unfolds() -> void:
	# (Seen in a soak: "regions found 9 of 7" — the found ids of the smaller box were kept.)
	# (Someone well away from the walls: near one, they would see into the new
	# land after it unfolds — a new region, rightly found.)
	var walker := session.people.all_people()[0]
	walker.flags &= ~PersonData.FLAG_INDOORS
	var inner := session.world.bounds.grow(-12)
	var spot := session.start.settlement_tile
	for y in range(inner.position.y, inner.end.y):
		for x in range(inner.position.x, inner.end.x):
			var tile := Vector2i(x, y)
			if not knowledge.is_known(tile) and session.pathfinder.can_stand(tile):
				spot = tile
	session.people.move(walker.id, spot, Vector2(0.5, 0.5), 0.0)
	knowledge.look_about()
	var found_before := session.events.of_type(&"region_found").size()
	assert_true(session.unfold())
	knowledge = session.knowledge
	assert_true(knowledge.discovered.size() <= knowledge.regions.regions.size(), "%d of %d" % [knowledge.discovered.size(), knowledge.regions.regions.size()])
	for id: int in knowledge.discovered:
		assert_not_null(knowledge.regions.get_region(id), "a region of the box as it is")
	assert_true(knowledge.discovered.size() >= 1)
	knowledge.look_about()
	assert_eq(session.events.of_type(&"region_found").size(), found_before, "nothing known is found again")
