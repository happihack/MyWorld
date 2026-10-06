extends TestCase
## The disasters the player brings down (the owner's design, 2026-10-05):
## each does what it should, harms what it should and nothing else, is
## noticed, written down, one at a time with a day's rest after it, and
## kept with the world.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440

var session: WorldSession
var disasters: DisasterSystem
var clock: GameClock
var stimuli: Array[Stimulus] = []
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
	session.behavior.enabled = false
	disasters = session.disasters
	clock = session.clock
	for knob: StringName in [&"base_death_per_year", &"infant_death_per_year", &"old_age_death_per_year",
			&"accident_per_work_day", &"crowding_chance_per_day", &"partner_chance_per_day", &"conceive_chance_per_day",
			&"starve_chance_per_day", &"illness_death_per_day", &"injury_death_per_day", &"newcomer_chance_per_day"]:
		_knob(Config.life, knob, 0.0)
	stimuli.clear()
	session.interactions.stimulus_emitted.connect(func(stimulus: Stimulus) -> void: stimuli.append(stimulus))


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


func _fire() -> Vector2:
	return session.settlement.fire().position2d()


## The clock moves on `minutes`, and what goes by it with it.
func _pass(minutes: int) -> void:
	clock.tick += minutes
	disasters.advance_to(clock.tick)


func _trees() -> int:
	var n := 0
	for prop in session.props.all_props():
		if prop.kind == PropData.Kind.TREE and not prop.felled:
			n += 1
	return n


func _condition_sum() -> int:
	var sum := 0
	for prop in session.props.all_props():
		if prop.is_building() and prop.kind != PropData.Kind.BRIDGE:
			sum += prop.condition
	return sum


func test_one_at_a_time_and_a_day_of_rest() -> void:
	assert_eq(DisasterSystem.KINDS.size(), 7)
	assert_true(bool(Settings.get_value(&"gameplay/gentle_hands")), "gentle hands are on")
	var iv := session.interactions.disaster(DisasterSystem.ECLIPSE, _fire())
	assert_true(iv.applied, "asked for and confirmed: not held back by gentle hands (%s)" % iv.rejected)
	assert_eq(iv.severity, Intervention.Severity.MAJOR)
	assert_eq(session.history.count(Intervention.DISASTER, DisasterSystem.ECLIPSE), 1, "in the player's history")
	assert_true(disasters.is_active())
	var again := session.interactions.disaster(DisasterSystem.EARTHQUAKE, _fire())
	assert_false(again.applied, "one at a time")
	assert_eq(again.rejected, &"resting")
	_pass(int(DisasterSystem.LASTS[DisasterSystem.ECLIPSE]))
	assert_false(disasters.is_active(), "over")
	assert_false(disasters.can_start(clock.tick), "the world rests")
	assert_eq(disasters.rest_left(clock.tick), DisasterSystem.REST_MINUTES)
	_pass(DisasterSystem.REST_MINUTES)
	assert_true(disasters.can_start(clock.tick), "a day later, another")
	assert_false(session.interactions.disaster(&"plague", _fire()).applied, "no such disaster")


func test_the_earthquake_shakes_what_stands_near() -> void:
	var before := _condition_sum()
	var trees := _trees()
	assert_true(session.interactions.disaster(DisasterSystem.EARTHQUAKE, _fire()).applied)
	assert_true(_condition_sum() < before, "what is built is damaged")
	assert_true(_trees() <= trees)
	assert_eq(session.events.of_type(&"earthquake").size(), 1, "written down")
	assert_eq(EventText.text(session.events.of_type(&"earthquake")[0], session.people, session.events), "The earth has shaken")
	assert_true(stimuli.any(func(s: Stimulus) -> bool: return s.type == Stimulus.EARTHQUAKE and s.radius >= 30.0), "felt far and wide")
	# Far from where it struck, nothing is touched.
	var far := DisasterSystem.new()
	far.bind(session)
	var buildings := far._buildings_near(_fire() + Vector2(1000, 1000), DisasterSystem.QUAKE_REACH)
	assert_true(buildings.is_empty())


func test_those_caught_in_it_may_be_hurt_but_not_those_far_off() -> void:
	var people := session.people.all_people()
	var near := people[0]
	var far := people[1]
	session.people.move(near.id, WorldCoords.world2d_to_tile(_fire()) + Vector2i(1, 0))
	session.people.move(far.id, WorldCoords.world2d_to_tile(_fire()) + Vector2i(12, 12))
	var far_health := far.health
	_knob(Config.life, &"injury_health", Config.life.injury_health)
	var hurt := 0
	# (The odds: many quakes, each a day and more apart.)
	for n in 30:
		disasters.rest_until = 0
		disasters.start(DisasterSystem.EARTHQUAKE, near.world2d(), clock.tick)
		_pass(DisasterSystem.LASTS[DisasterSystem.EARTHQUAKE])
		if session.people.get_person(near.id) == null:
			break
		if not near.injuries.is_empty():
			hurt += 1
			near.injuries.clear()
			near.health = 1.0
	assert_true(hurt > 0 or session.people.get_person(near.id) == null, "at its heart, people are hurt")
	assert_eq(far.health, far_health, "far off, nobody")
	assert_true(far.injuries.is_empty())


func test_the_eclipse_and_the_blood_harm_nobody() -> void:
	var before := _condition_sum()
	var trees := _trees()
	var living := session.people.size()
	assert_true(session.interactions.disaster(DisasterSystem.ECLIPSE, _fire()).applied)
	assert_eq(disasters.eclipse_amount(clock.tick), 0.0, "it begins in daylight")
	_pass(35)
	assert_near(disasters.eclipse_amount(clock.tick), 1.0, 0.01, "the sun is gone")
	assert_true(stimuli.any(func(s: Stimulus) -> bool: return s.type == Stimulus.ECLIPSE and s.anomalous))
	_pass(40)
	assert_eq(disasters.eclipse_amount(clock.tick), 0.0)
	disasters.rest_until = 0
	assert_true(session.interactions.disaster(DisasterSystem.BLOOD, _fire()).applied)
	_pass(120)
	assert_near(disasters.blood_amount(clock.tick), 1.0, 0.01, "the waters are blood")
	assert_true(disasters.water_is_blood())
	# Nobody drinks it.
	var person := session.people.all_people()[0]
	assert_eq(Planner.plan(&"drink", person, session.behavior.ctx), [], "nobody drinks blood")
	_pass(DAY)
	assert_false(disasters.water_is_blood())
	assert_false(Planner.plan(&"drink", person, session.behavior.ctx).is_empty(), "water again")
	assert_eq(_condition_sum(), before)
	assert_eq(_trees(), trees)
	assert_eq(session.people.size(), living)
	assert_eq(session.events.of_type(&"blood_water").size(), 1)


func test_the_storm_and_the_flood_are_the_weathers_and_the_rivers() -> void:
	assert_true(session.interactions.disaster(DisasterSystem.STORM, _fire()).applied)
	session.weather.advance_to(clock.tick)
	assert_eq(session.weather.state, WeatherSystem.STORM)
	assert_true(session.weather.is_held())
	_pass(DisasterSystem.LASTS[DisasterSystem.STORM])
	disasters.rest_until = 0
	var level := session.hydrology.level
	assert_true(session.interactions.disaster(DisasterSystem.FLOOD, _fire()).applied)
	assert_true(session.hydrology.level > level, "the river rises")
	assert_near(session.hydrology.level, Config.hydrology.highest, 0.001, "as high as it goes")
	assert_eq(session.weather.state, WeatherSystem.HEAVY_RAIN)


func test_the_whirlwind_crosses_the_land() -> void:
	var trees := _trees()
	assert_true(session.interactions.disaster(DisasterSystem.TORNADO, _fire()).applied)
	var from := disasters.tornado_at(clock.tick)
	var shown: Array = []
	disasters.struck.connect(func(kind: StringName, at: Vector2, _size: float) -> void: shown.append(at))
	_pass(DisasterSystem.LASTS[DisasterSystem.TORNADO] / 2)
	assert_near(disasters.tornado_at(clock.tick).distance_to(_fire()), 0.0, 1.5, "through where it was aimed")
	_pass(DisasterSystem.LASTS[DisasterSystem.TORNADO])
	assert_near(disasters.tornado_at(disasters.until).distance_to(from), DisasterSystem.TORNADO_TRAVEL, 2.5, "a long way")
	assert_true(shown.size() >= DisasterSystem.LASTS[DisasterSystem.TORNADO] - 1, "seen all the way")
	assert_true(_trees() <= trees)
	assert_false(disasters.is_active())


func test_stars_fall_and_burn_where_they_land() -> void:
	var stones := _boulders()
	assert_true(session.interactions.disaster(DisasterSystem.METEORS, _fire()).applied)
	assert_eq(disasters.stars_to_come().size(), DisasterSystem.METEOR_COUNT)
	var landed: Array = []
	disasters.struck.connect(func(kind: StringName, at: Vector2, _size: float) -> void: landed.append(at))
	_pass(DisasterSystem.LASTS[DisasterSystem.METEORS])
	assert_eq(landed.size(), DisasterSystem.METEOR_COUNT, "all of them")
	for at: Vector2 in landed:
		assert_true(at.distance_to(_fire()) <= DisasterSystem.METEOR_REACH + 0.01)
	assert_eq(_boulders(), stones + DisasterSystem.METEOR_COUNT, "a stone from the sky where each came down")
	var ash := 0
	for at: Vector2 in landed:
		if session.world.get_terrain(WorldCoords.world2d_to_tile(at)) == ChunkData.Terrain.ASH:
			ash += 1
	assert_true(ash > 0, "scorched ground (%d)" % ash)


func _boulders() -> int:
	var n := 0
	for object in session.loose.all_objects():
		if object.kind == LooseObject.Kind.BOULDER:
			n += 1
	return n


func test_kept_with_the_world() -> void:
	assert_true(session.interactions.disaster(DisasterSystem.METEORS, _fire()).applied)
	_pass(6)
	var to_come := disasters.stars_to_come()
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	assert_true(loaded.ok, loaded.error)
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(loaded.world))
	again.set_process(false)
	assert_eq(again.disasters.kind, DisasterSystem.METEORS, "still going on")
	assert_eq(again.disasters.until, disasters.until)
	assert_eq(again.disasters.stars_to_come(), to_come, "the same stars still to fall")
	again.clock.tick = disasters.until
	again.disasters.advance_to(again.clock.tick)
	assert_false(again.disasters.is_active())
	assert_eq(again.disasters.rest_until, disasters.until + DisasterSystem.REST_MINUTES)
	again.queue_free()
