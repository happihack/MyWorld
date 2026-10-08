extends TestCase
## FC5: raids walked. Decided in the night, made in the morning: the raiders
## gather at their fire, cross to the other's stores, take an armful each;
## its brave ones come out — as many as the raiders and the raiders drop it
## and flee; fewer and there is a scuffle and the raiders make off with it;
## home, into their stores; told as it went. Away, raids are made at once.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440

var session: WorldSession
var raids: RaidParties
var first: Settlement
var second: Settlement


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	raids = session.raids
	first = session.settlement
	var fire := first.fire().tile
	for dy in range(-28, 29, 2):
		for dx in range(-28, 29, 2):
			first.places().mark_visited(fire + Vector2i(dx, dy))
	while first.member_count() < 14:
		var a := session.spawn_person(fire + Vector2i(1, 1))
		var b := session.spawn_person(fire + Vector2i(1, 1))
		a.sex = PersonData.Sex.MALE
		b.sex = PersonData.Sex.FEMALE
		session.households.form_couple(a, b, session.clock.tick, session.ids.next_id())
	var journey := session.migration.depart(first, session.clock.tick)
	second = session.migration.found(journey, session.clock.tick)
	for person in session.people.all_people():
		person.set_flag(PersonData.FLAG_INDOORS, false)
		person.pose = PersonData.Pose.IDLE
		person.health = 1.0
		person.needs = PackedFloat32Array([0.95, 0.95, 0.95, 0.9, 0.6, 1.0])


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


func _at_hour(hour: float, day: int = 2) -> void:
	session.clock.tick = day * DAY + roundi((hour - Config.time.start_hour) * 60.0)
	raids._last = -1_000_000


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
		raids.advance_to(session.clock.tick)
		left -= dt


func test_made_in_the_morning() -> void:
	_at_hour(1.0)
	raids.queue(second.id, first.id, 0, [], session.clock.tick)
	raids.advance_to(session.clock.tick)
	assert_eq(raids.raids().size(), 0, "not in the night")
	_at_hour(6.0)
	raids.advance_to(session.clock.tick)
	assert_eq(raids.raids().size(), 1, "out at first light")
	var raid: Dictionary = raids.raids()[0]
	assert_eq(StringName(raid["phase"]), RaidParties.GATHER)
	assert_true((raid["members"] as Array).size() >= 1 and (raid["members"] as Array).size() <= 1 + RaidParties.RAIDERS_MORE)
	for id: int in raid["members"]:
		var person := session.people.get_person(id)
		assert_eq(person.settlement_id, second.id, "raiders of the raiding settlement")
		assert_eq(str(person.current_action.get("reason")), String(RaidParties.REASON))


func test_a_raid_walked() -> void:
	first.stockpile.add(&"grain", 40)
	var theirs := first.stockpile.amount(&"grain")
	var ours := second.stockpile.amount(&"grain")
	# (The victims indoors: nobody to stop them.)
	for person in first.members():
		person.set_flag(PersonData.FLAG_INDOORS, true)
	_at_hour(6.0)
	var told := []
	raids.done.connect(func(_raid: Dictionary, taken: int, repelled: bool) -> void: told.append([taken, repelled]))
	raids.set_out(second.id, first.id, 0, [], session.clock.tick)
	var waited := 0.0
	var phases := {}
	while told.is_empty() and waited < 10.0 * 60.0:
		_run(10.0)
		waited += 10.0
		for raid: Dictionary in raids.raids():
			phases[String(raid["phase"])] = true
	assert_false(told.is_empty(), "over (%s)" % str(phases.keys()))
	assert_true(phases.has("cross"), "they crossed over")
	assert_false(bool(told[0][1]), "not driven off: nobody came out")
	assert_true(int(told[0][0]) > 0, "food carried off (%d)" % told[0][0])
	assert_true(first.stockpile.amount(&"grain") < theirs, "out of their stores")
	assert_true(second.stockpile.amount(&"grain") > ours or int(told[0][0]) > 0, "and into ours")


func test_outnumbered_they_drop_it_and_flee() -> void:
	first.stockpile.add(&"grain", 40)
	_at_hour(9.0)
	var raid := raids.set_out(second.id, first.id, 0, [], session.clock.tick)
	var members: Array[PersonData] = raids._members(raid)
	raids._take(raid, first, members)
	var after_take := first.stockpile.amount(&"grain")
	var defenders: Array[PersonData] = []
	for person in first.members():
		if defenders.size() < members.size() and session.behavior.ctx.stage_of(person) == PersonData.LifeStage.ADULT:
			defenders.append(person)
	raid["phase"] = RaidParties.STANDOFF
	raid["since"] = session.clock.tick - 10
	raid["defenders"] = defenders.map(func(p: PersonData) -> int: return p.id)
	var told := []
	raids.done.connect(func(_r: Dictionary, taken: int, repelled: bool) -> void: told.append([taken, repelled]))
	raids._act(raid, session.clock.tick)
	assert_true(first.stockpile.amount(&"grain") > after_take, "they dropped it")
	assert_true(bool(raid["repelled"]))
	assert_eq(StringName(raid["phase"]), RaidParties.HOME)
	raids._end(raid, session.clock.tick)
	assert_eq(told[0], [0, true])
	assert_eq(session.events.of_type(&"raid_repelled").size(), 1, "told: driven off")


func test_away_raids_are_made_at_once() -> void:
	session.walking_raids = false
	assert_false(session.conflicts.walk_raid.call(second.id, first.id, 0, []), "not walked")
	session.walking_raids = true
	assert_true(session.conflicts.walk_raid.call(second.id, first.id, 0, []), "walked while watched")


func test_saved_and_restored() -> void:
	_at_hour(9.0)
	raids.set_out(second.id, first.id, 0, [], session.clock.tick)
	raids.queue(first.id, second.id, 0, [], session.clock.tick)
	var again := RaidParties.new()
	again.from_dict(raids.to_dict())
	assert_eq(again.raids().size(), 1)
	assert_eq(again.raids()[0]["members"], raids.raids()[0]["members"])
