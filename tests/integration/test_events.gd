extends TestCase
## The world's event log (M7.5, bible §21.1–21.2): events are recorded with
## what brought them about, can be asked for by kind, time, place and
## person, stay within bounds, and are saved with the world — and the
## chronicler writes down what the fields, the settlement, the people and
## the player's hand report. Also the hourly statistics.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const V12_FIXTURE := "res://tests/fixtures/saves/v12_world.sav"
const V12_ID := "w1790910591_f5d7c87e"

var session: WorldSession
var behavior: BehaviorSystem
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
func _hours(hours: int, of: WorldSession = null) -> void:
	var s := of if of != null else session
	for hour in hours:
		for half in 2:
			s.clock.tick += 30
			s.settlement.step(s.clock.tick)


func _empty_food(of: WorldSession = null) -> void:
	var s := of if of != null else session
	var stores := s.settlement.stockpile
	for resource: StringName in stores.amounts():
		if s.resources.get_def(resource).is_food():
			stores.take(resource, stores.amount(resource))


## A tile for a plot whose soil no water keeps wet.
func _dry_site() -> Vector2i:
	var from := session.start.settlement_tile
	for dy in range(-9, 10):
		for dx in range(-9, 10):
			var tile := from + Vector2i(dx, dy)
			if farming.suitable(tile) and not farming._wet_beside(tile):
				return tile
	fail("no dry site for a plot")
	return from


func _soil(tile: Vector2i, moisture: int, fertility: int = 200) -> void:
	var chunk := session.world.chunk_at_tile(tile)
	var i := session.world.index_at_tile(tile)
	chunk.set_moisture(i, moisture)
	chunk.set_fertility(i, fertility)


## No rain, and soil that dries out in three days: a dry spell after three
## days, and whatever grows withers soon after.
func _dry_weather() -> void:
	farming.rain_source = Callable() # (the fields' own made-up rain, which the test can switch off)
	_knob(Config.farming, &"rain_chance", PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))
	_knob(Config.farming, &"dry_spell_days", 3)
	_knob(Config.farming, &"evaporation_per_day", 60)
	_knob(Config.farming, &"seep_share", 0.0)
	_knob(Config.farming, &"wilt_days", 1.0)


## Dry spell → crop failure → food shortage, as it happens by itself.
## Returns [dry spell, crop failure, shortage] (the events).
func _the_chain() -> Array:
	_dry_weather()
	_knob(Config.settlement, &"shortage_after_minutes", 100_000_000)
	_empty_food()
	var tile := _dry_site()
	_soil(tile, 230)
	assert_not_null(farming.sow(tile, session.clock.tick))
	_hours(24 * 6)
	var dry := events.latest(Chronicler.TYPE_DRY_SPELL)
	var failure := events.latest(Chronicler.TYPE_CROP_FAILURE)
	# Now the stores are looked at again: nothing in them for three hours.
	Config.settlement.shortage_after_minutes = 180
	_hours(2)
	return [dry, failure, events.latest(Chronicler.TYPE_SHORTAGE)]


# --- the log itself -------------------------------------------------------------------------------

func test_the_log_records_and_answers() -> void:
	assert_eq(Config.events.validate().size(), 0)
	assert_eq(Config.problems.size(), 0, str(Config.problems))
	assert_eq(session.event_defs.problems.size(), 0, str(session.event_defs.problems))
	assert_true(session.event_defs.size() >= 20)
	for id in session.event_defs.ids():
		assert_true(MemoryText.has(session.event_defs.get_def(id).key_for_text()), "a text for %s" % id)
	var clock := GameClock.new(Config.time)
	var log := EventLog.new()
	log.bind(clock, session.event_defs, Config.events)
	var seen: Array = []
	log.recorded.connect(func(event: WorldEvent) -> void: seen.append(event.id))
	clock.tick = 100
	var first := log.record(&"animal_hunted", {"species": "deer", "participants": [7], "position": Vector2(3.5, 4.5), "settlement": 2})
	assert_eq(first.id, 1)
	assert_eq([first.type, first.tick, first.position, first.settlement_id], [&"animal_hunted", 100, Vector2(3.5, 4.5), 2])
	assert_eq(Array(first.participants), [7])
	assert_eq(first.text_params, {"species": "deer"}, "what is not about where and who goes into the text")
	assert_eq(first.text_key, "EVENT_ANIMAL_HUNTED")
	assert_true(first.has_tag("hunting"))
	# The first of its kind matters more — once for each species.
	assert_true(first.is_first())
	assert_near(first.significance, 0.55, 0.001)
	clock.tick = 500
	var second := log.record(&"animal_hunted", {"species": "deer", "participants": [9], "position": Vector2(30.5, 4.5)})
	assert_false(second.is_first())
	assert_near(second.significance, 0.2, 0.001)
	clock.tick = 900
	var rabbit := log.record(&"animal_hunted", {"species": "rabbit", "participants": [7], "position": Vector2(4.0, 5.0)})
	assert_true(rabbit.is_first(), "the first rabbit")
	clock.tick = 2000
	var short := log.record(&"food_shortage", {"days": 0.2, "position": Vector2(0.5, 0.5)}, [rabbit, second.id, 999, 0, second.id])
	assert_eq(Array(short.causes), [2, 3], "ids or events, each once, only what is in the log")
	assert_eq(seen, [1, 2, 3, 4])
	assert_eq(log.size(), 4)
	# Asked for by kind, by time, by place, by person.
	assert_eq(log.of_type(&"animal_hunted").size(), 3)
	assert_eq(log.of_type(&"animal_hunted", 400, 1000).map(func(e: WorldEvent) -> int: return e.id), [2, 3])
	assert_eq(log.count_of(&"animal_hunted"), 3)
	assert_eq(log.latest(&"animal_hunted").id, 3)
	assert_null(log.latest(&"crop_failure"))
	assert_eq(log.between(0, 500).size(), 2)
	assert_eq(log.near(Vector2(3.0, 4.0), 3.0).map(func(e: WorldEvent) -> int: return e.id), [1, 3])
	assert_eq(log.involving(7).map(func(e: WorldEvent) -> int: return e.id), [1, 3])
	assert_eq(log.find({"type": "animal_hunted", "participant": 7, "from": 200}).map(func(e: WorldEvent) -> int: return e.id), [3])
	assert_eq(log.find({"tag": "hardship"}).map(func(e: WorldEvent) -> int: return e.id), [4])
	assert_eq(log.find({"min_significance": 0.5}).size(), 3)
	assert_eq(log.find({"near": Vector2(30.0, 4.0), "radius": 2.0}).map(func(e: WorldEvent) -> int: return e.id), [2])
	assert_eq(log.recent_id(&"animal_hunted", 1200), 3)
	assert_eq(log.recent_id(&"animal_hunted", 1000), 0, "too long ago")
	# What led to what.
	assert_eq(log.chain(4).map(func(e: WorldEvent) -> int: return e.id), [2, 3])
	assert_true(log.led_to(2, 4))
	assert_false(log.led_to(1, 4))
	assert_eq(log.consequences(2).map(func(e: WorldEvent) -> int: return e.id), [4])
	# The same thing again, soon after, for the same reasons: one event that happened twice.
	clock.tick = 3000
	var failed := log.record(&"crop_failure", {"position": Vector2(1.5, 1.5)}, [short])
	var merged: Array = []
	log.merged.connect(func(event: WorldEvent) -> void: merged.append(event.id))
	clock.tick = 3600
	assert_eq(log.record(&"crop_failure", {"position": Vector2(2.5, 1.5)}, [short]), failed)
	assert_eq([failed.count, failed.tick, failed.last_tick], [2, 3000, 3600])
	assert_eq(merged, [failed.id])
	assert_ne(log.record(&"crop_failure", {}, []), failed, "for other reasons: another event")
	clock.tick = 3600 + 2000
	assert_eq(log.record(&"crop_failure", {}, []).count, 1, "a day later: another event")
	# In words.
	assert_eq(EventText.text(first), "Someone brought down the first deer")
	assert_eq(EventText.text(second), "Someone brought down a deer")
	assert_eq(EventText.text(failed), "2 crops have withered in the field")
	assert_eq(EventText.line(failed), "YEAR 1 · 2 crops have withered in the field")


func test_the_log_stays_within_bounds() -> void:
	var config := EventsConfig.new()
	config.max_events = 100
	var clock := GameClock.new(Config.time)
	var log := EventLog.new()
	log.bind(clock, session.event_defs, config)
	var first_hunt := log.record(&"animal_hunted", {"species": "deer"})
	var spell := log.record(&"dry_spell", {"days": 5})
	var failure := log.record(&"crop_failure", {}, [spell])
	for i in 300:
		clock.tick += 10
		log.record(&"animal_hunted", {"species": "deer", "participants": [i]})
	assert_true(log.size() <= 100, "%d events" % log.size())
	assert_true(log.size() >= 80)
	assert_true(log.pruned >= 200)
	assert_true(log.has_event(first_hunt.id), "a first is kept")
	assert_true(log.has_event(failure.id), "what matters is kept")
	assert_true(log.has_event(spell.id), "and what led to something that is kept")
	assert_eq(log.latest(&"animal_hunted").tick, clock.tick, "the latest are kept")
	assert_false(log.record(&"animal_hunted", {"species": "deer"}).is_first(), "nothing is the first twice")
	# Nothing but what matters: then the oldest of that goes too.
	for i in 150:
		clock.tick += 2000
		log.record(&"food_shortage", {"days": 0.1})
	assert_true(log.size() <= 100)


# --- what led to what -------------------------------------------------------------------------------

func test_event_causes_recorded() -> void:
	var chain := _the_chain()
	var dry: WorldEvent = chain[0]
	var failure: WorldEvent = chain[1]
	var shortage: WorldEvent = chain[2]
	assert_not_null(dry, "three days without rain are a dry spell")
	assert_not_null(failure, "the crop withered")
	assert_not_null(shortage, "and with nothing in store there is a shortage")
	assert_true(farming.is_dry_spell())
	assert_eq(settlement.shortage, Settlement.Shortage.SHORT)
	# Each names what brought it about, recorded as it happened.
	assert_true(dry.causes.is_empty())
	assert_eq(Array(failure.causes), [dry.id], "the crop failed because of the dry spell")
	assert_true(shortage.causes.has(failure.id), "the shortage because of the failed crop: %s" % str(Array(shortage.causes)))
	assert_true(dry.tick < failure.tick and failure.tick < shortage.tick)
	assert_eq(events.chain(shortage.id).map(func(e: WorldEvent) -> int: return e.id), [dry.id, failure.id])
	assert_true(events.led_to(dry.id, shortage.id), "dry spell → crop failure → food shortage")
	# What the settlement does about it names the shortage.
	var rationing := events.latest(Chronicler.TYPE_RATIONING)
	var further := events.latest(Chronicler.TYPE_FURTHER)
	assert_eq(Array(rationing.causes), [shortage.id])
	assert_eq(Array(further.causes), [shortage.id])
	assert_true(events.led_to(dry.id, rationing.id))
	assert_eq(session.chronicle.shortage_id(), shortage.id)
	assert_eq(session.chronicle.dry_spell_id(), dry.id)
	# Where and how much.
	assert_eq(failure.position, Places.middle_of(_dry_site_of(failure)))
	assert_eq(shortage.position, settlement.fire().position2d())
	assert_true(shortage.significance >= 0.7 and failure.significance >= 0.6)
	# And it is told with its cause.
	assert_eq(EventText.text(failure, session.people, events), "A crop has withered in the dry spell")
	assert_eq(EventText.text(shortage, session.people, events), "Food is running short after the failed crop")
	assert_eq(EventText.text(dry), "No rain for 3 days: a dry spell")
	# Nothing in store for three more hours: out of food — because of the shortage.
	_hours(4)
	var empty := events.latest(Chronicler.TYPE_EMPTY)
	assert_not_null(empty)
	assert_eq(Array(empty.causes), [shortage.id])
	assert_eq(settlement.shortage, Settlement.Shortage.EMPTY)
	# Food again: it is over, and the end names what it was the end of.
	stock.add(&"berries", 60)
	_hours(1)
	assert_eq(settlement.shortage, Settlement.Shortage.NONE)
	var over := events.latest(Chronicler.TYPE_OVER)
	assert_eq(Array(over.causes), [shortage.id])
	assert_true(shortage.effects.has("ended"))
	assert_eq(session.chronicle.shortage_id(), 0)
	# Rain: the dry spell is over; a crop that fails long after it does not blame it.
	Config.farming.rain_chance = PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
	_hours(24)
	assert_false(farming.is_dry_spell())
	assert_eq(session.chronicle.dry_spell_id(), 0)
	assert_true(dry.effects.has("ended"))
	session.clock.tick += 10 * 1440
	session.chronicle.on_crop_failed(0)
	assert_true(events.latest(Chronicler.TYPE_CROP_FAILURE).causes.is_empty())


## The tile of the plot a crop failure happened on.
func _dry_site_of(failure: WorldEvent) -> Vector2i:
	return Vector2i(floori(failure.position.x), floori(failure.position.y))


func test_event_persistence() -> void:
	var chain := _the_chain()
	var dry: WorldEvent = chain[0]
	var shortage: WorldEvent = chain[2]
	assert_not_null(shortage)
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	assert_true(loaded.ok, loaded.error)
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	s.loose_system.set_process(false)
	s.water.set_process(false)
	# Every event is back as it was: kind, time, place, people, causes, text.
	assert_eq(s.events.size(), events.size())
	assert_eq(s.events.to_dict(), events.to_dict())
	assert_eq(s.chronicle.to_dict(), session.chronicle.to_dict())
	var shortage_again := s.events.get_event(shortage.id)
	assert_eq(shortage_again.type, Chronicler.TYPE_SHORTAGE)
	assert_eq(Array(shortage_again.causes), Array(shortage.causes))
	assert_true(s.events.led_to(dry.id, shortage.id), "the chain is still there")
	assert_eq(EventText.text(shortage_again, s.people, s.events), "Food is running short after the failed crop")
	# The settlement is as short of food as it was, and the weather as dry.
	assert_eq(s.settlement.shortage, Settlement.Shortage.SHORT)
	assert_true(s.settlement.is_short() and s.farming.is_dry_spell())
	assert_near(s.behavior.ctx.places.forage_reach, Config.settlement.forage_further_factor, 0.001)
	# The story goes on where it was: what happens now names what was going on then.
	var tile := Vector2i.ZERO
	for crop in s.farming.crops():
		tile = crop.tile
	var chunk := s.world.chunk_at_tile(tile)
	chunk.set_moisture(s.world.index_at_tile(tile), 10)
	s.farming.finish(Farming.CLEAR, tile, s.props.prop_at(tile).id, s.clock.tick)
	assert_not_null(s.farming.sow(tile, s.clock.tick))
	_hours(24 * 2 + 2, s)
	var failed_again := s.events.latest(Chronicler.TYPE_CROP_FAILURE)
	assert_true(failed_again.id > shortage.id, "a new event, with a number of its own")
	assert_eq(Array(failed_again.causes), [dry.id], "the dry spell from before the save")
	s.settlement.stockpile.add(&"berries", 60)
	_hours(1, s)
	assert_eq(Array(s.events.latest(Chronicler.TYPE_OVER).causes), [shortage.id])
	# Firsts stay firsts: nothing is "the first" again after a load.
	assert_false(s.events.record(&"occupation_taken_up", {"occupation": "farmer"}).is_first())
	s.queue_free()


# --- what is written down -----------------------------------------------------------------------------

func test_a_new_world_begins_its_history() -> void:
	var all := events.all_events()
	assert_true(all.size() >= 3)
	var founded := all[0]
	assert_eq(founded.type, Chronicler.TYPE_FOUNDED, "the first entry")
	assert_eq(founded.participants.size(), 8)
	assert_eq(founded.position, settlement.fire().position2d())
	assert_eq(EventText.text(founded, session.people, events), "A band of 8 has settled by the fire")
	# Someone took up farming, someone hunting: the first of each.
	var trades := {}
	for event in events.of_type(Chronicler.TYPE_TOOK_UP):
		trades[event.text_params["occupation"]] = event
		assert_true(event.is_first())
		assert_eq(event.participants.size(), 1)
	assert_eq(trades.size(), 2, str(trades.keys()))
	var farmer := session.people.get_person((trades["farmer"] as WorldEvent).participants[0])
	assert_eq(farmer.occupation_id, &"farmer")
	assert_eq(EventText.text(trades["farmer"], session.people, events), "%s is the settlement's first farmer" % farmer.given_name)
	# What it was given to begin with is no event: nothing stored, nothing discovered yet.
	assert_eq(events.count_of(Chronicler.TYPE_FIRST_STORAGE), 0)
	assert_eq(events.count_of(Chronicler.TYPE_DISCOVERED), 0)
	# The first thing put in store; what it already had is no discovery, what is new is.
	stock.add(&"berries", 3)
	var stored := events.latest(Chronicler.TYPE_FIRST_STORAGE)
	assert_not_null(stored)
	assert_eq(stored.text_params["resource"], "berries")
	assert_eq(events.count_of(Chronicler.TYPE_DISCOVERED), 0)
	stock.add(&"meat", 2)
	var found := events.latest(Chronicler.TYPE_DISCOVERED)
	assert_eq(found.text_params["resource"], "meat")
	assert_eq(EventText.text(found, session.people, events), "The settlement has its first meat")
	assert_true(found.position.distance_to(stock.place(&"meat")) < 2.0)
	stock.add(&"meat", 2)
	stock.add(&"berries", 2)
	assert_eq([events.count_of(Chronicler.TYPE_FIRST_STORAGE), events.count_of(Chronicler.TYPE_DISCOVERED)], [1, 1])
	# The first field.
	assert_eq(events.count_of(Chronicler.TYPE_FIRST_FARM), 0)
	var tile: Vector2i = farming.next_plot()
	farming.sow(tile, session.clock.tick)
	var farm := events.latest(Chronicler.TYPE_FIRST_FARM)
	assert_eq(farm.position, Places.middle_of(tile))
	assert_eq(Array(farm.participants), [farmer.id])
	assert_eq(EventText.text(farm, session.people, events), "%s has sown the first field" % farmer.given_name)
	farming.sow(farming.next_plot(), session.clock.tick)
	assert_eq(events.count_of(Chronicler.TYPE_FIRST_FARM), 1)
	# A kill: the first deer is something; the next one is a day's work.
	var hunter: PersonData = null
	for p in session.people.all_people():
		if p.occupation_id == &"hunter":
			hunter = p
	behavior.hunted.emit(hunter.id, &"deer")
	behavior.hunted.emit(hunter.id, &"deer")
	var hunts := events.of_type(Chronicler.TYPE_HUNTED)
	assert_eq(hunts.size(), 2)
	assert_true(hunts[0].is_first() and not hunts[1].is_first())
	assert_eq(EventText.text(hunts[0], session.people, events), "%s brought down the first deer" % hunter.given_name)
	assert_eq(hunts[0].position, hunter.world2d())
	# Food going bad, the fire going out and being lit again.
	settlement.spoiled.emit(&"berries", 4)
	assert_eq(events.latest(Chronicler.TYPE_SPOILED).text_params, {"resource": "berries", "units": 4})
	settlement.fire_changed.emit(false)
	settlement.fire_changed.emit(true)
	assert_eq(Array(events.latest(Chronicler.TYPE_FIRE_RELIT).causes), [events.latest(Chronicler.TYPE_FIRE_OUT).id])
	# The bushes picked bare, and with berries again.
	for prop in session.props.all_props():
		if prop.kind == PropData.Kind.BUSH:
			session.nodes.take(prop.id, 1000, session.clock.tick)
	assert_near(settlement.bare_share(), 1.0, 0.001)
	_hours(2)
	assert_true(settlement.forage_low)
	var bare := events.latest(Chronicler.TYPE_FORAGE)
	assert_not_null(bare)
	assert_true(session.chronicle.shortage_causes().has(bare.id), "what a shortage now would be put down to")
	# Every event has a text.
	for event in events.all_events():
		assert_false(EventText.text(event, session.people, events).contains("{"), "%s: %s" % [event.type, EventText.text(event, session.people, events)])
		assert_ne(EventText.text(event, session.people, events), "Something happened", String(event.type))


func test_what_the_player_does_is_written_down() -> void:
	var before := events.size()
	var person := session.people.all_people()[0]
	person.set_flag(PersonData.FLAG_INDOORS, false)
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = person.id
	target.entity_kind = SpatialIndex.KIND_PERSON
	target.tile = person.position
	target.direct = true
	session.interactions.tap(target)
	assert_eq(events.size(), before + 1)
	var touch := events.latest(Chronicler.TYPE_PLAYER)
	assert_eq([touch.text_params["kind"], touch.text_params["subject"]], ["touch", "person"])
	assert_eq(Array(touch.participants), [person.id])
	assert_eq(touch.visibility, WorldEvent.Visibility.PLAYER, "nobody in the box knows who did it")
	assert_near(touch.significance, 0.1, 0.001)
	assert_eq(touch.text_params["intervention"], session.history.peek_next_id() - 1, "the same act as in the player's history")
	assert_false(session.event_defs.get_def(Chronicler.TYPE_PLAYER).toast, "the player is not told what the player did")
	# The same gentle thing again and again is one event.
	session.interactions.tap(target)
	session.interactions.tap(target)
	assert_eq(events.size(), before + 1)
	assert_eq(touch.count, 3)
	assert_true(EventText.text(touch, session.people, events).begins_with("You touched"), EventText.text(touch, session.people, events))
	assert_true(EventText.text(touch, session.people, events).ends_with("(3 times)"))
	# A tree torn out is another kind of thing, and matters more.
	var tree: PropData = null
	for prop in session.props.all_props():
		if prop.kind == PropData.Kind.TREE:
			tree = prop
			break
	var at := Picker.Result.new()
	at.kind = Picker.Kind.ENTITY
	at.entity_id = tree.id
	at.tile = tree.tile
	session.interactions.uproot(at)
	var uprooted := events.latest(Chronicler.TYPE_PLAYER)
	assert_ne(uprooted, touch)
	assert_eq(uprooted.text_params["kind"], "uproot")
	assert_true(uprooted.significance >= 0.35)
	assert_true(uprooted.position.distance_to(Vector2(tree.tile) + Vector2(0.5, 0.5)) < 1.0)


## The manual check of the plan, as a test: "starve the settlement by moving
## all food piles away → shortage events → responses".
func test_food_carried_off_by_the_player_is_what_the_shortage_is_put_down_to() -> void:
	var store := stock.place(&"berries")
	var taken := 0
	for pile in session.piles.piles(&"berries", store, Config.resources.storage_radius).duplicate():
		assert_true(session.interactions.grab(pile.id))
		session.interactions.carry(pile.id, pile.position + Vector2(9.0, 6.0), 0.5)
		assert_true(session.interactions.release(pile.id).applied)
		taken += 1
	for i in 30:
		session.loose_system.step(0.1)
	assert_true(taken >= 1)
	assert_eq(stock.food_units(), 0, "the stores are what lies at the storage place")
	var carried := events.latest(Chronicler.TYPE_PLAYER)
	assert_eq([carried.text_params["kind"], carried.text_params["subject"]], ["move_object", "pile"])
	assert_true(bool(carried.text_params.get("food", false)))
	assert_eq(carried.text_params["resource"], "berries")
	assert_true(carried.significance >= 0.35)
	_hours(4)
	var shortage := events.latest(Chronicler.TYPE_SHORTAGE)
	assert_not_null(shortage)
	assert_true(shortage.causes.has(carried.id))
	assert_eq(EventText.text(shortage, session.people, events), "Food is running short: the stores have been carried off")
	assert_eq(Array(events.latest(Chronicler.TYPE_RATIONING).causes), [shortage.id])
	# Wood carried off is no cause of hunger.
	for pile in session.piles.piles(&"wood", stock.place(&"wood"), Config.resources.storage_radius).duplicate():
		session.interactions.grab(pile.id)
		session.interactions.carry(pile.id, pile.position + Vector2(-9.0, 6.0), 0.5)
		session.interactions.release(pile.id)
	assert_false(bool(events.latest(Chronicler.TYPE_PLAYER).text_params.get("food", false)))


# --- the numbers ----------------------------------------------------------------------------------------

func test_the_worlds_numbers_are_written_down_every_hour() -> void:
	var stats := session.stats
	assert_eq(stats.sample_count(), 0)
	var now := session.sample_stats()
	assert_eq(now[&"population"], 8.0)
	assert_near(now[&"food"], stock.food(), 0.001)
	assert_eq(now[&"wood"], float(stock.amount(&"wood")))
	assert_eq(now[&"stone"], 0.0)
	assert_true(now[&"water"] > 10.0, "the river")
	assert_true(now[&"health"] > 0.6 and now[&"health"] <= 1.0)
	assert_true(now[&"mood"] > 0.0 and now[&"mood"] <= 1.0)
	# One sample an hour, however often it is asked.
	assert_true(stats.advance_to(session.clock.tick))
	assert_false(stats.advance_to(session.clock.tick + 30))
	assert_true(stats.advance_to(session.clock.tick + 60))
	assert_eq(stats.sample_count(), 2)
	assert_eq(Array(stats.ticks()), [session.clock.tick, session.clock.tick + 60])
	assert_eq(stats.latest()[&"population"], 8.0)
	stock.take(&"wood", 2)
	session.people.all_people()[0].health = 0.1
	assert_true(stats.advance_to(session.clock.tick + 120))
	assert_eq(stats.series(&"wood")[-1], stats.series(&"wood")[0] - 2.0)
	assert_true(stats.series(&"health")[-1] < stats.series(&"health")[0])
	assert_eq(stats.range_of(&"wood"), [stats.series(&"wood")[-1], stats.series(&"wood")[0]])
	# A clock set far ahead: one sample, not one for every hour nobody counted.
	var counted := [0]
	var far := StatsRecorder.new()
	far.source = func() -> Dictionary:
		counted[0] += 1
		return {&"population": 3.0}
	assert_true(far.advance_to(0))
	assert_true(far.advance_to(100 * 1440))
	assert_eq([far.sample_count(), counted[0]], [2, 2])
	# The oldest go when there is no more room.
	var small := EventsConfig.new()
	small.max_samples = 24
	var ring := StatsRecorder.new(small)
	for hour in 100:
		ring.add_sample(hour * 60, {&"population": float(hour)})
	assert_eq(ring.sample_count(), 24)
	assert_eq([ring.ticks()[0], ring.ticks()[-1]], [76 * 60, 99 * 60])
	assert_eq(ring.series(&"population")[0], 76.0)
	# Saved with the world.
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	assert_eq(s.stats.sample_count(), 3)
	assert_eq(s.stats.to_dict(), stats.to_dict())
	assert_false(s.stats.advance_to(session.clock.tick + 130), "it knows when it last looked")
	assert_false(StatsRecorder.new().from_dict({"ticks": "nonsense"}), "unusable: empty, and said so")
	s.queue_free()
	# The game takes them as the clock runs.
	session.clock.tick += 185
	session.set_process(true)
	await wait_frames(2)
	session.set_process(false)
	assert_eq(stats.sample_count(), 4)


# --- an older save ----------------------------------------------------------------------------------------

func test_version_12_save_begins_its_history() -> void:
	var dir := SaveManager.world_dir(V12_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V12_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 12)
	var loaded := SaveManager.load_world(V12_ID)
	assert_true(loaded.ok, loaded.error)
	assert_eq(loaded.world["world_state"]["events"], {})
	assert_eq(loaded.world["world_state"]["chronicle"], {"adopt": true})
	assert_eq(loaded.world["world_state"]["stats"], {})
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	s.loose_system.set_process(false)
	s.water.set_process(false)
	# Nothing of its past is written down; it is as it was.
	assert_eq(s.events.size(), 0)
	assert_eq(s.stats.sample_count(), 0)
	assert_eq(s.people.size(), 8)
	assert_eq(s.settlement.shortage, Settlement.Shortage.NONE)
	assert_true(s.settlement.stockpile.amount(&"berries") > 0 and s.settlement.stockpile.amount(&"wood") > 0)
	# What it has in store is not discovered a second time; what is new is.
	s.settlement.stockpile.add(&"berries", 2)
	s.settlement.stockpile.add(&"wood", 1)
	assert_eq(s.events.size(), 0)
	s.settlement.stockpile.add(&"grain", 3)
	assert_eq(s.events.size(), 1)
	assert_eq(s.events.latest(Chronicler.TYPE_DISCOVERED).text_params["resource"], "grain")
	# From now on its history is kept.
	_empty_food(s)
	_hours(5, s)
	assert_eq(s.events.count_of(Chronicler.TYPE_SHORTAGE), 1)
	# Saved again: the current version, the old file kept; and read back with its history.
	assert_true(SaveManager.save_world(s, &"test"))
	assert_true(SaveManager.SAVE_VERSION >= 13)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav.bak1")).header["save_version"], 12)
	var again := SaveManager.load_world(V12_ID)
	assert_true(again.ok, again.error)
	var s2: WorldSession = SessionScript.new()
	add_child(s2)
	assert_true(s2.load_from(again.world))
	s2.set_process(false)
	assert_eq(s2.events.to_dict(), s.events.to_dict())
	assert_eq(s2.settlement.shortage, Settlement.Shortage.SHORT)
	s2.settlement.stockpile.add(&"grain", 3)
	assert_eq(s2.events.count_of(Chronicler.TYPE_DISCOVERED), 1, "not adopted a second time")
	s.queue_free()
	s2.queue_free()
	# The step itself.
	assert_eq(SaveMigrations._v12_to_v13({"world": {"world_state": {}}})["world"]["world_state"], {})
	var kept: Dictionary = SaveMigrations._v12_to_v13({"world": {"world_state": {"people": {}, "events": {"next_id": 5}}}})
	assert_eq(kept["world"]["world_state"]["events"], {"next_id": 5})
	assert_eq(kept["world"]["world_state"]["chronicle"], {"adopt": true})
