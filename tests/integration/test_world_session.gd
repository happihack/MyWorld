extends TestCase

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var sessions: Array[WorldSession] = []


func after_each() -> void:
	for s in sessions:
		if is_instance_valid(s):
			s.queue_free()
	sessions.clear()
	await wait_frames(1)


func _new_session() -> WorldSession:
	var s: WorldSession = SessionScript.new()
	add_child(s)
	sessions.append(s)
	return s


func _advance_ticks(s: WorldSession, ticks: int) -> void:
	for i in ticks * 2:
		s.clock.advance(0.25)


func test_create_new_with_seed() -> void:
	var s := _new_session()
	s.create_new(777)
	assert_true(s.is_active)
	assert_eq(s.world_seed, 777)
	assert_true(s.world_id.begins_with("w"))


func test_random_seed_when_zero() -> void:
	var s := _new_session()
	s.create_new()
	assert_true(s.world_seed > 0)


func test_roundtrip_restores_state_and_rng() -> void:
	var s := _new_session()
	s.create_new(777)
	_advance_ticks(s, 2)
	s.ids.next_id()
	s.rng.stream(&"terrain").randi()
	s.clock.set_speed(GameClock.SPEED_FAST)
	var data := s.to_dict()
	var expected_next := s.rng.stream(&"terrain").randi()
	var s2 := _new_session()
	assert_true(s2.load_from(data))
	assert_eq(s2.world_id, s.world_id)
	assert_eq(s2.clock.tick, 2)
	assert_eq(s2.clock.speed_index, GameClock.SPEED_FAST)
	assert_eq(s2.ids.peek(), 2)
	assert_eq(s2.rng.stream(&"terrain").randi(), expected_next)


func test_missing_key_rejected_and_inactive() -> void:
	var s := _new_session()
	s.create_new(1)
	var broken := s.to_dict()
	broken.erase("clock")
	var s2 := _new_session()
	assert_false(s2.load_from(broken))
	assert_false(s2.is_active)


func test_unique_world_ids_for_same_seed() -> void:
	var a := _new_session()
	var b := _new_session()
	a.create_new(5)
	b.create_new(5)
	assert_ne(a.world_id, b.world_id)


func test_signals_and_idempotent_shutdown() -> void:
	var events := []
	var on_loaded := func(_id: String) -> void: events.append("loaded")
	var on_unloaded := func() -> void: events.append("unloaded")
	var on_speed := func(i: int) -> void: events.append("speed%d" % i)
	EventBus.world_loaded.connect(on_loaded)
	EventBus.world_unloaded.connect(on_unloaded)
	EventBus.sim_speed_changed.connect(on_speed)
	var s := _new_session()
	var closing := [0]
	s.create_new(3)
	s.about_to_close.connect(func() -> void: closing[0] += 1)
	s.clock.set_speed(GameClock.SPEED_FAST)
	s.shutdown()
	s.shutdown()
	EventBus.world_loaded.disconnect(on_loaded)
	EventBus.world_unloaded.disconnect(on_unloaded)
	EventBus.sim_speed_changed.disconnect(on_speed)
	assert_eq(events, ["loaded", "speed2", "unloaded"])
	assert_eq(closing[0], 1, "about_to_close once, while still active")


func test_freeing_session_shuts_it_down() -> void:
	var s := _new_session()
	s.create_new(9)
	var unloaded := [false]
	var cb := func() -> void: unloaded[0] = true
	EventBus.world_unloaded.connect(cb)
	s.queue_free()
	await wait_frames(1)
	EventBus.world_unloaded.disconnect(cb)
	assert_true(unloaded[0])


func test_clock_advances_in_tree() -> void:
	var s := _new_session()
	s.create_new(4)
	await wait_seconds(1.2)
	assert_true(s.clock.tick >= 2, "tick %d" % s.clock.tick)
