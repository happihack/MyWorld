extends TestCase

var library: OccupationLibrary


func before_each() -> void:
	library = OccupationLibrary.load_from()


func _rng(seed_value: int = 7) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _def(id: StringName, stages: Array[PersonData.LifeStage], share: float = 1.0, weights: Dictionary = {}) -> OccupationDef:
	var def := OccupationDef.new()
	def.id = id
	def.life_stages = stages
	def.starting_share = share
	def.trait_weights = weights
	return def


func test_the_first_occupations_are_defined_in_data() -> void:
	assert_eq(library.problems.size(), 0, str(library.problems))
	assert_eq(library.ids(), [&"builder", &"child", &"elder", &"farmer", &"forager", &"hunter", &"scientist", &"toolmaker", &"trader", &"woodcutter"] as Array[StringName])
	for id in library.ids():
		var def := library.get_def(id)
		assert_eq(def.id, id)
		assert_eq(def.validate().size(), 0)
		assert_true(UIText.OCCUPATION_NAMES.has(id), "wording for %s" % id)
	assert_false(library.get_def(&"builder").placeholder, "there is building to do (M12.1)")
	assert_eq(library.get_def(&"builder").work_target, &"site")
	assert_eq(library.get_def(&"builder").starting_share, 0.0)
	assert_true(library.get_def(&"child").allows(PersonData.LifeStage.CHILD))
	assert_false(library.get_def(&"child").allows(PersonData.LifeStage.ADULT))
	assert_true(library.get_def(&"elder").allows(PersonData.LifeStage.ELDER))
	assert_true(library.get_def(&"forager").allows(PersonData.LifeStage.ADOLESCENT), "the young help with foraging")
	assert_false(library.get_def(&"woodcutter").allows(PersonData.LifeStage.ADOLESCENT))
	assert_null(library.get_def(&"astronaut"))
	assert_false(library.has_def(&"astronaut"))


func test_everyone_gets_something_fitting_their_stage_of_life() -> void:
	var rng := _rng()
	for i in 50:
		var traits := Traits.generate(rng)
		assert_eq(library.choose(PersonData.LifeStage.CHILD, traits, rng), &"child")
		assert_eq(library.choose(PersonData.LifeStage.ELDER, traits, rng), &"elder")
		assert_eq(library.choose(PersonData.LifeStage.ADOLESCENT, traits, rng), &"forager")
		var adult := library.choose(PersonData.LifeStage.ADULT, traits, rng)
		assert_true(adult == &"forager" or adult == &"woodcutter", "placeholders are not taken up (%s)" % adult)


func test_traits_draw_people_to_work_without_deciding_it() -> void:
	var rng := _rng(21)
	var wanderer := Traits.neutral()
	wanderer[Traits.Axis.ADVENTURE] = 1.0
	wanderer[Traits.Axis.CURIOSITY] = 1.0
	wanderer[Traits.Axis.AMBITION] = -1.0
	wanderer[Traits.Axis.BRAVERY] = -1.0
	var striver := Traits.neutral()
	striver[Traits.Axis.AMBITION] = 1.0
	striver[Traits.Axis.BRAVERY] = 1.0
	striver[Traits.Axis.ADVENTURE] = -1.0
	striver[Traits.Axis.CURIOSITY] = -1.0
	var wanderers_foraging := 0
	var strivers_foraging := 0
	for i in 500:
		if library.choose(PersonData.LifeStage.ADULT, wanderer, rng) == &"forager":
			wanderers_foraging += 1
		if library.choose(PersonData.LifeStage.ADULT, striver, rng) == &"forager":
			strivers_foraging += 1
	assert_true(wanderers_foraging > 350, "the adventurous mostly forage (%d of 500)" % wanderers_foraging)
	assert_true(strivers_foraging < 150, "the ambitious mostly cut wood (%d of 500)" % strivers_foraging)
	assert_true(wanderers_foraging < 500 and strivers_foraging > 0, "but never all of them: no argmax")
	assert_true(library.get_def(&"forager").affinity(wanderer) > library.get_def(&"forager").affinity(striver))
	assert_eq(library.get_def(&"child").affinity(wanderer), 0.0)


func test_what_the_band_already_has_is_chosen_less() -> void:
	var rng := _rng(4)
	var plain := Traits.neutral()
	var crowded := 0
	for i in 500:
		if library.choose(PersonData.LifeStage.ADULT, plain, rng, {&"forager": 5}) == &"forager":
			crowded += 1
	assert_true(crowded < 150, "five foragers already: the sixth mostly cuts wood (%d of 500)" % crowded)


func test_amounts_count_from_their_middle() -> void:
	var def := _def(&"thinker", [PersonData.LifeStage.ADULT], 1.0, {"INTELLIGENCE": 1.0})
	var bright := Traits.neutral()
	bright[Traits.Axis.INTELLIGENCE] = 1.0
	var dim := Traits.neutral()
	dim[Traits.Axis.INTELLIGENCE] = 0.0
	assert_near(def.affinity(bright), 1.0)
	assert_near(def.affinity(dim), -1.0)
	assert_near(def.affinity(Traits.neutral()), 0.0)


func test_bad_definitions_are_reported_and_left_out() -> void:
	Log.console_output = false
	var mine := OccupationLibrary.new()
	assert_true(mine.add(_def(&"fisher", [PersonData.LifeStage.ADULT])))
	assert_false(mine.add(_def(&"fisher", [PersonData.LifeStage.ADULT])), "defined twice")
	assert_false(mine.add(_def(&"", [PersonData.LifeStage.ADULT])), "no id")
	assert_false(mine.add(_def(&"nobody", [])), "open to no one")
	assert_false(mine.add(_def(&"dreamer", [PersonData.LifeStage.ADULT], 1.0, {"DREAMINESS": 1.0})), "unknown trait")
	assert_eq(mine.size(), 1)
	assert_eq(mine.problems.size(), 4)
	assert_eq(mine.choose(PersonData.LifeStage.CHILD, Traits.neutral(), _rng()), &"", "nothing open to a child here")
	var none := OccupationLibrary.load_from("res://data/no_such_directory/")
	assert_eq(none.size(), 0)
	assert_true(none.problems.size() >= 1)
