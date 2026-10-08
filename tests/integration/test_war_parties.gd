extends TestCase
## FC6: war fought in the open. A battle decided on a day of war is fought the
## next morning: each side gathers at its fire, armed from its stores, marches
## to a meeting ground between the fires, faces the other and clashes; the
## fallen fall where they stand, are knelt by, and die of it (buried); the
## heroes are named; home. Away, as before: at once. Peace sets border stones.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440

var session: WorldSession
var wars: WarParties
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
	wars = session.wars
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
	wars._last = -1_000_000


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
		wars.advance_to(session.clock.tick)
		left -= dt


func _grown(of: Settlement) -> Array[PersonData]:
	var out: Array[PersonData] = []
	for person in of.members():
		if session.behavior.ctx.stage_of(person) == PersonData.LifeStage.ADULT:
			out.append(person)
	return out


func _at_war() -> Dictionary:
	var record := session.conflicts.pair(first.id, second.id)
	record["war"] = {"since": session.clock.tick, "fallen": 0, "event": 0}
	return record


func test_a_battle_fought_in_the_open() -> void:
	assert_not_null(wars.meeting_ground(first, second), "a meeting ground between them")
	_at_war()
	first.stockpile.add(Weapons.SPEARS, 2)
	var fallen := [_grown(first)[0].id]
	var hero := _grown(second)[0].id
	_at_hour(6.0)
	var told := []
	session.conflicts.battle.connect(func(a: int, b: int, down: Array, heroes: Array) -> void: told.append([a, b, down, heroes]))
	assert_true(session.conflicts.walk_battle.call(first.id, second.id, fallen, [hero]), "walked while watched")
	_at_hour(7.5)
	var waited := 0.0
	var phases := {}
	var battle: Dictionary = {}
	while told.is_empty() and waited < 9.0 * 60.0:
		_run(10.0)
		waited += 10.0
		for each: Dictionary in wars.battles():
			battle = each
			phases[String(each["phase"])] = true
	assert_false(told.is_empty(), "fought and told (%s)" % str(phases.keys()))
	for phase in ["gather", "march", "face", "clash", "tend"]:
		assert_true(phases.has(phase), "%s (%s)" % [phase, str(phases.keys())])
	assert_eq(told[0][2], fallen, "the fallen as the dice said")
	assert_eq(told[0][3], [hero], "the hero named")
	assert_false(session.people.has_person(int(fallen[0])), "they died of it")
	assert_eq(first.stockpile.amount(Weapons.SPEARS) + 1 >= 2, true, "the weapons back (but the fallen's)")
	var record := session.conflicts.pair(first.id, second.id)
	assert_false((record["war"] as Dictionary).has("pending"), "the war goes on")
	assert_eq(int(record["war"]["fallen"]), 1)


func test_the_sides() -> void:
	var fallen := [_grown(first)[-1].id]
	var side := wars._choose(first, fallen, [], session.clock.tick)
	assert_true(side.size() >= WarParties.SIDE_LEAST and side.size() <= WarParties.SIDE_MOST + 1, "%d go" % side.size())
	assert_true(side.any(func(p: PersonData) -> bool: return p.id == int(fallen[0])), "the fallen-to-be go")
	assert_true(side.size() < _grown(first).size() or _grown(first).size() <= WarParties.SIDE_LEAST, "never all")
	for person in side:
		assert_eq(session.behavior.ctx.stage_of(person), PersonData.LifeStage.ADULT, "only the grown")


func test_away_battles_are_at_once() -> void:
	session.walking_raids = false
	var record := _at_war()
	assert_false(session.conflicts.walk_battle.call(first.id, second.id, [], []), "not walked away")
	# A battle day, away: the fallen die at once.
	var told := []
	session.conflicts.battle.connect(func(_a: int, _b: int, down: Array, _heroes: Array) -> void: told.append(down))
	for day in 200:
		if not told.is_empty():
			break
		record["war"] = {"since": session.clock.tick, "fallen": 0, "event": 0}
		session.conflicts._day = day
		session.conflicts._wage(first, second, record, session.clock.tick)
	assert_false(told.is_empty(), "a battle in 200 days of war")
	assert_true(wars.battles().is_empty(), "none walked")


func test_no_ground_fought_at_once() -> void:
	var told := []
	wars.ended.connect(func(_a: int, _b: int, down: Array, _heroes: Array) -> void: told.append(down))
	wars.pathfinder = null # (no way to be found)
	var battle := wars.set_out(first.id, second.id, [], [], session.clock.tick)
	assert_true(battle.is_empty())
	assert_eq(told.size(), 1, "told at once")


func test_peace_sets_border_stones() -> void:
	var record := _at_war()
	record["war"]["fallen"] = ConflictSystem.PEACE_AFTER_FALLEN
	session.walking_raids = true
	session.conflicts._peace_if_due(first.id, second.id, session.clock.tick)
	assert_true((record["war"] as Dictionary).is_empty(), "peace")
	var stones := session.props.of_kind(PropData.Kind.BORDER_STONES)
	assert_eq(stones.size(), 1, "border stones set")
	assert_eq(UIText.prop_name(PropData.Kind.BORDER_STONES), "Border stones")
	var middle := (Vector2(first.fire().tile) + Vector2(second.fire().tile)) * 0.5
	assert_true(Vector2(stones[0].tile).distance_to(middle) <= 8.0, "between them")
	assert_true(session.assemblies.pending().any(func(e: Array) -> bool: return StringName(e[0]) == Assemblies.PEACE), "the leaders to meet")
	# Once only.
	assert_null(session.border_stones(first.id, second.id))


func test_saved_and_restored() -> void:
	assert_not_null(wars.meeting_ground(first, second))
	_at_war()
	_at_hour(8.0)
	var battle := wars.set_out(first.id, second.id, [_grown(first)[0].id], [], session.clock.tick)
	assert_false(battle.is_empty())
	wars.queue(first.id, second.id, [], [], session.clock.tick)
	var again := WarParties.new()
	again.from_dict(JSON.parse_string(JSON.stringify(wars.to_dict())))
	assert_eq(again.battles().size(), 1)
	assert_eq(again.battles()[0]["ground"], battle["ground"])
	assert_eq(again.battles()[0]["fallen"], battle["fallen"])
	assert_eq(again.battles()[0]["sides"], battle["sides"])
