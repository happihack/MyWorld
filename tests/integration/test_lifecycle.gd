extends TestCase
## A life from beginning to end (M10.2, bible §16.2): growing up and old,
## partners, children, injuries and illness, death — and what the dead leave
## behind: the archive, their household, their memories.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440
const V20_FIXTURE := "res://tests/fixtures/saves/v20_world.sav"
const V20_ID := "w1790988369_6ad752ad"

var session: WorldSession
var life: Lifecycle
var config: LifeConfig
var ctx: AiContext
var events: EventLog
var people: Array[PersonData] = []
var _knobs: Array = []


func before_each() -> void:
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	life = session.lifecycle
	config = Config.life
	ctx = session.behavior.ctx
	events = session.events
	people = session.people.all_people()
	# Nothing happens by chance unless a test asks for it.
	for knob: StringName in [&"base_death_per_year", &"infant_death_per_year", &"old_age_death_per_year",
			&"accident_per_work_day", &"crowding_chance_per_day", &"partner_chance_per_day", &"conceive_chance_per_day",
			&"starve_chance_per_day", &"illness_death_per_day", &"injury_death_per_day", &"newcomer_chance_per_day", &"marry_out_chance_per_day", &"gathering_romance"]:
		_knob(config, knob, 0.0)


func after_each() -> void:
	_knobs.reverse()
	for knob: Array in _knobs:
		(knob[0] as Resource).set(knob[1], knob[2])
	_knobs.clear()
	session.queue_free()
	await wait_frames(1)


func _knob(resource: Resource, knob: StringName, value: Variant) -> void:
	_knobs.append([resource, knob, resource.get(knob)])
	resource.set(knob, value)


## A game day passes for the lifecycle (and the clock).
func _day(days: int = 1) -> void:
	for n in days:
		session.clock.tick += DAY
		life.advance_to(session.clock.tick)


func _years(person: PersonData) -> int:
	return person.age_years(session.clock.tick, Config.time.ticks_per_year())


## Makes someone `years` old (a little past their birthday).
func _make_age(person: PersonData, years: int) -> void:
	person.birth_tick = session.clock.tick - years * Config.time.ticks_per_year() - DAY


func _first(test: Callable) -> PersonData:
	for person in session.people.all_people():
		if test.call(person):
			return person
	return null


func _stage(person: PersonData) -> PersonData.LifeStage:
	return person.life_stage(session.clock.tick, Config.time.ticks_per_year(), Config.people)


## A couple of the band with children (the mother first).
func _couple() -> Array[PersonData]:
	for person in session.people.all_people():
		if person.sex == PersonData.Sex.FEMALE and person.partner_id != 0 and not person.children.is_empty():
			return [person, session.people.get_person(person.partner_id)]
	return []


## A grown-up of each sex from outside, both free (each a household of their own).
func _two_newcomers() -> Array[PersonData]:
	var a := session.spawn_person(session.start.settlement_tile)
	var b := session.spawn_person(session.start.settlement_tile)
	a.sex = PersonData.Sex.FEMALE
	b.sex = PersonData.Sex.MALE
	_make_age(a, 24)
	_make_age(b, 27)
	return [a, b]


# --- growing up and old -----------------------------------------------------------------------------


func test_people_meet_at_the_evening_gatherings() -> void:
	# (PG.2: romance grew only by chance flirting; the dance, the songs, the
	# stories, a festival, the fire are where people meet.)
	_knob(config, &"gathering_romance", 0.1)
	var now := session.clock.tick
	var a := session.spawn_person(session.settlement.fire().tile)
	var b := session.spawn_person(session.settlement.fire().tile)
	var c := session.spawn_person(session.settlement.fire().tile)
	a.sex = PersonData.Sex.FEMALE
	b.sex = PersonData.Sex.MALE
	c.sex = PersonData.Sex.MALE
	for p: PersonData in [a, b, c]:
		p.birth_tick = now - 25 * Config.time.ticks_per_year()
		p.partner_id = 0
	a.activity_log["dance"] = now
	b.activity_log["sing"] = now
	life._gatherings(now)
	var ab := session.relationships.between(a.id, b.id)
	assert_not_null(ab, "they met")
	assert_true(ab.romance > 0.0, "and feel a little more (%.3f)" % ab.romance)
	var ac := session.relationships.between(a.id, c.id)
	assert_true(ac == null or ac.romance == 0.0, "who was not there did not meet her")

func test_aging_stage_transitions() -> void:
	assert_eq(config.validate().size(), 0, str(config.validate()))
	assert_eq(Config.problems.size(), 0, str(Config.problems))
	var child := _first(func(p: PersonData) -> bool: return _stage(p) == PersonData.LifeStage.CHILD)
	assert_not_null(child, "the band has a child")
	assert_eq(child.occupation_id, &"child")
	# The day they turn twelve: no longer a child — and their work is no longer play.
	child.birth_tick = session.clock.tick + DAY - Config.people.adolescent_from_years * Config.time.ticks_per_year()
	_day()
	assert_eq(_stage(child), PersonData.LifeStage.ADOLESCENT)
	assert_true(session.occupations.get_def(child.occupation_id).allows(PersonData.LifeStage.ADOLESCENT),
		"%s is open to an adolescent" % child.occupation_id)
	assert_eq(events.count_of(Chronicler.TYPE_CAME_OF_AGE), 0, "no event for that")
	assert_eq(DayLogText.text(session.day_log.of(child.id)[-1], session.people), "is no longer a child")
	# Grown up: adult work, and the world takes note.
	child.birth_tick = session.clock.tick + DAY - Config.people.adult_from_years * Config.time.ticks_per_year()
	_day()
	assert_eq(_stage(child), PersonData.LifeStage.ADULT)
	assert_true(session.occupations.get_def(child.occupation_id).allows(PersonData.LifeStage.ADULT))
	var came := events.latest(Chronicler.TYPE_CAME_OF_AGE)
	assert_not_null(came)
	assert_eq(EventText.text(came, session.people, events), "%s has come of age" % child.given_name)
	# Old: an elder's work.
	child.birth_tick = session.clock.tick + DAY - Config.people.elder_from_years * Config.time.ticks_per_year()
	_day()
	assert_eq(child.occupation_id, &"elder")
	assert_eq(EventText.text(events.latest(Chronicler.TYPE_CAME_OF_AGE), session.people, events),
		"%s is one of the elders now" % child.given_name)
	# Nothing changes on a day that changes nothing.
	var count := events.size()
	_day()
	assert_eq(events.size(), count)


# --- partners -----------------------------------------------------------------------------------------

func test_partnership() -> void:
	var pair := _two_newcomers()
	var a := pair[0]
	var b := pair[1]
	var store := session.relationships
	_knob(config, &"partner_chance_per_day", 1.0)
	# Not without romance.
	store.modify(a.id, b.id, {"familiarity": 0.6, "affinity": 0.6}, 0, session.clock.tick)
	_day()
	assert_eq(a.partner_id, 0)
	# Drawn to each other: partners. One of them lived alone: the other moves in.
	store.between(a.id, b.id).romance = 0.8
	store.between(a.id, b.id).affinity = 0.6
	var household := a.household_id
	_day()
	assert_eq([a.partner_id, b.partner_id], [b.id, a.id])
	assert_true(store.is_family(a.id, b.id))
	assert_eq(store.kinds(a.id, b.id) & Relationship.Kind.PARTNER, Relationship.Kind.PARTNER)
	assert_eq(b.household_id, household, "the one who lived alone took the other in")
	assert_eq(b.home_building_id, a.home_building_id)
	var event := events.latest(Chronicler.TYPE_PARTNERS)
	assert_not_null(event)
	assert_true(event.involves(a.id) and event.involves(b.id))
	assert_eq(DayLogText.text(session.day_log.of(a.id)[-1], session.people), "becomes %s's partner" % b.given_name)
	assert_eq(int(life.counts.get("partners", 0)), 1)
	# Not between family, not between two of one sex, not too far apart in years, not when taken.
	var c := session.spawn_person(session.start.settlement_tile)
	c.sex = PersonData.Sex.MALE
	_make_age(c, 25)
	store.modify(a.id, c.id, {"familiarity": 0.6, "affinity": 0.6, "romance": 0.9}, 0, session.clock.tick)
	_day()
	assert_eq(c.partner_id, 0, "she has a partner")
	var d := session.spawn_person(session.start.settlement_tile)
	d.sex = PersonData.Sex.FEMALE
	_make_age(d, 25 + config.partner_most_years_apart + 1)
	store.modify(c.id, d.id, {"familiarity": 0.6, "affinity": 0.6, "romance": 0.9}, 0, session.clock.tick)
	_day()
	assert_eq(c.partner_id, 0, "too far apart in years")
	_make_age(d, 26)
	d.sex = PersonData.Sex.MALE
	_day()
	assert_eq(c.partner_id, 0, "of one sex")
	d.sex = PersonData.Sex.FEMALE
	d.parents = PackedInt64Array([c.id])
	c.children.append(d.id)
	_day()
	assert_eq(c.partner_id, 0, "family")
	d.parents = PackedInt64Array()
	c.children = PackedInt64Array()
	_day()
	assert_eq(c.partner_id, d.id, "and now nothing stands between them")


func test_a_couple_founds_a_household_of_its_own() -> void:
	# Two of the band's grown children (from two households) become partners:
	# a new household, under the roof with most room; nobody else moves.
	var a := session.spawn_person(session.start.settlement_tile)
	var b := session.spawn_person(session.start.settlement_tile)
	a.sex = PersonData.Sex.FEMALE
	b.sex = PersonData.Sex.MALE
	var couple := _couple()
	a.household_id = couple[0].household_id
	a.home_building_id = couple[0].home_building_id
	var others := _first(func(p: PersonData) -> bool: return p.household_id != couple[0].household_id and p.household_id != a.id)
	b.household_id = others.household_id
	b.home_building_id = others.home_building_id
	session.households.ensure_records(session.clock.tick)
	var households_before := session.households.size()
	var expected_home := session.households.roomiest_home([a.id, b.id])
	life.partner(a, b, session.clock.tick)
	assert_ne(a.household_id, couple[0].household_id)
	assert_eq(a.household_id, b.household_id)
	assert_true(session.households.has_household(a.household_id))
	assert_eq(session.households.home_of(a.household_id), expected_home)
	assert_eq(a.home_building_id, expected_home)
	assert_eq(couple[0].household_id, couple[1].household_id, "their families stay as they were")
	assert_eq(session.households.size(), households_before + 1)
	# Saved with the world.
	assert_eq(session.households.to_dict()["households"].size(), session.households.size())


# --- children -----------------------------------------------------------------------------------------

func test_birth() -> void:
	var couple := _couple()
	var mother := couple[0]
	var father := couple[1]
	_make_age(mother, 30)
	_make_age(father, 32)
	for child in mother.children:
		_make_age(session.people.get_person(child), 5)
	# What it takes: a partner, her age, room under the roof, food enough, no child too recent.
	session.settlement.stockpile.add(&"grain", 200)
	assert_true(life.may_conceive(mother, session.clock.tick), "a couple with room and food")
	assert_false(life.may_conceive(father, session.clock.tick), "a man does not")
	_make_age(mother, config.fertile_until_years + 1)
	assert_false(life.may_conceive(mother, session.clock.tick), "too old")
	_make_age(mother, 30)
	# Food makes a child likelier or less likely, it does not forbid one (PG.3).
	assert_near(life.conceive_share(mother), 1.0, 0.0001, "well fed: the whole chance")
	_knob(config, &"food_days_for_child", 1000.0)
	assert_true(life.may_conceive(mother, session.clock.tick), "short of food, still possible")
	assert_true(life.conceive_share(mother) < 0.35 and life.conceive_share(mother) >= config.hungry_conceive_share,
		"but much less likely (%.2f)" % life.conceive_share(mother))
	session.settlement.shortage = Settlement.Shortage.SHORT
	assert_near(life.conceive_share(mother), config.short_conceive_share, 0.0001, "while it rations: little")
	session.settlement.shortage = Settlement.Shortage.EMPTY
	assert_eq(life.conceive_share(mother), 0.0, "the stores empty: none")
	session.settlement.shortage = Settlement.Shortage.NONE
	_knob(config, &"food_days_for_child", 0.0)
	_knob(config, &"home_room", session.people.living_in(mother.home_building_id).size())
	assert_false(life.may_conceive(mother, session.clock.tick), "no room under the roof")
	_knob(config, &"home_room", 30)
	var youngest := session.people.get_person(mother.children[0])
	youngest.birth_tick = session.clock.tick - DAY
	assert_false(life.may_conceive(mother, session.clock.tick), "a child too recent")
	_make_age(youngest, 5)
	assert_true(life.may_conceive(mother, session.clock.tick))
	# With child: the days she carries it, then it is born.
	life.conceive(mother, session.clock.tick)
	assert_true(Lifecycle.is_pregnant(mother))
	assert_false(life.may_conceive(mother, session.clock.tick), "not twice")
	assert_eq(DayLogText.text(session.day_log.of(mother.id)[-1], session.people), "is with child")
	var count := session.people.size()
	_day(config.carry_days - 1)
	assert_eq(session.people.size(), count, "not yet")
	_day()
	assert_eq(session.people.size(), count + 1)
	assert_false(Lifecycle.is_pregnant(mother))
	var child := session.people.get_person(mother.children[-1])
	assert_not_null(child)
	assert_eq(child.parents, PackedInt64Array([mother.id, father.id]))
	assert_true(father.children.has(child.id))
	assert_eq(child.family_name, father.family_name if config.family_name_from_father else mother.family_name)
	assert_eq([child.household_id, child.home_building_id, child.settlement_id],
		[mother.household_id, mother.home_building_id, mother.settlement_id])
	assert_eq(_years(child), 0)
	assert_eq(child.occupation_id, &"child")
	assert_ne(child.given_name, "")
	# Its nature: from its parents, within bounds.
	assert_eq(child.traits, Traits.sanitized(child.traits))
	assert_eq(child.traits.size(), Traits.COUNT)
	assert_eq(child.needs.size(), Needs.COUNT)
	# Known to its family; remembered by its parents; told of.
	assert_true(session.relationships.is_family(child.id, mother.id))
	assert_near(session.relationships.familiarity(child.id, mother.id), Config.relationships.family_familiarity, 0.001)
	var born := events.latest(Chronicler.TYPE_BORN)
	assert_not_null(born)
	assert_eq(Array(born.participants), [child.id, mother.id, father.id])
	assert_true(EventText.text(born, session.people, events).contains("%s, to %s and %s" % [child.given_name,
		mother.given_name, father.given_name]), EventText.text(born, session.people, events))
	assert_eq(DayLogText.text(session.day_log.of(mother.id)[-1], session.people), "has a child: %s" % child.given_name)
	assert_eq(DayLogText.text(session.day_log.of(child.id)[-1], session.people), "is born")
	var remembered := session.memories.about(mother, &"child_born")
	assert_eq(remembered.size(), 1)
	assert_eq(MemoryText.text(remembered[0], session.people), "saw their child born")
	assert_eq(int(life.counts.get("born", 0)), 1)


func test_traits_are_inherited_within_bounds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mother := Traits.generate(rng)
	var father := Traits.generate(rng)
	for n in 200:
		var child := Traits.inherit(mother, father, rng)
		assert_eq(child, Traits.sanitized(child))
	# Alike parents, alike children (on the whole).
	var same := Traits.neutral()
	same[Traits.Axis.CURIOSITY] = 0.8
	var total := 0.0
	for n in 200:
		total += Traits.value(Traits.inherit(same, same, rng), Traits.Axis.CURIOSITY)
	assert_true(total / 200.0 > 0.5, "children of the curious are curious (%.2f)" % (total / 200.0))


func test_named_after_a_forebear() -> void:
	var couple := _couple()
	var mother := couple[0]
	# Her parent, dead: their name is free for a grandchild of their sex.
	var elder := _first(func(p: PersonData) -> bool: return p.children.has(mother.id) or p.children.has(couple[1].id))
	if elder == null:
		elder = session.spawn_person(session.start.settlement_tile)
		mother.parents = PackedInt64Array([elder.id])
		elder.children.append(mother.id)
	var name := elder.given_name
	session.kill_person(elder.id, Lifecycle.CAUSE_OLD_AGE)
	_knob(config, &"named_after_forebear", 1.0)
	var child := PersonData.new()
	child.parents = PackedInt64Array([mother.id, couple[1].id])
	child.sex = elder.sex
	assert_eq(life._name_for(child), name)
	child.sex = PersonData.Sex.MALE if elder.sex == PersonData.Sex.FEMALE else PersonData.Sex.FEMALE
	assert_ne(life._name_for(child), name, "not of the other sex")
	_knob(config, &"named_after_forebear", 0.0)
	child.sex = elder.sex
	assert_ne(life._name_for(child), name, "a new name, mostly")


# --- injuries and illness -----------------------------------------------------------------------------

func test_injuries_heal() -> void:
	var person := _first(func(p: PersonData) -> bool: return _stage(p) == PersonData.LifeStage.ADULT)
	person.health = 1.0
	Health.injure(person, Health.FALL, 0.5, session.clock.tick)
	assert_near(person.health, 1.0 - 0.5 * config.injury_health, 0.0001)
	assert_near(Health.unwell(person), 0.5, 0.0001)
	# Days pass: it heals, and the health comes back (faster for someone resting).
	Health.live(person, ctx, DAY)
	assert_near(Health.worst_injury(person), 0.5 - config.injury_heal_per_day, 0.0001)
	person.pose = PersonData.Pose.SLEEP
	Health.live(person, ctx, DAY)
	assert_near(Health.worst_injury(person), 0.5 - config.injury_heal_per_day * (1.0 + config.rest_heals), 0.0001)
	person.pose = PersonData.Pose.IDLE
	for n in 10:
		Health.live(person, ctx, DAY)
	assert_true(person.injuries.is_empty())
	assert_near(person.health, 1.0, 0.0001)
	# Hurt, they go home to rest — and work less.
	Health.injure(person, Health.CUT, 0.7, session.clock.tick)
	var go_home := session.activities.get_def(&"go_home")
	var work := session.activities.get_def(&"work")
	var hurt_home := Brain.score(go_home, person, ctx)
	var hurt_work := Brain.score(work, person, ctx)
	person.injuries.clear()
	assert_true(hurt_home > Brain.score(go_home, person, ctx) + 0.2)
	assert_true(hurt_work < Brain.score(work, person, ctx) or Brain.score(work, person, ctx) <= 0.0)
	Health.injure(person, Health.CUT, 0.7, session.clock.tick)
	assert_eq(Brain._reason(go_home, person, ctx), Brain.REASON_UNWELL)


func test_illness() -> void:
	var person := _first(func(p: PersonData) -> bool: return _stage(p) == PersonData.LifeStage.ADULT)
	person.health = 0.9
	assert_true(Health.fall_ill(person, Health.BAD_WATER, session.clock.tick))
	assert_false(Health.fall_ill(person, Health.CROWDING, session.clock.tick), "one illness at a time")
	assert_true(Health.is_ill(person))
	_knob(config, &"illness_passes_per_day", 0.0)
	for n in 30:
		Health.live(person, ctx, DAY)
	assert_near(person.health, config.illness_floor, 0.0001, "it takes their health, down to the floor")
	# Gravely ill: they may die of it.
	_knob(config, &"illness_death_per_day", 0.04)
	var chance: Array = life.death_chance(person, session.clock.tick)
	assert_true((chance[1] as Dictionary).has(Lifecycle.CAUSE_ILLNESS))
	# It passes, and they get well.
	_knob(config, &"illness_passes_per_day", 1.0)
	Health.live(person, ctx, DAY)
	assert_false(Health.is_ill(person))
	assert_eq(ctx.ailments[-1], [person.id, Health.ILLNESS, false])
	for n in 10:
		Health.live(person, ctx, DAY)
	assert_near(person.health, 0.9, 0.0001)
	assert_true(Health.illness_of(person).is_empty())


func test_bad_water_and_crowding_make_people_ill() -> void:
	var person := _first(func(p: PersonData) -> bool: return _stage(p) == PersonData.LifeStage.ADULT)
	_knob(config, &"bad_water_chance", 1.0)
	# The river is good water; a puddle is not.
	var river := session.hydrology.bed()[0]
	assert_false(bool(ctx.bad_water.call(river)))
	Health.drank(person, ctx, river)
	assert_false(Health.is_ill(person))
	var dry := session.start.settlement_tile
	assert_true(bool(ctx.bad_water.call(dry)), "water where there was none of old")
	Health.drank(person, ctx, dry)
	assert_true(Health.is_ill(person))
	session.behavior.announce()
	var ill := events.latest(Chronicler.TYPE_ILL)
	assert_not_null(ill)
	assert_eq(EventText.text(ill, session.people, events), "%s has fallen ill from bad water" % person.given_name)
	assert_eq(DayLogText.text(session.day_log.of(person.id)[-1], session.people), "falls ill from bad water")
	# A crowded roof.
	var home := person.home_building_id
	_knob(config, &"home_room", session.people.living_in(home).size() - 1)
	_knob(config, &"crowding_chance_per_day", 1.0)
	_day()
	for other in session.people.living_in(home):
		assert_false(Health.illness_of(other).is_empty(), "%s is ill" % other.given_name)
	assert_eq(EventText.text(events.latest(Chronicler.TYPE_ILL), session.people, events).ends_with("under a crowded roof"), true)


func test_accidents_at_work() -> void:
	_knob(config, &"accident_per_work_day", 1.0)
	var worker := _first(func(p: PersonData) -> bool:
		var def := session.occupations.get_def(p.occupation_id)
		return def != null and def.work_target != &"")
	worker.activity_log["work"] = session.clock.tick
	var idle := _first(func(p: PersonData) -> bool: return p.id != worker.id)
	idle.activity_log.erase("work")
	_day()
	assert_false(worker.injuries.is_empty(), "hurt at work")
	var event := events.latest(Chronicler.TYPE_INJURED)
	assert_not_null(event)
	assert_true(event.involves(worker.id))
	assert_true(idle.injuries.is_empty() or idle.activity_log.has("work"), "nobody is hurt at work who did not work")


# --- death ----------------------------------------------------------------------------------------------

func test_death_chance() -> void:
	_knob(config, &"base_death_per_year", 0.004)
	_knob(config, &"old_age_death_per_year", 0.05)
	_knob(config, &"infant_death_per_year", 0.02)
	var person := _first(func(p: PersonData) -> bool: return _stage(p) == PersonData.LifeStage.ADULT)
	person.health = 1.0
	_make_age(person, 30)
	var young := float(life.death_chance(person, session.clock.tick)[0])
	_make_age(person, config.old_age_from_years + 12)
	var old: Array = life.death_chance(person, session.clock.tick)
	assert_true(float(old[0]) > young * 10.0, "the old die far more often (%f, %f)" % [old[0], young])
	assert_true((old[1] as Dictionary).has(Lifecycle.CAUSE_OLD_AGE))
	var per_day := 1.0 - exp(-(0.004 + 0.05 * 4.0) / float(Config.time.days_per_year()))
	assert_near(float(old[0]), per_day, 0.00001)
	_make_age(person, 0)
	assert_true(float(life.death_chance(person, session.clock.tick)[0]) > young, "and the very young")
	# Ill health makes it likelier.
	_make_age(person, 30)
	person.health = 0.3
	assert_true(float(life.death_chance(person, session.clock.tick)[0]) > young * 3.0)
	# Starving, for days on end.
	_knob(config, &"starve_chance_per_day", 0.06)
	person.health = Config.needs.sick_health_floor
	person.conditions.append({"id": "hunger", "since": session.clock.tick - 10 * DAY, "sick": true, "well": 1.0, "fed": false})
	var starving: Array = life.death_chance(person, session.clock.tick)
	assert_near(float((starving[1] as Dictionary).get(Lifecycle.CAUSE_STARVATION, 0.0)), 0.06, 0.0001)
	# Gravely hurt in a fight.
	person.conditions.clear()
	person.health = 1.0
	_knob(config, &"injury_death_per_day", 0.03)
	Health.injure(person, Health.FIGHT, 0.9, session.clock.tick)
	assert_true((life.death_chance(person, session.clock.tick)[1] as Dictionary).has(Lifecycle.CAUSE_INJURY))
	person.injuries.clear()
	Health.injure(person, Health.FALL, 0.9, session.clock.tick)
	assert_true((life.death_chance(person, session.clock.tick)[1] as Dictionary).has(Lifecycle.CAUSE_ACCIDENT))


func test_death_archives_person() -> void:
	var couple := _couple()
	var dying := couple[1]
	var partner := couple[0]
	var friend := _first(func(p: PersonData) -> bool: return not session.relationships.is_family(p.id, dying.id) and p.id != dying.id)
	session.relationships.modify(dying.id, friend.id, {"affinity": 0.8, "familiarity": 0.7}, 0, session.clock.tick)
	var friends := events.latest(Chronicler.TYPE_FRIENDS)
	assert_not_null(friends)
	var name := dying.given_name
	var children := dying.children.duplicate()
	var household := dying.household_id
	var count := session.people.size()
	# (Nobody else is anywhere near as old.)
	_knob(config, &"old_age_from_years", 150)
	_knob(config, &"old_age_death_per_year", 1000.0)
	_make_age(dying, 170)
	_day()
	assert_null(session.people.get_person(dying.id), "gone from the living")
	assert_eq(session.people.size(), count - 1)
	var record := session.archive.get_record(dying.id)
	assert_not_null(record, "kept in the archive")
	assert_eq([record.given_name, record.family_name, record.birth_tick, record.death_tick, record.cause],
		[name, dying.family_name, dying.birth_tick, session.clock.tick, Lifecycle.CAUSE_OLD_AGE])
	assert_eq(record.children, children)
	assert_eq(record.partner_id, partner.id)
	assert_eq(record.age_years(Config.time.ticks_per_year()), 170)
	# Their partner is left alone; their household goes on.
	assert_eq(partner.partner_id, 0)
	assert_eq(DayLogText.text(session.day_log.of(partner.id)[-1], session.people), "loses %s" % name)
	assert_eq(partner.household_id, household)
	assert_true(session.households.has_household(household))
	# The world tells of it — and still knows who they were.
	var died := events.latest(Chronicler.TYPE_DIED)
	assert_not_null(died)
	assert_eq(EventText.text(died, session.people, events), "%s has died, old and full of years" % name)
	assert_true(EventText.text(friends, session.people, events).contains(name), "an older event still names them")
	assert_eq(session.people.name_of(dying.id), name)
	assert_eq(session.relationships.between(dying.id, friend.id), null, "what others were to them goes with them")
	# Lineage outlives them: their children's parents are found in the archive.
	for child_id in children:
		var child := session.people.get_person(child_id)
		if child != null:
			assert_true(child.parents.has(dying.id))
	assert_eq(int(life.counts.get("died_old_age", 0)), 1)
	# The debug kill is a death like any other.
	assert_true(session.kill_person(friend.id))
	assert_not_null(session.archive.get_record(friend.id))
	assert_eq(EventText.text(events.latest(Chronicler.TYPE_DIED), session.people, events), "%s is gone" % friend.given_name)


func test_inheritance() -> void:
	var couple := _couple()
	var mother := couple[0]
	var father := couple[1]
	assert_false(mother.children.is_empty())
	var child := session.people.get_person(mother.children[0])
	# What she remembered most goes to her children.
	var memory := Memory.new()
	memory.subject = &"touch"
	memory.interpretation = &"spirit"
	memory.tick = session.clock.tick - 3 * DAY
	memory.first_tick = memory.tick
	memory.importance = 0.9
	memory.intensity = 0.8
	memory.emotions = PackedFloat32Array([0.0, 0.5, 0.0, 0.0, 0.0])
	memory.source = Memory.Source.DIRECT
	session.memories.remember(mother, memory)
	# What she carried goes to the stores.
	mother.carrying = &"wood"
	mother.carrying_amount = 3
	var wood := session.settlement.stockpile.amount(&"wood")
	session.kill_person(mother.id, Lifecycle.CAUSE_ILLNESS)
	assert_eq(session.settlement.stockpile.amount(&"wood"), wood + 3)
	var inherited: Array[Memory] = []
	for kept in session.memories.of(child):
		if kept.source == Memory.Source.INHERITED:
			inherited.append(kept)
	assert_false(inherited.is_empty(), "her memories live on in her child")
	var touch: Memory = null
	for kept in inherited:
		if kept.subject == &"touch":
			touch = kept
	assert_not_null(touch)
	assert_eq(touch.told_by, mother.id)
	assert_near(touch.importance, 0.9 * config.inherited_share, 0.0001)
	assert_true(MemoryText.text(touch, session.people).begins_with("remembers how %s " % mother.given_name),
		MemoryText.text(touch, session.people))
	assert_true(touch.first_tick == memory.first_tick)
	# The home stays with the household; when the father dies too, the
	# children are taken in by family (or whoever has most room).
	var home := child.home_building_id
	assert_eq(home, father.home_building_id)
	var orphans: Array[PersonData] = []
	for other in session.people.in_household(father.household_id):
		if other.id != father.id:
			orphans.append(other)
	var all_children := true
	for orphan in orphans:
		all_children = all_children and _stage(orphan) in [PersonData.LifeStage.CHILD, PersonData.LifeStage.ADOLESCENT]
	var household := father.household_id
	session.kill_person(father.id, Lifecycle.CAUSE_ACCIDENT)
	if all_children and not orphans.is_empty():
		for orphan in orphans:
			assert_ne(orphan.household_id, household, "%s was taken in" % orphan.given_name)
			assert_eq(orphan.home_building_id, session.households.home_of(orphan.household_id))
		assert_false(session.households.has_household(household), "a household nobody is left in is gone")
		var taken := events.latest(Chronicler.TYPE_TAKEN_IN)
		assert_not_null(taken)
		assert_true(EventText.text(taken, session.people, events).contains("left alone"), EventText.text(taken, session.people, events))
	else:
		assert_true(session.households.has_household(household))


func test_an_elder_left_alone_moves_in_with_a_child() -> void:
	var elder := session.spawn_person(session.start.settlement_tile, PersonData.LifeStage.ELDER)
	var partner := session.spawn_person(session.start.settlement_tile, PersonData.LifeStage.ELDER)
	elder.sex = PersonData.Sex.FEMALE
	partner.sex = PersonData.Sex.MALE
	life.partner(elder, partner, session.clock.tick)
	var son := _couple()[1]
	elder.children.append(son.id)
	son.parents = PackedInt64Array([elder.id])
	session.kill_person(partner.id, Lifecycle.CAUSE_OLD_AGE)
	assert_eq(elder.household_id, son.household_id, "she lives with her son now")
	assert_eq(elder.home_building_id, son.home_building_id)


# --- the running world and saving ---------------------------------------------------------------------

func test_lives_are_saved() -> void:
	var couple := _couple()
	_make_age(couple[0], 30)
	session.lifecycle.conceive(couple[0], session.clock.tick)
	Health.injure(couple[1], Health.CUT, 0.4, session.clock.tick)
	var gone := _first(func(p: PersonData) -> bool: return p.partner_id == 0 and p.children.is_empty())
	session.kill_person(gone.id, Lifecycle.CAUSE_ILLNESS)
	life.counts["born"] = 3
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	assert_true(loaded.ok, loaded.error)
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(loaded.world))
	again.set_process(false)
	assert_eq(again.archive.to_dict(), session.archive.to_dict())
	assert_eq(again.archive.get_record(gone.id).cause, Lifecycle.CAUSE_ILLNESS)
	assert_eq(again.people.name_of(gone.id), gone.given_name)
	assert_eq(again.households.to_dict(), session.households.to_dict())
	assert_eq(again.lifecycle.counts, life.counts)
	assert_eq(again.lifecycle.to_dict()["day"], life.to_dict()["day"])
	assert_true(Lifecycle.is_pregnant(again.people.get_person(couple[0].id)))
	assert_eq(again.people.get_person(couple[1].id).injuries.size(), 1)
	assert_true(again.behavior.ctx.lifecycle == again.lifecycle)
	assert_true(again.people.archive == again.archive)
	again.queue_free()
	# Broken records in a save are left out.
	var archive := HistoryArchive.new()
	assert_eq(archive.from_dict({"people": [{"id": 0}, "x", {"id": 5, "given_name": "Ama", "death_tick": -3, "birth_tick": 10},
		{"id": 5}]}), 3)
	assert_eq(archive.get_record(5).death_tick, 10, "nobody dies before they are born")
	var households := Households.new()
	households.bind(session.people, session.start)
	assert_eq(households.from_dict({"households": [{"id": -1}, {"id": 4, "home": -2}, {"id": 4}, 7]}), 3)
	assert_eq(households.home_of(4), 0)


func test_version_20_save_gets_households() -> void:
	var dir := SaveManager.world_dir(V20_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V20_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 20)
	var loaded := SaveManager.load_world(V20_ID)
	assert_true(loaded.ok, loaded.error)
	assert_eq(loaded.world["world_state"]["households"], {})
	assert_eq(loaded.world["world_state"]["archive"], {})
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	assert_eq(s.people.size(), 8)
	assert_eq(s.archive.size(), 0, "nobody has died yet")
	# Its households are as its people have them.
	assert_eq(s.households.size(), s.people.household_ids().size())
	for id in s.households.ids():
		for member in s.households.members(id):
			assert_eq(member.home_building_id, s.households.home_of(id))
	# Saved again: the current version, the old file kept.
	assert_true(SaveManager.save_world(s, &"test"))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav.bak1")).header["save_version"], 20)
	s.queue_free()
	# The step itself.
	assert_eq(SaveMigrations._v20_to_v21({"world": {"world_state": {}}})["world"]["world_state"], {})
	var state: Dictionary = SaveMigrations._v20_to_v21({"world": {"world_state": {"people": {}}}})["world"]["world_state"]
	assert_eq([state["households"], state["lifecycle"], state["archive"]], [{}, {}, {}])
	var kept: Dictionary = SaveMigrations._v20_to_v21({"world": {"world_state": {"archive": {"people": []}}}})
	assert_eq(kept["world"]["world_state"]["archive"], {"people": []})
	assert_true(SaveManager.SAVE_VERSION >= 21)


func test_someone_comes_from_far_away() -> void:
	_knob(config, &"newcomer_chance_per_day", 1.0)
	# Everyone has someone (or is too young or old to look): nobody comes.
	for person in session.people.all_people():
		if person.partner_id == 0 and _stage(person) == PersonData.LifeStage.ADULT:
			_make_age(person, 10)
	var count := session.people.size()
	_day()
	assert_eq(session.people.size(), count)
	assert_null(life.lonely_one(session.clock.tick))
	# A young woman with nobody to become partners with: a man comes.
	var lonely := session.spawn_person(session.start.settlement_tile)
	lonely.sex = PersonData.Sex.FEMALE
	_make_age(lonely, 20)
	assert_true(life.lonely_one(session.clock.tick) == lonely)
	_day()
	assert_eq(session.people.size(), count + 2)
	var stranger: PersonData = session.people.all_people()[-1]
	assert_eq(stranger.sex, PersonData.Sex.MALE)
	assert_true(absi(_years(stranger) - _years(lonely)) <= 4 or _years(stranger) == Config.people.adult_from_years)
	assert_true(session.households.has_household(stranger.household_id))
	assert_true(session.relationships.familiarity(stranger.id, lonely.id) > 0.0, "introduced")
	assert_near(session.relationships.between(stranger.id, lonely.id).romance, config.newcomer_spark, 0.0001, "a spark")
	var event := events.latest(Chronicler.TYPE_ARRIVED)
	assert_not_null(event)
	assert_eq(EventText.text(event, session.people, events), "%s has come from far away to live here" % stranger.given_name)
	# Now she has someone: nobody else comes.
	assert_null(life.lonely_one(session.clock.tick))
	_day()
	assert_eq(session.people.size(), count + 2)
	# No room under the roofs: nobody comes.
	stranger.sex = PersonData.Sex.FEMALE
	_knob(config, &"home_room", 1)
	_day()
	assert_eq(session.people.size(), count + 2)


func test_chemistry() -> void:
	var a := people[0]
	var b := people[1]
	assert_eq(SocialActs.chemistry(a, b), SocialActs.chemistry(b, a), "the same both ways")
	assert_true(SocialActs.chemistry(a, b) >= 0.0 and SocialActs.chemistry(a, b) <= 1.0)
	var spread := {}
	for x in range(1, 40):
		for y in range(x + 1, 40):
			var one := PersonData.new()
			one.id = x
			var other := PersonData.new()
			other.id = y
			spread[floori(SocialActs.chemistry(one, other) * 4.0)] = true
	assert_eq(spread.size(), 4, "some pairs are drawn to each other, some not")


func test_a_baby_stays_with_its_parent() -> void:
	var couple := _couple()
	life.conceive(couple[0], session.clock.tick)
	var baby := life.give_birth(couple[0], session.clock.tick)
	assert_eq(_years(baby), 0)
	for id: StringName in [&"play", &"explore", &"socialize", &"work"]:
		assert_eq(Brain.score(session.activities.get_def(id), baby, ctx), -1.0, "a baby does not %s" % id)
	assert_true(Brain.score(session.activities.get_def(&"tag_along"), baby, ctx) >= 0.0, "it stays with its parent")
	assert_true(PersonMeshLibrary.height_factor(0, Config.people) < PersonMeshLibrary.height_factor(1, Config.people))
	# Two years on, it plays.
	_make_age(baby, config.infant_years)
	assert_true(Brain.score(session.activities.get_def(&"play"), baby, ctx) >= 0.0)


func test_close_kin_do_not_become_partners() -> void:
	var store := session.relationships
	# A grandmother, her two children, and a child of each: first cousins.
	var grandmother := session.spawn_person(session.start.settlement_tile, PersonData.LifeStage.ELDER)
	var mother := session.spawn_person(session.start.settlement_tile)
	var uncle := session.spawn_person(session.start.settlement_tile)
	var girl := session.spawn_person(session.start.settlement_tile)
	var boy := session.spawn_person(session.start.settlement_tile)
	var stranger := session.spawn_person(session.start.settlement_tile)
	mother.parents = PackedInt64Array([grandmother.id])
	uncle.parents = PackedInt64Array([grandmother.id])
	girl.parents = PackedInt64Array([mother.id])
	boy.parents = PackedInt64Array([uncle.id])
	assert_true(store.close_kin(girl.id, boy.id), "first cousins")
	assert_true(store.close_kin(girl.id, uncle.id), "niece and uncle")
	assert_true(store.close_kin(boy.id, grandmother.id), "grandchild")
	assert_true(store.close_kin(mother.id, uncle.id), "brother and sister")
	assert_false(store.close_kin(girl.id, stranger.id))
	# Dead, the grandmother still makes them kin.
	session.kill_person(grandmother.id, Lifecycle.CAUSE_OLD_AGE)
	assert_true(store.close_kin(girl.id, boy.id))
	# Cousins do not flirt, nor become partners.
	girl.sex = PersonData.Sex.FEMALE
	boy.sex = PersonData.Sex.MALE
	_make_age(girl, 20)
	_make_age(boy, 21)
	assert_false(SocialActs.may_flirt(girl, boy, ctx))
	store.modify(girl.id, boy.id, {"familiarity": 0.8, "affinity": 0.7, "romance": 0.9}, 0, session.clock.tick)
	_knob(config, &"partner_chance_per_day", 1.0)
	_day()
	assert_eq(girl.partner_id, 0)
