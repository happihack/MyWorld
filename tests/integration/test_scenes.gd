extends TestCase
## FC2: quarrels and fights you can see. A quarrel is raised voices and
## anger, then they walk apart; a fight a scuffle, onlookers turning to it, a
## brave friend pulling them apart (the wounds lighter); children squabble and
## are scolded; those who make it up embrace; new friends wave.

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var session: WorldSession
var behavior: BehaviorSystem
var ctx: AiContext


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	behavior = session.behavior
	ctx = behavior.ctx
	session.clock.tick = 12 * 60 # (noon)
	for person in session.people.all_people():
		person.set_flag(PersonData.FLAG_INDOORS, false)
		person.pose = PersonData.Pose.IDLE


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


## Two of `stage`, side by side; everyone else far off.
func _pair(stage: PersonData.LifeStage) -> Array[PersonData]:
	var two: Array[PersonData] = []
	for person in session.people.all_people():
		if two.size() < 2 and ctx.stage_of(person) == stage:
			two.append(person)
	while two.size() < 2:
		two.append(session.spawn_person(session.settlement.fire().tile, stage))
	var spot := session.pathfinder.standable_near(session.settlement.fire().tile + Vector2i(3, 0), 2, 4)
	session.people.move(two[0].id, spot[0])
	session.people.move(two[1].id, spot[1])
	for person in session.people.all_people():
		if not two.has(person):
			session.people.move(person.id, session.settlement.fire().tile + Vector2i(30, 30))
			person.set_flag(PersonData.FLAG_INDOORS, true)
	return two


func _stage(kind: StringName, a: PersonData, b: PersonData) -> void:
	ctx.scenes.append([kind, a.id, b.id])
	behavior.announce()


func _steps(person: PersonData) -> Array:
	return person.current_action.get("steps", [])


func test_a_quarrel_is_seen() -> void:
	var two := _pair(PersonData.LifeStage.ADULT)
	_stage(Scenes.QUARREL, two[0], two[1])
	for person in two:
		assert_eq(str(person.current_action.get("reason")), String(Scenes.REASON))
		var steps := _steps(person)
		assert_eq(int(steps[0]["pose"]), int(PersonData.Pose.YELL), "raised voices")
		assert_eq(str(steps[0]["emote"]), String(Signs.ANGRY), "and anger")
		assert_eq(steps.size(), 1, "then back to what they were about")
		assert_eq(Signs.shown(person, session.clock.tick + int(steps[0]["minutes"]) + 2), Signs.ANGRY, "still sore a while")


func test_a_fight_is_seen_and_a_friend_steps_in() -> void:
	var two := _pair(PersonData.LifeStage.ADULT)
	# Someone looking on: a brave friend of one of them.
	var friend: PersonData = null
	for person in session.people.all_people():
		if not two.has(person) and ctx.stage_of(person) == PersonData.LifeStage.ADULT:
			friend = person
			break
	if friend == null:
		friend = session.spawn_person(session.settlement.fire().tile, PersonData.LifeStage.ADULT)
	friend.set_flag(PersonData.FLAG_INDOORS, false)
	session.people.move(friend.id, two[0].position + Vector2i(0, 3))
	friend.traits[Traits.Axis.BRAVERY] = 0.8
	session.relationships.modify(friend.id, two[0].id, {"affinity": 0.8, "familiarity": 0.8}, 0, session.clock.tick)
	ctx.scenes.clear() # (the two of them becoming friends: not this test)
	# The fight (its wounds just given), staged.
	for person in two:
		Health.injure(person, Health.FIGHT, 0.4, session.clock.tick)
	var hurt: float = (two[0].injuries[-1] as Dictionary)["severity"]
	_stage(Scenes.FIGHT, two[0], two[1])
	for person in two:
		var steps := _steps(person)
		assert_eq(int(steps[0]["pose"]), int(PersonData.Pose.SCUFFLE), "a scuffle")
		assert_eq(str(steps[1]["emote"]), String(Signs.HURT), "then sore")
	assert_eq(str(friend.current_action.get("reason")), String(Scenes.REASON), "the friend steps in")
	assert_near(float(_steps(two[0])[0]["minutes"]), Scenes.PULLED_APART_MINUTES, 0.001, "pulled apart sooner")
	assert_near(float((two[0].injuries[-1] as Dictionary)["severity"]), hurt * Scenes.LIGHTER, 0.001, "and less hurt")


func test_onlookers_turn_to_it() -> void:
	var two := _pair(PersonData.LifeStage.ADULT)
	var onlooker: PersonData = null
	for person in session.people.all_people():
		if not two.has(person):
			onlooker = person
			break
	onlooker.set_flag(PersonData.FLAG_INDOORS, false)
	onlooker.traits[Traits.Axis.BRAVERY] = -0.8
	session.people.move(onlooker.id, two[0].position + Vector2i(0, 4))
	_stage(Scenes.FIGHT, two[0], two[1])
	assert_eq(Signs.shown(onlooker, session.clock.tick), Signs.QUESTION, "they look")


func test_children_squabble_and_are_scolded() -> void:
	var two := _pair(PersonData.LifeStage.CHILD)
	var grown: PersonData = null
	for person in session.people.all_people():
		if not two.has(person) and ctx.stage_of(person) == PersonData.LifeStage.ADULT:
			grown = person
			break
	grown.set_flag(PersonData.FLAG_INDOORS, false)
	session.people.move(grown.id, two[0].position + Vector2i(0, 3))
	# Children never quarrel nor fight — they squabble.
	assert_false(SocialActs.weights(two[0], two[1], ctx).has(SocialActs.ARGUE))
	_stage(Scenes.SQUABBLE, two[0], two[1])
	for child in two:
		assert_eq(int(_steps(child)[0]["pose"]), int(PersonData.Pose.YELL))
	assert_eq(str(grown.current_action.get("reason")), String(Scenes.REASON), "a grown-up comes")
	assert_eq(int(_steps(grown)[-1]["pose"]), int(PersonData.Pose.YELL), "and scolds")


func test_making_up_is_an_embrace_and_new_friends_wave() -> void:
	var two := _pair(PersonData.LifeStage.ADULT)
	_stage(Scenes.EMBRACE, two[0], two[1])
	assert_eq(int(_steps(two[0])[-1]["pose"]), int(PersonData.Pose.EMBRACE))
	assert_eq(int(_steps(two[1])[-1]["pose"]), int(PersonData.Pose.EMBRACE))
	for person in two:
		behavior.set_plan(person, &"idle", &"routine", [RestStep.make(5.0)])
	_stage(Scenes.FRIENDS, two[0], two[1])
	assert_eq(Signs.shown(two[0], session.clock.tick + 1), Signs.NOTE, "new friends: glad (and not stopped for it)")
	assert_ne(str(two[0].current_action.get("reason")), String(Scenes.REASON))
	# At a meal, a quarrel is only seen in their faces.
	behavior.set_plan(two[0], &"eat", &"hunger", [RestStep.make(30.0)])
	behavior.set_plan(two[1], &"idle", &"routine", [RestStep.make(30.0)])
	_stage(Scenes.QUARREL, two[0], two[1])
	assert_eq(str(two[0].current_action.get("activity")), "eat", "the meal goes on")
	assert_eq(Signs.shown(two[0], session.clock.tick + 1), Signs.ANGRY, "but in anger")
	assert_eq(str(two[1].current_action.get("reason")), String(Scenes.REASON))
	# And from the relationships themselves: falling out, then making it up.
	for person in two:
		behavior.set_plan(person, &"idle", &"routine", [RestStep.make(5.0)])
	session.relationships.modify(two[0].id, two[1].id, {"affinity": -0.6, "familiarity": 0.6}, 0, session.clock.tick)
	ctx.scenes.clear()
	session.relationships.modify(two[0].id, two[1].id, {"affinity": 0.9}, 0, session.clock.tick)
	behavior.announce()
	assert_eq(int(_steps(two[1])[-1]["pose"]), int(PersonData.Pose.EMBRACE), "made up: an embrace")


# --- FC3: grief, love, hardship ---------------------------------------------------------------------

func test_hardship_is_seen_as_it_begins() -> void:
	var person := _pair(PersonData.LifeStage.ADULT)[0]
	var now := session.clock.tick
	Health.injure(person, Health.FALL, 0.4, now)
	assert_eq(Signs.shown(person, now + 1), Signs.HURT, "hurt")
	Signs.clear(person)
	Health.fall_ill(person, Health.BAD_WATER, now)
	assert_eq(Signs.shown(person, now + 1), Signs.ILL, "ill")
	assert_eq(Signs.shown(person, now + 60), &"", "for a while only")
	assert_eq(Signs.state_of(person), Signs.ILL, "— but the one selected shows it while it lasts")


func test_a_flirt_shows_hearts() -> void:
	var two := _pair(PersonData.LifeStage.ADULT)
	SocialActs.carry_out(ctx, two[0], two[1], SocialActs.FLIRT)
	for person in two:
		assert_eq(Signs.shown(person, session.clock.tick + 1), Signs.LOVE)


func test_the_dead_are_mourned() -> void:
	var two := _pair(PersonData.LifeStage.ADULT)
	session.relationships.modify(two[0].id, two[1].id, {"affinity": 0.8, "familiarity": 0.8}, 0, session.clock.tick)
	ctx.scenes.clear()
	behavior.set_plan(two[1], &"idle", &"routine", [RestStep.make(5.0)])
	session.lifecycle.die(two[0], Lifecycle.CAUSE_OLD_AGE, session.clock.tick)
	assert_eq(Signs.shown(two[1], session.clock.tick + 1), Signs.SAD, "grief")
	assert_eq(str(two[1].current_action.get("reason")), String(Scenes.REASON), "they go to mourn")
	var last: Dictionary = _steps(two[1])[-1]
	assert_eq(int(last["pose"]), int(PersonData.Pose.KNEEL), "kneeling")
	assert_eq(str(last["emote"]), String(Signs.SAD))
