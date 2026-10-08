extends TestCase
## PR1: big predators in the land (the owner, 2026-10-08). Bear, wolf,
## mountain lion and boar: visitors from the wilds — never there at the
## start, never born in the box — coming rarely to a settlement, to the kind
## of land they like, one at a time, keeping off the fires, staying a while
## and going again; a bear sleeps the winter through.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440

var session: WorldSession
var fauna: AnimalSystem
var animals: AnimalRegistry
var species: SpeciesLibrary


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	fauna = session.fauna
	animals = session.animals
	species = session.species
	# (Nobody about for the animals to mind.)
	session.behavior.enabled = false
	for p in session.people.all_people():
		p.set_flag(PersonData.FLAG_INDOORS, true)


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


## The animals alone live `minutes`.
func _animals_live(minutes: int, piece: int = 30) -> void:
	var left := minutes
	while left > 0:
		session.clock.tick += mini(piece, left)
		left -= piece
		fauna.advance_to(session.clock.tick)


func _fire() -> Vector2:
	return Vector2(session.settlement.fire().tile) + Vector2(0.5, 0.5)


func test_they_are_visitors() -> void:
	assert_eq(species.problems.size(), 0, str(species.problems))
	for id: StringName in [&"bear", &"wolf", &"lion", &"boar"]:
		var def := species.get_def(id)
		assert_not_null(def, "%s is a species" % id)
		assert_true(def.visitor, "%s comes from the wilds" % id)
		assert_false(def.is_hunted(), "%s is not one for a hunter alone" % id)
		assert_true(def.meat > 0 and def.hide > 0, "%s gives meat and a hide" % id)
		assert_not_null(AnimalMeshLibrary.mesh_for(def), "%s is drawn" % id)
		assert_eq(fauna.count(id), 0, "none at the start")
	assert_true(species.get_def(&"bear").strength > species.get_def(&"wolf").strength, "a bear takes more bringing down")
	assert_true(species.get_def(&"bear").winter_sleep)
	assert_true(species.get_def(&"wolf").group_max > 1, "wolves in packs")


func test_the_land_they_like() -> void:
	var world := WorldData.create_centered(32, 16, 0.4)
	var lion := species.get_def(&"lion")
	var bear := species.get_def(&"bear")
	var low := Vector2i(-10, -10)
	var high := Vector2i(10, 8)
	assert_true(world.is_in_bounds(low) and world.is_in_bounds(high))
	world.set_height(high, 6)
	assert_true(PredatorHabitat.score(world, null, lion, high, 0) > PredatorHabitat.score(world, null, lion, low, 0),
		"a lion likes the high ground")
	world.set_water(low + Vector2i(3, 0), 1.0)
	assert_true(PredatorHabitat.score(world, null, bear, low, 0) > PredatorHabitat.score(world, null, bear, high, 0),
		"a bear likes water near")


func test_none_in_the_first_year_then_rarely() -> void:
	# (Days lived one by one: the first year none come; over the next years,
	# about one every year or few.)
	var came := []
	fauna.arrived.connect(func(kind: StringName, _group: int, at: Vector2) -> void:
		came.append([kind, session.clock.tick, at]))
	var year := Config.time.ticks_per_year()
	while session.clock.tick < year - DAY:
		session.clock.tick += DAY
		fauna.skip_to(session.clock.tick)
	assert_eq(came.size(), 0, "none in a world's first year")
	for day in Config.time.days_per_year() * 6:
		session.clock.tick += DAY
		fauna.skip_to(session.clock.tick)
	assert_true(came.size() >= 1 and came.size() <= 10, "now and then over six years: %d" % came.size())
	for visit: Array in came:
		var distance := (visit[2] as Vector2).distance_to(_fire())
		assert_true(distance >= AnimalSystem.ARRIVE_FROM - 1.0 and distance <= AnimalSystem.ARRIVE_TO + 1.0,
			"%s came at %.0f tiles" % [visit[0], distance])
		assert_ne(visit[0], &"bear" if Config.time.season_of(visit[1]) == Seasons.WINTER else &"", "no bear in winter")


func test_one_at_a_time_and_they_move_on() -> void:
	session.clock.tick = Config.time.ticks_per_year() * 2 + 2 * DAY # (spring, year 3)
	fauna.last_tick = session.clock.tick
	var at := _fire() + Vector2(24.0, 0.0)
	var pack := fauna.bring(&"wolf", at, session.clock.tick)
	assert_true(pack.size() >= 3, "a pack")
	assert_eq(fauna.visitors().size(), pack.size())
	var gone := []
	fauna.left.connect(func(kind: StringName, group: int) -> void: gone.append([kind, group]))
	var came := 0
	fauna.arrived.connect(func(_kind: StringName, _group: int, _at: Vector2) -> void: came += 1)
	var until := fauna.stays_until(pack[0].group)
	assert_true(until > session.clock.tick)
	while session.clock.tick < until + DAY and gone.is_empty():
		session.clock.tick += DAY
		fauna.skip_to(session.clock.tick)
	assert_eq(gone, [[&"wolf", pack[0].group]], "back to the wilds when its stay is over")
	assert_eq(came, 0, "nothing else came while it was there")
	assert_eq(fauna.count(&"wolf"), 0)


func test_they_keep_off_the_fire() -> void:
	session.clock.tick = Config.time.ticks_per_year() * 2 + 2 * DAY + 12 * 60
	fauna.last_tick = session.clock.tick
	var bear: AnimalData = fauna.bring(&"bear", _fire() + Vector2(9.0, 0.0), session.clock.tick)[0]
	var nearest := INF
	for i in 48:
		_animals_live(60)
		if animals.has_animal(bear.id):
			nearest = minf(nearest, bear.position.distance_to(_fire()))
	assert_true(nearest >= AnimalSystem.FIRE_CLEAR - 1.0, "no nearer the fire than %.1f" % nearest)


func test_a_bear_sleeps_the_winter() -> void:
	var winter := Config.time.ticks_per_year() * 2 + 3 * Config.time.days_per_season * DAY + 2 * DAY + 12 * 60
	session.clock.tick = winter
	fauna.last_tick = winter
	var bear: AnimalData = fauna.bring(&"bear", _fire() + Vector2(20.0, 0.0), winter)[0]
	var from := bear.position
	_animals_live(6 * 60)
	assert_eq(bear.state, AnimalData.State.SLEEP, "asleep at noon in winter")
	assert_true(bear.position.distance_to(from) < 0.5, "and where it is")


func test_saved_and_restored() -> void:
	session.clock.tick = Config.time.ticks_per_year() * 2
	fauna.last_tick = session.clock.tick
	var lion: AnimalData = fauna.bring(&"lion", _fire() + Vector2(0.0, 25.0), session.clock.tick)[0]
	var until := fauna.stays_until(lion.group)
	var saved := fauna.to_dict()
	var again := AnimalSystem.new()
	again.bind(session.world, session.props, session.people, AnimalRegistry.new(), species, session.ids, session.start,
		RandomNumberGenerator.new())
	assert_eq(again.from_dict(saved), 0)
	assert_eq(again.count(&"lion"), 1)
	assert_eq(again.stays_until(lion.group), until, "and how long it stays")
