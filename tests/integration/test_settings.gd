extends TestCase
## Settings run against the runner's isolated file (user://test_run_<pid>/settings.cfg).


func before_each() -> void:
	Settings.reset_to_defaults()
	Settings.flush()


func test_defaults() -> void:
	assert_eq(Settings.get_value(&"haptics/enabled"), true)
	assert_eq(Settings.get_value(&"gameplay/gentle_hands"), true)
	assert_eq(Settings.get_value(&"debug/overlay_visible"), false)


func test_runner_isolated_the_settings_file() -> void:
	assert_has(Settings.path, "test_run")


func test_coercion_and_rejection() -> void:
	assert_true(Settings.set_value(&"audio/master", 1))
	assert_eq(typeof(Settings.get_value(&"audio/master")), TYPE_FLOAT)
	assert_false(Settings.set_value(&"audio/master", "loud"))
	assert_false(Settings.set_value(&"nope/key", 1))
	assert_null(Settings.get_value(&"nope/key"))


func test_changed_signal_only_on_real_change() -> void:
	var changed := []
	var cb := func(k: StringName, _v: Variant) -> void: changed.append(k)
	Settings.setting_changed.connect(cb)
	Settings.set_value(&"audio/master", 0.4)
	Settings.set_value(&"audio/master", 0.4)
	Settings.set_value(&"motion/baseline_gravity", Vector3(0, -9.8, 0.3))
	Settings.setting_changed.disconnect(cb)
	assert_eq(changed, [&"audio/master", &"motion/baseline_gravity"])


func test_persist_overwrite_and_reload() -> void:
	Settings.set_value(&"audio/master", 0.4)
	Settings.flush()
	Settings.set_value(&"audio/master", 0.7)
	Settings.set_value(&"motion/baseline_gravity", Vector3(0, -9.8, 0.3))
	Settings.flush() # must replace the existing file
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(Settings.path), OK)
	assert_near(cfg.get_value("audio", "master"), 0.7)
	Settings.use_path(Settings.path) # reload from disk
	assert_near(Settings.get_value(&"audio/master"), 0.7)
	assert_eq(Settings.get_value(&"motion/baseline_gravity"), Vector3(0, -9.8, 0.3))


func test_debounced_save_happens() -> void:
	Settings.set_value(&"audio/sfx", 0.25)
	await wait_seconds(Settings.SAVE_DEBOUNCE_S + 0.2)
	var cfg := ConfigFile.new()
	cfg.load(Settings.path)
	assert_near(cfg.get_value("audio", "sfx", -1.0), 0.25)


func test_invalid_saved_values_ignored() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", "not a number")
	cfg.set_value("haptics", "enabled", false)
	cfg.save(Settings.path)
	Settings.use_path(Settings.path)
	assert_near(Settings.get_value(&"audio/master"), 1.0, 0.0001, "bad type falls back to default")
	assert_eq(Settings.get_value(&"haptics/enabled"), false)
