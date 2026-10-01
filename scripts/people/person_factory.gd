class_name PersonFactory
extends RefCounted
## Makes a person who joins a settlement from outside: a stranger with a name
## in the settlement's tongue, a nature and needs of their own, a household of
## their own, and a roof — the hut with the fewest people under it. (The
## starting band is made as families by StartingBand; children born in the
## world come with M-lifecycle.) Used by the debug "spawn" command for now.

## Years of age a newcomer of each stage of life is given: from the first
## year of the stage up to this many more.
const AGE_SPAN := 12


## Creates the person, standing at (or beside) `near`. They are not added to
## the registry: the caller does that. `rng` is the world's "people" stream.
static func newcomer(ids: IdAllocator, rng: RandomNumberGenerator, names: NameGenerator, occupations: OccupationLibrary,
		people: PersonRegistry, start: WorldSetup.StartInfo, pathfinder: Pathfinder, now_tick: int, near: Vector2i,
		stage: PersonData.LifeStage = PersonData.LifeStage.ADULT) -> PersonData:
	var config := Config.people
	var year := Config.time.ticks_per_year()
	var person := PersonData.new()
	person.id = ids.next_id()
	person.sex = PersonData.Sex.FEMALE if rng.randf() < 0.5 else PersonData.Sex.MALE
	person.given_name = names.given_name(rng, person.sex, people.given_names())
	person.family_name = names.family_name(rng, people.family_names())
	var youngest := 2
	var oldest := config.adolescent_from_years - 1
	match stage:
		PersonData.LifeStage.ADOLESCENT:
			youngest = config.adolescent_from_years
			oldest = config.adult_from_years - 1
		PersonData.LifeStage.ADULT:
			youngest = config.adult_from_years
			oldest = mini(youngest + AGE_SPAN, config.elder_from_years - 1)
		PersonData.LifeStage.ELDER:
			youngest = config.elder_from_years
			oldest = youngest + AGE_SPAN
	var age := rng.randi_range(youngest, maxi(oldest, youngest))
	person.birth_tick = now_tick - age * year - rng.randi_range(0, maxi(year - 1, 0))
	person.traits = Traits.generate(rng)
	person.needs = Needs.initial(rng)
	person.health = rng.randf_range(0.8, 1.0)
	person.appearance = {
		"height": snappedf(rng.randf_range(0.92, 1.08), 0.01),
		"build": snappedf(rng.randf_range(0.9, 1.12), 0.01),
		"skin": rng.randi_range(0, PersonData.SKIN_TONES - 1),
		"hair": rng.randi_range(0, PersonData.HAIR_COLOURS - 1),
		"cloth": rng.randi_range(0, PersonData.CLOTH_COLOURS - 1),
	}
	person.household_id = ids.next_id()
	if start != null:
		person.settlement_id = start.settlement_id
		person.home_building_id = _emptiest_home(start.hut_ids, people)
	if occupations != null:
		var counts := {}
		for other in people.all_people():
			counts[other.occupation_id] = int(counts.get(other.occupation_id, 0)) + 1
		person.occupation_id = occupations.choose(stage, person.traits, rng, counts)
		var def := occupations.get_def(person.occupation_id)
		if def != null and def.work_target != &"":
			person.skills[String(person.occupation_id)] = snappedf(rng.randf_range(0.2, 0.6), 0.01)
	# Where they were asked for — or the nearest tile to it that can be stood
	# on and has nobody on it.
	person.position = near
	if pathfinder != null and pathfinder.is_bound():
		var taken := {}
		for other in people.everyone():
			taken[(other as PersonData).position] = true
		for spot in pathfinder.standable_near(near, 40):
			if not taken.has(spot):
				person.position = spot
				break
	person.sub_tile_offset = Vector2(rng.randf_range(0.25, 0.75), rng.randf_range(0.25, 0.75))
	person.facing = rng.randf() * TAU
	return person


## The home with the fewest people living in it (the first of them, by id).
static func _emptiest_home(homes: Array[int], people: PersonRegistry) -> int:
	var best := 0
	var fewest := -1
	for home in homes:
		var living := people.living_in(home).size()
		if fewest < 0 or living < fewest:
			fewest = living
			best = home
	return best
