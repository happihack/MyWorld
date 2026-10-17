extends TestCase
## The blessings the player gives (the owner and Josh, 2026-10-16; the
## plan's BLESSINGS section): the other hand of the Presence. One at a time
## with the disasters and the one rest after either; the lights in the sky
## come and go, harm nobody, are noticed, written down, and kept with the
## world while they last.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440

var session: WorldSession
var blessings: BlessingSystem
var disasters: DisasterSystem
var clock: GameClock
var stimuli: Array[Stimulus] = []


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
	session.behavior.enabled = false
	blessings = session.blessings
	disasters = session.disasters
	clock = session.clock
	stimuli.clear()
	session.interactions.stimulus_emitted.connect(func(stimulus: Stimulus) -> void: stimuli.append(stimulus))


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


func _fire() -> Vector2:
	return session.settlement.fire().position2d()


## The clock moves on `minutes`, and both hands with it.
func _pass(minutes: int) -> void:
	clock.tick += minutes
	disasters.advance_to(clock.tick)
	blessings.advance_to(clock.tick)


func test_one_act_a_day_whichever_hand() -> void:
	assert_eq(BlessingSystem.KINDS.size(), 7, "the first cut, and the mirror completed: the rain and the herds")
	assert_true(bool(Settings.get_value(&"gameplay/gentle_hands")), "gentle hands are on")
	var iv := session.interactions.bless(BlessingSystem.LIGHTS, _fire())
	assert_true(iv.applied, "asked for and confirmed: not held back by gentle hands (%s)" % iv.rejected)
	assert_eq(iv.severity, Intervention.Severity.MAJOR)
	assert_eq(session.history.count(Intervention.BLESSING, BlessingSystem.LIGHTS), 1, "in the player's history")
	assert_true(blessings.is_active())
	# Neither hand while the other is busy.
	assert_false(session.interactions.bless(BlessingSystem.LIGHTS, _fire()).applied, "one at a time")
	var curse := session.interactions.disaster(DisasterSystem.ECLIPSE, _fire())
	assert_false(curse.applied, "no disaster while a blessing goes on")
	assert_eq(curse.rejected, &"resting")
	assert_false(disasters.can_start(clock.tick))
	assert_eq(disasters.rest_left(clock.tick), blessings.rest_left(clock.tick), "the one rest, seen from either button")
	_pass(int(BlessingSystem.LASTS[BlessingSystem.LIGHTS]))
	assert_false(blessings.is_active(), "over")
	assert_false(blessings.can_start(clock.tick), "the world rests")
	assert_false(disasters.can_start(clock.tick), "from a disaster too: the one rest")
	assert_eq(blessings.rest_left(clock.tick), BlessingSystem.REST_MINUTES)
	assert_eq(disasters.rest_left(clock.tick), DisasterSystem.REST_MINUTES)
	_pass(BlessingSystem.REST_MINUTES)
	assert_true(blessings.can_start(clock.tick), "a day later, either")
	assert_true(disasters.can_start(clock.tick))
	assert_false(session.interactions.bless(&"plague", _fire()).applied, "no such blessing")
	# And after a disaster, no blessing until the world has rested.
	assert_true(session.interactions.disaster(DisasterSystem.ECLIPSE, _fire()).applied)
	assert_false(session.interactions.bless(BlessingSystem.LIGHTS, _fire()).applied, "no blessing while a disaster goes on")
	_pass(int(DisasterSystem.LASTS[DisasterSystem.ECLIPSE]))
	assert_false(blessings.can_start(clock.tick), "the rest after a disaster holds the blessings too")
	_pass(DisasterSystem.REST_MINUTES)
	assert_true(blessings.can_start(clock.tick))


func test_the_lights_come_and_go_and_harm_nobody() -> void:
	var living := session.people.size()
	var trees := 0
	for prop in session.props.all_props():
		if prop.kind == PropData.Kind.TREE and not prop.felled:
			trees += 1
	assert_true(session.interactions.bless(BlessingSystem.LIGHTS, _fire()).applied)
	assert_eq(blessings.lights_amount(clock.tick), 0.0, "they come")
	_pass(35)
	assert_near(blessings.lights_amount(clock.tick), 1.0, 0.01, "the sky is full of them")
	assert_true(stimuli.any(func(s: Stimulus) -> bool: return s.type == Stimulus.LIGHTS_IN_SKY and s.anomalous and s.large),
		"noticed, everywhere")
	_pass(40)
	assert_eq(blessings.lights_amount(clock.tick), 0.0, "and go")
	assert_false(blessings.is_active())
	assert_eq(session.people.size(), living)
	var after := 0
	for prop in session.props.all_props():
		if prop.kind == PropData.Kind.TREE and not prop.felled:
			after += 1
	assert_eq(after, trees)
	assert_eq(session.events.of_type(&"lights_in_sky").size(), 1, "written down")


func test_kept_with_the_world_while_it_lasts() -> void:
	var before := SaveManager.save_world(session, &"test")
	assert_true(before)
	var pristine := SaveManager.last_save_info["bytes"] as int
	assert_true(session.interactions.bless(BlessingSystem.LIGHTS, _fire()).applied)
	_pass(10)
	assert_true(SaveManager.save_world(session, &"test"))
	assert_true(SaveManager.last_save_info["bytes"] > pristine, "a blessing going on is saved")
	var loaded := SaveManager.load_world(session.world_id)
	assert_true(loaded.ok, loaded.error)
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(loaded.world))
	again.set_process(false)
	assert_eq(again.blessings.kind, BlessingSystem.LIGHTS, "still going on")
	assert_eq(again.blessings.until, blessings.until)
	assert_false(again.disasters.can_start(again.clock.tick), "and the disasters know it")
	again.clock.tick = blessings.until
	again.blessings.advance_to(again.clock.tick)
	assert_false(again.blessings.is_active())
	assert_eq(again.disasters.rest_until, blessings.until + BlessingSystem.REST_MINUTES, "the one rest, kept by the disasters")
	# Once over, the save carries nothing of it.
	assert_true(SaveManager.save_world(again, &"test"))
	var state: Dictionary = again.to_dict()["world_state"]
	assert_false(state.has("blessings"), "nothing to save of a blessing that is over")
	again.queue_free()


func test_it_goes_on_while_away() -> void:
	assert_true(session.interactions.bless(BlessingSystem.LIGHTS, _fire()).applied)
	var until := blessings.until
	# The session's own step brings it up to the clock (as it does while the game runs).
	clock.tick = until + 5
	session.advance_systems()
	assert_false(blessings.is_active(), "over, by the clock")
	assert_eq(disasters.rest_until, until + BlessingSystem.REST_MINUTES)


# --- the land and the water (step 2) ---------------------------------------------------------------

func _bush_near(where: Vector2, within: float, beyond: float = 0.0) -> PropData:
	var best: PropData = null
	for prop in session.props.of_kind(PropData.Kind.BUSH):
		if prop.kind != PropData.Kind.BUSH:
			continue
		var d := prop.position2d().distance_to(where)
		if d <= within and d > beyond and (best == null or d < best.position2d().distance_to(where)):
			best = prop
	return best


func _fertility(tile: Vector2i) -> int:
	var chunk := session.world.chunk_at_tile(tile)
	return int(chunk.fertility[session.world.index_at_tile(tile)]) if chunk != null else 0


func test_the_bounty_fills_the_bushes_and_they_grow_back_faster_for_a_season() -> void:
	var fire := _fire()
	var near := _bush_near(fire, BlessingSystem.REACH)
	var far := _bush_near(fire, 60.0, BlessingSystem.REACH + 2.0)
	assert_not_null(near, "a bush within reach of the fire")
	assert_not_null(far, "and one beyond it")
	var nodes := session.nodes
	var full := nodes.capacity(near)
	assert_eq(nodes.take(near.id, 3, clock.tick), 3, "picked")
	assert_eq(nodes.take(far.id, 3, clock.tick), 3)
	assert_eq(nodes.left(near), full - 3)
	assert_true(session.interactions.bless(BlessingSystem.BOUNTY, fire).applied)
	assert_eq(nodes.left(near), full, "filled as it was made")
	assert_eq(nodes.left(far), nodes.capacity(far) - 3, "beyond reach: as it was")
	assert_eq(session.vegetation.bounty_at(near.tile), VegetationSystem.BOUNTY_REGROW, "grows back faster under the bounty")
	assert_eq(session.vegetation.bounty_at(far.tile), 1.0, "not elsewhere")
	# Twice as fast (a bush grows all its berries back in two days).
	assert_eq(nodes.take(near.id, 3, clock.tick), 3)
	clock.tick += roundi(2.0 * Config.time.MINUTES_PER_DAY / full / VegetationSystem.BOUNTY_REGROW) + 10
	nodes.settle(clock.tick)
	assert_eq(nodes.left(near), full - 2, "a berry back already under the bounty")
	assert_eq(nodes.left(far), nodes.capacity(far) - 3, "none yet beyond it")
	assert_eq(session.events.of_type(&"bounty_of_bushes").size(), 1, "written down")
	# A season later: as before.
	clock.tick += Config.time.days_per_season * Config.time.MINUTES_PER_DAY
	assert_eq(session.vegetation.bounty_at(near.tile), 1.0, "the season over")
	# Kept with the world while it lasts.
	clock.tick -= Config.time.days_per_season * Config.time.MINUTES_PER_DAY
	assert_true(session.vegetation.to_dict().has("bounty"))
	var again := VegetationSystem.new()
	again.from_dict(session.vegetation.to_dict())
	assert_eq(again.to_dict()["bounty"], session.vegetation.to_dict()["bounty"])


func test_rich_soil_lies_on_the_land_within_reach_and_fades() -> void:
	var fire := _fire()
	var middle := WorldCoords.world2d_to_tile(fire)
	var before: Dictionary = {}
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			var tile := middle + Vector2i(dx, dy)
			if session.world.is_in_bounds(tile):
				before[tile] = _fertility(tile)
	var far := middle + Vector2i(0, 12)
	assert_true(session.interactions.bless(BlessingSystem.SOIL, fire).applied)
	var risen: Array[Vector2i] = []
	for tile: Vector2i in before:
		if _fertility(tile) > int(before[tile]):
			risen.append(tile)
			assert_true(Vector2(tile - middle).length() <= BlessingSystem.REACH, "%s within reach" % tile)
	assert_true(risen.size() >= 20, "%d tiles richer" % risen.size())
	assert_eq(_fertility(far), before[far], "beyond reach: as it was")
	var one := risen[0]
	assert_true(Farming.fertility_factor(_fertility(one)) > Farming.fertility_factor(before[one]), "heavier at harvest")
	assert_true(session.soil.silted >= risen.size())
	assert_eq(session.events.of_type(&"rich_soil").size(), 1)
	# It fades as silt does: a year on, the land is about as it was.
	session.soil.settle_all(clock.tick)
	for i in 40:
		clock.tick += 4 * Config.time.MINUTES_PER_DAY
		session.soil.settle_all(clock.tick)
	assert_true(_fertility(one) <= int(before[one]) + 4, "faded (%d, was %d)" % [_fertility(one), before[one]])


func test_teeming_waters_fill_the_river_and_bring_a_run() -> void:
	var waters := session.fauna.waters
	var fire := _fire()
	var middle := WorldCoords.world2d_to_tile(fire)
	var cells := waters.cells_near(middle, BlessingSystem.REACH)
	assert_false(cells.is_empty(), "water within reach of the fire")
	var at := FishWaters.middle_of(cells[0][0])
	var holds := waters.capacity_at(at)
	waters.set_stock(at, 1.0)
	assert_true(waters.stock_at(at) < holds, "fished down")
	assert_true(session.interactions.bless(BlessingSystem.WATERS, fire).applied)
	assert_true(waters.stock_at(at) >= holds - 0.01, "filled to what it holds")
	var run := waters.run_cell()
	assert_ne(run, Vector2i.MAX, "a run")
	assert_true(Vector2(FishWaters.middle_of(run) - middle).length() <= BlessingSystem.REACH, "within reach")
	assert_near(waters.stock_at(FishWaters.middle_of(run)), waters.capacity_at(FishWaters.middle_of(run)) * FishWaters.RUN_SHARE, 0.01, "thick with fish")
	assert_eq(session.events.of_type(&"teeming_waters").size(), 1)
	# It lasts its days, as a run does.
	clock.tick += (FishWaters.RUN_DAYS + 1) * Config.time.MINUTES_PER_DAY
	waters.advance_day(clock.tick, RandomNumberGenerator.new())
	assert_eq(waters.run_cell(), Vector2i.MAX, "over after its days")


# --- healing (step 3) -----------------------------------------------------------------------------

func test_healing_mends_the_ill_and_the_hurt_within_reach() -> void:
	var fire := _fire()
	var people := session.people.all_people()
	assert_true(people.size() >= 4)
	var hurt: PersonData = people[0]
	var ill: PersonData = people[1]
	var hungry: PersonData = people[2]
	var cold: PersonData = people[3]
	var well: PersonData = people[4] if people.size() > 4 else null
	for person: PersonData in [hurt, ill, hungry, cold]:
		person.position = WorldCoords.world2d_to_tile(fire + Vector2(1.0, 0.5))
	var far: PersonData = null
	for person in people:
		if not [hurt, ill, hungry, cold, well].has(person):
			far = person
			far.position = WorldCoords.world2d_to_tile(fire + Vector2(BlessingSystem.REACH + 6.0, 0.0))
			break
	assert_not_null(far)
	var now := clock.tick
	Health.injure(hurt, Health.FALL, 0.6, now)
	var hurt_health := hurt.health
	assert_true(hurt_health < 1.0 and not hurt.injuries.is_empty())
	assert_true(Health.fall_ill(ill, &"fever", now))
	assert_true(Health.is_ill(ill))
	hungry.conditions.append({"id": String(Hardship.HUNGER), "since": now - 3000, "sick": true, "fed": false})
	assert_true(Hardship.is_sick(hungry))
	cold.health = 0.5
	cold.conditions.append({"id": String(Exposure.COLD), "exposed": 400.0, "sick": true, "well": 0.9, "fed": false})
	Health.injure(far, Health.CUT, 0.5, now)
	var far_health := far.health
	var births: Array = []
	for person in people:
		births.append(person.birth_tick)
	var living := people.size()
	assert_true(session.interactions.bless(BlessingSystem.HEALING, fire).applied)
	assert_true(hurt.injuries.is_empty(), "the injury is gone")
	assert_true(hurt.health > hurt_health, "and the health it took is back")
	assert_false(Health.is_ill(ill), "the illness has passed")
	assert_false(Health.illness_of(ill).is_empty(), "health comes back over the day, as after any illness")
	assert_false(Hardship.is_sick(hungry), "the weak with hunger stand up")
	assert_false(Hardship.condition_of(hungry).is_empty(), "still hungry")
	assert_true(Hardship.condition_of(cold, Exposure.COLD).is_empty(), "warmed through")
	assert_near(cold.health, 0.9, 0.001)
	assert_eq(far.injuries.size(), 1, "beyond reach: as they were")
	assert_eq(far.health, far_health)
	assert_eq(blessings.healed.size(), 4, "four mended: %s" % str(blessings.healed))
	assert_true(blessings.healed.has(hurt.id) and blessings.healed.has(cold.id))
	assert_false(blessings.healed.has(far.id))
	var ailing: Array = session.behavior.ctx.ailments
	assert_true(ailing.any(func(entry: Array) -> bool: return entry[0] == ill.id and entry[1] == Health.ILLNESS and not entry[2]),
		"told of as a recovery")
	assert_eq(session.people.size(), living, "nobody brought back")
	for n in people.size():
		assert_eq(people[n].birth_tick, births[n], "nobody made younger")
	assert_eq(session.events.of_type(&"healing").size(), 1)


# --- noticed and remembered (step 4) ----------------------------------------------------------------

func test_the_land_and_the_water_are_noticed_by_those_near() -> void:
	var fire := _fire()
	for pair: Array in [[BlessingSystem.BOUNTY, Stimulus.BOUNTY_OF_BUSHES], [BlessingSystem.SOIL, Stimulus.RICH_SOIL],
			[BlessingSystem.WATERS, Stimulus.TEEMING_WATERS]]:
		stimuli.clear()
		disasters.rest_until = 0
		blessings.kind = &""
		assert_true(session.interactions.bless(pair[0], fire).applied, "%s given" % pair[0])
		assert_eq(stimuli.size(), 1, "%s: one thing to notice" % pair[0])
		var seen: Stimulus = stimuli[0]
		assert_eq(seen.type, pair[1])
		assert_true(seen.anomalous and seen.large and not seen.weatherlike)
		assert_true(seen.radius > BlessingSystem.REACH, "noticed by those about: %.0f" % seen.radius)
		assert_near(seen.position.distance_to(fire), 0.0, 0.6)
		assert_true(MemoryText.has("MEMWHAT_" + String(pair[1]).to_upper()))
		assert_true(MemoryText.has("EPITHET_" + String(pair[1]).to_upper()))
		assert_true(CultureSystem.FROM_MEMORIES.has(pair[1]), "%s may become a tradition" % pair[1])
		assert_true(MemoryText.has(str(CultureSystem.FROM_MEMORIES[pair[1]][0])))


func test_being_healed_is_felt_by_each_one_healed() -> void:
	var fire := _fire()
	var people := session.people.all_people()
	var mended: Array[PersonData] = [people[0], people[1]]
	for person in mended:
		person.position = WorldCoords.world2d_to_tile(fire + Vector2(1.0, 0.5))
		Health.injure(person, Health.FALL, 0.5, clock.tick)
	var well: PersonData = people[2]
	well.position = WorldCoords.world2d_to_tile(fire + Vector2(-1.0, 0.5))
	stimuli.clear()
	assert_true(session.interactions.bless(BlessingSystem.HEALING, fire).applied)
	assert_eq(stimuli.size(), 2, "one for each mended, none for the well")
	for person in mended:
		var felt: Array = stimuli.filter(func(s: Stimulus) -> bool: return s.type == Stimulus.HEALED and s.target_id == person.id)
		assert_eq(felt.size(), 1, "felt by %d" % person.id)
		assert_eq((felt[0] as Stimulus).radius, 0.0, "and by nobody else: as a touch")
	assert_false(stimuli.any(func(s: Stimulus) -> bool: return s.target_id == well.id))


func test_a_blessing_lived_through_becomes_a_tradition() -> void:
	var own := session.settlement
	# The bushes heavy with fruit, the Giver's doing, on five days over two seasons.
	for day: int in [1, 2, 3, 7, 8]:
		var tick := day * TimeConfig.MINUTES_PER_DAY + 60
		for person in own.members():
			var memory := Memory.new()
			memory.subject = Stimulus.BOUNTY_OF_BUSHES
			memory.interpretation = ReactionTable.DEITY
			memory.source = Memory.Source.WITNESSED
			memory.tick = tick
			memory.first_tick = tick
			memory.importance = 0.8
			memory.intensity = 0.8
			memory.intervention_id = 42
			memory.emotions = PackedFloat32Array([0.1, 0.6, 0.0, 0.7, 0.2])
			session.memories.remember(person, memory)
	var now := 9 * TimeConfig.MINUTES_PER_DAY
	session.culture.settle(now)
	session.cultures.look_for_traditions(now)
	var formed := session.cultures.tradition_of(own.id, Stimulus.BOUNTY_OF_BUSHES)
	assert_false(formed.is_empty(), "the offering of first fruits")
	assert_eq(formed["name"], "TRADITION_FIRST_FRUITS")
	assert_true(formed["player"], "it goes back to the player")
	var told := session.events.of_type(&"tradition_formed")
	assert_eq(told.size(), 1)
	assert_has(EventText.text(told[0], session.people), "the offering of first fruits")


# --- dependence, step one (step 5) -------------------------------------------------------------------

func test_blessed_twice_in_a_year_a_settlement_comes_to_expect_it() -> void:
	var own := session.settlement
	var fire := _fire()
	assert_true(Dependence.expects(session, own, clock.tick).is_empty(), "nothing yet")
	assert_true(session.interactions.bless(BlessingSystem.BOUNTY, fire).applied)
	_pass(int(BlessingSystem.LASTS[BlessingSystem.BOUNTY]) + BlessingSystem.REST_MINUTES)
	assert_eq(Dependence.gifts_in_year(session, own, clock.tick), {&"bounty_of_bushes": 1})
	assert_true(Dependence.expects(session, own, clock.tick).is_empty(), "once is a gift")
	assert_false(MenuPages.beliefs(session).has("%s has come to expect the fruit" % own.display_name()))
	_pass(20 * Config.time.MINUTES_PER_DAY)
	assert_true(session.interactions.bless(BlessingSystem.BOUNTY, fire).applied)
	_pass(int(BlessingSystem.LASTS[BlessingSystem.BOUNTY]) + BlessingSystem.REST_MINUTES)
	assert_eq(Dependence.expects(session, own, clock.tick), [&"bounty_of_bushes"] as Array[StringName], "twice is expected")
	assert_has(MenuPages.beliefs(session), "%s has come to expect the fruit" % own.display_name())
	# Another gift, once: not that one.
	assert_true(session.interactions.bless(BlessingSystem.WATERS, fire).applied)
	_pass(int(BlessingSystem.LASTS[BlessingSystem.WATERS]) + BlessingSystem.REST_MINUTES)
	assert_eq(Dependence.gifts_in_year(session, own, clock.tick), {&"bounty_of_bushes": 2, &"teeming_waters": 1})
	assert_eq(Dependence.expects(session, own, clock.tick), [&"bounty_of_bushes"] as Array[StringName])
	# A year without: forgotten.
	_pass(Config.time.ticks_per_year())
	assert_true(Dependence.expects(session, own, clock.tick).is_empty(), "a year on, as before")
	assert_false(MenuPages.beliefs(session).has("%s has come to expect the fruit" % own.display_name()))


func test_a_gift_far_from_the_fire_is_not_the_settlements() -> void:
	var own := session.settlement
	var away := _fire() + Vector2(Dependence.NEAR + 12.0, 0.0)
	assert_true(session.interactions.bless(BlessingSystem.SOIL, away).applied)
	_pass(int(BlessingSystem.LASTS[BlessingSystem.SOIL]) + BlessingSystem.REST_MINUTES)
	assert_true(session.interactions.bless(BlessingSystem.SOIL, away).applied)
	_pass(int(BlessingSystem.LASTS[BlessingSystem.SOIL]) + BlessingSystem.REST_MINUTES)
	assert_true(Dependence.gifts_in_year(session, own, clock.tick).is_empty(), "blessed land, but not theirs")


# --- dependence, step two (step 6) -------------------------------------------------------------------

func test_what_is_expected_has_teeth() -> void:
	var none: Array[StringName] = []
	var fruit: Array[StringName] = [&"bounty_of_bushes"]
	var river: Array[StringName] = [&"teeming_waters"]
	assert_eq(Dependence.plots_wanted(6, none), 6)
	assert_eq(Dependence.plots_wanted(6, fruit), 3, "fewer fields: the bushes will feed them")
	assert_eq(Dependence.plots_wanted(1, fruit), 1, "never none")
	assert_eq(Dependence.plots_wanted(0, fruit), 0)
	assert_eq(Dependence.plots_wanted(6, river), 6, "the river is not the fields' business")
	assert_eq(Dependence.fishers_wanted(3, none), 3)
	assert_eq(Dependence.fishers_wanted(3, river), 1, "no more take up the nets")
	assert_eq(Dependence.fishers_wanted(1, river), 1)
	assert_eq(Dependence.fishers_wanted(3, fruit), 3)


func test_the_session_weighs_what_is_expected_once_a_day() -> void:
	var own := session.settlement
	var fire := _fire()
	for n in 2:
		assert_true(session.interactions.bless(BlessingSystem.BOUNTY, fire).applied)
		_pass(int(BlessingSystem.LASTS[BlessingSystem.BOUNTY]) + BlessingSystem.REST_MINUTES)
	assert_true(own.expected.is_empty(), "not weighed yet today")
	var plots_before := own.farming.plots_wanted()
	var fishers_before := own.fishers_wanted()
	session.weigh_dependence(clock.tick, true)
	assert_eq(own.expected, [&"bounty_of_bushes"] as Array[StringName])
	assert_eq(own.farming.expected, own.expected, "the fields know it")
	assert_true(own.farming.plots_wanted() <= plots_before)
	assert_eq(own.fishers_wanted(), fishers_before, "the river was not expected")
	# Once a day: the same day, nothing is weighed again; the next day it is.
	own.expected = []
	session.weigh_dependence(clock.tick)
	assert_true(own.expected.is_empty(), "weighed once a day")
	_pass(Config.time.MINUTES_PER_DAY)
	session.weigh_dependence(clock.tick)
	assert_eq(own.expected, [&"bounty_of_bushes"] as Array[StringName], "the day after, again")
	# A year without, and the fields are their own again.
	_pass(Config.time.ticks_per_year())
	session.weigh_dependence(clock.tick)
	assert_true(own.expected.is_empty())
	assert_true(own.farming.expected.is_empty())


# --- the mirror completed (step 7) --------------------------------------------------------------------

func test_the_drought_broken_is_a_day_of_soft_rain_and_the_river_back_in_its_bed() -> void:
	var weather := session.weather
	var river := session.hydrology
	weather.begin_drought(clock.tick)
	assert_true(weather.has_condition(WeatherSystem.DROUGHT), "a drought")
	river.add(-0.3)
	assert_true(river.level < 0.0, "the river low")
	stimuli.clear()
	assert_true(session.interactions.bless(BlessingSystem.RAIN, _fire()).applied)
	assert_false(weather.has_condition(WeatherSystem.DROUGHT), "broken")
	assert_eq(weather.state, WeatherSystem.RAIN, "soft rain")
	assert_near(river.level, 0.0, 0.001, "the river back where it was made")
	assert_true(stimuli.is_empty(), "the weather's own: nothing of the Presence to notice")
	assert_eq(session.events.of_type(&"drought_broken").size(), 1)
	# Not over its banks: a river already high stays as it is.
	disasters.rest_until = 0
	blessings.kind = &""
	river.add(0.2)
	var high := river.level
	assert_true(session.interactions.bless(BlessingSystem.RAIN, _fire()).applied)
	assert_near(river.level, high, 0.001, "no higher")
	# It does not come back tomorrow for the dry days before.
	weather.advance_to(clock.tick + 2 * Config.time.MINUTES_PER_DAY)
	assert_false(weather.has_condition(WeatherSystem.DROUGHT), "the day's rain counted")


func test_the_herds_return_within_reach() -> void:
	var fire := _fire()
	var deer_before := session.animals.count(BlessingSystem.HERD_SPECIES)
	stimuli.clear()
	assert_true(session.interactions.bless(BlessingSystem.HERDS, fire).applied)
	var deer_after := session.animals.count(BlessingSystem.HERD_SPECIES)
	assert_true(deer_after >= deer_before + 5, "a herd: %d → %d" % [deer_before, deer_after])
	var near := 0
	for animal in session.animals.all_animals():
		if animal.species == BlessingSystem.HERD_SPECIES and animal.position.distance_to(fire) <= BlessingSystem.REACH + 2.0:
			near += 1
	assert_true(near >= 5, "%d of them within reach" % near)
	assert_true(stimuli.any(func(s: Stimulus) -> bool: return s.type == Stimulus.HERDS_CAME), "noticed")
	assert_eq(session.events.of_type(&"herds_returned").size(), 1)


func test_a_village_that_expects_the_rain_digs_no_well() -> void:
	var none: Array[StringName] = []
	var rain: Array[StringName] = [&"drought_broken"]
	assert_true(Dependence.digs_wells(none))
	assert_false(Dependence.digs_wells(rain))
	var own := session.settlement
	for n in 2:
		assert_true(session.interactions.bless(BlessingSystem.RAIN, _fire()).applied)
		_pass(int(BlessingSystem.LASTS[BlessingSystem.RAIN]) + BlessingSystem.REST_MINUTES)
	session.weigh_dependence(clock.tick, true)
	assert_eq(own.expected, [&"drought_broken"] as Array[StringName])
	assert_has(MenuPages.beliefs(session), "%s has come to expect the rain — and digs no well" % own.display_name())
