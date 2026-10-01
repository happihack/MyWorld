extends TestCase
## The debug AI inspector (M4.6) in the running game: with the debug overlay
## up it shows whoever is selected — what they are doing and why — and the
## commands.

var main: Node
var ui: UIRoot
var view: WorldView
var session: WorldSession
var rig: CameraRig
var overlay: DebugOverlay
var inspector: AiInspector
var heard: Array[InteractionResponse] = []
var _real_vibrate: Callable


func before_each() -> void:
	AudioManager.ensure_sounds()
	_real_vibrate = Haptics.vibrate_action
	Haptics.vibrate_action = func(_ms: int, _amplitude: float) -> void: pass
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
	session = main.get_node("WorldSession")
	overlay = main.get_node("DebugOverlay")
	inspector = main.inspector
	rig = view.camera_rig()
	rig.set_process(false)
	ui.quit_action = func() -> void: pass
	ui.hints().set_process(false)
	heard.clear()
	session.interactions.responded.connect(func(r: InteractionResponse) -> void: heard.append(r))


func after_each() -> void:
	Haptics.vibrate_action = _real_vibrate
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
	await wait_frames(2)


func _show_overlay(shown: bool) -> void:
	if overlay.is_shown() != shown:
		overlay.toggle()
	await wait_frames(2)


func _look_at(xz: Vector2, distance: float = 14.0) -> void:
	rig.focus_on(Vector3(xz.x, 0, xz.y), distance, false)
	for i in 120:
		rig.advance(1.0 / 60.0)
	await wait_frames(2)


func _tap(pos: Vector2) -> void:
	for pressed: bool in [true, false]:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = pos
		t.pressed = pressed
		get_tree().root.push_input(t, true)


## Someone who is up and standing still, with nobody else near them.
func _someone() -> PersonData:
	session.behavior.enabled = false # (everyone holds still to be tapped)
	var best: PersonData = null
	var most_room := -1.0
	for p in session.people.all_people():
		if p.has_flag(PersonData.FLAG_INDOORS):
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
	return rig.world_to_screen(view.people_view().ground_position(person) + Vector3(0, PersonMeshLibrary.ADULT_HEIGHT * 0.5, 0))


# --- the text -------------------------------------------------------------------------------------

func test_what_is_said_about_a_person() -> void:
	var person := session.people.all_people()[0]
	person.needs = PackedFloat32Array([0.1, 0.9, 0.8, 0.7, 0.6, 1.0])
	session.clock.tick = 4 * 60 # ten in the morning
	session.behavior.think(person)
	var text := AiInspector.describe(session, person)
	var lines := text.split("\n")
	assert_true(lines[0].begins_with(person.full_name()), lines[0])
	assert_has(lines[0], "#%d" % person.id)
	assert_has(lines[0], "tier 3")
	assert_has(lines[1], "mood")
	for need_name in Needs.NAMES:
		assert_has(text, String(need_name))
	assert_has(text, "hunger   [#.........] 0.10")
	assert_has(text, "doing: Eating — hungry  (eat")
	assert_has(text, "> walk_to  target %s" % [session.props.get_prop(session.start.campfire_id).tile], "the step being carried out is marked")
	assert_has(text, "  eat  at")
	assert_has(text, "0/25 min")
	assert_has(text, "scores: eat ")
	assert_has(text, "*", "the chosen activity is starred")
	assert_has(text, "walking:")
	assert_has(text, "looked up")
	# What is impossible is shown as such; nothing decided yet is said so.
	var child: PersonData = null
	for p in session.people.all_people():
		if p.occupation_id == &"child":
			child = p
	session.behavior.think(child)
	assert_has(AiInspector.describe(session, child), "work --")
	session.behavior._last.clear()
	assert_has(AiInspector.describe(session, person), "nothing decided in this session yet")
	# Someone asleep.
	session.behavior.set_plan(person, &"sleep", &"sleep", [SleepStep.make()], 1.0)
	text = AiInspector.describe(session, person)
	assert_has(text, "INDOORS")
	assert_has(text, "> sleep")
	assert_has(text, "doing: Sleeping — tired")
	# Nothing to do.
	person.current_action = {}
	assert_has(AiInspector.describe(session, person), "doing: nothing")


func test_bars_and_steps() -> void:
	assert_eq(AiInspector.bar(0.0), "[..........]")
	assert_eq(AiInspector.bar(1.0), "[##########]")
	assert_eq(AiInspector.bar(0.54), "[#####.....]")
	assert_eq(AiInspector.bar(7.0), "[##########]")
	assert_eq(AiInspector.bar(-1.0), "[..........]")
	assert_eq(AiInspector.describe_step(WalkToStep.make(Vector2i(3, 4))), "walk_to  target (3, 4)")
	assert_eq(AiInspector.describe_step(RestStep.make(20.0)), "rest  0/20 min")
	assert_eq(AiInspector.describe_step(SocializeStep.make(9, 15.0)), "socialize  partner 9  0/15 min")
	assert_eq(AiInspector.describe_step({}), "?")


# --- in the game ----------------------------------------------------------------------------------

func test_the_inspector_comes_and_goes_with_the_debug_overlay() -> void:
	await _show_overlay(false)
	assert_false(inspector.visible)
	await _show_overlay(true)
	assert_true(inspector.is_visible_in_tree())
	assert_has(inspector.text(), "tap a person")
	assert_true(inspector.button(&"freeze").visible and inspector.button(&"spawn").visible)
	assert_false(inspector.button(&"kill").visible, "nobody to kill yet")
	assert_false(inspector.button(&"think").visible)
	var person := session.people.all_people()[0]
	assert_true(main.select_person(person.id))
	await wait_frames(2)
	assert_eq(inspector.inspected_id(), person.id, "it shows whoever is selected")
	assert_true(inspector.button(&"kill").visible)
	await _show_overlay(false)
	assert_false(inspector.visible)
	assert_eq(main.selected_person_id(), person.id, "hiding the overlay does not let go of them")
	main.clear_selection()
	await _show_overlay(true)
	assert_eq(inspector.inspected_id(), 0)
	assert_has(inspector.text(), "tap a person")
	assert_false(inspector.inspect(999_999), "nobody there")


func test_tapping_a_person_with_the_overlay_up_inspects_them() -> void:
	var person := _someone()
	await _look_at(person.world2d())
	await _show_overlay(true)
	_tap(_screen_of(person))
	await wait_frames(2)
	assert_eq(inspector.inspected_id(), person.id)
	assert_true(inspector.text().begins_with(person.full_name()), inspector.text().get_slice("\n", 0))
	assert_eq(person.sim_tier, TierManager.FOCUS, "whoever is inspected is simulated most closely")
	assert_eq(heard.size(), 1, "the hand touched them")
	assert_eq(heard[0].person_id, person.id, "them, not the ground under them")
	# The ring marks them, above their card the inspector.
	assert_true(view.people_view().ring_shown())
	var ring := view.people_view().ring_position()
	assert_true(Vector2(ring.x, ring.z).distance_to(person.world2d()) < 0.01)
	var card := ui.person_card()
	assert_not_null(card)
	assert_true(inspector.get_global_rect().end.y <= card.get_global_rect().position.y, "the inspector sits above the card")
	# A tap on the ground, away from everyone, is an ordinary tap.
	var open := Vector3.ZERO
	for offset: Vector3 in [Vector3(3, 0, 0), Vector3(-3, 0, 0), Vector3(0, 0, 3), Vector3(0, 0, -3), Vector3(3, 0, 3), Vector3(-3, 0, -3)]:
		open = view.people_view().ground_position(person) + offset
		var crowded := false
		for other in session.people.all_people():
			if other.world2d().distance_to(Vector2(open.x, open.z)) < 2.0:
				crowded = true
		# (not under the card or the inspector either)
		if not crowded and not (main.get_node("InputRouter") as InputRouter).is_over_ui(rig.world_to_screen(open)):
			break
	await wait_real_ms(Config.interaction.double_tap_ms + 80) # a separate tap, not a double tap
	_tap(rig.world_to_screen(open))
	await wait_frames(2)
	assert_eq(inspector.inspected_id(), person.id, "still inspecting")
	assert_eq(heard.size(), 2, "and the ground answered")
	assert_eq(heard[1].person_id, 0)
	# The close button lets them go.
	inspector.button(&"close").pressed.emit()
	assert_eq(inspector.inspected_id(), 0)
	assert_eq(main.selected_person_id(), 0)
	assert_eq(person.sim_tier, TierManager.ACTIVE)
	await wait_frames(2)
	assert_null(ui.person_card())


func test_without_the_overlay_a_tap_on_a_person_selects_them_unseen_by_the_inspector() -> void:
	var person := _someone()
	await _look_at(person.world2d())
	await _show_overlay(false)
	_tap(_screen_of(person))
	await wait_frames(2)
	assert_eq(main.selected_person_id(), person.id)
	assert_false(inspector.visible)
	await _show_overlay(true)
	assert_eq(inspector.inspected_id(), person.id, "shown, it shows who is selected")


func test_someone_asleep_indoors_cannot_be_tapped() -> void:
	var person := _someone()
	await _look_at(person.world2d())
	await _show_overlay(true)
	person.set_flag(PersonData.FLAG_INDOORS, true)
	await wait_frames(2)
	assert_null(view.people_view().pick_shape(person.id))
	_tap(_screen_of(person))
	await wait_frames(2)
	assert_eq(inspector.inspected_id(), 0)
	assert_eq(view.pick_person(_screen_of(person), 60.0), 0)
	person.set_flag(PersonData.FLAG_INDOORS, false)
	await wait_frames(2)
	assert_eq(view.pick_person(_screen_of(person), 60.0), person.id)
	assert_eq(view.pick_person(Vector2(5, 5), 10.0), 0, "nobody up there")


func test_the_freeze_button_stops_everyone_and_lets_them_go_again() -> void:
	await _show_overlay(true)
	session.clock.set_speed(GameClock.SPEED_VERY_FAST)
	await wait_real_ms(400)
	inspector.button(&"freeze").pressed.emit()
	assert_false(session.behavior.enabled)
	assert_eq(inspector.button(&"freeze").text, "Unfreeze AI")
	assert_has(inspector.text(), "FROZEN")
	assert_has(main._doing_debug_section(), "FROZEN")
	assert_has(main._doing_debug_section(), "active AI 0")
	var frozen := session.people.to_dict()
	var tick := session.clock.tick
	await wait_real_ms(400)
	assert_true(session.clock.tick > tick, "the clock runs on")
	assert_eq(session.people.to_dict(), frozen, "but nobody lives and nobody walks")
	inspector.button(&"freeze").pressed.emit()
	assert_true(session.behavior.enabled)
	assert_eq(inspector.button(&"freeze").text, "Freeze AI")
	await wait_real_ms(400)
	assert_ne(session.people.to_dict(), frozen, "thawed, they go on")
	assert_has(main._doing_debug_section(), "active AI %d" % session.people.size())


func test_spawn_think_and_kill() -> void:
	await _show_overlay(true)
	await _look_at(Vector2(session.start.settlement_tile) + Vector2(0.5, 3.5))
	var before := session.people.size()
	inspector.button(&"spawn").pressed.emit()
	assert_eq(session.people.size(), before + 1, "someone new")
	var newcomer := session.people.get_person(main.selected_person_id())
	assert_not_null(newcomer, "and they are the one selected")
	assert_true(newcomer.world2d().distance_to(Vector2(rig.pivot().x, rig.pivot().z)) < 3.0, "where the player is looking")
	await wait_frames(3)
	assert_not_null(view.people_view().view_of(newcomer.id), "there to be seen")
	# Think: they weigh everything up now.
	var decisions := session.behavior.decisions
	inspector.button(&"think").pressed.emit()
	assert_true(session.behavior.decisions > decisions)
	assert_has(inspector.text(), "scores: ")
	# Kill: gone, and the inspector lets go.
	inspector.button(&"kill").pressed.emit()
	assert_null(session.people.get_person(newcomer.id))
	assert_eq(session.people.size(), before)
	assert_eq(inspector.inspected_id(), 0)
	assert_eq(main.selected_person_id(), 0)
	assert_has(inspector.text(), "tap a person")
	assert_false(inspector.button(&"kill").visible)


func test_the_inspector_follows_the_person_it_shows() -> void:
	await _show_overlay(true)
	var person := session.people.all_people()[0]
	main.select_person(person.id)
	person.needs[Needs.Need.HUNGER] = 0.33
	await wait_real_ms(400) # (the text refreshes four times a second)
	assert_has(inspector.text(), "0.3")
	# Touches on the panel never reach the world.
	var router: InputRouter = main.get_node("InputRouter")
	assert_true(router.is_over_ui(inspector.get_global_rect().get_center()))
	_tap(inspector.button(&"freeze").get_global_rect().get_center())
	await wait_frames(2)
	assert_eq(heard.size(), 0)


func test_the_overlay_counts_people_ai_and_paths() -> void:
	var doing: String = main._doing_debug_section()
	assert_has(doing, "active AI %d" % session.people.size())
	assert_has(doing, "tiers 4:0 3:%d 2:0" % session.people.size())
	assert_has(doing, "decisions")
	var people: String = main._people_debug_section()
	assert_has(people, "people %d in" % session.people.size())
	overlay.refresh()
	var text: String = (overlay.get_node("%OverlayLabel") as Label).text
	assert_has(text, "/frame")
	assert_has(text, "paths: ")
