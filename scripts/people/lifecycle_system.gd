class_name Lifecycle
extends RefCounted
## A life from beginning to end (bible §16.2, M10.2), once a game day:
## people grow up and grow old (and take up the work of their new stage of
## life), become partners, have children — when there is a roof with room and
## food enough — are hurt at work or fall ill under a crowded roof, and die:
## of old age, of illness, of their injuries, of hunger. Whoever dies leaves
## the live registry for the HistoryArchive, their household (and what they
## remembered most) to those who come after them.

signal born(child_id: int, mother_id: int, father_id: int)
## `cause`: one of CAUSE_*; `causes`: the events it came of (ids).
signal died(person_id: int, cause: StringName, causes: Array)
signal partnered(a: int, b: int)
## Someone is now grown up (or old).
signal came_of_age(person_id: int, stage: int)
signal injured(person_id: int, kind: StringName)
## Children left without a grown-up (or an elder left alone) moved in with family.
signal taken_in(person_id: int, household_id: int)
## Someone from far away has come to live here.
signal arrived(person_id: int)

const CAUSE_OLD_AGE := &"old_age"
const CAUSE_ILLNESS := &"illness"
const CAUSE_INJURY := &"injury"
const CAUSE_STARVATION := &"starvation"
const CAUSE_ACCIDENT := &"accident"
const CAUSE_DISASTER := &"disaster"
const PREGNANT := &"pregnant"
## Grieving someone who died: {"id": "grief", "of": id, "since": tick, "strength": 0 … 1}.
const GRIEF := &"grief"
## What the archive keeps of a life: so many deeds and memories.
const DEEDS_KEPT := 5
const MEMORIES_KEPT := 3
## What is no deed of theirs: what happened to them, and what they were to
## someone (friends, fallen out: their relationships keep that).
const NOT_DEEDS: Array[StringName] = [&"came_of_age", &"person_injured", &"person_ill", &"person_hungry_sick",
	&"person_cold_sick", &"person_recovered", &"taken_in", &"person_born", &"became_friends", &"fell_out",
	&"became_enemies", &"reconciled"]
## Days caught up at once at most (a world left for long lives its last days only).
const MAX_DAYS_AT_ONCE := 30
const DAY := TimeConfig.MINUTES_PER_DAY

var people: PersonRegistry
var archive: HistoryArchive
var households: Households
var relationships: RelationshipStore
var memories: MemoryStore
var day_log: DayLog
var settlement: Settlement
var occupations: OccupationLibrary
var names: NameGenerator
var ids: IdAllocator
var rng: RandomNumberGenerator
var clock: GameClock
var pathfinder: Pathfinder
var start: WorldSetup.StartInfo
var events: EventLog
var graves: Graves
var config: LifeConfig
## Off: nobody is born, ages into new work or dies (tests of other things).
var enabled := true
## Counts since the world began (saved): "born", "partners", and per cause of death.
var counts: Dictionary = {}

var _day := -1_000_000
var _stages: Dictionary = {} # person id -> the stage of life they were last seen at


func bind(registry: PersonRegistry, the_archive: HistoryArchive, the_households: Households, now: int,
		life_config: LifeConfig = null) -> void:
	people = registry
	archive = the_archive
	households = the_households
	config = life_config if life_config != null else Config.life
	_day = Config.time.day_index(now)
	_stages.clear()
	for person in people.all_people():
		_stages[person.id] = _stage(person, now)


func to_dict() -> Dictionary:
	return {"day": _day, "counts": counts.duplicate()}


func from_dict(data: Dictionary) -> void:
	if typeof(data.get("day")) == TYPE_INT:
		_day = data["day"]
	counts = (data["counts"] as Dictionary).duplicate() if typeof(data.get("counts")) == TYPE_DICTIONARY else {}


func debug_text() -> String:
	var pregnant := 0
	var hurt := 0
	var ill := 0
	for person in people.all_people():
		pregnant += 1 if is_pregnant(person) else 0
		hurt += 1 if not person.injuries.is_empty() else 0
		ill += 1 if Health.is_ill(person) else 0
	return "life: %d people in %d households, %d with child, %d hurt, %d ill  %s" % [people.size(),
		households.size() if households != null else 0, pregnant, hurt, ill, counts]


# --- questions --------------------------------------------------------------------------------------

static func is_pregnant(person: PersonData) -> bool:
	return not Hardship.condition_of(person, PREGNANT).is_empty()


## When someone was born, living or dead (null: unknown).
func birth_tick_of(id: int) -> Variant:
	var person := people.get_person(id)
	if person != null:
		return person.birth_tick
	var record := archive.get_record(id) if archive != null else null
	return record.birth_tick if record != null else null


## The chance someone dies today, and of what: [chance, {cause -> share}].
func death_chance(person: PersonData, now: int) -> Array:
	var years := person.age_years(now, Config.time.ticks_per_year())
	var per_year := config.base_death_per_year
	if years < config.infant_years:
		per_year += config.infant_death_per_year
	if years >= config.old_age_from_years:
		per_year += config.old_age_death_per_year * pow(2.0, float(years - config.old_age_from_years) / config.old_age_doubling_years)
	per_year *= 1.0 + config.frailty * pow(1.0 - clampf(person.health, 0.0, 1.0), 2.0)
	var of_age := 1.0 - exp(-per_year / float(Config.time.days_per_year()))
	var parts := {}
	parts[CAUSE_OLD_AGE if years >= config.old_age_from_years else CAUSE_ILLNESS] = of_age
	# Weak with hunger, at the end of their strength, for days.
	var hunger := Hardship.condition_of(person)
	if Hardship.is_sick(person) and person.health <= Config.needs.sick_health_floor + 0.001 \
			and now - int(hunger.get("since", now)) >= (config.starving_after_days + Config.needs.hunger_sick_after_minutes / float(DAY)) * DAY:
		parts[CAUSE_STARVATION] = config.starve_chance_per_day
	# Gravely ill (of an illness or of the cold).
	if (Health.is_ill(person) and person.health <= config.illness_floor + 0.001) \
			or (Exposure.is_sick(person) and person.health <= Config.needs.sick_health_floor + 0.001):
		parts[CAUSE_ILLNESS] = float(parts.get(CAUSE_ILLNESS, 0.0)) + config.illness_death_per_day
	# Gravely hurt.
	var worst := Health.worst_injury(person)
	if worst > config.grave_injury_from:
		var kind := CAUSE_INJURY
		for injury: Variant in person.injuries:
			if typeof(injury) == TYPE_DICTIONARY and float(injury.get("severity", 0.0)) >= worst:
				kind = CAUSE_INJURY if str(injury.get("kind", "")) == String(Health.FIGHT) else CAUSE_ACCIDENT
		parts[kind] = float(parts.get(kind, 0.0)) + config.injury_death_per_day * worst
	var survive := 1.0
	for cause: StringName in parts:
		survive *= 1.0 - clampf(float(parts[cause]), 0.0, 1.0)
	return [1.0 - survive, parts]


# --- the days ---------------------------------------------------------------------------------------

## Lives the days that have begun since last time.
func advance_to(now: int) -> void:
	if people == null:
		return
	var today := Config.time.day_index(now)
	if _day == -1_000_000 or today < _day:
		_day = today
		return
	var made_up := 0
	while _day < today:
		_day += 1
		made_up += 1
		if made_up <= MAX_DAYS_AT_ONCE and enabled:
			_live_day(now)
	_day = today


func _live_day(now: int) -> void:
	var everyone := people.all_people()
	everyone.sort_custom(func(a: PersonData, b: PersonData) -> bool: return a.id < b.id)
	for person in everyone:
		_grow(person, now)
		# Grief that has run its course is over.
		if not person.conditions.is_empty() and not Hardship.condition_of(person, GRIEF).is_empty() and grief_of(person, now) <= 0.0:
			person.conditions.erase(Hardship.condition_of(person, GRIEF))
	_mishaps(everyone, now)
	for person in everyone:
		if people.has_person(person.id):
			var chance: Array = death_chance(person, now)
			if rng.randf() < float(chance[0]):
				die(person, _pick(chance[1]), now)
	_pair_up(now)
	_children(now)
	_newcomers(now)


## Their stage of life has changed: the work of the new one.
func _grow(person: PersonData, now: int) -> void:
	var stage := _stage(person, now)
	var was: Variant = _stages.get(person.id)
	_stages[person.id] = stage
	if was == null or int(was) == stage:
		return
	var def := occupations.get_def(person.occupation_id) if occupations != null else null
	if occupations != null and (def == null or not def.allows(stage)):
		var counts_now := {}
		for other in people.all_people():
			counts_now[other.occupation_id] = int(counts_now.get(other.occupation_id, 0)) + 1
		var chosen := occupations.choose(stage, person.traits, rng, counts_now)
		if chosen != &"":
			person.occupation_id = chosen
			var trade := occupations.get_def(chosen)
			if trade != null and trade.work_target != &"" and not person.skills.has(String(chosen)):
				person.skills[String(chosen)] = 0.1
	if day_log != null:
		day_log.note(person.id, now, "life", "grew_%s" % _stage_word(stage))
	if stage == PersonData.LifeStage.ADULT or stage == PersonData.LifeStage.ELDER:
		came_of_age.emit(person.id, stage)


## A day's mishaps: accidents at work, and illness under crowded roofs.
func _mishaps(everyone: Array[PersonData], now: int) -> void:
	for person in everyone:
		var def := occupations.get_def(person.occupation_id) if occupations != null else null
		if def == null or def.work_target == &"" or int(person.activity_log.get("work", -1_000_000)) < now - DAY:
			continue
		if rng.randf() < config.accident_per_work_day:
			var kind := Health.CUT if def.work_target == &"tree" and rng.randf() < 0.5 else Health.FALL
			Health.injure(person, kind, rng.randf_range(0.15, 0.7), now, config)
			if day_log != null:
				day_log.note(person.id, now, "life", "hurt_%s" % kind)
			injured.emit(person.id, kind)
	if households == null:
		return
	for home in households.homes():
		var over := -households.room(home)
		if over <= 0:
			continue
		var under := people.living_in(home)
		under.sort_custom(func(a: PersonData, b: PersonData) -> bool: return a.id < b.id)
		for person in under:
			if rng.randf() < config.crowding_chance_per_day * over and Health.fall_ill(person, Health.CROWDING, now):
				if day_log != null:
					day_log.note(person.id, now, "life", "ill_crowding")
				injured.emit(person.id, Health.CROWDING)


## Grown-ups who are drawn to each other (and free, and not of one family)
## become partners.
func _pair_up(now: int) -> void:
	if relationships == null:
		return
	var everyone := people.all_people()
	everyone.sort_custom(func(a: PersonData, b: PersonData) -> bool: return a.id < b.id)
	for person in everyone:
		if person.partner_id != 0 or not _grown(person, now):
			continue
		var best: PersonData = null
		var best_romance := 0.0
		var known := relationships.of(person.id)
		var others: Array = known.keys()
		others.sort()
		for other_id: int in others:
			var record: Relationship = known[other_id]
			var other := people.get_person(other_id)
			if other == null or other.partner_id != 0 or other.sex == person.sex or not _grown(other, now) \
					or relationships.is_family(person.id, other_id) or relationships.close_kin(person.id, other_id) \
					or record.romance < config.partner_romance or record.affinity < config.partner_affinity \
					or absi(person.age_years(now, Config.time.ticks_per_year()) - other.age_years(now, Config.time.ticks_per_year())) > config.partner_most_years_apart:
				continue
			if record.romance > best_romance:
				best_romance = record.romance
				best = other
		if best != null and rng.randf() < config.partner_chance_per_day:
			partner(person, best, now)


## Someone grown-up and free who has nobody they could become partners with
## (and room under the roofs): now and then someone from far away comes.
func _newcomers(now: int) -> void:
	if start == null or households == null or names == null or config.newcomer_chance_per_day <= 0.0:
		return
	var room := 0
	for home in households.homes():
		room += maxi(households.room(home), 0)
	if room <= 0:
		return
	var lonely := lonely_one(now)
	if lonely == null or rng.randf() >= config.newcomer_chance_per_day:
		return
	var stranger := PersonFactory.newcomer(ids, rng, names, occupations, people, start, pathfinder, now,
		start.settlement_tile, PersonData.LifeStage.ADULT)
	stranger.sex = PersonData.Sex.MALE if lonely.sex == PersonData.Sex.FEMALE else PersonData.Sex.FEMALE
	stranger.given_name = names.given_name(rng, stranger.sex, people.given_names())
	var years := clampi(lonely.age_years(now, Config.time.ticks_per_year()) + rng.randi_range(-4, 4),
		Config.people.adult_from_years, config.lonely_until_years)
	stranger.birth_tick = now - years * Config.time.ticks_per_year() - rng.randi_range(0, Config.time.ticks_per_year() - 1)
	people.add(stranger)
	_stages[stranger.id] = _stage(stranger, now)
	households.ensure_records(now)
	# Introduced to everyone (and known to nobody well yet) — and to the one
	# they came for, with a spark between them.
	if relationships != null:
		for other in people.all_people():
			if other.id != stranger.id:
				relationships.modify(stranger.id, other.id, {"familiarity": Config.relationships.acquaintance_from}, 0, now)
		relationships.modify(stranger.id, lonely.id, {"familiarity": config.newcomer_spark,
			"affinity": config.newcomer_spark, "romance": config.newcomer_spark}, 0, now)
	counts["arrived"] = int(counts.get("arrived", 0)) + 1
	if day_log != null:
		day_log.note(stranger.id, now, "life", "arrived")
	arrived.emit(stranger.id)
	EventBus.person_born.emit(stranger.id)


## A grown-up, free, young enough, for whom there is nobody: no one of the
## other sex, free, grown-up, near enough in years and not of their family
## (the first of them by id; null if there is none).
func lonely_one(now: int) -> PersonData:
	var everyone := people.all_people()
	everyone.sort_custom(func(a: PersonData, b: PersonData) -> bool: return a.id < b.id)
	var year := Config.time.ticks_per_year()
	for person in everyone:
		if person.partner_id != 0 or _stage(person, now) != PersonData.LifeStage.ADULT \
				or person.age_years(now, year) > config.lonely_until_years:
			continue
		var someone := false
		for other in everyone:
			if other.sex != person.sex and other.partner_id == 0 and _grown(other, now) \
					and absi(other.age_years(now, year) - person.age_years(now, year)) <= config.partner_most_years_apart \
					and (relationships == null or not (relationships.is_family(person.id, other.id) or relationships.close_kin(person.id, other.id))):
				someone = true
				break
		if not someone:
			return person
	return null


## Two become partners: one household, one roof.
func partner(a: PersonData, b: PersonData, now: int) -> void:
	a.partner_id = b.id
	b.partner_id = a.id
	if households != null:
		households.form_couple(a, b, now, ids.next_id())
	counts["partners"] = int(counts.get("partners", 0)) + 1
	if day_log != null:
		day_log.note(a.id, now, "life", "partner", b.id)
		day_log.note(b.id, now, "life", "partner", a.id)
	partnered.emit(mini(a.id, b.id), maxi(a.id, b.id))


## Children: those carried long enough are born; couples with room and food
## enough may have one on the way.
func _children(now: int) -> void:
	var everyone := people.all_people()
	everyone.sort_custom(func(a: PersonData, b: PersonData) -> bool: return a.id < b.id)
	for mother in everyone:
		if not people.has_person(mother.id):
			continue
		var carrying := Hardship.condition_of(mother, PREGNANT)
		if not carrying.is_empty():
			if now - int(carrying.get("since", now)) >= config.carry_days * DAY:
				give_birth(mother, now)
			continue
		if may_conceive(mother, now) and rng.randf() < config.conceive_chance_per_day:
			conceive(mother, now)


## May she have a child now: a woman with a partner, young enough, her last
## child not too recent, a roof with room and food enough.
func may_conceive(mother: PersonData, now: int) -> bool:
	if mother.sex != PersonData.Sex.FEMALE or _stage(mother, now) != PersonData.LifeStage.ADULT \
			or mother.age_years(now, Config.time.ticks_per_year()) > config.fertile_until_years:
		return false
	var father := people.get_person(mother.partner_id) if mother.partner_id != 0 else null
	if father == null or is_pregnant(mother):
		return false
	for child in mother.children:
		var born_at: Variant = birth_tick_of(child)
		if born_at != null and now - int(born_at) < config.child_gap_days * DAY:
			return false
	if settlement != null and (settlement.is_short() or settlement.days_of_food() < config.food_days_for_child):
		return false
	if households != null and mother.home_building_id != 0 and households.room(mother.home_building_id) <= 0:
		return false
	return true


func conceive(mother: PersonData, now: int) -> void:
	var father := people.get_person(mother.partner_id)
	if father == null:
		return
	mother.conditions.append({"id": String(PREGNANT), "since": now, "father": father.id,
		"father_traits": Array(Traits.sanitized(father.traits)), "father_skin": int(father.appearance.get("skin", 0))})
	if day_log != null:
		day_log.note(mother.id, now, "life", "pregnant", father.id)


## A child is born to `mother` (now; whatever became of the father).
func give_birth(mother: PersonData, now: int) -> PersonData:
	var carrying := Hardship.condition_of(mother, PREGNANT)
	mother.conditions.erase(carrying)
	var father_id := int(carrying.get("father", mother.partner_id))
	var father := people.get_person(father_id)
	var father_record := archive.get_record(father_id) if archive != null and father == null else null
	var child := PersonData.new()
	child.id = ids.next_id()
	child.sex = PersonData.Sex.FEMALE if rng.randf() < 0.5 else PersonData.Sex.MALE
	child.birth_tick = now
	child.parents = PackedInt64Array([mother.id, father_id]) if father_id > 0 else PackedInt64Array([mother.id])
	var father_family := father.family_name if father != null else (father_record.family_name if father_record != null else "")
	child.family_name = father_family if config.family_name_from_father and father_family != "" else mother.family_name
	child.given_name = _name_for(child)
	var from_father: Variant = carrying.get("father_traits")
	var father_traits := PackedFloat32Array(from_father) if typeof(from_father) == TYPE_ARRAY \
		else (father.traits if father != null else Traits.generate(rng))
	child.traits = Traits.inherit(mother.traits, father_traits, rng)
	child.needs = Needs.full()
	child.health = rng.randf_range(0.9, 1.0)
	child.appearance = {
		"height": snappedf(rng.randf_range(0.92, 1.08), 0.01),
		"build": snappedf(rng.randf_range(0.9, 1.12), 0.01),
		"skin": int(mother.appearance.get("skin", 0)) if rng.randf() < 0.5 else int(carrying.get("father_skin", mother.appearance.get("skin", 0))),
		"hair": rng.randi_range(0, PersonData.HAIR_COLOURS - 1),
		"cloth": rng.randi_range(0, PersonData.CLOTH_COLOURS - 1),
	}
	child.household_id = mother.household_id
	child.home_building_id = mother.home_building_id
	child.settlement_id = mother.settlement_id
	child.occupation_id = occupations.choose(PersonData.LifeStage.CHILD, child.traits, rng) if occupations != null else &""
	child.position = mother.position
	child.sub_tile_offset = Vector2(clampf(mother.sub_tile_offset.x + 0.2, 0.05, 0.95), mother.sub_tile_offset.y)
	child.facing = mother.facing
	# (Born at home at night: indoors with her.)
	child.set_flag(PersonData.FLAG_INDOORS, mother.has_flag(PersonData.FLAG_INDOORS))
	mother.children.append(child.id)
	if father != null:
		father.children.append(child.id)
	elif father_record != null:
		archive.add_child(father_id, child.id)
	people.add(child)
	_stages[child.id] = PersonData.LifeStage.CHILD
	_welcome(child, now)
	counts["born"] = int(counts.get("born", 0)) + 1
	if day_log != null:
		day_log.note(child.id, now, "life", "born")
		for parent_id: int in child.parents:
			if people.has_person(parent_id):
				day_log.note(parent_id, now, "life", "child", child.id)
	if memories != null:
		for parent_id: int in child.parents:
			var parent := people.get_person(parent_id)
			if parent != null:
				memories.remember(parent, _life_memory(&"child_born", "MEM_CHILD_BORN", parent, now, 0.8))
	born.emit(child.id, mother.id, father_id)
	EventBus.person_born.emit(child.id)
	return child


## Someone dies (of `cause`): what they remembered most goes to those who come
## after them, they go to the archive, their partner is left alone, their
## household goes on without them — or is taken in by family.
func die(person: PersonData, cause: StringName, now: int, causes: Array = []) -> void:
	if person == null or not people.has_person(person.id):
		return
	_hand_down(person, now)
	_mourn(person, now)
	if archive != null:
		var record := HistoricalPerson.of(person, now, cause)
		_remember_them(person, record)
		archive.add(record)
		if graves != null:
			graves.bury(person.id)
	var partner := people.get_person(person.partner_id) if person.partner_id != 0 else null
	if partner != null and partner.partner_id == person.id:
		partner.partner_id = 0
		if day_log != null:
			day_log.note(partner.id, now, "life", "widowed", person.id)
	# What they carried goes to the stores.
	if settlement != null and person.carrying != &"" and person.carrying_amount > 0:
		settlement.stockpile.add(person.carrying, person.carrying_amount)
	var household := person.household_id
	var key := "died_" + String(cause)
	counts[key] = int(counts.get(key, 0)) + 1
	died.emit(person.id, cause, causes)
	people.remove(person.id)
	_stages.erase(person.id)
	if relationships != null:
		relationships.forget_person(person.id)
	if households != null:
		for moved: Array in households.after_death(household, now):
			if day_log != null:
				day_log.note(int(moved[0]), now, "life", "taken_in")
			taken_in.emit(int(moved[0]), int(moved[1]))
	EventBus.person_died.emit(person.id, cause)


## How much someone grieves now (0: not at all … 1), fading over the days of
## their mourning.
func grief_of(person: PersonData, now: int) -> float:
	var grieving := Hardship.condition_of(person, GRIEF)
	if grieving.is_empty():
		return 0.0
	var days := maxf(config.grief_days * float(grieving.get("strength", 0.0)), 0.001) * DAY
	return float(grieving.get("strength", 0.0)) * clampf(1.0 - float(now - int(grieving.get("since", now))) / days, 0.0, 1.0)


## Whose death someone grieves (0: nobody's).
static func grieving_for(person: PersonData) -> int:
	return int(Hardship.condition_of(person, GRIEF).get("of", 0))


# --- internals --------------------------------------------------------------------------------------

## Those who were close to them grieve: family most, then friends. Their
## spirits sink, they remember the loss, and they go to the grave.
func _mourn(person: PersonData, now: int) -> void:
	if relationships == null:
		return
	var everyone := people.all_people()
	everyone.sort_custom(func(a: PersonData, b: PersonData) -> bool: return a.id < b.id)
	for other in everyone:
		if other.id == person.id:
			continue
		var tie := relationships.family(other.id, person.id)
		var strength := 0.0
		if tie & (Relationship.Kind.PARTNER | Relationship.Kind.CHILD | Relationship.Kind.PARENT):
			strength = 1.0
		elif tie & Relationship.Kind.SIBLING:
			strength = 0.8
		elif relationships.close_kin(other.id, person.id):
			strength = 0.6
		var record := relationships.between(other.id, person.id)
		if record != null:
			if record.has_kind(Relationship.Kind.FRIEND):
				strength = maxf(strength, 0.5)
			elif record.affinity >= 0.25:
				strength = maxf(strength, 0.3)
		if strength <= 0.0:
			continue
		var grieving := Hardship.condition_of(other, GRIEF)
		if not grieving.is_empty() and grief_of(other, now) >= strength:
			pass # (a deeper grief already)
		else:
			other.conditions.erase(grieving)
			other.conditions.append({"id": String(GRIEF), "of": person.id, "since": now, "strength": strength})
		other.mood = maxf(other.mood - config.grief_mood * strength, 0.0)
		other.stress = minf(other.stress + 0.3 * strength, 1.0)
		if day_log != null and other.id != person.partner_id: # (their partner "loses" them: see die)
			day_log.note(other.id, now, "life", "mourns", person.id)
		if memories != null:
			var memory := _life_memory(&"death_of", "MEM_MOURNED", other, now, 0.4 + 0.5 * strength)
			memory.told_by = person.id
			memory.location = person.world2d()
			memory.emotions[ReactionTable.Emotion.JOY] = 0.0
			memory.emotions[ReactionTable.Emotion.FEAR] = 0.2 * strength
			memories.remember(other, memory)


## What the world keeps of them: what they did that was told of, what they
## remembered most, and how much they mattered.
func _remember_them(person: PersonData, record: HistoricalPerson) -> void:
	var deeds: Array[WorldEvent] = []
	if events != null:
		for event in events.all_events():
			# (Anything they were part of: everyone of a band founded the settlement.)
			if event.participants.has(person.id) and not NOT_DEEDS.has(event.type):
				deeds.append(event)
	deeds.sort_custom(func(a: WorldEvent, b: WorldEvent) -> bool:
		return a.significance > b.significance or (a.significance == b.significance and a.id < b.id))
	var weight := 0.0
	for event in deeds.slice(0, DEEDS_KEPT):
		record.accomplishments.append(event.id)
		weight += event.significance
	if memories != null:
		var own := memories.of(person)
		own.sort_custom(func(a: Memory, b: Memory) -> bool:
			return a.importance > b.importance or (a.importance == b.importance and a.id < b.id))
		for memory in own.slice(0, MEMORIES_KEPT):
			record.memories.append(memory.to_dict())
	var years := float(person.age_years(record.death_tick, Config.time.ticks_per_year()))
	record.significance = clampf(person.significance + years / 80.0 * 0.3 + mini(person.children.size(), 6) * 0.05 + weight * 0.1,
		0.0, 1.0)


## The few things they remembered most are handed down: to their children,
## else their partner, else their brothers and sisters.
func _hand_down(person: PersonData, now: int) -> void:
	if memories == null or config.memories_left <= 0:
		return
	var heirs: Array[PersonData] = []
	for id in person.children:
		var child := people.get_person(id)
		if child != null:
			heirs.append(child)
	if heirs.is_empty() and person.partner_id != 0 and people.get_person(person.partner_id) != null:
		heirs.append(people.get_person(person.partner_id))
	if heirs.is_empty():
		for other in people.all_people():
			if other.id != person.id and relationships != null and relationships.family(person.id, other.id) & Relationship.Kind.SIBLING:
				heirs.append(other)
	if heirs.is_empty():
		return
	var own: Array[Memory] = []
	for memory in memories.of(person):
		if memory.source == Memory.Source.DIRECT or memory.source == Memory.Source.WITNESSED:
			own.append(memory)
	own.sort_custom(func(a: Memory, b: Memory) -> bool:
		return a.importance > b.importance or (a.importance == b.importance and a.id < b.id))
	for memory in own.slice(0, config.memories_left):
		for heir in heirs:
			var copy := Memory.from_dict(memory.to_dict())
			if copy == null:
				continue
			copy.source = Memory.Source.INHERITED
			copy.told_by = person.id
			copy.first_tick = memory.first_tick
			copy.tick = now
			copy.importance = memory.importance * config.inherited_share
			copy.intensity = memory.intensity * config.inherited_share
			for i in copy.emotions.size():
				copy.emotions[i] *= config.inherited_share
			copy.fidelity = clampf(memory.fidelity * Config.memory.retelling_fidelity, 0.0, 1.0)
			copy.stage = _stage(heir, now)
			copy.told_tick = -1
			memories.remember(heir, copy)


## A newborn's family knows it as family.
func _welcome(child: PersonData, now: int) -> void:
	if relationships == null:
		return
	var rconfig := Config.relationships
	for other in people.all_people():
		if other.id == child.id or not (relationships.is_family(child.id, other.id) or other.household_id == child.household_id):
			continue
		relationships.modify(child.id, other.id, {"familiarity": rconfig.family_familiarity,
			"affinity": rconfig.family_affinity, "trust": rconfig.family_affinity}, 0, now)


## A name for a newborn: sometimes a forebear's (one of the same sex whose
## name nobody living bears), otherwise a new one.
func _name_for(child: PersonData) -> String:
	var taken := people.given_names()
	if rng.randf() < config.named_after_forebear:
		var forebears: Array[int] = []
		var ring := Array(child.parents)
		for generation in 2:
			var next: Array = []
			for id: int in ring:
				for parent in _parents_of(id):
					forebears.append(parent)
					next.append(parent)
			ring = next
		forebears.sort()
		for id in forebears:
			var name := ""
			var sex := -1
			var living := people.get_person(id)
			var record := archive.get_record(id) if archive != null else null
			if living != null:
				name = living.given_name
				sex = living.sex
			elif record != null:
				name = record.given_name
				sex = record.sex
			if name != "" and sex == child.sex and not taken.has(name):
				return name
	return names.given_name(rng, child.sex, taken) if names != null else "Child"


func _parents_of(id: int) -> PackedInt64Array:
	var person := people.get_person(id)
	if person != null:
		return person.parents
	var record := archive.get_record(id) if archive != null else null
	return record.parents if record != null else PackedInt64Array()


func _life_memory(subject: StringName, key: String, owner: PersonData, now: int, importance: float) -> Memory:
	var memory := Memory.new()
	memory.kind = Memory.KIND_EXPERIENCE
	memory.subject = subject
	memory.tick = now
	memory.first_tick = now
	memory.location = owner.world2d()
	memory.emotions = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
	memory.emotions.resize(ReactionTable.EMOTION_COUNT)
	memory.intensity = importance
	memory.importance = importance
	memory.source = Memory.Source.DIRECT
	memory.stage = _stage(owner, now)
	memory.text_key = key
	return memory


## Which of the causes it was (by their share of the chance).
func _pick(parts: Dictionary) -> StringName:
	var total := 0.0
	var causes: Array[String] = []
	for cause: StringName in parts:
		causes.append(String(cause))
	causes.sort() # (by name: the same order every time)
	for cause in causes:
		total += float(parts[StringName(cause)])
	var roll := rng.randf() * total
	for cause in causes:
		roll -= float(parts[StringName(cause)])
		if roll <= 0.0:
			return StringName(cause)
	return StringName(causes[-1]) if not causes.is_empty() else CAUSE_OLD_AGE


func _stage(person: PersonData, now: int) -> PersonData.LifeStage:
	return person.life_stage(now, Config.time.ticks_per_year(), Config.people)


func _grown(person: PersonData, now: int) -> bool:
	var stage := _stage(person, now)
	return stage == PersonData.LifeStage.ADULT or stage == PersonData.LifeStage.ELDER


static func _stage_word(stage: PersonData.LifeStage) -> String:
	return ["child", "adolescent", "adult", "elder"][stage]
