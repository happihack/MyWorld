extends TestCase
## How the river stands (M9.3, bible §10.3): its level follows the weather,
## level water is an equilibrium (bared banks, a flooded valley floor), high
## and low water and floods are events with their causes, the fields feel
## the river and the heat, the player's water is the river's, erosion, saving.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const V15_FIXTURE := "res://tests/fixtures/saves/v15_world.sav"
const V15_ID := "w1790969220_26b21055"
const DAY := 1440

var session: WorldSession
var weather: WeatherSystem
var river: Hydrology
var water: WaterSim
var world: WorldData
var clock: GameClock
var config: HydrologyConfig
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
	water = session.water
	world = session.world
	clock = session.clock
	config = Config.hydrology
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
## a kind; the river stands where it was made.
func _go_to(day: int, kind: StringName = &"clear") -> void:
	clock.tick = _midnight(day) + 720
	weather.advance_to(clock.tick)
	weather.hold(kind, clock.tick + 1000 * DAY)
	river.level = 0.0
	river.apply(true)
	river.step(clock.tick, 0.0)


func _hours(hours: int) -> void:
	for hour in hours:
		clock.tick += 60
		weather.advance_to(clock.tick)


## Sets the river's level and has it looked at (no time passes).
func _stand_at(level: float) -> void:
	river.level = level
	river.step(clock.tick, 0.0)


## A tile of the bank: sand under shallow water as the world was made.
func _bank() -> Vector2i:
	for tile in river.bed():
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0)]:
			if world.get_terrain(tile + offset) == ChunkData.Terrain.SAND and world.get_height(tile + offset) == world.get_height(tile) + 1:
				return tile + offset
	return Vector2i(-999, -999)


func _ground(tile: Vector2i) -> float:
	return world.get_height(tile) * world.height_step


func test_the_river_as_it_was_made() -> void:
	assert_eq(config.validate().size(), 0, str(config.validate()))
	assert_eq(Config.problems.size(), 0, str(Config.problems))
	assert_true(river.bed().size() > 100, "%d tiles of bed" % river.bed().size())
	assert_near(river.surface(), session.generator.water_surface_height(), 0.0001)
	assert_near(river.level, 0.0, 0.0001)
	assert_near(river.flow(), 1.0, 0.0001)
	assert_near(river.groundwater(), 1.0, 0.0001)
	assert_false(river.high_water or river.low_water or river.flooded)
	# Its water is where the world's water is: the bed and the banks.
	var bank := _bank()
	assert_true(world.is_in_bounds(bank))
	assert_true(river.is_river(bank) and river.is_river(river.bed()[0]))
	assert_false(river.is_river(session.start.settlement_tile))
	var wet := 0
	for chunk in world.loaded_chunks():
		for depth in chunk.water:
			if depth > 0.0:
				wet += 1
	assert_eq(river.body_size(), wet)
	# Springs feed it: in the bed, the same for the same world.
	assert_eq(river.springs().size(), config.spring_count)
	for spring in river.springs():
		assert_eq(world.get_terrain(spring), ChunkData.Terrain.RIVERBED)
	var again := Hydrology.new()
	again.bind(world, null, weather, config, session.world_seed, river.surface())
	assert_eq(again.springs(), river.springs())
	assert_true(river.debug_text().begins_with("river: level"))
	# Nothing has been touched: the world is as the generator makes it.
	assert_eq(river.applies, 0)
	assert_near(river.added_total + river.removed_total, 0.0, 0.0001)
	# The valley's measures, which the config's numbers are made for.
	assert_near(world.get_water(bank), 0.16, 0.01, "the banks")
	assert_near(_ground(session.start.settlement_tile) - river.surface(), 0.24, 0.01, "the valley floor above the water")
	assert_true(config.highest - 0.24 < Pathfinder.WADE_DEPTH * world.height_step, "a flood can be waded")


func test_the_river_follows_the_weather() -> void:
	var lows: Array = []
	var highs: Array = []
	river.low_water_changed.connect(func(active: bool) -> void: lows.append(active))
	river.high_water_changed.connect(func(active: bool) -> void: highs.append(active))
	var bank := _bank()
	var bed := river.bed()[0]
	var deep := world.get_water(bed)
	var volume := water.total_volume()
	# Two dry weeks of summer: it falls, until the banks lie dry.
	_go_to(days + 1, &"clear")
	_hours(24 * 3)
	assert_true(river.level < -0.02 and river.level > config.low_from, "falling, not at once (%.3f)" % river.level)
	_hours(24 * 11)
	assert_true(river.level <= config.low_from, "%.3f" % river.level)
	assert_true(river.level >= config.lowest)
	assert_true(river.low_water)
	assert_eq(lows, [true])
	assert_near(world.get_water(bank), 0.0, 0.0001, "the bank lies dry")
	assert_false(river.is_river(bank))
	assert_near(world.get_water(bed), deep + river.applied, 0.001, "the bed holds less")
	assert_true(water.total_volume() < volume * 0.8)
	assert_true(river.groundwater() < 0.8 and river.flow() < 0.7)
	assert_near(water.river_flow, river.flow(), 0.0001)
	assert_true(river.debug_text().contains("LOW WATER"))
	var low := river.level
	# However long it lasts, the springs do not run dry.
	_hours(24 * 30)
	assert_true(river.level >= config.lowest and river.level > low - 0.08, "%.3f" % river.level)
	assert_true(world.get_water(bed) > 0.15)
	# Rain raises it at once (it runs off the land) …
	weather.hold(&"storm", clock.tick + 1000 * DAY)
	var before := river.level
	_hours(3)
	assert_true(river.level - before >= config.rain_rise * weather.precipitation() * 3.0 * 0.9, "%.3f in three hours" % (river.level - before))
	# … the banks are under water again …
	_hours(24)
	assert_false(river.low_water)
	assert_eq(lows, [true, false])
	assert_true(world.get_water(bank) > 0.0)
	# … and days of storm bring high water — but the box is not filled.
	_hours(24 * 3)
	assert_true(river.high_water, "%.3f" % river.level)
	assert_eq(highs, [true])
	assert_true(river.flow() > 1.5)
	_hours(24 * 20)
	assert_near(river.level, config.highest, 0.0001)
	assert_true(water.total_volume() < volume * 6.0)
	# It clears up: the river goes back into its bed.
	weather.hold(&"clear", clock.tick + 1000 * DAY)
	var steps := 0
	while river.high_water and steps < 24 * 20:
		_hours(3)
		steps += 3
	assert_false(river.high_water)
	assert_true(steps >= 24, "not in a day (%d hours)" % steps)
	assert_eq(highs, [true, false])
	# Melting snow raises it too; and under ice it moves slowly.
	_go_to(days * 3 + 3, &"clear")
	weather.snow_cover = 1.0
	river.step(clock.tick, 0.0)
	weather.snow_cover = 0.5
	river.step(clock.tick, 0.0)
	assert_near(river.level, config.melt_rise * 0.5, 0.0001)
	river.level = 0.2
	river.apply(true)
	var free := Hydrology.new()
	free.bind(world, null, weather, config, session.world_seed, river.surface())
	free.level = 0.2
	weather.frozen = true
	river.step(clock.tick, 12.0)
	weather.frozen = false
	free.step(clock.tick, 12.0)
	assert_true(river.level > free.level + 0.005, "frozen %.3f, open %.3f" % [river.level, free.level])


func test_level_water_is_an_equilibrium() -> void:
	var bank := _bank()
	var home := session.start.settlement_tile
	session.pathfinder.refresh_dirty()
	var wading := session.pathfinder.speed_factor(bank)
	var made := {} # the world's water as it was made
	for tile: Vector2i in river._body:
		made[tile] = world.get_water(tile)
	var volume := water.total_volume()
	var changes: Array = []
	river.level_changed.connect(func(level: float) -> void: changes.append(level))
	# A little movement is not set on the tiles; enough of it is.
	river.level = config.apply_step * 0.4
	assert_true(river.apply().is_empty())
	assert_eq(changes, [])
	for level: float in [-0.2, 0.1, 0.3, -0.1, 0.0]:
		river.level = level
		var changed := river.apply()
		assert_false(changed.is_empty())
		assert_near(river.applied, level, 0.0001)
		assert_near(river.surface(), session.generator.water_surface_height() + level, 0.0001)
		# Every tile of the river stands at the same surface; and nothing beside it lies lower and dry.
		for tile: Vector2i in river._body:
			assert_near(_ground(tile) + world.get_water(tile), river.surface(), 0.0005)
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var beside := tile + offset
				if world.is_in_bounds(beside) and not river.is_river(beside):
					assert_true(_ground(beside) > river.surface() - config.least_depth - 0.0001, "%s beside %s" % [beside, tile])
		for tile in river.bed():
			assert_true(river.is_river(tile), "the bed is always under water")
		# The water that moves has nothing to do: level water does not flow.
		assert_true(water.is_still())
		assert_near(water._depth[water._index(bank)], world.get_water(bank), 0.0001, "and it knows the depths")
		# Every drop is in the books.
		assert_near(water.total_volume(), volume + river.added_total - river.removed_total, 0.01)
		match level:
			-0.2:
				assert_near(world.get_water(bank), 0.0, 0.0001)
				assert_true(session.pathfinder.can_stand(bank))
				session.pathfinder.refresh_dirty()
				assert_true(session.pathfinder.speed_factor(bank) > wading + 0.1, "dry sand is walked on, not waded through")
			0.3:
				# Over the banks: the valley floor is under water — the settlement too.
				assert_true(river.is_river(home))
				assert_near(world.get_water(home), 0.06, 0.001)
				assert_true(river.body_size() > made.size() * 3)
				assert_eq(world.chunk_at_tile(home).moisture[world.index_at_tile(home)], 255, "soaked")
				session.pathfinder.refresh_dirty()
				var beside_home := home
				for tile: Vector2i in river._body:
					if world.get_height(tile) == world.get_height(home) and session.props.prop_at(tile) == null 							and Vector2(tile).distance_to(Vector2(home)) < 6.0:
						beside_home = tile
						break
				assert_ne(beside_home, home, "open ground by the huts, under water")
				assert_true(session.pathfinder.can_stand(beside_home), "it can be waded")
				assert_true(session.pathfinder.speed_factor(beside_home) < 0.9, "slowly")
				assert_eq(river.flooded_tiles().size(), session.settled_tiles().size())
			-0.1:
				assert_false(river.is_river(home))
				assert_near(world.get_water(home), 0.0, 0.0001, "it has run off")
	assert_eq(changes.size(), 5)
	# Back where it was made: exactly the water there was.
	assert_eq(river.body_size(), made.size())
	for tile: Vector2i in made:
		assert_near(world.get_water(tile), made[tile], 0.0005)
	assert_near(water.total_volume(), volume, 0.05)
	assert_true(river.flooded_tiles().is_empty())


func test_flood_event_causes() -> void:
	var events := session.events
	var floods: Array = []
	river.flood_changed.connect(func(active: bool, tiles: int, at: Vector2) -> void: floods.append([active, tiles, at]))
	# Days of storm in autumn: the river rises to its banks' edge, then over them.
	_go_to(days * 2 + 1, &"storm")
	var storm := events.latest(Chronicler.TYPE_STORM)
	assert_not_null(storm)
	var steps := 0
	while not river.flooded and steps < 24 * 12:
		_hours(3)
		steps += 3
	assert_true(river.flooded, "after %d hours the river stands at %.2f" % [steps, river.level])
	assert_true(steps >= 24, "not on the first day (%d hours)" % steps)
	var high := events.latest(Chronicler.TYPE_HIGH_WATER)
	var flood := events.latest(Chronicler.TYPE_FLOOD)
	assert_not_null(high)
	assert_not_null(flood)
	assert_true(high.tick < flood.tick, "high water first")
	# The causes are written down: the storm raised the river, the river flooded the settlement.
	storm = events.latest(Chronicler.TYPE_STORM)
	assert_true(Array(high.causes).has(events.of_type(Chronicler.TYPE_STORM, high.tick - 2 * DAY, high.tick)[-1].id))
	assert_eq(Array(flood.causes), [high.id])
	assert_true(events.led_to(high.id, flood.id))
	assert_eq(EventText.text(high, session.people, events), "After the storm the river is rising to the edge of its banks")
	assert_eq(EventText.text(flood, session.people, events), "The river has come over its banks: the settlement is under water")
	assert_true(flood.significance >= Config.events.high_from, "it matters a great deal")
	assert_eq(session.chronicle.condition_id(Chronicler.TYPE_FLOOD), flood.id)
	# Where: among the huts.
	assert_eq(floods.size(), 1)
	assert_true(floods[0][0] and floods[0][1] >= config.flood_tiles)
	assert_true(flood.position.distance_to(Vector2(session.start.settlement_tile)) < 8.0)
	assert_true(river.flooded_tiles().size() >= config.flood_tiles)
	assert_true(river.debug_text().contains("FLOOD"))
	# It clears up: the water runs off, and that is noted on the events.
	weather.hold(&"clear", clock.tick + 1000 * DAY)
	steps = 0
	while (river.flooded or river.high_water) and steps < 24 * 20:
		_hours(3)
		steps += 3
	assert_false(river.flooded or river.high_water)
	assert_eq(floods.size(), 2)
	assert_false(floods[1][0])
	assert_true(flood.effects.has("ended") and high.effects.has("ended"))
	assert_eq(session.chronicle.condition_id(Chronicler.TYPE_FLOOD), 0)
	assert_eq(events.count_of(Chronicler.TYPE_FLOOD), 1, "one flood, one event")
	assert_near(world.get_water(session.start.settlement_tile), 0.0, 0.0001)
	# One wet tile is no flood; and without a storm high water is only high water.
	_stand_at(0.3)
	assert_true(river.flooded)
	assert_eq(EventText.text(events.latest(Chronicler.TYPE_HIGH_WATER), session.people, events), "The river is rising to the edge of its banks")
	_stand_at(0.0)
	assert_false(river.flooded)
	river.settled_source = func() -> Array[Vector2i]:
		var none: Array[Vector2i] = []
		return none
	_stand_at(0.3)
	assert_false(river.flooded, "nobody lives there")


func test_low_water_and_what_it_does_to_the_fields() -> void:
	var events := session.events
	var farming := session.farming
	_go_to(days + 2, &"clear")
	# A drought, and the river falls: the banks lie dry — because of the drought.
	weather.condition_changed.emit(WeatherSystem.DROUGHT, true)
	var drought := events.latest(Chronicler.TYPE_DROUGHT)
	assert_not_null(drought)
	_stand_at(-0.2)
	assert_true(river.low_water)
	var low := events.latest(Chronicler.TYPE_LOW_WATER)
	assert_not_null(low)
	assert_eq(Array(low.causes), [drought.id])
	assert_eq(EventText.text(low, session.people, events), "The river has fallen in the drought: its banks lie dry")
	# The ground beside a low river holds less: the fields dry out.
	assert_near(river.groundwater(), 1.0 - 0.2 * config.groundwater_per_level, 0.001)
	_knob(Config.farming, &"seep_share", 1.0)
	_knob(Config.farming, &"crop_draw_per_day", 0)
	farming.rain_source = func(_day: int) -> bool: return false
	var tile: Vector2i = farming.next_plot()
	var crop := farming.sow(tile, clock.tick)
	assert_false(farming._wet_beside(tile))
	var base := farming._baseline_of(tile)
	var chunk := world.chunk_at_tile(tile)
	var i := world.index_at_tile(tile)
	chunk.set_moisture(i, 0)
	farming._soil_day(Config.time.day_index(clock.tick))
	assert_eq(int(chunk.moisture[i]), roundi(base * river.groundwater()), "what the land holds beside a low river")
	assert_true(Farming.moisture_factor(chunk.moisture[i]) < Farming.moisture_factor(base) or base * river.groundwater() >= Config.farming.good_from)
	# A crop that fails now is put down to the low river.
	session.chronicle.on_crop_failed(crop.id)
	var failed := events.latest(Chronicler.TYPE_CROP_FAILURE)
	assert_not_null(failed)
	assert_true(Array(failed.causes).has(low.id))
	assert_eq(EventText.text(failed, session.people, events), "A crop has withered: the ground has dried out with the river so low")
	assert_true(events.led_to(drought.id, failed.id), "drought, low water, failed crop")
	# The river back in its bed: the ground holds what it held.
	_stand_at(0.0)
	assert_false(river.low_water)
	assert_true(low.effects.has("ended"))
	chunk.set_moisture(i, 0)
	farming._soil_day(Config.time.day_index(clock.tick))
	assert_eq(int(chunk.moisture[i]), base)
	# A high river: a little more, within bounds.
	river.level = 0.4
	assert_near(river.groundwater(), config.groundwater_most, 0.001)
	river.level = -0.36
	assert_near(river.groundwater(), config.groundwater_least, 0.001)
	river.level = 0.0


func test_weather_effects() -> void:
	# Rain raises the soil's moisture; a dry day lowers it — a hot one more than a cool one.
	var farming := session.farming
	_go_to(2, &"clear")
	_knob(Config.farming, &"seep_share", 0.0)
	_knob(Config.farming, &"crop_draw_per_day", 0)
	var rainy := [false]
	farming.rain_source = func(_day: int) -> bool: return rainy[0]
	var tile: Vector2i = farming.next_plot()
	farming.sow(tile, clock.tick)
	assert_false(farming._wet_beside(tile))
	var chunk := world.chunk_at_tile(tile)
	var i := world.index_at_tile(tile)
	var day := Config.time.day_index(clock.tick)
	var usual: int = Config.farming.evaporation_per_day
	# An ordinary dry day (20 degrees at its warmest).
	weather._warmest[day] = config.drying_normal_degrees
	assert_near(river.drying(day), 1.0, 0.001)
	chunk.set_moisture(i, 150)
	farming._soil_day(day)
	assert_eq(int(chunk.moisture[i]), 150 - usual)
	# A hot day dries it faster, a cool one hardly.
	weather._warmest[day] = 30.0
	assert_near(river.drying(day), 1.5, 0.001)
	chunk.set_moisture(i, 150)
	farming._soil_day(day)
	assert_eq(int(chunk.moisture[i]), 150 - roundi(usual * 1.5))
	weather._warmest[day] = 2.0
	assert_near(river.drying(day), config.drying_least, 0.001)
	chunk.set_moisture(i, 150)
	farming._soil_day(day)
	assert_eq(int(chunk.moisture[i]), 150 - roundi(usual * config.drying_least))
	weather._warmest[day] = 60.0
	assert_near(river.drying(day), config.drying_most, 0.001)
	assert_near(river.drying(day + 500), 1.0, 0.001, "a day nobody watched: as usual")
	# Rain: wetter, even on a hot day.
	weather._warmest[day] = 30.0
	rainy[0] = true
	chunk.set_moisture(i, 150)
	farming._soil_day(day)
	assert_eq(int(chunk.moisture[i]), 150 + Config.farming.rain_moisture - roundi(usual * 1.5))
	assert_true(chunk.moisture[i] > 150)
	# And the real thing: a day of the weather's rain wets the field, the dry days after it dry it.
	farming.rain_source = weather.rain_on
	weather.hold(&"rain", clock.tick + 1000 * DAY)
	farming.settle(clock.tick)
	chunk.set_moisture(i, 120)
	_hours(24)
	farming.settle(clock.tick)
	var wet := int(chunk.moisture[i])
	assert_true(wet > 120, "%d after a day of rain" % wet)
	weather.hold(&"clear", clock.tick + 1000 * DAY)
	_hours(24) # (the day the rain stopped on still counts as a rainy one)
	farming.settle(clock.tick)
	wet = int(chunk.moisture[i])
	_hours(48)
	farming.settle(clock.tick)
	assert_true(chunk.moisture[i] < wet, "%d after two dry days (%d before them)" % [chunk.moisture[i], wet])


func test_the_players_water_is_the_rivers() -> void:
	_go_to(2, &"clear")
	var bed := river.bed()
	var volume := water.total_volume()
	# Water poured into the river (a great deal of it): it flows, and settles.
	for n in 40:
		water.add_water(bed[n * 3], 0.5)
	assert_false(water.is_still())
	# While it flows the river's level is not set over it …
	river.level = 0.1
	var applies := river.applies
	river.step(clock.tick, 0.0)
	river.step(clock.tick, 0.0)
	assert_eq(river.applies, applies, "put off")
	river.level = 0.0
	var steps := 0
	while not water.is_still() and steps < 3000:
		water.step_once()
		steps += 1
	assert_true(water.is_still(), "still after %d steps" % steps)
	assert_near(water.total_volume(), volume + 20.0, 0.5)
	# … and when it has settled it is in the river's level: the river stands higher.
	river.step(clock.tick, 0.0)
	assert_true(river.level > 0.03 and river.level < 0.08, "%.3f" % river.level)
	assert_near(water.total_volume(), volume + 20.0, 4.0, "nothing much was lost or made")
	assert_near(world.get_water(bed[0]) + _ground(bed[0]), river.surface(), 0.001)
	# Scooped out again: lower.
	var high := river.level
	for n in 40:
		water.take_water(bed[n * 3], 0.5)
	steps = 0
	while not water.is_still() and steps < 3000:
		water.step_once()
		steps += 1
	river.step(clock.tick, 0.0)
	assert_true(river.level < high - 0.03, "%.3f" % river.level)
	# Water that will not come to rest does not hold the river up for ever.
	water.add_water(bed[5], 0.3)
	river.level = 0.2
	applies = river.applies
	for n in Hydrology.MAX_PUT_OFF + 1:
		river.step(clock.tick, 0.0)
	assert_eq(river.applies, applies + 1)
	assert_near(river.applied, 0.2, 0.0001)


func test_the_river_runs_harder_when_it_stands_high() -> void:
	_go_to(2, &"clear")
	var middle := Vector2i.ZERO
	for tile in river.bed():
		if absf(session.generator.river_center_x(tile.y) - (tile.x + 0.5)) < 0.6:
			middle = tile
			break
	var usual := water.current_at(middle).length()
	assert_true(usual > 0.3)
	_stand_at(0.3)
	assert_near(water.river_flow, 1.0 + 0.3 * config.flow_per_level, 0.001)
	assert_near(water.current_at(middle).length(), usual * water.river_flow, 0.01)
	_stand_at(-0.3)
	assert_near(water.river_flow, config.flow_least, 0.001)
	assert_true(water.current_at(middle).length() < usual * 0.5)
	river.level = 2.0
	assert_near(river.flow(), config.flow_most, 0.001)
	river.level = 0.0


func test_high_water_takes_a_piece_of_the_bank() -> void:
	_go_to(days * 2 + 1, &"clear")
	var taken: Array = []
	river.eroded.connect(func(tile: Vector2i) -> void: taken.append(tile))
	# Not when the dice say no.
	_knob(config, &"erosion_chance", 0.0)
	_stand_at(0.3)
	assert_eq(taken, [])
	_stand_at(0.0)
	# When they say yes: one tile of sand beside the bed becomes bed.
	_knob(config, &"erosion_chance", 1.0)
	var beds := river.bed().size()
	var before := {}
	for tile in river.bed():
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0)]:
			before[tile + offset] = [world.get_terrain(tile + offset), world.get_height(tile + offset)]
	_stand_at(0.3)
	assert_eq(taken.size(), 1)
	var tile: Vector2i = taken[0]
	assert_eq(before[tile][0], ChunkData.Terrain.SAND)
	assert_eq(world.get_terrain(tile), ChunkData.Terrain.RIVERBED)
	assert_eq(world.get_height(tile), int(before[tile][1]) - 1)
	assert_eq(river.bed().size(), beds + 1)
	assert_true(river.bed().has(tile))
	assert_eq(river.eroded_count, 1)
	assert_near(world.get_water(tile) + _ground(tile), river.surface(), 0.001, "as deep as the bed now")
	assert_near(water._ground[water._index(tile)], _ground(tile), 0.0001, "the moving water knows the ground")
	assert_true(world.chunk_at_tile(tile).modified, "a change of the ground: kept in the save")
	# Written down (a line, no toast) — because of the high water.
	var event := session.events.latest(Chronicler.TYPE_BANK_ERODED)
	assert_not_null(event)
	assert_eq(event.position, Places.middle_of(tile))
	assert_eq(Array(event.causes), [session.chronicle.condition_id(Chronicler.TYPE_HIGH_WATER)])
	assert_eq(EventText.text(event, session.people, session.events), "The river has taken a piece of its bank")
	assert_true(event.significance < Config.events.notify_from)
	# Once for each high water; and never more than the config allows.
	river.step(clock.tick, 0.0)
	assert_eq(taken.size(), 1)
	_knob(config, &"erosion_most", 1)
	_stand_at(0.0)
	_stand_at(0.3)
	assert_eq(taken.size(), 1)
	# A world opened again finds the new bed.
	var again := Hydrology.new()
	again.bind(world, null, weather, config, session.world_seed, session.generator.water_surface_height())
	assert_true(again.bed().has(tile))


func test_the_river_is_saved() -> void:
	_go_to(days * 2 + 1, &"clear")
	_stand_at(0.3)
	river.level = 0.293
	assert_true(river.flooded and river.high_water)
	var body := river.body_size()
	var home := session.start.settlement_tile
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	assert_true(loaded.ok, loaded.error)
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	s.water.set_process(false)
	assert_near(s.hydrology.level, 0.293, 0.0001)
	assert_near(s.hydrology.applied, 0.3, 0.0001)
	assert_true(s.hydrology.flooded and s.hydrology.high_water and not s.hydrology.low_water)
	assert_eq(s.hydrology.body_size(), body)
	assert_near(s.world.get_water(home), world.get_water(home), 0.0001)
	assert_near(s.hydrology.added_total, river.added_total, 0.001)
	assert_near(s.water.river_flow, s.hydrology.flow(), 0.0001)
	assert_eq(s.hydrology.eroded_count, river.eroded_count)
	# It goes on from there: the water runs off, and the land it leaves is dry.
	s.weather.hold(&"clear", s.clock.tick + 1000 * DAY)
	for step in 8 * 12:
		s.clock.tick += 180
		s.weather.advance_to(s.clock.tick)
	assert_false(s.hydrology.flooded, s.hydrology.debug_text())
	assert_near(s.world.get_water(home), 0.0, 0.0001)
	s.queue_free()
	# Nonsense in a save does no harm.
	river.from_dict({"level": "high", "applied": NAN, "high": 3, "added": -5.0})
	assert_near(river.level, 0.0, 0.0001)
	assert_near(river.applied, 0.0, 0.0001)
	assert_false(river.high_water)
	river.from_dict({"level": 99.0})
	assert_near(river.level, config.highest, 0.0001)


func test_version_15_save_gets_its_river() -> void:
	var dir := SaveManager.world_dir(V15_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V15_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 15)
	var loaded := SaveManager.load_world(V15_ID)
	assert_true(loaded.ok, loaded.error)
	assert_eq(loaded.world["world_state"]["hydrology"], {})
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	assert_eq(s.people.size(), 8)
	assert_near(s.hydrology.level, 0.0, 0.0001, "the river stands where it was made")
	assert_true(s.hydrology.body_size() > 100)
	assert_false(s.hydrology.high_water or s.hydrology.low_water or s.hydrology.flooded)
	# Saved again: the current version, the old file kept.
	assert_true(SaveManager.save_world(s, &"test"))
	assert_true(SaveManager.SAVE_VERSION >= 16)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav.bak1")).header["save_version"], 15)
	s.queue_free()
	# The step itself.
	assert_eq(SaveMigrations._v15_to_v16({"world": {"world_state": {}}})["world"]["world_state"], {})
	assert_eq(SaveMigrations._v15_to_v16({"world": {"world_state": {"people": {}}}})["world"]["world_state"]["hydrology"], {})
	var kept: Dictionary = SaveMigrations._v15_to_v16({"world": {"world_state": {"hydrology": {"level": 0.1}}}})
	assert_eq(kept["world"]["world_state"]["hydrology"], {"level": 0.1})
