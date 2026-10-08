extends TestCase
## Each day is lived once (2026-10-08). The systems the people's own step
## brings up to the clock — lifecycle, relationships, culture, governance,
## the animals — were also brought up to a moment staggered behind it each
## frame (advance_systems), and they took turns at "today" and "yesterday" for
## the first minutes of every day: each time back to yesterday, then today
## lived again — a day's births, deaths and accidents thrown over and over.
## Worlds watched on the phone dwindled; the soaks, which never call
## advance_systems, did not.

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var session: WorldSession


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(4242)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


func test_a_day_is_lived_once() -> void:
	var watched := {"lifecycle": session.lifecycle, "relationships": session.relationships, "culture": session.culture,
		"governance": session.governance, "fauna": session.fauna}
	var minute := Config.time.real_seconds_per_game_minute
	var frame := Config.time.max_frame_delta_s
	var last := {}
	var went_back := []
	# Two midnights, minute by minute, as the game steps (people, then the rest).
	for i in 2 * 1440 + 120:
		var seconds := minute
		while seconds > 0.000001:
			var piece := minf(seconds, frame)
			session.clock.advance(piece)
			seconds -= piece
		session.behavior.step(1.0)
		_look(watched, last, went_back, i)
		session.pathfinder.serve(1_000_000)
		session.movement.step(1.0)
		session.advance_systems()
		_look(watched, last, went_back, i)
	assert_eq(went_back.slice(0, 5), [], "no system goes back a day (%d times)" % went_back.size())
	for name: String in watched:
		assert_eq(int(last[name]), Config.time.day_index(session.clock.tick), "%s is up to today" % name)


## Has any of them gone back a day since it was last looked at?
static func _look(watched: Dictionary, last: Dictionary, went_back: Array, minute: int) -> void:
	for name: String in watched:
		var day := int(watched[name].get("_day"))
		if last.has(name) and day < int(last[name]):
			went_back.append("%s at minute %d: day %d after %d" % [name, minute, day, last[name]])
		last[name] = day
