extends TestCase

var clock: GameClock


func before_each() -> void:
	clock = GameClock.new(Config.time)


func test_half_second_is_one_tick_at_normal() -> void:
	assert_eq(clock.advance(0.25), 0)
	assert_eq(clock.advance(0.25), 1)
	assert_eq(clock.tick, 1)


func test_partial_ticks_accumulate() -> void:
	clock.advance(0.1)
	assert_near(clock.tick_fraction(), 0.2)


func test_large_delta_is_clamped() -> void:
	assert_eq(clock.advance(10.0), 0)
	assert_near(clock.tick_fraction(), 0.5) # 0.25 s max -> half a tick


func test_pause_and_speeds() -> void:
	var seen := []
	clock.speed_changed.connect(func(i: int) -> void: seen.append(i))
	clock.set_speed(GameClock.SPEED_PAUSE)
	assert_true(clock.is_paused())
	assert_eq(clock.advance(0.25), 0)
	clock.set_speed(GameClock.SPEED_FAST)
	assert_eq(clock.advance(0.25), 2)
	clock.set_speed(99)
	assert_eq(clock.speed_index, GameClock.SPEED_VERY_FAST)
	clock.set_speed(GameClock.SPEED_VERY_FAST) # no change -> no signal
	assert_eq(seen, [0, 2, 3])


func test_roundtrip() -> void:
	clock.set_speed(GameClock.SPEED_FAST)
	clock.advance(0.2)
	var copy := GameClock.new(Config.time)
	copy.from_dict(clock.to_dict())
	assert_eq(copy.tick, clock.tick)
	assert_eq(copy.speed_index, clock.speed_index)
	assert_near(copy.tick_fraction(), clock.tick_fraction())


func test_corrupt_data_sanitized() -> void:
	clock.from_dict({"tick": -5, "speed_index": 42, "accumulator": 7.0})
	assert_eq(clock.tick, 0)
	assert_eq(clock.speed_index, GameClock.SPEED_VERY_FAST)
	assert_true(clock.tick_fraction() < 1.0)
