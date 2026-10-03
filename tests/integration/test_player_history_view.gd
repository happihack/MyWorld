extends TestCase
## The player's own history (M11.4, bible §27.2–27.3): a year-stamped log of
## what they did, the counts that grow with it — and what came of each act,
## as far as the world knows: who remembers it (and as what), and what the
## chronicle records as caused by it.

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var session: WorldSession
var ctx: AiContext


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
	ctx = session.behavior.ctx


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


func _touch(person: PersonData) -> void:
	person.set_flag(PersonData.FLAG_INDOORS, false)
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = person.id
	target.entity_kind = SpatialIndex.KIND_PERSON
	target.tile = person.position
	target.direct = true
	session.interactions.tap(target)


func _step(minutes: int) -> void:
	for i in minutes:
		session.clock.tick += 1
		session.behavior.step(1.0)
		session.pathfinder.serve(1000000)
		session.movement.step(1.0)


func test_who_remembers_what_i_did() -> void:
	var person := session.people.all_people()[1]
	_touch(person)
	var act := session.history.peek_next_id() - 1
	_step(5)
	# The one touched remembers it — and the memory knows which act it was.
	var theirs: Memory = null
	for memory in session.memories.of(person):
		if memory.intervention_id == act:
			theirs = memory
	assert_not_null(theirs, "the memory knows the act")
	var who := PlayerConsequences.remembered_by(session, [act])
	assert_true(int(who["count"]) >= 1)
	assert_true((who["as"] as Dictionary).has(String(theirs.interpretation)))
	# Told on, the act travels with the story.
	var listener := session.people.all_people()[4]
	Gossip.tell(ctx, person, listener, theirs.subject, theirs.interpretation, 0.8, theirs.fidelity, {}, theirs.intervention_id)
	var heard: Stimulus = (ctx.perceptions[listener.id] as Array)[-1]["stimulus"]
	assert_eq(heard.intervention_id, act)
	# At bedtime too, and handed down.
	var child := PersonData.new()
	child.id = session.ids.next_id()
	child.traits = Traits.neutral()
	child.settlement_id = person.settlement_id
	child.position = person.position
	session.people.add(child)
	assert_eq(Stories.tell(ctx, person, child, theirs).intervention_id, act)
	assert_eq(Memory.from_dict(theirs.to_dict()).intervention_id, act, "saved with the memory")
	assert_true(int(PlayerConsequences.remembered_by(session, [act])["count"]) >= 2)
	assert_true(PlayerConsequences.people_who_remember(session) >= 2)


func test_what_came_of_it() -> void:
	var person := session.people.all_people()[2]
	_touch(person)
	var act := session.history.peek_next_id() - 1
	var touched := session.events.latest(Chronicler.TYPE_PLAYER)
	assert_eq(int(touched.text_params["intervention"]), act)
	# The chronicle records something as caused by it, and something by that.
	var first := session.events.record(Chronicler.TYPE_SHORTAGE, {}, [touched.id])
	var second := session.events.record(Chronicler.TYPE_RATIONING, {}, [first.id])
	var unrelated := session.events.record(Chronicler.TYPE_STORM, {})
	var caused := PlayerConsequences.caused(session, [act])
	assert_eq(caused, [first, second] as Array[WorldEvent])
	assert_false(caused.has(unrelated))
	var lines := PlayerConsequences.lines(session, [act])
	assert_true(lines.has("  → " + EventText.text(first, session.people, session.events)), str(lines))


func test_the_history_card_tells_it() -> void:
	var person := session.people.all_people()[3]
	for n in 3:
		_touch(person)
	_step(5)
	# One line for the same thing again, and the acts it stands for.
	var groups := HistoryCard.groups_of(session.history, 10)
	assert_false(groups.is_empty())
	var ids: Array = groups[0]["ids"]
	assert_true(ids.size() >= 1)
	var came := PlayerConsequences.lines(session, ids)
	assert_true(came.size() >= 1 and came[0].begins_with("  remembered by "), str(came))
	# The counts grow with what was done — and with what the world makes of it.
	var rows := HistoryCard.counters(session.history) + HistoryCard.world_counters(session)
	var labels: Array = []
	for row: Array in rows:
		labels.append(row[0])
	assert_true(labels.has("Who remember you"), str(labels))
	assert_false(labels.has("Rain made"), "nothing of what was not done")
	assert_false(labels.has("Generations witnessed"), "one generation is not yet worth saying")
	# Generations: someone born in the world to a child of the band.
	var parent: PersonData = null
	for p in session.people.all_people():
		if not p.children.is_empty():
			parent = p
	var child := session.people.get_person(parent.children[0])
	var grandchild := PersonData.new()
	grandchild.id = session.ids.next_id()
	grandchild.parents = PackedInt64Array([child.id])
	grandchild.birth_tick = session.clock.tick
	grandchild.position = child.position
	session.people.add(grandchild)
	assert_eq(HistoryCard.generations_witnessed(session), 2, "the band, and one born in the world")
