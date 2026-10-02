extends TestCase
## Short of food (M7.5): a settlement with too little in store rations it
## and goes further for berries; with nothing at all it eats its seed grain
## — and the next harvest is the poorer for it; people who go hungry too
## long are weak with it, remember it and talk of it.

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var session: WorldSession
var behavior: BehaviorSystem
var ctx: AiContext
var settlement: Settlement
var stock: Stockpile
var farming: Farming
var events: EventLog
var _knobs: Array = [] # [config, name, value before]


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
	settlement = session.settlement
	stock = settlement.stockpile
	farming = session.farming
	events = session.events


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


## Lets hours pass for the settlement and its fields alone (nobody lives).
func _hours(hours: int) -> void:
	for hour in hours:
		for half in 2:
			session.clock.tick += 30
			settlement.step(session.clock.tick)


## Lets everyone live.
func _run(minutes: float, step: float = 1.0) -> void:
	var left := minutes
	while left > 0.0001:
		var dt := minf(step, left)
		var seconds := dt * Config.time.real_seconds_per_game_minute
		while seconds > 0.000001:
			var piece := minf(seconds, Config.time.max_frame_delta_s)
			session.clock.advance(piece)
			seconds -= piece
		behavior.step(dt)
		session.pathfinder.serve(1_000_000)
		session.movement.step(dt)
		if session.nodes.due(session.clock.tick):
			session.nodes.settle(session.clock.tick)
		left -= dt


func _empty_food() -> void:
	for resource: StringName in stock.amounts():
		if session.resources.get_def(resource).is_food():
			stock.take(resource, stock.amount(resource))


## Short of food, from nothing in store for hours.
func _make_short() -> void:
	_empty_food()
	_hours(4)
	assert_eq(settlement.shortage, Settlement.Shortage.SHORT)


func _adult(occupation: StringName = &"forager") -> PersonData:
	for p in session.people.all_people():
		if p.occupation_id == occupation:
			return p
	return null


func _child() -> PersonData:
	for p in session.people.all_people():
		if ctx.stage_of(p) == PersonData.LifeStage.CHILD:
			return p
	return null


func _calm(person: PersonData, hunger: float = 0.9) -> PersonData:
	person.needs = PackedFloat32Array([hunger, 0.95, 0.9, 0.9, 0.6, 1.0])
	person.food_in_hand = 0.0
	return person


func _soil(tile: Vector2i, moisture: int, fertility: int) -> void:
	var chunk := session.world.chunk_at_tile(tile)
	var i := session.world.index_at_tile(tile)
	chunk.set_moisture(i, moisture)
	chunk.set_fertility(i, fertility)


## Eats at the stores until the step is done. Returns the step.
func _eat_at_the_stores(person: PersonData) -> Dictionary:
	var step := EatStep.make(ctx.places.food_tile(person), false)
	var handler := EatStep.new()
	handler.begin(ctx, person, step)
	for minute in 300:
		if handler.update(ctx, person, step, 1.0) != ActionStep.Status.RUNNING:
			break
	handler.end(ctx, person, step)
	return step


func _strip_bushes(center: Vector2i, radius: float) -> int:
	var stripped := 0
	for prop in session.props.all_props():
		if prop.kind == PropData.Kind.BUSH and Vector2(prop.tile - center).length() <= radius:
			session.nodes.take(prop.id, 1000, session.clock.tick)
			stripped += 1
	return stripped


# --- the stages -----------------------------------------------------------------------------------------

func test_a_shortage_begins_and_ends() -> void:
	assert_eq(Config.settlement.validate().size(), 0)
	assert_eq(Config.needs.validate().size(), 0)
	var changes: Array = []
	settlement.shortage_changed.connect(func(stage: int, was: int) -> void: changes.append([stage, was]))
	assert_eq(settlement.shortage, Settlement.Shortage.NONE)
	assert_false(settlement.is_short())
	assert_near(ctx.places.forage_reach, 1.0, 0.001)
	# An untouched day: a new settlement's day of food is no shortage.
	_hours(8)
	assert_eq(changes, [])
	# Nothing in store: not at once...
	_empty_food()
	_hours(2)
	assert_eq(settlement.shortage, Settlement.Shortage.NONE, "a bad hour is no shortage")
	# ...but after three hours of it.
	_hours(2)
	assert_eq(settlement.shortage, Settlement.Shortage.SHORT)
	assert_eq(changes, [[Settlement.Shortage.SHORT, Settlement.Shortage.NONE]])
	assert_true(settlement.is_short())
	assert_near(settlement.ration(), Config.settlement.food_per_person_day * Config.settlement.ration_share, 0.0001)
	assert_near(ctx.places.forage_reach, Config.settlement.forage_further_factor, 0.001, "people go further for berries")
	assert_true(settlement.debug_text().contains("SHORT OF FOOD"))
	# A little food is not the end of it (and puts off the worst).
	_hours(2)
	stock.add(&"berries", 5)
	_hours(2)
	assert_eq(settlement.shortage, Settlement.Shortage.SHORT)
	# Nothing at all for three hours: out of food.
	_empty_food()
	_hours(2)
	assert_eq(settlement.shortage, Settlement.Shortage.SHORT)
	_hours(2)
	assert_eq(settlement.shortage, Settlement.Shortage.EMPTY)
	assert_true(settlement.debug_text().contains("OUT OF FOOD"))
	assert_false(settlement.seed_eaten, "there was no seed to eat")
	# Something again: short, but not out.
	stock.add(&"berries", 10)
	_hours(1)
	assert_eq(settlement.shortage, Settlement.Shortage.SHORT)
	# Enough again: over.
	stock.add(&"berries", 30)
	_hours(1)
	assert_eq(settlement.shortage, Settlement.Shortage.NONE)
	assert_near(ctx.places.forage_reach, 1.0, 0.001)
	assert_eq(changes.size(), 4)
	assert_eq(changes[-1], [Settlement.Shortage.NONE, Settlement.Shortage.SHORT])
	# Each stage is in the log, in order, each because of the shortage.
	var shortage := events.latest(Chronicler.TYPE_SHORTAGE)
	assert_eq(events.count_of(Chronicler.TYPE_SHORTAGE), 1)
	assert_eq(Array(events.latest(Chronicler.TYPE_EMPTY).causes), [shortage.id])
	assert_eq(Array(events.latest(Chronicler.TYPE_OVER).causes), [shortage.id])


func test_rationing_everyone_gets_a_share() -> void:
	var person := _calm(_adult(), 0.0)
	var other := _calm(_adult(&"woodcutter"), 0.0)
	# No shortage: the stores are open to everyone, however much they have had.
	settlement.note_served(person.id, 5.0)
	assert_true(settlement.serves(person.id))
	_make_short()
	stock.add(&"berries", 12) # (half a day's food: still short)
	_hours(1)
	assert_eq(settlement.shortage, Settlement.Shortage.SHORT)
	settlement._served.clear()
	assert_true(settlement.serves(person.id))
	# They eat — their share for the day, no more.
	var before := stock.amount(&"berries")
	var step := _eat_at_the_stores(person)
	var eaten := before - stock.amount(&"berries")
	assert_true(eaten >= 1)
	assert_true(settlement.served_today(person.id) >= settlement.ration(), "%.2f of %.2f" % [settlement.served_today(person.id), settlement.ration()])
	assert_near(settlement.served_today(person.id), eaten * session.resources.get_def(&"berries").nutrition, 0.001)
	assert_true(settlement.served_today(person.id) < Config.settlement.food_per_person_day, "less than a day's food")
	assert_false(settlement.serves(person.id))
	assert_true(settlement.serves(other.id), "everyone has a share of their own")
	# Hungry again the same day: nothing more from the stores for them.
	_calm(person, 0.2)
	before = stock.amount(&"berries")
	step = _eat_at_the_stores(person)
	assert_true(bool(step.get("empty", false)))
	assert_eq(stock.amount(&"berries"), before, "the stores are closed to them")
	assert_near(Needs.value(person.needs, Needs.Need.HUNGER), 0.2, 0.01, "still hungry")
	# They go to the bushes instead.
	var plan := Planner.plan(&"eat", person, ctx)
	assert_eq(plan.size(), 2)
	assert_true((plan[1] as Dictionary).has("bush"), "to a bush: %s" % str(plan))
	assert_true(ctx.places.has_food(person, settlement))
	# With the bushes bare there is nothing for them to eat today — while the other still eats.
	_strip_bushes(session.start.settlement_tile, 100.0)
	assert_false(ctx.places.has_food(person, settlement))
	assert_eq(Planner.plan(&"eat", person, ctx), [])
	assert_true(ctx.places.has_food(other, settlement))
	assert_eq((Planner.plan(&"eat", other, ctx)[1] as Dictionary).has("bush"), false)
	# A new day, a new share.
	_hours(24)
	assert_eq(settlement.shortage != Settlement.Shortage.NONE, true)
	assert_true(settlement.serves(person.id))
	assert_near(settlement.served_today(person.id), 0.0, 0.0001)


func test_people_go_further_for_berries() -> void:
	var person := _adult()
	var home: Vector2i = ctx.places.home_tile(person)
	var near := 0
	var far := 0
	for prop in session.props.all_props():
		if prop.kind == PropData.Kind.BUSH and session.world.get_water(prop.tile) <= Pathfinder.WET_DEPTH:
			var distance := Vector2(prop.tile - home).length()
			if distance <= Places.WORK_RADIUS:
				near += 1
			elif distance <= Places.WORK_RADIUS * Config.settlement.forage_further_factor:
				far += 1
	assert_true(near > 0 and far > 0, "bushes near (%d) and further off (%d)" % [near, far])
	# The bushes near home are bare.
	_strip_bushes(home, Places.WORK_RADIUS)
	assert_eq(ctx.places.forage_place(person, null), {}, "nothing within reach")
	# Short of food, they go further.
	_make_short()
	var place := ctx.places.forage_place(person, null)
	assert_false(place.is_empty(), "further off there are berries")
	var distance := Vector2((place["tile"] as Vector2i) - home).length()
	assert_true(distance > Places.WORK_RADIUS and distance <= Places.WORK_RADIUS * Config.settlement.forage_further_factor,
		"%.1f tiles from home" % distance)
	var work := ctx.places.work_place(person, &"bush", ctx.rng)
	assert_true(Vector2((work["tile"] as Vector2i) - home).length() > Places.WORK_RADIUS, "to gather, too")
	# Trees are cut where they always were.
	var tree := ctx.places.work_place(person, &"tree", ctx.rng)
	assert_true(Vector2((tree["tile"] as Vector2i) - home).length() <= Places.WORK_RADIUS)
	# Over: back to the bushes near home (bare as they are).
	stock.add(&"berries", 60)
	_hours(1)
	assert_eq(settlement.shortage, Settlement.Shortage.NONE)
	var back := ctx.places.forage_place(person, null)
	assert_true(back.is_empty() or Vector2((back["tile"] as Vector2i) - home).length() <= Places.WORK_RADIUS)


# --- the seed grain -------------------------------------------------------------------------------------

func test_the_seed_grain_is_eaten_and_the_next_harvest_suffers() -> void:
	# Soil that keeps what it is given; no shortage until the test wants one.
	for knob: Array in [[&"rain_moisture", 0], [&"evaporation_per_day", 0], [&"crop_draw_per_day", 0], [&"seep_share", 0.0]]:
		_knob(Config.farming, knob[0], knob[1])
	_knob(Config.farming, &"season_growth", PackedFloat32Array([1.0, 1.0, 1.0, 1.0]))
	_knob(Config.farming, &"grow_days", 8.0) # (the days this test counts in)
	_knob(Config.settlement, &"shortage_after_minutes", 100_000_000)
	_empty_food()
	# The first field: sown with what was gathered wild — no seed asked for.
	var tile: Vector2i = farming.next_plot()
	_soil(tile, 200, 200)
	assert_eq(farming.seed_wanted(), 0, "before the first harvest there is no grain to keep")
	var crop := farming.sow(tile, session.clock.tick)
	assert_false(farming.is_thin(crop.id))
	_hours(24 * 9)
	assert_eq(Farming.stage_of(crop), Farming.Stage.RIPE)
	var full_yield := crop.stock
	assert_true(full_yield >= 5, "%d" % full_yield)
	assert_eq(session.nodes.take(crop.id, 1000, session.clock.tick), full_yield)
	assert_eq(Farming.stage_of(crop), Farming.Stage.STUBBLE)
	assert_eq(farming.harvest_count(), 1)
	# From now on seed is kept: a unit for every plot that is to be sown.
	var plots := farming.plots_wanted()
	assert_eq(farming.seed_wanted(), plots * Config.farming.seed_per_plot)
	_empty_food()
	stock.add(&"grain", plots + 4)
	_hours(1)
	assert_eq(stock.reserved(&"grain"), plots)
	assert_eq(stock.available(&"grain"), 4)
	assert_eq(stock.food_units(), 4, "what is kept for seed is not food")
	assert_near(stock.food(), 4.0, 0.001)
	assert_true(stock.debug_text().contains("(%d kept)" % plots))
	# It is not eaten: when the rest is gone, there is "nothing to eat".
	var eaten := 0
	while stock.take_food() != &"":
		eaten += 1
	assert_eq(eaten, 4)
	assert_eq(stock.amount(&"grain"), plots)
	assert_eq(stock.food_units(), 0)
	# Short of food, and then out of it: the seed is eaten.
	var released: Array = []
	settlement.seed_released.connect(func(units: int) -> void: released.append(units))
	Config.settlement.shortage_after_minutes = 180
	_hours(1)
	assert_eq(settlement.shortage, Settlement.Shortage.SHORT)
	assert_eq(stock.reserved(&"grain"), plots, "short of food is not yet reason enough")
	_hours(4)
	assert_eq(released, [plots])
	assert_true(settlement.seed_eaten)
	assert_eq(stock.reserved(&"grain"), 0)
	assert_eq(stock.food_units(), plots, "now it is food")
	var seed_eaten := events.latest(Chronicler.TYPE_SEED_EATEN)
	var empty := events.latest(Chronicler.TYPE_EMPTY)
	var shortage := events.latest(Chronicler.TYPE_SHORTAGE)
	assert_eq(Array(seed_eaten.causes), [empty.id])
	assert_eq(Array(empty.causes), [shortage.id])
	assert_eq(EventText.text(seed_eaten, session.people, events), "The seed grain is being eaten")
	while stock.take_food() != &"":
		pass
	assert_eq(stock.amount(&"grain"), 0)
	# The plot is sown all the same — with what can be gleaned: a thin sowing.
	var thin_reports: Array = []
	farming.sown_thin.connect(func(crop_id: int) -> void: thin_reports.append(crop_id))
	session.clock.tick += 2 * 1440
	_soil(tile, 200, 200)
	var thin := farming.sow(tile, session.clock.tick)
	assert_not_null(thin)
	assert_true(farming.is_thin(thin.id))
	assert_eq(thin_reports, [thin.id])
	var thin_sowing := events.latest(Chronicler.TYPE_THIN_SOWING)
	assert_eq(Array(thin_sowing.causes), [seed_eaten.id])
	# Beside it a plot sown with seed someone had left, in the same soil.
	stock.add(&"grain", 1)
	var beside: Vector2i = farming.next_plot()
	_soil(beside, 200, 200)
	var seeded := farming.sow(beside, session.clock.tick)
	assert_false(farming.is_thin(seeded.id))
	assert_eq(stock.amount(&"grain"), 0, "the seed went into the ground")
	stock.add(&"grain", 200) # (the hunger is over)
	_hours(24 * 9)
	assert_eq(settlement.shortage, Settlement.Shortage.NONE)
	assert_eq(Farming.stage_of(thin), Farming.Stage.RIPE)
	assert_eq(Farming.stage_of(seeded), Farming.Stage.RIPE)
	assert_eq(seeded.stock, full_yield)
	assert_eq(thin.stock, maxi(roundi(full_yield * Config.farming.thin_yield), 1), "half a harvest")
	# The whole chain is written down: shortage → empty stores → seed eaten → thin sowing → poor harvest.
	var poor := events.latest(Chronicler.TYPE_POOR_HARVEST)
	assert_not_null(poor)
	assert_eq(Array(poor.causes), [thin_sowing.id])
	assert_eq(events.chain(poor.id).map(func(e: WorldEvent) -> int: return e.id),
		[shortage.id, empty.id, seed_eaten.id, thin_sowing.id])
	assert_true(events.led_to(shortage.id, poor.id))
	assert_eq(EventText.text(poor, session.people, events), "The harvest is poor: the seed was eaten")
	# Reaped, there is grain again — and seed is kept again.
	session.nodes.take(thin.id, 1000, session.clock.tick)
	assert_false(farming.is_thin(thin.id))
	stock.add(&"grain", 20)
	_hours(1)
	assert_false(settlement.seed_eaten)
	assert_true(stock.reserved(&"grain") >= 1)
	var again := farming.sow(tile, session.clock.tick)
	assert_false(farming.is_thin(again.id), "sown with seed")
	# What the fields keep is saved.
	var saved := farming.to_dict()
	assert_eq(saved["harvests"], farming.harvest_count())
	farming.from_dict({"day": saved["day"], "harvests": 3, "thin": [seeded.id], "dry_days": 2, "dry": false})
	assert_eq([farming.harvest_count(), farming.is_thin(seeded.id), farming.dry_days()], [3, true, 2])


# --- people ---------------------------------------------------------------------------------------------

func test_going_hungry_makes_people_weak_and_they_talk_of_it() -> void:
	var person := _adult()
	var friend := _adult(&"woodcutter")
	var child := _child()
	assert_not_null(child)
	var ill: Array = []
	var well: Array = []
	behavior.fell_ill.connect(func(id: int, condition: StringName) -> void: ill.append([id, condition]))
	behavior.recovered.connect(func(id: int, condition: StringName) -> void: well.append([id, condition]))
	# Hungry with food in the settlement: an empty belly, nothing to remember.
	_calm(person, 0.05)
	Hardship.live(person, ctx, 1.0)
	assert_false(Hardship.condition_of(person).is_empty())
	assert_false(Hardship.is_sick(person))
	assert_eq(session.memories.about(person, Hardship.HUNGER).size(), 0)
	_calm(person, 0.9)
	Hardship.live(person, ctx, 1.0)
	assert_true(Hardship.condition_of(person).is_empty(), "fed: nothing came of it")
	# In a shortage, whoever is hungry remembers it.
	_make_short()
	for p: PersonData in [person, child]:
		_calm(p, 0.05)
		Hardship.live(p, ctx, 1.0)
	var memories := session.memories.about(person, Hardship.HUNGER)
	assert_eq(memories.size(), 1)
	var memory := memories[0]
	assert_eq([memory.kind, memory.source, memory.count], [Memory.KIND_HARDSHIP, Memory.Source.DIRECT, 1])
	assert_eq(MemoryText.text(memory, session.people), "went hungry: there was not enough for everyone")
	assert_eq(MemoryText.text(session.memories.about(child, Hardship.HUNGER)[0], session.people), "went to bed hungry")
	assert_true(memory.importance >= Config.memory.tell_importance)
	Hardship.live(person, ctx, 1.0)
	assert_eq(memory.count, 1, "once a day")
	# Half a day of it and they are weak with hunger.
	var health := person.health
	session.clock.tick += Config.needs.hunger_sick_after_minutes - 10
	Hardship.live(person, ctx, 1.0)
	assert_false(Hardship.is_sick(person))
	session.clock.tick += 10
	Hardship.live(person, ctx, 1.0)
	assert_true(Hardship.is_sick(person))
	behavior.announce()
	assert_eq(ill, [[person.id, Hardship.HUNGER]])
	var sick := events.latest(Chronicler.TYPE_SICK)
	assert_not_null(sick)
	assert_eq(Array(sick.participants), [person.id])
	assert_eq(Array(sick.causes), [events.latest(Chronicler.TYPE_SHORTAGE).id], "because of the shortage")
	assert_eq(EventText.text(sick, session.people, events), "%s is weak with hunger" % person.given_name)
	assert_eq(PersonCard.facts(session, person)["mood"], "Weak with hunger")
	# Their health goes down day by day (and with it how fast they walk) — to a floor.
	assert_near(person.health, health, 0.0001)
	Hardship.live(person, ctx, 1440.0)
	assert_near(person.health, health - Config.needs.sick_health_per_day, 0.001)
	for day in 10:
		Hardship.live(person, ctx, 1440.0)
	assert_near(person.health, Config.needs.sick_health_floor, 0.001)
	# The next day they remember it again: the same memory, twice.
	session.clock.tick += 1440
	session.memories.about(person, Hardship.HUNGER)[0].told_tick = -1
	Hardship.condition_of(person)["sick"] = false
	Hardship.condition_of(person)["since"] = session.clock.tick
	Hardship.live(person, ctx, 1.0)
	assert_eq(session.memories.about(person, Hardship.HUNGER).size(), 1)
	assert_true(session.memories.about(person, Hardship.HUNGER)[0].count >= 2)
	Hardship.condition_of(person)["sick"] = true
	Hardship.live(child, ctx, 1.0) # (the child is as hungry today)
	# Someone who went hungry too is not told; someone who did not, is — and knows it second hand.
	assert_null(Gossip.share(ctx, person, child), "the child was there")
	var beliefs := friend.beliefs.duplicate()
	ctx.perceptions.clear()
	var told := Gossip.share(ctx, person, friend)
	assert_not_null(told)
	assert_eq(told.subject, Hardship.HUNGER)
	var heard := session.memories.about(friend, Hardship.HUNGER)
	assert_eq(heard.size(), 1)
	assert_eq([heard[0].source, heard[0].told_by, heard[0].kind], [Memory.Source.TOLD, person.id, Memory.KIND_HARDSHIP])
	assert_eq(MemoryText.text(heard[0], session.people), "heard from %s that there is not enough to eat" % person.given_name)
	assert_true(heard[0].importance < session.memories.about(person, Hardship.HUNGER)[0].importance)
	assert_eq(friend.beliefs, beliefs, "nothing to make of it: no doing of the unseen")
	assert_false(ctx.perceptions.has(friend.id))
	assert_null(Gossip.share(ctx, person, friend), "not twice")
	# Fed again: they recover, and their health comes back to what it was.
	_calm(person, 0.9)
	Hardship.live(person, ctx, 1.0)
	assert_false(Hardship.is_sick(person))
	behavior.announce()
	assert_eq(well, [[person.id, Hardship.HUNGER]])
	var recovered := events.latest(Chronicler.TYPE_RECOVERED)
	assert_eq(Array(recovered.causes), [sick.id])
	assert_ne(PersonCard.facts(session, person)["mood"], "Weak with hunger")
	Hardship.live(person, ctx, 1440.0)
	assert_near(person.health, Config.needs.sick_health_floor + Config.needs.recover_health_per_day, 0.001)
	for day in 10:
		Hardship.live(person, ctx, 1440.0)
	assert_near(person.health, health, 0.001)
	assert_true(Hardship.condition_of(person).is_empty())
	# The condition is saved with the person.
	_calm(child, 0.02)
	var again := PersonData.from_dict(child.to_dict())
	assert_eq(Hardship.condition_of(again).get("id"), "hunger")


## The plan's manual check as a test, with everyone living: the stores are
## gone. By day the settlement makes good the loss within hours (no
## shortage comes of it); gone in the evening, there is nothing until
## morning: it rations, goes further for berries, eats off the bushes,
## fills its stores again — and everyone gets through it.
func test_a_starved_settlement_gets_through() -> void:
	# By day: everyone turns to gathering, and before long there is food again.
	_run(120.0)
	_empty_food()
	_run(360.0)
	assert_eq(events.count_of(Chronicler.TYPE_SHORTAGE), 0, "made good within hours")
	assert_true(stock.food() > 0.0)
	# In the evening: nothing until morning.
	while session.clock.hour() < 19.5:
		_run(10.0)
	_empty_food()
	var ate_off_a_bush := {}
	var hungriest := 1.0
	var days := 0
	while days < 6:
		for hour in 24:
			_run(60.0)
			for person in session.people.all_people():
				hungriest = minf(hungriest, Needs.value(person.needs, Needs.Need.HUNGER))
				for entry: Array in session.day_log.of(person.id):
					if str(entry[1]) == "eat" and str(entry[2]) == "bush":
						ate_off_a_bush[person.id] = true
		days += 1
		if events.count_of(Chronicler.TYPE_OVER) > 0:
			break
	assert_true(ate_off_a_bush.size() >= 1, "someone ate off the bushes (the hungriest anyone was: %.2f)" % hungriest)
	assert_eq(events.count_of(Chronicler.TYPE_SHORTAGE), 1, "the stores gone overnight: a shortage")
	assert_true(events.count_of(Chronicler.TYPE_RATIONING) >= 1 and events.count_of(Chronicler.TYPE_FURTHER) >= 1)
	assert_true(events.count_of(Chronicler.TYPE_OVER) >= 1, "over within %d days (food for %.2f days)" % [days, settlement.days_of_food()])
	assert_eq(settlement.shortage, Settlement.Shortage.NONE)
	assert_eq(session.people.size(), 8, "everyone is still there")
	for person in session.people.all_people():
		assert_true(person.health >= Config.needs.sick_health_floor - 0.001)
		assert_false(Hardship.is_sick(person), "%s is over it" % person.given_name)
