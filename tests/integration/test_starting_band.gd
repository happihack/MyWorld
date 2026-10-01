extends TestCase
## The people a world begins with (M4.1), and their place in the save.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const V3_FIXTURE := "res://tests/fixtures/saves/v3_world.sav"
const SEEDS: Array[int] = [12345, 777, 4242, 99, 31337, 2026]

var sessions: Array[WorldSession] = []


func before_each() -> void:
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)


func after_each() -> void:
	SaveManager.attach(null)
	for s in sessions:
		if is_instance_valid(s):
			s.queue_free()
	sessions.clear()
	await wait_frames(1)


func _session() -> WorldSession:
	var s: WorldSession = SessionScript.new()
	add_child(s)
	sessions.append(s)
	return s


func _world(seed_value: int) -> WorldSession:
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


func _age(s: WorldSession, p: PersonData) -> int:
	return p.age_years(s.clock.tick, Config.time.ticks_per_year())


func _stage(s: WorldSession, p: PersonData) -> PersonData.LifeStage:
	return p.life_stage(s.clock.tick, Config.time.ticks_per_year(), Config.people)


# --- who they are -------------------------------------------------------------------------------

func test_household_plans_fit_the_band_the_config_asks_for() -> void:
	var rng := RandomNumberGenerator.new()
	var sizes := {}
	var household_counts := {}
	for seed_value in 400:
		rng.seed = seed_value
		var plans := StartingBand.plan_households(rng, Config.people)
		var total := 0
		var children := 0
		var elders := 0
		for roles in plans:
			total += roles.size()
			children += roles.count(StartingBand.Role.CHILD)
			elders += roles.count(StartingBand.Role.ELDER)
			# Parents come in pairs; nobody is a child without them.
			assert_eq(roles.count(StartingBand.Role.MOTHER), roles.count(StartingBand.Role.FATHER))
			if roles.has(StartingBand.Role.CHILD):
				assert_true(roles.has(StartingBand.Role.MOTHER))
		if total < Config.people.band_min_people or total > Config.people.band_max_people:
			fail("band of %d (seed %d)" % [total, seed_value])
		if plans.size() < Config.people.band_min_households or plans.size() > Config.people.band_max_households:
			fail("%d households (seed %d)" % [plans.size(), seed_value])
		if children < 1 or elders < 1:
			fail("a band needs its young and its old (seed %d: %d children, %d elders)" % [seed_value, children, elders])
		sizes[total] = true
		household_counts[plans.size()] = true
	assert_eq(sizes.size(), 3, "bands of 6, 7 and 8 all occur")
	assert_eq(household_counts.size(), 2, "with 2 and with 3 households")


func test_other_band_sizes_can_be_asked_for() -> void:
	var config := PeopleConfig.new()
	config.band_min_people = 12
	config.band_max_people = 14
	config.band_min_households = 3
	config.band_max_households = 3
	assert_eq(config.validate().size(), 0)
	var rng := RandomNumberGenerator.new()
	for seed_value in 50:
		rng.seed = seed_value
		var total := 0
		for roles in StartingBand.plan_households(rng, config):
			total += roles.size()
		assert_true(total >= 12 and total <= 14, "band of %d" % total)
	config.band_max_people = 3
	assert_true(config.validate().size() >= 1, "nonsense is reported")


func test_a_new_world_has_its_first_band() -> void:
	for seed_value in SEEDS:
		var s := _world(seed_value)
		var band := s.people.all_people()
		var label := "seed %d" % seed_value
		assert_true(band.size() >= 6 and band.size() <= 8, "%s: %d people" % [label, band.size()])
		var households := s.people.household_ids()
		assert_true(households.size() >= 2 and households.size() <= 3, "%s: %d households" % [label, households.size()])
		assert_true(s.start.settlement_id > 0, "the settlement has an id")
		assert_eq(s.people.in_settlement(s.start.settlement_id).size(), band.size(), "all of one settlement")

		var ids := {}
		var given := {}
		var tiles := {}
		var homes := {}
		var has_child := false
		var has_elder := false
		var adult_occupations := {}
		for p in band:
			# Ids come from the world's allocator and are nobody else's.
			assert_true(p.id > 0 and p.id < s.ids.peek() and not PropData.is_generated_id(p.id))
			assert_null(s.props.get_prop(p.id))
			assert_false(ids.has(p.id))
			ids[p.id] = true
			assert_false(given.has(p.given_name), "%s: two called %s" % [label, p.given_name])
			given[p.given_name] = true
			assert_true(NameGenerator.is_acceptable(p.given_name) and NameGenerator.is_acceptable(p.family_name), p.full_name())
			# Where they stand.
			assert_false(tiles.has(p.position), "%s: two people on %s" % [label, p.position])
			tiles[p.position] = true
			assert_true(WorldSetup.is_walkable(s.world, p.position))
			assert_eq(s.world.get_water(p.position), 0.0, "dry feet")
			assert_null(s.props.prop_at(p.position), "not inside a hut, a tree or the fire")
			assert_eq(s.loose.objects_at(p.position).size(), 0, "nor on a rock")
			var home := s.props.get_prop(p.home_building_id)
			assert_not_null(home, "%s has a home" % p.given_name)
			assert_eq(home.kind, PropData.Kind.HUT)
			assert_true(s.start.hut_ids.has(p.home_building_id))
			var from_home := p.position - home.tile
			assert_true(maxi(absi(from_home.x), absi(from_home.y)) <= Config.people.spawn_radius_tiles, "near home")
			assert_eq(s.spatial.get_kind(p.id), SpatialIndex.KIND_PERSON)
			assert_eq(s.spatial.get_position(p.id), p.world2d())
			var to_fire := (Vector2(s.start.settlement_tile) + Vector2(0.5, 0.5) - p.world2d()).normalized()
			assert_true(Vector2.from_angle(p.facing).dot(to_fire) > 0.99, "turned to the fire")
			homes[p.household_id] = p.home_building_id
			# Who they are.
			var stage := _stage(s, p)
			var def := s.occupations.get_def(p.occupation_id)
			assert_not_null(def, "%s has an occupation (%s)" % [p.given_name, p.occupation_id])
			assert_true(def.allows(stage), "%s: a %s aged %d" % [label, p.occupation_id, _age(s, p)])
			assert_false(def.placeholder)
			assert_eq(p.traits.size(), Traits.COUNT)
			assert_true(p.health > 0.6 and p.health <= 1.0)
			assert_true(p.birth_tick < 0, "born before the world's first tick")
			for key: String in ["height", "build", "skin", "hair", "cloth"]:
				assert_true(p.appearance.has(key), key)
			assert_true(int(p.appearance["skin"]) < PersonData.SKIN_TONES)
			assert_eq(p.needs.size(), 0, "needs come with M4.4")
			assert_eq(p.current_action, {})
			if stage == PersonData.LifeStage.CHILD:
				has_child = true
				assert_eq(p.skills.size(), 0)
			if stage == PersonData.LifeStage.ELDER:
				has_elder = true
			if stage == PersonData.LifeStage.ADULT:
				adult_occupations[p.occupation_id] = true
				assert_true(float(p.skills.get(String(p.occupation_id), 0.0)) >= 0.2, "knows the work")
		assert_true(has_child, "%s: the band has its young" % label)
		assert_true(has_elder, "%s: and its old" % label)
		assert_true(adult_occupations.has(&"forager") and adult_occupations.has(&"woodcutter"),
			"%s: someone forages and someone cuts wood (%s)" % [label, adult_occupations.keys()])
		var distinct_homes := {}
		for household: int in homes:
			distinct_homes[homes[household]] = true
		assert_eq(distinct_homes.size(), homes.size(), "%s: a hut for each household" % label)


func test_households_are_families() -> void:
	for seed_value in SEEDS:
		var s := _world(seed_value)
		for household in s.people.household_ids():
			var members := s.people.in_household(household)
			assert_true(members.size() >= 1)
			var family := members[0].family_name
			for p in members:
				assert_eq(p.family_name, family, "a household shares its name")
				assert_eq(p.home_building_id, members[0].home_building_id, "and its roof")
				if p.partner_id != 0:
					var partner := s.people.get_person(p.partner_id)
					assert_not_null(partner)
					assert_eq(partner.partner_id, p.id, "partners are each other's")
					assert_eq(partner.household_id, p.household_id)
					assert_eq(_stage(s, p), PersonData.LifeStage.ADULT)
				for parent_id in p.parents:
					var parent := s.people.get_person(parent_id)
					assert_not_null(parent, "parents are of the band")
					assert_true(parent.children.has(p.id), "and know their children")
					assert_eq(parent.household_id, p.household_id)
					assert_true(_age(s, parent) - _age(s, p) >= Config.people.adult_from_years,
						"%s (%d) is old enough to be the parent of %s (%d)" % [parent.given_name, _age(s, parent), p.given_name, _age(s, p)])
				if _stage(s, p) == PersonData.LifeStage.CHILD:
					assert_eq(p.parents.size(), 2, "a child has a mother and a father")
					assert_eq(s.people.get_person(p.parents[0]).sex, PersonData.Sex.FEMALE)
					assert_eq(s.people.get_person(p.parents[1]).sex, PersonData.Sex.MALE)
					var skin: int = p.appearance["skin"]
					assert_true(skin == s.people.get_person(p.parents[0]).appearance["skin"]
						or skin == s.people.get_person(p.parents[1]).appearance["skin"], "takes after a parent")
		var families := s.people.family_names()
		assert_eq(families.size(), s.people.household_ids().size(), "each household its own name")


func test_the_same_seed_gives_the_same_people() -> void:
	var a := _world(12345)
	var b := _world(12345)
	assert_eq(a.people.to_dict(), b.people.to_dict())
	assert_eq(a.start.settlement_id, b.start.settlement_id)
	var c := _world(777)
	var names_a: Array[String] = []
	var names_c: Array[String] = []
	for p in a.people.all_people():
		names_a.append(p.full_name())
	for p in c.people.all_people():
		names_c.append(p.full_name())
	assert_ne(names_a, names_c, "another world, other people")
	assert_ne(a.names.phonology.onsets, c.names.phonology.onsets, "who sound different")


func test_spawning_the_band_does_not_disturb_other_dice() -> void:
	# Each system has its own stream: the people's dice are not the touch dice.
	var s := _world(12345)
	var states: Dictionary = s.rng.to_dict()["states"]
	assert_true(states.has("people"))
	assert_false(states.has("interaction"), "untouched until the player touches something")


# --- saving -------------------------------------------------------------------------------------

func test_people_are_saved_with_the_world() -> void:
	var s := _world(12345)
	var before := s.people.to_dict()
	var first := s.people.all_people()[0]
	s.people.move(first.id, first.position + Vector2i(1, 0), Vector2(0.25, 0.25), 1.0)
	first.set_flag(PersonData.FLAG_MARKED_IMPORTANT, true)
	var moved := s.people.to_dict()
	assert_ne(moved, before)

	var again := _save_and_reload(s)
	assert_eq(again.people.to_dict(), moved, "the same people, where they were")
	assert_eq(again.people.size(), s.people.size())
	assert_eq(again.start.settlement_id, s.start.settlement_id)
	assert_eq(again.spatial.get_position(first.id), first.world2d())
	assert_true(again.people.get_person(first.id).has_flag(PersonData.FLAG_MARKED_IMPORTANT))
	assert_eq(again.ids.peek(), s.ids.peek(), "ids continue where they left off")
	assert_eq(again.rng.to_dict(), s.rng.to_dict(), "and so do the dice")
	assert_eq(again.names.phonology.onsets, s.names.phonology.onsets, "newcomers will sound like them")
	# A third generation of the save is still the same.
	assert_eq(_save_and_reload(again).people.to_dict(), moved)


func test_a_world_whose_people_are_gone_stays_empty() -> void:
	var s := _world(12345)
	for p in s.people.all_people():
		s.people.remove(p.id)
	assert_eq(s.people.size(), 0)
	var again := _save_and_reload(s)
	assert_eq(again.people.size(), 0, "no new band appears by itself")
	assert_eq(again.spatial.query_radius(Vector2(again.start.settlement_tile), 50.0, SpatialIndex.KIND_PERSON).size(), 0)


func test_unusable_people_data_brings_a_new_band() -> void:
	var s := _world(12345)
	var data := s.to_dict()
	data["world_state"]["people"] = {"persons": "broken"}
	Log.console_output = false
	var again := _session()
	assert_true(again.load_from(data), "the world still loads")
	assert_true(again.people.size() >= 6, "and is not left empty by a damaged record")
	for p in again.people.all_people():
		assert_true(p.id >= s.ids.peek(), "the new people have ids of their own")
	# Single bad records are skipped; the others stay who they were.
	data = s.to_dict()
	(data["world_state"]["people"]["persons"] as Array)[0] = {"id": "nobody"}
	Log.console_output = false
	var partly := _session()
	assert_true(partly.load_from(data))
	assert_eq(partly.people.size(), s.people.size() - 1)


func test_ids_stay_clear_of_saved_people_even_with_a_stale_allocator() -> void:
	var s := _world(12345)
	var data := s.to_dict()
	data["ids"] = {"next_id": 2}
	var again := _session()
	assert_true(again.load_from(data))
	var highest := 0
	for p in again.people.all_people():
		highest = maxi(highest, p.id)
	assert_true(again.ids.next_id() > highest)


func test_version_3_save_migrates_and_its_first_band_arrives() -> void:
	# The fixture was written by the last build without people (bc5f82b): seed
	# 12345, a rock carried to the huts, a tree uprooted, water in hand.
	assert_true(FileAccess.file_exists(V3_FIXTURE), "fixture present")
	var id := "w1790836236_7409924f"
	var dir := SaveManager.world_dir(id)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V3_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 3)

	var loaded := SaveManager.load_world(id)
	assert_true(loaded.ok, loaded.error)
	assert_eq(loaded.world["world_state"]["people"], {}, "migration: nobody has arrived yet")
	var s := _session()
	assert_true(s.load_from(loaded.world))
	# Everything that world already was, it still is.
	assert_eq(s.clock.tick, 1000)
	assert_eq(s.start.settlement_tile, Vector2i(11, 9))
	assert_eq(s.loose.get_object(4611826756259676167).moved_count, 1, "the rock by the huts")
	assert_null(s.props.prop_at(Vector2i(-8, -32)), "the uprooted tree")
	assert_near(s.water.carried, 0.3, 0.0001)
	var rock_tile := s.loose.get_object(4611826756259676167).tile()
	assert_eq(s.history.total(), 3)
	# And now it has people — with ids above everything it already had.
	assert_true(s.people.size() >= 6 and s.people.size() <= 8)
	assert_true(s.start.settlement_id >= 7)
	for p in s.people.all_people():
		assert_true(p.id > s.start.settlement_id)
		assert_null(s.loose.get_object(p.id))
		assert_ne(p.position, rock_tile, "nobody stands on the rock the player left by the huts")
		assert_true(_age(s, p) >= 1)
	# The same save always gets the same band ...
	var twin := _session()
	assert_true(twin.load_from(SaveManager.load_world(id).world))
	assert_eq(twin.people.to_dict(), s.people.to_dict())
	# ... and once saved, they are simply its people.
	assert_true(SaveManager.save_world(s, &"test"))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav.bak1")).header["save_version"], 3)
	var again := _session()
	assert_true(again.load_from(SaveManager.load_world(id).world))
	assert_eq(again.people.to_dict(), s.people.to_dict())
	assert_eq(again.ids.peek(), s.ids.peek())


func test_the_running_game_keeps_its_people_across_a_relaunch() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	var s: WorldSession = get_tree().current_scene.get_node("WorldSession")
	assert_true(s.people.size() >= 6, "the game opens on an inhabited world")
	var people := s.people.to_dict()
	var world_id := s.world_id
	await wait_real_ms(Config.save.min_save_gap_ms + 100)
	get_tree().unload_current_scene()
	await wait_frames(2)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	var s2: WorldSession = get_tree().current_scene.get_node("WorldSession")
	assert_eq(s2.world_id, world_id)
	assert_eq(s2.people.to_dict(), people, "the same people after a relaunch")
	get_tree().unload_current_scene()
	await wait_frames(2)
