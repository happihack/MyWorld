extends TestCase
## The blessings the player gives (the owner and Josh, 2026-10-16; the
## plan's BLESSINGS section): the other hand of the Presence. One at a time
## with the disasters and the one rest after either; the lights in the sky
## come and go, harm nobody, are noticed, written down, and kept with the
## world while they last.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440

var session: WorldSession
var blessings: BlessingSystem
var disasters: DisasterSystem
var clock: GameClock
var stimuli: Array[Stimulus] = []


func before_each() -> void:
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	session.behavior.enabled = false
	blessings = session.blessings
	disasters = session.disasters
	clock = session.clock
	stimuli.clear()
	session.interactions.stimulus_emitted.connect(func(stimulus: Stimulus) -> void: stimuli.append(stimulus))


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


func _fire() -> Vector2:
	return session.settlement.fire().position2d()


## The clock moves on `minutes`, and both hands with it.
func _pass(minutes: int) -> void:
	clock.tick += minutes
	disasters.advance_to(clock.tick)
	blessings.advance_to(clock.tick)


func test_one_act_a_day_whichever_hand() -> void:
	assert_eq(BlessingSystem.KINDS, [BlessingSystem.LIGHTS] as Array[StringName], "the first cut's first")
	assert_true(bool(Settings.get_value(&"gameplay/gentle_hands")), "gentle hands are on")
	var iv := session.interactions.bless(BlessingSystem.LIGHTS, _fire())
	assert_true(iv.applied, "asked for and confirmed: not held back by gentle hands (%s)" % iv.rejected)
	assert_eq(iv.severity, Intervention.Severity.MAJOR)
	assert_eq(session.history.count(Intervention.BLESSING, BlessingSystem.LIGHTS), 1, "in the player's history")
	assert_true(blessings.is_active())
	# Neither hand while the other is busy.
	assert_false(session.interactions.bless(BlessingSystem.LIGHTS, _fire()).applied, "one at a time")
	var curse := session.interactions.disaster(DisasterSystem.ECLIPSE, _fire())
	assert_false(curse.applied, "no disaster while a blessing goes on")
	assert_eq(curse.rejected, &"resting")
	assert_false(disasters.can_start(clock.tick))
	assert_eq(disasters.rest_left(clock.tick), blessings.rest_left(clock.tick), "the one rest, seen from either button")
	_pass(int(BlessingSystem.LASTS[BlessingSystem.LIGHTS]))
	assert_false(blessings.is_active(), "over")
	assert_false(blessings.can_start(clock.tick), "the world rests")
	assert_false(disasters.can_start(clock.tick), "from a disaster too: the one rest")
	assert_eq(blessings.rest_left(clock.tick), BlessingSystem.REST_MINUTES)
	assert_eq(disasters.rest_left(clock.tick), DisasterSystem.REST_MINUTES)
	_pass(BlessingSystem.REST_MINUTES)
	assert_true(blessings.can_start(clock.tick), "a day later, either")
	assert_true(disasters.can_start(clock.tick))
	assert_false(session.interactions.bless(&"plague", _fire()).applied, "no such blessing")
	# And after a disaster, no blessing until the world has rested.
	assert_true(session.interactions.disaster(DisasterSystem.ECLIPSE, _fire()).applied)
	assert_false(session.interactions.bless(BlessingSystem.LIGHTS, _fire()).applied, "no blessing while a disaster goes on")
	_pass(int(DisasterSystem.LASTS[DisasterSystem.ECLIPSE]))
	assert_false(blessings.can_start(clock.tick), "the rest after a disaster holds the blessings too")
	_pass(DisasterSystem.REST_MINUTES)
	assert_true(blessings.can_start(clock.tick))


func test_the_lights_come_and_go_and_harm_nobody() -> void:
	var living := session.people.size()
	var trees := 0
	for prop in session.props.all_props():
		if prop.kind == PropData.Kind.TREE and not prop.felled:
			trees += 1
	assert_true(session.interactions.bless(BlessingSystem.LIGHTS, _fire()).applied)
	assert_eq(blessings.lights_amount(clock.tick), 0.0, "they come")
	_pass(35)
	assert_near(blessings.lights_amount(clock.tick), 1.0, 0.01, "the sky is full of them")
	assert_true(stimuli.any(func(s: Stimulus) -> bool: return s.type == Stimulus.LIGHTS_IN_SKY and s.anomalous and s.large),
		"noticed, everywhere")
	_pass(40)
	assert_eq(blessings.lights_amount(clock.tick), 0.0, "and go")
	assert_false(blessings.is_active())
	assert_eq(session.people.size(), living)
	var after := 0
	for prop in session.props.all_props():
		if prop.kind == PropData.Kind.TREE and not prop.felled:
			after += 1
	assert_eq(after, trees)
	assert_eq(session.events.of_type(&"lights_in_sky").size(), 1, "written down")


func test_kept_with_the_world_while_it_lasts() -> void:
	var before := SaveManager.save_world(session, &"test")
	assert_true(before)
	var pristine := SaveManager.last_save_info["bytes"] as int
	assert_true(session.interactions.bless(BlessingSystem.LIGHTS, _fire()).applied)
	_pass(10)
	assert_true(SaveManager.save_world(session, &"test"))
	assert_true(SaveManager.last_save_info["bytes"] > pristine, "a blessing going on is saved")
	var loaded := SaveManager.load_world(session.world_id)
	assert_true(loaded.ok, loaded.error)
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(loaded.world))
	again.set_process(false)
	assert_eq(again.blessings.kind, BlessingSystem.LIGHTS, "still going on")
	assert_eq(again.blessings.until, blessings.until)
	assert_false(again.disasters.can_start(again.clock.tick), "and the disasters know it")
	again.clock.tick = blessings.until
	again.blessings.advance_to(again.clock.tick)
	assert_false(again.blessings.is_active())
	assert_eq(again.disasters.rest_until, blessings.until + BlessingSystem.REST_MINUTES, "the one rest, kept by the disasters")
	# Once over, the save carries nothing of it.
	assert_true(SaveManager.save_world(again, &"test"))
	var state: Dictionary = again.to_dict()["world_state"]
	assert_false(state.has("blessings"), "nothing to save of a blessing that is over")
	again.queue_free()


func test_it_goes_on_while_away() -> void:
	assert_true(session.interactions.bless(BlessingSystem.LIGHTS, _fire()).applied)
	var until := blessings.until
	# The session's own step brings it up to the clock (as it does while the game runs).
	clock.tick = until + 5
	session.advance_systems()
	assert_false(blessings.is_active(), "over, by the clock")
	assert_eq(disasters.rest_until, until + BlessingSystem.REST_MINUTES)
