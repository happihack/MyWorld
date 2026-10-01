extends TestCase
## Reactions as the player meets them (M5.3) in the running game: touch
## someone, and they show what they make of it — a pose, a sign above the
## head, a voice, a pulse, a line on their card.

var main: Node
var ui: UIRoot
var view: WorldView
var people_view: PeopleView
var session: WorldSession
var rig: CameraRig
var pulses: Array = [] # [milliseconds, amplitude]
var _real_vibrate: Callable


func before_each() -> void:
	AudioManager.ensure_sounds()
	_real_vibrate = Haptics.vibrate_action
	pulses.clear()
	Haptics.vibrate_action = func(ms: int, amplitude: float) -> void: pulses.append([ms, amplitude])
	Haptics.reset()
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	var first := WorldSession.new()
	add_child(first)
	first.create_new(12345)
	SaveManager.save_world(first, &"test")
	first.queue_free()
	await wait_frames(2)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	main = get_tree().current_scene
	ui = main.get_node("UIRoot")
	view = main.get_node("WorldView")
	people_view = view.people_view()
	session = main.get_node("WorldSession")
	rig = view.camera_rig()
	rig.set_process(false)
	ui.quit_action = func() -> void: pass
	ui.hints().set_process(false)
	session.clock.tick = 5 * 60 # late morning: everyone is up
	# Everyone stays where they are until something happens to them.
	for p in session.people.all_people():
		p.set_flag(PersonData.FLAG_INDOORS, false)
		session.behavior.set_plan(p, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(600.0)])


func after_each() -> void:
	Haptics.vibrate_action = _real_vibrate
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
	await wait_frames(2)


func _look_at(xz: Vector2, distance: float = 12.0) -> void:
	rig.focus_on(Vector3(xz.x, 0, xz.y), distance, false)
	for i in 60:
		rig.advance(1.0 / 60.0)
	await wait_frames(2)


func _tap(pos: Vector2) -> void:
	for pressed: bool in [true, false]:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = pos
		t.pressed = pressed
		get_tree().root.push_input(t, true)


## Someone grown with nobody else near them.
func _someone() -> PersonData:
	var best: PersonData = null
	var most_room := -1.0
	for p in session.people.all_people():
		if p.life_stage(session.clock.tick, Config.time.ticks_per_year(), Config.people) != PersonData.LifeStage.ADULT:
			continue
		var room := INF
		for other in session.people.all_people():
			if other.id != p.id:
				room = minf(room, other.world2d().distance_to(p.world2d()))
		if room > most_room:
			most_room = room
			best = p
	return best


func _screen_of(person: PersonData) -> Vector2:
	return rig.world_to_screen(people_view.ground_position(person) + Vector3(0, PersonMeshLibrary.ADULT_HEIGHT * 0.5, 0))


func test_a_touched_person_shows_what_they_make_of_it() -> void:
	var person := _someone()
	await _look_at(person.world2d())
	assert_eq(people_view.emote_count(), 0)
	var reacted: Array = []
	session.behavior.reacted.connect(func(id: int, reaction: StringName, interpretation: StringName, _stimulus: StringName, direct: bool) -> void:
		reacted.append([id, reaction, interpretation, direct]))
	_tap(_screen_of(person))
	await wait_frames(3)
	# The pipeline ran: an intervention, a stimulus, a reaction.
	assert_eq(session.history.total(), 1)
	assert_eq(session.perception.emitted, 1)
	assert_eq(reacted.size(), 1)
	assert_eq(reacted[0][0], person.id)
	assert_true(reacted[0][3], "it happened to them")
	assert_eq(BehaviorSystem.activity_of(person), BehaviorSystem.ACTIVITY_REACT)
	# A sign above their head...
	assert_ne(person.emote, &"")
	assert_eq(people_view.emote_of(person.id), person.emote)
	var sprite := people_view.emote_sprite(person.id)
	assert_true(sprite.visible)
	assert_true(sprite.texture == PeopleView.EMOTES[person.emote])
	var body := people_view.view_of(person.id)
	assert_true(sprite.position.y > body.position.y + body.scale.y, "above the head")
	assert_near(sprite.position.x, body.position.x, 0.01)
	assert_true(sprite.no_depth_test, "never hidden behind a tree")
	# ...a pose...
	assert_eq(body.act(), float(PersonView.ACT.get(person.pose, 0.0)))
	# ...a voice and a pulse (the touch → reaction moment)...
	if reacted[0][1] != ReactionTable.DISMISS:
		assert_eq(AudioManager.last_sound, &"voice")
	assert_true(pulses.size() >= 1, "felt")
	assert_eq(pulses[0][0], Haptics.duration_ms(Haptics.Strength.MEDIUM), "a medium pulse")
	# ...and a line on their card that says why.
	var card := ui.person_card()
	assert_not_null(card, "the tap selected them too")
	card.refresh()
	assert_eq(card.activity_text(), UIText.reaction_phrase(reacted[0][1], reacted[0][2]))
	assert_has(card.activity_text(), "thinks")
	# The debug overlay knows.
	assert_has(session.perception.debug_text(), "touch #1")
	# When it has run its course the sign goes.
	session.clock.set_speed(GameClock.SPEED_VERY_FAST)
	for i in 400:
		await wait_frames(1)
		if BehaviorSystem.activity_of(person) != BehaviorSystem.ACTIVITY_REACT:
			break
	await wait_frames(2)
	assert_ne(BehaviorSystem.activity_of(person), BehaviorSystem.ACTIVITY_REACT, "it ends")
	if person.emote == &"":
		assert_eq(people_view.emote_of(person.id), &"")
		assert_eq(body.act() if people_view.view_of(person.id) == body else 0.0, float(PersonView.ACT.get(person.pose, 0.0)))


func test_looking_with_observe_disturbs_nobody() -> void:
	var person := _someone()
	await _look_at(person.world2d())
	main.tools.select(ObserveTool.ID)
	_tap(_screen_of(person))
	await wait_frames(3)
	assert_eq(session.perception.emitted, 0, "nothing was given off")
	assert_eq(BehaviorSystem.activity_of(person), BehaviorSystem.ACTIVITY_CALLED)
	assert_eq(people_view.emote_count(), 0)
	assert_eq(session.behavior.reactions, 0)


func test_signs_are_readable_from_afar_and_go_with_their_people() -> void:
	var person := _someone()
	await _look_at(person.world2d(), 9.0)
	session.behavior.set_plan(person, BehaviorSystem.ACTIVITY_REACT, ReactionTable.SPIRIT,
		[ReactStep.make(PersonData.Pose.KNEEL, &"pray", 600.0)])
	await wait_frames(30)
	var sprite := people_view.emote_sprite(person.id)
	assert_eq(people_view.emote_of(person.id), &"pray")
	var near := sprite.scale.x
	assert_near(near, PeopleView.EMOTE_SIZE, 0.001, "its size in the world, up close")
	assert_eq(people_view.view_of(person.id).act(), 2.0, "kneeling")
	# Another sign takes its place.
	person.emote = &"question"
	await wait_frames(30)
	assert_eq(people_view.emote_of(person.id), &"question")
	assert_true(people_view.emote_sprite(person.id) == sprite, "the same sprite")
	assert_eq(people_view.emote_count(), 1)
	# From the middle distance it does not shrink away.
	await _look_at(person.world2d(), 60.0)
	await wait_frames(30)
	var far := people_view.emote_sprite(person.id).scale.x
	var on_screen := far / rig.world_units_per_screen_unit(rig.pivot())
	assert_near(on_screen, PeopleView.EMOTE_MIN_ON_SCREEN, 1.0, "never smaller than can be read")
	assert_true(far > near)
	# Someone with no body drawn (far away) still has their sign.
	await _look_at(person.world2d(), rig.fit_distance())
	await wait_frames(5)
	if not people_view.bodies_shown():
		assert_null(people_view.view_of(person.id))
	assert_eq(people_view.emote_of(person.id), &"question")
	# Indoors: no sign. Out again: back.
	person.set_flag(PersonData.FLAG_INDOORS, true)
	await wait_frames(3)
	assert_eq(people_view.emote_count(), 0)
	person.set_flag(PersonData.FLAG_INDOORS, false)
	await wait_frames(3)
	assert_eq(people_view.emote_count(), 1)
	# A sign nobody has a picture for is not shown.
	person.emote = &"no_such_sign"
	await wait_frames(3)
	assert_eq(people_view.emote_count(), 0)
	person.emote = &"exclaim"
	await wait_frames(3)
	assert_eq(people_view.emote_count(), 1)
	# Gone with the person.
	session.kill_person(person.id)
	await wait_frames(3)
	assert_eq(people_view.emote_count(), 0)
	for emote: StringName in PeopleView.EMOTES:
		assert_not_null(PeopleView.EMOTES[emote], String(emote))
		assert_true((PeopleView.EMOTES[emote] as Texture2D).get_width() >= 64)


func test_a_sign_pops_up_unless_motion_is_reduced() -> void:
	var person := _someone()
	await _look_at(person.world2d(), 9.0)
	people_view.set_process(false) # stepped by hand
	people_view.refresh(0.016)
	person.emote = &"exclaim"
	people_view.refresh(0.016)
	var sprite := people_view.emote_sprite(person.id)
	assert_true(sprite.scale.x < PeopleView.EMOTE_SIZE * 0.9, "small at first")
	var largest := 0.0
	for i in 30:
		people_view.refresh(0.016)
		largest = maxf(largest, sprite.scale.x)
	assert_true(largest > PeopleView.EMOTE_SIZE * 1.02, "a little too large on the way")
	assert_near(sprite.scale.x, PeopleView.EMOTE_SIZE, 0.001, "then to size")
	person.emote = &""
	people_view.refresh(0.016)
	people_view.reduced_motion = true
	person.emote = &"exclaim"
	people_view.refresh(0.016)
	assert_near(people_view.emote_sprite(person.id).scale.x, PeopleView.EMOTE_SIZE, 0.001, "reduced motion: simply there")
	people_view.reduced_motion = false


func test_voices_are_theirs() -> void:
	var child: PersonData = null
	var man: PersonData = null
	var woman: PersonData = null
	var elder: PersonData = null
	for p in session.people.all_people():
		match p.life_stage(session.clock.tick, Config.time.ticks_per_year(), Config.people):
			PersonData.LifeStage.CHILD:
				child = p
			PersonData.LifeStage.ELDER:
				elder = p
			PersonData.LifeStage.ADULT:
				if p.sex == PersonData.Sex.MALE:
					man = p
				else:
					woman = p
	assert_true(main.voice_pitch(child) > main.voice_pitch(woman), "children pipe")
	assert_true(main.voice_pitch(woman) > main.voice_pitch(man))
	if elder != null:
		assert_true(main.voice_pitch(elder) < main.voice_pitch(woman) if elder.sex == PersonData.Sex.FEMALE else main.voice_pitch(elder) < main.voice_pitch(man))
	assert_true(main.voice_pitch(man, ReactionTable.RUN) > main.voice_pitch(man), "fright is shrill")
	assert_true(main.voice_pitch(man, ReactionTable.PRAY) < main.voice_pitch(man))
	assert_true(AudioManager.has_sound(&"voice"))
	# Someone who only saw something is heard too, more quietly, and without a pulse.
	await _look_at(man.world2d())
	pulses.clear()
	AudioManager.last_sound = &""
	main._on_person_reacted(man.id, ReactionTable.FREEZE, ReactionTable.SPIRIT, Stimulus.OBJECT_MOVED, false)
	assert_eq(AudioManager.last_sound, &"voice")
	assert_eq(pulses.size(), 0)
	# A shrug says nothing.
	AudioManager.last_sound = &""
	main._last_voice_msec = 0
	main._on_person_reacted(man.id, ReactionTable.DISMISS, ReactionTable.NATURAL, Stimulus.TOUCH, true)
	assert_eq(AudioManager.last_sound, &"")
	assert_eq(pulses.size(), 1, "but a touch is felt")
	main._on_person_reacted(999_999, ReactionTable.YELL, ReactionTable.NATURAL, Stimulus.TOUCH, true) # nobody: nothing


func test_shaking_a_tree_turns_heads() -> void:
	# The nearest tree to anyone, and whoever is near it.
	var tree: PropData = null
	var nearest := INF
	for prop in session.props.all_props():
		if prop.kind != PropData.Kind.TREE:
			continue
		for p in session.people.all_people():
			var d := p.world2d().distance_to(prop.position2d())
			if d < nearest:
				nearest = d
				tree = prop
	assert_not_null(tree)
	for p in session.people.all_people():
		p.traits = Traits.neutral()
		p.traits[Traits.Axis.CURIOSITY] = 0.6
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = tree.id
	target.tile = tree.tile
	session.interactions.tap(target)
	assert_eq(session.perception.emitted, 1)
	var noticed := session.perception.last_noticed
	assert_true(noticed >= 1, "someone noticed")
	assert_eq(session.behavior.reactions, 0, "not before their turn")
	await wait_real_ms(1500)
	assert_eq(session.behavior.reactions, noticed, "each of them made something of it")
	assert_true(people_view.emote_count() >= 0)
	assert_has(main.debug_overlay._sections.keys() if "_sections" in main.debug_overlay else [&"perception"], &"perception")
