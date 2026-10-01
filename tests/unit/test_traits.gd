extends TestCase


func _rng(seed_value: int = 7) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _traits(values: Dictionary) -> PackedFloat32Array:
	var t := Traits.neutral()
	for axis: int in values:
		t[axis] = values[axis]
	return t


func test_axes_and_words_line_up() -> void:
	assert_eq(Traits.Axis.size(), Traits.COUNT)
	assert_eq(Traits.LOW_WORDS.size(), Traits.COUNT)
	assert_eq(Traits.HIGH_WORDS.size(), Traits.COUNT)
	# The order is part of the save format.
	assert_eq(Traits.Axis.CURIOSITY, 0)
	assert_eq(Traits.Axis.ADVENTURE, 8)
	assert_eq(Traits.Axis.INTELLIGENCE, 9)
	assert_eq(Traits.Axis.LOYALTY, 11)
	for axis in Traits.COUNT:
		assert_true(Traits.HIGH_WORDS[axis] != &"")
		assert_eq(Traits.LOW_WORDS[axis] == &"", Traits.is_amount(axis), "only opposites have a word for the low end")
		assert_true(UIText.TRAIT_WORDS.has(Traits.HIGH_WORDS[axis]), "wording for %s" % Traits.HIGH_WORDS[axis])
		if Traits.LOW_WORDS[axis] != &"":
			assert_true(UIText.TRAIT_WORDS.has(Traits.LOW_WORDS[axis]), "wording for %s" % Traits.LOW_WORDS[axis])


func test_generated_traits_stay_in_range_and_are_deterministic() -> void:
	var rng := _rng()
	for i in 200:
		var t := Traits.generate(rng)
		assert_eq(t.size(), Traits.COUNT)
		for axis in Traits.COUNT:
			var low := 0.0 if Traits.is_amount(axis) else -1.0
			if t[axis] < low or t[axis] > 1.0:
				fail("axis %d out of range: %f" % [axis, t[axis]])
	assert_eq(Traits.generate(_rng(3)), Traits.generate(_rng(3)), "same dice, same person")
	assert_true(Traits.generate(_rng(3)) != Traits.generate(_rng(4)))


func test_generated_traits_are_varied_but_mostly_moderate() -> void:
	var rng := _rng(11)
	var sum := 0.0
	var strong := 0
	var mild := 0
	var with_a_strong_trait := 0
	var samples := 1000
	for i in samples:
		var t := Traits.generate(rng)
		sum += t[Traits.Axis.CURIOSITY]
		if absf(t[Traits.Axis.CURIOSITY]) > 0.6:
			strong += 1
		if absf(t[Traits.Axis.CURIOSITY]) < 0.3:
			mild += 1
		if not Traits.describe_top(t, 1).is_empty():
			with_a_strong_trait += 1
	assert_near(sum / samples, 0.0, 0.08, "no lean in the population")
	assert_true(strong > samples / 20 and strong < samples / 2, "some stand out (%d)" % strong)
	assert_true(mild > samples / 4, "many are middling (%d)" % mild)
	assert_true(with_a_strong_trait > samples * 9 / 10, "nearly everyone stands out in something (%d)" % with_a_strong_trait)


func test_describe_top_names_the_strongest_traits() -> void:
	var t := _traits({Traits.Axis.CURIOSITY: 0.9, Traits.Axis.BRAVERY: -0.7, Traits.Axis.GENEROSITY: 0.4,
		Traits.Axis.SOCIABILITY: 0.1, Traits.Axis.CREATIVITY: 0.95})
	assert_eq(Traits.describe_top(t, 3), PackedStringArray(["curious", "creative", "fearful"]))
	assert_eq(Traits.describe_top(t, 1), PackedStringArray(["curious"]))
	assert_eq(Traits.describe_top(t, 10), PackedStringArray(["curious", "creative", "fearful", "generous"]),
		"what is not pronounced gets no word")
	assert_eq(UIText.trait_words(t, 2), PackedStringArray(["Curious", "Inventive"]))


func test_an_unremarkable_person_has_no_words() -> void:
	assert_eq(Traits.describe_top(Traits.neutral(), 3).size(), 0)
	# Little intelligence is not a description (nobody is named by a lack).
	var dull := _traits({Traits.Axis.INTELLIGENCE: 0.0, Traits.Axis.LOYALTY: 0.05})
	assert_eq(Traits.describe_top(dull, 3).size(), 0)
	assert_eq(Traits.word(dull, Traits.Axis.INTELLIGENCE), &"")
	assert_eq(Traits.strength(dull, Traits.Axis.INTELLIGENCE), 0.0)
	assert_eq(Traits.word(Traits.neutral(), 99), &"")


func test_equal_strengths_are_ordered_by_axis() -> void:
	var t := _traits({Traits.Axis.ADVENTURE: 0.5, Traits.Axis.BRAVERY: 0.5, Traits.Axis.AMBITION: -0.5})
	assert_eq(Traits.describe_top(t, 3), PackedStringArray(["brave", "lazy", "adventurous"]))


func test_children_take_after_their_parents() -> void:
	var bold := _traits({Traits.Axis.BRAVERY: 0.9, Traits.Axis.CREATIVITY: 0.9})
	var meek := _traits({Traits.Axis.BRAVERY: -0.9, Traits.Axis.CREATIVITY: 0.1})
	var rng := _rng(5)
	var of_bold := 0.0
	var of_mixed := 0.0
	var of_meek := 0.0
	var spread := 0.0
	var samples := 400
	for i in samples:
		var child := Traits.inherit(bold, bold, rng)
		of_bold += child[Traits.Axis.BRAVERY]
		spread += absf(child[Traits.Axis.BRAVERY] - 0.9)
		of_mixed += Traits.inherit(bold, meek, rng)[Traits.Axis.BRAVERY]
		of_meek += Traits.inherit(meek, meek, rng)[Traits.Axis.CREATIVITY]
	assert_true(of_bold / samples > 0.6, "children of the brave are mostly brave (%.2f)" % (of_bold / samples))
	assert_near(of_mixed / samples, 0.0, 0.1, "between its parents")
	assert_true(of_meek / samples < 0.3, "amounts are inherited too (%.2f)" % (of_meek / samples))
	assert_true(spread / samples > 0.05, "but each child is its own person")
	# Parents with broken records still have children.
	assert_eq(Traits.inherit(PackedFloat32Array(), PackedFloat32Array([NAN]), rng).size(), Traits.COUNT)


func test_sanitized_repairs_anything() -> void:
	assert_eq(Traits.sanitized(PackedFloat32Array()), Traits.neutral())
	var repaired := Traits.sanitized(PackedFloat32Array([5.0, -5.0, NAN, 0.25, 0, 0, 0, 0, 0, -1.0, 2.0, 0.5, 9.0, 9.0]))
	assert_eq(repaired.size(), Traits.COUNT)
	assert_eq(repaired[0], 1.0)
	assert_eq(repaired[1], -1.0)
	assert_eq(repaired[2], 0.0)
	assert_eq(repaired[3], 0.25)
	assert_eq(repaired[Traits.Axis.INTELLIGENCE], 0.0)
	assert_eq(repaired[Traits.Axis.CREATIVITY], 1.0)
	assert_eq(Traits.value(PackedFloat32Array(), Traits.Axis.LOYALTY), 0.5)
	assert_eq(Traits.value(PackedFloat32Array(), Traits.Axis.BRAVERY), 0.0)
