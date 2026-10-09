extends TestCase
## A plan that ends the moment it begins, chosen again and again in the same
## moment, used to go round set_plan → _carry_on → _finish → _think → set_plan
## until the engine's stack broke ("Stack underflow", soaks of 2026-10-08/09).
## Past BehaviorSystem.INSTANT_PLANS_MOST in one moment, the person rests a minute.

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var session: WorldSession


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


func test_plans_ending_as_they_begin_are_stopped() -> void:
	var behavior := session.behavior
	var person := session.people.all_people()[0]
	# A plan whose only step is done at once: a walk to where they stand.
	for i in BehaviorSystem.INSTANT_PLANS_MOST + 3:
		behavior.set_plan(person, &"wander", &"test", [WalkToStep.make(person.position, person.sub_tile_offset)])
		if behavior.instant_loops_stopped > 0:
			break
	assert_true(behavior.instant_loops_stopped >= 1, "stopped (%d)" % behavior.instant_loops_stopped)
	assert_eq(BehaviorSystem.activity_of(person), BehaviorSystem.ACTIVITY_IDLE, "a minute's rest")
	assert_eq(str(person.current_action.get("steps", [{}])[0].get("type", "")), String(RestStep.TYPE))
	# A minute on, they choose again as ever.
	session.clock.tick += 2
	behavior.step(2.0)
	assert_ne(BehaviorSystem.activity_of(person), &"", "doing something")


func test_listening_to_nobody_fails() -> void:
	# (The loop the soaks found: going to listen by the fire when nobody is
	# telling ended "done" at once, and was chosen again at once.)
	var step := FireStoryStep.listen(0, 30.0)
	var handler := FireStoryStep.new()
	var person := session.people.all_people()[0]
	assert_eq(handler.update(session.behavior.ctx, person, step, 0.0), ActionStep.Status.FAILED, "no story: failed (put aside a while)")
