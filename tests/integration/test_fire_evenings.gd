extends TestCase
## Evenings by the fire (the owner, 2026-10-06): a dance circle, stories
## told and listened to (and what is told goes round), singing, and warming
## oneself — only while the fire burns.

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var session: WorldSession
var ctx: AiContext


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.behavior.enabled = false
	ctx = session.behavior.ctx


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


func _grown() -> Array[PersonData]:
	var out: Array[PersonData] = []
	for person in session.people.all_people():
		if ctx.stage_of(person) == PersonData.LifeStage.ADULT:
			out.append(person)
	return out


func test_only_while_the_fire_burns() -> void:
	var person := _grown()[0]
	assert_true(Planner.can(&"fire", person, ctx))
	session.settlement.fire().stock = 0 # (it has gone out)
	assert_false(session.settlement.fire_lit())
	assert_false(Planner.can(&"fire", person, ctx), "a cold hearth draws nobody")
	for id: StringName in [&"dance", &"storytelling", &"sing", &"warm_by_fire"]:
		assert_true(session.activities.get_def(id).requires.has(&"fire"), "%s needs the fire" % id)
		assert_eq(UIText.ACTIVITY_NAMES.has(id), true, "%s has a name on the card" % id)
		assert_true(MemoryText.has("DAY_" + String(id).to_upper()), "%s in the day's log" % id)
	# Of an evening, not at noon.
	var dance := session.activities.get_def(&"dance")
	assert_true(dance.hour_factor(20.0) > 1.0)
	assert_eq(dance.hour_factor(12.0), 0.0)


func test_a_dance_circle() -> void:
	var person := _grown()[0]
	var steps := Planner.plan(&"dance", person, ctx)
	assert_true(steps.size() >= 4)
	var spots := {}
	var fire := session.settlement.fire().tile
	for i in range(0, steps.size(), 2):
		var spot: Vector2i = steps[i]["target"]
		assert_eq(maxi(absi(spot.x - fire.x), absi(spot.y - fire.y)), 1, "round the fire")
		spots[spot] = true
		assert_eq(str(steps[i + 1]["emote"]), "note", "singing as they go")
	assert_eq(spots.size(), steps.size() / 2, "from place to place round it")


func test_stories_go_round_the_fire() -> void:
	var grown := _grown()
	var teller := grown[0]
	var listener := grown[1]
	# Something to tell: the teller saw the river come into the huts.
	var memory := Memory.new()
	memory.subject = Stimulus.FLOOD
	memory.interpretation = &"natural"
	memory.source = Memory.Source.WITNESSED
	memory.tick = ctx.now()
	memory.first_tick = ctx.now()
	memory.importance = 0.8
	memory.intensity = 0.8
	memory.emotions = PackedFloat32Array([0.1, 0.6, 0.0, 0.7, 0.2])
	session.memories.remember(teller, memory)
	assert_true(Planner.can(&"stories", teller, ctx), "tales to tell")
	var telling := Planner.plan(&"storytelling", teller, ctx)
	assert_eq(str(telling[1]["role"]), "tell")
	assert_eq(Planner._teller_at_fire(listener, ctx), teller.id, "known as the teller at once")
	assert_true(Planner.can(&"stories", listener, ctx), "someone to listen to")
	var listening := Planner.plan(&"storytelling", listener, ctx)
	assert_eq(str(listening[1]["role"]), "listen")
	assert_eq(int(listening[1]["teller"]), teller.id)
	# By the fire, both: the story is told, and the listener has it now.
	var spot_teller: Vector2i = telling[0]["target"]
	var spot_listener: Vector2i = listening[0]["target"]
	session.people.move(teller.id, spot_teller)
	session.people.move(listener.id, spot_listener)
	listener.current_action = {"activity": "storytelling"}
	var step := FireStoryStep.new()
	var tell_step: Dictionary = telling[1]
	step.begin(ctx, teller, tell_step)
	assert_eq(teller.emote, &"speech")
	var listen_step: Dictionary = listening[1]
	step.begin(ctx, listener, listen_step)
	assert_eq(listener.pose, PersonData.Pose.KNEEL, "sitting to listen")
	assert_eq(step.update(ctx, teller, tell_step, FireStoryStep.TOLD_AFTER + 1.0), ActionStep.Status.RUNNING)
	assert_true(bool(tell_step["told"]))
	# (Heard as a telling: the listener makes of it what they will when next they think.)
	var told: Array = ctx.perceptions.get(listener.id, [])
	assert_true(told.any(func(p: Dictionary) -> bool:
		var stimulus: Stimulus = p["stimulus"]
		return stimulus.type == Stimulus.TOLD and stimulus.about == Stimulus.FLOOD and stimulus.told_by == teller.id),
		"what the teller saw, the listener has heard of")
	assert_true(memory.told_tick >= 0, "told")
	assert_eq(step.update(ctx, listener, listen_step, 1.0), ActionStep.Status.RUNNING, "listening on")
	step.end(ctx, teller, tell_step)
	assert_eq(Planner._teller_at_fire(listener, ctx), 0, "the story over")
	assert_eq(step.update(ctx, listener, listen_step, 1.0), ActionStep.Status.DONE, "and the listeners go")
	# A child listens, but does not tell.
	for person in session.people.all_people():
		if ctx.stage_of(person) == PersonData.LifeStage.CHILD:
			session.lifecycle.remember_life(person, &"life_flood", ctx.now(), 0.8)
			assert_false(Planner.can(&"stories", person, ctx), "a child has nobody to listen to and tells none")
			break


func test_singing_and_warming() -> void:
	var person := _grown()[0]
	var singing := Planner.plan(&"sing", person, ctx)
	assert_eq(int(singing[1]["pose"]), PersonData.Pose.KNEEL)
	assert_eq(str(singing[1]["emote"]), "note")
	var warming := Planner.plan(&"warm_by_fire", person, ctx)
	assert_eq(warming.size(), 2)
	var fire := session.settlement.fire().tile
	var at: Vector2i = warming[0]["target"]
	assert_eq(maxi(absi(at.x - fire.x), absi(at.y - fire.y)), 1, "at the fire")
