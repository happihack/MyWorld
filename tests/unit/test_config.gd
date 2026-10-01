extends TestCase


func test_loaded_without_problems() -> void:
	assert_eq(Config.problems.size(), 0, str(Config.problems))


func test_time_defaults() -> void:
	assert_eq(Config.time.days_per_year(), 24)
	assert_near(Config.time.real_seconds_per_game_minute, 0.5)
	assert_eq(Config.time.speed_multipliers, PackedFloat32Array([0, 1, 4, 16]))


func test_world_and_interaction_defaults() -> void:
	assert_eq(Config.world.chunk_size, 16)
	assert_eq(Config.world.initial_world_tiles, 64)
	assert_eq(Config.interaction.long_press_ms, 450)
	assert_eq(Config.interaction.grab_hold_ms, 200)
	var bad := InteractionConfig.new()
	bad.grab_hold_ms = 900
	assert_eq(bad.validate().size(), 1, "grabbing must come before the long press")


func test_people_defaults() -> void:
	assert_eq(Config.time.ticks_per_year(), 24 * 1440)
	assert_eq(Config.people.band_min_people, 6)
	assert_eq(Config.people.band_max_people, 8)
	assert_eq(Config.people.stage_for_age(0), PersonData.LifeStage.CHILD)
	assert_eq(Config.people.stage_for_age(12), PersonData.LifeStage.ADOLESCENT)
	assert_eq(Config.people.stage_for_age(16), PersonData.LifeStage.ADULT)
	assert_eq(Config.people.stage_for_age(48), PersonData.LifeStage.ELDER)
	var bad := PeopleConfig.new()
	bad.adult_from_years = 10
	bad.band_min_people = 9
	assert_eq(bad.validate().size(), 2)


func test_validate_catches_bad_values() -> void:
	var w := WorldConfig.new()
	w.initial_world_tiles = 70
	assert_eq(w.validate().size(), 1)
	var t := TimeConfig.new()
	t.speed_multipliers = PackedFloat32Array([1, 2])
	assert_true(t.validate().size() >= 2, "wrong count and non-zero pause")
	var s := SaveConfig.new()
	s.backup_count = 0
	s.save_root = "res://nope"
	assert_eq(s.validate().size(), 2)


func test_all_default_configs_valid() -> void:
	for cfg: ConfigBase in [TimeConfig.new(), WorldConfig.new(), SaveConfig.new(), InteractionConfig.new(), PerfConfig.new(), FeedbackConfig.new(), PeopleConfig.new(), NeedsConfig.new()]:
		assert_eq(cfg.validate().size(), 0, cfg.get_script().resource_path)
