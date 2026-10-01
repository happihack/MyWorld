extends TestCase
## The plan's `test_person_serialization`, with the rest of PersonData and the
## registry.

const YEAR := 1440 * 24

var config: PeopleConfig


func before_each() -> void:
	config = PeopleConfig.new()


func _person(id: int = 1) -> PersonData:
	var p := PersonData.new()
	p.id = id
	p.given_name = "Mara"
	p.family_name = "Velun"
	p.birth_tick = -20 * YEAR
	p.position = Vector2i(3, -4)
	return p


func _full() -> PersonData:
	var p := _person(41)
	p.sex = PersonData.Sex.MALE
	p.health = 0.8
	p.injuries = [{"kind": "sprain"}]
	p.conditions = ["cold"]
	p.traits = Traits.neutral()
	p.traits[Traits.Axis.CURIOSITY] = 0.75
	p.needs = PackedFloat32Array([0.25, 0.5])
	p.mood = 0.75
	p.stress = 0.25
	p.occupation_id = &"forager"
	p.skills = {"forager": 0.5}
	p.household_id = 9
	p.home_building_id = 3
	p.workplace_id = 5
	p.settlement_id = 6
	p.parents = PackedInt64Array([11, 12])
	p.children = PackedInt64Array([50])
	p.partner_id = 40
	p.memory_ids = PackedInt64Array([100, 101])
	p.beliefs = PackedFloat32Array([0.5])
	p.knowledge = {"fire": true}
	p.goals = [{"goal": "find_partner"}]
	p.current_action = {"step": "walk_to", "target": Vector2i(1, 1)}
	p.sub_tile_offset = Vector2(0.25, 0.75)
	p.facing = 1.5
	p.sim_tier = 4
	p.significance = 2.5
	p.flags = PersonData.FLAG_MARKED_IMPORTANT | PersonData.FLAG_TOUCHED_BY_PLAYER
	p.appearance = {"height": 1.05, "build": 0.95, "skin": 2, "hair": 1, "cloth": 4}
	return p


func test_a_new_person_is_healthy_and_unremarkable() -> void:
	var p := PersonData.new()
	assert_eq(p.id, 0)
	assert_eq(p.health, 1.0)
	assert_eq(p.traits, Traits.neutral())
	assert_eq(p.sub_tile_offset, Vector2(0.5, 0.5))
	assert_eq(p.flags, 0)
	assert_eq(p.partner_id, 0)


func test_names_and_place() -> void:
	var p := _person()
	assert_eq(p.full_name(), "Mara Velun")
	p.family_name = ""
	assert_eq(p.full_name(), "Mara")
	p.sub_tile_offset = Vector2(0.25, 0.75)
	assert_eq(p.world2d(), Vector2(3.25, -3.25))


func test_age_comes_from_the_clock() -> void:
	var p := _person()
	assert_eq(p.age_years(0, YEAR), 20)
	assert_eq(p.age_years(YEAR - 1, YEAR), 20)
	assert_eq(p.age_years(YEAR, YEAR), 21, "a year later, a year older")
	assert_eq(p.age_years(-30 * YEAR, YEAR), 0, "never negative")
	assert_eq(p.age_years(0, 0), 20 * YEAR, "a broken calendar does not divide by zero")


func test_life_stages_follow_age() -> void:
	var p := _person()
	p.birth_tick = 0
	assert_eq(p.life_stage(0, YEAR, config), PersonData.LifeStage.CHILD)
	assert_eq(p.life_stage(11 * YEAR, YEAR, config), PersonData.LifeStage.CHILD)
	assert_eq(p.life_stage(12 * YEAR, YEAR, config), PersonData.LifeStage.ADOLESCENT)
	assert_eq(p.life_stage(16 * YEAR, YEAR, config), PersonData.LifeStage.ADULT, "grown at 16 (bible 9.1)")
	assert_eq(p.life_stage(47 * YEAR, YEAR, config), PersonData.LifeStage.ADULT)
	assert_eq(p.life_stage(48 * YEAR, YEAR, config), PersonData.LifeStage.ELDER)
	config.elder_from_years = 40
	assert_eq(p.life_stage(41 * YEAR, YEAR, config), PersonData.LifeStage.ELDER, "the ages of life are data")


func test_flags() -> void:
	var p := _person()
	assert_false(p.has_flag(PersonData.FLAG_FOLLOWED))
	p.set_flag(PersonData.FLAG_FOLLOWED, true)
	p.set_flag(PersonData.FLAG_QUARANTINED, true)
	assert_true(p.has_flag(PersonData.FLAG_FOLLOWED))
	p.set_flag(PersonData.FLAG_FOLLOWED, false)
	assert_false(p.has_flag(PersonData.FLAG_FOLLOWED))
	assert_true(p.has_flag(PersonData.FLAG_QUARANTINED))


func test_person_serialization() -> void:
	var p := _full()
	var record := p.to_dict()
	var back := PersonData.from_dict(record)
	assert_not_null(back)
	assert_eq(back.to_dict(), record, "everything survives")
	assert_eq(back.full_name(), "Mara Velun")
	assert_eq(back.sex, PersonData.Sex.MALE)
	assert_eq(back.occupation_id, &"forager")
	assert_eq(back.parents, PackedInt64Array([11, 12]))
	assert_eq(back.current_action["target"], Vector2i(1, 1))
	assert_true(back.has_flag(PersonData.FLAG_TOUCHED_BY_PLAYER))
	assert_eq(back.sim_tier, PersonData.new().sim_tier, "the simulation tier is not saved")
	assert_false(record.has("sim_tier"))
	assert_false(record.has("age"), "age is never stored")
	# Through the same encoding the save file uses.
	var bytes := var_to_bytes(record)
	assert_eq(PersonData.from_dict(bytes_to_var(bytes)).to_dict(), record)
	# The copy shares nothing with the original.
	back.skills["forager"] = 0.9
	back.parents.append(99)
	assert_eq(p.skills["forager"], 0.5)
	assert_eq(p.parents.size(), 2)


func test_what_later_milestones_fill_is_saved_empty() -> void:
	var record := _person().to_dict()
	for key: String in ["needs", "memory_ids", "beliefs", "knowledge", "goals", "current_action", "injuries",
			"conditions", "skills", "children", "parents"]:
		assert_true(record.has(key), key)
		assert_eq(record[key].size(), 0, "%s is empty" % key)
	var back := PersonData.from_dict({"id": 5, "position": Vector2i.ZERO})
	assert_not_null(back, "a minimal record is a person")
	assert_eq(back.traits, Traits.neutral())
	assert_eq(back.health, 1.0)
	assert_eq(back.mood, 0.5)


func test_unusable_records_are_refused() -> void:
	assert_null(PersonData.from_dict({}))
	assert_null(PersonData.from_dict({"id": 0, "position": Vector2i.ZERO}))
	assert_null(PersonData.from_dict({"id": -3, "position": Vector2i.ZERO}))
	assert_null(PersonData.from_dict({"id": "7", "position": Vector2i.ZERO}))
	assert_null(PersonData.from_dict({"id": 7}))
	assert_null(PersonData.from_dict({"id": 7, "position": Vector2(1, 1)}))


func test_damaged_fields_fall_back_to_something_harmless() -> void:
	var record := _full().to_dict()
	record["health"] = NAN
	record["mood"] = 7.0
	record["stress"] = "calm"
	record["traits"] = PackedFloat32Array([4.0])
	record["needs"] = PackedFloat32Array([2.0, NAN])
	record["skills"] = "many"
	record["parents"] = PackedInt64Array([11, -2, 0])
	record["children"] = [1, 2]
	record["sub_tile_offset"] = Vector2(5.0, -1.0)
	record["facing"] = INF
	record["significance"] = -2.0
	record["sex"] = 9
	record["household_id"] = -4
	record["goals"] = null
	record["appearance"] = 3
	var p := PersonData.from_dict(record)
	assert_not_null(p)
	assert_eq(p.health, 1.0)
	assert_eq(p.mood, 1.0)
	assert_eq(p.stress, 0.0)
	assert_eq(p.traits.size(), Traits.COUNT)
	assert_eq(p.traits[0], 1.0)
	assert_eq(p.needs, PackedFloat32Array([1.0, 0.0]))
	assert_eq(p.skills, {})
	assert_eq(p.parents, PackedInt64Array([11]))
	assert_eq(p.children.size(), 0)
	assert_eq(p.sub_tile_offset, Vector2(0.999, 0.0))
	assert_eq(p.facing, 0.0)
	assert_eq(p.significance, 0.0)
	assert_eq(p.sex, PersonData.Sex.FEMALE)
	assert_eq(p.household_id, 0)
	assert_eq(p.goals, [])
	assert_eq(p.appearance, {})


# --- registry -----------------------------------------------------------------------------------

func test_registry_add_get_remove() -> void:
	var registry := PersonRegistry.new()
	var seen := []
	registry.person_added.connect(func(id: int) -> void: seen.append(["added", id]))
	registry.person_removed.connect(func(id: int) -> void: seen.append(["removed", id]))
	assert_true(registry.add(_person(5)))
	assert_true(registry.add(_person(2)))
	assert_false(registry.add(_person(5)), "an id is one person")
	assert_false(registry.add(PersonData.new()), "no id, no person")
	assert_false(registry.add(null))
	assert_eq(registry.size(), 2)
	assert_true(registry.has_person(5))
	assert_eq(registry.get_person(2).id, 2)
	assert_null(registry.get_person(99))
	assert_true(registry.remove(5))
	assert_false(registry.remove(5))
	assert_false(registry.has_person(5))
	assert_eq(seen, [["added", 5], ["added", 2], ["removed", 5]])


func test_registry_iterates_in_order_and_by_group() -> void:
	var registry := PersonRegistry.new()
	for id: int in [9, 3, 7, 5]:
		var p := _person(id)
		p.settlement_id = 1 if id != 9 else 2
		p.household_id = 20 if id < 6 else 30
		p.home_building_id = 100 + p.household_id
		p.sim_tier = 4 if id == 7 else 3
		p.given_name = "N%d" % id
		p.family_name = "F%d" % p.household_id
		registry.add(p)
	var order: Array[int] = []
	for p in registry.all_people():
		order.append(p.id)
	assert_eq(order, [3, 5, 7, 9] as Array[int], "in order of id, whatever order they were added in")
	assert_eq(registry.in_settlement(1).size(), 3)
	assert_eq(registry.in_settlement(2)[0].id, 9)
	assert_eq(registry.in_settlement(8).size(), 0)
	assert_eq(registry.in_household(20).size(), 2)
	assert_eq(registry.living_in(130).size(), 2)
	assert_eq(registry.in_tier(4)[0].id, 7)
	assert_eq(registry.in_tier(3).size(), 3)
	assert_eq(registry.household_ids(), PackedInt64Array([20, 30]))
	assert_eq(registry.household_ids(2), PackedInt64Array([30]))
	assert_true(registry.given_names().has("N7"))
	assert_eq(registry.family_names().size(), 2)


func test_registry_keeps_the_spatial_index_in_step() -> void:
	var index := SpatialIndex.new()
	var registry := PersonRegistry.new(index)
	var moved := []
	registry.person_moved.connect(func(id: int) -> void: moved.append(id))
	var p := _person(4)
	registry.add(p)
	assert_eq(index.get_kind(4), SpatialIndex.KIND_PERSON)
	assert_eq(index.get_position(4), Vector2(3.5, -3.5))
	assert_eq(index.query_radius(Vector2(3.5, -3.5), 1.0, SpatialIndex.KIND_PERSON), [4] as Array[int])
	assert_true(registry.move(4, Vector2i(10, 2), Vector2(0.25, 0.25), 2.0))
	assert_eq(p.position, Vector2i(10, 2))
	assert_eq(p.facing, 2.0)
	assert_eq(index.get_position(4), Vector2(10.25, 2.25))
	assert_true(registry.move(4, Vector2i(10, 3)))
	assert_eq(p.facing, 2.0, "facing is kept unless given")
	assert_eq(p.sub_tile_offset, Vector2(0.5, 0.5))
	assert_false(registry.move(99, Vector2i.ZERO))
	assert_false(registry.move(4, Vector2i.ZERO, Vector2(NAN, 0)))
	assert_eq(moved, [4, 4])
	registry.remove(4)
	assert_false(index.has(4))
	registry.add(_person(6))
	registry.clear()
	assert_eq(index.size(), 0)
	assert_eq(registry.size(), 0)


func test_registry_round_trip() -> void:
	var registry := PersonRegistry.new()
	registry.add(_full())
	registry.add(_person(8))
	registry.add(_person(2))
	var data := registry.to_dict()
	assert_eq((data["persons"] as Array).size(), 3)
	assert_eq(data["persons"][0]["id"], 2, "saved in order of id")
	var index := SpatialIndex.new()
	var back := PersonRegistry.new(index)
	assert_eq(back.from_dict(bytes_to_var(var_to_bytes(data))), 0)
	assert_eq(back.to_dict(), data)
	assert_eq(index.size(), 3)
	# An empty world is a valid world.
	var empty := PersonRegistry.new()
	assert_eq(empty.from_dict({"persons": []}), 0)
	assert_eq(empty.size(), 0)


func test_registry_skips_bad_records_and_refuses_bad_data() -> void:
	var registry := PersonRegistry.new()
	var good := _person(3).to_dict()
	assert_eq(registry.from_dict({"persons": [good, "nonsense", {"id": 0}, good, _person(4).to_dict()]}), 3)
	assert_eq(registry.size(), 2)
	assert_eq(registry.from_dict({}), -1)
	assert_eq(registry.size(), 0, "left empty")
	assert_eq(registry.from_dict({"persons": "broken"}), -1)
