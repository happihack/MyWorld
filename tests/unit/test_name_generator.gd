extends TestCase


func _rng(seed_value: int = 7) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _is_letters(text: String) -> bool:
	for c in text.to_lower():
		if c < "a" or c > "z":
			return false
	return true


func test_a_phonology_is_a_pure_function_of_its_seed() -> void:
	var a := Phonology.from_seed(42)
	var b := Phonology.from_seed(42)
	assert_eq(a.onsets, b.onsets)
	assert_eq(a.vowels, b.vowels)
	assert_eq(a.codas, b.codas)
	assert_eq(a.female_endings, b.female_endings)
	assert_eq(a.male_endings, b.male_endings)
	assert_eq(a.family_suffix, b.family_suffix)
	assert_eq(a.coda_chance, b.coda_chance)


func test_every_phonology_can_make_words() -> void:
	var inventories := {}
	for seed_value in 60:
		var p := Phonology.from_seed(seed_value * 7919 + 1)
		assert_true(p.onsets.size() >= 7 and p.onsets.size() <= 13, "onsets %d" % p.onsets.size())
		assert_true(p.vowels.size() >= 3 and p.vowels.size() <= 6)
		assert_true(p.codas.size() >= 3)
		assert_eq(p.female_endings.size(), 2)
		assert_true(p.male_endings.size() >= 2)
		for sound in p.onsets:
			assert_true(Phonology.ONSETS.has(sound))
		for ending in p.female_endings:
			assert_false(p.male_endings.has(ending), "women's and men's names end differently")
		inventories["%s|%s|%s" % [p.onsets, p.vowels, p.codas]] = true
	assert_true(inventories.size() >= 58, "cultures differ (%d distinct of 60)" % inventories.size())


func test_names_are_well_formed() -> void:
	for seed_value in 12:
		var names := NameGenerator.new(Phonology.from_seed(1000 + seed_value))
		var rng := _rng(seed_value)
		for i in 60:
			for text: String in [names.given_name(rng, i % 2), names.family_name(rng)]:
				if not NameGenerator.is_acceptable(text) or not _is_letters(text) \
						or text[0] != text[0].to_upper() or text.substr(1) != text.substr(1).to_lower():
					fail("bad name '%s' (culture %d)" % [text, seed_value])


func test_names_are_deterministic_and_varied() -> void:
	var names := NameGenerator.new(Phonology.from_seed(5))
	var first: Array[String] = []
	var again: Array[String] = []
	var rng_a := _rng(9)
	var rng_b := _rng(9)
	for i in 40:
		first.append(names.given_name(rng_a, i % 2))
		again.append(names.given_name(rng_b, i % 2))
	assert_eq(first, again, "same dice, same names")
	var distinct := {}
	var rng := _rng(10)
	for i in 300:
		distinct[names.given_name(rng, i % 2)] = true
	assert_true(distinct.size() > 150, "plenty of different names (%d of 300)" % distinct.size())


func test_names_in_use_are_avoided() -> void:
	var names := NameGenerator.new(Phonology.from_seed(5))
	var rng := _rng(3)
	var taken := {}
	for i in 200:
		var given := names.given_name(rng, i % 2, taken)
		assert_false(taken.has(given), "'%s' given twice" % given)
		taken[given] = true
	var families := {}
	for i in 60:
		var family := names.family_name(rng, families)
		assert_false(families.has(family), "'%s' given twice" % family)
		families[family] = true


func test_names_of_women_and_men_tend_to_end_differently() -> void:
	var p := Phonology.from_seed(77)
	var names := NameGenerator.new(p)
	var rng := _rng(1)
	var female_hits := 0
	var male_hits := 0
	var crossed := 0
	for i in 300:
		var woman := names.given_name(rng, PersonData.Sex.FEMALE).to_lower()
		var man := names.given_name(rng, PersonData.Sex.MALE).to_lower()
		for ending in p.female_endings:
			if woman.ends_with(ending):
				female_hits += 1
				break
		for ending in p.male_endings:
			if man.ends_with(ending):
				male_hits += 1
				break
		for ending in p.female_endings:
			if man.ends_with(ending):
				crossed += 1
				break
	assert_true(female_hits > 150, "most women's names end the women's way (%d of 300)" % female_hits)
	assert_true(male_hits > 150, "most men's names end the men's way (%d of 300)" % male_hits)
	assert_true(crossed < female_hits / 2, "it is a tendency one can hear (%d crossed)" % crossed)


func test_families_of_a_culture_sound_alike() -> void:
	var p := Phonology.from_seed(12345)
	p.family_suffix = "ash"
	var names := NameGenerator.new(p)
	var rng := _rng(2)
	for i in 30:
		var family := names.family_name(rng)
		assert_true(family.ends_with("ash"), family)


func test_rude_and_unpronounceable_words_are_refused() -> void:
	assert_false(NameGenerator.is_acceptable("Ko"), "too short")
	assert_false(NameGenerator.is_acceptable("Kolomarenu"), "too long")
	assert_false(NameGenerator.is_acceptable("Kaaat"), "three of the same letter")
	assert_false(NameGenerator.is_acceptable("Shita"))
	assert_false(NameGenerator.is_acceptable("Mafuk"))
	assert_true(NameGenerator.is_acceptable("Mara"))
	assert_true(NameGenerator.is_acceptable("Velun"))


func test_endings_replace_the_end_of_a_word() -> void:
	assert_eq(NameGenerator._with_ending("karon", "a"), "kara")
	assert_eq(NameGenerator._with_ending("karo", "a"), "kara")
	assert_eq(NameGenerator._with_ending("karo", "n"), "karon")
	assert_eq(NameGenerator._with_ending("karosh", "n"), "karon")
	assert_eq(NameGenerator._with_ending("kai", "ou"), "kou")
	assert_eq(NameGenerator._with_ending("karo", ""), "karo")
	assert_eq(NameGenerator._with_ending("a", "an"), "aan")


func test_words_never_stack_three_consonants() -> void:
	var consonants := "bcdfghjklmnpqrstvwxyz"
	for seed_value in 20:
		var names := NameGenerator.new(Phonology.from_seed(300 + seed_value))
		var rng := _rng(seed_value)
		for i in 100:
			var text := names.word(rng, 3)
			var run := 0
			var worst := 0
			for c in text:
				run = run + 1 if consonants.contains(c) else 0
				worst = maxi(worst, run)
			# Digraphs (sh, th, ch) are one sound written with two letters.
			if worst > 3:
				fail("'%s' is a mouthful" % text)
