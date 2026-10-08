extends TestCase
## PR4: the hunting party. A beast seen by day: two to four of the able grown
## (hunters first; the timid may refuse) gather at the fire, track it, bring
## it to bay and fight it, round by round — killing it (its meat and hide
## home), losing it, or being driven off; home at dusk, out again next day.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440

var session: WorldSession
var parties: HuntingParties
var watch: PredatorWatch
var fauna: AnimalSystem
var own: Settlement


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	parties = session.parties
	watch = session.predators
	fauna = session.fauna
	own = session.settlement
	# (Strong enough to go: the band's grown all well.)
	for person in own.members():
		person.health = 1.0
		person.needs = PackedFloat32Array([0.95, 0.95, 0.95, 0.9, 0.6, 1.0])


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


func _at_hour(hour: float) -> void:
	session.clock.tick = Config.time.ticks_per_year() * 2 + 2 * DAY + roundi((hour - Config.time.start_hour) * 60.0)
	fauna.last_tick = session.clock.tick
	parties._last = -1_000_000
	watch._last = -1_000_000


func _run(minutes: float, step: float = 1.0) -> void:
	var left := minutes
	while left > 0.0001:
		var dt := minf(step, left)
		var seconds := dt * Config.time.real_seconds_per_game_minute
		while seconds > 0.000001:
			var piece := minf(seconds, Config.time.max_frame_delta_s)
			session.clock.advance(piece)
			seconds -= piece
		session.behavior.step(dt)
		session.pathfinder.serve(1_000_000)
		session.movement.step(dt)
		fauna.advance_to(session.clock.tick)
		watch.advance_to(session.clock.tick)
		parties.advance_to(session.clock.tick)
		left -= dt


## A beast `distance` tiles from the fire, on ground that can be walked to.
func _beast(kind: StringName, distance: float) -> Array[AnimalData]:
	var fire := own.fire().tile
	for way: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var near := session.pathfinder.standable_near(fire + way * roundi(distance), 1, 3)
		if not near.is_empty() and session.pathfinder.is_reachable(fire + Vector2i(1, 0), near[0]):
			return fauna.bring(kind, Vector2(near[0]) + Vector2(0.5, 0.5), session.clock.tick)
	return fauna.bring(kind, Vector2(fire) + Vector2(distance, 0.5), session.clock.tick)


func test_who_goes() -> void:
	_at_hour(9.0)
	var hunter: PersonData = null
	for person in own.members():
		if session.behavior.ctx.stage_of(person) == PersonData.LifeStage.ADULT and hunter == null:
			hunter = person
	hunter.occupation_id = &"hunter"
	var chosen := parties.choose(own, 4, session.clock.tick)
	assert_true(chosen.size() >= HuntingParties.PARTY_LEAST and chosen.size() <= 4, "%d go" % chosen.size())
	assert_eq(chosen[0], hunter, "the hunter leads")
	for person in chosen:
		assert_eq(session.behavior.ctx.stage_of(person), PersonData.LifeStage.ADULT, "only the grown")
	# Hurt or ill, they stay.
	hunter.health = 0.3
	assert_false(parties.choose(own, 4, session.clock.tick).has(hunter), "not the hurt")


func test_the_timid_may_refuse() -> void:
	_at_hour(9.0)
	var stayed := 0
	for person in own.members():
		person.occupation_id = &"forager"
		if person.traits.size() > Traits.Axis.BRAVERY:
			person.traits[Traits.Axis.BRAVERY] = -0.9
	for i in 20:
		stayed += 1 if parties.choose(own, 4, session.clock.tick).size() < mini(4, own.members().size()) else 0
	assert_true(stayed > 0, "some will not go")


func test_a_hunt() -> void:
	_at_hour(8.0)
	var boar := _beast(&"boar", 16.0)
	assert_false(boar.is_empty())
	# Seen: a party forms.
	var spotter: PersonData = null
	for person in own.members():
		if session.behavior.ctx.stage_of(person) == PersonData.LifeStage.ADULT:
			spotter = person
			break
	session.people.move(spotter.id, WorldCoords.world2d_to_tile(boar[0].position) + Vector2i(-4, 0))
	spotter.set_flag(PersonData.FLAG_INDOORS, false)
	var formed := []
	parties.formed.connect(func(party: Dictionary) -> void: formed.append(party))
	var ended := []
	parties.ended.connect(func(party: Dictionary, outcome: StringName, killed: int) -> void: ended.append([outcome, killed, party]))
	_run(30.0)
	assert_eq(formed.size(), 1, "a party gathers")
	var party: Dictionary = formed[0]
	assert_true((party["members"] as Array).size() >= 2 and (party["members"] as Array).size() <= 2, "two for a boar")
	for id: int in party["members"]:
		assert_eq(str(session.people.get_person(id).current_action.get("reason")), String(HuntingParties.REASON))
	var phases := {}
	var waited := 0.0
	while ended.is_empty() and waited < 10.0 * 60.0:
		_run(10.0)
		waited += 10.0
		phases[String(party["phase"])] = true
	assert_false(ended.is_empty(), "over by dusk (%s)" % str(phases.keys()))
	assert_true(phases.has("track") or phases.has("fight"), "they went after it: %s" % str(phases.keys()))
	var outcome: StringName = ended[0][0]
	assert_true(outcome in [HuntingParties.KILLED, HuntingParties.ESCAPED, HuntingParties.BEATEN, HuntingParties.DARK], str(outcome))
	if outcome == HuntingParties.KILLED:
		assert_eq(fauna.count(&"boar"), boar.size() - int(ended[0][1]))
		assert_true(own.stockpile.amount(&"hide") >= 1, "a hide")
		assert_eq(session.events.of_type(Chronicler.TYPE_PARTY_KILLED).size(), 1, "told")


func test_a_kill_brings_meat_and_hide() -> void:
	_at_hour(10.0)
	var bear: AnimalData = _beast(&"bear", 12.0)[0]
	var party := parties.form(bear.group, own.id, &"bear", session.clock.tick)
	assert_false(party.is_empty())
	party["phase"] = HuntingParties.FIGHT
	party["strength"] = 0.1
	var members := parties._members(party)
	for person in members:
		session.people.move(person.id, WorldCoords.world2d_to_tile(bear.position))
	var hides := own.stockpile.amount(&"hide")
	var meat := own.stockpile.amount(&"meat")
	var carried := 0
	parties._round(party, fauna.of_group(bear.group), members, session.clock.tick)
	if StringName(party["phase"]) != HuntingParties.BUTCHER:
		party["strength"] = 0.0
		parties._round(party, fauna.of_group(bear.group), members, session.clock.tick)
	assert_eq(StringName(party["phase"]), HuntingParties.BUTCHER, "down: butchered")
	assert_eq(fauna.count(&"bear"), 0)
	var def0 := session.species.get_def(&"bear")
	assert_eq(session.piles.total(&"meat", party["at"], 3.0), def0.meat, "its meat laid out where it fell")
	parties._go_home(party, session.clock.tick, HuntingParties.KILLED)
	assert_eq(session.piles.total(&"meat", party["at"], 3.0), 0, "taken up")
	var memory_of_it := false
	for person in members:
		for memory in session.memories.of(person):
			memory_of_it = memory_of_it or String(memory.subject) == "life_slew_bear"
	assert_true(memory_of_it, "remembered")
	for person in members:
		if person.carrying == &"meat":
			carried += person.carrying_amount
	var def := session.species.get_def(&"bear")
	assert_eq(carried + own.stockpile.amount(&"meat") - meat, def.meat, "all its meat: in arms or the stores")
	assert_eq(own.stockpile.amount(&"hide") - hides, def.hide, "and its hide")
	assert_eq(EventText.text(session.events.of_type(Chronicler.TYPE_PARTY_KILLED)[-1], session.people),
		"%s's hunting party has killed the bear" % session.people.get_person(int(party["leader"])).given_name)


func test_two_badly_hurt_and_they_break() -> void:
	_at_hour(10.0)
	var lion: AnimalData = _beast(&"lion", 12.0)[0]
	var party := parties.form(lion.group, own.id, &"lion", session.clock.tick)
	party["phase"] = HuntingParties.FIGHT
	var members := parties._members(party)
	for person in members:
		session.people.move(person.id, WorldCoords.world2d_to_tile(lion.position))
	party["hurt"] = [members[0].id, members[1].id]
	var ended := []
	parties.ended.connect(func(_p: Dictionary, outcome: StringName, _k: int) -> void: ended.append(outcome))
	party["strength"] = 1000.0
	parties._round(party, fauna.of_group(lion.group), members, session.clock.tick)
	assert_eq(ended, [HuntingParties.BEATEN], "driven off")
	assert_false(fauna.is_held(lion.group), "it is free again")
	assert_eq(EventText.text(session.events.of_type(Chronicler.TYPE_PARTY_BEATEN)[-1]), "The mountain lion has driven off the hunting party")


func test_a_pack_breaks() -> void:
	_at_hour(10.0)
	var pack := _beast(&"wolf", 14.0)
	while pack.size() < 4:
		pack = fauna.of_group(pack[0].group)
		if pack.size() < 4:
			pack.append(fauna.spawn(&"wolf", pack[0].position, pack[0].home, pack[0].group, session.clock.tick))
	var party := parties.form(pack[0].group, own.id, &"wolf", session.clock.tick)
	party["pack"] = 4
	party["full"] = 12.0
	party["strength"] = 12.0 - 6.0 # (two down's worth)
	party["phase"] = HuntingParties.FIGHT
	for person in parties._members(party):
		session.people.move(person.id, WorldCoords.world2d_to_tile(pack[0].position))
	for wolf in fauna.of_group(pack[0].group):
		fauna.registry.move(wolf.id, pack[0].position, 0.0)
	parties._round(party, fauna.of_group(pack[0].group), parties._members(party), session.clock.tick)
	assert_eq(int(party["killed"]) >= 2, true, "two down")
	assert_eq(fauna.count(&"wolf"), 0, "the rest have fled for good")
	assert_eq(StringName(party["phase"]), HuntingParties.BUTCHER)


func test_home_at_dusk_and_out_again_in_the_morning() -> void:
	_at_hour(15.0)
	var bear: AnimalData = _beast(&"bear", 20.0)[0]
	watch._seen(bear, own.members()[0], session.clock.tick)
	parties.advance_to(session.clock.tick)
	assert_eq(parties.parties().size(), 1, "out")
	var party: Dictionary = parties.parties()[0]
	party["phase"] = HuntingParties.TRACK
	fauna.hold(bear.group, session.clock.tick + 10 * DAY) # (it stays where it is)
	_at_hour(19.5)
	parties.advance_to(session.clock.tick)
	assert_eq(StringName(party["phase"]), HuntingParties.HOME, "home at dusk")
	assert_eq(str(party["outcome"]), String(HuntingParties.DARK))
	assert_eq(session.events.of_type(Chronicler.TYPE_PARTY_ESCAPED).size() + session.events.of_type(Chronicler.TYPE_PARTY_BEATEN).size(), 0,
		"(nothing to tell)")
	parties._parties.clear()
	session.clock.tick += DAY - roundi(13.0 * 60.0) # (next morning)
	parties._last = -1_000_000
	parties.advance_to(session.clock.tick)
	assert_eq(parties.parties().size(), 1, "out again")


func test_saved_and_restored() -> void:
	_at_hour(10.0)
	var bear: AnimalData = _beast(&"bear", 12.0)[0]
	var party := parties.form(bear.group, own.id, &"bear", session.clock.tick)
	party["phase"] = HuntingParties.FIGHT
	party["strength"] = 4.5
	var again := HuntingParties.new()
	again.from_dict(parties.to_dict())
	assert_eq(again.parties().size(), 1)
	var back: Dictionary = again.parties()[0]
	assert_eq(StringName(back["phase"]), HuntingParties.FIGHT)
	assert_near(float(back["strength"]), 4.5, 0.001)
	assert_eq(back["members"], party["members"])


func test_away_the_fight_is_lived_at_once() -> void:
	_at_hour(12.0)
	var bear: AnimalData = _beast(&"bear", 14.0)[0]
	var outcome := parties.resolve_away(bear.group, own.id, &"bear", session.clock.tick)
	assert_true(outcome in [HuntingParties.KILLED, HuntingParties.ESCAPED, HuntingParties.BEATEN], "it ended: %s" % outcome)
	assert_eq(parties.parties().size(), 0, "and nobody is still out")
	if outcome == HuntingParties.KILLED:
		assert_eq(fauna.count(&"bear"), 0)


func test_away_a_beast_is_seen_and_dealt_with() -> void:
	_at_hour(12.0)
	_beast(&"bear", 18.0)
	var offline := OfflineSimulator.new(session)
	offline.run(6 * DAY)
	assert_eq(session.events.of_type(Chronicler.TYPE_PREDATOR_SPOTTED).size(), 1, "seen while they were away")
	var told := session.events.of_type(Chronicler.TYPE_PARTY_KILLED).size() + session.events.of_type(Chronicler.TYPE_PARTY_ESCAPED).size() \
		+ session.events.of_type(Chronicler.TYPE_PARTY_BEATEN).size() + session.events.of_type(Chronicler.TYPE_PREDATOR_GONE).size()
	assert_true(told >= 1 or fauna.count(&"bear") == 1, "a party went after it (or it is still about)")
	assert_eq(parties.parties().size(), 0, "nobody left out there")
