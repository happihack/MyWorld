extends TestCase
## M17.2: belief and religion — what a settlement as a whole holds leans how
## its people take things; a myth's places are sacred, someone speaks for it,
## a shrine is built for it; it travels with founders and loads; it splits.

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var session: WorldSession
var faith: MythSystem


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	faith = session.faith


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


func _believe(agent: StringName, share: float = 1.0) -> void:
	var members := session.settlement.members()
	for i in members.size():
		var beliefs := Interpretation.beliefs_of(members[i])
		beliefs.fill(0.0)
		if i < roundi(members.size() * share):
			beliefs[ReactionTable.INTERPRETATIONS.find(agent)] = 1.0
		members[i].beliefs = beliefs


## A myth of the first settlement about `subject`, taken as `agent`'s doing, with `believers`.
func _myth(subject: StringName, agent: StringName, believers: int, at: Vector2) -> Dictionary:
	var myth := {"id": 0, "settlement": session.settlement.id, "subject": String(subject), "agent": String(agent),
		"epithet": "EPITHET_" + String(subject).to_upper(), "sentiment": "benevolent", "believers": believers,
		"formed": session.clock.tick, "days": 6, "places": [at]}
	return session.culture.adopt(myth, session.settlement.id)


func test_what_a_settlement_holds_leans_how_its_people_take_things() -> void:
	var own := session.settlement
	_believe(ReactionTable.DEITY)
	session.cultures.each_day(session.clock.tick)
	var deity := ReactionTable.INTERPRETATIONS.find(ReactionTable.DEITY)
	assert_near(session.cultures.belief_share(own.id, deity), 1.0, 0.001, "all of them hold it")
	assert_eq(session.cultures.belief_share(own.id, ReactionTable.INTERPRETATIONS.find(ReactionTable.NATURAL)), 0.0)
	# A newcomer's first touch: the settlement's belief weighs in.
	var person: PersonData = own.members()[0]
	var stimulus := Stimulus.new()
	stimulus.type = Stimulus.TOUCH
	stimulus.target_id = person.id
	stimulus.intensity = 0.5
	var ctx := session.behavior.ctx
	var circumstances := Interpretation.features(person, stimulus, true, 1, ctx, Config.reactions)
	var with := Interpretation.scores(person, stimulus, circumstances, ctx, Config.reactions)
	_believe(ReactionTable.NATURAL)
	session.cultures.each_day(session.clock.tick + 1440)
	var without := Interpretation.scores(person, stimulus, circumstances, ctx, Config.reactions)
	assert_true(float(with[ReactionTable.DEITY]) - float(without[ReactionTable.DEITY]) > 0.1, "what they all hold leans it")


func test_a_myth_hallows_its_place_and_is_spoken_for() -> void:
	var own := session.settlement
	_believe(ReactionTable.DEITY)
	var at := own.fire().position2d() + Vector2(4.0, 1.0)
	var myth := _myth(Stimulus.RAIN_FROM_CLEAR_SKY, ReactionTable.DEITY, 6, at)
	faith.on_myth(myth)
	assert_true(session.world.has_flag(WorldCoords.world2d_to_tile(at), ChunkData.FLAG_SACRED), "where it showed itself is sacred")
	var founder := int(faith.founders[int(myth["id"])])
	assert_ne(founder, 0, "someone speaks for it")
	var told := session.events.of_type(&"faith_founded")
	assert_eq(told.size(), 1)
	assert_eq(told[0].participants[0], founder)
	assert_true(told[0].significance >= 0.7, "a founder is someone history keeps")
	# Enough believe: a shrine is wanted, at its sacred place.
	assert_true(own.planner.needs(session.clock.tick).has(&"shrine"))
	var site: Variant = own.planner.shrine_site()
	assert_not_null(site)
	assert_true(Vector2(site - WorldCoords.world2d_to_tile(at)).length() <= 2.5, "by the sacred place")
	# Saved.
	var again := MythSystem.new()
	again.from_dict(bytes_to_var(var_to_bytes(faith.to_dict())))
	assert_eq(again.founders, faith.founders)


func test_myth_split_merge() -> void:
	var own := session.settlement
	var people := own.member_count()
	_myth(Stimulus.TOUCH, ReactionTable.DEITY, ceili(people * 0.4), Vector2.ZERO)
	faith.look_for_schisms(session.clock.tick)
	assert_eq(session.events.of_type(&"schism").size(), 0, "one belief: no schism")
	_myth(Stimulus.TOUCH, ReactionTable.SPIRIT, ceili(people * 0.4), Vector2.ZERO)
	faith.look_for_schisms(session.clock.tick)
	var told := session.events.of_type(&"schism")
	assert_eq(told.size(), 1, "a god's doing, say some; a spirit's, say others")
	faith.look_for_schisms(session.clock.tick + 1440)
	assert_eq(session.events.of_type(&"schism").size(), 1, "told once")
	# A settlement founded from it takes its myths along; a load may carry one.
	var founded := Settlement.new()
	founded.id = 990
	session.settlements.add(founded)
	faith.on_founded(founded, {"from": own.id})
	assert_eq(faith.myths_of(founded.id).size(), 2)
	var other := Settlement.new()
	other.id = 991
	session.settlements.add(other)
	var loads := 0
	while faith.myths_of(other.id).is_empty() and loads < 400:
		loads += 1
		faith.on_traded({"from": own.id, "to": other.id, "units": loads})
	assert_false(faith.myths_of(other.id).is_empty(), "carried with the loads")
	assert_true(session.events.of_type(&"myth_spread").size() >= 1)
	session.settlements.remove(founded)
	session.settlements.remove(other)
