class_name StartingBand
extends RefCounted
## The handful of people a world begins with (bible §8.5, §13): a few
## households — couples, their children, an elder — living in the huts around
## the fire. Deterministic for a given state of the dice.

enum Role { MOTHER, FATHER, CHILD, ELDER, ADULT }

## Nobody in the starting band has a child before this many years into adulthood.
const PARENT_YEARS_AFTER_ADULT := 1
## The oldest a child of the starting band can be.
const OLDEST_CHILD := 16


## Creates the band and adds it to `people`. `rng` is the world's "people"
## stream. Gives the settlement an id if it has none yet. Returns the people
## created, in order of id.
static func spawn(people: PersonRegistry, ids: IdAllocator, rng: RandomNumberGenerator, names: NameGenerator,
		occupations: OccupationLibrary, world: WorldData, props: PropRegistry, start: WorldSetup.StartInfo,
		now_tick: int, config: PeopleConfig, ticks_per_year: int, loose: LooseObjectRegistry = null) -> Array[PersonData]:
	if start.settlement_id == 0:
		start.settlement_id = ids.next_id()
	var band: Array[PersonData] = []
	var given_taken := people.given_names()
	var family_taken := people.family_names()
	var plans := plan_households(rng, config)
	var homes: Array[Array] = [] # per household: its members
	for h in plans.size():
		var members := _create_household(plans[h], ids, rng, names, given_taken, family_taken, now_tick, config, ticks_per_year)
		var household_id := ids.next_id()
		var home_id: int = start.hut_ids[h % start.hut_ids.size()] if not start.hut_ids.is_empty() else 0
		for person in members:
			person.household_id = household_id
			person.home_building_id = home_id
			person.settlement_id = start.settlement_id
			band.append(person)
		homes.append(members)
	_assign_occupations(band, occupations, rng, now_tick, config, ticks_per_year)
	# Nobody stands where something lies (a rock the player left by the fire).
	var taken_tiles := {}
	if loose != null:
		for object in loose.all_objects():
			taken_tiles[object.tile()] = true
	var fire := Vector2(start.settlement_tile) + Vector2(0.5, 0.5)
	for members: Array in homes:
		for person: PersonData in members:
			var home := props.get_prop(person.home_building_id)
			var around := home.tile if home != null else start.settlement_tile
			person.position = _free_tile_near(around, start.settlement_tile, world, props, taken_tiles, rng, config.spawn_radius_tiles)
			taken_tiles[person.position] = true
			person.sub_tile_offset = Vector2(rng.randf_range(0.25, 0.75), rng.randf_range(0.25, 0.75))
			# Everyone starts out turned towards the fire.
			person.facing = (fire - person.world2d()).angle()
	band.sort_custom(func(a: PersonData, b: PersonData) -> bool: return a.id < b.id)
	for person in band:
		people.add(person)
	return band


## Who lives with whom: one list of roles per household, sized to the band
## the config asks for. Every band has at least one child and one elder.
static func plan_households(rng: RandomNumberGenerator, config: PeopleConfig) -> Array[Array]:
	var plans: Array[Array] = []
	var count := rng.randi_range(config.band_min_households, config.band_max_households)
	for h in count:
		var roles: Array = [Role.MOTHER, Role.FATHER]
		match h % 3:
			0: # a couple with children
				roles.append(Role.CHILD)
				if rng.randf() < 0.5:
					roles.append(Role.CHILD)
			1: # a couple with a parent of one of them, and perhaps a child
				roles.append(Role.ELDER)
				if rng.randf() < 0.5:
					roles.append(Role.CHILD)
			2: # someone on their own, or a young couple
				if rng.randf() >= 0.4:
					roles = [Role.ADULT]
		plans.append(roles)
	# Too many: children first (but never the last one), then a partner of a
	# childless couple, then an elder (but never the last one).
	for guard in 64:
		if _total(plans) <= config.band_max_people:
			break
		if not (_count(plans, Role.CHILD) > 1 and _drop(plans, Role.CHILD)) \
				and not _split_childless_couple(plans) \
				and not (_count(plans, Role.ELDER) > 1 and _drop(plans, Role.ELDER)):
			break
	# Too few: more children, in the smallest family that has parents.
	for guard in 64:
		if _total(plans) >= config.band_min_people:
			break
		var smallest: Array = []
		for roles in plans:
			if roles.has(Role.MOTHER) and (smallest.is_empty() or roles.size() < smallest.size()):
				smallest = roles
		if smallest.is_empty():
			break
		smallest.append(Role.CHILD)
	return plans


static func _total(plans: Array[Array]) -> int:
	var total := 0
	for roles in plans:
		total += roles.size()
	return total


static func _count(plans: Array[Array], role: Role) -> int:
	var total := 0
	for roles in plans:
		total += roles.count(role)
	return total


## Removes one `role` from the household that has most of them.
static func _drop(plans: Array[Array], role: Role) -> bool:
	var most: Array = []
	for roles in plans:
		if roles.count(role) > most.count(role):
			most = roles
	if most.is_empty():
		return false
	most.erase(role)
	return true


static func _split_childless_couple(plans: Array[Array]) -> bool:
	for roles in plans:
		if roles.size() == 2 and roles.has(Role.MOTHER) and roles.has(Role.FATHER):
			roles.clear()
			roles.append(Role.ADULT)
			return true
	return false


static func _create_household(roles: Array, ids: IdAllocator, rng: RandomNumberGenerator, names: NameGenerator,
		given_taken: Dictionary, family_taken: Dictionary, now_tick: int, config: PeopleConfig,
		ticks_per_year: int) -> Array[PersonData]:
	var members: Array[PersonData] = []
	var family := names.family_name(rng, family_taken)
	family_taken[family] = true
	var children := roles.count(Role.CHILD)
	var youngest_adult := config.adult_from_years + PARENT_YEARS_AFTER_ADULT
	var oldest_adult := config.elder_from_years - 1
	var mother: PersonData = null
	var father: PersonData = null
	var ages := {} # id -> years

	var make := func(sex: PersonData.Sex, age: int, from_mother: PersonData, from_father: PersonData) -> PersonData:
		var person := PersonData.new()
		person.id = ids.next_id()
		person.sex = sex
		person.family_name = family
		person.given_name = names.given_name(rng, sex, given_taken)
		given_taken[person.given_name] = true
		person.birth_tick = now_tick - age * ticks_per_year - rng.randi_range(0, maxi(ticks_per_year - 1, 0))
		if from_mother != null and from_father != null:
			person.traits = Traits.inherit(from_mother.traits, from_father.traits, rng)
			person.parents = PackedInt64Array([from_mother.id, from_father.id])
			from_mother.children.append(person.id)
			from_father.children.append(person.id)
		else:
			person.traits = Traits.generate(rng)
		person.health = rng.randf_range(0.85, 1.0)
		var looks_like: PersonData = null
		if from_mother != null:
			looks_like = from_mother if rng.randf() < 0.5 else from_father
		person.appearance = {
			"height": snappedf(rng.randf_range(0.92, 1.08), 0.01),
			"build": snappedf(rng.randf_range(0.9, 1.12), 0.01),
			"skin": int(looks_like.appearance["skin"]) if looks_like != null else rng.randi_range(0, PersonData.SKIN_TONES - 1),
			"hair": rng.randi_range(0, PersonData.HAIR_COLOURS - 1),
			"cloth": rng.randi_range(0, PersonData.CLOTH_COLOURS - 1),
		}
		ages[person.id] = age
		members.append(person)
		return person

	if roles.has(Role.MOTHER):
		# Couples with children are old enough to have had them; others are young.
		var low := youngest_adult + (5 if children > 0 else 0)
		var high := mini(low + (16 if children > 0 else 7), oldest_adult)
		var mother_age := rng.randi_range(low, maxi(high, low))
		var father_age := clampi(mother_age + rng.randi_range(-3, 6), low, maxi(oldest_adult, low))
		mother = make.call(PersonData.Sex.FEMALE, mother_age, null, null)
		father = make.call(PersonData.Sex.MALE, father_age, null, null)
		mother.partner_id = father.id
		father.partner_id = mother.id
	if roles.has(Role.ADULT):
		var sex := PersonData.Sex.FEMALE if rng.randf() < 0.5 else PersonData.Sex.MALE
		make.call(sex, rng.randi_range(youngest_adult, mini(youngest_adult + 13, oldest_adult)), null, null)
	if roles.has(Role.ELDER):
		# The parent of one of the couple (or of whoever is there).
		var of: PersonData = members[rng.randi_range(0, members.size() - 1)] if not members.is_empty() else null
		var age := config.elder_from_years + rng.randi_range(0, 6)
		if of != null:
			age = maxi(age, int(ages[of.id]) + config.adult_from_years + 1 + rng.randi_range(0, 8))
		var sex := PersonData.Sex.FEMALE if rng.randf() < 0.5 else PersonData.Sex.MALE
		var elder: PersonData = make.call(sex, age, null, null)
		elder.health = rng.randf_range(0.65, 0.9)
		if of != null:
			elder.children.append(of.id)
			of.parents = PackedInt64Array([elder.id])
			elder.appearance["skin"] = of.appearance["skin"]
	for i in children:
		var oldest := OLDEST_CHILD
		if mother != null:
			oldest = mini(oldest, mini(int(ages[mother.id]), int(ages[father.id])) - config.adult_from_years)
		var sex := PersonData.Sex.FEMALE if rng.randf() < 0.5 else PersonData.Sex.MALE
		make.call(sex, rng.randi_range(1, maxi(oldest, 1)), mother, father)
	return members


## Everyone gets an occupation that suits their stage of life and traits, and
## no kind of work the band could do is left without anyone to do it.
static func _assign_occupations(band: Array[PersonData], occupations: OccupationLibrary, rng: RandomNumberGenerator,
		now_tick: int, config: PeopleConfig, ticks_per_year: int) -> void:
	var counts := {}
	for person in band:
		var stage := person.life_stage(now_tick, ticks_per_year, config)
		person.occupation_id = occupations.choose(stage, person.traits, rng, counts)
		counts[person.occupation_id] = int(counts.get(person.occupation_id, 0)) + 1
	for id in occupations.ids():
		var def := occupations.get_def(id)
		if counts.get(id, 0) > 0 or def.starting_share <= 0.0 or not def.allows(PersonData.LifeStage.ADULT):
			continue
		# Take the adult best suited to it from an occupation that has several.
		var best: PersonData = null
		for person in band:
			if person.life_stage(now_tick, ticks_per_year, config) != PersonData.LifeStage.ADULT \
					or int(counts.get(person.occupation_id, 0)) < 2:
				continue
			if best == null or def.affinity(person.traits) > def.affinity(best.traits):
				best = person
		if best != null:
			counts[best.occupation_id] = int(counts[best.occupation_id]) - 1
			best.occupation_id = id
			counts[id] = 1
	for person in band:
		var def := occupations.get_def(person.occupation_id)
		if def != null and not def.placeholder and not def.allows(PersonData.LifeStage.CHILD):
			person.skills[String(person.occupation_id)] = snappedf(rng.randf_range(0.2, 0.6), 0.01)


## A tile near `around` where someone can stand: dry, nothing on it, not
## `taken` yet. One of the nearest few, so that a household stands by its own door
## without lining up.
static func _free_tile_near(around: Vector2i, fire_tile: Vector2i, world: WorldData, props: PropRegistry,
		taken: Dictionary, rng: RandomNumberGenerator, radius: int) -> Vector2i:
	for reach: int in [radius, radius + 3, radius + 8]:
		var free: Array[Vector2i] = []
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var tile := around + Vector2i(dx, dy)
				if not taken.has(tile) and WorldSetup.is_walkable(world, tile) and props.prop_at(tile) == null \
						and world.get_water(tile) <= 0.0:
					free.append(tile)
		if free.is_empty():
			continue
		free.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da := maxi(absi(a.x - around.x), absi(a.y - around.y))
			var db := maxi(absi(b.x - around.x), absi(b.y - around.y))
			if da != db:
				return da < db
			var fa := (a - fire_tile).length_squared()
			var fb := (b - fire_tile).length_squared()
			if fa != fb:
				return fa < fb
			return a.x < b.x or (a.x == b.x and a.y < b.y))
		return free[rng.randi_range(0, mini(free.size(), 5) - 1)]
	return around
