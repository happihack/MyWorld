extends TestCase
## Needs (M4.4): running down, filling up, and what they say about a person.

var config: NeedsConfig
var person: PersonData


func before_each() -> void:
	config = NeedsConfig.new()
	person = PersonData.new()
	person.id = 1
	person.needs = Needs.full()


func _rng(seed_value: int = 7) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_names_and_order() -> void:
	assert_eq(Needs.Need.size(), Needs.COUNT)
	assert_eq(Needs.NAMES.size(), Needs.COUNT)
	# The order is part of the save format.
	assert_eq(Needs.Need.HUNGER, 0)
	assert_eq(Needs.Need.SAFETY, 5)
	assert_eq(Needs.index_of(&"thirst"), Needs.Need.THIRST)
	assert_eq(Needs.index_of(&"wealth"), -1)
	for need_name in Needs.NAMES:
		assert_true(UIText.NEED_WORDS.has(need_name), "wording for %s" % need_name)


func test_needs_decay() -> void:
	Needs.decay(person, 60.0, config, PersonData.LifeStage.ADULT)
	assert_near(person.needs[Needs.Need.HUNGER], 1.0 - 60.0 * config.hunger_per_minute, 0.0001)
	assert_near(person.needs[Needs.Need.THIRST], 1.0 - 60.0 * config.thirst_per_minute, 0.0001)
	assert_near(person.needs[Needs.Need.SLEEP], 1.0 - 60.0 * config.sleep_per_minute, 0.0001)
	assert_near(person.needs[Needs.Need.SOCIAL], 1.0 - 60.0 * config.social_per_minute, 0.0001)
	assert_near(person.needs[Needs.Need.PURPOSE], 1.0 - 60.0 * config.purpose_per_minute, 0.0001)
	assert_eq(person.needs[Needs.Need.SAFETY], 1.0, "nothing threatens anyone yet")
	assert_true(person.needs[Needs.Need.THIRST] < person.needs[Needs.Need.HUNGER], "thirst comes sooner than hunger")
	# Never below nothing, however long it lasts.
	Needs.decay(person, 100_000.0, config, PersonData.LifeStage.ADULT)
	for need in [Needs.Need.HUNGER, Needs.Need.THIRST, Needs.Need.SLEEP, Needs.Need.SOCIAL, Needs.Need.PURPOSE]:
		assert_eq(person.needs[need], 0.0)
	# No time, no change; needs that were never set up are left alone.
	person.needs = Needs.full()
	Needs.decay(person, 0.0, config, PersonData.LifeStage.ADULT)
	assert_eq(person.needs, Needs.full())
	person.needs = PackedFloat32Array()
	Needs.decay(person, 60.0, config, PersonData.LifeStage.ADULT)
	assert_eq(person.needs.size(), 0)


func test_decay_does_not_depend_on_the_size_of_the_step() -> void:
	var other := PersonData.new()
	other.needs = Needs.full()
	Needs.decay(person, 120.0, config, PersonData.LifeStage.ADULT)
	for i in 480:
		Needs.decay(other, 0.25, config, PersonData.LifeStage.ADULT)
	for need in Needs.COUNT:
		assert_near(other.needs[need], person.needs[need], 0.0005)


func test_a_day_is_survivable() -> void:
	# Awake from six to nine at night without food, water or rest: hungry,
	# very thirsty and tired, but nothing has run out.
	Needs.decay(person, 15.0 * 60.0, config, PersonData.LifeStage.ADULT)
	assert_eq(person.needs[Needs.Need.THIRST], 0.0, "except water: nobody goes a day without")
	assert_true(person.needs[Needs.Need.HUNGER] <= 0.0, "or food, quite")
	assert_true(person.needs[Needs.Need.SLEEP] > 0.2 and person.needs[Needs.Need.SLEEP] < 0.45, "tired by evening (%.2f)" % person.needs[Needs.Need.SLEEP])
	assert_eq(config.validate().size(), 0)
	var bad := NeedsConfig.new()
	bad.full_sleep_minutes = 1600.0
	assert_eq(bad.validate().size(), 1, "sleep that restores less than waking takes is reported")


func test_work_and_sleep_change_the_rates() -> void:
	var worker := PersonData.new()
	worker.needs = Needs.full()
	var sleeper := PersonData.new()
	sleeper.needs = Needs.full()
	Needs.decay(person, 100.0, config, PersonData.LifeStage.ADULT)
	Needs.decay(worker, 100.0, config, PersonData.LifeStage.ADULT, Needs.State.WORKING)
	Needs.decay(sleeper, 100.0, config, PersonData.LifeStage.ADULT, Needs.State.SLEEPING)
	assert_true(worker.needs[Needs.Need.HUNGER] < person.needs[Needs.Need.HUNGER], "work makes hungry")
	assert_true(worker.needs[Needs.Need.SLEEP] < person.needs[Needs.Need.SLEEP], "and tired")
	assert_eq(worker.needs[Needs.Need.PURPOSE], 1.0, "but nobody at work wonders what for")
	assert_true(sleeper.needs[Needs.Need.HUNGER] > person.needs[Needs.Need.HUNGER], "asleep, hunger waits")
	assert_eq(sleeper.needs[Needs.Need.SLEEP], 1.0, "sleeping does not tire")
	assert_eq(sleeper.needs[Needs.Need.SOCIAL], 1.0, "nor does one miss company")


func test_bodies_and_natures_differ() -> void:
	var child := PersonData.new()
	child.needs = Needs.full()
	Needs.decay(person, 100.0, config, PersonData.LifeStage.ADULT)
	Needs.decay(child, 100.0, config, PersonData.LifeStage.CHILD)
	assert_true(child.needs[Needs.Need.HUNGER] < person.needs[Needs.Need.HUNGER], "children are hungry sooner")
	var sociable := PersonData.new()
	sociable.needs = Needs.full()
	sociable.traits[Traits.Axis.SOCIABILITY] = 1.0
	sociable.traits[Traits.Axis.AMBITION] = -1.0
	var loner := PersonData.new()
	loner.needs = Needs.full()
	loner.traits[Traits.Axis.SOCIABILITY] = -1.0
	loner.traits[Traits.Axis.AMBITION] = 1.0
	Needs.decay(sociable, 200.0, config, PersonData.LifeStage.ADULT)
	Needs.decay(loner, 200.0, config, PersonData.LifeStage.ADULT)
	assert_true(sociable.needs[Needs.Need.SOCIAL] < loner.needs[Needs.Need.SOCIAL], "the sociable miss company sooner")
	assert_true(loner.needs[Needs.Need.PURPOSE] < sociable.needs[Needs.Need.PURPOSE], "the ambitious grow restless sooner")
	assert_true(loner.needs[Needs.Need.SOCIAL] < 1.0, "but everyone does in the end")


func test_safety_comes_back_by_itself() -> void:
	person.needs[Needs.Need.SAFETY] = 0.2
	Needs.decay(person, 60.0, config, PersonData.LifeStage.ADULT)
	assert_true(person.needs[Needs.Need.SAFETY] > 0.5)
	Needs.decay(person, 600.0, config, PersonData.LifeStage.ADULT)
	assert_eq(person.needs[Needs.Need.SAFETY], 1.0)


func test_urgency_and_satisfying() -> void:
	person.needs[Needs.Need.HUNGER] = 0.25
	assert_near(Needs.urgency(person.needs, Needs.Need.HUNGER), 0.75)
	assert_eq(Needs.most_urgent(person.needs), Needs.Need.HUNGER)
	Needs.satisfy(person.needs, Needs.Need.HUNGER, 0.5)
	assert_near(person.needs[Needs.Need.HUNGER], 0.75)
	Needs.satisfy(person.needs, Needs.Need.HUNGER, 5.0)
	assert_eq(person.needs[Needs.Need.HUNGER], 1.0, "never more than met")
	Needs.satisfy(person.needs, 99, 1.0) # no such need: nothing happens
	assert_eq(Needs.value(PackedFloat32Array(), Needs.Need.THIRST), 1.0)
	assert_eq(Needs.urgency(PackedFloat32Array(), Needs.Need.THIRST), 0.0)


func test_mood_and_stress() -> void:
	assert_near(Needs.mood(Needs.full()), 1.0)
	assert_eq(Needs.stress(Needs.full()), 0.0)
	var hungry := Needs.full()
	hungry[Needs.Need.HUNGER] = 0.0
	assert_true(Needs.mood(hungry) < 0.65, "one empty need spoils the mood (%.2f)" % Needs.mood(hungry))
	assert_near(Needs.stress(hungry), 1.0)
	var uneasy := Needs.full()
	uneasy[Needs.Need.SLEEP] = Needs.PRESSING
	assert_near(Needs.stress(uneasy), 0.5)
	assert_eq(Needs.mood(PackedFloat32Array()), 0.5)
	assert_eq(Needs.stress(PackedFloat32Array()), 0.0)


func test_new_people_start_out_differently_but_not_in_need() -> void:
	var rng := _rng()
	var seen := {}
	for i in 100:
		var needs := Needs.initial(rng)
		assert_eq(needs.size(), Needs.COUNT)
		for need in Needs.COUNT:
			if needs[need] < 0.4 or needs[need] > 1.0:
				fail("need %d starts at %f" % [need, needs[need]])
		seen[snappedf(needs[Needs.Need.HUNGER], 0.05)] = true
	assert_true(seen.size() > 5, "not everyone gets hungry at once")
	assert_eq(Needs.initial(_rng(3)), Needs.initial(_rng(3)))


func test_people_from_before_needs_get_some() -> void:
	var mended := Needs.sanitized(PackedFloat32Array(), 41)
	assert_eq(mended.size(), Needs.COUNT)
	assert_eq(mended, Needs.sanitized(PackedFloat32Array(), 41), "the same every time")
	assert_ne(mended, Needs.sanitized(PackedFloat32Array(), 42), "but not the same for everyone")
	for need in Needs.COUNT:
		assert_true(mended[need] >= 0.5 and mended[need] <= 1.0)
	assert_eq(mended[Needs.Need.SAFETY], 1.0)
	# What is there is kept; what is broken is repaired.
	var partly := Needs.sanitized(PackedFloat32Array([0.25, 7.0, NAN]), 5)
	assert_eq(partly[0], 0.25)
	assert_eq(partly[1], 1.0)
	assert_true(partly[2] >= 0.5)
	assert_eq(Needs.sanitized(PackedFloat32Array([0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8])).size(), Needs.COUNT)


# --- activity definitions ---------------------------------------------------------------------------

func _activity(needs: Dictionary = {}, traits: Dictionary = {}) -> ActivityDef:
	var def := ActivityDef.new()
	def.id = &"test"
	def.need_weights = needs
	def.trait_weights = traits
	return def


func test_pressing_needs_shout_and_mild_ones_whisper() -> void:
	var def := _activity({"hunger": 2.0})
	var needs := Needs.full()
	needs[Needs.Need.HUNGER] = 0.8
	var mild: float = def.need_parts(needs)[Needs.Need.HUNGER]
	needs[Needs.Need.HUNGER] = 0.2
	var pressing: float = def.need_parts(needs)[Needs.Need.HUNGER]
	assert_eq(mild, 0.0, "a need that is mostly met says nothing (nobody eats because they could)")
	assert_near(pressing, 2.0 * ActivityDef.voice(0.8), 0.0001)
	assert_true(pressing > 1.0)
	assert_eq(def.need_parts(Needs.full())[Needs.Need.HUNGER], 0.0)
	# The voice of a need: silent, then rising faster and faster.
	assert_eq(ActivityDef.voice(0.0), 0.0)
	assert_eq(ActivityDef.voice(ActivityDef.QUIET_BELOW), 0.0)
	assert_near(ActivityDef.voice(1.0), 1.0)
	var half := ActivityDef.voice(0.625) # halfway between quiet and desperate
	assert_near(half, 0.25, 0.0001, "half as urgent, a quarter as loud")


func test_traits_lean_people_towards_activities() -> void:
	var def := _activity({}, {"CURIOSITY": 1.0, "INTELLIGENCE": 1.0})
	var keen := Traits.neutral()
	keen[Traits.Axis.CURIOSITY] = 1.0
	keen[Traits.Axis.INTELLIGENCE] = 1.0
	var dull := Traits.neutral()
	dull[Traits.Axis.CURIOSITY] = -1.0
	dull[Traits.Axis.INTELLIGENCE] = 0.0
	assert_near(def.trait_part(keen), 2.0 * ActivityDef.TRAIT_SCALE, 0.0001)
	assert_near(def.trait_part(dull), -2.0 * ActivityDef.TRAIT_SCALE, 0.0001)
	assert_near(def.trait_part(Traits.neutral()), 0.0, 0.0001)


func test_the_hour_is_a_factor_between_the_hours() -> void:
	var def := _activity()
	assert_eq(def.hour_factor(3.0), 1.0, "no hours given: any time")
	def.hours = PackedFloat32Array()
	def.hours.resize(24)
	def.hours.fill(1.0)
	def.hours[8] = 2.0
	def.hours[23] = 0.5
	def.hours[0] = 1.5
	assert_near(def.hour_factor(8.0), 2.0)
	assert_near(def.hour_factor(7.5), 1.5, 0.0001, "halfway between seven and eight")
	assert_near(def.hour_factor(23.5), 1.0, 0.0001, "midnight joins the ends")
	assert_near(def.hour_factor(32.0), 2.0, 0.0001, "hours wrap")
	assert_near(def.hour_factor(-1.0), 0.5, 0.0001)


func test_bad_activity_data_is_reported() -> void:
	var def := _activity({"wealth": 1.0}, {"DREAMINESS": 1.0})
	def.hours = PackedFloat32Array([1.0, 2.0])
	assert_eq(def.validate().size(), 3)
	def.id = &""
	assert_eq(def.validate().size(), 4)
	assert_true(def.allows(PersonData.LifeStage.CHILD), "no stages given: everyone")
	def.life_stages = [PersonData.LifeStage.ADULT]
	assert_false(def.allows(PersonData.LifeStage.CHILD))
	Log.console_output = false
	var library := ActivityLibrary.new()
	assert_false(library.add(def))
	var good := _activity({"hunger": 1.0})
	assert_true(library.add(good))
	assert_false(library.add(good), "defined twice")
	assert_eq(library.size(), 1)
	assert_true(library.problems.size() >= 5)
