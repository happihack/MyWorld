extends TestCase
## The day log in the running game (M6.4): "Today" on a person's card,
## the OBSERVER achievement for a day spent following one person, and worlds
## saved before there was a day log.

const V7_FIXTURE := "res://tests/fixtures/saves/v7_world.sav"
const V7_ID := "w1790879302_4bb6614d"

var main: Node
var ui: UIRoot
var view: WorldView
var session: WorldSession
var rig: CameraRig
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
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	main = get_tree().current_scene
	ui = main.get_node("UIRoot")
	view = main.get_node("WorldView")
	session = main.get_node("WorldSession")
	rig = view.camera_rig()
	rig.set_process(false)
	ui.quit_action = func() -> void: pass
	ui.hints().set_process(false)
	session.behavior.enabled = false # (people stand still: the tests write their days)
	session.clock.set_speed(0)


func after_each() -> void:
	EventBus.achievement_unlocked.disconnect(_on_unlocked)
	Haptics.vibrate_action = _real_vibrate
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
	await wait_frames(2)


func _on_unlocked(id: StringName) -> void:
	unlocked.append(id)


func _adult(occupation: StringName = &"woodcutter") -> PersonData:
	for p in session.people.all_people():
		if p.occupation_id == occupation:
			return p
	return null


func _tick_at(hour: float, day: int = 0) -> int:
	return roundi((hour - Config.time.start_hour) * 60.0) + day * 1440


func test_the_card_shows_today() -> void:
	var person := _adult()
	var friend := _adult(&"forager")
	var log := session.day_log
	log.forget(person.id)
	session.clock.tick = _tick_at(13.0)
	main.select_person(person.id)
	await wait_frames(2)
	var card := ui.person_card()
	assert_not_null(card)
	card.set_state(PersonCard.State.FULL)
	card.refresh()
	await wait_frames(4)
	assert_eq(card.today_title(), "Today")
	assert_eq(card.today_text(), "Nothing yet")
	# Their day so far.
	log.note(person.id, _tick_at(6.5), DayLog.WAKE)
	log.note(person.id, _tick_at(7.0), "eat", "meal")
	log.note(person.id, _tick_at(8.0), "work", "tree")
	log.note(person.id, _tick_at(12.0), "socialize", "", friend.id)
	card.refresh()
	await wait_frames(5)
	assert_eq(card.today_text(), "06:30 wakes · 07:00 has breakfast · 08:00 chops wood · 12:00 talks to %s" % friend.given_name)
	var today: Label = card.get_node("%Today")
	var title: Label = card.get_node("%TodayTitle")
	assert_true(today.is_visible_in_tree() and title.is_visible_in_tree())
	assert_true(title.get_global_rect().position.y < today.get_global_rect().position.y, "under its title")
	assert_true(today.get_global_rect().end.y <= (card.get_node("%Family") as Control).get_global_rect().position.y + 1.0, "above the family")
	# It keeps up by itself as the day goes on.
	log.note(person.id, _tick_at(12.9), "eat", "meal")
	await wait_seconds(PersonCard.REFRESH_INTERVAL_S * 2.0)
	assert_true(card.today_text().ends_with(" · 12:54 has lunch"), card.today_text())
	# A long day wraps inside the card and the card stays on the screen.
	for i in 20:
		log.note(person.id, _tick_at(13.0) + i * 10, "drink" if i % 2 == 0 else "work", "" if i % 2 == 0 else "tree")
	session.clock.tick = _tick_at(17.0)
	card.refresh()
	await wait_frames(6)
	var screen := card.get_viewport_rect().size
	assert_true(today.get_line_count() >= 3, "wrapped (%d lines)" % today.get_line_count())
	assert_true(today.get_global_rect().size.x <= card.size.x, "inside the card")
	assert_true(card.get_global_rect().position.y >= 0.0 and card.get_global_rect().end.y <= screen.y, "the card is on the screen")
	# The half card and the peek do not carry it.
	card.set_state(PersonCard.State.HALF)
	await wait_frames(4)
	assert_false(today.is_visible_in_tree())
	# Past midnight, before they are up: yesterday's.
	session.clock.tick = _tick_at(2.0, 1)
	card.set_state(PersonCard.State.FULL)
	card.refresh()
	await wait_frames(4)
	assert_eq(card.today_title(), "Yesterday")
	assert_true(card.today_text().begins_with("06:30 wakes"))
	log.note(person.id, _tick_at(5.6, 1), DayLog.WAKE)
	session.clock.tick = _tick_at(5.7, 1)
	card.refresh()
	assert_eq(card.today_title(), "Today")
	assert_eq(card.today_text(), "05:36 wakes")
	# Someone else's card, someone else's day.
	main.select_person(friend.id)
	await wait_frames(3)
	card = ui.person_card()
	card.set_state(PersonCard.State.FULL)
	card.refresh()
	assert_false(card.today_text().contains("05:36 wakes"))


func test_people_write_their_own_days_in_the_running_game() -> void:
	session.day_log.clear()
	session.behavior.enabled = true
	session.clock.set_speed(3)
	var waited := 0
	while session.day_log.people_count() < session.people.size() and waited < 600:
		await wait_frames(1)
		waited += 1
	session.clock.set_speed(0)
	assert_eq(session.day_log.people_count(), session.people.size(), "everyone has done something")
	var person := _adult()
	main.select_person(person.id)
	await wait_frames(2)
	var card := ui.person_card()
	card.set_state(PersonCard.State.FULL)
	card.refresh()
	assert_eq(card.today_text(), DayLogText.timeline(session.day_log.of(person.id), session.people))
	assert_ne(card.today_text(), "")
	assert_false(card.today_text().contains("{"))


func test_following_someone_for_a_day_unlocks_observer() -> void:
	var person := _adult()
	var other := _adult(&"forager")
	session.clock.tick = 300
	assert_true(main.follow_person(person.id))
	await wait_frames(2)
	assert_eq(session.observer.person_id, person.id, "the world knows who is followed")
	assert_eq(session.observer.since_tick, 300)
	# Half a day; then the view is dragged away for three hours (too long), and taken up again.
	session.clock.tick = 1000
	await wait_frames(2)
	main.follow.pause()
	await wait_frames(2)
	session.clock.tick = 1180
	await wait_frames(2)
	assert_eq(session.observer.away(1180), 180, "paused: the camera is not with them")
	main.follow.resume()
	await wait_frames(2)
	session.clock.tick = 300 + 1440
	await wait_frames(2)
	assert_false(session.history.has_achievement(PlayerHistory.OBSERVER), "a day, but not nine tenths of it with them")
	assert_eq(unlocked, [])
	# Once those hours have passed out of the day, it is a day with them.
	session.clock.tick = 1000 + 1440 + 36
	await wait_frames(2)
	assert_true(session.history.has_achievement(PlayerHistory.OBSERVER))
	assert_eq(unlocked, [PlayerHistory.OBSERVER])
	assert_eq(session.history.achievements()["observer"]["tick"], session.clock.tick)
	# Once only.
	main.follow_person(other.id)
	session.clock.tick += 3000
	await wait_frames(3)
	assert_eq(unlocked.size(), 1)
	# And a world where nobody is followed counts nothing.
	main.stop_following()
	await wait_frames(2)
	assert_false(main.follow.is_active())


func test_following_someone_else_starts_over() -> void:
	var person := _adult()
	var other := _adult(&"forager")
	session.clock.tick = 0
	main.follow_person(person.id)
	await wait_frames(2)
	session.clock.tick = 1400
	await wait_frames(2)
	main.follow_person(other.id)
	await wait_frames(2)
	assert_eq(session.observer.person_id, other.id)
	session.clock.tick = 1500
	await wait_frames(2)
	assert_false(session.history.has_achievement(PlayerHistory.OBSERVER), "a day of following, but not of one person")
	session.clock.tick = 1400 + 1440
	await wait_frames(2)
	assert_true(session.history.has_achievement(PlayerHistory.OBSERVER))


func test_version_7_save_gains_a_day_log() -> void:
	# Written by M6.3 (a22432e): a morning lived, three people touched. There
	# was no day log and nobody counted how long anyone was followed.
	assert_true(FileAccess.file_exists(V7_FIXTURE), "fixture present")
	var dir := SaveManager.world_dir(V7_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V7_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 7)
	var loaded := SaveManager.load_world(V7_ID)
	assert_true(loaded.ok, loaded.error)
	assert_eq(loaded.world["world_state"]["day_log"], {"logs": {}}, "the migration gives it empty pages")
	assert_eq(loaded.world["world_state"]["observer"], {})
	var s := WorldSession.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	s.loose_system.set_process(false)
	s.water.set_process(false)
	assert_eq(s.people.size(), 8)
	assert_eq(s.clock.tick, 253)
	assert_eq(s.day_log.entry_count(), 0, "what they did before is not known")
	assert_eq(s.observer.person_id, 0)
	assert_eq(s.history.people_touched(), 3, "nothing else was lost")
	assert_eq(s.memories.size(), 4)
	var someone := s.people.all_people()[0]
	assert_eq(PersonCard.facts(s, someone)["today"], "Nothing yet")
	# They go on living, and from now on it is written down.
	for i in 240:
		s.clock.advance(0.25)
		s.behavior.step(0.5)
		s.pathfinder.serve(1_000_000)
		s.movement.step(0.5)
	assert_true(s.day_log.entry_count() >= s.people.size(), "%d entries" % s.day_log.entry_count())
	assert_eq(s.day_log.people_count(), s.people.size())
	# Saved again: the current version, the old file kept; and read back the same.
	assert_true(SaveManager.save_world(s, &"test"))
	assert_eq(SaveManager.SAVE_VERSION, 8)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 8)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav.bak1")).header["save_version"], 7)
	var again := SaveManager.load_world(V7_ID)
	assert_true(again.ok, again.error)
	var s2 := WorldSession.new()
	add_child(s2)
	assert_true(s2.load_from(again.world))
	s2.set_process(false)
	for p in s.people.all_people():
		assert_eq(s2.day_log.of(p.id), s.day_log.of(p.id))
	s.queue_free()
	s2.queue_free()
	# The step by itself: only a world that has a state gets pages.
	assert_eq(SaveMigrations._v7_to_v8({"world": {"world_state": {}}})["world"]["world_state"], {})
	assert_eq(SaveMigrations._v7_to_v8({"settings": {}}), {"settings": {}})
	var kept: Dictionary = SaveMigrations._v7_to_v8({"world": {"world_state": {"people": {}, "day_log": {"logs": {3: []}}}}})
	assert_eq(kept["world"]["world_state"]["day_log"], {"logs": {3: []}}, "what is there is left alone")
	assert_eq(kept["world"]["world_state"]["observer"], {})
