extends TestCase
## The player's history and first statistics (M5.5, bible §27.2–27.4): what
## is counted, what is said, the first achievement, and the card that shows it.

const V6_FIXTURE := "res://tests/fixtures/saves/v6_world.sav"
const V6_ID := "w1790870731_6c3083c1"

var main: Node
var ui: UIRoot
var view: WorldView
var session: WorldSession
var rig: CameraRig
var router: InputRouter
var unlocked: Array[StringName] = []
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
	unlocked.clear()
	EventBus.achievement_unlocked.connect(_on_unlocked)
	await _open_main()


func _open_main() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	main = get_tree().current_scene
	ui = main.get_node("UIRoot")
	view = main.get_node("WorldView")
	session = main.get_node("WorldSession")
	router = main.get_node("InputRouter")
	rig = view.camera_rig()
	rig.set_process(false)
	ui.quit_action = func() -> void: pass
	ui.hints().set_process(false)
	session.behavior.enabled = false # (nobody moves or reacts: this is about the player's side)


func after_each() -> void:
	EventBus.achievement_unlocked.disconnect(_on_unlocked)
	Haptics.vibrate_action = _real_vibrate
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
	await wait_frames(2)


func _on_unlocked(id: StringName) -> void:
	unlocked.append(id)


func _touch(person: PersonData) -> Intervention:
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = person.id
	target.entity_kind = SpatialIndex.KIND_PERSON
	target.tile = person.position
	target.direct = true
	return session.interactions.apply_intervention(Intervention.create(Intervention.TOUCH, &"hand", target))


func _tap_prop(kind: PropData.Kind) -> void:
	for prop in session.props.all_props():
		if prop.kind == kind:
			var target := Picker.Result.new()
			target.kind = Picker.Kind.ENTITY
			target.entity_id = prop.id
			target.tile = prop.tile
			session.interactions.tap(target)
			return


func _tap(pos: Vector2) -> void:
	for pressed: bool in [true, false]:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = pos
		t.pressed = pressed
		get_tree().root.push_input(t, true)


# --- counting -------------------------------------------------------------------------------------

func test_people_touched_are_counted_once_each() -> void:
	var history := session.history
	var people := session.people.all_people()
	assert_eq(history.people_touched(), 0)
	assert_eq(history.stats()["people_touched"], 0)
	_touch(people[0])
	_touch(people[0])
	_touch(people[1])
	assert_eq(history.people_touched(), 2, "two people, however often")
	assert_eq(history.touches_of(people[0].id), 2)
	assert_eq(history.touches_of(people[2].id), 0)
	assert_eq(history.count(Intervention.TOUCH, &"person"), 3)
	var stats := history.stats()
	assert_eq(stats["people_touched"], 2)
	assert_eq(stats["total_interactions"], 3)
	assert_eq(stats["objects_moved"], 0)
	# Other things touched are not people.
	_tap_prop(PropData.Kind.TREE)
	assert_eq(history.people_touched(), 2)
	assert_eq(history.stats()["total_interactions"], 4)
	# Someone touched who leaves the world still counts.
	session.kill_person(people[0].id)
	assert_eq(history.people_touched(), 2)
	# Kept across saves.
	var again := PlayerHistory.new()
	assert_true(again.from_dict(history.to_dict().duplicate(true)))
	assert_eq(again.people_touched(), 2)
	assert_eq(again.touches_of(people[0].id), 2)
	assert_eq(again.to_dict(), history.to_dict())
	# Broken data does no harm.
	var broken := history.to_dict().duplicate(true)
	broken["people"] = {"x": 3, 5: "many", 6: -2, 7: 4}
	broken["achievements"] = {"first_contact": "yes", "other": {"tick": 9}}
	assert_true(again.from_dict(broken))
	assert_eq(again.people_touched(), 1)
	assert_eq(again.touches_of(7), 4)
	assert_false(again.has_achievement(PlayerHistory.FIRST_CONTACT))
	assert_true(again.has_achievement(&"other"))
	broken["people"] = "nobody"
	broken.erase("achievements")
	assert_true(again.from_dict(broken))
	assert_eq(again.people_touched(), 0)
	assert_eq(again.achievements().size(), 0)


func test_first_contact_is_unlocked_once() -> void:
	var history := session.history
	var people := session.people.all_people()
	assert_false(history.has_achievement(PlayerHistory.FIRST_CONTACT))
	# Touching the world is not contact.
	_tap_prop(PropData.Kind.TREE)
	assert_eq(unlocked.size(), 0)
	assert_eq(history.achievements().size(), 0)
	session.clock.tick = 4321
	var iv := _touch(people[0])
	assert_true(history.has_achievement(PlayerHistory.FIRST_CONTACT))
	assert_eq(unlocked, [PlayerHistory.FIRST_CONTACT] as Array[StringName], "the world is told")
	assert_eq(history.achievements(), {"first_contact": {"tick": 4321, "intervention": iv.id}}, "when, and by what")
	assert_eq(history.take_unlocked().size(), 0, "announced: nothing left to announce")
	# Never again.
	_touch(people[0])
	_touch(people[1])
	assert_eq(unlocked.size(), 1)
	assert_false(history.unlock(PlayerHistory.FIRST_CONTACT, 9999))
	assert_eq(int(history.achievements()["first_contact"]["tick"]), 4321)
	# It is the world's: saved with it, and not announced again on loading.
	var saved := session.to_dict()
	var again := WorldSession.new()
	add_child(again)
	assert_true(again.load_from(saved.duplicate(true)))
	assert_true(again.history.has_achievement(PlayerHistory.FIRST_CONTACT))
	assert_eq(again.history.take_unlocked().size(), 0)
	assert_eq(unlocked.size(), 1)
	again.queue_free()
	# Another achievement is another matter.
	assert_true(history.unlock(&"something_else", 5000))
	assert_eq(history.take_unlocked(), [&"something_else"] as Array[StringName])
	# A new world starts without any.
	session.create_new(777)
	assert_eq(session.history.achievements().size(), 0)
	assert_eq(session.history.people_touched(), 0)
	assert_true(MemoryText.has("ACHIEVEMENT_FIRST_CONTACT"))


# --- words ----------------------------------------------------------------------------------------

func test_the_history_in_words() -> void:
	assert_true(MemoryText.has("HIST_YEAR"), "the templates are loaded (data/text/history.csv)")
	var year := Config.time.ticks_per_year()
	var start := roundi(Config.time.start_hour * 60.0) # (the world begins at this minute of its first day)
	assert_eq(HistoryText.year_of(0), 1, "the first year is year 1")
	assert_eq(HistoryText.year_of(year - start - 1), 1)
	assert_eq(HistoryText.year_of(year - start), 2, "years turn at midnight")
	assert_eq(HistoryText.year_of(year * 30 + 5), 31)
	assert_eq(HistoryText.year_of(-50), 1)
	assert_eq(HistoryText.line({"type": "touch", "subject": "person", "first": true, "tick": 10}), "YEAR 1 · touched first inhabitant")
	assert_eq(HistoryText.line({"type": "touch", "subject": "person", "first": false, "tick": year * 2}), "YEAR 3 · touched an inhabitant")
	assert_eq(HistoryText.text({"type": "touch", "subject": "tree", "first": true}), "shook a tree for the first time")
	assert_eq(HistoryText.text({"type": "touch", "subject": "hut", "first": true}), "touched a hut for the first time")
	assert_eq(HistoryText.text({"type": "move_object", "subject": "boulder", "first": true}), "moved a boulder for the first time")
	assert_eq(HistoryText.text({"type": "move_object", "subject": "boulder", "first": false}), "moved a boulder")
	assert_eq(HistoryText.text({"type": "uproot", "subject": "tree", "first": true}), "uprooted a first tree")
	assert_eq(HistoryText.text({"type": "uproot", "subject": "tree"}), "uprooted a tree")
	assert_eq(HistoryText.text({"type": "pour_water", "subject": "water", "first": true}), "poured water from above for the first time")
	assert_eq(HistoryText.text({"type": "move_object", "subject": "thing_from_the_future"}), "moved something")
	assert_eq(HistoryText.text({"type": "rain", "subject": "sky"}), "did something to something", "a kind without words yet still reads")
	# Every kind of act there is, on every kind of thing, has words with nothing left to fill in.
	var subjects: Array[String] = ["person", "water", "ground"]
	for kind: String in PropData.Kind.keys():
		subjects.append(kind.to_lower())
	for kind: String in LooseObject.Kind.keys():
		subjects.append(kind.to_lower())
	for type: StringName in [Intervention.TOUCH, Intervention.MOVE_OBJECT, Intervention.UPROOT, Intervention.SCOOP_WATER, Intervention.POUR_WATER]:
		for subject in subjects:
			for first: bool in [true, false]:
				var text := HistoryText.text({"type": String(type), "subject": subject, "first": first})
				assert_false(text.contains("{") or text.contains("HIST") or text.contains("something"), "%s of %s: %s" % [type, subject, text])


# --- the card -------------------------------------------------------------------------------------

func test_the_journal_button_opens_the_history() -> void:
	var button := ui.journal_button()
	var home := ui.get_node("%HomeButton") as Control
	assert_true(button.is_visible_in_tree())
	assert_true(button.get_global_rect().end.y <= home.get_global_rect().position.y, "above the Home button")
	assert_near(button.get_global_rect().get_center().x, home.get_global_rect().get_center().x, 1.0)
	assert_near(button.get_global_rect().size.x, home.get_global_rect().size.x, 1.0, "the same size")
	assert_true(button.get_global_rect().size.y >= UITheme.TOUCH_TARGET)
	assert_true(router.is_over_ui(button.get_global_rect().get_center()), "a touch on it is not a touch of the world")
	assert_null(ui.history_card())
	# A real tap on it.
	_tap(button.get_global_rect().get_center())
	await wait_frames(3)
	var card := ui.history_card()
	assert_not_null(card)
	assert_eq(session.history.total(), 0, "and the world was not touched")
	assert_eq(card.title_text(), "Your hand in this world")
	assert_eq(card.subtitle_text(), "Year 1")
	assert_eq(card.count_rows(), {"Interactions": "0", "People touched": "0", "Objects moved": "0"})
	assert_eq(card.lines(), PackedStringArray(["Nothing yet. The world has not felt you."]))
	assert_true(card.get_global_rect().end.y < ui.tool_bar().get_global_rect().position.y, "above the tools")
	assert_true(card.get_global_rect().position.y >= 0.0)
	assert_false(card.get_global_rect().intersects(button.get_global_rect()), "clear of the round buttons")
	assert_true(router.is_over_ui(card.get_global_rect().get_center()))
	# Pressed again: closed. The back button closes it too.
	button.pressed.emit()
	await wait_frames(2)
	assert_null(ui.history_card())
	assert_eq(ui.panel_count(), 0)
	button.pressed.emit()
	await wait_frames(2)
	assert_not_null(ui.history_card())
	EventBus.back_requested.emit()
	await wait_frames(2)
	assert_null(ui.history_card())


func test_the_card_tells_what_was_done_latest_first() -> void:
	var people := session.people.all_people()
	ui.open_history()
	await wait_frames(2)
	var card := ui.history_card()
	assert_true(ui.open_history() == card, "open already: the same card")
	# Things are done while it is open.
	_tap_prop(PropData.Kind.TREE)
	_touch(people[0])
	_touch(people[0])
	_touch(people[1])
	card.refresh()
	await wait_frames(4)
	assert_eq(card.lines(), PackedStringArray(["YEAR 1 · touched first inhabitant", "YEAR 1 · shook a tree for the first time"]),
		"the firsts, the latest on top; ordinary touches are counted, not listed")
	assert_eq(card.count_rows(), {"Interactions": "4", "People touched": "2", "Objects moved": "0"})
	# Years go by.
	session.clock.tick = Config.time.ticks_per_year() * 2 + 100
	var rock: LooseObject = null
	for object in session.loose.all_objects():
		if object.kind == LooseObject.Kind.BOULDER:
			rock = object
			break
	assert_not_null(rock)
	assert_true(session.interactions.grab(rock.id))
	session.interactions.carry(rock.id, rock.position + Vector2(1.0, 0.0), 0.5)
	assert_true(session.interactions.release(rock.id).applied)
	await wait_real_ms(700) # (the card keeps itself up to date)
	assert_eq(card.lines()[0], "YEAR 3 · moved a boulder for the first time")
	assert_eq(card.subtitle_text(), "Year 3")
	assert_eq(card.count_rows()["Objects moved"], "1")
	assert_eq(card.lines().size(), 3)
	assert_eq(HistoryCard.lines_of(session.history, 2).size(), 2, "no more than asked for")
	# A long history: the latest are listed, the list scrolls, the card stays on the screen.
	# The same thing done several times running in a year is one line.
	for i in 12:
		session.history._entries.append({"id": 900 + i, "type": "move_object", "subject": "boulder", "first": false, "tick": session.clock.tick})
	assert_eq(HistoryCard.lines_of(session.history, 3), PackedStringArray(["YEAR 3 · moved a boulder (12 times)",
		"YEAR 3 · moved a boulder for the first time", "YEAR 1 · touched first inhabitant"]))
	for i in 200:
		session.history._entries.append({"id": 1000 + i, "type": "move_object" if i % 2 == 0 else "uproot",
			"subject": "boulder" if i % 2 == 0 else "tree", "first": false, "tick": 100 + i})
	card.refresh()
	await wait_frames(6)
	assert_eq(card.lines().size(), HistoryCard.MAX_SHOWN)
	assert_true(card.get_global_rect().position.y >= 0.0, "on the screen")
	assert_true(card.get_global_rect().end.y < ui.tool_bar().get_global_rect().position.y)
	var scroll := card.get_node("%Scroll") as ScrollContainer
	assert_true(scroll.size.y <= HistoryCard.LIST_MAX_HEIGHT + 1.0)
	assert_true((card.get_node("%List") as Control).size.y > scroll.size.y, "more than fits: it scrolls")


func test_one_card_at_a_time() -> void:
	var person := session.people.all_people()[0]
	ui.open_history()
	await wait_frames(2)
	main.select_person(person.id)
	await wait_frames(2)
	assert_null(ui.history_card(), "a person's card takes its place")
	assert_not_null(ui.person_card())
	assert_eq(ui.panel_count(), 1)
	ui.journal_button().pressed.emit()
	await wait_frames(2)
	assert_not_null(ui.history_card())
	assert_null(ui.person_card(), "and the other way round")
	assert_eq(main.selected_person_id(), 0, "the person is let go")
	assert_eq(ui.panel_count(), 1)


# --- older worlds ---------------------------------------------------------------------------------

func test_version_6_save_migrates_its_history() -> void:
	# Written by M5.4 (0318478): three people touched (one of them three
	# times), a tree shaken, a rock moved. The history did not yet know whom.
	assert_true(FileAccess.file_exists(V6_FIXTURE), "fixture present")
	var dir := SaveManager.world_dir(V6_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V6_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 6)
	var loaded := SaveManager.load_world(V6_ID)
	assert_true(loaded.ok, loaded.error)
	var s := WorldSession.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	var history := s.history
	assert_eq(history.people_touched(), 3, "who had been touched is known from the marks they carry")
	assert_eq(history.touches_of(7), 3, "and how often")
	assert_eq(history.touches_of(8), 1)
	assert_eq(history.touches_of(10), 0)
	assert_eq(history.count(Intervention.TOUCH, &"person"), 5)
	assert_true(history.has_achievement(PlayerHistory.FIRST_CONTACT), "first contact had been made")
	var first: Dictionary = history.achievements()["first_contact"]
	assert_eq(first["intervention"], 1, "by the first intervention of all")
	assert_eq(first["tick"], history.entries()[0]["tick"])
	assert_eq(history.take_unlocked().size(), 0, "not announced again")
	assert_eq(HistoryCard.lines_of(history, 10), PackedStringArray([
		"YEAR 1 · moved a rock for the first time", "YEAR 1 · shook a tree for the first time", "YEAR 1 · touched first inhabitant"]))
	assert_eq(HistoryCard.counters(history), [["Interactions", 7], ["People touched", 3], ["Objects moved", 1]])
	assert_eq(s.memories.size(), 4, "and nothing else was lost")
	# Saved again: the current version, the old file kept.
	assert_true(SaveManager.save_world(s, &"test"))
	assert_eq(SaveManager.SAVE_VERSION, 7)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 7)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav.bak1")).header["save_version"], 6)
	s.queue_free()
	# A world whose history is empty has nothing to derive.
	var data := {"world": {"world_state": {"history": {}, "people": {"persons": []}}}}
	assert_eq(SaveMigrations._v6_to_v7(data)["world"]["world_state"]["history"], {})
	var untouched := {"world": {"world_state": {"history": {"next_id": 2, "keys": {"touch:tree": 1}, "entries": []},
		"people": {"persons": [{"id": 3, "flags": 0}]}}}}
	var migrated: Dictionary = SaveMigrations._v6_to_v7(untouched)["world"]["world_state"]["history"]
	assert_eq(migrated["people"], {})
	assert_eq(migrated["achievements"], {})
