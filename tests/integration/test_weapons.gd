extends TestCase
## PR6: weapons as made things (the owner, 2026-10-08: W1 made things, W2 they
## count in war, W3 bows now, W4 metals wait for ore). The toolmaker makes
## spears — and once Archery is known, bows of wood and hide — when no tools
## are wanted; hunters and parties take the best in store; the better armed
## hunt better, are hurt less, and lose fewer in battle.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440

var session: WorldSession
var own: Settlement
var _knobs: Array = []


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	own = session.settlement
	for person in own.members():
		person.health = 1.0
		person.needs = PackedFloat32Array([0.95, 0.95, 0.95, 0.9, 0.6, 1.0])


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


func _grown() -> Array[PersonData]:
	var out: Array[PersonData] = []
	for person in own.members():
		if session.behavior.ctx.stage_of(person) == PersonData.LifeStage.ADULT:
			out.append(person)
	return out


## Tools enough in store: the toolmaker turns to weapons.
func _tools_enough() -> void:
	while own.tools_wanted():
		own.stockpile.add(&"tools", 1)


func test_made_at_the_workshop() -> void:
	assert_eq(Weapons.wanted(own, Weapons.SPEARS), 0, "not before toolmaking")
	own.learn(&"toolmaking", 0, session.clock.tick)
	_grown()[0].occupation_id = &"hunter"
	_tools_enough()
	own.stockpile.add(&"wood", 10)
	own.stockpile.add(&"stone", 10)
	assert_eq(Weapons.wanted(own, Weapons.SPEARS), own.hunter_count() + Weapons.PARTY_PLACES, "one for each hunter, and a party's")
	assert_eq(Weapons.wanted(own, Weapons.BOWS), 0, "no bows before archery")
	assert_true(own.craft_wanted())
	assert_eq(own.next_craft(), Weapons.SPEARS)
	var wood := own.stockpile.amount(&"wood")
	assert_true(own.craft(null))
	assert_eq(own.stockpile.amount(Weapons.SPEARS), 1, "a spear made")
	assert_eq(own.stockpile.amount(&"wood"), wood - 1, "of wood")
	# Tools first, while they are wanted.
	own.stockpile.take(&"tools", own.stockpile.amount(&"tools"))
	assert_eq(own.next_craft(), &"tools")
	_tools_enough()
	# Archery: bows, of wood and hide — none without hide.
	own.learn(&"archery", 0, session.clock.tick)
	assert_eq(Weapons.wanted(own, Weapons.BOWS), own.hunter_count() + Weapons.BOW_PARTY_PLACES)
	assert_eq(own.next_craft(), Weapons.SPEARS, "no hide: spears still")
	own.stockpile.add(&"hide", 3)
	assert_eq(own.next_craft(), Weapons.BOWS, "the bow first, with hide in store")
	assert_true(own.craft(null))
	assert_eq(own.stockpile.amount(Weapons.BOWS), 1)
	assert_eq(own.stockpile.amount(&"hide"), 2, "a hide used")
	# Enough of everything: nothing to make.
	own.stockpile.add(Weapons.BOWS, 10)
	own.stockpile.add(Weapons.SPEARS, 10)
	assert_false(own.craft_wanted(), "all armed")


func test_a_party_takes_them_and_brings_them_back() -> void:
	own.stockpile.add(Weapons.SPEARS, 1)
	own.stockpile.add(Weapons.BOWS, 1)
	var parties := session.parties
	var group := 0
	var fire := own.fire().tile
	var near := session.pathfinder.standable_near(fire + Vector2i(12, 0), 1, 3)
	var beasts := session.fauna.bring(&"wolf", Vector2(near[0]) + Vector2(0.5, 0.5), session.clock.tick)
	group = beasts[0].group
	var party := parties.form(group, own.id, &"wolf", session.clock.tick)
	assert_false(party.is_empty(), "a party")
	var members: Array = party["members"]
	assert_eq(HuntingParties.weapon_of(party, int(members[0])), Weapons.BOWS, "the leader has the best")
	assert_eq(HuntingParties.weapon_of(party, int(members[1])), Weapons.SPEARS)
	if members.size() > 2:
		assert_eq(HuntingParties.weapon_of(party, int(members[2])), Weapons.NONE, "the rest a stick of their own")
	assert_eq(own.stockpile.amount(Weapons.SPEARS) + own.stockpile.amount(Weapons.BOWS), 0, "taken out of the stores")
	assert_eq(session.people.get_person(int(members[0])).armed, &"bow", "drawn with a bow")
	assert_eq(session.people.get_person(int(members[1])).armed, &"spear")
	parties._go_home(party, session.clock.tick, HuntingParties.DARK)
	assert_eq(own.stockpile.amount(Weapons.SPEARS) + own.stockpile.amount(Weapons.BOWS), 2, "back in the stores")
	assert_eq(session.people.get_person(int(members[0])).armed, &"", "put away")


func test_the_better_armed_fight_better() -> void:
	var parties := session.parties
	parties.kill = Callable() # (nobody dies of it here)
	var taken := {}
	var wounds := {}
	var hurt := [0.0]
	parties.wounded.connect(func(_id: int, _species: StringName, severity: float, _own: int) -> void: hurt[0] += severity)
	for kind: StringName in [Weapons.NONE, Weapons.SPEARS, Weapons.BOWS]:
		parties.rng.seed = 7
		var strength := 0.0
		hurt[0] = 0.0
		var grown := _grown()
		for round in 300:
			var party := {"species": "bear", "strength": 1000.0, "full": 1000.0, "killed": 0, "pack": 1, "group": -1,
				"members": [grown[0].id, grown[1].id], "leader": grown[0].id, "hurt": [], "phase": HuntingParties.FIGHT,
				"settlement": own.id, "meat": 0, "hides": 0, "arms": {str(grown[0].id): String(kind), str(grown[1].id): String(kind)}}
			var bear := AnimalData.new()
			bear.species = &"bear"
			bear.position = grown[0].world2d()
			var members: Array[PersonData] = [grown[0], grown[1]]
			parties._round(party, [bear] as Array[AnimalData], members, session.clock.tick, true)
			strength += 1000.0 - float(party["strength"])
		taken[kind] = strength
		wounds[kind] = hurt[0]
	assert_true(taken[Weapons.SPEARS] > taken[Weapons.NONE], "spears strike harder than sticks (%s)" % str(taken))
	assert_true(taken[Weapons.BOWS] > taken[Weapons.NONE], "and bows (%s)" % str(taken))
	assert_true(wounds[Weapons.BOWS] < wounds[Weapons.NONE], "a bow keeps it furthest off (%s)" % str(wounds))


func test_hunters_take_the_best() -> void:
	var hunter := _grown()[0]
	var step := HuntStep.make(0)
	var hunt := HuntStep.new()
	hunt.begin(session.behavior.ctx, hunter, step)
	assert_eq(StringName(step["weapon"]), Weapons.NONE, "nothing in store: a stick")
	assert_eq(float(Weapons.stat(Weapons.NONE, "reach")), 2.6, "thrown from as near as ever")
	own.stockpile.add(Weapons.BOWS, 1)
	step = HuntStep.make(0)
	hunt.begin(session.behavior.ctx, hunter, step)
	assert_eq(StringName(step["weapon"]), Weapons.BOWS, "a bow from the stores")
	assert_eq(hunter.armed, &"bow")
	assert_true(float(Weapons.stat(Weapons.BOWS, "reach")) > float(Weapons.stat(Weapons.SPEARS, "reach")), "shot from further off")
	hunt.end(session.behavior.ctx, hunter, step)
	assert_eq(hunter.armed, &"")


func test_arms_count_in_war() -> void:
	var grown := _grown().size()
	assert_eq(Weapons.arms_of(own, grown), 0.0, "unarmed")
	own.stockpile.add(Weapons.BOWS, 1)
	own.stockpile.add(Weapons.SPEARS, 1)
	assert_near(Weapons.arms_of(own, grown), (1.0 + 0.7) / grown, 0.0001, "a bow and a spear among them")
	own.stockpile.add(Weapons.SPEARS, 100)
	assert_near(Weapons.arms_of(own, grown), (1.0 + 0.7 * (grown - 1)) / grown, 0.0001, "the best shared out first")
	# A battle wears them.
	var spears := own.stockpile.amount(Weapons.SPEARS)
	Weapons.worn_in_battle(own, 0.99)
	assert_true(own.stockpile.amount(Weapons.SPEARS) < spears, "some lost")


func test_better_armed_lose_fewer() -> void:
	# Two settlements at war: one armed, one not — over many battles, the
	# unarmed lose more.
	var fire := own.fire().tile
	for dy in range(-28, 29, 2):
		for dx in range(-28, 29, 2):
			own.places().mark_visited(fire + Vector2i(dx, dy))
	while own.member_count() < 14:
		var a := session.spawn_person(fire + Vector2i(1, 1))
		var b := session.spawn_person(fire + Vector2i(1, 1))
		a.sex = PersonData.Sex.MALE
		b.sex = PersonData.Sex.FEMALE
		session.households.form_couple(a, b, session.clock.tick, session.ids.next_id())
	var journey := session.migration.depart(own, session.clock.tick)
	var other := session.migration.found(journey, session.clock.tick)
	var conflicts := session.conflicts
	session.walking_raids = false # (the odds at once, as away: FC6 walks them)
	var record := conflicts.pair(own.id, other.id)
	var lost := {own.id: 0, other.id: 0}
	var alive := {}
	for person in session.people.all_people():
		alive[person.id] = person.settlement_id
	conflicts.kill = func(id: int, _cause: StringName, _causes: Array) -> void:
		lost[int(alive.get(id, 0))] = int(lost.get(int(alive.get(id, 0)), 0)) + 1
	for day in 400:
		own.stockpile.add(Weapons.BOWS, maxi(20 - own.stockpile.amount(Weapons.BOWS), 0))
		record["war"] = {"since": session.clock.tick, "fallen": 0, "event": 0}
		conflicts._day = day
		conflicts._wage(own, other, record, session.clock.tick)
	assert_true(int(lost[other.id]) > 0, "battles were fought (%s)" % str(lost))
	var per_own := float(lost[own.id]) / _adults(own)
	var per_other := float(lost[other.id]) / _adults(other)
	assert_true(per_own < per_other, "the armed lose fewer (%.3f against %.3f)" % [per_own, per_other])


func _adults(of: Settlement) -> int:
	var count := 0
	for person in of.members():
		if session.behavior.ctx.stage_of(person) == PersonData.LifeStage.ADULT:
			count += 1
	return maxi(count, 1)


func test_made_away() -> void:
	own.learn(&"toolmaking", 0, session.clock.tick)
	_grown()[0].occupation_id = &"hunter"
	var sim := OfflineSimulator.new(session)
	own.stockpile.add(&"wood", 10)
	own.stockpile.add(&"stone", 10)
	sim._craft(own, 1.0)
	assert_eq(own.stockpile.amount(Weapons.SPEARS), 0, "only where a workshop stands")
	# A workshop (as in test_trade).
	_knob(Config.trade, &"workshop_from", 1)
	_knob(Config.construction, &"homes_spare_least", -1000)
	_knob(Config.construction, &"storage_room_least", -1000)
	_knob(Config.construction, &"spoiled_from", 1_000_000)
	_knob(Config.construction, &"well_from", 1_000_000)
	var p := own.planner.plan(session.clock.tick)
	assert_eq(str(p.get("def", "")), "workshop")
	for resource: StringName in session.construction.still_needed(p):
		session.construction.deliver(p, resource, int(session.construction.still_needed(p)[resource]))
	while not session.construction.work(p, _grown()[1], 60.0, session.clock.tick):
		pass
	assert_not_null(own.workshop())
	_tools_enough()
	own.stockpile.add(&"wood", 10)
	own.stockpile.add(&"stone", 10)
	sim._craft(own, 1.0)
	assert_true(own.stockpile.amount(Weapons.SPEARS) > 0, "the toolmaker's day away")
