extends TestCase
## Death creates history (M10.3, bible §16.3): the dead are kept in the
## archive with what they did and remembered; they are laid in graves that
## can be read; those close to them grieve and visit the grave; and whatever
## names them still knows who they were.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440
const V21_FIXTURE := "res://tests/fixtures/saves/v21_world.sav"
const V21_ID := "w1790995606_d76b24a1"

var session: WorldSession
var life: Lifecycle
var config: LifeConfig
var ctx: AiContext
var events: EventLog
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
	for knob: StringName in [&"base_death_per_year", &"infant_death_per_year", &"old_age_death_per_year",
			&"accident_per_work_day", &"crowding_chance_per_day", &"partner_chance_per_day", &"conceive_chance_per_day",
			&"starve_chance_per_day", &"illness_death_per_day", &"injury_death_per_day", &"newcomer_chance_per_day"]:
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


func _couple() -> Array[PersonData]:
	for person in session.people.all_people():
		if person.sex == PersonData.Sex.FEMALE and person.partner_id != 0 and not person.children.is_empty():
			return [person, session.people.get_person(person.partner_id)]
	return []


func test_death_archives_person() -> void:
	var couple := _couple()
	var dying := couple[1]
	dying.significance = 0.4
	# Something they did that was told of, and something they remembered.
	var hunted := events.record(Chronicler.TYPE_HUNTED, {"participants": [dying.id], "species": "deer"})
	var memory := Memory.new()
	memory.subject = &"touch"
	memory.interpretation = &"spirit"
	memory.tick = session.clock.tick
	memory.importance = 0.9
	memory.emotions = PackedFloat32Array([0.0, 0.5, 0.0, 0.0, 0.0])
	session.memories.remember(dying, memory)
	var count := session.people.size()
	session.kill_person(dying.id, Lifecycle.CAUSE_OLD_AGE)
	assert_eq(session.people.size(), count - 1)
	var record := session.archive.get_record(dying.id)
	assert_not_null(record)
	assert_true(record.accomplishments.has(hunted.id), "what they did")
	assert_eq(record.memories.size(), 1, "what they remembered most")
	assert_eq(record.remembered()[0].subject, &"touch")
	assert_true(record.significance >= 0.4, "how much they mattered (%f)" % record.significance)
	# Their obituary matters as much as they did.
	var obituary := events.get_event(record.obituary_event)
	assert_not_null(obituary)
	assert_eq(obituary.type, Chronicler.TYPE_DIED)
	assert_near(obituary.significance, clampf(Chronicler.OBITUARY_BASE + Chronicler.OBITUARY_WEIGHT
		* minf(record.significance / Config.significance.important_from, 1.0), 0.0, 1.0), 0.0001)
	# The archive is saved as it is.
	var copy := HistoricalPerson.from_dict(record.to_dict())
	assert_eq(copy.to_dict(), record.to_dict())


func test_graves() -> void:
	var people := session.people.all_people()
	var fire := session.start.settlement_tile
	session.kill_person(people[0].id, Lifecycle.CAUSE_ILLNESS)
	var first := session.archive.get_record(people[0].id)
	assert_ne(first.grave_id, 0, "laid in a grave")
	var grave := session.props.get_prop(first.grave_id)
	assert_not_null(grave)
	assert_eq(grave.kind, PropData.Kind.GRAVE)
	assert_eq(grave.tile, first.grave_tile)
	var distance := maxi(absi(grave.tile.x - fire.x), absi(grave.tile.y - fire.y))
	assert_true(distance >= Graves.NEAREST and distance <= Graves.FURTHEST, "a little way from the fire (%d)" % distance)
	assert_true(session.pathfinder.can_stand(grave.tile), "people can walk past a grave")
	assert_true(session.archive.buried_in(grave.id) == first)
	# The next one beside it, a tile apart.
	session.kill_person(people[1].id, Lifecycle.CAUSE_ILLNESS)
	var second := session.props.get_prop(session.archive.get_record(people[1].id).grave_id)
	assert_not_null(second)
	var apart := second.tile - grave.tile
	assert_true(apart.length() <= 3.0, "the burial ground (%s)" % apart)
	assert_true(absi(apart.x) + absi(apart.y) > 1, "not on the tile next to it")
	assert_eq(session.graves.all_graves().size(), 2)
	# A grave is read: long press offers Read and View family.
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = grave.id
	target.tile = grave.tile
	target.direct = true
	assert_eq(session.interactions.actions_for(target),
		[InteractionManager.ACTION_READ, InteractionManager.ACTION_VIEW_FAMILY, InteractionManager.ACTION_FOCUS] as Array[StringName])
	assert_eq(UIText.prop_name(PropData.Kind.GRAVE), "Grave")
	# Graves are kept with the world.
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	assert_true(loaded.ok, loaded.error)
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(loaded.world))
	again.set_process(false)
	var kept := again.props.get_prop(grave.id)
	assert_not_null(kept)
	assert_eq([kept.kind, kept.tile], [PropData.Kind.GRAVE, grave.tile])
	assert_eq(again.archive.buried_in(grave.id).id, people[0].id)
	again.queue_free()


func test_reading_a_grave() -> void:
	var couple := _couple()
	var mother := couple[0]
	var father := couple[1]
	session.kill_person(father.id, Lifecycle.CAUSE_INJURY)
	var record := session.archive.get_record(father.id)
	var said := GraveCard.facts(session, record)
	assert_eq(said["name"], father.full_name())
	assert_true(father.birth_tick < 0, "of the band: born before the world began")
	assert_eq(said["years"], "Born before the first year · died in Year %d" % HistoryText.year_of(record.death_tick))
	record.birth_tick = 5
	assert_eq(GraveCard.facts(session, record)["years"], "Year 1 – Year %d" % HistoryText.year_of(record.death_tick))
	record.birth_tick = father.birth_tick
	assert_eq((said["life"] as PackedStringArray)[0], "Died of their wounds, at %d" % record.age_years(Config.time.ticks_per_year()))
	var relations := {}
	for entry: Array in said["family"]:
		relations[entry[0]] = [entry[1], entry[3]]
	assert_eq(relations[mother.id], ["Partner", true], "his partner is named (and alive)")
	for child_id in father.children:
		assert_true(relations.has(child_id), "and his children")
	# The card itself.
	var card := UIRoot.GRAVE_CARD.instantiate() as GraveCard
	card.setup(session, father.id)
	add_child(card)
	await wait_frames(1)
	assert_eq(card.title_text(), father.full_name())
	assert_true(card.lines().has("Remembered for"))
	assert_true(card.lines().has("Family"))
	var chosen: Array = []
	card.person_chosen.connect(func(id: int) -> void: chosen.append(id))
	card.family_buttons()[0].pressed.emit()
	assert_eq(chosen.size(), 1)
	card.queue_free()
	# View family: the family first.
	var family := UIRoot.GRAVE_CARD.instantiate() as GraveCard
	family.setup(session, father.id, true)
	add_child(family)
	await wait_frames(1)
	assert_eq(family.lines()[0], "Family")
	family.queue_free()
	# The living's card names the dead among their family (whose grave can be read).
	var card_facts := PersonCard.facts(session, mother)
	var named := false
	for entry: Array in card_facts["family"]:
		if entry[0] == father.id:
			named = String(entry[2]).contains("died in year")
	assert_true(named, "the person card names him, and that he died")


func test_mourning() -> void:
	var couple := _couple()
	var mother := couple[0]
	var father := couple[1]
	var child := session.people.get_person(mother.children[0])
	var stranger: PersonData = null
	for person in session.people.all_people():
		if person.household_id != mother.household_id and not session.relationships.close_kin(person.id, mother.id) \
				and not session.relationships.is_family(person.id, mother.id):
			stranger = person
	session.relationships.between(stranger.id, mother.id).affinity = 0.0 if stranger != null else 0.0
	var mood := father.mood
	session.kill_person(mother.id, Lifecycle.CAUSE_ILLNESS)
	# Those closest grieve most.
	assert_near(life.grief_of(father, session.clock.tick), 1.0, 0.0001)
	assert_near(life.grief_of(child, session.clock.tick), 1.0, 0.0001)
	assert_eq(Lifecycle.grieving_for(father), mother.id)
	assert_true(father.mood < mood or mood <= 0.0)
	if stranger != null:
		assert_eq(life.grief_of(stranger, session.clock.tick), 0.0, "someone who was nothing to her does not")
	var lost := session.memories.about(father, &"death_of")
	assert_eq(lost.size(), 1)
	assert_eq(MemoryText.text(lost[0], session.people), "lost %s" % mother.given_name)
	assert_eq(DayLogText.text(session.day_log.of(father.id)[-1], session.people), "loses %s" % mother.given_name)
	assert_eq(DayLogText.text(session.day_log.of(child.id)[-1], session.people), "mourns %s" % mother.given_name)
	# Grief weighs on them when they next take stock.
	father.needs = Needs.full()
	session.behavior.think(father)
	assert_true(father.mood <= Needs.mood(father.needs) - config.grief_mood * 0.99, "grief lowers the mood")
	# They go to her grave.
	assert_false(ctx.places.grave_to_visit(father).is_empty())
	assert_eq(ctx.places.grave_to_visit(father)["of"], mother.id)
	var visit := session.activities.get_def(&"visit_grave")
	assert_not_null(visit)
	session.clock.tick += 9 * 60 # (the morning)
	var grieving := Brain.score(visit, father, ctx)
	var steps := Planner.plan(&"visit_grave", father, ctx)
	assert_eq(steps.size(), 2)
	assert_eq(steps[1]["type"], "rest")
	assert_true(bool(steps[1]["kneel"]))
	session.behavior.set_plan(father, &"visit_grave", &"routine", steps)
	assert_eq(DayLogText.text(session.day_log.of(father.id)[-1], session.people), "visits %s's grave" % mother.given_name)
	# It passes, in time.
	for n in int(config.grief_days) + 1:
		session.clock.tick += DAY
		life.advance_to(session.clock.tick)
	assert_eq(life.grief_of(father, session.clock.tick), 0.0)
	assert_eq(Lifecycle.grieving_for(father), 0, "over")
	assert_true(Brain.score(visit, father, ctx) < grieving, "the grave draws them less")
	assert_false(ctx.places.grave_to_visit(father).is_empty(), "but it is still there to go to")


func test_references_to_the_dead() -> void:
	var people := session.people.all_people()
	var a := people[0]
	var b := people[1]
	session.relationships.modify(a.id, b.id, {"affinity": 0.9, "familiarity": 0.9}, 0, session.clock.tick)
	var friends := events.latest(Chronicler.TYPE_FRIENDS)
	session.day_log.note(b.id, session.clock.tick, "socialize", "", a.id)
	var name := a.given_name
	session.kill_person(a.id)
	# The UI finds them in the archive …
	assert_true(EventText.text(friends, session.people, events).contains(name))
	var said := PackedStringArray()
	for entry: Array in session.day_log.of(b.id):
		said.append(DayLogText.text(entry, session.people))
	assert_true(said.has("talks to %s" % name), str(said))
	assert_eq(session.people.name_of(a.id), name)
	# … the simulation does not find them at all.
	assert_null(session.people.get_person(a.id))
	assert_false(session.people.has_person(a.id))
	assert_null(session.relationships.between(a.id, b.id))


func test_version_21_save_loads() -> void:
	# Written by M10.2 (8295cd8): Mutgith (16) has died — before there were graves.
	var dir := SaveManager.world_dir(V21_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V21_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 21)
	var loaded := SaveManager.load_world(V21_ID)
	assert_true(loaded.ok, loaded.error)
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	assert_eq(s.people.size(), 7)
	var record := s.archive.get_record(16)
	assert_not_null(record)
	assert_eq(record.given_name, "Mutgith")
	assert_eq(record.grave_id, 0, "died before there were graves")
	assert_eq(s.graves.all_graves().size(), 0)
	assert_eq(GraveCard.facts(s, record)["name"], record.full_name(), "still read")
	# The next to die is laid in the first grave.
	s.kill_person(s.people.all_people()[0].id, Lifecycle.CAUSE_OLD_AGE)
	assert_eq(s.graves.all_graves().size(), 1)
	assert_true(SaveManager.save_world(s, &"test"))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav.bak1")).header["save_version"], 21)
	s.queue_free()
	assert_true(SaveManager.SAVE_VERSION >= 22)
	var data := {"world": {"world_state": {"archive": {"people": [{"id": 4, "given_name": "Ama"}]}}}}
	assert_eq(SaveMigrations._v21_to_v22(data), data)
	var odd := HistoricalPerson.from_dict({"id": 4, "given_name": "Ama", "significance": 7.0, "memories": ["x", {}],
		"accomplishments": PackedInt64Array([3, -1])})
	assert_eq(odd.grave_id, 0, "an older record has no grave")
	assert_eq(odd.significance, 7.0, "points (M11.2), not a share")
	assert_eq(odd.memories.size(), 0, "broken memories are left out")
	assert_eq(odd.accomplishments, PackedInt64Array([3]))


func test_a_full_burial_ground_does_not_leave_the_dead_unburied() -> void:
	# Centuries of dead (300-year soaks: the ground filled up and the rest went unburied).
	var graves := session.graves
	var laid := 0
	var tiles := {}
	for n in 140:
		var tile: Variant = graves.site()
		if tile == null:
			break
		var grave := PropData.new()
		grave.id = session.ids.next_id()
		grave.kind = PropData.Kind.GRAVE
		grave.tile = tile
		assert_true(session.props.add(grave))
		assert_false(tiles.has(tile), "a grave of its own")
		tiles[tile] = true
		laid += 1
	assert_eq(laid, 140, "room for the dead of centuries (closer together, then a second ground)")
