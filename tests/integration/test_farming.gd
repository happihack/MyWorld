extends TestCase
## Simple agriculture (M7.3): someone takes up farming, plots are tilled and
## sown, grain grows through its stages by what the soil gives it, wilts and
## fails when the soil is dry, is reaped and carried home — and the ground
## is the poorer for it.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const V10_FIXTURE := "res://tests/fixtures/saves/v10_world.sav"
const V10_ID := "w1790891177_8d77c879"

var session: WorldSession
var behavior: BehaviorSystem
var ctx: AiContext
var farming: Farming
var config: FarmingConfig
var _knobs: Dictionary = {}


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
	farming = session.farming
	# (These are the rules of the fields: with the rain FarmingConfig makes up,
	# which a test can set. That the weather's rain reaches them is test_weather's.)
	farming.rain_source = Callable()
	config = Config.farming
	_knobs.clear()


func after_each() -> void:
	for knob: StringName in _knobs:
		Config.farming.set(knob, _knobs[knob])
	Config.settlement.fire_wood_per_day = SettlementConfig.new().fire_wood_per_day
	session.queue_free()
	await wait_frames(1)


## Changes one of the farming numbers for the length of a test.
func _knob(knob: StringName, value: Variant) -> void:
	if not _knobs.has(knob):
		_knobs[knob] = Config.farming.get(knob)
	Config.farming.set(knob, value)


## The soil keeps the moisture it is given (no rain, no drying, no ground water).
func _still_soil() -> void:
	_knob(&"rain_moisture", 0)
	_knob(&"evaporation_per_day", 0)
	_knob(&"crop_draw_per_day", 0)
	_knob(&"seep_share", 0.0)


func _run(minutes: float, step: float = 1.0, of: WorldSession = null) -> void:
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


## Lets time pass for the fields alone, an hour at a time.
func _grow(hours: int) -> void:
	for hour in hours:
		session.clock.tick += 60
		farming.settle(session.clock.tick)


func _farmer() -> PersonData:
	for p in session.people.all_people():
		if p.occupation_id == &"farmer":
			return p
	return null


func _soil(tile: Vector2i, moisture: int, fertility: int = -1) -> void:
	var chunk := session.world.chunk_at_tile(tile)
	var i := session.world.index_at_tile(tile)
	chunk.set_moisture(i, moisture)
	if fertility >= 0:
		chunk.set_fertility(i, fertility)


## A new plot with soil as given, sown now.
func _plot(moisture: int = 200, fertility: int = 200) -> PropData:
	var tile: Vector2i = farming.next_plot()
	_soil(tile, moisture, fertility)
	return farming.sow(tile, session.clock.tick)


func _only(people: Array) -> void:
	for p in session.people.all_people():
		if not people.has(p):
			behavior.set_plan(p, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(1000000.0)])


func _calm(person: PersonData) -> PersonData:
	person.needs = PackedFloat32Array([0.9, 0.95, 0.9, 0.9, 0.6, 1.0])
	return person


func _winter_tick() -> int:
	return 3 * Config.time.days_per_season * 1440 + 600


# --- who farms ------------------------------------------------------------------------------------

func test_someone_takes_up_farming() -> void:
	assert_eq(config.validate().size(), 0)
	assert_eq(Config.problems.size(), 0, str(Config.problems))
	var def := session.occupations.get_def(&"farmer")
	assert_not_null(def)
	assert_eq(def.work_target, &"field")
	assert_eq(def.starting_share, 0.0, "nobody arrives a farmer")
	assert_true(def.helps_with.has("bush"), "a farmer also picks berries")
	assert_not_null(PersonMeshLibrary.accessory(def.accessory), "and carries a hoe")
	assert_eq(UIText.occupation_name(&"farmer"), "Farmer")
	# A new world opens in spring: one of the band has taken it up — one of
	# the trade with the most people, the one it suits best.
	var farmer := _farmer()
	assert_not_null(farmer, "the first farmer")
	assert_eq(farming.farmer_count(), 1)
	assert_eq(farming.plots_wanted(), config.plots_per_farmer)
	var cutters := 0
	var foragers := 0
	for p in session.people.all_people():
		cutters += 1 if p.occupation_id == &"woodcutter" else 0
		foragers += 1 if p.occupation_id == &"forager" else 0
	assert_eq(cutters, 2, "(there were three woodcutters)")
	assert_true(foragers >= 1, "and the others still have their people")
	for p in session.people.all_people():
		if p.occupation_id == &"woodcutter":
			assert_true(def.affinity(farmer.traits) >= def.affinity(p.traits), "the one of them it suits best")
	assert_eq(ctx.stage_of(farmer), PersonData.LifeStage.ADULT)
	# Once is enough.
	assert_null(session.settlement.ensure_farmer(session.clock.tick))
	assert_eq(farming.farmer_count(), 1)
	# Not in winter: there is nothing to sow.
	farmer.occupation_id = &"woodcutter"
	assert_null(session.settlement.ensure_farmer(_winter_tick()))
	# In a season for it, by itself as time passes (a world from before there were farmers).
	var taken: Array = []
	session.settlement.took_up.connect(func(id: int, occupation: StringName) -> void: taken.append([id, occupation]))
	session.clock.tick = 100
	session.settlement.step(session.clock.tick + Settlement.FARMER_CHECK_MINUTES)
	assert_eq(taken, [[farmer.id, &"farmer"]], "the same one again")
	assert_eq(farming.farmer_count(), 1)
	# Too few to spare keeps to what it does: the others in food trades (never
	# taken from), two left in others — not enough.
	farmer.occupation_id = &"woodcutter"
	var kept := 0
	for p in session.people.all_people():
		if p.occupation_id == &"woodcutter" or p.occupation_id == &"forager" or p.occupation_id == &"builder":
			kept += 1
			if kept > 2:
				p.occupation_id = &"hunter"
	assert_null(session.settlement.ensure_farmer(session.clock.tick), "two who could be spared are not enough")
	# (From anywhere: a builder, a toolmaker as much as a gatherer — the owner, 2026-10-07.)
	kept = 0
	for p in session.people.all_people():
		if p.occupation_id == &"hunter" and ctx.stage_of(p) == PersonData.LifeStage.ADULT:
			kept += 1
			if kept <= 2:
				p.occupation_id = &"toolmaker" if kept == 1 else &"builder"
	var from_trade := session.settlement.ensure_farmer(session.clock.tick)
	assert_not_null(from_trade, "now enough, from other trades")
	assert_eq(from_trade.occupation_id, &"farmer")


func test_more_farmers_as_the_settlement_grows() -> void:
	# (One farmer, whatever the size of the village, was why food ran short:
	# one more for every so many people.)
	var own := session.settlement
	var farmer := _farmer()
	assert_not_null(farmer)
	assert_eq(own.farmers_wanted(), clampi(own.member_count() / Settlement.FARMERS_PER_PEOPLE, 1, Settlement.FARMERS_MOST))
	# A bigger settlement: newcomers, gatherers all.
	for i in Settlement.FARMERS_PER_PEOPLE * 2:
		session.spawn_person(own.fire().tile)
	var wanted: int = own.farmers_wanted()
	assert_true(wanted >= 2, "more people, more farmers wanted (%d people)" % own.member_count())
	var taken := 0
	while own.ensure_farmer(_winter_tick()) != null and taken < 10:
		taken += 1
	assert_eq(farming.farmer_count(), wanted, "taken up — in any season, once there is a first")
	assert_null(own.ensure_farmer(session.clock.tick), "and no more")
	assert_eq(farming.plots_wanted(), wanted * config.plots_per_farmer, "a field for each")


# --- plots ----------------------------------------------------------------------------------------

func test_plots_are_tilled_beside_each_other_near_the_settlement() -> void:
	var home := session.start.settlement_tile
	assert_eq(farming.plot_count(), 0)
	var firsts: Array = []
	farming.first_field.connect(func(tile: Vector2i) -> void: firsts.append(tile))
	var sown: Array = []
	farming.sown.connect(func(id: int) -> void: sown.append(id))
	var first: Vector2i = farming.next_plot()
	assert_true(farming.suitable(first))
	var distance := Vector2(first - home).length()
	assert_true(distance >= config.site_min_distance and distance <= config.site_max_distance, "near, not on top of the fire (%.1f)" % distance)
	assert_eq(session.world.get_water(first), 0.0)
	assert_false(session.props.has_prop_at(first))
	var before := session.world.get_terrain(first)
	assert_true(before == ChunkData.Terrain.GRASS or before == ChunkData.Terrain.DIRT)
	# Sown: tilled ground with seed in it.
	var crop := farming.sow(first, session.clock.tick)
	assert_not_null(crop)
	assert_eq(session.world.get_terrain(first), ChunkData.Terrain.FARMLAND)
	assert_eq(crop.kind, PropData.Kind.CROP)
	assert_eq(session.props.prop_at(first), crop)
	assert_eq(Farming.stage_of(crop), Farming.Stage.SOWN)
	assert_eq([crop.growth, crop.vigor, crop.stock], [0, 1000, -1])
	assert_false(crop.is_generated())
	assert_eq(firsts, [first], "the first field of the world")
	assert_eq(sown, [crop.id])
	assert_true(session.pathfinder.can_stand(first), "people walk through their fields")
	assert_eq(session.nodes.available(crop), 0, "nothing to reap yet")
	# More plots lie beside those there are.
	for i in 6:
		var next: Vector2i = farming.next_plot()
		var beside := false
		for other in farming.crops():
			if absi(other.tile.x - next.x) + absi(other.tile.y - next.y) == 1:
				beside = true
		assert_true(beside, "plot %d lies beside the field" % (i + 2))
		assert_not_null(farming.sow(next, session.clock.tick))
	assert_eq(farming.plot_count(), 7)
	assert_eq(firsts.size(), 1)
	# Where a plot cannot be.
	assert_null(farming.sow(first, session.clock.tick), "sown already")
	assert_false(farming.suitable(home), "not on the fire")
	var hut := session.props.get_prop(session.start.hut_ids[0])
	assert_false(farming.suitable(hut.tile + Vector2i(1, 0)), "not at a hut's door")
	assert_false(farming.suitable(home + Vector2i(config.site_max_distance + 3, 0)), "not far off")
	assert_false(farming.suitable(Vector2i(100000, 0)), "not outside the box")
	for prop in session.props.all_props():
		if prop.kind == PropData.Kind.TREE and Vector2(prop.tile - home).length() <= config.site_max_distance:
			assert_false(farming.suitable(prop.tile), "not where a tree stands")
			assert_null(farming.sow(prop.tile, session.clock.tick))
			break


# --- growth -----------------------------------------------------------------------------------------

func test_production_crops() -> void:
	_knob(&"grow_days", 8.0) # (the days this test counts in)
	_still_soil()
	var ripened: Array = []
	var failed: Array = []
	farming.ripened.connect(func(id: int) -> void: ripened.append(id))
	farming.failed.connect(func(id: int) -> void: failed.append(id))
	var chunks: Array = []
	session.props.chunk_changed.connect(func(coord: Vector2i) -> void: chunks.append(coord))
	# Moist, fertile soil in spring: through the stages to ripe grain.
	session.clock.tick = 0
	var crop := _plot(200, 200)
	var tile := crop.tile
	var seen: Array = [Farming.stage_of(crop)]
	var hours := 0
	chunks.clear()
	while Farming.stage_of(crop) != Farming.Stage.RIPE and hours < 24 * 30:
		_grow(1)
		hours += 1
		if Farming.stage_of(crop) != seen[-1]:
			seen.append(Farming.stage_of(crop))
	assert_eq(seen, [Farming.Stage.SOWN, Farming.Stage.SPROUT, Farming.Stage.GROWING, Farming.Stage.RIPE], "planted, sprout, growing, ripe")
	var days := hours / 24.0
	var expected := config.grow_days / (Farming.fertility_factor(200) * (1.0 + config.tend_bonus * (1.0 / days)))
	assert_true(days > config.grow_days * 0.7 and days < config.grow_days * 1.1, "in about %.0f days (%.1f; %.1f untended)" % [config.grow_days, days, expected])
	assert_eq(crop.growth, 1000)
	assert_eq(crop.vigor, 1000, "never thirsty")
	assert_eq(ripened, [crop.id])
	assert_eq(chunks.size(), 3, "drawn anew at each stage")
	# What it bears, and what that cost the soil.
	assert_eq(crop.stock, roundi(config.yield_units * Farming.fertility_factor(200)))
	assert_eq(session.nodes.resource_of(crop), &"grain")
	assert_eq(session.nodes.available(crop), crop.stock)
	assert_eq(farming.fertility(tile), 200 - config.fertility_cost)
	# Ripe grain waits to be reaped.
	_grow(48)
	assert_eq(Farming.stage_of(crop), Farming.Stage.RIPE)
	# Reaped: the grain is taken like berries off a bush; with the last of it the plot is stubble.
	var bore := crop.stock
	assert_eq(session.nodes.take(crop.id, 2, session.clock.tick), 2)
	assert_eq(Farming.stage_of(crop), Farming.Stage.RIPE)
	assert_eq(session.nodes.take(crop.id, 100, session.clock.tick), bore - 2)
	assert_eq(Farming.stage_of(crop), Farming.Stage.STUBBLE)
	assert_eq(crop.stock, -1)
	assert_eq(session.nodes.available(crop), 0)
	assert_eq(session.nodes.take(crop.id, 1, session.clock.tick), 0)
	# --- Dry soil: it stands still, wilts, and fails.
	var dry := _plot(config.wilt_below - 30, 200)
	chunks.clear()
	_grow(12)
	assert_eq(dry.growth, 0, "nothing grows in dry soil")
	assert_true(dry.vigor < 1000 and dry.vigor > 700, "it suffers (%d)" % dry.vigor)
	assert_false(Farming.looks_dry(dry), "(seed in the ground shows nothing)")
	_grow(int(config.wilt_days * 24.0))
	assert_eq(Farming.stage_of(dry), Farming.Stage.FAILED, "dead after %s dry days" % config.wilt_days)
	assert_eq(failed, [dry.id])
	assert_eq(dry.vigor, 0)
	assert_true(chunks.size() >= 1, "and seen to be")
	assert_eq(session.nodes.available(dry), 0)
	_grow(48)
	assert_eq(Farming.stage_of(dry), Farming.Stage.FAILED, "dead is dead")
	# --- A crop that goes dry half grown is seen wilting — and saved by water.
	session.clock.tick = Config.time.ticks_per_year() # (spring again)
	farming.last_settle_tick = -1000000
	var thirsty := _plot(200, 200)
	_grow(4 * 24)
	assert_eq(Farming.stage_of(thirsty), Farming.Stage.GROWING)
	_soil(thirsty.tile, config.wilt_below - 20)
	var grown := thirsty.growth
	chunks.clear()
	_grow(int(config.wilt_days * 24.0 * 0.6))
	assert_eq(thirsty.growth, grown, "it stands still")
	assert_true(Farming.looks_dry(thirsty), "brown and hanging (vigour %d)" % thirsty.vigor)
	assert_eq(Farming.shown_variant(thirsty), Farming.Stage.GROWING + Farming.DRY_VARIANT)
	assert_eq(chunks.size(), 1, "drawn anew when it wilts")
	_soil(thirsty.tile, 220) # (the player pours water on it; rain comes)
	_grow(int(config.recover_days * 24.0))
	assert_false(Farming.looks_dry(thirsty), "it has picked up")
	assert_true(thirsty.growth > grown, "and grows again")
	assert_eq(failed.size(), 1)
	# One that ripens after a bad time bears less.
	thirsty.variant = Farming.Stage.GROWING
	thirsty.stock = -1
	thirsty.vigor = 300
	thirsty.growth = 990
	_grow(6)
	assert_eq(Farming.stage_of(thirsty), Farming.Stage.RIPE)
	assert_true(thirsty.stock < bore, "a poor crop (%d against %d)" % [thirsty.stock, bore])
	assert_true(Farming.looks_dry(thirsty))


func test_growth_follows_soil_and_season() -> void:
	_still_soil()
	session.clock.tick = 0
	# Moisture: nothing below the wilting point, full growth from "good", in between by degree.
	assert_eq(Farming.moisture_factor(config.wilt_below - 1), 0.0)
	assert_eq(Farming.moisture_factor(config.wilt_below), 0.0)
	assert_eq(Farming.moisture_factor(config.good_from), 1.0)
	assert_eq(Farming.moisture_factor(255), 1.0)
	assert_near(Farming.moisture_factor((config.wilt_below + config.good_from) / 2), 0.5, 0.02)
	# Fertility: poor soil grows slowly.
	assert_true(Farming.fertility_factor(40) < Farming.fertility_factor(200))
	assert_near(Farming.fertility_factor(255), 1.2, 0.001)
	var rich := _plot(200, 220)
	var poor := _plot(200, 40)
	var damp := _plot((config.wilt_below + config.good_from) / 2, 220)
	rich.tended_tick = -100000
	poor.tended_tick = -100000
	damp.tended_tick = -100000
	_grow(72)
	assert_true(rich.growth > poor.growth * 1.6, "rich soil grows faster (%d against %d)" % [rich.growth, poor.growth])
	assert_near(float(damp.growth) / rich.growth, 0.5, 0.08, "half as fast in half-dry soil")
	assert_eq(damp.vigor, 1000, "but it does not suffer")
	# Tended grain grows faster.
	var tended := _plot(200, 220)
	var left_alone := _plot(200, 220)
	left_alone.tended_tick = -100000
	for hour in 20:
		_grow(1)
	assert_near(float(tended.growth) / left_alone.growth, 1.0 + config.tend_bonus, 0.06)
	assert_true(farming.finish(Farming.TEND, left_alone.tile, left_alone.id, session.clock.tick))
	assert_eq(left_alone.tended_tick, session.clock.tick)
	# The seasons: full growth in spring and summer, slower in autumn, none in winter.
	assert_eq(config.season_factor(0), 1.0)
	assert_eq(config.season_factor(3), 0.0)
	assert_eq(config.season_factor(9), 0.0)
	var per_season: Array = []
	for season in 4:
		session.clock.tick = season * Config.time.days_per_season * 1440 + 60
		var crop := _plot(200, 220)
		_grow(48)
		per_season.append(crop.growth)
	assert_near(float(per_season[1]) / per_season[0], 1.0, 0.03, "summer as spring")
	assert_near(float(per_season[2]) / per_season[0], config.season_growth[2], 0.05, "autumn slower")
	assert_eq(per_season[3], 0, "nothing in winter")
	# Sowing is for spring — while what is sown can still ripen before winter.
	assert_true(farming.sowing_time(0))
	assert_true(farming.ripens_before_winter(0))
	assert_true(farming.growing_days_left(0) > farming.growing_days_left(4 * 1440))
	assert_false(farming.sowing_time(Config.time.days_per_season * 1440 + 5), "summer: too late for this year")
	assert_false(farming.sowing_time(2 * Config.time.days_per_season * 1440 + 5))
	assert_false(farming.sowing_time(3 * Config.time.days_per_season * 1440 + 5))
	assert_near(farming.growing_days_left(3 * Config.time.days_per_season * 1440 + 5), 0.0, 0.001, "winter")
	# Grain that ripens quickly can be sown later.
	_knob(&"grow_days", 4.0)
	assert_true(farming.sowing_time(Config.time.days_per_season * 1440 + 5))
	assert_false(farming.sowing_time(3 * Config.time.days_per_season * 1440 + 5), "but never in winter")
	assert_false(farming.sowing_time(_winter_tick()))
	assert_true(farming.sowing_time(Config.time.ticks_per_year() + 5), "and spring again")


func test_the_soil_has_its_days() -> void:
	# Rain (a placeholder for the weather): the same on the same day in the same world, about as often as said.
	assert_eq(farming.rain_on(5), farming.rain_on(5))
	var per_season := [0, 0, 0, 0]
	var years := 60
	for day in years * Config.time.days_per_year():
		if farming.rain_on(day):
			per_season[(day / Config.time.days_per_season) % 4] += 1
	for season in 4:
		var share := float(per_season[season]) / (years * Config.time.days_per_season)
		assert_near(share, config.rain_chance[season], 0.07, "season %d rains on %.2f of days" % [season, share])
	var other: WorldSession = SessionScript.new()
	add_child(other)
	other.create_new(777)
	other.set_process(false)
	var differs := 0
	for day in 60:
		differs += 1 if other.farming.rain_on(day) != farming.rain_on(day) else 0
	assert_true(differs > 10, "another world has other weather (%d of 60 days)" % differs)
	other.queue_free()
	# A day without rain: the soil dries, and a growing crop drinks.
	_knob(&"rain_moisture", 0)
	_knob(&"seep_share", 0.0)
	session.clock.tick = 0
	var crop := _plot(180, 200)
	var fallow := _plot(180, 200)
	farming.reaped(fallow, session.clock.tick) # (an empty plot)
	farming.settle(0)
	session.clock.tick = 1440 * 1 + 5
	farming.settle(session.clock.tick)
	assert_eq(farming.soil(crop.tile), 180 - config.evaporation_per_day - config.crop_draw_per_day)
	assert_eq(farming.soil(fallow.tile), 180 - config.evaporation_per_day, "nothing drinks from an empty plot")
	assert_eq(farming.fertility(fallow.tile), 200 + config.fallow_gain_per_day, "and it rests")
	assert_eq(farming.fertility(crop.tile), 200)
	# Days missed are made up.
	session.clock.tick += 1440 * 3
	farming.settle(session.clock.tick)
	assert_eq(farming.soil(fallow.tile), 180 - config.evaporation_per_day * 4)
	# Rain gives it back.
	_knob(&"rain_moisture", 60)
	_knob(&"rain_chance", PackedFloat32Array([1.0, 1.0, 1.0, 1.0]))
	var before := farming.soil(fallow.tile)
	session.clock.tick += 1440
	farming.settle(session.clock.tick)
	assert_eq(farming.soil(fallow.tile), before + 60 - config.evaporation_per_day)
	# Ground water: dry soil comes back towards what the land holds by itself.
	_knob(&"rain_chance", PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))
	_knob(&"seep_share", 0.25)
	var base := int(session.generator.sample_tile(fallow.tile)["moisture"])
	_soil(fallow.tile, 20)
	session.clock.tick += 1440
	farming.settle(session.clock.tick)
	var after := maxi(20 - config.evaporation_per_day, 0)
	assert_eq(farming.soil(fallow.tile), after + ceili((base - after) * 0.25) if base > after else after, "a quarter of the way back (the land there holds %d)" % base)
	# Water standing beside a plot keeps it wet.
	_soil(crop.tile, 40)
	session.world.set_water(crop.tile + Vector2i(1, 0), 0.3)
	session.clock.tick += 1440
	farming.settle(session.clock.tick)
	assert_true(farming.soil(crop.tile) >= Farming.WET_SOIL)
	# The day it is at is saved (no day twice).
	var again := Farming.new()
	again.from_dict(bytes_to_var(var_to_bytes(farming.to_dict())))
	assert_eq(again.to_dict(), farming.to_dict())


# --- the farmer's work ------------------------------------------------------------------------------

func test_the_field_tells_the_farmer_what_it_needs() -> void:
	_still_soil()
	session.clock.tick = 300
	var farmer := _calm(_farmer())
	var now := session.clock.tick
	session.settlement.stockpile.add(&"berries", 60) # (nothing else on the board for a farmer)
	session.settlement.jobs.refresh(session.settlement, now)
	# Nothing there yet, spring: a plot to make.
	var task := farming.task_for(farmer, now)
	assert_eq(task["task"], Farming.SOW)
	assert_eq(task["id"], 0)
	assert_eq(task["tile"], farming.next_plot())
	assert_near(farming.pressing(now), 0.7, 0.001)
	# The plan: to the plot, till and sow.
	var steps := Planner.plan(&"work", farmer, ctx)
	assert_eq(steps.size(), 2)
	assert_eq([steps[0]["type"], steps[1]["type"]], ["walk_to", "work"])
	assert_eq(steps[1]["kind"], "field")
	assert_eq(steps[1]["task"], "sow")
	assert_eq(steps[1]["minutes"], config.sow_minutes)
	assert_eq(steps[0]["target"], task["tile"])
	# All the plots a farmer keeps: then there is only tending, when it is due.
	while farming.plot_count() < farming.plots_wanted():
		farming.sow(farming.next_plot(), now)
	assert_eq(farming.task_for(farmer, now), {}, "sown and tended today")
	assert_eq(farming.pressing(now), 0.0)
	now += config.tend_every_minutes
	task = farming.task_for(farmer, now)
	assert_eq(task["task"], Farming.TEND)
	assert_near(farming.pressing(now), 0.4, 0.001)
	# A failed crop is cleared before anything is tended; ripe grain comes before everything.
	var crops := farming.crops()
	crops[2].variant = Farming.Stage.FAILED
	assert_eq(farming.task_for(farmer, now), {"task": Farming.CLEAR, "tile": crops[2].tile, "id": crops[2].id})
	crops[5].variant = Farming.Stage.RIPE
	crops[5].stock = 6
	assert_eq(farming.task_for(farmer, now), {"task": Farming.HARVEST, "tile": crops[5].tile, "id": crops[5].id})
	assert_near(farming.pressing(now), 0.9, 0.001)
	session.clock.tick = now
	session.settlement.jobs.refresh(session.settlement, now)
	var reaping := Planner.plan(&"work", farmer, ctx)
	assert_eq(reaping.size(), 4, "to the plot, reap, to the stores, put it down")
	assert_true(bool(reaping[1]["gather"]))
	assert_false(reaping[1].has("task"))
	assert_eq(reaping[1]["target"], crops[5].id)
	assert_eq(reaping[2]["target"], ctx.places.storage_tile(&"grain"))
	# Clearing leaves a plot that can be sown again after it has rested.
	crops[5].variant = Farming.Stage.GROWING
	crops[5].stock = -1
	assert_true(farming.finish(Farming.CLEAR, crops[2].tile, crops[2].id, now))
	assert_eq(Farming.stage_of(crops[2]), Farming.Stage.STUBBLE)
	assert_ne(farming.task_for(farmer, now).get("task"), Farming.SOW, "not the same day")
	var later := now + roundi(config.fallow_days * 1440)
	for crop in crops:
		crop.tended_tick = later
	assert_eq(farming.task_for(farmer, later), {"task": Farming.SOW, "tile": crops[2].tile, "id": crops[2].id})
	assert_true(farming.finish(Farming.SOW, crops[2].tile, crops[2].id, later))
	assert_eq(Farming.stage_of(crops[2]), Farming.Stage.SOWN)
	# In winter nothing is sown: stubble lies until spring.
	farming.reaped(crops[3], later)
	var winter := _winter_tick()
	for crop in crops:
		crop.tended_tick = winter
	assert_eq(farming.task_for(farmer, winter), {})
	# What cannot be done is not done.
	assert_false(farming.finish(Farming.TEND, crops[3].tile, crops[3].id, later), "nothing grows there")
	assert_false(farming.finish(Farming.CLEAR, crops[0].tile, crops[0].id, later), "it has not failed")
	assert_false(farming.finish(Farming.TEND, Vector2i.ZERO, 987654, later))


func test_the_board_calls_the_farmer_to_the_field() -> void:
	Config.settlement.fire_wood_per_day = 6.0
	session.clock.tick = 300
	var board := session.settlement.jobs
	var farmer := _calm(_farmer())
	var def := session.occupations.get_def(&"farmer")
	board.refresh(session.settlement, session.clock.tick)
	var farm: JobBoard.Job = null
	for job in board.jobs():
		if job.kind == JobBoard.FARM:
			farm = job
	assert_not_null(farm, "the field is on the board")
	assert_eq(farm.node, &"field")
	assert_near(farm.priority, 0.7, 0.001, "there is sowing to do")
	# It is the farmer's alone; the farmer also picks berries, at less weight.
	assert_eq(board.affinity(farm, &"field"), 1.0)
	assert_eq(board.affinity(farm, &"tree"), 0.0)
	assert_eq(board.affinity(farm, &"bush"), 0.0)
	farm.priority = 1.0
	assert_eq(board.affinity(farm, &"tree"), 0.0, "however pressing")
	farm.priority = 0.7
	var berries := board.job_for(&"berries")
	assert_eq(board.affinity(berries, &"field", def.helps_with), Config.settlement.other_trade_factor)
	assert_eq(board.affinity(berries, &"field"), 0.0, "(by itself the field trade is no berry picker)")
	assert_eq(board.affinity(board.job_for(&"wood"), &"field", def.helps_with), 0.0)
	var kinds := {}
	for i in 200:
		var steps := Planner.plan(&"work", farmer, ctx)
		kinds[steps[1]["kind"]] = int(kinds.get(steps[1]["kind"], 0)) + 1
	assert_true(int(kinds.get("field", 0)) > 120, "mostly the field (%s)" % [kinds])
	assert_true(int(kinds.get("bush", 0)) > 15, "sometimes berries")
	assert_false(kinds.has("tree"))
	# The field needs nothing: no job for it, and the farmer goes picking.
	while farming.plot_count() < farming.plots_wanted():
		farming.sow(farming.next_plot(), session.clock.tick)
	board.refresh(session.settlement, session.clock.tick)
	for job in board.jobs():
		assert_ne(job.kind, JobBoard.FARM)
	for i in 30:
		assert_eq(Planner.plan(&"work", farmer, ctx)[1]["kind"], "bush")
	assert_true(board.work_factor(&"field", def.helps_with) > Config.settlement.work_without_jobs, "which is work too")
	# Nobody farms: nothing about the field is posted.
	farmer.occupation_id = &"woodcutter"
	for crop in farming.crops():
		crop.tended_tick = -100000
	board.refresh(session.settlement, session.clock.tick)
	for job in board.jobs():
		assert_ne(job.kind, JobBoard.FARM)
	assert_eq(farming.plots_wanted(), 0)


func test_a_farmer_sows_tends_and_reaps() -> void:
	_still_soil()
	Config.settlement.fire_wood_per_day = 0.01
	session.clock.tick = 120
	var farmer := _calm(_farmer())
	_only([farmer])
	session.settlement.stockpile.add(&"berries", 60) # (so that the farmer need not go picking)
	session.settlement.jobs.refresh(session.settlement, session.clock.tick)
	# Sowing: to the plot, forty minutes of work, and it is a field.
	session.day_log.forget(farmer.id)
	behavior.set_plan(farmer, &"work", &"purpose", Planner.plan(&"work", farmer, ctx), 2.0)
	assert_eq(DayLogText.text(session.day_log.of(farmer.id)[-1]), "works in the field")
	var waited := 0.0
	while farming.plot_count() == 0 and waited < 180.0:
		_run(1.0)
		waited += 1.0
	assert_eq(farming.plot_count(), 1, "the first plot, after %d minutes" % waited)
	var first := farming.crops()[0]
	assert_true(farmer.world2d().distance_to(Places.middle_of(first.tile)) < 1.2, "they stood on it to do it")
	assert_true(waited >= config.sow_minutes)
	# Left to it for the rest of the day, the farmer makes more.
	farmer.needs = PackedFloat32Array([0.95, 0.95, 0.95, 0.9, 0.3, 1.0])
	_run(360.0)
	assert_true(farming.plot_count() >= 4, "a field takes shape (%d plots)" % farming.plot_count())
	assert_true(farming.plot_count() <= farming.plots_wanted())
	# Ripe grain is reaped and carried to the stores.
	var crop := farming.crops()[0]
	_soil(crop.tile, 200, 200)
	crop.growth = 995
	crop.variant = Farming.Stage.GROWING
	crop.stock_tick = session.clock.tick
	farming.last_settle_tick = -1000000
	session.clock.tick += 120
	farming.settle(session.clock.tick)
	assert_eq(Farming.stage_of(crop), Farming.Stage.RIPE)
	var bears := crop.stock
	assert_true(bears >= 4)
	_calm(farmer)
	farmer.carrying = &""
	farmer.carrying_amount = 0
	session.settlement.jobs.refresh(session.settlement, session.clock.tick)
	behavior.set_plan(farmer, &"work", &"purpose", Planner.plan(&"work", farmer, ctx), 2.0)
	assert_eq(BehaviorSystem.current_step(farmer).get("type"), "walk_to")
	waited = 0.0
	var armful := ctx.carry_capacity(&"grain")
	while session.stored(&"grain") < mini(bears, armful) and waited < 240.0:
		_run(1.0)
		waited += 1.0
	# (A plot bears more than an armful: back for the rest — the next working day.)
	waited = 0.0
	while session.stored(&"grain") < bears and waited < 600.0:
		if farmer.current_action.get("activity", "") != "work":
			_calm(farmer)
			behavior.set_plan(farmer, &"work", &"purpose", Planner.plan(&"work", farmer, ctx), 2.0)
		_run(1.0)
		waited += 1.0
	assert_eq(session.stored(&"grain"), bears, "the harvest is in the stores")
	assert_eq(Farming.stage_of(crop), Farming.Stage.STUBBLE, "and the plot is stubble")
	assert_eq(session.piles.piles(&"grain").size(), 1)
	assert_true(session.piles.piles(&"grain")[0].position.distance_to(session.storage_place(&"grain")) < 0.7, "with the food")
	assert_true(session.settlement.stockpile.food() >= bears * 1.0, "and it is food")


# --- seen -------------------------------------------------------------------------------------------

func test_crops_are_drawn_by_their_stage() -> void:
	var library := PropMeshLibrary.new()
	var heights: Array = []
	for stage in Farming.Stage.size():
		var template := library.template_for(PropData.Kind.CROP, stage)
		assert_not_null(template, Farming.Stage.keys()[stage])
		var top := 0.0
		for v in template.vertices:
			top = maxf(top, v.y)
		heights.append(top)
		var across := 0.0
		for v in template.vertices:
			across = maxf(across, maxf(absf(v.x), absf(v.z)))
		assert_true(across <= 0.5, "%s stays on its tile (%.2f)" % [Farming.Stage.keys()[stage], across])
	assert_true(heights[Farming.Stage.SOWN] < heights[Farming.Stage.SPROUT], "bare earth, then sprouts")
	assert_true(heights[Farming.Stage.SPROUT] < heights[Farming.Stage.GROWING] and heights[Farming.Stage.GROWING] < heights[Farming.Stage.RIPE], "taller as it grows")
	assert_true(heights[Farming.Stage.STUBBLE] < heights[Farming.Stage.SPROUT], "stubble is short")
	var has_colour := func(template: PropMeshLibrary.Template, colour: Color) -> bool:
		for c in template.colors:
			if absf(c.r - colour.r) < 0.02 and absf(c.g - colour.g) < 0.02 and absf(c.b - colour.b) < 0.02:
				return true
		return false
	assert_true(has_colour.call(library.template_for(PropData.Kind.CROP, Farming.Stage.GROWING), PropMeshLibrary.CROP_GREEN), "green")
	assert_true(has_colour.call(library.template_for(PropData.Kind.CROP, Farming.Stage.RIPE), PropMeshLibrary.CROP_GOLD), "golden when ripe")
	assert_true(has_colour.call(library.template_for(PropData.Kind.CROP, Farming.Stage.FAILED), PropMeshLibrary.CROP_DEAD), "brown when it has failed")
	var wilting := library.template_for(PropData.Kind.CROP, Farming.Stage.GROWING + Farming.DRY_VARIANT)
	assert_ne(wilting, library.template_for(PropData.Kind.CROP, Farming.Stage.GROWING))
	assert_true(has_colour.call(wilting, PropMeshLibrary.CROP_DRY), "brown crops")
	assert_false(has_colour.call(wilting, PropMeshLibrary.CROP_GREEN))
	# In the chunk's mesh: the plot's plants are there, and change with the crop.
	_still_soil()
	session.clock.tick = 0
	var crop := _plot(200, 200)
	var coord := WorldCoords.tile_to_chunk(crop.tile, session.world.chunk_size)
	var sown := PropMesher.build_buffers(session.world, session.props, coord, library, false).triangle_count()
	crop.growth = 600
	crop.variant = Farming.Stage.GROWING
	var growing := PropMesher.build_buffers(session.world, session.props, coord, library, false).triangle_count()
	assert_true(growing > sown + 50, "plants on it (%d → %d)" % [sown, growing])
	# What the player is told.
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = crop.id
	target.tile = crop.tile
	var report := session.interactions.inspect(target)
	assert_eq([report.crop_stage, report.crop_growth, report.crop_dry], [Farming.Stage.GROWING, 600, false])
	assert_eq(UIText.crop_name(report.crop_stage), "Growing grain")
	assert_eq(UIText.crop_state(report.crop_stage, report.crop_growth, report.crop_vigor, report.crop_dry), "60% grown")
	assert_eq(UIText.crop_state(Farming.Stage.GROWING, 600, 400, true), "60% grown — wilting")
	assert_eq(UIText.crop_state(Farming.Stage.GROWING, 600, 800, false), "60% grown — thirsty")
	assert_eq(UIText.crop_state(Farming.Stage.RIPE, 1000, 1000, false), "Ready to reap")
	assert_eq(UIText.crop_state(Farming.Stage.FAILED, 300, 0, false), "Dried out")
	assert_eq(UIText.crop_state(Farming.Stage.STUBBLE, 0, 1000, false), "Resting")
	for stage in Farming.Stage.size():
		assert_ne(UIText.crop_name(stage), "Field", Farming.Stage.keys()[stage])
	assert_eq(UIText.prop_name(PropData.Kind.CROP), "Field")
	assert_eq(String(TranslationServer.translate("HISTTHING_CROP")), "a field")
	# A touch on it is a touch on a field.
	var response := session.interactions.tap(target)
	assert_eq(InteractionManager.subject_of(response), &"crop")
	assert_has(farming.debug_text(session.clock.tick), "fields: 1 of %d plots" % farming.plots_wanted())


# --- over a year --------------------------------------------------------------------------------------

func test_a_year_of_farming() -> void:
	session.clock.tick = 0
	var first_fields: Array = []
	var ripened := [0]
	var failed := [0]
	farming.first_field.connect(func(tile: Vector2i) -> void: first_fields.append(tile))
	farming.ripened.connect(func(_id: int) -> void: ripened[0] += 1)
	farming.failed.connect(func(_id: int) -> void: failed[0] += 1)
	var grain_in := [0]
	session.piles.stored.connect(func(resource: StringName, amount: int, _pile: int) -> void:
		if resource == &"grain":
			grain_in[0] += amount)
	var hungriest := 1.0
	var plots_by_season: Array = []
	var worn := 0
	var ripe_in_season := [0, 0, 0, 0]
	farming.ripened.connect(func(_id: int) -> void: ripe_in_season[Config.time.season_of(session.clock.tick)] += 1)
	var year_days := Config.time.days_per_year()
	for day in year_days:
		for part in 4:
			_run(360.0)
			for p in session.people.all_people():
				hungriest = minf(hungriest, Needs.value(p.needs, Needs.Need.HUNGER))
		if (day + 1) % Config.time.days_per_season == 0:
			plots_by_season.append("%d plots, %d grain in store" % [farming.plot_count(), session.stored(&"grain")])
		# The ground that has just borne grain is the poorer for it (it rests over winter).
		if day == 2 * Config.time.days_per_season + 2:
			for crop in farming.crops():
				worn += 1 if farming.fertility(crop.tile) < int(session.generator.sample_tile(crop.tile)["fertility"]) else 0
	var rain_days := 0
	for day in year_days:
		rain_days += 1 if farming.rain_on(day) else 0
	print("    a year: %s; %d crops ripened, %d failed, %d grain brought in; %d rainy days of %d; hungriest moment %.2f; %s" % [
		plots_by_season, ripened[0], failed[0], grain_in[0], rain_days, year_days, hungriest, farming.debug_text(session.clock.tick)])
	assert_eq(first_fields.size(), 1, "the first field was made")
	assert_true(farming.plot_count() >= 4 and farming.plot_count() <= farming.plots_wanted(), "a field of %d plots" % farming.plot_count())
	assert_true(ripened[0] + failed[0] >= farming.plot_count(), "every plot came to something (%d ripe, %d failed)" % [ripened[0], failed[0]])
	assert_true(ripened[0] >= 3, "grain ripened (%d)" % ripened[0])
	assert_true(grain_in[0] >= 12, "and was brought in (%d)" % grain_in[0])
	assert_true(hungriest > 0.05, "nobody starved (%.2f)" % hungriest)
	assert_true(session.settlement.fire_lit())
	assert_true(worn >= 3, "fertility was taken out (%d plots)" % worn)
	# One sowing in spring, one harvest: at the end of summer and in autumn.
	assert_eq(ripe_in_season[0] + ripe_in_season[3], 0, "none in spring, none in winter (%s)" % str(ripe_in_season))
	assert_true(ripe_in_season[1] + ripe_in_season[2] >= 3)
	for crop in farming.crops():
		assert_eq(Farming.stage_of(crop), Farming.Stage.STUBBLE, "the field lies bare over winter")
	# It all survives a save: plots, stages, soil.
	var data: Dictionary = bytes_to_var(var_to_bytes(session.to_dict()))
	var loaded: WorldSession = SessionScript.new()
	add_child(loaded)
	assert_true(loaded.load_from(data))
	loaded.set_process(false)
	assert_eq(loaded.farming.plot_count(), farming.plot_count())
	assert_eq(loaded.farming.to_dict(), farming.to_dict())
	for crop in farming.crops():
		var again := loaded.props.get_prop(crop.id)
		assert_not_null(again)
		assert_eq([again.kind, again.variant, again.growth, again.vigor, again.stock, again.stock_tick, again.tended_tick],
			[crop.kind, crop.variant, crop.growth, crop.vigor, crop.stock, crop.stock_tick, crop.tended_tick])
		assert_eq(loaded.world.get_terrain(crop.tile), ChunkData.Terrain.FARMLAND)
		assert_eq(loaded.farming.soil(crop.tile), farming.soil(crop.tile))
		assert_eq(loaded.farming.fertility(crop.tile), farming.fertility(crop.tile))
	assert_eq(loaded.farming.farmer_count(), 1)
	loaded.queue_free()


func test_version_10_save_gains_fields() -> void:
	# Written by M7.2 (8cc344f): a morning lived; nobody farmed, nothing was tilled.
	assert_true(FileAccess.file_exists(V10_FIXTURE), "fixture present")
	var dir := SaveManager.world_dir(V10_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V10_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 10)
	var loaded := SaveManager.load_world(V10_ID)
	assert_true(loaded.ok, loaded.error)
	assert_eq(loaded.world["world_state"]["farming"], {})
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	s.loose_system.set_process(false)
	s.water.set_process(false)
	assert_eq(s.farming.plot_count(), 0)
	assert_eq(s.farming.farmer_count(), 0, "as it was saved")
	assert_eq(s.settlement.stockpile.amounts(), {&"berries": 31, &"wood": 12})
	# It is spring there: before long one of them farms, and there is a field.
	var taken: Array = []
	s.settlement.took_up.connect(func(id: int, occupation: StringName) -> void: taken.append(occupation))
	_run(900.0, 1.0, s)
	assert_true(taken.has(&"farmer"), str(taken))
	assert_eq(s.farming.farmer_count(), 1)
	assert_true(s.farming.plot_count() >= 1, "a first plot (%d)" % s.farming.plot_count())
	# Saved again: the current version, the old file kept; and read back the same.
	assert_true(SaveManager.save_world(s, &"test"))
	assert_true(SaveManager.SAVE_VERSION >= 11)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav.bak1")).header["save_version"], 10)
	var again := SaveManager.load_world(V10_ID)
	assert_true(again.ok, again.error)
	var s2: WorldSession = SessionScript.new()
	add_child(s2)
	assert_true(s2.load_from(again.world))
	s2.set_process(false)
	assert_eq(s2.farming.plot_count(), s.farming.plot_count())
	assert_eq(s2.farming.farmer_count(), 1)
	s.queue_free()
	s2.queue_free()
	# The step itself.
	assert_eq(SaveMigrations._v10_to_v11({"world": {"world_state": {}}})["world"]["world_state"], {})
	var kept: Dictionary = SaveMigrations._v10_to_v11({"world": {"world_state": {"people": {}, "farming": {"day": 4}}}})
	assert_eq(kept["world"]["world_state"]["farming"], {"day": 4})
