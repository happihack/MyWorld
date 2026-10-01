extends TestCase
## People across saves (M4.6): the version-4 fixture, what the band knows,
## nobody saved "behind", the running game resumed — and the debug commands
## that bring people into the world and take them out of it.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const V4_FIXTURE := "res://tests/fixtures/saves/v4_world.sav"
const V4_ID := "w1790849320_bae975ac"
const YEAR := 1440 * 24
const FRAME := 1.0 / 60.0

var sessions: Array[WorldSession] = []


func before_each() -> void:
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()


func after_each() -> void:
	SaveManager.attach(null)
	for s in sessions:
		if is_instance_valid(s):
			s.queue_free()
	sessions.clear()
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
	await wait_frames(2)


func _session() -> WorldSession:
	var s: WorldSession = SessionScript.new()
	add_child(s)
	s.set_process(false) # the tests are the frames
	s.loose_system.set_process(false)
	s.water.set_process(false)
	sessions.append(s)
	return s


func _world(seed_value: int = 12345) -> WorldSession:
	var s := _session()
	s.create_new(seed_value)
	return s


func _save_and_reload(s: WorldSession) -> WorldSession:
	assert_true(SaveManager.save_world(s, &"test"))
	var loaded := SaveManager.load_world(s.world_id)
	assert_true(loaded.ok, loaded.error)
	var again := _session()
	assert_true(again.load_from(loaded.world))
	return again


func _frames(s: WorldSession, count: int) -> void:
	for i in count:
		s.simulation.advance(FRAME)


# --- the version-4 fixture ------------------------------------------------------------------------

func test_version_4_save_migrates_and_its_people_start_living() -> void:
	# Written by M4.3 (2157016): eight people called to a spot and on their
	# way there — who have no needs, no plans and no behaviour yet.
	assert_true(FileAccess.file_exists(V4_FIXTURE), "fixture present")
	var dir := SaveManager.world_dir(V4_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V4_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 4)

	var loaded := SaveManager.load_world(V4_ID)
	assert_true(loaded.ok, loaded.error)
	assert_eq(loaded.world["world_state"]["behavior"], {}, "migration: nothing known of the world yet")
	for record: Dictionary in loaded.world["world_state"]["people"]["persons"]:
		assert_eq((record["needs"] as PackedFloat32Array).size(), 0, "(a person from before needs)")
	var s := _session()
	assert_true(s.load_from(loaded.world))
	assert_eq(s.clock.tick, 306)
	assert_eq(s.people.size(), 8, "the same eight people")
	var first := s.people.get_person(7)
	assert_eq(first.full_name(), "Fubrudu Skadou")
	assert_eq(first.position, Vector2i(8, 8), "where the save left them, in mid-walk")
	assert_near(first.sub_tile_offset.y, 0.856727, 0.0001)
	# They have needs now — the same ones every time this save is opened.
	var needs := {}
	for p in s.people.all_people():
		assert_eq(p.needs.size(), Needs.COUNT)
		assert_true(p.needs[Needs.Need.HUNGER] >= 0.5)
		needs[p.id] = p.needs.duplicate()
	var twin := _session()
	assert_true(twin.load_from(SaveManager.load_world(V4_ID).world))
	for p in twin.people.all_people():
		assert_eq(p.needs, needs[p.id])
	# Time passes: everyone finds something to do.
	_frames(s, 120)
	for p in s.people.all_people():
		assert_ne(BehaviorSystem.activity_of(p), &"", "%s lives" % p.given_name)
	# Saved again: the current version; the old file is kept.
	assert_true(SaveManager.save_world(s, &"test"))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	assert_eq(SaveManager.SAVE_VERSION, 7)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav.bak1")).header["save_version"], 4)
	var again := _session()
	assert_true(again.load_from(SaveManager.load_world(V4_ID).world))
	assert_eq(again.people.to_dict(), s.people.to_dict(), "and they are who and where and at what they were")


func test_every_older_save_still_loads() -> void:
	# Versions 1 to 6, each written by the build of its day.
	var fixtures := {1: "w1790000000_fixture1", 2: "w1790835263_88a7bf97", 3: "w1790836236_7409924f", 4: V4_ID,
		5: "w1790867949_3c2d625b", 6: "w1790870731_6c3083c1"}
	for version: int in fixtures:
		var path := "res://tests/fixtures/saves/v%d_world.sav" % version
		var id: String = fixtures[version]
		var dir := SaveManager.world_dir(id)
		DirAccess.make_dir_recursive_absolute(dir)
		write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(path))
		var loaded := SaveManager.load_world(id)
		assert_true(loaded.ok, "version %d: %s" % [version, loaded.error])
		var s := _session()
		assert_true(s.load_from(loaded.world), "version %d loads" % version)
		assert_true(s.people.size() >= 6, "version %d: a world with people (%d)" % [version, s.people.size()])
		_frames(s, 90)
		for p in s.people.all_people():
			assert_ne(BehaviorSystem.activity_of(p), &"", "version %d: %s lives" % [version, p.given_name])
		assert_true(SaveManager.save_world(s, &"test"), "version %d saves as the current one" % version)


# --- what is saved --------------------------------------------------------------------------------

func test_what_the_band_knows_of_the_world_is_saved() -> void:
	var s := _world()
	var places := s.behavior.ctx.places
	assert_eq(places.visited_count(), 0)
	var here := s.start.settlement_tile + Vector2i(13, 2)
	var there := s.start.settlement_tile + Vector2i(-9, 14)
	places.mark_visited(here)
	places.mark_visited(there)
	assert_eq(s.to_dict()["world_state"]["behavior"]["visited"].size(), 2)
	var again := _save_and_reload(s)
	var known := again.behavior.ctx.places
	assert_eq(known.visited_count(), 2)
	assert_true(known.was_visited(here) and known.was_visited(there))
	assert_false(known.was_visited(s.start.settlement_tile + Vector2i(-20, -20)))
	assert_eq(known.visited_cells(), places.visited_cells())
	# Another world knows nothing of this one's.
	again.create_new(777)
	assert_eq(again.behavior.ctx.places.visited_count(), 0)
	# Broken data is ignored.
	var data := s.to_dict()
	data["world_state"]["behavior"] = {"visited": ["here", 4, Vector2i(1, 1)]}
	var odd := _session()
	assert_true(odd.load_from(data))
	assert_eq(odd.behavior.ctx.places.visited_count(), 1)
	data["world_state"]["behavior"] = "nonsense"
	var none := _session()
	assert_true(none.load_from(data))
	assert_eq(none.behavior.ctx.places.visited_count(), 0)


func test_nobody_is_saved_behind_their_time() -> void:
	var s := _world()
	var sleeper := s.people.all_people()[0]
	var walker := s.people.all_people()[1]
	sleeper.needs = Needs.full()
	sleeper.needs[Needs.Need.SLEEP] = 0.2
	s.clock.tick = 17 * 60 # eleven at night
	s.behavior.set_plan(sleeper, &"sleep", &"sleep", [SleepStep.make()], 5.0)
	var target := s.pathfinder.standable_near(s.start.settlement_tile + Vector2i(0, 12), 1)[0]
	s.behavior.set_plan(walker, BehaviorSystem.ACTIVITY_CALLED, &"", [WalkToStep.make(target)])
	var asleep_from := sleeper.needs[Needs.Need.SLEEP]
	var tick := s.clock.tick
	_frames(s, 30 * 7 + 11) # seven ticks and a bit: the sleeper's next turn is not due
	assert_true(s.simulation.pending_minutes(sleeper.id) > 1.0, "(time has built up for the sleeper: %.1f min)" % s.simulation.pending_minutes(sleeper.id))
	var data := s.to_dict()
	assert_near(s.simulation.pending_minutes(sleeper.id), 0.0, 0.0001, "saving lets everyone catch up")
	var elapsed := (s.clock.tick - tick) + s.clock.tick_fraction()
	var slept: float = (sleeper.needs[Needs.Need.SLEEP] - asleep_from) * Config.needs.full_sleep_minutes
	assert_near(slept, elapsed, 0.05, "the sleeper has slept all the time that passed")
	# What is in the save is that state: loading loses nothing.
	var again := _session()
	assert_true(again.load_from(bytes_to_var(var_to_bytes(data))))
	assert_near(again.people.get_person(sleeper.id).needs[Needs.Need.SLEEP], sleeper.needs[Needs.Need.SLEEP], 0.00001)
	assert_eq(again.people.get_person(walker.id).world2d(), walker.world2d(), "the walker is where the save put them")
	# Saving twice in a row changes nothing.
	var second: Dictionary = s.to_dict()["world_state"]["people"]
	assert_eq(second, data["world_state"]["people"])
	# A frozen world is saved as it stands: nobody lives, nobody walks.
	s.behavior.enabled = false
	var frozen := s.people.to_dict()
	_frames(s, 60)
	assert_true(s.movement.is_walking(walker.id), "(the walk is kept)")
	s.to_dict()
	assert_eq(s.people.to_dict(), frozen)
	# Thawed, the walker goes on.
	s.behavior.enabled = true
	_frames(s, 30)
	assert_ne(walker.world2d(), again.people.get_person(walker.id).world2d())


func test_the_running_game_resumes_where_it_was() -> void:
	# The M4 manual check, automated: relaunch -> same people, same tasks resumed.
	var first := _session()
	first.create_new(12345)
	SaveManager.save_world(first, &"test")
	first.queue_free()
	await wait_frames(2)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	var s: WorldSession = get_tree().current_scene.get_node("WorldSession")
	s.clock.set_speed(GameClock.SPEED_VERY_FAST)
	await wait_real_ms(2500) # about an hour and a half of the band's morning
	s.clock.set_speed(GameClock.SPEED_PAUSE) # (so that what is compared holds still)
	await wait_frames(2)
	s.simulation.settle() # (as saving will: everyone up to date)
	var was := {}
	var walking := 0
	for p in s.people.all_people():
		was[p.id] = [p.full_name(), BehaviorSystem.activity_of(p), BehaviorSystem.reason_of(p), BehaviorSystem.current_step(p).duplicate(true),
			p.world2d(), p.needs.duplicate(), p.has_flag(PersonData.FLAG_INDOORS)]
		if s.movement.is_walking(p.id):
			walking += 1
		assert_ne(BehaviorSystem.activity_of(p), &"")
	var tick := s.clock.tick
	await wait_real_ms(Config.save.min_save_gap_ms + 100)
	get_tree().unload_current_scene() # an orderly close saves
	await wait_frames(2)

	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	var s2: WorldSession = get_tree().current_scene.get_node("WorldSession")
	assert_eq(s2.clock.tick, tick, "the same moment")
	assert_eq(s2.people.size(), was.size(), "the same people")
	for p in s2.people.all_people():
		var then: Array = was[p.id]
		assert_eq(p.full_name(), then[0])
		assert_eq(BehaviorSystem.activity_of(p), then[1], "%s is still at it" % p.given_name)
		assert_eq(BehaviorSystem.reason_of(p), then[2])
		assert_eq(BehaviorSystem.current_step(p), then[3], "at the same step, as far along")
		assert_eq(p.world2d(), then[4], "in the same place")
		assert_eq(p.needs, then[5])
		assert_eq(p.has_flag(PersonData.FLAG_INDOORS), then[6])
	# Time goes on: whoever was on their way is on their way again.
	s2.clock.set_speed(GameClock.SPEED_NORMAL)
	await wait_real_ms(700)
	var walking_again := 0
	var moved := 0
	for p in s2.people.all_people():
		if s2.movement.is_walking(p.id):
			walking_again += 1
		if p.world2d() != was[p.id][4]:
			moved += 1
	if walking > 0:
		assert_true(moved > 0, "%d were walking when the game closed; %d have moved on since" % [walking, moved])
	print("    relaunch: %d people resumed (%d were walking, %d walking again)" % [was.size(), walking, walking_again])


# --- people into the world and out of it (debug) --------------------------------------------------

func test_someone_new_can_be_brought_into_the_world() -> void:
	var s := _world()
	var before := s.people.size()
	var born := []
	var listener := func(id: int) -> void: born.append(id)
	EventBus.person_born.connect(listener)
	var at := s.start.settlement_tile + Vector2i(1, 3)
	var newcomer := s.spawn_person(at)
	EventBus.person_born.disconnect(listener)
	assert_not_null(newcomer)
	assert_eq(s.people.size(), before + 1)
	assert_true(s.people.get_person(newcomer.id) == newcomer)
	assert_eq(born, [newcomer.id])
	# A whole person.
	assert_true(NameGenerator.is_acceptable(newcomer.given_name) and NameGenerator.is_acceptable(newcomer.family_name))
	var same_name := 0
	for p in s.people.all_people():
		if p.given_name == newcomer.given_name:
			same_name += 1
	assert_eq(same_name, 1, "a name of their own")
	assert_eq(newcomer.life_stage(s.clock.tick, YEAR, Config.people), PersonData.LifeStage.ADULT)
	assert_eq(newcomer.needs.size(), Needs.COUNT)
	assert_eq(newcomer.traits.size(), Traits.COUNT)
	assert_eq(newcomer.settlement_id, s.start.settlement_id)
	assert_true(s.start.hut_ids.has(newcomer.home_building_id), "a roof")
	assert_eq(s.people.in_household(newcomer.household_id).size(), 1, "a household of their own")
	var def := s.occupations.get_def(newcomer.occupation_id)
	assert_not_null(def)
	assert_true(def.allows(PersonData.LifeStage.ADULT))
	assert_true(s.pathfinder.can_stand(newcomer.position))
	assert_true((newcomer.position - at).length() <= 2.0, "where they were asked for")
	assert_eq(s.spatial.get_kind(newcomer.id), SpatialIndex.KIND_PERSON)
	# The roof with the fewest under it.
	var fewest := 99
	for hut in s.start.hut_ids:
		fewest = mini(fewest, s.people.living_in(hut).size() - (1 if hut == newcomer.home_building_id else 0))
	assert_eq(s.people.living_in(newcomer.home_building_id).size() - 1, fewest)
	# They live like everyone else, and are saved like everyone else.
	_frames(s, 120)
	assert_ne(BehaviorSystem.activity_of(newcomer), &"")
	assert_eq(newcomer.sim_tier, TierManager.ACTIVE)
	var again := _save_and_reload(s)
	assert_eq(again.people.get_person(newcomer.id).full_name(), newcomer.full_name())
	assert_true(again.ids.next_id() > newcomer.household_id)
	# Of any age.
	var child := s.spawn_person(at, PersonData.LifeStage.CHILD)
	assert_eq(child.life_stage(s.clock.tick, YEAR, Config.people), PersonData.LifeStage.CHILD)
	assert_eq(child.occupation_id, &"child")
	var elder := s.spawn_person(at, PersonData.LifeStage.ELDER)
	assert_eq(elder.life_stage(s.clock.tick, YEAR, Config.people), PersonData.LifeStage.ELDER)
	assert_ne(child.position, elder.position)
	# The same dice bring the same person.
	var a := _world(4242)
	var b := _world(4242)
	assert_eq(a.spawn_person(a.start.settlement_tile).to_dict(), b.spawn_person(b.start.settlement_tile).to_dict())


func test_someone_can_be_taken_out_of_the_world() -> void:
	var s := _world()
	var died := []
	var listener := func(id: int, cause: StringName) -> void: died.append([id, cause])
	EventBus.person_died.connect(listener)
	var victim: PersonData = null
	for p in s.people.all_people():
		if p.partner_id != 0:
			victim = p
			break
	var partner := s.people.get_person(victim.partner_id)
	_frames(s, 60)
	s.behavior.set_plan(partner, &"socialize", &"social", [SocializeStep.make(victim.id, 30.0)], 1.0)
	s.simulation.tiers.focus(victim.id)
	var before := s.people.size()
	assert_true(s.kill_person(victim.id))
	EventBus.person_died.disconnect(listener)
	assert_eq(died, [[victim.id, &"debug"]])
	assert_eq(s.people.size(), before - 1)
	assert_null(s.people.get_person(victim.id))
	assert_false(s.spatial.has(victim.id))
	assert_false(s.simulation.tiers.is_focused(victim.id))
	assert_false(s.movement.is_walking(victim.id))
	assert_eq(partner.partner_id, victim.id, "who they were to each other is not forgotten")
	assert_false(s.kill_person(victim.id), "only once")
	assert_false(s.kill_person(999_999))
	# Life goes on for the others (the partner's conversation is simply over).
	_frames(s, 240)
	assert_false(BehaviorSystem.activity_of(partner) == &"socialize" and int(BehaviorSystem.current_step(partner).get("partner", 0)) == victim.id)
	for p in s.people.all_people():
		assert_ne(BehaviorSystem.activity_of(p), &"")
	# And they stay gone.
	var again := _save_and_reload(s)
	assert_null(again.people.get_person(victim.id))
	assert_eq(again.people.size(), before - 1)
	# Everyone gone: an empty world that stays empty and does not trip.
	for p in s.people.all_people():
		s.kill_person(p.id)
	_frames(s, 60)
	assert_eq(s.people.size(), 0)
	assert_eq(s.simulation.last_lived, 0)
	assert_eq(_save_and_reload(s).people.size(), 0)


func test_no_settlement_no_newcomers() -> void:
	var s := _session()
	assert_null(s.spawn_person(Vector2i.ZERO), "no world at all")
	assert_false(s.kill_person(1))


# --- stranded --------------------------------------------------------------------------------------

func test_someone_stranded_is_put_on_firm_ground() -> void:
	var s := _world()
	var person := s.people.all_people()[0]
	s.behavior.enabled = false
	var where := person.position
	# The water rises around them: deep, on their tile and all about it.
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			s.world.set_water(where + Vector2i(dx, dy), 1.0)
			s.pathfinder.mark_dirty(where + Vector2i(dx, dy))
	assert_false(s.pathfinder.can_stand(where))
	Log.console_output = false
	var far := s.pathfinder.standable_near(s.start.settlement_tile + Vector2i(0, 8), 1)[0]
	s.movement.walk_to(person.id, far)
	s.pathfinder.serve(1_000_000)
	assert_false(s.movement.is_walking(person.id), "there is no way out of deep water")
	assert_eq(s.behavior.rescues, 1)
	assert_true(s.pathfinder.can_stand(person.position), "so they are put on the nearest firm ground")
	assert_true((person.position - where).length() <= 3.0, "close by (%s -> %s)" % [where, person.position])
	assert_eq(s.spatial.get_position(person.id), person.world2d())
	# From there they can walk again.
	s.movement.walk_to(person.id, far)
	s.pathfinder.serve(1_000_000)
	assert_true(s.movement.is_walking(person.id))
	# Someone who merely has no way to where they want to go is left where they are.
	var other: PersonData = null
	for p in s.people.all_people():
		if p.id != person.id and s.pathfinder.can_stand(p.position):
			other = p
	var stood := other.position
	var river_x := int(s.generator.river_center_x(s.start.settlement_tile.y))
	var side := -1 if s.start.settlement_tile.x > river_x else 1
	s.movement.walk_to(other.id, Vector2i(river_x + side * 12, s.start.settlement_tile.y))
	s.pathfinder.serve(1_000_000)
	assert_eq(other.position, stood)
	assert_eq(s.behavior.rescues, 1)
