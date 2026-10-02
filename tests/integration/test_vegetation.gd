extends TestCase
## The soil of all the land and what grows on it (M9.4, bible §10.4): the
## ground gets wet and dries, a flood leaves silt, grass thins and comes
## back, trees seed and die — within bounds —, what would burn, saving.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const V16_FIXTURE := "res://tests/fixtures/saves/v16_world.sav"
const V16_ID := "w1790972824_c9bf48bd"
const DAY := 1440

var session: WorldSession
var weather: WeatherSystem
var river: Hydrology
var soil: SoilSystem
var plants: VegetationSystem
var world: WorldData
var clock: GameClock
var config: VegetationConfig
var days := 6
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
	weather = session.weather
	river = session.hydrology
	soil = session.soil
	plants = session.vegetation
	world = session.world
	clock = session.clock
	config = Config.vegetation
	days = Config.time.days_per_season


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


func _midnight(day: int) -> int:
	return day * DAY - roundi(Config.time.start_hour * 60.0)


## Sets the clock to a day (at noon) and brings the weather there, held at
## a kind. The river stays where it was made (unless a test moves it).
func _go_to(day: int, kind: StringName = &"clear") -> void:
	river.enabled = false
	clock.tick = _midnight(day) + 720
	weather.advance_to(clock.tick)
	weather.hold(kind, clock.tick + 1000 * DAY)


## The very middle of summer (everything grows as it can), the weather held clear.
func _midsummer() -> void:
	river.enabled = false
	clock.tick = roundi(1.5 * days * DAY - Config.time.start_hour * 60.0)
	weather.advance_to(clock.tick)
	weather.hold(&"clear", clock.tick + 1000 * DAY)


## What a past day was like, in the weather's record.
func _day_was(day: int, rain: float, warmest: float) -> void:
	weather._rain[day] = rain
	weather._warmest[day] = warmest


## Lets whole days pass for the land, the chunks having their turns through each.
func _days(count: int) -> void:
	for step in count * 16:
		clock.tick += 90
		weather.advance_to(clock.tick)
		soil.advance_to(clock.tick)
		if step % 8 == 0:
			session.nodes.settle(clock.tick)


## An open tile of grass away from the water with something growing on it
## — and not at its chunk's edge.
func _meadow(least_cover: int = 80) -> Vector2i:
	var size := world.chunk_size
	for chunk in world.loaded_chunks():
		for i in chunk.terrain.size():
			@warning_ignore("integer_division")
			var local := Vector2i(i % size, i / size)
			if local.x < 2 or local.y < 2 or local.x > size - 3 or local.y > size - 3:
				continue
			var tile := WorldCoords.chunk_origin(chunk.coord, size) + local
			if chunk.terrain[i] == ChunkData.Terrain.GRASS and chunk.water[i] <= 0.0 and chunk.vegetation[i] >= least_cover \
					and chunk.moisture[i] >= 120 and chunk.moisture[i] <= 200 and not session.props.has_prop_at(tile):
				return tile
	return Vector2i(-999, -999)


func _chunk_of(tile: Vector2i) -> ChunkData:
	return world.chunk_at_tile(tile)


func _trees() -> Array[PropData]:
	var out: Array[PropData] = []
	for prop in session.props.all_props():
		if prop.kind == PropData.Kind.TREE:
			out.append(prop)
	return out


func test_the_land_as_it_was_made() -> void:
	assert_eq(config.validate().size(), 0, str(config.validate()))
	assert_eq(Config.problems.size(), 0, str(Config.problems))
	var tile := _meadow()
	assert_true(world.is_in_bounds(tile))
	var chunk := _chunk_of(tile)
	var i := world.index_at_tile(tile)
	# What the land holds by itself is what the generator made.
	assert_eq(soil.base_moisture(tile), int(chunk.moisture[i]))
	assert_eq(soil.base_fertility(tile), int(chunk.fertility[i]))
	assert_eq(soil.base_vegetation(tile), int(chunk.vegetation[i]))
	assert_eq(soil.base_moisture(tile), int(session.generator.sample_tile(tile)["moisture"]))
	assert_eq(soil.base_moisture(Vector2i(9999, 0)), 0)
	# As it was made, the soil lets grow exactly what grows there.
	assert_eq(plants.potential(tile), int(chunk.vegetation[i]))
	assert_true(plants.potential(tile, 0.7) < chunk.vegetation[i], "less in winter")
	# The forest: its trees are the measure of its bounds.
	assert_eq(plants.tree_count(), _trees().size())
	assert_eq(plants.forest_base, plants.tree_count())
	assert_true(plants.tree_count() > 100)
	assert_true(plants.forest_coverage() > 0.03 and plants.forest_coverage() < 0.4, "%.3f" % plants.forest_coverage())
	assert_true(plants.grass_cover() > 0.2 and plants.grass_cover() < 0.7, "%.3f" % plants.grass_cover())
	assert_true(soil.debug_text().begins_with("soil: ") and plants.debug_text().begins_with("plants: "))
	# The statistics keep them.
	var sample := session.sample_stats()
	assert_near(sample[&"trees"], plants.tree_count(), 0.001)
	assert_near(sample[&"grass"], plants.grass_cover(), 0.0001)
	assert_true(StatsRecorder.SERIES.has(&"trees") and StatsRecorder.SERIES.has(&"grass"))
	# Every chunk has its turn once a day, one after the other — never the whole box at once.
	_go_to(2)
	soil.advance_to(clock.tick)
	var passes := soil.passes
	var most_at_once := 0
	for step in 16 * 3:
		clock.tick += 90
		var before := soil.passes
		soil.advance_to(clock.tick)
		most_at_once = maxi(most_at_once, soil.passes - before)
	assert_eq(most_at_once, 1)
	assert_true(soil.passes - passes >= world.chunk_coords().size() * 2, "%d passes in three days" % (soil.passes - passes))
	# After a long absence: one pass each, for no more days than the config allows.
	var done: Array = []
	soil.chunk_done.connect(func(coord: Vector2i, count: int, _day: int) -> void: done.append([coord, count]))
	clock.tick += 100 * DAY
	soil.advance_to(clock.tick)
	assert_eq(done.size(), world.chunk_coords().size())
	for entry: Array in done:
		assert_eq(entry[1], config.days_made_up)


func test_soil_gets_wet_and_dries() -> void:
	_go_to(days + 3)
	var day := Config.time.day_index(clock.tick) - 1
	var tile := _meadow()
	var chunk := _chunk_of(tile)
	var i := world.index_at_tile(tile)
	var base := soil.base_moisture(tile)
	var farm := Config.farming
	# An ordinary dry day: it dries, and some comes back from below.
	_day_was(day, 0.0, 20.0)
	soil._soil_days(chunk.coord, 1, day)
	var lost: int = farm.evaporation_per_day
	assert_eq(int(chunk.moisture[i]), base - lost + ceili(lost * farm.seep_share), "an ordinary dry day")
	assert_true(chunk.modified, "the chunk is kept in the save")
	# A hot day dries it more.
	chunk.moisture[i] = base
	_day_was(day, 0.0, 30.0)
	soil._soil_days(chunk.coord, 1, day)
	var hot := int(chunk.moisture[i])
	assert_true(hot < base - lost + ceili(lost * farm.seep_share))
	# A rainy day wets it — and what is more than the land holds drains.
	chunk.moisture[i] = base
	_day_was(day, 6.0, 20.0)
	soil._soil_days(chunk.coord, 1, day)
	var gained: int = farm.rain_moisture - lost
	assert_eq(int(chunk.moisture[i]), mini(base + gained - floori(gained * config.drain_share), 255), "a rainy day")
	assert_true(chunk.moisture[i] > base)
	# Dry day after dry day it settles somewhat below what the land holds (what
	# dries is made up from below) — wherever it began; rainy day after rainy day, above.
	chunk.moisture[i] = 255
	_day_was(day, 0.0, 20.0)
	for n in 40:
		soil._soil_days(chunk.coord, 1, day)
	var dry_spell := int(chunk.moisture[i])
	assert_true(dry_spell < base and dry_spell >= base - roundi(lost / farm.seep_share), "%d against %d" % [dry_spell, base])
	chunk.moisture[i] = 0
	for n in 40:
		soil._soil_days(chunk.coord, 1, day)
	assert_true(absi(int(chunk.moisture[i]) - dry_spell) <= 4, "%d from below, %d from above" % [chunk.moisture[i], dry_spell])
	_day_was(day, 6.0, 20.0)
	for n in 40:
		soil._soil_days(chunk.coord, 1, day)
	assert_true(chunk.moisture[i] > base and chunk.moisture[i] <= base + roundi(gained / config.drain_share) + 2,
		"%d against %d in a wet spell" % [chunk.moisture[i], base])
	_day_was(day, 0.0, 20.0)
	# Beside a low river the land holds less.
	river.level = -0.18
	for n in 30:
		soil._soil_days(chunk.coord, 1, day)
	assert_true(chunk.moisture[i] < dry_spell - 20, "%d (%d beside the river as it was made)" % [chunk.moisture[i], dry_spell])
	assert_true(chunk.moisture[i] > 0)
	river.level = 0.0
	# Many days at once come to much the same as one by one.
	chunk.moisture[i] = 255
	for d in range(day - 5, day + 1):
		_day_was(d, 0.0, 20.0)
	soil._soil_days(chunk.coord, 6, day)
	var at_once := int(chunk.moisture[i])
	chunk.moisture[i] = 255
	for n in 6:
		soil._soil_days(chunk.coord, 1, day)
	assert_true(absi(int(chunk.moisture[i]) - at_once) <= 25, "%d at once, %d one by one" % [at_once, chunk.moisture[i]])
	# Ground under water is soaked; the riverbed is nobody's soil; a field is the farmers'.
	chunk.moisture[i] = 100
	chunk.water[i] = 0.05
	soil._soil_days(chunk.coord, 1, day)
	assert_eq(int(chunk.moisture[i]), 255)
	chunk.water[i] = 0.0
	var bed := river.bed()[0]
	var bed_chunk := _chunk_of(bed)
	bed_chunk.moisture[world.index_at_tile(bed)] = 7
	soil._soil_days(bed_chunk.coord, 1, day)
	assert_eq(int(bed_chunk.moisture[world.index_at_tile(bed)]), 7)
	var plot: Vector2i = session.farming.next_plot()
	var crop := session.farming.sow(plot, clock.tick)
	assert_not_null(crop)
	var plot_chunk := _chunk_of(plot)
	plot_chunk.moisture[world.index_at_tile(plot)] = 3
	plot_chunk.fertility[world.index_at_tile(plot)] = 3
	soil._soil_days(plot_chunk.coord, 1, day)
	assert_eq(int(plot_chunk.moisture[world.index_at_tile(plot)]), 3, "the field's soil is Farming's")
	assert_eq(int(plot_chunk.fertility[world.index_at_tile(plot)]), 3)
	# Poor land left alone recovers — up to what it is by itself.
	var rich := soil.base_fertility(tile)
	chunk.fertility[i] = rich - 10
	soil._soil_days(chunk.coord, 4, day)
	assert_eq(int(chunk.fertility[i]), rich - 10 + roundi(config.fertility_recover_per_day * 4))
	soil._soil_days(chunk.coord, 10, day)
	assert_eq(int(chunk.fertility[i]), rich)


func test_a_flood_leaves_silt() -> void:
	_go_to(days * 2 + 2)
	river.enabled = true
	var home := session.start.settlement_tile
	var floor_tile := home + Vector2i(0, 3)
	for tile: Vector2i in [home + Vector2i(0, 3), home + Vector2i(1, 3), home + Vector2i(-2, 2), home + Vector2i(2, -3)]:
		if world.get_terrain(tile) == ChunkData.Terrain.GRASS and world.get_height(tile) == world.get_height(home):
			floor_tile = tile
	assert_eq(world.get_terrain(floor_tile), ChunkData.Terrain.GRASS)
	var rich := soil.base_fertility(floor_tile)
	var drained: Array = []
	river.drained.connect(func(tiles: Array[Vector2i]) -> void: drained.append(tiles.size()))
	# The river comes over its banks, and goes back.
	river.level = 0.3
	river.apply()
	assert_true(world.get_water(floor_tile) > 0.0)
	assert_eq(soil.fertility(floor_tile), rich, "not while the water stands")
	river.level = 0.0
	river.apply()
	assert_eq(drained.size(), 1)
	assert_true(drained[0] > 500, "%d tiles drained" % drained[0])
	assert_near(world.get_water(floor_tile), 0.0, 0.0001)
	assert_eq(soil.fertility(floor_tile), mini(rich + config.silt_gain, 255), "silt")
	assert_true(soil.silted > 500)
	assert_eq(soil.moisture(floor_tile), 255, "and soaked ground")
	# Sand takes none.
	for tile in river.bed():
		var beside := tile + Vector2i(1, 0)
		if world.get_terrain(beside) == ChunkData.Terrain.SAND:
			assert_eq(soil.fertility(beside), soil.base_fertility(beside))
			break
	# Flood after flood: not without end.
	for n in 8:
		river.level = 0.3
		river.apply()
		river.level = 0.0
		river.apply()
	assert_eq(soil.fertility(floor_tile), mini(rich + config.silt_most, 255))
	# Richer soil lets more grow.
	if rich + config.silt_most <= 255 and soil.base_vegetation(floor_tile) > 20:
		_chunk_of(floor_tile).moisture[world.index_at_tile(floor_tile)] = soil.base_moisture(floor_tile)
		assert_true(plants.potential(floor_tile) > soil.base_vegetation(floor_tile))
	# It fades with the years: one in four days.
	var chunk := _chunk_of(floor_tile)
	var day := Config.time.day_index(clock.tick) - 1
	var before := soil.fertility(floor_tile)
	soil._soil_days(chunk.coord, 8, day - (day % config.silt_fade_days) + 8)
	assert_eq(soil.fertility(floor_tile), maxi(before - 8 / config.silt_fade_days, rich))
	for n in 60:
		soil._soil_days(chunk.coord, 10, day + n * 10)
	assert_eq(soil.fertility(floor_tile), rich, "back to what the land is, not below")


func test_grass_thins_and_comes_back() -> void:
	_midsummer()
	var tile := _meadow()
	var chunk := _chunk_of(tile)
	var i := world.index_at_tile(tile)
	var lush := int(chunk.vegetation[i])
	var redrawn: Array = []
	session.props.chunk_changed.connect(func(coord: Vector2i) -> void: redrawn.append(coord))
	# Soil as it was made: nothing changes, nothing is drawn anew, nothing need be saved.
	var as_made := chunk.vegetation.duplicate()
	plants._grass_days(chunk.coord, 1, clock.tick)
	assert_eq(chunk.vegetation, as_made)
	assert_eq(redrawn, [])
	assert_eq(plants.redraws, 0)
	# The soil dries out: the grass thins, day by day — not at once.
	var wet := int(chunk.moisture[i])
	chunk.moisture[i] = wet / 3
	var could := plants.potential(tile)
	assert_true(could < lush / 2)
	plants._grass_days(chunk.coord, 1, clock.tick)
	assert_eq(int(chunk.vegetation[i]), lush - ceili((lush - could) * config.die_per_day))
	assert_true(chunk.modified)
	var thinned_in_a_day := lush - int(chunk.vegetation[i])
	for n in 60:
		plants._grass_days(chunk.coord, 1, clock.tick)
	assert_eq(int(chunk.vegetation[i]), could, "as thin as the soil lets it be")
	# That shows: the chunk is drawn anew (once it is far from how it was drawn).
	assert_true(plants.redraws >= 1)
	assert_true(redrawn.has(chunk.coord))
	assert_true(chunk.is_dirty(ChunkData.DIRTY_MESH))
	# The soil is moist again: it comes back — more slowly than it went.
	chunk.moisture[i] = wet
	var thin := int(chunk.vegetation[i])
	plants._grass_days(chunk.coord, 1, clock.tick)
	var back_in_a_day := int(chunk.vegetation[i]) - thin
	assert_true(back_in_a_day > 0 and back_in_a_day < thinned_in_a_day, "%d back, %d gone in a day" % [back_in_a_day, thinned_in_a_day])
	for n in 200:
		plants._grass_days(chunk.coord, 1, clock.tick)
	assert_eq(int(chunk.vegetation[i]), lush, "as lush as the land was made")
	# Winter: thinner; and green again in the year after.
	clock.tick = roundi(3.5 * days * DAY - Config.time.start_hour * 60.0) # (the very middle of winter)
	for n in 40:
		plants._grass_days(chunk.coord, 1, clock.tick)
	assert_eq(int(chunk.vegetation[i]), plants.potential(tile, config.by_season[3]))
	assert_true(chunk.vegetation[i] < lush)
	# Bare ground greens from the grass beside it: alone it takes far longer.
	_midsummer()
	var size := world.chunk_size
	var beside := i + 3 # (three tiles along: its neighbours are not this tile's)
	for n: int in [i, i - 1, i + 1, i - size, i + size]:
		chunk.terrain[n] = ChunkData.Terrain.GRASS
		chunk.water[n] = 0.0
		chunk.vegetation[n] = 0
	chunk.terrain[beside] = ChunkData.Terrain.GRASS
	chunk.vegetation[beside] = 0
	chunk.vegetation[beside + 1] = 200
	chunk.terrain[beside + 1] = ChunkData.Terrain.GRASS
	chunk.moisture[beside] = chunk.moisture[i]
	chunk.fertility[beside] = chunk.fertility[i]
	soil._base_vegetation[chunk.coord][beside] = soil.base_vegetation(tile)
	soil._base_moisture[chunk.coord][beside] = soil.base_moisture(tile)
	soil._base_fertility[chunk.coord][beside] = soil.base_fertility(tile)
	plants._grass_days(chunk.coord, 1, clock.tick)
	assert_true(chunk.vegetation[beside] > chunk.vegetation[i], "%d beside grass, %d alone" % [chunk.vegetation[beside], chunk.vegetation[i]])
	assert_true(chunk.vegetation[i] > 0, "but it does come back")


func test_abandoned_ground_turns_to_grass_again() -> void:
	_midsummer()
	_knob(config, &"reclaim_chance_per_day", 1.0)
	var tile := _meadow()
	var chunk := _chunk_of(tile)
	var i := world.index_at_tile(tile)
	# Tilled ground with nothing on it, and burnt ground.
	world.set_terrain(tile, ChunkData.Terrain.FARMLAND)
	world.set_terrain(tile + Vector2i(1, 0), ChunkData.Terrain.ASH)
	chunk.vegetation[i] = 0
	plants._grass_days(chunk.coord, 1, clock.tick)
	assert_eq(world.get_terrain(tile), ChunkData.Terrain.GRASS)
	assert_eq(world.get_terrain(tile + Vector2i(1, 0)), ChunkData.Terrain.GRASS)
	assert_true(chunk.vegetation[i] <= config.bare_below, "bare at first")
	for n in 200:
		plants._grass_days(chunk.coord, 1, clock.tick)
	assert_eq(int(chunk.vegetation[i]), plants.potential(tile), "then green")
	# A field somebody tends stays a field.
	var plot: Vector2i = session.farming.next_plot()
	assert_not_null(session.farming.sow(plot, clock.tick))
	for n in 20:
		plants._grass_days(_chunk_of(plot).coord, 1, clock.tick)
	assert_eq(world.get_terrain(plot), ChunkData.Terrain.FARMLAND)
	# With the usual chance it takes its time.
	_knob(config, &"reclaim_chance_per_day", 0.0)
	world.set_terrain(tile, ChunkData.Terrain.FARMLAND)
	plants._grass_days(chunk.coord, 5, clock.tick)
	assert_eq(world.get_terrain(tile), ChunkData.Terrain.FARMLAND)


func test_trees_seed_and_die() -> void:
	_go_to(2) # spring
	var seeded: Array = []
	var deaths: Array = []
	plants.tree_seeded.connect(func(id: int) -> void: seeded.append(id))
	plants.tree_died.connect(func(tile: Vector2i, cause: StringName) -> void: deaths.append([tile, cause]))
	var grown := plants.tree_count()
	# Grown trees seed saplings on open ground near them (here: every one of them tries).
	_knob(config, &"sapling_chance_per_day", 1.0)
	for coord in world.chunk_coords():
		plants._tree_days(coord, 1, clock.tick)
	assert_true(seeded.size() > 20, "%d saplings" % seeded.size())
	assert_eq(plants.seeded, seeded.size())
	assert_eq(plants.tree_count(), grown, "a sapling is not a tree yet")
	for id: int in seeded:
		var sapling := session.props.get_prop(id)
		assert_not_null(sapling)
		assert_true(sapling.felled and sapling.stock > 0)
		assert_eq(ResourceNodes.look_of(sapling), ResourceNodes.Look.SAPLING)
		assert_true(ResourceNodes.look_scale(sapling) < 0.5)
		assert_eq(session.nodes.available(sapling), 0, "nothing to cut from it")
		var terrain := world.get_terrain(sapling.tile)
		assert_true(terrain == ChunkData.Terrain.GRASS or terrain == ChunkData.Terrain.DIRT)
		assert_near(world.get_water(sapling.tile), 0.0, 0.0001)
		assert_true(soil.moisture(sapling.tile) >= config.sapling_moisture)
		assert_true((Vector2(sapling.tile) + Vector2(0.5, 0.5)).distance_to(Vector2(session.start.settlement_tile) + Vector2(0.5, 0.5))
			>= config.settlement_clearance, "not among the huts")
		assert_false(PropData.is_generated_id(sapling.id))
	assert_true(session.nodes.tracked_count() >= seeded.size(), "they grow by the nodes' rules")
	# The forest has an upper bound: with all of them growing up, nobody seeds more.
	var cap := roundi(plants.forest_base * config.forest_most)
	for n in 12:
		for coord in world.chunk_coords():
			plants._tree_days(coord, 1, clock.tick)
	assert_true(_trees().size() <= cap, "%d trees and saplings, %d at most" % [_trees().size(), cap])
	assert_true(_trees().size() >= cap - 3, "and it is reached")
	# They grow up: after a year they are trees.
	_knob(config, &"sapling_chance_per_day", 0.0)
	var first := session.props.get_prop(seeded[0])
	clock.tick += roundi(float(Config.resources.node(&"tree")["regrow_days"]) * DAY) + DAY
	session.nodes.settle(clock.tick)
	assert_false(first.felled)
	assert_eq(ResourceNodes.look_of(first), ResourceNodes.Look.FULL)
	assert_eq(plants.tree_count(), _trees().size(), "all of them stand now")
	assert_eq(plants.tree_count(), cap)
	assert_true(plants.forest_coverage() > 0.0)
	# No seeding in autumn and winter.
	_knob(config, &"sapling_chance_per_day", 1.0)
	_knob(config, &"forest_most", 3.0)
	var before := plants.seeded
	clock.tick = _midnight(Config.time.days_per_year() * 2 + days * 2 + 2) + 720
	for coord in world.chunk_coords():
		plants._tree_days(coord, 1, clock.tick)
	assert_eq(plants.seeded, before)
	_knob(config, &"sapling_chance_per_day", 0.0)
	# A tree whose ground has dried out dies — in a drought that is why.
	weather.condition_changed.emit(WeatherSystem.DROUGHT, true)
	var drought := session.events.latest(Chronicler.TYPE_DROUGHT)
	_knob(config, &"dry_death_per_day", 1.0)
	var victim := first
	var chunk := _chunk_of(victim.tile)
	var standing := plants.tree_count()
	for prop in session.props.props_in_chunk(chunk.coord):
		chunk.moisture[world.index_at_tile(prop.tile)] = 200 # (the others stand in moist ground)
	chunk.moisture[world.index_at_tile(victim.tile)] = config.dry_below - 1
	var where := victim.tile
	var victim_id := victim.id
	plants._tree_days(chunk.coord, 1, clock.tick)
	assert_null(session.props.get_prop(victim_id))
	assert_eq(deaths, [[where, VegetationSystem.CAUSE_DROUGHT]])
	assert_eq(plants.tree_count(), standing - 1)
	assert_eq(plants.died, 1)
	var event := session.events.latest(Chronicler.TYPE_TREE_WITHERED)
	assert_not_null(event)
	assert_eq(Array(event.causes), [drought.id])
	assert_eq(event.position, Places.middle_of(where))
	assert_eq(EventText.text(event, session.people, session.events), "A tree has withered in the drought")
	assert_true(event.significance < Config.events.notify_from, "a line, not a toast")
	# Several in two days are one line.
	session.chronicle.on_tree_died(where + Vector2i(1, 0), VegetationSystem.CAUSE_DROUGHT)
	session.chronicle.on_tree_died(where + Vector2i(0, 1), VegetationSystem.CAUSE_DROUGHT)
	assert_eq(session.events.count_of(Chronicler.TYPE_TREE_WITHERED), 1)
	assert_eq(EventText.text(event, session.people, session.events), "3 trees have withered in the drought")
	# The forest has a lower bound too: below it nothing dies of drought.
	_knob(config, &"forest_least", 3.0)
	for prop in _trees():
		_chunk_of(prop.tile).moisture[world.index_at_tile(prop.tile)] = 0
	for coord in world.chunk_coords():
		plants._tree_days(coord, 1, clock.tick)
	assert_eq(plants.died, 1)
	_knob(config, &"dry_death_per_day", 0.0)
	# A cold snap kills the young, not the grown.
	_knob(config, &"cold_death_per_day", 1.0)
	_knob(config, &"sapling_chance_per_day", 1.0)
	for prop in _trees():
		_chunk_of(prop.tile).moisture[world.index_at_tile(prop.tile)] = 200
	clock.tick = _midnight(Config.time.days_per_year() * 3 + 2) + 720
	for coord in world.chunk_coords():
		plants._tree_days(coord, 1, clock.tick)
	var young := plants.seeded - before
	assert_true(young > 0)
	_knob(config, &"sapling_chance_per_day", 0.0)
	weather._conditions[WeatherSystem.COLD_SNAP] = Config.time.day_index(clock.tick)
	standing = plants.tree_count()
	deaths.clear()
	for coord in world.chunk_coords():
		plants._tree_days(coord, 1, clock.tick)
	assert_eq(deaths.size(), young)
	assert_eq(deaths[0][1], VegetationSystem.CAUSE_COLD)
	assert_eq(plants.tree_count(), standing, "the grown ones stand")
	# Felled by an axe: not standing; grown back: standing again.
	var tree := _trees()[0]
	standing = plants.tree_count()
	session.nodes.take(tree.id, 1000, clock.tick)
	assert_true(tree.felled)
	assert_eq(plants.tree_count(), standing - 1)
	clock.tick += roundi(float(Config.resources.node(&"tree")["regrow_days"]) * DAY) + DAY
	session.nodes.settle(clock.tick)
	assert_false(tree.felled)
	assert_eq(plants.tree_count(), standing)


func test_vegetation_bounds() -> void:
	# Years of the real weather over the untouched land: the grass and the forest stay within bounds.
	var grass_at_first := plants.grass_cover()
	var trees_at_first := plants.tree_count()
	var least := roundi(trees_at_first * config.forest_least)
	var most := roundi(trees_at_first * config.forest_most)
	var grass_least := 1.0
	var grass_most := 0.0
	var years := 6
	for day in Config.time.days_per_year() * years:
		_days(1)
		if day % 3 == 0:
			var cover := plants.grass_cover()
			grass_least = minf(grass_least, cover)
			grass_most = maxf(grass_most, cover)
			assert_true(plants.tree_count() >= least and plants.tree_count() <= most, "day %d: %d trees" % [day, plants.tree_count()])
			assert_true(_trees().size() <= most, "day %d: %d trees and saplings" % [day, _trees().size()])
	assert_true(grass_least > grass_at_first * 0.45, "the thinnest it got: %.2f (%.2f at first)" % [grass_least, grass_at_first])
	assert_true(grass_most < grass_at_first * 1.5, "the lushest: %.2f" % grass_most)
	assert_true(grass_most > grass_least + 0.03, "and it does change with the years")
	assert_true(plants.seeded > 0, "saplings come up")
	# Soil: every tile within what a byte holds, and on average about what the land holds by itself.
	var held := 0
	var by_itself := 0
	for chunk in world.loaded_chunks():
		var base: PackedByteArray = soil.base_layers(chunk.coord)[0]
		for i in chunk.moisture.size():
			if chunk.terrain[i] == ChunkData.Terrain.GRASS and chunk.water[i] <= 0.0:
				held += chunk.moisture[i]
				by_itself += base[i]
	assert_true(held > by_itself * 0.7 and held < by_itself * 1.3, "%d held, %d by itself" % [held, by_itself])
	# Nothing was drawn anew more often than now and then (a chunk a few times a year).
	assert_true(plants.redraws < years * 40, "%d redraws in %d years" % [plants.redraws, years])
	# The same world, the same years: the same land.
	var twin: WorldSession = SessionScript.new()
	add_child(twin)
	twin.create_new(12345)
	twin.set_process(false)
	twin.loose_system.set_process(false)
	twin.water.set_process(false)
	for step in Config.time.days_per_year() * 16:
		twin.clock.tick += 90
		twin.weather.advance_to(twin.clock.tick)
		twin.soil.advance_to(twin.clock.tick)
		if step % 8 == 0:
			twin.nodes.settle(twin.clock.tick)
	var third: WorldSession = SessionScript.new()
	add_child(third)
	third.create_new(12345)
	third.set_process(false)
	third.loose_system.set_process(false)
	third.water.set_process(false)
	for step in Config.time.days_per_year() * 16:
		third.clock.tick += 90
		third.weather.advance_to(third.clock.tick)
		third.soil.advance_to(third.clock.tick)
		if step % 8 == 0:
			third.nodes.settle(third.clock.tick)
	assert_eq(twin.vegetation.debug_text(), third.vegetation.debug_text())
	assert_eq(WorldChecksum.terrain(twin.world), WorldChecksum.terrain(third.world))
	twin.queue_free()
	third.queue_free()


func test_what_would_burn() -> void:
	_go_to(days + 3)
	var tile := _meadow(100)
	var chunk := _chunk_of(tile)
	var i := world.index_at_tile(tile)
	chunk.vegetation[i] = 255
	chunk.moisture[i] = 0
	# Lush dry grass burns well; wet ground hardly; a tree is fuel too.
	assert_near(plants.fuel_at(tile), config.fuel_grass, 0.001)
	assert_true(plants.can_burn(tile))
	chunk.moisture[i] = 255
	assert_near(plants.fuel_at(tile), config.fuel_grass * config.wet_fuel_share, 0.001)
	assert_false(plants.can_burn(tile))
	var tree := _trees()[0]
	var tree_chunk := _chunk_of(tree.tile)
	var t := world.index_at_tile(tree.tile)
	tree_chunk.moisture[t] = 0
	tree_chunk.vegetation[t] = 0
	tree_chunk.terrain[t] = ChunkData.Terrain.GRASS
	assert_near(plants.fuel_at(tree.tile), config.fuel_tree, 0.001)
	# Nothing burns in the rain, under snow, or under water — nor bare ground, nor outside the box.
	chunk.moisture[i] = 0
	weather.hold(&"rain", clock.tick + 1000 * DAY)
	assert_near(plants.fuel_at(tile), 0.0, 0.001)
	weather.hold(&"clear", clock.tick + 1000 * DAY)
	weather.snow_cover = 0.8
	assert_near(plants.fuel_at(tile), 0.0, 0.001)
	weather.snow_cover = 0.0
	chunk.water[i] = 0.1
	assert_near(plants.fuel_at(tile), 0.0, 0.001)
	chunk.water[i] = 0.0
	assert_near(plants.fuel_at(river.bed()[0]), 0.0, 0.001)
	assert_near(plants.fuel_at(Vector2i(9999, 9999)), 0.0, 0.001)
	assert_eq(plants.burn(river.bed()[0]), {})
	# Burning a tile: its grass is gone, the ground is ash — which feeds the soil.
	var burnt: Array = []
	var deaths: Array = []
	plants.burned.connect(func(where: Vector2i) -> void: burnt.append(where))
	plants.tree_died.connect(func(where: Vector2i, cause: StringName) -> void: deaths.append([where, cause]))
	var rich := int(chunk.fertility[i])
	assert_eq(plants.burn(tile), {"grass": 255, "tree": false})
	assert_eq(world.get_terrain(tile), ChunkData.Terrain.ASH)
	assert_eq(int(chunk.vegetation[i]), 0)
	assert_eq(int(chunk.fertility[i]), mini(rich + config.ash_gain, 255))
	assert_eq(burnt, [tile])
	assert_true(chunk.is_dirty(ChunkData.DIRTY_MESH))
	assert_eq(plants.burn(tile), {}, "what has burnt does not burn again")
	# A tree burns with its tile (the fire tells of it, not the chronicle of withered trees).
	var standing := plants.tree_count()
	var tree_tile := tree.tile
	var events := session.events.count_of(Chronicler.TYPE_TREE_WITHERED)
	var result := plants.burn(tree_tile)
	assert_true(result["tree"])
	assert_null(session.props.prop_at(tree_tile))
	assert_eq(plants.tree_count(), standing - 1)
	assert_eq(deaths, [[tree_tile, VegetationSystem.CAUSE_FIRE]])
	assert_eq(session.events.count_of(Chronicler.TYPE_TREE_WITHERED), events)
	# Ash turns to grass again.
	_knob(config, &"reclaim_chance_per_day", 1.0)
	plants._grass_days(chunk.coord, 1, clock.tick)
	assert_eq(world.get_terrain(tile), ChunkData.Terrain.GRASS)


func test_grass_shows_on_the_ground() -> void:
	var palette := Config.terrain_palette
	assert_eq(palette.grass(255), palette.top(ChunkData.Terrain.GRASS))
	assert_eq(palette.grass(palette.lush_from), palette.top(ChunkData.Terrain.GRASS))
	assert_true(palette.grass(0).is_equal_approx(palette.top(ChunkData.Terrain.GRASS).lerp(palette.sparse_grass, palette.sparse_strength)))
	assert_true(palette.grass(60).g < palette.grass(200).g or palette.grass(60).r > palette.grass(200).r)
	# The ground's mesh carries it.
	var tile := _meadow(palette.lush_from)
	var chunk := _chunk_of(tile)
	var lush := TerrainMesher.build_buffers(world, chunk.coord, palette, world.height_step).colors
	chunk.vegetation[world.index_at_tile(tile)] = 0
	var bare := TerrainMesher.build_buffers(world, chunk.coord, palette, world.height_step).colors
	assert_eq(lush.size(), bare.size())
	var differ := 0
	for n in lush.size():
		if not lush[n].is_equal_approx(bare[n]):
			differ += 1
	assert_eq(differ, 4, "the four corners of that tile's top")


func test_the_land_is_saved() -> void:
	_knob(config, &"sapling_chance_per_day", 0.2)
	river.enabled = false
	clock.tick = _midnight(1) + 720
	weather.advance_to(clock.tick)
	_days(4)
	assert_true(plants.seeded > 0 and soil.passes > 0)
	var saplings := 0
	for prop in _trees():
		if prop.felled:
			saplings += 1
	assert_eq(saplings, plants.seeded)
	var tile := _meadow(60)
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	assert_true(loaded.ok, loaded.error)
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	s.water.set_process(false)
	assert_eq(s.vegetation.forest_base, plants.forest_base)
	assert_eq(s.vegetation.seeded, plants.seeded)
	assert_eq(s.vegetation.tree_count(), plants.tree_count())
	assert_eq(s.soil.to_dict(), soil.to_dict())
	assert_eq(s.soil.moisture(tile), soil.moisture(tile))
	assert_eq(s.soil.base_moisture(tile), soil.base_moisture(tile), "what the land holds by itself is not what was saved")
	assert_eq(WorldChecksum.terrain(s.world), WorldChecksum.terrain(world))
	var young := 0
	for prop in s.props.all_props():
		if prop.kind == PropData.Kind.TREE and prop.felled:
			young += 1
	assert_eq(young, saplings)
	assert_true(s.nodes.tracked_count() >= saplings, "and they go on growing")
	# It goes on: a chunk's turn comes when it is due, not all at once on opening.
	var passes := s.soil.passes
	s.soil.advance_to(s.clock.tick)
	assert_eq(s.soil.passes, passes)
	s.clock.tick += DAY
	s.weather.advance_to(s.clock.tick)
	s.soil.advance_to(s.clock.tick)
	assert_true(s.soil.passes > passes)
	s.queue_free()
	# Nonsense in a save does no harm.
	soil.from_dict({"slot": "x", "coords": [1, 2], "days": PackedInt32Array([1])})
	plants.from_dict({"forest_base": -4, "seeded": "many"})
	assert_true(plants.forest_base > 0)
	assert_eq(plants.seeded, 0)


func test_version_16_save_gets_its_land() -> void:
	var dir := SaveManager.world_dir(V16_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V16_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 16)
	var loaded := SaveManager.load_world(V16_ID)
	assert_true(loaded.ok, loaded.error)
	assert_eq(loaded.world["world_state"]["soil"], {})
	assert_eq(loaded.world["world_state"]["vegetation"], {})
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	assert_eq(s.people.size(), 8)
	assert_true(s.vegetation.forest_base > 100, "the trees it has are the measure of its forest")
	assert_eq(s.vegetation.forest_base, s.vegetation.tree_count())
	assert_eq(s.soil.passes, 0)
	# Saved again: the current version, the old file kept.
	assert_true(SaveManager.save_world(s, &"test"))
	assert_true(SaveManager.SAVE_VERSION >= 17)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav.bak1")).header["save_version"], 16)
	s.queue_free()
	# The step itself.
	assert_eq(SaveMigrations._v16_to_v17({"world": {"world_state": {}}})["world"]["world_state"], {})
	var given: Dictionary = SaveMigrations._v16_to_v17({"world": {"world_state": {"people": {}}}})["world"]["world_state"]
	assert_eq([given["soil"], given["vegetation"]], [{}, {}])
	var kept: Dictionary = SaveMigrations._v16_to_v17({"world": {"world_state": {"soil": {"slot": 4}}}})
	assert_eq(kept["world"]["world_state"]["soil"], {"slot": 4})
