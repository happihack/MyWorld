extends TestCase


func test_signal_round_trip() -> void:
	var got := []
	var cb := func(id: int) -> void: got.append(id)
	EventBus.person_born.connect(cb)
	EventBus.person_born.emit(42)
	EventBus.person_born.disconnect(cb)
	assert_eq(got, [42])


func test_catalogue_present() -> void:
	for s in ["world_loaded", "world_unloaded", "person_born", "person_died", "intervention_applied",
			"save_completed", "save_failed", "load_failed", "app_paused", "app_resumed",
			"app_quit_requested", "back_requested", "sim_speed_changed", "major_event_occurred"]:
		assert_true(EventBus.has_signal(s), s)
