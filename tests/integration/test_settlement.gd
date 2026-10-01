extends TestCase
## The settlement, its stockpile and its job board (M7.2): who and what
## belongs to it, what it has in store, eating from the stores (and from
## the bushes when they are empty), food going bad, the fire burning its
## wood, and the board that calls people to work.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const V9_FIXTURE := "res://tests/fixtures/saves/v9_world.sav"
const V9_ID := "w1790887417_3964530d"

var session: WorldSession
var behavior: BehaviorSystem
var ctx: AiContext
var settlement: Settlement
var stock: Stockpile
var board: JobBoard
var piles: PileStore
var config: SettlementConfig


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
	board = settlement.jobs
	piles = session.piles
	config = Config.settlement


func after_each() -> void:
	var fresh := SettlementConfig.new()
	Config.settlement.fire_wood_per_day = fresh.fire_wood_per_day
	Config.settlement.urgent_from = fresh.urgent_from
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
	person.food_in_hand = 0.0
	return person


func _only(people: Array) -> void:
	for p in session.people.all_people():
		if not people.has(p):
			behavior.set_plan(p, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(1000000.0)])


func _empty_stores() -> void:
	for pile in piles.piles():
		session.loose.remove(pile.id)
	board.refresh(settlement, session.clock.tick)


func _refresh() -> void:
	board.refresh(settlement, session.clock.tick)


func _fire_out_of_the_way() -> void:
	Config.settlement.fire_wood_per_day = 0.01


# --- who and what ---------------------------------------------------------------------------------

func test_a_settlement_is_its_people_and_what_they_have() -> void:
	assert_not_null(settlement)
	assert_eq(settlement.id, session.start.settlement_id)
	assert_ne(settlement.id, 0)
	assert_eq(ctx.settlement, settlement, "people's minds know it")
	# Everyone of the first band lives here, in their households.
	var members := settlement.members()
	assert_eq(members.size(), session.people.size())
	assert_eq(settlement.member_count(), 8)
	var households := settlement.households()
	assert_eq(households.size(), session.people.household_ids().size())
	var counted := 0
	for household: int in households:
		counted += (households[household] as PackedInt64Array).size()
		for id: int in households[household]:
			assert_eq(session.people.get_person(id).household_id, household)
	assert_eq(counted, members.size(), "everyone in exactly one")
	# Its buildings: the fire and the huts.
	var buildings := settlement.buildings()
	assert_eq(buildings.size(), 1 + session.start.hut_ids.size())
	assert_eq(buildings[0], settlement.fire())
	assert_eq(settlement.fire().kind, PropData.Kind.CAMPFIRE)
	assert_true(settlement.fire_lit())
	# A new settlement begins with something by the fire: a day of food, some wood.
	var need := settlement.food_need_per_day()
	assert_near(need, 8 * config.food_per_person_day, 0.001)
	assert_eq(stock.amounts(), {&"berries": ceili(need * config.starting_food_days / 0.65), &"wood": config.starting_wood})
	assert_near(settlement.days_of_food(), config.starting_food_days, 0.06)
	assert_eq(piles.piles().size(), 2)
	assert_true(piles.piles(&"berries")[0].position.distance_to(session.storage_place(&"berries")) < 0.6)
	# Someone who leaves is no longer of it; a newcomer is.
	var gone := members[0]
	session.people.remove(gone.id)
	assert_eq(settlement.member_count(), 7)
	assert_near(settlement.food_need_per_day(), 7 * config.food_per_person_day, 0.001)
	var newcomer := session.spawn_person(session.start.settlement_tile)
	assert_true(settlement.members().has(newcomer))
	assert_has(settlement.debug_text(), "8 people in")
	assert_has(settlement.debug_text(), "fire burning")
	# The numbers.
	assert_eq(config.validate().size(), 0)
	assert_eq(Config.problems.size(), 0, str(Config.problems))
	var broken := SettlementConfig.new()
	broken.work_without_jobs = 1.5
	broken.food_per_person_day = 0.0
	assert_eq(broken.validate().size(), 2)
	# What a day's food is worth: about what a person's hunger takes in a day.
	var per_day := Config.needs.hunger_per_minute * (16.0 * 60.0 * 1.1 + 8.0 * 60.0 * Config.needs.sleeping_factor)
	assert_near(config.food_per_person_day, per_day, 0.25, "food_per_person_day follows the needs (%.2f)" % per_day)
	for id in session.resources.of_category(ResourceDef.Category.FOOD):
		assert_true(session.resources.get_def(id).nutrition > 0.0, "%s feeds" % id)
	assert_eq(session.resources.get_def(&"wood").nutrition, 0.0)


func test_the_stockpile_is_what_lies_at_the_storage_place() -> void:
	_empty_stores()
	assert_eq(stock.amounts(), {})
	assert_eq(stock.amount(&"wood"), 0)
	assert_eq(stock.food_units(), 0)
	assert_eq(stock.food(), 0.0)
	assert_eq(stock.take_food(), &"")
	assert_eq(stock.take(&"wood", 3), 0)
	assert_eq(stock.place(&"wood"), session.storage_place(&"wood"))
	# Put in, counted.
	stock.add(&"wood", 10)
	stock.add(&"berries", 12)
	stock.add(&"grain", 5)
	assert_eq(stock.amounts(), {&"wood": 10, &"berries": 12, &"grain": 5})
	assert_eq(stock.food_units(), 17)
	assert_near(stock.food(), 12 * 0.65 + 5 * 1.0, 0.001)
	assert_eq(stock.debug_text(), "berries 12 grain 5 wood 10")
	assert_eq(stock.room(&"wood"), Config.resources.piles_per_resource * 16 - 10)
	# Taken out.
	assert_eq(stock.take(&"wood", 4), 4)
	assert_eq(stock.amount(&"wood"), 6)
	assert_eq(stock.take(&"wood", 100), 6)
	assert_eq(stock.amount(&"wood"), 0)
	# Food: what goes bad soonest is eaten first.
	assert_eq(stock.take_food(), &"berries")
	assert_eq(stock.amount(&"berries"), 11)
	stock.add(&"fish", 2)
	assert_eq(stock.take_food(), &"fish", "fish keeps two days")
	assert_eq(stock.take_food(), &"fish")
	assert_eq(stock.take_food(), &"berries")
	stock.take(&"berries", 100)
	assert_eq(stock.take_food(), &"grain", "grain last: it keeps")
	# The count follows what really lies there: a pile carried off is gone from it...
	stock.add(&"berries", 9)
	var pile := piles.piles(&"berries")[0]
	session.loose.move(pile.id, pile.position + Vector2(7.0, 0.0))
	assert_eq(stock.amount(&"berries"), 0)
	assert_eq(piles.total(&"berries"), 9)
	# ...and one put back is in it again.
	session.loose.move(pile.id, session.storage_place(&"berries") + Vector2(0.2, 0.1))
	assert_eq(stock.amount(&"berries"), 9)
	session.loose.remove(pile.id)
	assert_eq(stock.amount(&"berries"), 0)
	# Something that is not a pile, or lies elsewhere, is not in store.
	piles.add(&"wood", 5, session.storage_place(&"wood") + Vector2(9.0, 9.0))
	assert_eq(stock.amount(&"wood"), 0)


# --- eating ---------------------------------------------------------------------------------------

func test_consumption() -> void:
	# Eating reduces stock: what a meal restores is taken from the stores.
	_fire_out_of_the_way()
	_set_hour(12.2)
	var person := _calm(_adult())
	_only([person])
	_empty_stores()
	stock.add(&"berries", 20)
	person.needs[Needs.Need.HUNGER] = 0.3
	var steps := Planner.plan(&"eat", person, ctx)
	assert_eq(steps.size(), 2)
	assert_false(steps[1].has("bush"), "from the stores, at the fire")
	behavior.set_plan(person, &"eat", &"hunger", steps, 2.0)
	var waited := 0.0
	while person.pose != PersonData.Pose.EAT and waited < 120.0:
		_run(0.5)
		waited += 0.5
	assert_true(stock.amount(&"berries") >= 19, "nothing is taken before they sit down to it")
	while BehaviorSystem.activity_of(person) == &"eat" and waited < 240.0:
		_run(0.5)
		waited += 0.5
	var fed := Needs.value(person.needs, Needs.Need.HUNGER)
	assert_true(fed > 0.97, "fed (%.2f)" % fed)
	# Some 0.7 of a belly at 0.65 a unit: two units — and what is left of the
	# second is kept, not thrown away.
	assert_eq(stock.amount(&"berries"), 18, "the stockpile has less")
	assert_true(person.food_in_hand > 0.3 and person.food_in_hand < 0.65, "the rest of the second (%.2f)" % person.food_in_hand)
	# The next time they are hungry it is eaten first.
	behavior.set_plan(person, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(1000000.0)])
	var in_store := stock.amount(&"berries")
	person.needs[Needs.Need.HUNGER] = 0.6
	person.food_in_hand = 0.65
	var eating := EatStep.new()
	var snack := EatStep.make(settlement.fire().tile)
	var took := 0
	while eating.update(ctx, person, snack, 1.0) == ActionStep.Status.RUNNING and took < 60:
		took += 1
	assert_true(Needs.value(person.needs, Needs.Need.HUNGER) > 0.97)
	assert_eq(stock.amount(&"berries"), in_store, "what was in hand was enough")
	assert_near(person.food_in_hand, 0.65 - 0.4, 0.05)
	assert_eq(in_store, 18)
	# It is saved with them.
	person.food_in_hand = 0.4
	assert_near(PersonData.from_dict(bytes_to_var(var_to_bytes(person.to_dict()))).food_in_hand, 0.4, 0.0001)
	# Someone who is not hungry sits through a meal without taking anything.
	person.needs[Needs.Need.HUNGER] = 1.0
	person.food_in_hand = 0.0
	var handler := EatStep.new()
	var meal := EatStep.make(settlement.fire().tile, true)
	for i in 10:
		assert_eq(handler.update(ctx, person, meal, 1.0), ActionStep.Status.RUNNING)
	assert_eq(stock.amount(&"berries"), 18)
	# The last of the food: whoever is still hungry stops eating.
	stock.take(&"berries", 1000)
	stock.add(&"berries", 1)
	person.needs[Needs.Need.HUNGER] = 0.1
	var bite := EatStep.make(settlement.fire().tile)
	var status := ActionStep.Status.RUNNING
	var minutes := 0
	while status == ActionStep.Status.RUNNING and minutes < 60:
		status = handler.update(ctx, person, bite, 1.0)
		minutes += 1
	assert_eq(stock.amount(&"berries"), 0)
	assert_true(bool(bite.get("empty", false)), "the stores ran out under them")
	assert_near(Needs.value(person.needs, Needs.Need.HUNGER), 0.1 + 0.65, 0.05, "one unit's worth")
	assert_true(minutes < 25, "and they do not sit before nothing")


func test_with_empty_stores_people_eat_from_the_bushes() -> void:
	_fire_out_of_the_way()
	_set_hour(15.0)
	var person := _calm(_adult())
	_only([person])
	_empty_stores()
	person.needs[Needs.Need.HUNGER] = 0.2
	assert_true(Planner.can(&"food", person, ctx), "there are berries on the bushes")
	var steps := Planner.plan(&"eat", person, ctx)
	assert_eq(steps.size(), 2)
	assert_true(steps[1].has("bush"))
	var bush := session.props.get_prop(int(steps[1]["bush"]))
	assert_eq(bush.kind, PropData.Kind.BUSH)
	assert_eq(steps[0]["target"], bush.tile)
	var full := session.nodes.capacity(bush)
	session.day_log.forget(person.id)
	behavior.set_plan(person, &"eat", &"hunger", steps, 2.0)
	assert_eq(session.day_log.of(person.id)[-1].slice(1), ["eat", "bush", 0])
	assert_eq(DayLogText.text(session.day_log.of(person.id)[-1]), "eats berries off a bush")
	var waited := 0.0
	while BehaviorSystem.activity_of(person) == &"eat" and waited < 180.0:
		_run(0.5)
		waited += 0.5
	assert_true(Needs.value(person.needs, Needs.Need.HUNGER) > 0.8, "fed (%.2f)" % Needs.value(person.needs, Needs.Need.HUNGER))
	assert_true(session.nodes.left(bush) <= full - 1, "the bush has fewer (%d of %d)" % [session.nodes.left(bush), full])
	assert_eq(stock.food_units(), 0, "nothing came from the stores")
	# With food in the stores again, meals are at the fire.
	stock.add(&"berries", 10)
	person.needs[Needs.Need.HUNGER] = 0.2
	assert_false(Planner.plan(&"eat", person, ctx)[1].has("bush"))
	# No food in store and no berry on any bush: there is nothing to eat.
	_empty_stores()
	person.food_in_hand = 0.0
	for prop in session.props.all_props():
		if prop.kind == PropData.Kind.BUSH:
			session.nodes.take(prop.id, 1000, session.clock.tick)
	assert_true(ctx.places.forage_place(person, ctx.rng).is_empty())
	assert_false(Planner.can(&"food", person, ctx))
	assert_eq(Planner.plan(&"eat", person, ctx), [])
	assert_eq(Brain.score(session.activities.get_def(&"eat"), person, ctx), -1.0, "it does not even occur to them")
	# A morsel still in hand is something.
	person.food_in_hand = 0.3
	assert_true(Planner.can(&"food", person, ctx))


# --- spoiling -------------------------------------------------------------------------------------

func test_spoilage() -> void:
	_empty_stores()
	var berries := session.resources.get_def(&"berries")
	assert_eq(berries.spoil_days, 8.0)
	stock.add(&"berries", 24)
	stock.add(&"wood", 10)
	var pile := piles.piles(&"berries")[0]
	# A day: an eighth of the berries. Wood keeps.
	assert_eq(piles.spoil(1.0), {&"berries": 3})
	assert_eq(pile.amount, 21)
	assert_eq(stock.amount(&"wood"), 10)
	assert_near(pile.spoil, 0.0, 0.0001)
	# Whole units go; what is left over of one counts towards the next day.
	assert_eq(piles.spoil(1.0), {&"berries": 2})
	assert_eq(pile.amount, 19)
	assert_near(pile.spoil, 0.625, 0.0001)
	assert_eq(piles.spoil(1.0), {&"berries": 3}, "19/8 and what was left over")
	assert_eq(pile.amount, 16)
	assert_near(pile.spoil, 0.0, 0.0001)
	assert_true(pile.scale_percent < PileStore.scale_for(24, berries.stack), "the heap has shrunk")
	# How far a unit has gone is saved with the pile.
	piles.spoil(0.5)
	assert_eq(pile.amount, 15)
	var again := LooseObject.from_dict(bytes_to_var(var_to_bytes(pile.to_dict())))
	assert_near(again.spoil, pile.spoil, 0.0001)
	assert_eq(again.amount, 15)
	# A single berry lasts its eight days, then the pile is gone.
	_empty_stores()
	stock.add(&"berries", 1)
	for day in 7:
		assert_eq(piles.spoil(1.0), {})
	assert_eq(stock.amount(&"berries"), 1)
	assert_eq(piles.spoil(1.0), {&"berries": 1})
	assert_eq(piles.piles(&"berries").size(), 0)
	# It happens by itself, once for every day that passes, wherever the pile lies.
	_fire_out_of_the_way()
	stock.add(&"berries", 16)
	piles.add(&"fish", 12, session.storage_place(&"fish") + Vector2(10.0, 3.0)) # (left lying somewhere)
	var lost: Array = []
	settlement.spoiled.connect(func(resource: StringName, amount: int) -> void: lost.append([resource, amount]))
	session.clock.tick = 100
	settlement.step(session.clock.tick)
	assert_eq(lost, [], "the day is not over")
	session.clock.tick = 17 * 60 + 59 # (a minute before midnight: the first day began at six)
	settlement.step(session.clock.tick)
	assert_eq(lost, [])
	session.clock.tick += 2
	settlement.step(session.clock.tick)
	assert_eq(lost.size(), 2, "at midnight")
	assert_true(lost.has([&"berries", 2]) and lost.has([&"fish", 6]), str(lost))
	assert_eq(stock.amount(&"berries"), 14)
	assert_eq(piles.total(&"fish"), 6, "fish keeps two days")
	settlement.step(session.clock.tick + 300)
	assert_eq(lost.size(), 2, "once a day")
	# Days missed are made up for (a clock set ahead), but not without end.
	lost.clear()
	session.clock.tick += 3 * 1440
	settlement.step(session.clock.tick)
	assert_true(piles.total(&"fish") <= 1, "all but gone (%d)" % piles.total(&"fish"))
	assert_true(stock.amount(&"berries") <= 10 and stock.amount(&"berries") >= 8, "three more days (%d)" % stock.amount(&"berries"))
	# The settlement remembers which day it is at across a save.
	var data: Dictionary = bytes_to_var(var_to_bytes(session.to_dict()))
	var loaded: WorldSession = SessionScript.new()
	add_child(loaded)
	assert_true(loaded.load_from(data))
	loaded.set_process(false)
	var before := loaded.settlement.stockpile.amount(&"berries")
	loaded.settlement.step(loaded.clock.tick + 10)
	assert_eq(loaded.settlement.stockpile.amount(&"berries"), before, "not spoiled twice for the same day")
	loaded.queue_free()


# --- the fire -------------------------------------------------------------------------------------

func test_the_fire_burns_wood_and_goes_out_without_it() -> void:
	_empty_stores()
	stock.add(&"berries", 60) # (so that nobody has to go foraging meanwhile)
	stock.add(&"wood", 2)
	var fire := settlement.fire()
	var changes: Array = []
	settlement.fire_changed.connect(func(lit: bool) -> void: changes.append(lit))
	var chunks: Array = []
	session.props.chunk_changed.connect(func(coord: Vector2i) -> void: chunks.append(coord))
	assert_eq(config.fire_wood_per_day, 6.0)
	var per_log := 240
	session.clock.tick = 1000
	settlement.step(1000)
	assert_eq(stock.amount(&"wood"), 2, "a log lasts a while")
	settlement.step(1000 + per_log - 1)
	assert_eq(stock.amount(&"wood"), 2)
	settlement.step(1000 + per_log)
	assert_eq(stock.amount(&"wood"), 1, "one on the fire")
	settlement.step(1000 + per_log * 2)
	assert_eq(stock.amount(&"wood"), 0)
	assert_true(settlement.fire_lit(), "the last one burns")
	assert_eq(changes, [])
	# Nothing to put on: it goes out.
	settlement.step(1000 + per_log * 3)
	assert_false(settlement.fire_lit())
	assert_eq(changes, [false])
	assert_eq(fire.stock, 0)
	assert_eq(ResourceNodes.look_of(fire), ResourceNodes.Look.BARE)
	assert_eq(chunks, [WorldCoords.tile_to_chunk(fire.tile, session.world.chunk_size)], "drawn again, without its flame")
	assert_has(settlement.debug_text(), "fire OUT")
	settlement.step(1000 + per_log * 5)
	assert_eq(changes, [false], "out is out")
	# What it looks like and what the player is told.
	var library := PropMeshLibrary.new()
	var burning := library.template_for(PropData.Kind.CAMPFIRE, 0)
	var cold := library.template_for(PropData.Kind.CAMPFIRE, 0, ResourceNodes.Look.BARE)
	assert_true(cold.triangle_count() < burning.triangle_count(), "no flame")
	var glows := false
	for i in cold.vertices.size():
		glows = glows or cold.glow_of(i) > 0.0
	assert_false(glows, "nothing shines")
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = fire.id
	target.tile = fire.tile
	var report := session.interactions.inspect(target)
	assert_eq(report.look, ResourceNodes.Look.BARE)
	assert_eq(UIText.node_name(PropData.Kind.CAMPFIRE, 0, report.look), "Cold fire")
	# A cold fire is saved as one.
	var data: Dictionary = bytes_to_var(var_to_bytes(session.to_dict()))
	var loaded: WorldSession = SessionScript.new()
	add_child(loaded)
	assert_true(loaded.load_from(data))
	loaded.set_process(false)
	assert_false(loaded.settlement.fire_lit())
	loaded.queue_free()
	# Wood arrives: it is lit again at once, and burns on from then.
	var now := 1000 + per_log * 5 + 17
	stock.add(&"wood", 3)
	settlement.step(now)
	assert_true(settlement.fire_lit())
	assert_eq(changes, [false, true])
	assert_eq(fire.stock, -1)
	assert_eq(stock.amount(&"wood"), 2, "the first piece is on it")
	settlement.step(now + per_log - 1)
	assert_eq(stock.amount(&"wood"), 2)
	settlement.step(now + per_log)
	assert_eq(stock.amount(&"wood"), 1)
	assert_eq(UIText.node_name(PropData.Kind.CAMPFIRE, 0, ResourceNodes.look_of(fire)), UIText.prop_name(PropData.Kind.CAMPFIRE, 0))
	# A long time at once (the clock set ahead) burns what there is and no more.
	stock.add(&"wood", 4)
	settlement.step(now + per_log * 40)
	assert_eq(stock.amount(&"wood"), 0)
	assert_false(settlement.fire_lit())
	# A fire that burns nothing never goes out.
	Config.settlement.fire_wood_per_day = 0.0
	stock.add(&"wood", 1)
	settlement.step(now + per_log * 41)
	settlement.step(now + per_log * 400)
	assert_eq(stock.amount(&"wood"), 1)


# --- the job board --------------------------------------------------------------------------------

func test_the_board_posts_what_runs_low() -> void:
	_fire_out_of_the_way()
	Config.settlement.fire_wood_per_day = 6.0 # (wanted as usual; nothing is stepped here)
	var posted: Array = []
	var closed: Array = []
	board.posted.connect(func(job: JobBoard.Job) -> void: posted.append(job.describe()))
	board.closed.connect(func(job: JobBoard.Job) -> void: closed.append(job.resource))
	# As a new settlement stands: a day of food of the two wanted, a third of the wood.
	_refresh()
	var food_wanted := settlement.food_need_per_day() * config.food_days_wanted
	var wood_wanted := config.fire_wood_per_day * config.wood_days_wanted
	assert_eq(board.jobs().size(), 5, "berries, meat, wood, the fire and the field")
	var food_job := board.job_for(&"berries")
	var wood_job := board.job_for(&"wood")
	assert_eq(food_job.kind, JobBoard.GATHER)
	assert_eq(food_job.node, ResourceNodes.BUSH)
	assert_near(food_job.wanted, food_wanted, 0.001)
	assert_near(food_job.have, stock.food(), 0.001)
	assert_near(food_job.priority, 1.0 - stock.food() / food_wanted, 0.001)
	assert_near(food_job.priority, 0.5, 0.03)
	assert_eq(wood_job.node, ResourceNodes.TREE)
	assert_near(wood_job.priority, 1.0 - config.starting_wood / wood_wanted, 0.001)
	for i in range(1, board.jobs().size()):
		assert_true(board.jobs()[i - 1].priority >= board.jobs()[i].priority, "the most pressing first")
	assert_true(board.wants(&"wood") and board.wants(&"berries"))
	assert_false(board.wants(&"stone"))
	var tend: JobBoard.Job = null
	for job in board.jobs():
		if job.kind == JobBoard.TEND:
			tend = job
	assert_eq([tend.node, tend.priority], [&"fire", config.fire_job_priority])
	assert_has(board.debug_text(), "wood 0.67 (6 of 18)")
	# Nothing in store: as pressing as can be.
	_empty_stores()
	assert_eq(board.job_for(&"berries").priority, 1.0)
	assert_eq(board.job_for(&"wood").priority, 1.0)
	assert_eq(board.job_for(&"berries").id, food_job.id, "the same job, more pressing")
	assert_eq(board.job_for(&"berries").posted_tick, food_job.posted_tick)
	# Enough in store: the job is taken down. Any food counts.
	stock.add(&"wood", 18)
	stock.add(&"grain", ceili(food_wanted))
	_refresh()
	assert_false(board.wants(&"wood"))
	assert_false(board.wants(&"berries"))
	assert_true(closed.has(&"wood") and closed.has(&"berries"))
	assert_eq(board.jobs().size(), 2, "the fire is always there to keep (and the field to sow)")
	# Low again: posted again, as a new job.
	posted.clear()
	stock.take(&"wood", 9)
	session.clock.tick += 500
	_refresh()
	assert_eq(posted.size(), 1)
	assert_near(board.job_for(&"wood").priority, 0.5, 0.001)
	assert_ne(board.job_for(&"wood").id, wood_job.id)
	assert_eq(board.job_for(&"wood").posted_tick, session.clock.tick)
	# The board keeps itself up to date as time passes.
	stock.take(&"wood", 9)
	settlement.step(session.clock.tick + config.job_check_minutes - 1)
	assert_near(board.job_for(&"wood").priority, 0.5, 0.001, "not yet looked at")
	settlement.step(session.clock.tick + config.job_check_minutes)
	assert_eq(board.job_for(&"wood").priority, 1.0)
	# Saved and read back.
	var again := JobBoard.new()
	again.from_dict(bytes_to_var(var_to_bytes(board.to_dict())))
	assert_eq(again.jobs().size(), board.jobs().size())
	assert_eq(again.job_for(&"wood").id, board.job_for(&"wood").id)
	assert_eq(again.job_for(&"wood").priority, 1.0)
	assert_eq(again.to_dict(), board.to_dict())
	again.from_dict({"jobs": ["x", {"no": "id"}]})
	assert_eq(again.jobs().size(), 0)


func test_people_weigh_what_is_posted() -> void:
	_fire_out_of_the_way()
	Config.settlement.fire_wood_per_day = 6.0
	_empty_stores()
	stock.add(&"wood", 9) # wood: half of what is wanted
	stock.add(&"berries", 21) # food: half of what is wanted
	_refresh()
	var wood_job := board.job_for(&"wood")
	var food_job := board.job_for(&"berries")
	# One's own trade counts in full; nobody else takes up what is not pressing.
	assert_eq(board.affinity(wood_job, &"tree"), 1.0)
	assert_eq(board.affinity(wood_job, &"bush"), 0.0)
	assert_eq(board.affinity(wood_job, &"fire"), 0.0)
	assert_eq(board.affinity(food_job, &"bush"), 1.0)
	assert_eq(board.affinity(wood_job, &""), 0.0, "someone without a trade")
	assert_near(board.pull_for(&"tree"), 0.5, 0.01)
	assert_near(board.pull_for(&"bush"), 0.5, 0.03)
	assert_eq(board.pull_for(&"fire"), config.fire_job_priority)
	for i in 30:
		assert_eq(board.choose(&"tree", ctx.rng), wood_job)
		assert_eq(board.choose(&"bush", ctx.rng), food_job)
		assert_eq(board.choose(&"fire", ctx.rng).kind, JobBoard.TEND)
	assert_null(board.choose(&"", ctx.rng))
	# Food running out: now it is everyone's business (but less than their own).
	stock.take(&"berries", 18)
	_refresh()
	assert_true(food_job.priority >= config.urgent_from, "pressing (%.2f)" % food_job.priority)
	assert_eq(board.affinity(food_job, &"tree"), config.other_trade_factor)
	assert_eq(board.affinity(food_job, &"fire"), config.other_trade_factor)
	assert_eq(board.affinity(food_job, &"bush"), 1.0)
	var chosen := {wood_job: 0, food_job: 0}
	for i in 400:
		chosen[board.choose(&"tree", ctx.rng)] += 1
	assert_true(chosen[wood_job] > 150 and chosen[food_job] > 120, "a woodcutter does either (%d wood, %d food)" % [chosen[wood_job], chosen[food_job]])
	# Keeping the fire is the fire-keeper's alone.
	for i in 50:
		assert_ne(board.choose(&"tree", ctx.rng).kind, JobBoard.TEND)
	# How much work is worth follows the board.
	assert_near(board.work_factor(&"tree"), lerpf(config.work_without_jobs, config.work_with_urgent_job, board.pull_for(&"tree")), 0.0001)
	var cutter := _calm(_adult(&"woodcutter"))
	_set_hour(9.5)
	_refresh()
	var work := session.activities.get_def(&"work")
	var busy := Brain.score(work, cutter, ctx)
	# ...with everything in store there is less reason to.
	stock.add(&"wood", 30)
	stock.add(&"berries", 60)
	_refresh()
	assert_eq(board.pull_for(&"tree"), 0.0)
	assert_eq(board.work_factor(&"tree"), config.work_without_jobs)
	var idle := Brain.score(work, cutter, ctx)
	assert_true(idle < busy * 0.95, "less to do, less wish to (%.2f against %.2f)" % [idle, busy])
	assert_true(idle > 0.0, "but people still keep their hand in")
	# A new settlement works as people did before there was a board (factor 1).
	assert_near(lerpf(config.work_without_jobs, config.work_with_urgent_job, 1.0 - config.starting_wood / (config.fire_wood_per_day * config.wood_days_wanted)), 1.0, 0.01)


func test_what_is_posted_is_what_work_brings_in() -> void:
	_fire_out_of_the_way()
	Config.settlement.fire_wood_per_day = 6.0
	_set_hour(9.0)
	var cutter := _calm(_adult(&"woodcutter"))
	var elder := _calm(_adult(&"elder"))
	_only([cutter])
	# Wood wanted, food plentiful: the woodcutter cuts wood and brings it in.
	_empty_stores()
	stock.add(&"berries", 60)
	_refresh()
	for i in 20:
		var steps := Planner.plan(&"work", cutter, ctx)
		assert_eq(steps.size(), 4)
		assert_eq(steps[1]["kind"], "tree")
		assert_true(bool(steps[1]["gather"]))
	# Enough wood: nothing posted — work at the tree brings nothing in.
	stock.add(&"wood", 20)
	_refresh()
	var idle := Planner.plan(&"work", cutter, ctx)
	assert_eq(idle.size(), 2)
	assert_eq(idle[1]["kind"], "tree")
	assert_false(idle[1].has("gather"))
	assert_eq(ctx.gatherable(int(idle[1]["target"])), &"", "enough of it for now")
	# The food is gone (the player has carried it off): the woodcutter goes picking too.
	for pile in piles.piles(&"berries"):
		session.loose.move(pile.id, pile.position + Vector2(9.0, 2.0))
	_refresh()
	assert_eq(board.job_for(&"berries").priority, 1.0)
	var picking := 0
	for i in 40:
		var steps := Planner.plan(&"work", cutter, ctx)
		if steps[1]["kind"] == "bush":
			picking += 1
			assert_eq(steps.size(), 4)
			assert_true(bool(steps[1]["gather"]))
			assert_eq(session.props.get_prop(int(steps[1]["target"])).kind, PropData.Kind.BUSH)
			assert_eq(steps[2]["target"], ctx.places.storage_tile(&"berries"))
	assert_eq(picking, 40, "the only thing posted that they can do")
	# ...and so does the elder, some of the time; the fire is still theirs to keep.
	var kinds := {}
	for i in 60:
		var steps := Planner.plan(&"work", elder, ctx)
		kinds[steps[1]["kind"]] = int(kinds.get(steps[1]["kind"], 0)) + 1
	assert_true(int(kinds.get("fire", 0)) > 10 and int(kinds.get("bush", 0)) > 10, str(kinds))
	# The woodcutter does it: berries come into the stores, and the day says what they did.
	var steps_now := Planner.plan(&"work", cutter, ctx)
	session.day_log.forget(cutter.id)
	behavior.set_plan(cutter, &"work", &"purpose", steps_now, 2.0)
	assert_eq(DayLogText.text(session.day_log.of(cutter.id)[-1]), "gathers berries")
	var waited := 0.0
	while stock.amount(&"berries") == 0 and waited < 240.0:
		_run(1.0)
		waited += 1.0
	assert_true(stock.amount(&"berries") >= 1, "berries in store again (%d)" % stock.amount(&"berries"))


# --- the whole of it ------------------------------------------------------------------------------

func test_a_settlement_robbed_of_its_food_feeds_itself_again() -> void:
	# The player carries every food pile away at dawn.
	session.clock.tick = 0
	for pile in piles.piles():
		if session.resources.get_def(pile.resource).is_food():
			session.loose.move(pile.id, pile.position + Vector2(12.0, -6.0))
	_refresh()
	assert_eq(stock.food_units(), 0)
	assert_eq(board.jobs()[0].resource, &"berries", "food before everything")
	assert_eq(board.jobs()[0].priority, 1.0)
	var off_the_bush := 0
	var hungriest := 1.0
	for hour in 24:
		_run(60.0, 1.0)
		for p in session.people.all_people():
			hungriest = minf(hungriest, Needs.value(p.needs, Needs.Need.HUNGER))
			if BehaviorSystem.current_step(p).has("bush"):
				off_the_bush += 1
	var from_bushes := 0
	for p in session.people.all_people():
		for entry: Array in session.day_log.of(p.id):
			if entry[DayLog.KIND] == "eat" and entry[DayLog.DETAIL] == "bush":
				from_bushes += 1
	print("    robbed at dawn: %d meals off the bushes; a day later %d berries in store (%.1f days), hungriest moment %.2f" % [
		from_bushes, stock.amount(&"berries"), settlement.days_of_food(), hungriest])
	assert_true(from_bushes >= 2, "people went to the bushes to eat (%d)" % from_bushes)
	assert_true(stock.food_units() >= 6, "and food was brought in again (%d)" % stock.food_units())
	assert_true(hungriest > 0.02, "nobody starved meanwhile (%.2f)" % hungriest)
	assert_eq(piles.total(&"berries") > stock.amount(&"berries"), true, "what was carried off still lies where it was put")


func test_a_month_of_housekeeping() -> void:
	session.clock.tick = 0
	var people := session.people.all_people()
	var fire_checks := 0
	var fire_lit := 0
	var days_with_food := 0
	var hungriest := 1.0
	var lowest_food := INF
	var felled_most := 0
	var spoiled := {}
	settlement.spoiled.connect(func(resource: StringName, amount: int) -> void: spoiled[resource] = int(spoiled.get(resource, 0)) + amount)
	var days := 30
	for day in days:
		for part in 4:
			_run(360.0, 1.0)
			fire_checks += 1
			fire_lit += 1 if settlement.fire_lit() else 0
			for p in people:
				hungriest = minf(hungriest, Needs.value(p.needs, Needs.Need.HUNGER))
		days_with_food += 1 if stock.food_units() > 0 else 0
		lowest_food = minf(lowest_food, settlement.days_of_food())
		var felled := 0
		for prop in session.props.all_props():
			felled += 1 if prop.felled else 0
		felled_most = maxi(felled_most, felled)
	print("    %d days: fire lit %d of %d checks; food in store on %d days (least %.1f days' worth, now %.1f); hungriest moment %.2f; wood %d; most trees down at once %d; spoiled %s; %d bushes regrowing" % [
		days, fire_lit, fire_checks, days_with_food, lowest_food, settlement.days_of_food(), hungriest, stock.amount(&"wood"),
		felled_most, spoiled, session.nodes.tracked_count()])
	assert_true(fire_lit >= fire_checks * 0.9, "the fire is kept (%d of %d)" % [fire_lit, fire_checks])
	assert_true(days_with_food >= days - 3, "there is food in store (%d of %d days)" % [days_with_food, days])
	assert_true(hungriest > 0.05, "nobody starves (%.2f)" % hungriest)
	assert_true(felled_most >= 2, "wood is cut for the fire (%d)" % felled_most)
	assert_true(felled_most <= 14, "the forest stands (%d)" % felled_most)
	assert_true(stock.amount(&"berries") <= Config.resources.piles_per_resource * 24)
	for p in people:
		assert_true(p.carrying_amount <= ctx.carry_capacity(p.carrying) if p.carrying != &"" else true)
	# Everyone still lives a day of many things.
	var last_day := Config.time.day_index(session.clock.tick) - 1
	for p in people:
		var kinds := {}
		for entry: Array in session.day_log.of_day(p.id, last_day, Config.time):
			kinds[entry[DayLog.KIND]] = true
		assert_true(kinds.size() >= 3, "%s lives on (%s)" % [p.given_name, kinds.keys()])
		assert_true(kinds.has("eat"), "%s eats" % p.given_name)


func test_version_9_save_gains_a_settlement() -> void:
	# Written by M7.1 (2408b4e): a morning lived; 12 berries and 7 wood
	# brought in. Nothing was eaten from the stores yet, and no fire burned wood.
	assert_true(FileAccess.file_exists(V9_FIXTURE), "fixture present")
	var dir := SaveManager.world_dir(V9_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V9_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 9)
	var loaded := SaveManager.load_world(V9_ID)
	assert_true(loaded.ok, loaded.error)
	assert_eq(loaded.world["world_state"]["settlement"], {}, "the migration gives it a settlement to begin")
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	s.loose_system.set_process(false)
	s.water.set_process(false)
	assert_not_null(s.settlement)
	assert_eq(s.settlement.member_count(), 8)
	assert_eq(s.settlement.stockpile.amounts(), {&"berries": 12, &"wood": 7}, "what had been brought in is its stores")
	assert_true(s.settlement.fire_lit())
	assert_true(s.settlement.jobs.wants(&"berries") and s.settlement.jobs.wants(&"wood"), "and its board is up")
	for p in s.people.all_people():
		assert_eq(p.food_in_hand, 0.0)
	for pile in s.piles.piles():
		assert_eq(pile.spoil, 0.0)
	# Life goes on: meals now come out of the stores.
	var eaten := [0]
	s.piles.taken.connect(func(resource: StringName, amount: int, _pile: int) -> void:
		if resource == &"berries":
			eaten[0] += amount)
	_run(600.0, 1.0, s)
	assert_true(eaten[0] >= 4, "berries were eaten (%d)" % eaten[0])
	assert_true(s.day_log.entry_count() > 0)
	# Saved again: the current version, the old file kept; and read back the same.
	assert_true(SaveManager.save_world(s, &"test"))
	assert_true(SaveManager.SAVE_VERSION >= 10)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav.bak1")).header["save_version"], 9)
	var again := SaveManager.load_world(V9_ID)
	assert_true(again.ok, again.error)
	var s2: WorldSession = SessionScript.new()
	add_child(s2)
	assert_true(s2.load_from(again.world))
	s2.set_process(false)
	assert_eq(s2.settlement.stockpile.amounts(), s.settlement.stockpile.amounts())
	assert_eq(s2.settlement.to_dict()["burn_tick"], s.settlement.to_dict()["burn_tick"])
	assert_eq(s2.settlement.fire_lit(), s.settlement.fire_lit())
	s.queue_free()
	s2.queue_free()
	# The step itself.
	assert_eq(SaveMigrations._v9_to_v10({"world": {"world_state": {}}})["world"]["world_state"], {})
	var kept: Dictionary = SaveMigrations._v9_to_v10({"world": {"world_state": {"people": {}, "settlement": {"burn_tick": 5}}}})
	assert_eq(kept["world"]["world_state"]["settlement"], {"burn_tick": 5})
