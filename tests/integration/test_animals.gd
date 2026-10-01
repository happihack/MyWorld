extends TestCase
## Animals v1 (M7.4): the species in data, a new world's herds, how they
## live (graze, wander, drink, sleep, run), foxes and rabbits, young and
## old, fish as a number, and the hunter who brings meat home.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const V11_FIXTURE := "res://tests/fixtures/saves/v11_world.sav"
const V11_ID := "w1790893780_8c5faea5"

var session: WorldSession
var behavior: BehaviorSystem
var ctx: AiContext
var fauna: AnimalSystem
var animals: AnimalRegistry
var species: SpeciesLibrary


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
	fauna = session.fauna
	animals = session.animals
	species = session.species


func after_each() -> void:
	Config.settlement.fire_wood_per_day = SettlementConfig.new().fire_wood_per_day
	session.queue_free()
	await wait_frames(1)


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


## Lets the animals alone live `minutes` (nobody else does anything).
func _animals_live(minutes: int, piece: int = 10) -> void:
	var left := minutes
	while left > 0:
		session.clock.tick += mini(piece, left)
		left -= piece
		fauna.advance_to(session.clock.tick)


func _set_hour(hour: float, day: int = 1) -> void:
	session.clock.tick = posmod(roundi((hour - Config.time.start_hour) * 60.0), 1440) + 1440 * day
	fauna.last_tick = session.clock.tick


## Everyone goes indoors and stays there (so that no animal is afraid of anyone).
func _people_away() -> void:
	behavior.enabled = false
	for p in session.people.all_people():
		p.set_flag(PersonData.FLAG_INDOORS, true)


func _first(kind: StringName) -> AnimalData:
	var all := animals.of_species(kind)
	return all[0] if not all.is_empty() else null


func _hunter() -> PersonData:
	for p in session.people.all_people():
		if p.occupation_id == &"hunter":
			return p
	return null


# --- what there is --------------------------------------------------------------------------------

func test_species_are_defined_in_data() -> void:
	assert_eq(species.problems.size(), 0, str(species.problems))
	assert_eq(species.ids(), [&"deer", &"fish", &"fox", &"rabbit"] as Array[StringName])
	var deer := species.get_def(&"deer")
	var rabbit := species.get_def(&"rabbit")
	var fox := species.get_def(&"fox")
	var fish := species.get_def(&"fish")
	for def: SpeciesDef in [deer, rabbit, fox, fish]:
		assert_eq(def.validate().size(), 0, String(def.id))
		assert_ne(UIText.species_name(def.id), String(def.id).capitalize() + "?", String(def.id))
	assert_eq(deer.diet, SpeciesDef.Diet.GRAZER)
	assert_true(deer.is_hunted() and rabbit.is_hunted(), "game")
	assert_true(deer.meat > rabbit.meat)
	assert_eq(fox.diet, SpeciesDef.Diet.PREDATOR)
	assert_true(fox.preys_on(&"rabbit"))
	assert_false(fox.preys_on(&"deer"))
	assert_false(fox.is_hunted(), "nobody eats fox")
	assert_true(fish.aggregate, "fish are a number for all the water")
	assert_false(fish.is_hunted())
	assert_true(rabbit.birth_rate > deer.birth_rate, "rabbits breed like rabbits")
	assert_true(deer.run_speed > Config.people.walk_tiles_per_minute * 2.0, "nobody outruns a deer")
	# Shapes to draw them with.
	for def: SpeciesDef in [deer, rabbit, fox]:
		assert_true(AnimalMeshLibrary.has_shape(def.shape), String(def.id))
		var mesh := AnimalMeshLibrary.mesh_for(def)
		assert_not_null(mesh)
		assert_eq(AnimalMeshLibrary.mesh_for(def), mesh, "made once")
		var box := mesh.get_aabb()
		assert_true(box.position.y >= -0.001 and box.end.y <= def.height + 0.08, "%s stands on the ground, about as tall as said (%.2f)" % [def.id, box.end.y])
		assert_true(box.size.x > box.size.z, "%s is longer than wide (it faces +X)" % def.id)
	assert_null(AnimalMeshLibrary.mesh_for(fish))
	# Sleeping hours, also over midnight.
	assert_true(deer.sleeps_at(23.0) and deer.sleeps_at(3.0))
	assert_false(deer.sleeps_at(12.0))
	assert_true(fox.sleeps_at(12.0), "a fox sleeps by day")
	assert_false(fox.sleeps_at(23.0))
	# Unusable definitions are refused.
	var other := SpeciesLibrary.new()
	assert_false(other.add(SpeciesDef.new()), "no id")
	var beast := SpeciesDef.new()
	beast.id = &"beast"
	beast.diet = SpeciesDef.Diet.PREDATOR
	assert_false(other.add(beast), "a predator without prey")
	beast.diet = SpeciesDef.Diet.GRAZER
	beast.walk_speed = 3.0
	beast.run_speed = 1.0
	beast.adult_days = 500
	assert_eq(beast.validate().size(), 2)
	assert_eq(UIText.animal_state(AnimalData.State.GRAZE), "Grazing")
	assert_eq(UIText.animal_state(AnimalData.State.GRAZE, true), "Resting")
	assert_eq(UIText.animal_age(1, false), "Young (1 day)")
	assert_eq(UIText.animal_age(40, true), "Grown (40 days)")


func test_a_new_world_has_its_animals() -> void:
	assert_true(fauna.seeded)
	var settlement := Vector2(session.start.settlement_tile)
	for id: StringName in [&"deer", &"rabbit", &"fox"]:
		var def := species.get_def(id)
		var count := animals.count(id)
		assert_true(count >= def.starting_groups * def.group_min and count <= mini(def.starting_groups * def.group_max, def.capacity),
			"%d %s" % [count, id])
		var groups := {}
		var ages := {}
		for animal in animals.of_species(id):
			groups[animal.group] = true
			ages[animal.age_days(session.clock.tick)] = true
			assert_true(animal.position.distance_to(settlement) >= AnimalSystem.SETTLEMENT_CLEARANCE - 3.0, "%s lives away from people" % id)
			assert_true(animal.position.distance_to(animal.home) <= 2.5, "with its group")
			assert_true(session.world.bounds.has_point(animal.tile()))
			assert_eq(session.world.get_water(animal.tile()) <= 0.3, true)
			assert_true(animal.age_days(session.clock.tick) < def.lifespan_days)
			assert_eq(session.spatial.get_kind(animal.id), SpatialIndex.KIND_ANIMAL, "found by where it is")
		assert_eq(groups.size(), def.starting_groups)
		if count >= 4:
			assert_true(ages.size() >= 2, "of different ages")
	assert_eq(animals.count(&"fish"), 0, "fish are not animals one by one")
	assert_true(fauna.fish_capacity > 5.0, "the river holds fish (%.0f)" % fauna.fish_capacity)
	assert_near(fauna.fish, fauna.fish_capacity * 0.8, 0.01)
	# Once.
	var before := animals.size()
	fauna.seed_world(session.clock.tick)
	assert_eq(animals.size(), before)
	# The same world has the same animals.
	var twin: WorldSession = SessionScript.new()
	add_child(twin)
	twin.create_new(12345)
	twin.set_process(false)
	assert_eq(twin.animals.size(), animals.size())
	var mine := animals.all_animals()
	var theirs := twin.animals.all_animals()
	for i in mine.size():
		assert_eq([theirs[i].species, theirs[i].position, theirs[i].born_tick], [mine[i].species, mine[i].position, mine[i].born_tick])
	twin.queue_free()
	assert_has(fauna.debug_text(), "deer %d/10" % animals.count(&"deer"))
	# In the registry.
	var deer := _first(&"deer")
	assert_eq(animals.get_animal(deer.id), deer)
	assert_false(animals.add(deer), "not twice")
	assert_false(animals.add(null))
	assert_true(animals.remove(deer.id))
	assert_false(animals.remove(deer.id))
	assert_eq(animals.count(&"deer"), mine.size() - animals.count(&"rabbit") - animals.count(&"fox") - 1)
	assert_eq(session.spatial.get_kind(deer.id), 0, "gone from the index")


# --- how they live --------------------------------------------------------------------------------

func test_animals_graze_wander_drink_and_sleep() -> void:
	_people_away()
	_set_hour(8.0)
	var deer := animals.of_species(&"deer")
	var foxes := animals.of_species(&"fox")
	var states := {}
	var farthest := 0.0
	var longest_step := 0.0
	var before := {}
	for animal in animals.all_animals():
		before[animal.id] = animal.position
	# A day from eight to eight, ten minutes at a time.
	for step in 144:
		_animals_live(10)
		for animal in animals.all_animals():
			var def := species.get_def(animal.species)
			states[[animal.species, animal.state]] = true
			if def.diet == SpeciesDef.Diet.GRAZER and animal.state == AnimalData.State.SLEEP:
				farthest = maxf(farthest, animal.position.distance_to(animal.home) - def.home_range)
			longest_step = maxf(longest_step, animal.position.distance_to(before[animal.id]) - def.run_speed * 10.0)
			before[animal.id] = animal.position
			assert_true(session.world.bounds.has_point(animal.tile()), "inside the box")
			assert_true(session.world.get_water(animal.tile()) <= Pathfinder.WADE_DEPTH * session.world.height_step + 0.001, "not in deep water")
			var prop := session.props.prop_at(animal.tile())
			assert_true(prop == null or prop.kind != PropData.Kind.HUT, "not in a hut")
		var hour := Config.time.minute_of_day(session.clock.tick) / 60.0
		if hour >= 23.0 or hour < 3.5:
			for animal in deer:
				assert_eq(animal.state, AnimalData.State.SLEEP, "deer sleep at night (%.1f)" % hour)
		if hour >= 11.0 and hour < 15.0:
			for animal in foxes:
				assert_eq(animal.state, AnimalData.State.SLEEP, "foxes sleep by day (%.1f)" % hour)
	assert_true(states.has([&"deer", AnimalData.State.GRAZE]) and states.has([&"deer", AnimalData.State.WANDER]), "they graze and move about")
	assert_true(states.has([&"rabbit", AnimalData.State.WANDER]))
	assert_false(states.has([&"deer", AnimalData.State.HUNT]))
	assert_true(farthest <= 1.5, "they sleep where they live, however far the water was (%.1f beyond it)" % farthest)
	assert_true(longest_step <= 0.01, "nobody moves faster than they can run")
	# They have been to the water (those who can get to it).
	var drank := 0
	for animal in deer:
		drank += 1 if animal.drank_day >= 0 else 0
	assert_true(drank >= deer.size() - 1, "the deer drank (%d of %d)" % [drank, deer.size()])
	assert_true(states.has([&"deer", AnimalData.State.DRINK]))
	# The same at any pace: in half-hour pieces they end the day alive, at home, asleep at night.
	_set_hour(8.0, 3)
	_animals_live(900, 30)
	for animal in deer:
		assert_eq(animal.state, AnimalData.State.SLEEP)
		assert_true(animal.position.distance_to(animal.home) <= species.get_def(&"deer").home_range + 1.5)


func test_animals_run_from_people_and_from_what_the_player_does() -> void:
	_people_away()
	_set_hour(10.0)
	var deer := _first(&"deer")
	var def := species.get_def(&"deer")
	var fled: Array = []
	fauna.fled.connect(func(id: int) -> void: fled.append(id))
	# Someone walks up: at the edge of its fear it runs, away from them.
	var person := session.people.all_people()[0]
	person.set_flag(PersonData.FLAG_INDOORS, false)
	var beside := WorldCoords.world2d_to_tile(deer.position + Vector2(def.fear_radius + 2.0, 0.0))
	session.people.move(person.id, beside, Vector2(0.5, 0.5), 0.0)
	_animals_live(2, 1)
	assert_ne(deer.state, AnimalData.State.FLEE, "too far to mind")
	session.people.move(person.id, WorldCoords.world2d_to_tile(deer.position + Vector2(def.fear_radius - 1.5, 0.0)), Vector2(0.5, 0.5), 0.0)
	var was := deer.position.distance_to(person.world2d())
	_animals_live(1, 1)
	assert_eq(deer.state, AnimalData.State.FLEE)
	assert_true(fled.has(deer.id))
	_animals_live(4, 1)
	assert_true(deer.position.distance_to(person.world2d()) > was + 1.5, "it has put ground between them (%.1f → %.1f)" % [was, deer.position.distance_to(person.world2d())])
	# After a while it settles.
	person.set_flag(PersonData.FLAG_INDOORS, true)
	_animals_live(AnimalSystem.FLEE_MINUTES + 5, 1)
	assert_ne(deer.state, AnimalData.State.FLEE)
	# Someone stalking it gets nearer before it notices.
	person.set_flag(PersonData.FLAG_INDOORS, false)
	behavior.enabled = true
	behavior.set_plan(person, &"work", &"purpose", [HuntStep.make(deer.id)], 2.0)
	behavior.enabled = false
	session.movement.stop(person.id)
	session.people.move(person.id, WorldCoords.world2d_to_tile(deer.position + Vector2(def.fear_radius * 0.7, 0.0)), Vector2(0.5, 0.5), 0.0)
	_animals_live(1, 1)
	assert_ne(deer.state, AnimalData.State.FLEE, "a hunter creeps")
	person.current_action = {}
	_animals_live(1, 1)
	assert_eq(deer.state, AnimalData.State.FLEE, "someone just walking there is seen")
	person.set_flag(PersonData.FLAG_INDOORS, true)
	_animals_live(AnimalSystem.FLEE_MINUTES + 5, 1)
	# What the player does near them startles them: a touch on the ground beside a rabbit.
	var rabbit := _first(&"rabbit")
	var ground := Picker.Result.new()
	ground.kind = Picker.Kind.TILE
	ground.tile = rabbit.tile() + Vector2i(1, 0)
	ground.position = Vector3(rabbit.position.x + 1.0, 0.0, rabbit.position.y)
	fled.clear()
	session.interactions.tap(ground)
	assert_true(fled.has(rabbit.id), "the rabbit bolts")
	assert_eq(rabbit.state, AnimalData.State.FLEE)
	if deer.position.distance_to(rabbit.position) > 8.0:
		assert_false(fled.has(deer.id), "the deer, far off, did not notice")
	# A touch on the animal itself.
	_animals_live(AnimalSystem.FLEE_MINUTES + 5, 1)
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = deer.id
	target.entity_kind = SpatialIndex.KIND_ANIMAL
	target.tile = deer.tile()
	var report := session.interactions.inspect(target)
	assert_eq(report.subject, InspectReport.Subject.ANIMAL)
	assert_eq(report.species, &"deer")
	assert_eq(report.species_count, animals.count(&"deer"))
	assert_eq(report.animal_age_days, deer.age_days(session.clock.tick))
	var response := session.interactions.tap(target)
	assert_eq(response.animal_id, deer.id)
	assert_eq(response.animal_species, &"deer")
	assert_eq(InteractionManager.subject_of(response), &"deer")
	assert_eq(deer.state, AnimalData.State.FLEE, "touched: it bolts")
	assert_eq(session.history.count(Intervention.TOUCH, &"deer"), 1, "and the player's history has it")
	assert_eq(String(TranslationServer.translate("HISTTHING_DEER")), "a deer")
	# Startling by hand.
	assert_eq(fauna.startle(Vector2(-900.0, -900.0), 3.0, session.clock.tick), 0)
	assert_false(fauna.startle_one(987654, Vector2.ZERO, session.clock.tick))


func test_foxes_hunt_rabbits() -> void:
	_people_away()
	_set_hour(20.0)
	var fox := _first(&"fox")
	var fox_def := species.get_def(&"fox")
	var deaths: Array = []
	fauna.died.connect(func(id: int, kind: StringName, cause: StringName, _at: Vector2) -> void: deaths.append([kind, cause]))
	# A rabbit warren where the fox lives.
	var rabbits := animals.of_species(&"rabbit")
	for rabbit in rabbits:
		rabbit.home = fox.home + Vector2(3.0, 0.0)
		animals.move(rabbit.id, fox.home + Vector2(3.0 + 0.3 * (rabbit.id % 5), 0.4 * (rabbit.id % 3)))
	var before := animals.count(&"rabbit")
	# Not hungry: it leaves them be.
	fox.fed_tick = session.clock.tick
	fox.state_until = session.clock.tick
	_animals_live(120, 5)
	assert_eq(animals.count(&"rabbit"), before)
	# Hungry: it goes after one — and over some nights it gets some.
	var hunted := false
	for night in 12:
		_set_hour(20.0, 2 + night)
		fox.fed_tick = session.clock.tick - roundi(fox_def.hunts_every_days * 1440)
		fox.state = AnimalData.State.GRAZE
		fox.state_until = session.clock.tick
		for step in 40:
			_animals_live(5, 5)
			hunted = hunted or fox.state == AnimalData.State.HUNT
	assert_true(hunted, "it hunted")
	assert_true(deaths.has([&"rabbit", &"prey"]), "and took rabbits (%s)" % [deaths])
	assert_true(animals.count(&"rabbit") >= AnimalSystem.REFUGE, "not all of them: the last few keep hidden (%d of %d)" % [animals.count(&"rabbit"), before])
	for death: Array in deaths:
		assert_ne(death[0], &"deer", "foxes do not take deer")
	# Rabbits near a fox are wary of it.
	_set_hour(18.0, 20)
	fox = _first(&"fox") # (one that is alive now)
	var rabbit := _first(&"rabbit")
	animals.move(rabbit.id, fox.position + Vector2(1.0, 0.0))
	rabbit.state = AnimalData.State.GRAZE
	rabbit.state_until = session.clock.tick + 1000
	fox.state = AnimalData.State.GRAZE
	fox.fed_tick = session.clock.tick
	fox.state_until = session.clock.tick + 1000
	var ran: Array = []
	fauna.fled.connect(func(id: int) -> void: ran.append(id))
	_animals_live(AnimalSystem.CALM_EVERY, 1) # (calm animals look about every few minutes)
	assert_true(ran.has(rabbit.id), "a fox ambling past is seen (state %d, %.1f from the fox)" % [rabbit.state, rabbit.position.distance_to(fox.position)])


# --- numbers --------------------------------------------------------------------------------------

func test_young_are_born_and_the_old_die() -> void:
	_people_away()
	var deer_def := species.get_def(&"deer")
	var births: Array = []
	var deaths: Array = []
	fauna.born.connect(func(id: int, kind: StringName) -> void: births.append(kind))
	fauna.died.connect(func(id: int, kind: StringName, cause: StringName, _at: Vector2) -> void: deaths.append([kind, cause]))
	# Foxes and rabbits out of the way: this is about the deer.
	for animal in animals.all_animals():
		if animal.species != &"deer":
			animals.remove(animal.id)
	deaths.clear()
	var herd := animals.of_species(&"deer")
	var now := session.clock.tick
	for animal in herd:
		animal.born_tick = now - 60 * 1440 # grown, far from old
	var before := herd.size()
	# With room in the box, young come — more slowly the fuller it is.
	_set_hour(12.0, 1)
	var young: AnimalData = null
	for day in 80:
		session.clock.tick += 1440
		fauna.advance_to(session.clock.tick)
		if young == null and not births.is_empty():
			# The first of them: small, beside the herd, one of it.
			for animal in animals.of_species(&"deer"):
				if animal.age_days(session.clock.tick) < deer_def.adult_days:
					young = animal
			assert_not_null(young, "a young one")
			assert_true(young.position.distance_to(young.home) < deer_def.home_range + 2.0, "born into the herd")
			assert_eq(young.home, herd[0].home)
	var after := animals.count(&"deer")
	assert_true(after > before, "young were born (%d → %d)" % [before, after])
	assert_true(after <= deer_def.capacity, "no more than the box holds")
	assert_true(births.size() >= after - before)
	assert_not_null(young)
	# The old die.
	var old := animals.of_species(&"deer")[0]
	old.born_tick = session.clock.tick - deer_def.lifespan_days * 1440
	session.clock.tick += 1440
	fauna.advance_to(session.clock.tick)
	assert_null(animals.get_animal(old.id))
	assert_true(deaths.has([&"deer", &"age"]))
	# One alone has no young.
	for animal in animals.of_species(&"deer").slice(1):
		animals.remove(animal.id)
	animals.of_species(&"deer")[0].born_tick = session.clock.tick - 40 * 1440
	births.clear()
	for day in 40:
		session.clock.tick += 1440
		fauna.advance_to(session.clock.tick)
	assert_eq(births.size(), 0)
	assert_eq(animals.count(&"deer"), 1)
	# Fish: taken, and back in days — never more than the water holds.
	var holds := fauna.fish_capacity
	fauna.fish = holds
	assert_eq(fauna.take_fish(5), 5)
	assert_near(fauna.fish, holds - 5.0, 0.001)
	assert_eq(fauna.take_fish(100000), floori(holds - 5.0))
	var low := fauna.fish
	for day in 3:
		session.clock.tick += 1440
		fauna.advance_to(session.clock.tick)
	assert_true(fauna.fish > low + holds * 0.4, "they come back (%.1f)" % fauna.fish)
	for day in 40:
		session.clock.tick += 1440
		fauna.advance_to(session.clock.tick)
	assert_true(fauna.fish <= holds + 0.001 and fauna.fish > holds * 0.98)


func test_animal_population_bounds() -> void:
	# Twenty game years of the animals' own lives, with a hunter's take: no
	# species explodes and none dies out.
	_people_away()
	session.clock.tick = 0
	fauna.last_tick = 0
	var least := {}
	var most := {}
	var sum := {}
	var kinds: Array[StringName] = [&"deer", &"rabbit", &"fox"]
	for id in kinds:
		least[id] = animals.count(id)
		most[id] = animals.count(id)
		sum[id] = 0
	var taken := {&"deer": 0, &"rabbit": 0}
	var causes := {}
	fauna.died.connect(func(_id: int, kind: StringName, cause: StringName, _at: Vector2) -> void:
		causes[[kind, cause]] = int(causes.get([kind, cause], 0)) + 1)
	var days := 20 * Config.time.days_per_year()
	for day in days:
		# Hour by hour (in half-hour pieces inside).
		for hour in 24:
			session.clock.tick += 60
			fauna.advance_to(session.clock.tick)
		# A hunter's take: an animal every other day, where there are enough to take from.
		if day % 2 == 0:
			for id: StringName in [&"deer", &"rabbit"]:
				if fauna.may_hunt(id):
					var quarry := animals.of_species(id)[0]
					fauna.hunted(quarry.id)
					taken[id] += 1
					break
		for id in kinds:
			var count := animals.count(id)
			least[id] = mini(least[id], count)
			most[id] = maxi(most[id], count)
			sum[id] += count
	var lines := PackedStringArray()
	for id in kinds:
		lines.append("%s %d–%d (about %.1f)" % [id, least[id], most[id], float(sum[id]) / days])
	print("    twenty years: %s; hunters took %d deer and %d rabbits; %s" % [", ".join(lines), taken[&"deer"], taken[&"rabbit"], causes])
	for id in kinds:
		var def := species.get_def(id)
		assert_true(least[id] >= 1, "%s never died out (least %d)" % [id, least[id]])
		assert_true(most[id] <= def.capacity, "%s never more than the box holds (%d of %d)" % [id, most[id], def.capacity])
		assert_true(animals.count(id) >= 1, "%s are there at the end" % id)
	assert_true(least[&"deer"] >= 2 and least[&"rabbit"] >= 3, "herds, not last survivors")
	assert_true(taken[&"deer"] >= 20 and taken[&"rabbit"] >= 30, "and they fed the hunters all those years")
	assert_true(int(causes.get([&"rabbit", &"prey"], 0)) >= 8, "foxes took rabbits too (%d)" % int(causes.get([&"rabbit", &"prey"], 0)))
	assert_true(animals.size() <= 40)


# --- hunters ----------------------------------------------------------------------------------------

func test_someone_takes_up_hunting_and_the_board_calls_for_meat() -> void:
	var def := session.occupations.get_def(&"hunter")
	assert_not_null(def)
	assert_eq(def.work_target, &"game")
	assert_eq(def.starting_share, 0.0)
	assert_not_null(PersonMeshLibrary.accessory(def.accessory), "a spear")
	assert_eq(UIText.occupation_name(&"hunter"), "Hunter")
	# With game about, one of the gatherers hunts from the first day.
	var hunter := _hunter()
	assert_not_null(hunter, "the first hunter")
	assert_eq(session.settlement.hunter_count(), 1)
	assert_true(float(hunter.skills.get("hunter", 0.0)) >= Settlement.FIRST_FARMER_SKILL)
	assert_null(session.settlement.ensure_hunter(session.clock.tick), "once")
	var trades := {}
	for p in session.people.all_people():
		trades[p.occupation_id] = int(trades.get(p.occupation_id, 0)) + 1
	assert_true(int(trades.get(&"woodcutter", 0)) >= 1 and int(trades.get(&"forager", 0)) >= 1 and int(trades.get(&"farmer", 0)) == 1,
		"no trade was left without anyone (%s)" % [trades])
	# Food short and game about: hunting is on the board, for hunters.
	var board := session.settlement.jobs
	board.refresh(session.settlement, session.clock.tick)
	var hunt: JobBoard.Job = null
	for job in board.jobs():
		if job.kind == JobBoard.HUNT:
			hunt = job
	assert_not_null(hunt)
	assert_eq([hunt.node, hunt.resource], [&"game", &"meat"])
	assert_near(hunt.priority, board.job_for(&"berries").priority, 0.001, "as pressing as the food is short")
	assert_eq(board.affinity(hunt, &"game"), 1.0)
	assert_eq(board.affinity(hunt, &"bush"), 0.0)
	assert_eq(board.affinity(board.job_for(&"berries"), &"game", def.helps_with), Config.settlement.other_trade_factor, "a hunter also picks berries")
	# Enough food: nobody is sent hunting.
	session.settlement.stockpile.add(&"grain", 60)
	board.refresh(session.settlement, session.clock.tick)
	for job in board.jobs():
		assert_ne(job.kind, JobBoard.HUNT)
	session.settlement.stockpile.take(&"grain", 60)
	# No game to spare: none either, and nobody takes it up.
	for animal in animals.all_animals():
		if animal.species != &"fox":
			animals.remove(animal.id)
	assert_false(fauna.has_game())
	board.refresh(session.settlement, session.clock.tick)
	for job in board.jobs():
		assert_ne(job.kind, JobBoard.HUNT)
	hunter.occupation_id = &"forager"
	assert_null(session.settlement.ensure_hunter(session.clock.tick))
	assert_eq(Planner._hunt(hunter, ctx), [])


func test_a_hunter_brings_meat_home() -> void:
	Config.settlement.fire_wood_per_day = 0.01
	_set_hour(9.0)
	var hunter := _hunter()
	hunter.needs = PackedFloat32Array([0.95, 0.95, 0.95, 0.9, 0.5, 1.0])
	for p in session.people.all_people():
		if p != hunter:
			p.set_flag(PersonData.FLAG_INDOORS, true)
			behavior.set_plan(p, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(1000000.0)])
	# What may be hunted: deer and rabbits while there are enough; never foxes.
	assert_true(fauna.may_hunt(&"deer") and fauna.may_hunt(&"rabbit"))
	assert_false(fauna.may_hunt(&"fox"))
	assert_false(fauna.may_hunt(&"fish"))
	var fire := session.settlement.fire().position2d()
	var quarry := fauna.quarry_for(hunter.world2d(), fire, Config.settlement.hunt_radius)
	assert_not_null(quarry)
	assert_true(fauna.may_hunt(quarry.species))
	assert_null(fauna.quarry_for(hunter.world2d(), fire, 2.0), "none that near the fire")
	# The plan: after it; with a kill, home with the meat.
	var steps := Planner._hunt(hunter, ctx)
	assert_eq(steps.size(), 3)
	assert_eq([steps[0]["type"], steps[1]["type"], steps[2]["type"]], ["hunt", "walk_to", "store"])
	assert_eq(steps[0]["animal"], quarry.id)
	assert_eq(steps[1]["target"], ctx.places.storage_tile(&"meat"))
	# Hunt after hunt until one comes home: misses send the animal running and end the hunt.
	var kills: Array = []
	behavior.hunted.connect(func(id: int, kind: StringName) -> void: kills.append([id, kind]))
	var deaths: Array = []
	fauna.died.connect(func(_id: int, kind: StringName, cause: StringName, _at: Vector2) -> void: deaths.append([kind, cause]))
	var before := animals.count(&"deer") + animals.count(&"rabbit")
	var hunts := 0
	var misses := 0
	session.day_log.forget(hunter.id)
	while kills.is_empty() and hunts < 12:
		hunts += 1
		hunter.needs = PackedFloat32Array([0.95, 0.95, 0.95, 0.9, 0.5, 1.0])
		var plan := Planner._hunt(hunter, ctx)
		if plan.is_empty():
			break
		behavior.set_plan(hunter, &"work", &"purpose", plan, 3.0)
		if hunts == 1:
			assert_eq(DayLogText.text(session.day_log.of(hunter.id)[-1]), "goes hunting")
		var waited := 0.0
		while BehaviorSystem.current_step(hunter).get("type") == "hunt" and waited < 400.0:
			_run(1.0)
			waited += 1.0
		if kills.is_empty():
			misses += 1
		print("      hunt %d: after %d minutes, hunter at %s, activity %s, carrying %d, deer %d rabbits %d" % [hunts, waited, hunter.position,
			BehaviorSystem.activity_of(hunter), hunter.carrying_amount, animals.count(&"deer"), animals.count(&"rabbit")])
	print("    the hunter: %d hunts, %d of them came to nothing; killed %s" % [hunts, misses, kills])
	assert_eq(kills.size(), 1, "a kill")
	assert_eq(kills[0][0], hunter.id)
	assert_true(deaths.has([kills[0][1], &"hunted"]))
	assert_eq(animals.count(&"deer") + animals.count(&"rabbit"), before - 1, "one animal fewer")
	var meat := species.get_def(kills[0][1]).meat
	assert_eq(hunter.carrying, &"meat")
	assert_eq(hunter.carrying_amount, mini(meat, ctx.carry_capacity(&"meat")))
	assert_true(float(hunter.skills.get("hunter", 0.0)) > Settlement.FIRST_FARMER_SKILL, "and they are the better for it")
	# Home with it: meat in the stores, and it is food.
	var waited_home := 0.0
	while hunter.carrying_amount > 0 and waited_home < 600.0:
		_run(1.0)
		waited_home += 1.0
	assert_eq(session.stored(&"meat"), mini(meat, ctx.carry_capacity(&"meat")), "the meat is in the stores")
	assert_true(session.settlement.stockpile.food() >= session.stored(&"meat") * session.resources.get_def(&"meat").nutrition)
	assert_eq(session.settlement.stockpile.take_food(), &"meat", "eaten first: it goes bad soonest")
	# Too few left of a kind: they are left alone.
	for animal in animals.of_species(&"deer").slice(4):
		animals.remove(animal.id)
	assert_false(fauna.may_hunt(&"deer"), "four deer are not hunted")
	for i in 20:
		var next := fauna.quarry_for(hunter.world2d(), fire, Config.settlement.hunt_radius)
		assert_true(next == null or next.species != &"deer")


# --- the whole of it ------------------------------------------------------------------------------

func test_a_season_with_animals_and_hunters() -> void:
	session.clock.tick = 0
	var kills := [0]
	behavior.hunted.connect(func(_id: int, _kind: StringName) -> void: kills[0] += 1)
	var meat_in := [0]
	session.piles.stored.connect(func(resource: StringName, amount: int, _pile: int) -> void:
		if resource == &"meat":
			meat_in[0] += amount)
	var hungriest := 1.0
	var least := {&"deer": 99, &"rabbit": 99, &"fox": 99}
	for day in 12:
		for part in 4:
			_run(360.0)
			for p in session.people.all_people():
				hungriest = minf(hungriest, Needs.value(p.needs, Needs.Need.HUNGER))
		for id: StringName in least:
			least[id] = mini(least[id], animals.count(id))
			assert_true(animals.count(id) <= species.get_def(id).capacity)
	print("    twelve days: %d kills, %d meat brought in; least of each kind %s; now %s; hungriest moment %.2f" % [
		kills[0], meat_in[0], least, fauna.debug_text(), hungriest])
	assert_true(kills[0] >= 2, "the hunter hunted (%d kills)" % kills[0])
	assert_true(meat_in[0] >= 4, "and brought meat home (%d)" % meat_in[0])
	assert_true(least[&"deer"] >= 3 and least[&"rabbit"] >= 4, "without emptying the land")
	assert_true(hungriest > 0.05)
	# Animals keep clear of the settlement while people are about.
	var fire := session.settlement.fire().position2d()
	for animal in animals.all_animals():
		assert_true(animal.position.distance_to(fire) > 3.0, "%s is not at the fire" % animal.species)
	# It all survives a save.
	var data: Dictionary = bytes_to_var(var_to_bytes(session.to_dict()))
	var loaded: WorldSession = SessionScript.new()
	add_child(loaded)
	assert_true(loaded.load_from(data))
	loaded.set_process(false)
	assert_eq(loaded.animals.size(), animals.size())
	assert_true(loaded.fauna.seeded)
	assert_near(loaded.fauna.fish, fauna.fish, 0.001)
	var mine := animals.all_animals()
	var theirs := loaded.animals.all_animals()
	for i in mine.size():
		assert_eq(theirs[i].to_dict(), mine[i].to_dict())
		assert_eq(loaded.spatial.get_kind(theirs[i].id), SpatialIndex.KIND_ANIMAL)
	assert_eq(loaded.fauna.to_dict(), fauna.to_dict())
	assert_eq(loaded.settlement.hunter_count(), 1)
	# New animals after the load do not take the ids of those there.
	var newcomer := loaded.fauna.spawn(&"rabbit", theirs[0].position, theirs[0].home, 99, loaded.clock.tick)
	assert_false(animals.has_animal(newcomer.id))
	loaded.queue_free()
	# Unusable records are left out.
	var broken := AnimalRegistry.new()
	assert_eq(broken.from_dict({"animals": [mine[0].to_dict(), "x", {"id": 5}, {"id": 6, "position": Vector2(NAN, 0), "species": "deer"},
		{"id": 7, "position": Vector2.ZERO, "species": ""}]}), 4)
	assert_eq(broken.size(), 1)


func test_version_11_save_gains_animals() -> void:
	# Written by M7.3 (3c084b3): a morning lived; no animals in it.
	assert_true(FileAccess.file_exists(V11_FIXTURE), "fixture present")
	var dir := SaveManager.world_dir(V11_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V11_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 11)
	var loaded := SaveManager.load_world(V11_ID)
	assert_true(loaded.ok, loaded.error)
	assert_eq(loaded.world["world_state"]["animals"], {})
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	s.loose_system.set_process(false)
	s.water.set_process(false)
	# The world is given its animals as it is opened.
	assert_true(s.fauna.seeded)
	assert_true(s.animals.count(&"deer") >= 5 and s.animals.count(&"rabbit") >= 10 and s.animals.count(&"fox") == 3)
	assert_eq(s.people.size(), 8)
	assert_eq(s.settlement.hunter_count(), 0, "as it was saved")
	for animal in s.animals.all_animals():
		assert_null(s.people.get_person(animal.id), "ids of their own")
		assert_null(s.props.get_prop(animal.id))
		assert_null(s.loose.get_object(animal.id))
	# Before long someone hunts.
	_run(120.0, 1.0, s)
	assert_eq(s.settlement.hunter_count(), 1)
	# Saved again: the current version, the old file kept; and read back with the same animals.
	assert_true(SaveManager.save_world(s, &"test"))
	assert_eq(SaveManager.SAVE_VERSION, 12)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 12)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav.bak1")).header["save_version"], 11)
	var again := SaveManager.load_world(V11_ID)
	assert_true(again.ok, again.error)
	var s2: WorldSession = SessionScript.new()
	add_child(s2)
	assert_true(s2.load_from(again.world))
	s2.set_process(false)
	assert_eq(s2.animals.size(), s.animals.size(), "not given a second lot")
	assert_eq(s2.animals.all_animals()[0].to_dict(), s.animals.all_animals()[0].to_dict())
	s.queue_free()
	s2.queue_free()
	# The step itself.
	assert_eq(SaveMigrations._v11_to_v12({"world": {"world_state": {}}})["world"]["world_state"], {})
	var kept: Dictionary = SaveMigrations._v11_to_v12({"world": {"world_state": {"people": {}, "animals": {"seeded": true}}}})
	assert_eq(kept["world"]["world_state"]["animals"], {"seeded": true})
