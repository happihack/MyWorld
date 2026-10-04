extends TestCase
## Governance v0 (M12.5, bible §17.4): a leader emerges in each settlement —
## the one most looked to (respect, liking, years, founding, deeds, nature);
## succession when they die or leave, and a challenger only when clearly more
## looked to; what a leader brings: their people lean toward their beliefs,
## and their nature tilts the settlement's plans. All of it is history.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440
const V27_FIXTURE := "res://tests/fixtures/saves/v27_world.sav"
const V27_ID := "w1791060708_5c4cfcd3"

var session: WorldSession
var governance: Governance
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
	governance = session.governance


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


func _grown(own: Settlement) -> Array[PersonData]:
	var out: Array[PersonData] = []
	for person in own.members():
		if governance._can_lead(person):
			out.append(person)
	return out


func _day_passes() -> void:
	session.clock.tick += DAY
	governance.advance_to(session.clock.tick)


func test_leader_emergence() -> void:
	var first := session.settlement
	assert_eq(governance.leader_of(first.id), 0, "nobody yet")
	_day_passes()
	var leader_id := governance.leader_of(first.id)
	assert_ne(leader_id, 0, "someone has come to lead")
	var leader := session.people.get_person(leader_id)
	assert_true(governance._can_lead(leader), "someone grown")
	# The one most looked to.
	for person in _grown(first):
		assert_true(governance.standing(person, first) <= governance.standing(leader, first) + 0.0001,
			"%s is not more looked to than %s" % [person.given_name, leader.given_name])
	assert_eq(governance.leads(leader_id), first.id)
	var led := session.events.of_type(&"leadership")
	assert_eq(led.size(), 1)
	assert_eq(EventText.text(led[0], session.people, session.events), "%s has come to lead the first camp" % leader.given_name)
	# What makes one looked to: respect.
	var other: PersonData = null
	for person in _grown(first):
		if person.id != leader_id:
			other = person
			break
	var before := governance.standing(other, first)
	for person in first.members():
		if person.id != other.id:
			session.relationships.ensure(person.id, other.id).respect = 1.0
	assert_true(governance.standing(other, first) > before + 1.0, "respected, they are looked to")
	# … and clearly more than the leader: they take over.
	_day_passes()
	assert_eq(governance.leader_of(first.id), other.id)
	var taken := session.events.of_type(&"leadership")[-1]
	assert_eq(EventText.text(taken, session.people, session.events),
		"%s has taken over the lead of the first camp from %s" % [other.given_name, leader.given_name])
	# A small lead is not enough to take over.
	_knob(Config.governance, &"challenge_margin", 100.0)
	for person in first.members():
		if person.id != leader_id:
			session.relationships.ensure(person.id, leader_id).respect = 1.0
	_day_passes()
	assert_eq(governance.leader_of(first.id), other.id, "a leader is not easily replaced")


func test_succession_when_the_leader_dies() -> void:
	var first := session.settlement
	_day_passes()
	var leader_id := governance.leader_of(first.id)
	var leader_name := session.people.name_of(leader_id)
	session.kill_person(leader_id, Lifecycle.CAUSE_OLD_AGE)
	_day_passes()
	var next := governance.leader_of(first.id)
	assert_ne(next, 0)
	assert_ne(next, leader_id)
	var after := session.events.of_type(&"leadership")[-1]
	assert_eq(EventText.text(after, session.people, session.events),
		"After the death of %s, %s leads the first camp" % [leader_name, session.people.name_of(next)])
	assert_eq(after.causes.size(), 1, "because they died")
	assert_eq(governance.changes, {"first": 1, "died": 1})


func test_a_founder_is_looked_to() -> void:
	var first := session.settlement
	var person := _grown(first)[0]
	var plain := governance.standing(person, first)
	first.founders.append(person.id)
	assert_near(governance.standing(person, first), plain + Config.governance.founder_weight, 0.0001)


func test_a_leader_tilts_beliefs_and_plans() -> void:
	var first := session.settlement
	_day_passes()
	var leader := session.people.get_person(governance.leader_of(first.id))
	# Beliefs: the leader holds it is nature fully; their people lean that way.
	var natural := ReactionTable.INTERPRETATIONS.find(ReactionTable.NATURAL)
	var held := Interpretation.beliefs_of(leader)
	held[natural] = 0.0
	leader.beliefs = held
	_day_passes()
	var someone: PersonData = null
	for person in _grown(first):
		if person.id != leader.id:
			someone = person
			break
	var stimulus := Stimulus.new()
	stimulus.type = &"rain"
	var ctx := session.behavior.ctx
	var before: float = Interpretation.scores(someone, stimulus, {}, ctx, Config.reactions)[ReactionTable.NATURAL]
	held[natural] = 1.0
	leader.beliefs = held
	_day_passes()
	assert_near(governance.belief(first.id, natural), 1.0, 0.001)
	var after: float = Interpretation.scores(someone, stimulus, {}, ctx, Config.reactions)[ReactionTable.NATURAL]
	assert_near(after - before, Config.governance.belief_weight, 0.001, "they lean toward what their leader believes")
	# Plans: an ambitious leader wants homes with a place more to spare.
	var places := first.start_info().hut_ids.size() * Config.life.home_room
	_knob(Config.construction, &"homes_spare_least", places - first.member_count())
	var traits := leader.traits.duplicate()
	traits[Traits.Axis.AMBITION] = -1.0
	leader.traits = traits
	assert_false(first.planner.homes_short(), "places enough, for a leader with no ambition")
	traits[Traits.Axis.AMBITION] = 1.0
	leader.traits = traits
	assert_eq(first.leader_lean(Traits.Axis.AMBITION), 1.0)
	assert_true(first.planner.homes_short(), "an ambitious leader wants a place more to spare")
	# And a cautious one keeps more food back from trade, a generous one less.
	traits[Traits.Axis.CURIOSITY] = -1.0
	traits[Traits.Axis.GENEROSITY] = -1.0
	leader.traits = traits
	var cautious := session.trade._food_kept(first)
	traits[Traits.Axis.CURIOSITY] = 0.0
	traits[Traits.Axis.GENEROSITY] = 1.0
	leader.traits = traits
	var generous := session.trade._food_kept(first)
	assert_true(cautious > generous, "the cautious keep more back (%d > %d)" % [cautious, generous])


func test_a_small_band_has_no_leader() -> void:
	_knob(Config.governance, &"least_people", 100)
	_day_passes()
	assert_eq(governance.leader_of(session.settlement.id), 0)


func test_leaders_are_saved_and_shown() -> void:
	var first := session.settlement
	_day_passes()
	var leader_id := governance.leader_of(first.id)
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = first.start_info().campfire_id
	target.tile = first.start_info().settlement_tile
	assert_eq(session.interactions.inspect(target).leader_name, session.people.name_of(leader_id))
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	assert_true(loaded.ok, loaded.error)
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(loaded.world))
	again.set_process(false)
	assert_eq(again.governance.leader_of(first.id), leader_id)
	assert_eq(again.governance.changes, {"first": 1})
	again.queue_free()


func test_version_27_save_loads() -> void:
	# Written by M12.4 (6f30da6): before anyone led.
	var dir := SaveManager.world_dir(V27_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V27_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 27)
	var loaded := SaveManager.load_world(V27_ID)
	assert_true(loaded.ok, loaded.error)
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	assert_eq(s.governance.leader_of(s.settlement.id), 0, "nobody leads yet")
	s.clock.tick += DAY
	s.governance.advance_to(s.clock.tick)
	assert_ne(s.governance.leader_of(s.settlement.id), 0, "on its first day, someone does")
	assert_true(SaveManager.save_world(s, &"test"))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	s.queue_free()
	var data := {"world": {"world_state": {"people": []}}}
	assert_eq(SaveMigrations._v27_to_v28(data)["world"]["world_state"]["governance"], {})
