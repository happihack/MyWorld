extends TestCase
## The ☰ menu v0 (VS.1, bible §26.5): WORLD (Weather), PEOPLE, HISTORY
## (Timeline, with Locate), PLAYER (Interaction History) and SETTINGS (Audio,
## Haptics, Save); what is not there yet stays hidden.

var main: Node
var ui: UIRoot
var session: WorldSession


func before_each() -> void:
	AudioManager.ensure_sounds()
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
	session = main.get_node("WorldSession")
	session.clock.set_speed(0)


func after_each() -> void:
	ui.close_all_panels()
	Settings.reset_to_defaults()
	await wait_frames(2)


func test_the_sections_of_the_menu() -> void:
	var menu := ui.open_menu()
	await wait_frames(1)
	var said := menu.texts()
	var order: Array[int] = []
	for section in ["WORLD", "PEOPLE", "HISTORY", "PLAYER", "SETTINGS"]:
		assert_true(said.has(section), section)
		order.append(said.find(section))
	var sorted := order.duplicate()
	sorted.sort()
	assert_eq(order, sorted, "in the bible's order")
	for entry in ["Map", "Weather", "Statistics", "Individuals", "Timeline", "Interaction History", "Audio", "Haptics", "Save"]:
		assert_true(said.has(entry), entry)
	assert_false(said.has("CIVILIZATION"), "not there yet: hidden")
	# HISTORY's events: the timeline, whose events a tap looks for.
	_entry_named(menu, "Timeline").pressed.emit()
	await wait_frames(2)
	assert_not_null(ui.timeline())
	# PLAYER: what the player has done, with its counts.
	ui.open_menu()
	await wait_frames(1)
	_entry_named(ui.main_menu(), "Interaction History").pressed.emit()
	await wait_frames(2)
	assert_null(ui.main_menu())


func test_the_weather_page() -> void:
	var menu := ui.open_menu()
	_entry_named(menu, "Weather").pressed.emit()
	await wait_frames(1)
	assert_eq(menu.page(), MainMenu.PAGE_WEATHER)
	assert_eq(menu.title_text(), "Weather")
	var said := menu.texts()
	assert_eq(said[0], session.clock.format_date(false))
	assert_eq(said[1], "Now: " + UIText.weather_line(session.weather.state, session.weather.temperature(session.clock.tick)))
	assert_true(said[-1].begins_with("Rain fell on") or said[-1].begins_with("No rain"), said[-1])
	# What is going on is said: a drought, frozen ground.
	session.weather._conditions[WeatherSystem.DROUGHT] = true
	session.weather.frozen = true
	var lines := MainMenu.weather_lines(session)
	assert_true(lines.has("A drought: it has hardly rained for days"))
	assert_true(lines.has("The ground is frozen"))
	session.weather._conditions.erase(WeatherSystem.DROUGHT)
	session.weather.frozen = false


func test_audio_and_haptics() -> void:
	var menu := ui.open_menu()
	_entry_named(menu, "Audio").pressed.emit()
	await wait_frames(1)
	assert_eq(menu.page(), MainMenu.PAGE_AUDIO)
	assert_eq(_volume_buttons(menu, "All sound").size(), 2, "a volume with - and +")
	# Sound off and on again.
	_entry_named(menu, "Sound: On").pressed.emit()
	await wait_frames(1)
	assert_true(bool(Settings.get_value(&"audio/muted")))
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master")), "silent")
	assert_not_null(_entry_named(menu, "Sound: Off"))
	_entry_named(menu, "Sound: Off").pressed.emit()
	await wait_frames(1)
	assert_false(bool(Settings.get_value(&"audio/muted")))
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master")))
	# A volume a step down, and not above full.
	var buttons := _volume_buttons(menu, "The world around")
	buttons[0].pressed.emit()
	await wait_frames(1)
	assert_near(float(Settings.get_value(&"audio/ambience")), 0.9)
	buttons = _volume_buttons(menu, "The world around")
	buttons[1].pressed.emit()
	await wait_frames(1)
	buttons = _volume_buttons(menu, "The world around")
	buttons[1].pressed.emit()
	await wait_frames(1)
	assert_near(float(Settings.get_value(&"audio/ambience")), 1.0)
	# Haptics: vibration off.
	menu.back()
	_entry_named(menu, "Haptics").pressed.emit()
	await wait_frames(1)
	assert_eq(menu.page(), MainMenu.PAGE_HAPTICS)
	_entry_named(menu, "Vibration: On").pressed.emit()
	await wait_frames(1)
	assert_false(bool(Settings.get_value(&"haptics/enabled")))
	assert_false(Haptics.enabled, "no more pulses")
	assert_not_null(_entry_named(menu, "Vibration: Off"))


func test_the_save_page() -> void:
	var menu := ui.open_menu()
	_entry_named(menu, "Save").pressed.emit()
	await wait_frames(1)
	assert_eq(menu.page(), MainMenu.PAGE_SAVE)
	assert_true(menu.texts()[1].begins_with("The world saves itself every 2 minutes"), menu.texts()[1])
	_entry_named(menu, "Save now").pressed.emit()
	await wait_frames(1)
	assert_eq(SaveManager.last_save_info.get("reason"), &"menu")
	assert_eq(menu.texts()[0], "Saved just now")
	assert_true(FileAccess.file_exists(SaveManager.world_dir(session.world_id).path_join(SaveManager.SAVE_FILE)))
	# In words.
	assert_eq(MainMenu.saved_text({}, 1000), "Not saved yet")
	assert_eq(MainMenu.saved_text({"unix": 1000}, 1030), "Saved just now")
	assert_eq(MainMenu.saved_text({"unix": 1000}, 1000 + 150), "Saved 2 min ago")
	assert_eq(MainMenu.saved_text({"unix": 1000}, 1000 + 7300), "Saved 2 h ago")
	assert_eq(MainMenu.saved_text({"error": "disk full"}, 1000), "The last save failed")


func _entry_named(menu: MainMenu, text: String) -> Button:
	for entry in menu.entries():
		if entry.text == text:
			return entry
	fail("no entry %s in %s" % [text, menu.texts()])
	return null


## The − and + of a volume on the Audio page.
func _volume_buttons(menu: MainMenu, label_text: String) -> Array[Button]:
	var out: Array[Button] = []
	for label: Label in menu.find_children("*", "Label", true, false):
		if label.text == label_text and not label.get_parent().is_queued_for_deletion():
			for child in label.get_parent().get_children():
				if child is Button:
					out.append(child)
	return out
