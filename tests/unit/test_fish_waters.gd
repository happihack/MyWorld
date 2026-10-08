extends TestCase
## Where the fish are (FB1, bible §18.2a): the water in cells, each with its
## own fish — more in deep, quiet water, fewer in shallows; taken where one
## fishes; coming back by the season; the spring run; the bad fishing year.

const DAY := 1440

var world: WorldData
var waters: FishWaters
var rng: RandomNumberGenerator
## A deep pool (cell 0,0) and a shallow reach (cell 1,0), 16 tiles each.
var deep := Vector2i(2, 2)
var shallow := Vector2i(10, 2)


func before_each() -> void:
	world = WorldData.create_centered(32, 16, 0.4)
	for y in range(0, 4):
		for x in range(0, 4):
			world.set_water(Vector2i(x, y), 1.2) # three levels deep
			world.set_water(Vector2i(8 + x, y), 0.1) # a quarter of a level
	waters = FishWaters.new()
	waters.bind(world)
	rng = RandomNumberGenerator.new()
	rng.seed = 7


func _cap(tile: Vector2i) -> float:
	return waters.capacity_at(tile)


func test_deep_quiet_water_holds_more_fish() -> void:
	assert_true(_cap(deep) > _cap(shallow) * 3.0, "the pool %.1f, the shallows %.1f" % [_cap(deep), _cap(shallow)])
	assert_near(waters.total_capacity(), 16.0 * FishWaters.DEEP_SHARE / FishWaters.TILES_PER_FISH
		+ 16.0 * FishWaters.SHALLOW_SHARE / FishWaters.TILES_PER_FISH, 0.001)
	assert_eq(waters.stock_at(Vector2i(20, 20)), 0.0, "no water, no fish")


func test_fish_are_taken_where_one_fishes() -> void:
	waters.set_total(waters.total_capacity())
	var pool := waters.stock_at(deep)
	var reach := waters.stock_at(shallow)
	assert_eq(waters.take(2, deep), 2)
	assert_near(waters.stock_at(deep), pool - 2.0, 0.001)
	assert_near(waters.stock_at(shallow), reach, 0.001, "the other water untouched")
	assert_eq(waters.take(1000, deep), floori(pool - 2.0), "that water fished out")
	assert_eq(waters.take(1, deep), 0)
	assert_eq(waters.take(1, Vector2i(20, 20)), 0, "nothing where there is no water")


func test_they_come_back_by_the_season_and_slowly_when_fished_hard() -> void:
	var spring := 0
	var winter := 3 * Config.time.days_per_season * DAY
	waters.set_total(0.0)
	waters.set_stock(deep, _cap(deep) * 0.5)
	# (Day 2 of a season: not the first of spring, no run.)
	waters.advance_day(spring + 2 * DAY, rng)
	var spring_gain := waters.stock_at(deep) - _cap(deep) * 0.5
	waters.set_stock(deep, _cap(deep) * 0.5)
	waters.advance_day(winter + 2 * DAY, rng)
	var winter_gain := waters.stock_at(deep) - _cap(deep) * 0.5
	assert_true(spring_gain > winter_gain * 3.0, "spring %.2f, winter %.2f" % [spring_gain, winter_gain])
	waters.set_stock(deep, _cap(deep) * 0.1)
	waters.advance_day(spring + 3 * DAY, rng)
	var hard_gain := waters.stock_at(deep) - _cap(deep) * 0.1
	assert_true(hard_gain < spring_gain * 0.9 * 1.8, "fished hard, it comes back more slowly (%.2f)" % hard_gain)


func test_the_spring_run() -> void:
	waters.set_total(waters.total_capacity())
	var told := []
	waters.run_began.connect(func(at: Vector2i) -> void: told.append(at))
	var first_of_spring := Config.time.ticks_per_year() # (day 1 of spring of year 2: tick 0 is day 1 of year 1)
	waters.advance_day(first_of_spring, rng)
	var run := waters.run_cell()
	assert_ne(run, Vector2i.MAX, "the fish run somewhere")
	var at := FishWaters.middle_of(run)
	assert_near(waters.richness_at(at), FishWaters.RUN_SHARE, 0.001, "thick with fish")
	assert_eq(told.size(), 0, "told when someone fishes there")
	waters.take(1, at)
	assert_eq(told.size(), 1)
	waters.take(1, at)
	assert_eq(told.size(), 1, "once")
	for day in FishWaters.RUN_DAYS + 3:
		waters.advance_day(first_of_spring + (day + 1) * DAY, rng)
	assert_eq(waters.run_cell(), Vector2i.MAX, "over in a few days")
	assert_true(waters.richness_at(at) <= 1.0 + 0.001, "and the water as it was")


func test_a_bad_fishing_year_is_told() -> void:
	var told := []
	waters.bad_year.connect(func(id: int, caught: int, usual: float) -> void: told.append([id, caught, usual]))
	var year := Config.time.ticks_per_year()
	for y in 4:
		waters.note_catch(5, 60, y * year + DAY) # years 1 … 4
	waters.note_catch(5, 10, 4 * year + DAY) # year 5
	waters.note_catch(6, 3, 3 * year + DAY) # (too few to be usual: never told)
	waters.note_catch(6, 1, 4 * year + DAY)
	waters.advance_day(5 * year, rng) # the first of spring of year 6: year 5 is weighed
	assert_eq(told.size(), 1)
	assert_eq(told[0][0], 5)
	assert_eq(told[0][1], 10)
	assert_near(float(told[0][2]), 60.0, 0.001)


func test_saved_and_restored() -> void:
	waters.set_total(waters.total_capacity())
	waters.take(3, deep)
	waters.note_catch(4, 9, DAY)
	var again := FishWaters.new()
	again.bind(world)
	assert_true(again.from_dict(waters.to_dict()))
	assert_near(again.stock_at(deep), waters.stock_at(deep), 0.001)
	assert_eq(again.caught(4, 1), 9, "the first year's catch")
	assert_false(FishWaters.new().from_dict({"fish": 12.0}), "an older save: nothing by cell")
