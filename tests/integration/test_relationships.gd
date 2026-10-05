extends TestCase
## What people are to each other (M10.1, bible §16.1): the store, how it
## changes, what comes of people being together, whom they seek out, and
## saving — including what is broken in a save.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const V19_FIXTURE := "res://tests/fixtures/saves/v19_world.sav"
const V19_ID := "w1790983054_93e3083e"
const DAY := 1440

var session: WorldSession
var store: RelationshipStore
var ctx: AiContext
var config: RelationshipsConfig
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
	store = session.relationships
	ctx = session.behavior.ctx
	config = Config.relationships
	people = session.people.all_people()


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


## Two grown-ups of different households (who are not family).
func _strangers() -> Array[PersonData]:
	for a in people:
		for b in people:
			if a.id < b.id and not store.is_family(a.id, b.id) and a.household_id != b.household_id \
					and ctx.stage_of(a) == PersonData.LifeStage.ADULT and ctx.stage_of(b) == PersonData.LifeStage.ADULT:
				return [a, b]
	return []


## A parent and their child.
func _parent_and_child() -> Array[PersonData]:
	for child in people:
		if not child.parents.is_empty():
			var parent := session.people.get_person(child.parents[0])
			if parent != null:
				return [parent, child]
	return []


func test_relationship_creation() -> void:
	assert_eq(config.validate().size(), 0, str(config.validate()))
	assert_eq(Config.problems.size(), 0, str(Config.problems))
	var n := people.size()
	assert_true(n >= 6)
	# A new band: everyone knows everyone — family well and warmly, the others a little.
	assert_eq(store.size(), n * (n - 1) / 2)
	for a in people:
		assert_eq(store.count_for(a.id), n - 1)
		for b in people:
			if a.id == b.id:
				assert_null(store.between(a.id, b.id), "nobody has a relationship with themselves")
				continue
			var record := store.between(a.id, b.id)
			assert_not_null(record)
			assert_true(record == store.between(b.id, a.id), "one record for the pair")
			assert_true(record.has_kind(Relationship.Kind.ACQUAINTANCE))
			var close := store.is_family(a.id, b.id) or a.household_id == b.household_id
			assert_near(record.familiarity, config.family_familiarity if close else config.band_familiarity, 0.001)
			assert_near(record.affinity, config.family_affinity if close else 0.0, 0.001)
	# Family ties come from the people themselves, seen from either side.
	var pair := _parent_and_child()
	assert_eq(pair.size(), 2)
	var parent: PersonData = pair[0]
	var child: PersonData = pair[1]
	assert_true(store.kinds(child.id, parent.id) & Relationship.Kind.PARENT != 0, "to the child, a parent")
	assert_true(store.kinds(parent.id, child.id) & Relationship.Kind.CHILD != 0, "to the parent, a child")
	if parent.partner_id != 0:
		assert_true(store.kinds(parent.id, parent.partner_id) & Relationship.Kind.PARTNER != 0)
		assert_true(store.kinds(parent.partner_id, parent.id) & Relationship.Kind.PARTNER != 0)
	for other in people:
		if other.id != child.id and not other.parents.is_empty() and other.parents[0] == child.parents[0]:
			assert_true(store.kinds(child.id, other.id) & Relationship.Kind.SIBLING != 0)
	var strangers := _strangers()
	assert_eq(store.family(strangers[0].id, strangers[1].id), 0)
	# What is there, and who.
	assert_eq(store.of(parent.id).size(), n - 1)
	assert_true(store.ensure(parent.id, child.id) == store.between(parent.id, child.id))
	assert_null(store.ensure(parent.id, parent.id))
	assert_null(store.ensure(parent.id, 0))
	assert_true(store.debug_text().begins_with("relationships: "))


func test_relationship_changes() -> void:
	var pair := _strangers()
	var a: PersonData = pair[0]
	var b: PersonData = pair[1]
	var changes: Array = []
	store.kind_changed.connect(func(x: int, y: int, kind: int, gained: bool) -> void: changes.append([x, y, kind, gained]))
	var events := session.events
	var now := session.clock.tick
	# Good things raise how they feel — each a little less, the warmer they are already.
	var first := store.modify(a.id, b.id, {"affinity": 0.2, "familiarity": 0.2}, 0, now)
	assert_near(first.affinity, 0.2, 0.0001)
	store.modify(a.id, b.id, {"affinity": 0.2}, 0, now)
	assert_near(first.affinity, 0.2 + 0.2 * 0.8, 0.0001)
	assert_eq(changes, [])
	# Friends.
	store.modify(a.id, b.id, {"affinity": 0.3}, 0, now)
	assert_true(first.affinity >= config.friend_from)
	assert_true(first.has_kind(Relationship.Kind.FRIEND))
	assert_eq(changes, [[mini(a.id, b.id), maxi(a.id, b.id), Relationship.Kind.FRIEND, true]])
	var friends := events.latest(Chronicler.TYPE_FRIENDS)
	assert_not_null(friends)
	assert_true(friends.involves(a.id) and friends.involves(b.id))
	var names := [session.people.get_person(friends.participants[0]).given_name, session.people.get_person(friends.participants[1]).given_name]
	assert_eq(EventText.text(friends, session.people, events), "%s and %s have become friends" % names)
	assert_true(first.history.has(friends.id), "the moment is on their record")
	assert_eq(store.with_kind(a.id, Relationship.Kind.FRIEND), [b.id])
	# A little cooler is still friends; much cooler is not (with some give either way).
	first.affinity = (config.friend_from + config.friend_until) * 0.5
	store.modify(a.id, b.id, {}, 0, now)
	assert_true(first.has_kind(Relationship.Kind.FRIEND))
	first.affinity = config.friend_until - 0.01
	store.modify(a.id, b.id, {}, 0, now)
	assert_false(first.has_kind(Relationship.Kind.FRIEND))
	# Bad things: rivals, enemies — and back.
	changes.clear()
	store.modify(a.id, b.id, {"affinity": -0.7}, 0, now)
	assert_true(first.has_kind(Relationship.Kind.RIVAL), "%.2f" % first.affinity)
	var fell_out := events.latest(Chronicler.TYPE_FELL_OUT)
	assert_not_null(fell_out)
	assert_eq(EventText.text(fell_out, session.people, events), "%s and %s have fallen out" % names)
	store.modify(a.id, b.id, {"affinity": -0.6}, 0, now)
	assert_true(first.has_kind(Relationship.Kind.ENEMY), "%.2f" % first.affinity)
	assert_not_null(events.latest(Chronicler.TYPE_ENEMIES))
	assert_true(store.with_kind(b.id, Relationship.Kind.RIVAL).has(a.id))
	# Reconciliation: the rivalry over, and that is told — because they had fallen out.
	first.affinity = config.rival_until + 0.05
	store.modify(a.id, b.id, {}, 0, now)
	assert_false(first.has_kind(Relationship.Kind.RIVAL) or first.has_kind(Relationship.Kind.ENEMY))
	var made_up := events.latest(Chronicler.TYPE_RECONCILED)
	assert_not_null(made_up)
	assert_eq(Array(made_up.causes), [fell_out.id])
	assert_eq(EventText.text(made_up, session.people, events), "%s and %s have made it up again" % names)
	assert_true(first.history.size() <= Relationship.HISTORY)
	# Values stay within their scales.
	store.modify(a.id, b.id, {"affinity": 5.0, "trust": -9.0, "familiarity": 3.0, "romance": 4.0, "respect": 2.0}, 0, now)
	assert_true(first.affinity <= 1.0 and first.trust >= -1.0 and first.familiarity <= 1.0 and first.romance <= 1.0 and first.respect <= 1.0)
	# Time: feelings cool back, strangers grow strange again, nothing left is forgotten — family never.
	store.settle(now)
	first.affinity = 0.8
	first.familiarity = 0.3
	first.last_tick = now
	var parent: PersonData = _parent_and_child()[0]
	var child: PersonData = _parent_and_child()[1]
	var kin := store.between(parent.id, child.id)
	kin.affinity = -0.5
	kin.familiarity = 0.05
	kin.last_tick = now - 100 * DAY
	store.settle(now + 10 * DAY)
	assert_true(first.affinity < 0.8 and first.affinity > 0.4, "cooler (%.2f)" % first.affinity)
	assert_near(first.familiarity, 0.3 - config.familiarity_fade_per_day * 10.0, 0.0001, "ten days without meeting: strangers a little again")
	assert_true(kin.affinity > -0.5, "family warms again (%.2f)" % kin.affinity)
	store.settle(now + 40 * DAY)
	assert_true(first.familiarity < 0.3)
	store.settle(now + 300 * DAY)
	store.settle(now + 600 * DAY)
	store.settle(now + 900 * DAY)
	assert_null(store.between(a.id, b.id), "nothing left between them: forgotten")
	assert_not_null(store.between(parent.id, child.id), "family is never forgotten")
	assert_true(store.between(parent.id, child.id).affinity > 0.2, "and it warms back towards where it began")


func test_nobody_keeps_too_many() -> void:
	_knob(config, &"most_per_person", 3)
	var pair := _parent_and_child()
	var parent: PersonData = pair[0]
	store.clear()
	var now := session.clock.tick
	var others: Array[PersonData] = []
	for other in people:
		if other.id != parent.id:
			others.append(other)
	# The family first, then the rest — the weakest of them are forgotten.
	for other in others:
		store.modify(parent.id, other.id, {"familiarity": 0.1 * (1 + others.find(other)), "affinity": 0.0}, 0, now)
	var kept := store.of(parent.id)
	var family := 0
	for other in others:
		if store.is_family(parent.id, other.id):
			family += 1
			assert_true(kept.has(other.id), "family is kept")
	assert_eq(kept.size(), maxi(3, family))
	if family < 3:
		var strongest: PersonData = null
		for other in others:
			if not store.is_family(parent.id, other.id):
				strongest = other
		assert_true(kept.has(strongest.id), "the strongest of the rest is kept")


func test_malformed_relationship_repair() -> void:
	var a: PersonData = people[0]
	var b: PersonData = people[1]
	var c: PersonData = people[2]
	var good := {"a": a.id, "b": b.id, "familiarity": 0.5, "affinity": 0.6, "trust": 0.1, "respect": 0.0, "romance": 0.0,
		"kinds": Relationship.Kind.FRIEND | Relationship.Kind.ACQUAINTANCE, "last": 5, "history": PackedInt64Array([3, 4])}
	var saved := {"day": 2, "pairs": [
		good,
		{"a": a.id, "b": b.id, "familiarity": 0.9}, # the same pair again
		{"a": c.id, "b": c.id, "familiarity": 0.9}, # with themselves
		{"a": c.id, "b": 999999, "familiarity": 0.9}, # someone who is not there
		{"a": "x", "b": c.id},
		{"a": a.id, "b": c.id, "affinity": NAN},
		{"a": a.id, "b": c.id, "affinity": "warm"},
		{"a": b.id, "b": c.id, "affinity": 7.0, "familiarity": -3.0, "kinds": Relationship.Kind.PARENT | Relationship.Kind.FRIEND},
		"rubbish",
		42,
	]}
	var skipped := store.from_dict(saved)
	assert_eq(skipped, 8)
	assert_eq(store.size(), 2)
	var kept := store.between(a.id, b.id)
	assert_near(kept.affinity, 0.6, 0.0001)
	assert_true(kept.has_kind(Relationship.Kind.FRIEND))
	assert_eq(kept.history, PackedInt64Array([3, 4]))
	var clamped := store.between(b.id, c.id)
	assert_near(clamped.affinity, 1.0, 0.0001, "clamped into its scale")
	assert_near(clamped.familiarity, 0.0, 0.0001)
	assert_eq(clamped.kinds & Relationship.Kind.PARENT, 0, "family ties are not kept on the record")
	# Not a dictionary at all, or no pairs: nothing, and no harm.
	assert_eq(store.from_dict({"pairs": "none"}), 0)
	assert_eq(store.size(), 0)
	# Someone gone: their pairs go with them.
	store.from_dict(saved)
	session.people.remove(c.id)
	assert_eq(store.drop_missing(session.people), 1)
	assert_eq(store.size(), 1)
	assert_eq(store.count_for(c.id), 0)


func test_what_comes_of_being_together() -> void:
	var pair := _strangers()
	var a: PersonData = pair[0]
	var b: PersonData = pair[1]
	# Compatibility: symmetric, within 0 … 1, highest for the same nature.
	assert_near(SocialActs.compatibility(a, b), SocialActs.compatibility(b, a), 0.0001)
	var twin := PersonData.new()
	twin.traits = a.traits.duplicate()
	assert_true(SocialActs.compatibility(a, twin) > SocialActs.compatibility(a, b) or SocialActs.compatibility(a, b) > 0.95)
	var opposite := PersonData.new()
	opposite.traits = a.traits.duplicate()
	for axis in SocialActs.KINDRED:
		opposite.traits[axis] = -signf(a.traits[axis]) if a.traits[axis] != 0.0 else 1.0
	assert_true(SocialActs.compatibility(a, opposite) < 0.5)
	# What may come of it, now.
	a.stress = 0.0
	b.pose = PersonData.Pose.IDLE
	a.food_in_hand = 0.0
	var plain := SocialActs.weights(a, b, ctx)
	assert_true(plain.has(SocialActs.CONVERSE))
	assert_false(plain.has(SocialActs.HELP), "nothing to help with")
	assert_false(plain.has(SocialActs.GIFT), "nothing to give")
	b.pose = PersonData.Pose.WORK
	assert_true(SocialActs.weights(a, b, ctx).has(SocialActs.HELP))
	store.modify(a.id, b.id, {"affinity": 0.4}, 0, session.clock.tick)
	a.food_in_hand = 1.0
	assert_true(SocialActs.weights(a, b, ctx).has(SocialActs.GIFT))
	# A quarrel: between those who do not suit each other, under strain.
	var unlike: float = SocialActs.weights(a, b, ctx).get(SocialActs.ARGUE, 0.0)
	store.modify(a.id, b.id, {"affinity": -1.0}, 0, session.clock.tick)
	a.stress = 0.9
	assert_true(float(SocialActs.weights(a, b, ctx).get(SocialActs.ARGUE, 0.0)) > float(unlike))
	# Flirting: two grown-ups, both free, not of one family, not of one sex.
	assert_eq(SocialActs.may_flirt(a, b, ctx), a.partner_id == 0 and b.partner_id == 0 and a.sex != b.sex)
	var family := _parent_and_child()
	assert_false(SocialActs.may_flirt(family[0], family[1], ctx))
	# Doing it.
	var events := session.events
	var day_log := ctx.day_log
	var before := store.between(a.id, b.id).affinity
	var trust := store.between(a.id, b.id).trust
	b.pose = PersonData.Pose.WORK
	assert_eq(SocialActs.carry_out(ctx, a, b, SocialActs.HELP), SocialActs.HELP)
	assert_true(store.between(a.id, b.id).affinity > before and store.between(a.id, b.id).trust > trust)
	assert_eq(DayLogText.text(day_log.of(a.id)[-1], session.people), "lends %s a hand" % b.given_name)
	assert_eq(DayLogText.text(day_log.of(b.id)[-1], session.people), "is lent a hand by %s" % a.given_name)
	a.food_in_hand = 1.0
	b.food_in_hand = 0.0
	SocialActs.carry_out(ctx, a, b, SocialActs.GIFT)
	assert_near(a.food_in_hand, 1.0 - SocialActs.GIFT_FOOD, 0.0001)
	assert_near(b.food_in_hand, SocialActs.GIFT_FOOD, 0.0001, "the food changes hands")
	if a.occupation_id != &"":
		var skill := float(b.skills.get(String(a.occupation_id), 0.0))
		SocialActs.carry_out(ctx, a, b, SocialActs.TEACH)
		assert_near(float(b.skills.get(String(a.occupation_id), 0.0)), skill + config.teach_skill, 0.0001)
	# A quarrel lowers it and puts them under strain; between those who already dislike each other it may come to blows.
	var stress := b.stress
	before = store.between(a.id, b.id).affinity
	_knob(config, &"fight_chance", 0.0)
	SocialActs.carry_out(ctx, a, b, SocialActs.ARGUE)
	assert_true(store.between(a.id, b.id).affinity < before)
	assert_true(b.stress > stress)
	assert_eq(DayLogText.text(day_log.of(a.id)[-1], session.people), "quarrels with %s" % b.given_name)
	_knob(config, &"fight_chance", 1.0)
	a.traits[Traits.Axis.AGGRESSION] = 0.9
	store.between(a.id, b.id).affinity = -0.6
	var health := a.health
	assert_eq(SocialActs.carry_out(ctx, a, b, SocialActs.ARGUE), SocialActs.FIGHT)
	assert_true(a.health < health, "a fight hurts")
	assert_eq(str(a.injuries[-1]["kind"]), "fight")
	assert_near(float(a.injuries[-1]["severity"]), Config.life.fight_injury * (1.5 - SocialActs.compatibility(a, b)), 0.0001)
	assert_eq(ctx.social_events[-1], [SocialActs.FIGHT, a.id, b.id])
	session.behavior.announce()
	var fight := events.latest(Chronicler.TYPE_FIGHT)
	assert_not_null(fight)
	assert_true(fight.involves(a.id) and fight.involves(b.id))
	assert_true(store.between(a.id, b.id).history.has(fight.id))
	assert_true(EventText.text(fight, session.people, events).contains("come to blows"))
	assert_eq(DayLogText.text(day_log.of(b.id)[-1], session.people), "comes to blows with %s" % a.given_name)
	# A talk: closer for those who suit each other, a little further apart for those who do not.
	var fit := SocialActs.compatibility(a, b)
	before = store.between(a.id, b.id).affinity
	SocialActs.carry_out(ctx, a, b, SocialActs.CONVERSE)
	var after := store.between(a.id, b.id).affinity
	assert_true((after - before) * (fit - config.talk_suits_from) >= 0.0, "fit %.2f: %.3f -> %.3f" % [fit, before, after])
	# Every act has its words in the day.
	for act: StringName in SocialActs.ALL:
		if act != SocialActs.CONVERSE:
			assert_true(DayLogText.has("DAY_SOCIAL_" + String(act).to_upper()))
			assert_true(DayLogText.has("DAY_SOCIAL_" + String(act).to_upper() + "_BY"))
	assert_true(store.acts.get(SocialActs.HELP, 0) >= 1)


func test_children_are_not_drawn_into_quarrels() -> void:
	var pair := _parent_and_child()
	var grown := pair[0]
	var young := pair[1]
	var year := Config.time.ticks_per_year()
	var now := session.clock.tick
	young.birth_tick = now - 6 * year
	ctx.forget(young.id) # (its stage is worked out anew)
	assert_eq(ctx.stage_of(young), PersonData.LifeStage.CHILD)
	# However badly they get on, no quarrel with a child …
	store.modify(grown.id, young.id, {"affinity": -1.0}, 0, now)
	grown.stress = 1.0
	grown.traits[Traits.Axis.AGGRESSION] = 1.0
	assert_false(SocialActs.weights(grown, young, ctx).has(SocialActs.ARGUE))
	assert_false(SocialActs.weights(young, grown, ctx).has(SocialActs.ARGUE))
	# … nor a fight, whatever asks for one: a talk.
	_knob(config, &"fight_chance", 1.0)
	var health := young.health
	assert_eq(SocialActs.carry_out(ctx, grown, young, SocialActs.ARGUE), SocialActs.CONVERSE)
	assert_eq(SocialActs.carry_out(ctx, grown, young, SocialActs.FIGHT), SocialActs.CONVERSE)
	assert_eq(young.health, health, "nobody hurts a child")
	# Talk never wears on what they are to each other.
	var before := store.between(grown.id, young.id).affinity
	SocialActs.carry_out(ctx, grown, young, SocialActs.CONVERSE)
	assert_true(store.between(grown.id, young.id).affinity >= before)
	# The young quarrel, but it stays words.
	young.birth_tick = now - 14 * year
	ctx.forget(young.id)
	assert_eq(ctx.stage_of(young), PersonData.LifeStage.ADOLESCENT)
	assert_true(SocialActs.weights(grown, young, ctx).has(SocialActs.ARGUE))
	assert_eq(SocialActs.carry_out(ctx, grown, young, SocialActs.ARGUE), SocialActs.ARGUE, "words, not blows")


func test_people_seek_out_those_they_like() -> void:
	var places := ctx.places
	var person := _strangers()[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for other in people:
		other.set_flag(PersonData.FLAG_INDOORS, false)
		other.pose = PersonData.Pose.IDLE
	# Everyone stands about them, as near as each other.
	var around: Array[PersonData] = []
	for other in people:
		if other.id != person.id and around.size() < 3:
			around.append(other)
	for i in around.size():
		session.people.move(around[i].id, person.position + Vector2i(i - 1, 2))
	var friend := around[0]
	var rival := around[1]
	var neutral := around[2]
	for other in around:
		store.between(person.id, other.id).affinity = 0.0
	store.modify(person.id, friend.id, {"affinity": 0.7, "familiarity": 0.5}, 0, session.clock.tick)
	store.between(person.id, rival.id).affinity = -0.5
	store.modify(person.id, rival.id, {}, 0, session.clock.tick)
	assert_true(store.kinds(person.id, rival.id) & Relationship.Kind.RIVAL != 0)
	var chosen := {}
	for n in 300:
		var other := places.company(person, rng)
		chosen[other.id] = int(chosen.get(other.id, 0)) + 1
	assert_false(chosen.has(rival.id), "a rival is not sought out")
	assert_true(int(chosen.get(friend.id, 0)) > int(chosen.get(neutral.id, 0)) * 1.5, str(chosen))
	# With nobody else about, even a rival is company.
	for other in people:
		if other.id != person.id and other.id != rival.id:
			other.set_flag(PersonData.FLAG_INDOORS, true)
	assert_eq(places.company(person, rng), rival)
	# Friends count among those whose beliefs rub off.
	assert_true(Interpretation._close_ones(person, ctx).has(friend))


func test_in_the_running_world_people_get_to_know_each_other() -> void:
	var before := {}
	for a in people:
		for b in people:
			if a.id < b.id:
				before[[a.id, b.id]] = store.between(a.id, b.id).familiarity
	session.behavior.enabled = true
	for minute in 2 * DAY:
		session.clock.tick += 1
		session.behavior.step(1.0)
		session.pathfinder.serve(1_000_000)
		session.movement.step(1.0)
	assert_true(int(store.acts.get(SocialActs.CONVERSE, 0)) >= 3, str(store.acts))
	var closer := 0
	for key: Array in before:
		if store.between(key[0], key[1]).familiarity > float(before[key]) + 0.01:
			closer += 1
	assert_true(closer >= 2, "%d pairs know each other better" % closer)


func test_relationships_are_saved() -> void:
	var pair := _strangers()
	store.modify(pair[0].id, pair[1].id, {"affinity": 0.8, "familiarity": 0.6, "romance": 0.3, "respect": 0.2}, 77, session.clock.tick)
	assert_true(store.between(pair[0].id, pair[1].id).has_kind(Relationship.Kind.FRIEND))
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	assert_true(loaded.ok, loaded.error)
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(loaded.world))
	again.set_process(false)
	assert_eq(again.relationships.size(), store.size())
	assert_eq(again.relationships.to_dict(), store.to_dict())
	var kept := again.relationships.between(pair[0].id, pair[1].id)
	assert_true(kept.has_kind(Relationship.Kind.FRIEND))
	assert_eq(kept.history, store.between(pair[0].id, pair[1].id).history)
	assert_true(kept.history.has(77), "the moments they shared (and their becoming friends)")
	assert_true(again.behavior.ctx.relationships == again.relationships)
	assert_true(again.behavior.ctx.places.relationships == again.relationships)
	again.queue_free()


func test_version_19_save_gets_its_relationships() -> void:
	var dir := SaveManager.world_dir(V19_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V19_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 19)
	var loaded := SaveManager.load_world(V19_ID)
	assert_true(loaded.ok, loaded.error)
	assert_eq(loaded.world["world_state"]["relationships"], {})
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	var n := s.people.size()
	assert_eq(n, 8)
	assert_eq(s.relationships.size(), n * (n - 1) / 2, "given what a new band has")
	# Saved again: the current version, the old file kept.
	assert_true(SaveManager.save_world(s, &"test"))
	assert_true(SaveManager.SAVE_VERSION >= 20)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav.bak1")).header["save_version"], 19)
	s.queue_free()
	# The step itself.
	assert_eq(SaveMigrations._v19_to_v20({"world": {"world_state": {}}})["world"]["world_state"], {})
	assert_eq(SaveMigrations._v19_to_v20({"world": {"world_state": {"people": {}}}})["world"]["world_state"]["relationships"], {})
	var kept: Dictionary = SaveMigrations._v19_to_v20({"world": {"world_state": {"relationships": {"day": 3}}}})
	assert_eq(kept["world"]["world_state"]["relationships"], {"day": 3})
