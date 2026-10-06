extends TestCase
## Resources and nodes (M7.1): what resources there are, trees and bushes as
## nodes that give up what they hold and grow it back (and look it), people
## gathering, carrying and storing, and piles the player can move.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const V8_FIXTURE := "res://tests/fixtures/saves/v8_world.sav"
const V8_ID := "w1790881698_74a27de9"

var session: WorldSession
var behavior: BehaviorSystem
var ctx: AiContext
var nodes: ResourceNodes
var piles: PileStore
var config: ResourcesConfig


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
	behavior = session.behavior
	ctx = behavior.ctx
	nodes = session.nodes
	piles = session.piles
	config = Config.resources


func after_each() -> void:
	Config.settlement.fire_wood_per_day = SettlementConfig.new().fire_wood_per_day
	Config.settlement.wood_days_wanted = SettlementConfig.new().wood_days_wanted
	Config.settlement.urgent_from = SettlementConfig.new().urgent_from
	Config.construction.cut_off_least = ConstructionConfig.new().cut_off_least
	Config.construction.storage_room_least = ConstructionConfig.new().storage_room_least
	session.queue_free()
	await wait_frames(1)


func _run(minutes: float, step: float = 0.5, of: WorldSession = null) -> void:
	var s := of if of != null else session
	var left := minutes
	while left > 0.0001:
		var dt := minf(step, left)
		var seconds := dt * Config.time.real_seconds_per_game_minute
		while seconds > 0.000001:
			var piece := minf(seconds, Config.time.max_frame_delta_s)
			s.clock.advance(piece)
			seconds -= piece
		s.behavior.step(dt)
		s.pathfinder.serve(1_000_000)
		s.movement.step(dt)
		if s.nodes.due(s.clock.tick):
			s.nodes.settle(s.clock.tick)
		left -= dt


func _set_hour(hour: float) -> void:
	session.clock.tick = posmod(roundi((hour - Config.time.start_hour) * 60.0), 1440) + 1440


func _adult(occupation: StringName = &"woodcutter") -> PersonData:
	for p in session.people.all_people():
		if p.occupation_id == occupation:
			return p
	return null


func _calm(person: PersonData) -> PersonData:
	person.needs = PackedFloat32Array([0.9, 0.95, 0.9, 0.9, 0.6, 1.0])
	return person


## Takes away what the settlement began with (for tests that count piles).
func _empty_stores() -> void:
	for pile in piles.piles():
		session.loose.remove(pile.id)
	session.settlement.jobs.refresh(session.settlement, session.clock.tick)


## For tests about gathering alone: the fire burns next to nothing (but
## the same amount of wood is wanted), and nobody takes up a job that is not
## their trade (see test_settlement for those).
func _gathering_only() -> void:
	Config.settlement.fire_wood_per_day = 0.01
	Config.settlement.wood_days_wanted = 1800.0
	Config.settlement.urgent_from = 2.0
	Config.construction.cut_off_least = 1_000_000 # (no bridge across wanting wood)
	Config.construction.storage_room_least = -1000 # (nor a woodshed, when the wood piles fill)
	_empty_stores()


## Everyone but `people` stands still for the length of the test.
func _only(people: Array) -> void:
	for p in session.people.all_people():
		if not people.has(p):
			behavior.set_plan(p, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(1000000.0)])


## A prop of `kind` near the settlement.
func _near(kind: PropData.Kind) -> PropData:
	var best: PropData = null
	var home := session.start.settlement_tile
	for prop in session.props.all_props():
		if prop.kind == kind and (best == null or (prop.tile - home).length_squared() < (best.tile - home).length_squared()):
			best = prop
	return best


## Everything of `resource` there is: on nodes that are not whole (what has
## been taken from them is the difference), in arms, and in piles.
func _carried(resource: StringName) -> int:
	var total := 0
	for p in session.people.all_people():
		if p.carrying == resource:
			total += p.carrying_amount
	return total


func _missing_from_nodes(resource: StringName) -> int:
	var missing := 0
	for prop in session.props.all_props():
		if prop.stock >= 0 and nodes.resource_of(prop) == resource:
			missing += nodes.capacity(prop) - prop.stock
	return missing


func _target_of(pile: LooseObject) -> Picker.Result:
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = pile.id
	target.tile = pile.tile()
	return target


# --- what there is --------------------------------------------------------------------------------

func test_resources_are_defined_in_data() -> void:
	var library := session.resources
	assert_eq(library.problems.size(), 0, str(library.problems))
	assert_eq(library.ids(), [&"berries", &"clay", &"fish", &"grain", &"herbs", &"meat", &"stone", &"tools", &"water", &"wood"] as Array[StringName])
	assert_eq(library.of_category(ResourceDef.Category.FOOD), [&"berries", &"fish", &"grain", &"meat"] as Array[StringName])
	assert_eq(library.of_category(ResourceDef.Category.MATERIAL), [&"clay", &"stone", &"tools", &"wood"] as Array[StringName])
	assert_eq(library.of_category(ResourceDef.Category.WATER), [&"water"] as Array[StringName])
	assert_eq(library.of_category(ResourceDef.Category.MEDICINE), [&"herbs"] as Array[StringName])
	for id in library.ids():
		var def := library.get_def(id)
		assert_eq(def.validate().size(), 0, String(id))
		assert_true(def.stack >= 1 and def.weight > 0.0)
		assert_true(LooseObject.PILE_RESOURCES.has(id), "%s has a pile to lie in" % id)
		assert_ne(UIText.resource_name(id), "something", "%s has a name" % id)
	var wood := library.get_def(&"wood")
	var berries := library.get_def(&"berries")
	assert_false(wood.is_food())
	assert_false(wood.spoils())
	assert_true(berries.is_food() and berries.spoils())
	assert_true(library.get_def(&"clay").defined_only and library.get_def(&"herbs").defined_only, "defined for later")
	assert_false(library.get_def(&"grain").defined_only)
	# How much one carries: by weight, at least one, at most so many.
	assert_eq(wood.units_carried(8.0, 6), 2)
	assert_eq(library.get_def(&"stone").units_carried(8.0, 6), 1)
	assert_eq(library.get_def(&"stone").units_carried(1.0, 6), 1, "at least one")
	assert_eq(berries.units_carried(8.0, 6), 6, "not more than arms hold")
	assert_eq(ctx.carry_capacity(&"wood"), 2)
	assert_eq(ctx.carry_capacity(&"berries"), 6)
	# Unusable definitions are refused.
	var other := ResourceLibrary.new()
	var nameless := ResourceDef.new()
	assert_false(other.add(nameless))
	var twin := ResourceDef.new()
	twin.id = &"wood"
	assert_true(other.add(twin))
	assert_false(other.add(twin.duplicate()), "defined twice")
	assert_eq(other.size(), 1)
	assert_true(other.problems.size() >= 2)
	# The numbers.
	assert_eq(config.validate().size(), 0, str(config.validate()))
	assert_eq(Config.problems.size(), 0, str(Config.problems))
	for key: StringName in [ResourceNodes.TREE, ResourceNodes.BUSH, ResourceNodes.ROCK, ResourceNodes.SHOAL]:
		var settings := config.node(key)
		assert_false(settings.is_empty(), "%s is a node" % key)
		assert_true(library.has_def(settings["resource"]), "%s yields something there is" % key)
	assert_eq(config.node(&"cloud"), {})
	assert_eq(config.storage_offset(ResourceDef.Category.FOOD), Vector2i(-2, 1))
	assert_eq(config.storage_offset(ResourceDef.Category.MATERIAL), Vector2i(2, 1))
	var broken := ResourcesConfig.new()
	broken.nodes = {&"tree": {"resource": &"", "quantity": 0, "strokes_per_unit": 0, "regrow_days": -1.0}, &"bush": 3}
	broken.pile_scale_min = 200
	assert_eq(broken.validate().size(), 6)
	assert_eq(UIText.resource_amount(&"wood", 3), "3 wood")
	assert_eq(UIText.resource_name(&"moonrock"), "something")


# --- nodes ------------------------------------------------------------------------------------------

func test_a_tree_holds_wood_until_it_is_felled_and_grows_back() -> void:
	var tree := _near(PropData.Kind.TREE)
	var now := 5000
	assert_eq(ResourceNodes.key_of(tree), ResourceNodes.TREE)
	assert_eq(nodes.resource_of(tree), &"wood")
	var full := nodes.capacity(tree)
	assert_eq(full, maxi(roundi(16 * tree.scale_percent / 100.0), 1), "a bigger tree holds more")
	assert_eq(tree.stock, -1, "whole, as it was made")
	assert_eq(nodes.left(tree), full)
	assert_eq(nodes.available(tree), full)
	assert_eq(ResourceNodes.look_of(tree), ResourceNodes.Look.FULL)
	assert_eq(nodes.tracked_count(), 0)
	assert_eq(session.props.to_dict()["changed"].size(), 0, "untouched nodes are not saved")
	var chunks: Array = []
	session.props.chunk_changed.connect(func(coord: Vector2i) -> void: chunks.append(coord))
	var fallen: Array = []
	nodes.depleted.connect(func(id: int) -> void: fallen.append(id))
	# Wood taken: it is less, it is kept track of and saved — and the tree stands as before.
	assert_eq(nodes.take(tree.id, 3, now), 3)
	assert_eq(tree.stock, full - 3)
	assert_eq(nodes.available(tree), full - 3)
	assert_eq(nodes.tracked_count(), 1)
	assert_eq(ResourceNodes.look_of(tree), ResourceNodes.Look.FULL, "a tree stands whole while it is being cut")
	assert_eq(chunks.size(), 0, "nothing to draw anew")
	assert_eq(session.props.to_dict()["changed"].size(), 1)
	assert_false(tree.felled)
	assert_true(tree.bears_left() > 0)
	assert_eq(nodes.take(tree.id, 0, now), 0)
	assert_eq(nodes.take(987654321, 1, now), 0, "no such node")
	# The last of it: the tree comes down.
	var whole_body := tree.pick_shape()
	assert_eq(nodes.take(tree.id, 1000, now), full - 3, "no more than there is")
	assert_eq(tree.stock, 0)
	assert_true(tree.felled)
	assert_eq(fallen, [tree.id])
	assert_eq(ResourceNodes.look_of(tree), ResourceNodes.Look.STUMP)
	assert_eq(chunks, [WorldCoords.tile_to_chunk(tree.tile, session.world.chunk_size)], "its chunk is drawn again")
	assert_eq(nodes.available(tree), 0)
	assert_eq(nodes.take(tree.id, 1, now), 0)
	assert_eq(tree.bears_left(), 0, "a stump bears nothing")
	assert_true(tree.pick_shape().x < whole_body.x * 0.5, "and is a small thing to hit")
	assert_eq(nodes.exhausted_count(), 1)
	# It grows back over the days: a stump, then a sapling that grows, then a tree.
	var days := float(config.node(ResourceNodes.TREE)["regrow_days"])
	var per_unit := maxi(roundi(days * 1440.0 / full), 1)
	chunks.clear()
	nodes.settle(now + per_unit - 1)
	assert_eq(tree.stock, 0, "not yet")
	nodes.settle(now + per_unit)
	assert_eq(tree.stock, 1)
	assert_eq(ResourceNodes.look_of(tree), ResourceNodes.Look.STUMP, "still a stump")
	var sapling_at := ceili(config.sapling_from * full)
	nodes.settle(now + per_unit * sapling_at)
	assert_eq(tree.stock, sapling_at)
	assert_eq(ResourceNodes.look_of(tree), ResourceNodes.Look.SAPLING)
	var small := ResourceNodes.look_scale(tree)
	assert_true(small >= config.sapling_scale and small < 0.6, "a small one (%.2f)" % small)
	assert_eq(nodes.available(tree), 0, "nobody cuts a sapling")
	assert_eq(nodes.left(tree), sapling_at)
	assert_true(chunks.size() >= 1, "seen to change")
	nodes.settle(now + per_unit * (full - 1))
	assert_eq(tree.stock, full - 1)
	assert_true(ResourceNodes.look_scale(tree) > small, "it has grown")
	assert_true(tree.felled)
	var back: Array = []
	nodes.regrown.connect(func(id: int) -> void: back.append(id))
	nodes.settle(now + per_unit * full)
	assert_eq(back, [tree.id])
	assert_eq(tree.stock, -1, "whole again: as it was made")
	assert_false(tree.felled)
	assert_eq(ResourceNodes.look_of(tree), ResourceNodes.Look.FULL)
	assert_eq(ResourceNodes.look_scale(tree), 1.0)
	assert_eq(nodes.available(tree), full)
	assert_eq(nodes.tracked_count(), 0)
	assert_true(per_unit * full <= roundi(days * 1440.0) + full, "in about %s days" % days)
	# Regrowth is worked out every so often.
	assert_false(nodes.due(now + per_unit * full + config.regrow_check_minutes - 1))
	assert_true(nodes.due(now + per_unit * full + config.regrow_check_minutes))
	# A whole tree is not felled by being looked at, and other props are no nodes.
	assert_eq(nodes.settle(now + 999999), 0)
	var fire := session.props.get_prop(session.start.campfire_id)
	assert_eq(ResourceNodes.key_of(fire), &"")
	assert_eq(nodes.capacity(fire), 0)
	assert_eq(nodes.take(fire.id, 1, now), 0)
	assert_eq(ResourceNodes.look_of(fire), ResourceNodes.Look.FULL)
	assert_eq(ResourceNodes.look_of(null), ResourceNodes.Look.FULL)


func test_a_bush_thins_out_goes_bare_and_grows_back() -> void:
	var bush := _near(PropData.Kind.BUSH)
	var now := 2000
	assert_eq(nodes.resource_of(bush), &"berries")
	var full := nodes.capacity(bush)
	assert_true(full >= 4, "berries on it (%d)" % full)
	var chunks: Array = []
	session.props.chunk_changed.connect(func(coord: Vector2i) -> void: chunks.append(coord))
	assert_eq(nodes.take(bush.id, 1, now), 1)
	assert_eq(ResourceNodes.look_of(bush), ResourceNodes.Look.FULL)
	assert_eq(chunks.size(), 0)
	# Less than half left: it looks picked over.
	var to_sparse := full - 1 - (ceili(full * config.sparse_below) - 1)
	nodes.take(bush.id, to_sparse, now)
	assert_true(ResourceNodes.fraction_of(bush) < config.sparse_below)
	assert_eq(ResourceNodes.look_of(bush), ResourceNodes.Look.SPARSE)
	assert_eq(chunks.size(), 1)
	assert_true(nodes.available(bush) > 0, "still something to pick")
	# The last berry: bare, and a little smaller.
	nodes.take(bush.id, 100, now)
	assert_eq(bush.stock, 0)
	assert_false(bush.felled, "only trees fall")
	assert_eq(ResourceNodes.look_of(bush), ResourceNodes.Look.BARE)
	assert_eq(ResourceNodes.look_scale(bush), config.bare_scale)
	assert_eq(chunks.size(), 2)
	# Berries come back in days, and can be picked as they come.
	var days := float(config.node(ResourceNodes.BUSH)["regrow_days"])
	var per_unit := maxi(roundi(days * 1440.0 / full), 1)
	nodes.settle(now + per_unit * 2)
	assert_eq(bush.stock, 2)
	assert_eq(nodes.available(bush), 2, "a bush is picked while it grows")
	assert_eq(ResourceNodes.look_of(bush), ResourceNodes.Look.SPARSE)
	assert_eq(nodes.take(bush.id, 1, now + per_unit * 2 + 10), 1)
	assert_eq(bush.stock, 1)
	# (Taking does not set the growing back: the next berry is due when it was.)
	nodes.settle(now + per_unit * 3)
	assert_eq(bush.stock, 2)
	nodes.settle(now + per_unit * (full + 2))
	assert_eq(bush.stock, -1, "whole again")
	assert_eq(ResourceNodes.look_of(bush), ResourceNodes.Look.FULL)
	assert_true(days <= 5.0, "quickly: berries are the band's food")
	# Taking from a bush left alone for a long time first lets it grow.
	nodes.take(bush.id, full, now + 100000)
	assert_eq(nodes.take(bush.id, 1, now + 100000 + per_unit * 3), 1)
	assert_eq(bush.stock, 2)


func test_nodes_look_what_they_hold() -> void:
	var library := PropMeshLibrary.new()
	var tree := _near(PropData.Kind.TREE)
	var whole := library.template_for(tree.kind, tree.variant)
	var stump := library.template_for(tree.kind, tree.variant, ResourceNodes.Look.STUMP)
	assert_ne(stump, whole)
	assert_true(stump.triangle_count() < whole.triangle_count())
	var top := 0.0
	for v in stump.vertices:
		top = maxf(top, v.y)
	assert_true(top < 0.25, "a stump is low (%.2f)" % top)
	assert_eq(library.template_for(tree.kind, tree.variant, ResourceNodes.Look.SAPLING), whole, "a sapling is the tree, small")
	assert_eq(library.template_for(tree.kind, tree.variant, ResourceNodes.Look.FULL), whole)
	var bush := _near(PropData.Kind.BUSH)
	var berries := func(template: PropMeshLibrary.Template) -> int:
		var count := 0
		for c in template.colors:
			if absf(c.r - PropMeshLibrary.BERRY.r) < 0.01 and absf(c.g - PropMeshLibrary.BERRY.g) < 0.01:
				count += 1
		return count
	var full_bush := library.template_for(bush.kind, bush.variant)
	var sparse := library.template_for(bush.kind, bush.variant, ResourceNodes.Look.SPARSE)
	var bare := library.template_for(bush.kind, bush.variant, ResourceNodes.Look.BARE)
	assert_true(berries.call(full_bush) > berries.call(sparse) and berries.call(sparse) > 0, "fewer berries")
	assert_eq(berries.call(bare), 0, "none")
	assert_eq(library.template_for(PropData.Kind.HUT, 0, ResourceNodes.Look.STUMP), library.template_for(PropData.Kind.HUT, 0), "a hut is a hut")
	# In the chunk's mesh: a felled tree's chunk has fewer triangles, and the stump is low.
	var coord := WorldCoords.tile_to_chunk(tree.tile, session.world.chunk_size)
	var before := PropMesher.build_buffers(session.world, session.props, coord, library, false)
	nodes.take(tree.id, 1000, 100)
	var after := PropMesher.build_buffers(session.world, session.props, coord, library, false)
	assert_eq(before.triangle_count() - after.triangle_count(), whole.triangle_count() - stump.triangle_count())
	# As a sapling it is the whole tree again, smaller.
	var full := nodes.capacity(tree)
	tree.stock = ceili(full * 0.5)
	assert_eq(ResourceNodes.look_of(tree), ResourceNodes.Look.SAPLING)
	var young := PropMesher.build_buffers(session.world, session.props, coord, library, false)
	assert_eq(young.triangle_count(), before.triangle_count())
	var height := func(buffers: PropMesher.Buffers) -> float:
		var origin := WorldCoords.chunk_origin(coord, session.world.chunk_size)
		var at := tree.position2d() - Vector2(origin)
		var ground := session.world.get_height(tree.tile) * session.world.height_step
		var highest := 0.0
		for v in buffers.vertices:
			if Vector2(v.x, v.z).distance_to(at) < 0.7:
				highest = maxf(highest, v.y - ground)
		return highest
	assert_true(height.call(young) < height.call(before) * 0.85, "smaller (%.2f of %.2f)" % [height.call(young), height.call(before)])
	assert_true(height.call(young) > height.call(after) * 2.0, "but more than a stump")
	# Names for the player.
	assert_eq(UIText.node_name(PropData.Kind.TREE, 0, ResourceNodes.Look.STUMP), "Tree stump")
	assert_eq(UIText.node_name(PropData.Kind.TREE, 0, ResourceNodes.Look.SAPLING), "Young tree")
	assert_eq(UIText.node_name(PropData.Kind.BUSH, 0, ResourceNodes.Look.BARE), "Bare bush")
	assert_eq(UIText.node_name(PropData.Kind.TREE, 0, ResourceNodes.Look.FULL), UIText.prop_name(PropData.Kind.TREE, 0))
	assert_eq(UIText.holds_text(&"wood", 12, 16), "12 of 16 wood")
	assert_eq(UIText.holds_text(&"berries", 0, 8), "No berries left")


# --- piles ------------------------------------------------------------------------------------------

func test_what_is_gathered_lies_in_piles() -> void:
	var at := session.storage_place(&"wood")
	assert_ne(at, Vector2.INF)
	assert_eq(at, Places.middle_of(session.start.settlement_tile + Vector2i(2, 1)), "materials beside the fire")
	assert_eq(session.storage_place(&"berries"), Places.middle_of(session.start.settlement_tile + Vector2i(-2, 1)), "food on the other side")
	assert_true(session.pathfinder.can_stand(ctx.places.storage_tile(&"wood")))
	_empty_stores()
	assert_eq(piles.piles().size(), 0)
	assert_eq(session.stored(&"wood"), 0)
	var stack := session.resources.get_def(&"wood").stack
	assert_eq(piles.room(&"wood", at), config.piles_per_resource * stack)
	var events: Array = []
	piles.stored.connect(func(resource: StringName, amount: int, pile_id: int) -> void: events.append([resource, amount, pile_id]))
	var before := session.loose.size()
	# The first load makes a pile.
	var onto := piles.add(&"wood", 2, at)
	assert_eq(onto.size(), 1)
	assert_eq(session.loose.size(), before + 1)
	var pile := session.loose.get_object(onto[0])
	assert_true(pile.is_pile())
	assert_eq(pile.kind, LooseObject.Kind.PILE)
	assert_eq(pile.resource, &"wood")
	assert_eq(pile.amount, 2)
	assert_eq(pile.variant, LooseObject.pile_variant(&"wood"))
	assert_true(pile.position.distance_to(at) < 0.6, "on the storage tile")
	assert_false(pile.is_generated())
	assert_eq(events, [[&"wood", 2, pile.id]])
	assert_eq(session.stored(&"wood"), 2)
	assert_eq(piles.total(&"wood"), 2)
	assert_eq(piles.room(&"wood", at), config.piles_per_resource * stack - 2)
	var small := pile.scale_percent
	assert_eq(small, PileStore.scale_for(2, stack))
	# More goes onto it, and it grows.
	var moved: Array = []
	session.loose.object_moved.connect(func(id: int) -> void: moved.append(id))
	assert_eq(piles.add(&"wood", 6, at), [pile.id] as Array[int])
	assert_eq(pile.amount, 8)
	assert_true(pile.scale_percent > small, "a bigger heap")
	assert_eq(moved, [pile.id], "whoever draws it is told")
	assert_eq(session.loose.size(), before + 1)
	assert_eq(PileStore.scale_for(0, stack), config.pile_scale_min)
	assert_eq(PileStore.scale_for(stack, stack), config.pile_scale_max)
	assert_eq(PileStore.scale_for(stack * 5, stack), config.pile_scale_max)
	# A full pile: the rest begins the next one, beside it.
	onto = piles.add(&"wood", stack, at)
	assert_eq(onto.size(), 2)
	assert_eq(pile.amount, stack)
	var second := session.loose.get_object(onto[1])
	assert_eq(second.amount, 8)
	assert_true(second.position.distance_to(pile.position) >= PileStore.SLOT_CLEARANCE, "not on top of the other")
	assert_eq(session.stored(&"wood"), stack + 8)
	# Other things lie in their own piles, in their own place.
	var food := session.storage_place(&"berries")
	piles.add(&"berries", 5, food)
	piles.add(&"stone", 3, at)
	assert_eq(piles.piles(&"berries").size(), 1)
	assert_eq(piles.piles(&"berries")[0].variant, LooseObject.pile_variant(&"berries"))
	assert_eq(piles.totals(), {&"wood": stack + 8, &"berries": 5, &"stone": 3})
	assert_eq(piles.totals(at, config.storage_radius), {&"wood": stack + 8, &"stone": 3})
	assert_eq(session.stored(&"berries"), 5)
	assert_eq(piles.piles(&"", at, config.storage_radius).size(), 3)
	for a in piles.piles():
		for b in piles.piles():
			if a.id != b.id:
				assert_true(a.position.distance_to(b.position) >= PileStore.SLOT_CLEARANCE * 0.99, "each its own place")
	# Nothing is lost when the place is full: one more pile is made — which
	# makes no room for more.
	piles.add(&"wood", stack * 2, at)
	assert_eq(piles.piles(&"wood").size(), 4, "three full ones and what was over")
	assert_eq(piles.room(&"wood", at), 0, "full")
	piles.add(&"wood", 3, at)
	assert_eq(session.stored(&"wood"), stack * 3 + 8 + 3)
	assert_eq(piles.piles(&"wood").size(), 4)
	assert_eq(piles.room(&"wood", at), 0)
	# Taking: the smallest heaps are used up first; an empty pile is gone.
	var gone: Array = []
	session.loose.object_removed.connect(func(id: int) -> void: gone.append(id))
	assert_eq(piles.take(&"wood", 5, at, config.storage_radius), 5)
	assert_eq(gone.size(), 0)
	assert_eq(piles.piles(&"wood")[-1].amount, 6, "from the small one")
	assert_eq(piles.take(&"wood", 8, at, config.storage_radius), 8)
	assert_eq(gone.size(), 1, "the small pile is gone")
	assert_eq(piles.piles(&"wood").size(), 3)
	assert_eq(session.stored(&"wood"), stack * 3 - 2)
	assert_eq(piles.room(&"wood", at), 2)
	assert_eq(piles.take(&"wood", 100000, at, config.storage_radius), stack * 3 - 2, "no more than there is")
	assert_eq(piles.piles(&"wood").size(), 0)
	assert_eq(piles.take(&"wood", 1), 0)
	assert_eq(piles.take_from(987654, 1), 0)
	# Nothing of nothing.
	assert_eq(piles.add(&"", 3, at).size(), 0)
	assert_eq(piles.add(&"wood", 0, at).size(), 0)
	assert_eq(piles.add(&"wood", 2, Vector2(NAN, 0.0)).size(), 0)
	# Piles do not stand in anyone's way.
	piles.add(&"wood", stack, at)
	assert_true(session.pathfinder.can_stand(ctx.places.storage_tile(&"wood")))
	# Every resource has a shape to lie in.
	var library := PropMeshLibrary.new()
	for resource in LooseObject.PILE_RESOURCES:
		var template := library.loose_template(LooseObject.Kind.PILE, LooseObject.pile_variant(resource))
		assert_not_null(template, String(resource))
		assert_true(template.triangle_count() >= 10)
	assert_ne(library.loose_template(LooseObject.Kind.PILE, LooseObject.pile_variant(&"wood")),
		library.loose_template(LooseObject.Kind.PILE, LooseObject.pile_variant(&"stone")))
	assert_eq(LooseObject.pile_variant(&"moonrock"), 0)


func test_the_player_can_move_a_pile() -> void:
	_empty_stores()
	var at := session.storage_place(&"berries")
	var pile := session.loose.get_object(piles.add(&"berries", 10, at)[0])
	assert_eq(session.stored(&"berries"), 10)
	# What it is.
	var report := session.interactions.inspect(_target_of(pile))
	assert_true(report.is_loose())
	assert_eq(report.loose_kind, LooseObject.Kind.PILE)
	assert_eq(report.resource, &"berries")
	assert_eq(report.resource_left, 10)
	assert_eq(UIText.loose_name(LooseObject.Kind.PILE), "Pile")
	# A touch nudges it like anything that lies about.
	var response := session.interactions.tap(_target_of(pile))
	assert_not_null(response)
	assert_eq(response.loose_kind, LooseObject.Kind.PILE)
	assert_eq(InteractionManager.subject_of(response), &"pile")
	# Carried off: an intervention, and no longer the settlement's.
	var before := session.history.stats()["resources_manipulated"] as int
	assert_true(session.interactions.grab(pile.id))
	session.interactions.carry(pile.id, pile.position + Vector2(6.0, 4.0), 0.5)
	var iv := session.interactions.release(pile.id)
	assert_true(iv.applied)
	assert_eq(iv.type, Intervention.MOVE_OBJECT)
	assert_eq(iv.subject, &"pile")
	for i in 60:
		session.loose_system.step(0.05)
	assert_true(pile.position.distance_to(at) > 5.0)
	assert_eq(pile.amount, 10, "nothing spilled")
	assert_eq(session.stored(&"berries"), 0, "it is not in the stores any more")
	assert_eq(piles.total(&"berries"), 10, "but it is somewhere")
	assert_eq(session.history.count(Intervention.MOVE_OBJECT, &"pile"), 1)
	assert_eq(session.history.stats()["resources_manipulated"], before + 1)
	assert_eq(session.history.entries()[-1]["subject"], "pile")
	assert_eq(String(TranslationServer.translate("HISTTHING_PILE")), "a pile")
	assert_eq(pile.moved_count, 1)
	# The stores have room again, and the next load begins a new pile there.
	assert_eq(piles.room(&"berries", at), config.piles_per_resource * session.resources.get_def(&"berries").stack)
	piles.add(&"berries", 2, at)
	assert_eq(piles.piles(&"berries").size(), 2)
	assert_eq(session.stored(&"berries"), 2)
	# Saved and loaded with everything else that lies about.
	var data: Dictionary = bytes_to_var(var_to_bytes(session.to_dict()))
	var loaded: WorldSession = SessionScript.new()
	add_child(loaded)
	assert_true(loaded.load_from(data))
	loaded.set_process(false)
	var again := loaded.loose.get_object(pile.id)
	assert_not_null(again)
	assert_eq([again.kind, again.resource, again.amount, again.scale_percent, again.variant],
		[LooseObject.Kind.PILE, &"berries", 10, pile.scale_percent, pile.variant])
	assert_true(again.position.distance_to(pile.position) < 0.001)
	assert_eq(loaded.stored(&"berries"), 2)
	assert_eq(loaded.piles.total(&"berries"), 12)
	loaded.queue_free()
	# A pile of nothing is no pile.
	var record := pile.to_dict()
	record["amount"] = 0
	assert_null(LooseObject.from_dict(record))
	record["amount"] = 4
	record["resource"] = ""
	assert_null(LooseObject.from_dict(record))


# --- gathering ---------------------------------------------------------------------------------------

func test_gathering() -> void:
	# A woodcutter's morning: wood leaves the tree and arrives in the stores.
	_set_hour(8.5)
	var cutter := _calm(_adult(&"woodcutter"))
	var forager := _calm(_adult(&"forager"))
	_only([cutter, forager])
	_gathering_only()
	behavior.set_plan(forager, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(600.0)])
	var steps := Planner.plan(&"work", cutter, ctx)
	assert_eq(steps.size(), 4, "to the tree, work, to the stores, put it down")
	assert_eq([steps[0]["type"], steps[1]["type"], steps[2]["type"], steps[3]["type"]], ["walk_to", "work", "walk_to", "store"])
	assert_true(bool(steps[1]["gather"]))
	assert_eq(steps[2]["target"], ctx.places.storage_tile(&"wood"))
	var tree := session.props.get_prop(int(steps[1]["target"]))
	assert_eq(tree.kind, PropData.Kind.TREE)
	var full := nodes.capacity(tree)
	assert_eq(ctx.gatherable(tree.id), &"wood")
	cutter.skills[String(cutter.occupation_id)] = 0.0 # (a beginner: the skilled are quicker, M12.4)
	behavior.set_plan(cutter, &"work", &"purpose", steps, 2.0)
	# At the tree: every dozen strokes a piece of wood, taken up.
	var waited := 0.0
	while cutter.carrying_amount == 0 and waited < 120.0:
		_run(1.0)
		waited += 1.0
	assert_eq(cutter.carrying, &"wood")
	assert_eq(cutter.carrying_amount, 1)
	assert_eq(nodes.left(tree), full - 1, "the tree has less")
	assert_eq(BehaviorSystem.current_step(cutter)["type"], "work")
	var strokes := int(BehaviorSystem.current_step(cutter)["strokes"])
	assert_eq(strokes, nodes.strokes_per_unit(tree), "after %d strokes" % strokes)
	assert_eq(cutter.pose, PersonData.Pose.WORK)
	# Arms full: off to the stores.
	waited = 0.0
	while BehaviorSystem.current_step(cutter).get("type") == "work" and waited < 120.0:
		_run(1.0)
		waited += 1.0
	assert_eq(cutter.carrying_amount, ctx.carry_capacity(&"wood"), "as much as one carries")
	assert_eq(nodes.left(tree), full - 2)
	assert_eq(BehaviorSystem.current_step(cutter)["type"], "walk_to")
	assert_eq(BehaviorSystem.activity_of(cutter), &"work", "carrying it home is part of the work")
	assert_eq(session.stored(&"wood"), 0)
	assert_eq(PersonCard.activity_line(cutter), "Working — restless · carrying 2 wood")
	# Put down: a pile at the storage place, empty arms.
	waited = 0.0
	while cutter.carrying_amount > 0 and waited < 60.0:
		_run(0.5)
		waited += 0.5
	assert_eq(cutter.carrying, &"")
	assert_eq(session.stored(&"wood"), 2, "the stockpile has more")
	assert_eq(piles.piles(&"wood").size(), 1)
	assert_true(piles.piles(&"wood")[0].position.distance_to(session.storage_place(&"wood")) < 0.6)
	assert_true(cutter.world2d().distance_to(session.storage_place(&"wood")) < 1.2, "they brought it there themselves")
	assert_false(PersonCard.activity_line(cutter).contains("carrying"))
	assert_eq(_missing_from_nodes(&"wood"), 2)
	# A forager and the berries, the same way.
	behavior.set_plan(cutter, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(1000000.0)])
	_calm(forager)
	var picking := Planner.plan(&"work", forager, ctx)
	assert_eq(picking.size(), 4)
	var bush := session.props.get_prop(int(picking[1]["target"]))
	assert_eq(bush.kind, PropData.Kind.BUSH)
	var berries := nodes.capacity(bush)
	behavior.set_plan(forager, &"work", &"purpose", picking, 2.0)
	waited = 0.0
	while session.stored(&"berries") == 0 and waited < 240.0:
		_run(1.0)
		waited += 1.0
	var picked := session.stored(&"berries")
	assert_true(picked >= 1 and picked <= ctx.carry_capacity(&"berries"), "an armful (%d)" % picked)
	assert_eq(picked, mini(berries, ctx.carry_capacity(&"berries")), "all they could carry, or all there was")
	assert_eq(_missing_from_nodes(&"berries"), picked, "nothing made, nothing lost")
	assert_eq(session.storage_place(&"berries").distance_to(piles.piles(&"berries")[0].position) < 0.6, true)
	# An elder's work at the fire yields nothing to carry.
	var elder := _adult(&"elder")
	var tending := Planner.plan(&"work", elder, ctx)
	assert_eq(tending.size(), 2)
	assert_false(tending[1].has("gather"))
	assert_eq(ctx.gatherable(session.start.campfire_id), &"")


func test_work_stops_yielding_when_the_stores_are_full_or_the_node_is_empty() -> void:
	_set_hour(9.0)
	var cutter := _calm(_adult(&"woodcutter"))
	_only([cutter])
	_gathering_only()
	var at := session.storage_place(&"wood")
	var stack := session.resources.get_def(&"wood").stack
	# Full stores: work is only work (as it was before there were resources).
	piles.add(&"wood", stack * config.piles_per_resource, at)
	assert_eq(piles.room(&"wood", at), 0)
	var steps := Planner.plan(&"work", cutter, ctx)
	assert_eq(steps.size(), 2)
	assert_false(steps[1].has("gather"))
	behavior.set_plan(cutter, &"work", &"purpose", steps, 2.0)
	_run(90.0)
	assert_eq(_missing_from_nodes(&"wood"), 0, "no tree is cut for wood nobody has room for")
	assert_eq(cutter.carrying_amount, 0)
	# Room, but enough in store: the board has nothing posted, and nobody cuts.
	session.loose.remove(piles.piles(&"wood")[0].id)
	session.settlement.jobs.refresh(session.settlement, session.clock.tick)
	assert_eq(piles.room(&"wood", at), stack)
	assert_false(session.settlement.jobs.wants(&"wood"), "two full piles are plenty")
	assert_eq(Planner.plan(&"work", cutter, ctx).size(), 2)
	# The player carries the piles off: wood is wanted again, and gathering goes on.
	for pile in piles.piles(&"wood"):
		session.loose.move(pile.id, pile.position + Vector2(8.0, 0.0))
	session.settlement.jobs.refresh(session.settlement, session.clock.tick)
	assert_true(session.settlement.jobs.wants(&"wood"))
	assert_eq(session.stored(&"wood"), 0)
	assert_eq(Planner.plan(&"work", cutter, ctx).size(), 4)
	# A tree that has been begun is cut down before the next one is.
	var begun := session.props.get_prop(int(Planner.plan(&"work", cutter, ctx)[1]["target"]))
	nodes.take(begun.id, 1, session.clock.tick)
	for i in 30:
		assert_eq(int(Planner.plan(&"work", cutter, ctx)[1]["target"]), begun.id, "the one already begun")
	nodes.take(begun.id, 1000, session.clock.tick)
	assert_true(begun.felled)
	# People go where there is something to take: not to a felled tree.
	var first := session.props.get_prop(int(Planner.plan(&"work", cutter, ctx)[1]["target"]))
	assert_ne(first.id, begun.id)
	var seen := {}
	for i in 60:
		seen[int(Planner.plan(&"work", cutter, ctx)[1]["target"])] = true
	assert_true(seen.size() >= 2 and seen.size() <= Places.WORK_CHOICES, "one of the nearest few (%d)" % seen.size())
	for id: int in seen:
		nodes.take(id, 1000, session.clock.tick)
	for i in 60:
		var target := int(Planner.plan(&"work", cutter, ctx)[1]["target"])
		assert_false(seen.has(target), "not to a stump")
		assert_true(nodes.available(session.props.get_prop(target)) > 0)
	assert_true(first.felled)
	# A tree felled under the axe ends the work there: home with what there is.
	var steps_now := Planner.plan(&"work", cutter, ctx)
	var tree := session.props.get_prop(int(steps_now[1]["target"]))
	behavior.set_plan(cutter, &"work", &"purpose", steps_now, 2.0)
	var waited := 0.0
	while cutter.carrying_amount == 0 and waited < 120.0:
		_run(1.0)
		waited += 1.0
	assert_eq(cutter.carrying_amount, 1)
	nodes.take(tree.id, 1000, session.clock.tick) # (someone else takes the rest)
	_run(3.0)
	assert_ne(BehaviorSystem.current_step(cutter).get("type"), "work", "nothing left to cut")
	waited = 0.0
	while cutter.carrying_amount > 0 and waited < 60.0:
		_run(0.5)
		waited += 0.5
	assert_eq(cutter.carrying_amount, 0)
	assert_eq(session.stored(&"wood"), 1, "the one piece is in the stores")
	# Nothing to take anywhere near: they work on all the same (nobody stands idle for it).
	for prop in session.props.all_props():
		if prop.kind == PropData.Kind.TREE:
			nodes.take(prop.id, 1000, session.clock.tick)
	var idle := Planner.plan(&"work", cutter, ctx)
	assert_eq(idle.size(), 2, "work without a yield")
	assert_false(idle[1].has("gather"))


func test_someone_called_away_keeps_what_they_carry_and_brings_it_home_later() -> void:
	_set_hour(9.0)
	var cutter := _calm(_adult(&"woodcutter"))
	_only([cutter])
	_gathering_only()
	behavior.set_plan(cutter, &"work", &"purpose", Planner.plan(&"work", cutter, ctx), 2.0)
	var waited := 0.0
	while cutter.carrying_amount == 0 and waited < 120.0:
		_run(1.0)
		waited += 1.0
	assert_eq(cutter.carrying_amount, 1)
	# Thirst: off to the water, wood in arms.
	behavior.set_plan(cutter, &"drink", &"thirst", Planner.plan(&"drink", cutter, ctx), 2.0)
	_run(5.0)
	assert_eq(cutter.carrying, &"wood")
	assert_eq(cutter.carrying_amount, 1)
	# It is saved with them.
	var again := PersonData.from_dict(bytes_to_var(var_to_bytes(cutter.to_dict())))
	assert_eq([again.carrying, again.carrying_amount], [&"wood", 1])
	var record := cutter.to_dict()
	record["carrying_amount"] = 0
	assert_eq(PersonData.from_dict(record).carrying, &"", "nothing of something is nothing")
	record["carrying_amount"] = 3
	record["carrying"] = ""
	assert_eq(PersonData.from_dict(record).carrying_amount, 0)
	# Back at work: first to the stores with it.
	var steps := Planner.plan(&"work", cutter, ctx)
	assert_eq(steps.size(), 2)
	assert_eq([steps[0]["type"], steps[1]["type"]], ["walk_to", "store"])
	assert_eq(steps[0]["target"], ctx.places.storage_tile(&"wood"))
	session.day_log.forget(cutter.id)
	behavior.set_plan(cutter, &"work", &"purpose", steps, 2.0)
	assert_eq(session.day_log.of(cutter.id)[-1].slice(1), ["work", "haul", 0])
	assert_eq(DayLogText.text(session.day_log.of(cutter.id)[-1]), "carries a load to the stores")
	waited = 0.0
	while cutter.carrying_amount > 0 and waited < 120.0:
		_run(0.5)
		waited += 0.5
	assert_eq(session.stored(&"wood"), 1)
	assert_eq(_missing_from_nodes(&"wood"), 1)
	# Putting down takes a moment, and nothing happens with empty arms.
	assert_eq(ctx.put_down(cutter), 0)
	var handler := StoreStep.new()
	var step := StoreStep.make()
	assert_eq(handler.update(ctx, cutter, step, 1.0), ActionStep.Status.DONE, "empty-handed: nothing to do")
	cutter.carrying = &"wood"
	cutter.carrying_amount = 2
	assert_eq(handler.update(ctx, cutter, step, config.store_minutes * 0.5), ActionStep.Status.RUNNING)
	assert_eq(handler.update(ctx, cutter, step, config.store_minutes), ActionStep.Status.DONE)
	assert_eq(session.stored(&"wood"), 3)


func test_an_uprooted_stump_leaves_no_log() -> void:
	var tree := _near(PropData.Kind.TREE)
	nodes.take(tree.id, 1000, 100)
	assert_true(tree.felled)
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = tree.id
	target.tile = tree.tile
	var report := session.interactions.inspect(target)
	assert_eq(report.resource, &"wood")
	assert_eq(report.resource_left, 0)
	assert_eq(report.resource_capacity, nodes.capacity(tree))
	assert_eq(report.look, ResourceNodes.Look.STUMP)
	assert_eq(report.bears_left, 0)
	var loose_before := session.loose.size()
	var response := session.interactions.uproot(target)
	assert_not_null(response)
	assert_null(session.props.get_prop(tree.id), "the stump is gone")
	assert_eq(session.loose.size(), loose_before, "and there was no trunk to leave lying")
	assert_eq(nodes.settle(999999), 0, "what is gone does not grow back")
	assert_eq(nodes.tracked_count(), 0)
	# A standing tree, half cut, still leaves its trunk.
	var other := _near(PropData.Kind.TREE)
	nodes.take(other.id, 3, 100)
	target.entity_id = other.id
	target.tile = other.tile
	session.interactions.uproot(target)
	assert_eq(session.loose.size(), loose_before + 1)


func test_fallen_fruit_is_picked_up() -> void:
	# (Owner: the fruit a shaken tree lets go of just lay about.)
	_set_hour(8.5)
	var forager := _calm(_adult(&"forager"))
	_only([forager])
	_gathering_only()
	var home: Variant = ctx.places.home_tile(forager)
	var spot: Vector2i = (home as Vector2i) + Vector2i(3, 1)
	var fallen: Array[int] = []
	for n in 3:
		var fruit := LooseObject.new()
		fruit.id = session.ids.next_id()
		fruit.kind = LooseObject.Kind.FRUIT
		fruit.position = Places.middle_of(spot) + Vector2(0.3 * n - 0.3, 0.2)
		assert_true(session.loose.add(fruit))
		fallen.append(fruit.id)
	# One the player put somewhere is left there.
	var kept := LooseObject.new()
	kept.id = session.ids.next_id()
	kept.kind = LooseObject.Kind.FRUIT
	kept.position = Places.middle_of(spot) + Vector2(0.0, -0.4)
	kept.placed_by_player = true
	assert_true(session.loose.add(kept))
	# A forager picks it up before picking a bush, and takes it to the stores.
	var steps := Planner.plan(&"work", forager, ctx)
	assert_true(bool(steps[1].get("fruit", false)), "the fallen fruit first")
	assert_eq([steps[0]["type"], steps[2]["type"], steps[3]["type"]], ["walk_to", "walk_to", "store"])
	behavior.set_plan(forager, &"work", &"purpose", steps, 2.0)
	var waited := 0.0
	while int(forager.current_action.get("index", 0)) < 2 and waited < 200.0:
		_run(1.0)
		waited += 1.0
	assert_eq(forager.carrying, &"berries")
	assert_eq(forager.carrying_amount, mini(3, ctx.carry_capacity(&"berries")), "a piece a unit, as much as one carries")
	var left := 0
	for id in fallen:
		left += 1 if session.loose.get_object(id) != null else 0
	assert_eq(left, 3 - forager.carrying_amount, "picked up: gone from the ground")
	assert_not_null(session.loose.get_object(kept.id), "not the player's")


func test_an_uprooted_tree_is_cut_up_for_wood() -> void:
	# (Owner: the logs of uprooted trees just lay about.)
	_set_hour(8.5)
	var cutter := _calm(_adult(&"woodcutter"))
	_only([cutter])
	_gathering_only()
	var tree := _near(PropData.Kind.TREE)
	nodes.take(tree.id, 3, 100)
	var wood := nodes.left(tree)
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = tree.id
	target.tile = tree.tile
	var response := session.interactions.uproot(target)
	var log := session.loose.get_object(response.dropped[0])
	assert_eq(log.kind, LooseObject.Kind.LOG)
	assert_eq(WorkStep.log_wood(log), wood, "the wood that was in the tree lies in its trunk")
	for n in 200: # (it falls, and comes to rest)
		session.loose_system.step(0.05)
	assert_eq(log.state, LooseObject.State.RESTING)
	var looked := Picker.Result.new()
	looked.kind = Picker.Kind.ENTITY
	looked.entity_id = log.id
	looked.tile = log.tile()
	var report := session.interactions.inspect(looked)
	assert_eq([report.resource, report.resource_left], [&"wood", wood], "the card says what is in it")
	# A woodcutter cuts it up before felling a standing tree, and carries the wood home.
	var steps := Planner.plan(&"work", cutter, ctx)
	assert_eq(int(steps[1].get("log", 0)), log.id, "the fallen trunk first")
	assert_eq([steps[0]["type"], steps[2]["type"], steps[3]["type"]], ["walk_to", "walk_to", "store"])
	behavior.set_plan(cutter, &"work", &"purpose", steps, 2.0)
	var waited := 0.0
	# (Until the cutting is done: on to the stores, the third step.)
	while int(cutter.current_action.get("index", 0)) < 2 and waited < 400.0:
		_run(1.0)
		waited += 1.0
	assert_eq(BehaviorSystem.activity_of(cutter), &"work")
	assert_eq(cutter.carrying, &"wood")
	assert_eq(cutter.carrying_amount, ctx.carry_capacity(&"wood"))
	assert_true(WorkStep.log_wood(session.loose.get_object(log.id)) <= wood - cutter.carrying_amount, "the log has less (by what they carry, and any load taken home already)")
	# The last of it cut: the log is gone (and no longer in the way).
	cutter.carrying_amount = 0
	log.amount = 1
	assert_true(WorkStep.cut_log(ctx, cutter, {"effort": 0}, log, 100))
	assert_null(session.loose.get_object(log.id), "cut up and carried off")
	# A log the player has put somewhere is left where it is.
	var placed := LooseObject.new()
	placed.id = session.ids.next_id()
	placed.kind = LooseObject.Kind.LOG
	placed.position = Places.middle_of(cutter.position + Vector2i(2, 0))
	placed.placed_by_player = true
	assert_true(session.loose.add(placed))
	cutter.carrying_amount = 0
	assert_false(int(Planner.plan(&"work", cutter, ctx)[1].get("log", 0)) == placed.id, "not the player's")


# --- over days ---------------------------------------------------------------------------------------

func test_a_week_of_gathering() -> void:
	session.clock.tick = 0
	var people := session.people.all_people()
	var wood_stack := session.resources.get_def(&"wood").stack
	var berry_stack := session.resources.get_def(&"berries").stack
	var most_wood := config.piles_per_resource * wood_stack
	var most_berries := config.piles_per_resource * berry_stack
	var after_first_day := {}
	var felled_at_most := 0
	for day in 7:
		_run(1440.0, 1.0)
		# Nothing made, nothing lost: what is missing from the nodes has
		# grown back, is carried, or lies in piles.
		var wood := session.stored(&"wood")
		var berries := session.stored(&"berries")
		# (The settlement wants a few days' worth, not all the stores hold.)
		assert_true(wood <= 18 + ctx.carry_capacity(&"wood") * 4, "day %d: wood about what is wanted (%d)" % [day + 1, wood])
		assert_true(berries <= most_berries, "day %d: berries (%d)" % [day + 1, berries])
		assert_eq(piles.total(&"wood"), wood, "nobody leaves wood lying elsewhere")
		var felled := 0
		for prop in session.props.all_props():
			felled += 1 if prop.felled else 0
		felled_at_most = maxi(felled_at_most, felled)
		if day == 0:
			after_first_day = {"wood": wood, "berries": berries, "felled": felled}
			assert_true(wood >= 6, "wood came in on the first day (%d)" % wood)
			assert_true(berries >= 6, "and berries (%d)" % berries)
		for p in people:
			assert_true(p.carrying_amount <= ctx.carry_capacity(p.carrying) if p.carrying != &"" else p.carrying_amount == 0)
	var wood_end := session.stored(&"wood")
	var berries_end := session.stored(&"berries")
	print("    after a day: %s; after a week: wood %d of %d, berries %d of %d in %d piles; %d trees felled at most, %d nodes regrowing" % [
		after_first_day, wood_end, most_wood, berries_end, most_berries, piles.piles().size(), felled_at_most, nodes.tracked_count()])
	assert_true(wood_end >= 6 and wood_end <= most_wood, "wood in store (%d)" % wood_end)
	assert_true(berries_end >= 6, "and food (%d)" % berries_end)
	assert_true(session.settlement.fire_lit(), "the fire burns")
	assert_true(felled_at_most >= 1, "trees came down for it")
	assert_true(felled_at_most <= 8, "but not the forest (%d)" % felled_at_most)
	assert_true(piles.piles().size() <= config.piles_per_resource * 2 + 4)
	# Nobody is stuck: everyone has done several different things on the last day.
	var last_day := Config.time.day_index(session.clock.tick) - 1
	for p in people:
		var entries := session.day_log.of_day(p.id, last_day, Config.time)
		var kinds := {}
		for entry: Array in entries:
			kinds[entry[DayLog.KIND]] = true
		assert_true(kinds.size() >= 3, "%s lives on (%s)" % [p.given_name, kinds.keys()])
		assert_true(Needs.value(p.needs, Needs.Need.HUNGER) > 0.05 and Needs.value(p.needs, Needs.Need.THIRST) > 0.05, "%s is not starving" % p.given_name)
	# It survives a save.
	var data: Dictionary = bytes_to_var(var_to_bytes(session.to_dict()))
	var loaded: WorldSession = SessionScript.new()
	add_child(loaded)
	assert_true(loaded.load_from(data))
	loaded.set_process(false)
	assert_eq(loaded.stored(&"wood"), wood_end)
	assert_eq(loaded.stored(&"berries"), berries_end)
	assert_eq(loaded.nodes.tracked_count(), nodes.tracked_count(), "what was regrowing is regrowing")
	for prop in session.props.all_props():
		if prop.stock >= 0:
			var again := loaded.props.get_prop(prop.id)
			assert_eq([again.stock, again.stock_tick, again.felled], [prop.stock, prop.stock_tick, prop.felled])
	for p in people:
		var again := loaded.people.get_person(p.id)
		assert_eq([again.carrying, again.carrying_amount], [p.carrying, p.carrying_amount])
	loaded.queue_free()


func test_version_8_save_gains_resources() -> void:
	# Written by M6.4 (84d0833): a morning lived. Nobody had gathered anything.
	assert_true(FileAccess.file_exists(V8_FIXTURE), "fixture present")
	var dir := SaveManager.world_dir(V8_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V8_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 8)
	var loaded := SaveManager.load_world(V8_ID)
	assert_true(loaded.ok, loaded.error)
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	s.loose_system.set_process(false)
	s.water.set_process(false)
	assert_eq(s.people.size(), 8)
	assert_eq(s.piles.piles().size(), 0, "no stores yet")
	assert_eq(s.nodes.tracked_count(), 0, "every node is whole")
	for prop in s.props.all_props():
		assert_eq([prop.stock, prop.felled], [-1, false])
	for p in s.people.all_people():
		assert_eq([p.carrying, p.carrying_amount], [&"", 0])
	assert_true(s.day_log.entry_count() > 0, "and what was there is there")
	assert_eq(s.history.people_touched(), 3)
	# They go on living — and now their work brings something home.
	_run(600.0, 1.0, s)
	assert_true(s.stored(&"wood") + s.stored(&"berries") > 0, "wood %d, berries %d" % [s.stored(&"wood"), s.stored(&"berries")])
	assert_true(s.nodes.tracked_count() > 0)
	# Saved again: the current version, the old file kept.
	assert_true(SaveManager.save_world(s, &"test"))
	assert_true(SaveManager.SAVE_VERSION >= 9)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav.bak1")).header["save_version"], 8)
	var again := SaveManager.load_world(V8_ID)
	assert_true(again.ok, again.error)
	var s2: WorldSession = SessionScript.new()
	add_child(s2)
	assert_true(s2.load_from(again.world))
	s2.set_process(false)
	assert_eq(s2.stored(&"wood"), s.stored(&"wood"))
	assert_eq(s2.stored(&"berries"), s.stored(&"berries"))
	assert_eq(s2.nodes.tracked_count(), s.nodes.tracked_count())
	s.queue_free()
	s2.queue_free()
	# The step itself has nothing to rewrite.
	var data := {"world": {"world_state": {"props": {"changed": []}}}}
	assert_eq(SaveMigrations._v8_to_v9(data), data)
