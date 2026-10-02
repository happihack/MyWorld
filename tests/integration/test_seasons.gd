extends TestCase
## The seasons (M9.2, bible §10.2): where in the year it is, snow lying and
## the ground freezing, ice that carries, the fields' year, the settlement
## laying in stores before winter, and the animals' year.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const V14_FIXTURE := "res://tests/fixtures/saves/v14_world.sav"
const V14_ID := "w1790963917_6393dfc8"
const DAY := 1440

var session: WorldSession
var weather: WeatherSystem
var farming: Farming
var clock: GameClock
var seasons: SeasonsConfig
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
	farming = session.farming
	clock = session.clock
	seasons = Config.seasons
	days = Config.time.days_per_season


func after_each() -> void:
	_knobs.reverse()
	for knob: Array in _knobs:
		(knob[0] as Resource).set(knob[1], knob[2])
	_knobs.clear()
	session.queue_free()
	await wait_frames(1)


func _knob(config: Resource, knob: StringName, value: Variant) -> void:
	_knobs.append([config, knob, config.get(knob)])
	config.set(knob, value)


## The tick at which a calendar day begins (its midnight).
func _midnight(day: int) -> int:
	return day * DAY - roundi(Config.time.start_hour * 60.0)


## Sets the clock to a day (at noon) and brings the weather there, held at a kind.
func _go_to(day: int, kind: StringName = &"clear") -> void:
	clock.tick = _midnight(day) + 720
	weather.advance_to(clock.tick)
	weather.hold(kind, clock.tick + 100 * DAY)


## Lets hours pass for the weather and the settlement (nobody lives).
func _hours(hours: int) -> void:
	for hour in hours:
		clock.tick += 60
		weather.advance_to(clock.tick)
		session.settlement.step(clock.tick)


func _soil(tile: Vector2i, moisture: int, fertility: int = 200) -> void:
	var chunk := session.world.chunk_at_tile(tile)
	var i := session.world.index_at_tile(tile)
	chunk.set_moisture(i, moisture)
	chunk.set_fertility(i, fertility)


func test_where_in_the_year() -> void:
	assert_eq(seasons.validate().size(), 0, str(seasons.validate()))
	assert_eq(Config.problems.size(), 0, str(Config.problems))
	assert_near(Seasons.position(_midnight(0)), 0.0, 0.001, "the first midnight of spring")
	assert_near(Seasons.position(_midnight(days)), 1.0, 0.001, "of summer")
	assert_near(Seasons.position(_midnight(days * 3 + days / 2)), 3.5, 0.001, "the middle of winter")
	assert_near(Seasons.position(_midnight(days * 4)), 0.0, 0.001, "and round again")
	assert_near(Seasons.position(0), Config.time.start_hour / 24.0 / days, 0.001, "a world begins in the morning of its first day")
	# Values by season stand for the middle of each season, and go over into one another.
	var values := PackedFloat32Array([10.0, 20.0, 30.0, 40.0])
	assert_near(Seasons.blend(values, 0.5), 10.0, 0.001)
	assert_near(Seasons.blend(values, 1.5), 20.0, 0.001)
	assert_near(Seasons.blend(values, 1.0), 15.0, 0.001, "at the turn: half way")
	assert_near(Seasons.blend(values, 0.0), 25.0, 0.001, "between winter and spring")
	assert_near(Seasons.blend(values, 3.999), 25.0, 0.05, "no jump at the year's end")
	var colours := PackedColorArray([Color.RED, Color.GREEN, Color.BLUE, Color.WHITE])
	assert_eq(Seasons.blend_color(colours, 2.5), Color.BLUE)
	assert_true(Seasons.blend_color(colours, 2.0).is_equal_approx(Color.GREEN.lerp(Color.BLUE, 0.5)))
	# How long until winter.
	assert_near(Seasons.days_until_winter(_midnight(0)), 3.0 * days, 0.01)
	assert_near(Seasons.days_until_winter(_midnight(days * 2 + days / 2)), days * 0.5, 0.01)
	assert_near(Seasons.days_until_winter(_midnight(days * 3 + 1)), 0.0, 0.001)
	assert_true(Seasons.is_winter(_midnight(days * 3 + 1)))
	assert_false(Seasons.is_winter(_midnight(days * 3) - 5))


func test_snow_lies_and_the_ground_freezes() -> void:
	var frozen: Array = []
	weather.frozen_changed.connect(func(now_frozen: bool) -> void: frozen.append(now_frozen))
	# A summer's day: nothing lies, nothing freezes.
	_go_to(days + 3)
	_hours(24)
	assert_near(weather.snow_cover, 0.0, 0.001)
	assert_near(weather.frost, 0.0, 0.001)
	assert_false(weather.is_frozen())
	# The middle of winter, snowing: it lies, more by the hour.
	_knob(Config.climate, &"air_mass_degrees", 0.0)
	_go_to(days * 3 + 2, &"snow")
	_hours(3)
	var after_three := weather.snow_cover
	assert_true(after_three > 0.1 and after_three < 0.4, "%.2f after three hours" % after_three)
	_hours(21)
	assert_near(weather.snow_cover, 1.0, 0.001, "a day of snow: everything is white")
	# And the cold gets into the ground: frozen.
	assert_true(weather.frost >= seasons.frozen_from)
	assert_true(weather.is_frozen())
	assert_eq(frozen, [true])
	assert_true(weather.debug_text().contains("FROZEN"))
	# A clear cold day: the snow stays, the frost deepens.
	weather.hold(&"clear", clock.tick + 100 * DAY)
	_hours(24)
	assert_true(weather.snow_cover > 0.6 and weather.snow_cover < 1.0, "a little goes in the afternoon sun (%.2f)" % weather.snow_cover)
	assert_true(weather.is_frozen() and weather.frost > 0.6, "the ground stays frozen (%.2f)" % weather.frost)
	# Towards spring it melts, and the ground thaws — not on the first mild afternoon (it thaws late).
	var steps := 0
	while weather.is_frozen() and steps < 24 * days:
		_hours(1)
		steps += 1
	assert_true(steps >= 24, "not at once (%d hours)" % steps)
	assert_false(weather.is_frozen())
	assert_true(weather.frost <= seasons.thawed_below + 0.001)
	assert_eq(frozen, [true, false])
	_hours(24 * 4)
	assert_near(weather.snow_cover, 0.0, 0.001, "gone")
	# Rain takes snow faster than mild air alone.
	var mild := WeatherSystem.new()
	mild.bind(GameClock.new(Config.time), Config.climate, 7)
	var wet := WeatherSystem.new()
	wet.bind(GameClock.new(Config.time), Config.climate, 7)
	for own: WeatherSystem in [mild, wet]:
		own._clock.tick = _midnight(2) + 720
		own.advance_to(own._clock.tick)
		own.snow_cover = 1.0
	mild.hold(&"cloudy", 1_000_000)
	wet.hold(&"rain", 1_000_000)
	for own: WeatherSystem in [mild, wet]:
		own._clock.tick += 9 * 60
		own.advance_to(own._clock.tick)
	assert_true(wet.snow_cover < mild.snow_cover - 0.1, "%.2f in the rain, %.2f without" % [wet.snow_cover, mild.snow_cover])
	# What lies and what is frozen is saved with the weather.
	_go_to(days * 3 + 2 + Config.time.days_per_year(), &"snow")
	_hours(30)
	var again := WeatherSystem.new()
	again.bind(clock, Config.climate, session.world_seed)
	again.from_dict(bytes_to_var(var_to_bytes(weather.to_dict())))
	assert_near(again.snow_cover, weather.snow_cover, 0.0001)
	assert_near(again.frost, weather.frost, 0.0001)
	assert_eq(again.is_frozen(), weather.is_frozen())
	assert_true(again.is_frozen())


func test_ice_carries() -> void:
	var finder := session.pathfinder
	# Shallow water and deep water beside the land.
	var shallow := Vector2i.ZERO
	var deep := Vector2i.ZERO
	var found_shallow := false
	var found_deep := false
	var bounds := session.world.bounds
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var depth := session.world.get_water(Vector2i(x, y))
			if not found_shallow and depth > Pathfinder.WET_DEPTH and depth <= seasons.ice_depth:
				shallow = Vector2i(x, y)
				found_shallow = true
			if not found_deep and depth > seasons.ice_depth + 0.1:
				deep = Vector2i(x, y)
				found_deep = true
	assert_true(found_shallow and found_deep, "the river has a shallow edge and a deep middle")
	assert_false(finder.is_frozen())
	assert_false(finder.is_ice(shallow))
	var wading := finder.speed_factor(shallow)
	assert_true(wading < 0.9, "wading is slow (%.2f)" % wading)
	# Winter: the ground freezes — and the shallow water with it.
	_knob(Config.climate, &"air_mass_degrees", 0.0)
	_go_to(days * 3 + 2, &"snow")
	_hours(26)
	assert_true(weather.is_frozen())
	assert_true(finder.is_frozen(), "the paths know")
	finder.refresh_dirty()
	assert_true(finder.is_ice(shallow))
	assert_true(finder.can_stand(shallow))
	assert_true(finder.speed_factor(shallow) > wading + 0.1, "ice carries: walked on like ground (%.2f)" % finder.speed_factor(shallow))
	assert_false(finder.is_ice(deep), "deep water does not freeze over")
	assert_false(finder.can_stand(deep))
	# Thaw: water again.
	clock.tick = _midnight(days * 4 + 2) + 720
	weather.advance_to(clock.tick)
	var steps := 0
	while weather.is_frozen() and steps < 24 * 20:
		_hours(1)
		steps += 1
	finder.refresh_dirty()
	assert_false(finder.is_frozen())
	assert_near(finder.speed_factor(shallow), wading, 0.001, "wading again")
	# The rule by itself; nothing changes when nothing changes.
	assert_true(finder.set_frozen(true, seasons.ice_depth) > 0)
	assert_eq(finder.set_frozen(true, seasons.ice_depth), 0)
	finder.refresh_dirty()
	assert_true(finder.speed_factor(shallow) > wading + 0.1)
	# A world opened in winter knows it is frozen.
	finder.set_frozen(false, seasons.ice_depth)
	_go_to(days * 3 + 2 + Config.time.days_per_year(), &"snow")
	_hours(30)
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	assert_true(s.weather.is_frozen() and s.pathfinder.is_frozen())
	s.pathfinder.refresh_dirty()
	assert_true(s.pathfinder.is_ice(shallow))
	assert_true(s.pathfinder.speed_factor(shallow) > wading + 0.1)
	s.queue_free()


func test_season_crop_rules() -> void:
	farming.rain_source = Callable() # (the fields' rules; their rain is not the point here)
	for knob: Array in [[&"rain_moisture", 0], [&"evaporation_per_day", 0], [&"crop_draw_per_day", 0], [&"seep_share", 0.0]]:
		_knob(Config.farming, knob[0], knob[1])
	var config := Config.farming
	# Sowing is for spring: while what is sown can ripen before winter.
	assert_true(farming.sowing_time(_midnight(0) + 600))
	assert_true(farming.sowing_time(_midnight(3) + 600))
	assert_false(farming.sowing_time(_midnight(days + 2) + 600), "summer: it would not ripen any more")
	assert_false(farming.sowing_time(_midnight(days * 2 + 1) + 600), "autumn")
	assert_false(farming.sowing_time(_midnight(days * 3 + 1) + 600), "winter")
	assert_true(farming.growing_days_left(_midnight(0)) >= config.grow_days)
	assert_true(farming.growing_days_left(_midnight(0)) > farming.growing_days_left(_midnight(days)))
	assert_near(farming.growing_days_left(_midnight(days * 3) + 5), 0.0, 0.001)
	# The farmer has nothing to sow in summer, autumn and winter (a field of stubble is left to rest).
	var tile: Vector2i = farming.next_plot()
	_soil(tile, 200)
	var crop := farming.sow(tile, _midnight(0) + 600)
	farming.reaped(crop, _midnight(0) + 700)
	for day: int in [days + 2, days * 2 + 2, days * 3 + 2]:
		var task := farming.task_for(null, _midnight(day) + 600)
		assert_true(task.is_empty(), "day %d: %s" % [day, task])
	assert_eq(farming.task_for(null, _midnight(Config.time.days_per_year() + 1) + 600).get("task"), Farming.SOW, "next spring")
	# Not into frozen ground, whatever the season.
	weather.frost = 1.0
	weather.frozen = true
	assert_true(farming.ground_frozen())
	assert_false(farming.sowing_time(_midnight(0) + 600), "a late frost: wait")
	weather.frost = 0.0
	weather.frozen = false
	assert_true(farming.sowing_time(_midnight(0) + 600))
	# Sown in spring, tended: ripe at the end of summer — not in spring, not in winter.
	clock.tick = _midnight(1)
	farming.last_settle_tick = -1_000_000
	var sown := farming.sow(tile, clock.tick)
	var ripe_day := -1
	for hour in 24 * days * 3:
		clock.tick += 60
		if hour % 24 == 0:
			sown.tended_tick = clock.tick
		farming.settle(clock.tick)
		if ripe_day < 0 and Farming.stage_of(sown) == Farming.Stage.RIPE:
			ripe_day = Config.time.day_index(clock.tick)
	assert_true(ripe_day >= days + 2 and ripe_day < days * 3, "ripe on day %d of the year" % ripe_day)
	assert_true(ripe_day >= days * 2 - 2, "late in summer or in autumn (day %d)" % ripe_day)
	# Ripe grain stands through a frost (it is reaped all the same); what is still growing dies.
	var beside: Vector2i = farming.next_plot()
	_soil(beside, 200)
	var late := farming.sow(beside, clock.tick) # (sown far too late)
	var killed: Array = []
	farming.frost_killed.connect(func(crop_id: int) -> void: killed.append(crop_id))
	clock.tick = _midnight(days * 3) + 600
	farming.settle(clock.tick)
	assert_eq(Farming.stage_of(late), Farming.Stage.SOWN, "winter, but no frost yet: it only stands still")
	var growth := late.growth
	clock.tick += DAY
	farming.settle(clock.tick)
	assert_eq(late.growth, growth, "nothing grows in winter")
	weather.frost = 1.0
	weather.frozen = true
	clock.tick += 120
	farming.settle(clock.tick)
	assert_eq(Farming.stage_of(late), Farming.Stage.FAILED, "the frost took it")
	assert_eq(killed, [late.id])
	assert_eq(Farming.stage_of(sown), Farming.Stage.RIPE)
	assert_true(sown.stock > 0)
	# It is written down — because of the cold snap, if there is one.
	var frozen := session.events.latest(Chronicler.TYPE_CROP_FROZEN)
	assert_not_null(frozen)
	assert_eq(frozen.position, Places.middle_of(beside))
	assert_eq(EventText.text(frozen, session.people, session.events), "A crop has frozen in the field")
	assert_true(session.chronicle.shortage_causes().has(frozen.id), "what a shortage now would be put down to")
	weather.condition_changed.emit(WeatherSystem.COLD_SNAP, true)
	clock.tick += 2 * DAY
	session.chronicle.on_crop_frozen(late.id)
	var in_the_cold := session.events.latest(Chronicler.TYPE_CROP_FROZEN)
	assert_eq(Array(in_the_cold.causes), [session.events.latest(Chronicler.TYPE_COLD_SNAP).id])
	assert_eq(EventText.text(in_the_cold, session.people, session.events), "A crop has frozen in the bitter cold")
	# The ripe grain is reaped first; then the dead crop is cleared; then the field waits for spring.
	assert_eq(farming.task_for(null, clock.tick).get("task"), Farming.HARVEST)
	session.nodes.take(sown.id, 1000, clock.tick)
	assert_eq(farming.task_for(null, clock.tick).get("task"), Farming.CLEAR)
	assert_true(farming.finish(Farming.CLEAR, beside, late.id, clock.tick))
	assert_true(farming.task_for(null, clock.tick).is_empty())
	weather.frost = 0.0
	weather.frozen = false


func test_the_settlement_lays_in_for_winter() -> void:
	var settlement := session.settlement
	var board := settlement.jobs
	var config := Config.settlement
	# In spring and summer: what it always wants.
	assert_near(settlement.winter_factor(_midnight(1), 2.0), 1.0, 0.001)
	assert_near(settlement.winter_factor(_midnight(days + 3), 2.0), 1.0, 0.001)
	# Through autumn more and more; by winter twice as much; in winter half way back.
	assert_near(settlement.winter_factor(_midnight(days * 2), 2.0), 1.0, 0.01)
	assert_near(settlement.winter_factor(_midnight(days * 2 + days / 2), 2.0), 1.5, 0.01)
	assert_near(settlement.winter_factor(_midnight(days * 3) - 1, 2.0), 2.0, 0.01)
	assert_near(settlement.winter_factor(_midnight(days * 3 + 2), 2.0), 1.5, 0.001)
	# The job board asks for it: more food and more wood wanted — and so more pressing.
	settlement.stockpile.add(&"wood", 10)
	board.refresh(settlement, _midnight(days + 3))
	var food_summer := board.job_for(&"berries").wanted if board.job_for(&"berries") != null else 0.0
	var wood_summer := board.job_for(&"wood").wanted if board.job_for(&"wood") != null else 0.0
	var pressing_summer := board.job_for(&"wood").priority if board.job_for(&"wood") != null else 0.0
	board.refresh(settlement, _midnight(days * 3) - 60)
	var food_autumn := board.job_for(&"berries").wanted
	var wood_autumn := board.job_for(&"wood").wanted
	assert_near(food_autumn, settlement.food_need_per_day() * config.food_days_wanted * config.winter_food_factor, 0.2)
	assert_near(wood_autumn, config.fire_wood_per_day * config.wood_days_wanted * config.winter_wood_factor, 0.2)
	assert_true(food_summer == 0.0 or food_autumn > food_summer * 1.8)
	assert_true(wood_summer == 0.0 or wood_autumn > wood_summer * 1.8)
	assert_true(board.job_for(&"wood").priority > pressing_summer, "the woodcutters are called more strongly")
	# No preparing if it is switched off.
	_knob(config, &"winter_prepare_days", 0.0)
	assert_near(settlement.winter_factor(_midnight(days * 3) - 1, 2.0), 1.0, 0.001)


func test_the_animals_year() -> void:
	var fauna := session.fauna
	var animals := session.animals
	var deer := session.species.get_def(&"deer")
	var rabbit := session.species.get_def(&"rabbit")
	assert_true(deer.migrates and not rabbit.migrates)
	assert_true(deer.mates_in(Seasons.SPRING) and not deer.mates_in(Seasons.SUMMER) and not deer.mates_in(Seasons.WINTER))
	assert_true(rabbit.mates_in(Seasons.SUMMER) and not rabbit.mates_in(Seasons.AUTUMN))
	assert_near(deer.mating_boost(), 4.0, 0.001, "a year's young in one season")
	assert_near(rabbit.mating_boost(), 2.0, 0.001)
	# Young are born in spring (and for rabbits in summer), in no other season.
	var born_in := [0, 0, 0, 0]
	var born_species := {}
	fauna.born.connect(func(_id: int, species_id: StringName) -> void:
		born_in[Config.time.season_of(clock.tick)] += 1
		born_species[[species_id, Config.time.season_of(clock.tick)]] = true)
	var moved: Array = []
	fauna.migrated.connect(func(species_id: StringName, group: int, to: Vector2) -> void:
		moved.append([species_id, group, to, Config.time.season_of(clock.tick), Config.time.day_of_season(clock.tick)]))
	# (Room for young: a few of each are taken out first.)
	for id: StringName in [&"deer", &"rabbit"]:
		var all := animals.of_species(id)
		for i in 2:
			fauna.hunted(all[i].id)
	var home_before: Vector2 = animals.of_species(&"deer")[0].home
	var years := 3
	var arrivals: Array = [] # [days on the way, how many got there, of how many]
	var on_the_way := 0
	for day in Config.time.days_per_year() * years:
		clock.tick = _midnight(day + 1) + 30
		fauna.advance_to(clock.tick)
		if fauna.journey_count() > 0:
			on_the_way += 1
		elif on_the_way > 0:
			# They have got there: the whole herd lives where it set out for, and is there.
			var there := 0
			for animal in animals.of_species(&"deer"):
				assert_eq(animal.home, (moved[-1] as Array)[2], "the whole herd lives there now")
				if animal.position.distance_to(animal.home) <= deer.home_range + 2.0:
					there += 1
			arrivals.append([on_the_way, there, animals.count(&"deer")])
			on_the_way = 0
	assert_true(born_in[0] > 0, "young in spring (%s)" % str(born_in))
	assert_eq(born_in[2] + born_in[3], 0, "none in autumn and winter (%s)" % str(born_in))
	assert_false(born_species.has([&"deer", 1]), "deer only in spring")
	for species_id: StringName in [&"deer", &"rabbit", &"fox"]:
		assert_true(animals.count(species_id) >= 2 and animals.count(species_id) <= session.species.get_def(species_id).capacity,
			"%d %s" % [animals.count(species_id), species_id])
	# The deer move on when autumn comes, and again in spring: well away from where they were
	# (when there is a way there that keeps clear of the people's huts).
	assert_true(moved.size() >= 2, "%d moves in %d years" % [moved.size(), years])
	for move: Array in moved:
		assert_eq(move[0], &"deer", "only those that migrate")
		assert_true(move[3] == Seasons.AUTUMN or move[3] == Seasons.SPRING)
		assert_eq(move[4], 1, "on the season's first day")
	var first: Array = moved[0]
	assert_true((first[2] as Vector2).distance_to(home_before) >= AnimalSystem.MIGRATION_MIN_TILES)
	# They get there, each by a way it can walk, within a day or two — nobody is left behind.
	assert_true(arrivals.size() >= 2, str(arrivals))
	for arrival: Array in arrivals:
		assert_true(arrival[0] <= 2, "%d days on the way" % arrival[0])
		assert_true(arrival[1] >= arrival[2] - 1, "%d of %d have arrived" % [arrival[1], arrival[2]])
	# A journey is kept in a save, and goes on from there.
	var to := home_before + Vector2(3.0, 0.0)
	fauna._journeys[animals.of_species(&"deer")[0].group] = to
	assert_eq(fauna.journey_count(), 1)
	var again := AnimalSystem.new()
	again.registry = AnimalRegistry.new()
	again.species = session.species
	again.from_dict(fauna.to_dict())
	assert_eq(again.journey_count(), 1)
	assert_eq(again._journeys.values()[0], to)
	# Time nobody lived through: they are there.
	fauna._end_journeys(clock.tick, true)
	assert_eq(fauna.journey_count(), 0)
	for animal in animals.of_species(&"deer"):
		assert_eq(animal.home, to)
		assert_true(animal.position.distance_to(to) <= 2.5)
	# It is written down.
	var event := session.events.latest(Chronicler.TYPE_HERD_MOVED)
	assert_not_null(event)
	assert_eq(EventText.text(event, session.people, session.events), "The deer have moved to other ground")
	assert_true(event.significance < Config.events.notify_from, "worth a line, not a toast")


func test_version_14_save_gets_its_ground() -> void:
	var dir := SaveManager.world_dir(V14_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V14_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 14)
	var loaded := SaveManager.load_world(V14_ID)
	assert_true(loaded.ok, loaded.error)
	var saved: Dictionary = loaded.world["world_state"]["weather"]
	assert_eq([saved["snow"], saved["frost"], saved["frozen"]], [0.0, 0.0, false])
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	assert_eq(s.people.size(), 8)
	assert_near(s.weather.snow_cover, 0.0, 0.001)
	assert_false(s.weather.is_frozen() or s.pathfinder.is_frozen())
	# Saved again: the current version, the old file kept.
	assert_true(SaveManager.save_world(s, &"test"))
	assert_true(SaveManager.SAVE_VERSION >= 15)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav.bak1")).header["save_version"], 14)
	s.queue_free()
	# The step itself.
	assert_eq(SaveMigrations._v14_to_v15({"world": {"world_state": {}}})["world"]["world_state"], {})
	var kept: Dictionary = SaveMigrations._v14_to_v15({"world": {"world_state": {"weather": {"state": "snow", "snow": 0.4}}}})
	assert_eq(kept["world"]["world_state"]["weather"], {"state": "snow", "snow": 0.4, "frost": 0.0, "frozen": false})
	assert_eq(SaveMigrations._v14_to_v15({"world": {"world_state": {"people": {}, "weather": {}}}})["world"]["world_state"]["weather"], {})
