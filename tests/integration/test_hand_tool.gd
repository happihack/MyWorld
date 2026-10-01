extends TestCase
## The hand tool: grabbing, carrying and dropping loose objects, on a real
## generated world with a real view and camera (no Main scene).

const ViewScript := preload("res://scripts/rendering/world_view.gd")
const SessionScript := preload("res://scripts/simulation/world_session.gd")
const VIEW := Vector2(1080, 1920)

var session: WorldSession
var view: WorldView
var rig: CameraRig
var tools: ToolManager
var hand: HandTool
var pulses: Array = []
var landings: Array = []
var _real_vibrate: Callable


func before_each() -> void:
	AudioManager.ensure_sounds()
	_real_vibrate = Haptics.vibrate_action
	pulses.clear()
	Haptics.vibrate_action = func(ms: int, _amplitude: float) -> void: pulses.append(ms)
	Haptics.reset()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.loose_system.set_process(false) # tests step time themselves
	view = ViewScript.new()
	add_child(view)
	view.show_world(session.world, session.props, session.start, session.loose)
	rig = view.camera_rig()
	rig.set_process(false)
	rig.set_view_size(VIEW)
	var context := ToolBase.Context.new()
	context.session = session
	context.view = view
	context.touch_radius = 60.0
	tools = ToolManager.new()
	add_child(tools)
	tools.set_process(false)
	tools.setup(context)
	hand = tools.current() as HandTool
	landings.clear()
	session.loose_system.landed.connect(func(id: int, speed: float) -> void: landings.append([id, speed]))


func after_each() -> void:
	Haptics.vibrate_action = _real_vibrate
	tools.queue_free()
	view.queue_free()
	session.queue_free()
	await wait_frames(1)


func _nearest(kind: LooseObject.Kind) -> LooseObject:
	var best: LooseObject = null
	var best_distance := INF
	for o in session.loose.all_objects():
		var d := o.position.distance_to(Vector2(session.start.settlement_tile))
		if o.kind == kind and d < best_distance:
			best_distance = d
			best = o
	return best


func _look_at(xz: Vector2, distance: float = 12.0) -> void:
	rig.focus_on(Vector3(xz.x, 0, xz.y), distance, false)
	for i in 120:
		rig.advance(1.0 / 60.0)


func _screen_of(object: LooseObject) -> Vector2:
	return rig.world_to_screen(object.world_position(session.world) + Vector3(0, object.height() * 0.5, 0))


func _ground_screen(xz: Vector2) -> Vector2:
	var tile := WorldCoords.world2d_to_tile(xz)
	return rig.world_to_screen(Vector3(xz.x, session.world.get_height(tile) * session.world.height_step, xz.y))


func _gesture(type: Gesture.Type, at: Vector2 = Vector2.ZERO) -> Gesture:
	var g := Gesture.new(type)
	g.position = at
	return g


## Lets time pass for the tool and the falling objects.
func _run(seconds: float) -> void:
	var steps := int(seconds * 60.0)
	for i in steps:
		hand.update(1.0 / 60.0)
		session.loose_system.step(1.0 / 60.0)


## Grabs `object` as a resting finger would.
func _grab(object: LooseObject) -> bool:
	_look_at(object.position)
	return tools.handle_gesture(_gesture(Gesture.Type.HOLD, _screen_of(object)))


func _drag_to(screen: Vector2) -> void:
	tools.handle_gesture(_gesture(Gesture.Type.DRAG_START, screen))
	tools.handle_gesture(_gesture(Gesture.Type.DRAG, screen))


# --- grabbing -------------------------------------------------------------------------------

func test_resting_a_finger_on_a_rock_picks_it_up() -> void:
	var rock := _nearest(LooseObject.Kind.ROCK)
	assert_true(_grab(rock), "the hold is kept by the tool")
	assert_true(hand.is_busy())
	assert_eq(hand.held_id(), rock.id)
	assert_eq(rock.state, LooseObject.State.HELD)
	assert_eq(pulses, [Config.feedback.haptic_light_ms], "a light tick on pick-up")
	assert_eq(AudioManager.last_sound, &"click")
	var at := rock.position
	_run(0.5)
	assert_near(rock.height_offset, HandTool.hover_height(rock), 0.01, "lifted to hover height")
	assert_eq(rock.position, at, "but not moved sideways until the finger moves")
	# The picture follows, with a soft shadow on the ground below.
	var shown := view.loose_view()
	assert_near(shown.object_transform(rock.id).origin.y,
		session.world.get_height(rock.tile()) * session.world.height_step + rock.height_offset, 0.0001)
	assert_eq(shown.drop_shadow_id(), rock.id)
	assert_near(shown.drop_shadow_position().x, rock.position.x, 0.0001)


func test_only_loose_things_can_be_picked_up() -> void:
	var hut := session.props.get_prop(session.start.hut_ids[0])
	_look_at(hut.position2d())
	var roof := rig.world_to_screen(Vector3(hut.position2d().x, session.world.get_height(hut.tile) * session.world.height_step + 0.7, hut.position2d().y))
	assert_false(tools.handle_gesture(_gesture(Gesture.Type.HOLD, roof)), "huts stay where they are")
	var glade := Vector2(session.start.settlement_tile) + Vector2(1.5, 0.5)
	assert_false(tools.handle_gesture(_gesture(Gesture.Type.HOLD, _ground_screen(glade))), "nothing there")
	assert_false(hand.is_busy())
	assert_eq(pulses.size(), 0)
	# A rock right beside a tree is still reachable: only loose things count.
	var rock := _nearest(LooseObject.Kind.ROCK)
	var tree := PropData.new()
	tree.id = session.ids.next_id()
	tree.kind = PropData.Kind.TREE
	tree.tile = rock.tile() + Vector2i(1, 0)
	if session.props.add(tree):
		assert_true(_grab(rock))


func test_gestures_pass_through_when_nothing_is_held() -> void:
	for type: Gesture.Type in [Gesture.Type.DRAG_START, Gesture.Type.DRAG, Gesture.Type.DRAG_END, Gesture.Type.TAP,
			Gesture.Type.LONG_PRESS, Gesture.Type.MULTI_START, Gesture.Type.PINCH, Gesture.Type.DOUBLE_TAP]:
		assert_false(tools.handle_gesture(_gesture(type, VIEW * 0.5)), Gesture.Type.keys()[type])


# --- carrying -------------------------------------------------------------------------------

func test_a_carried_rock_follows_the_finger() -> void:
	var rock := _nearest(LooseObject.Kind.ROCK)
	var from := rock.position
	assert_true(_grab(rock))
	_run(0.3)
	var target := from + Vector2(1.2, 0.5) # well inside the screen: no edge panning
	assert_eq(HandTool.edge_push(_ground_screen(target), VIEW, Config.interaction.edge_pan_margin), Vector2.ZERO)
	_drag_to(_ground_screen(target))
	assert_true(tools.handle_gesture(_gesture(Gesture.Type.DRAG, _ground_screen(target))), "the camera never sees a carrying drag")
	var pivot := rig.pivot()
	_run(1.0)
	assert_true(rock.position.distance_to(target) < 0.6, "arrived near the finger (%s vs %s)" % [rock.position, target])
	assert_eq(rock.state, LooseObject.State.HELD)
	assert_true(rock.height_offset > 0.2, "still in the air")
	assert_eq(rig.pivot(), pivot, "the view stays put in the middle of the screen")
	assert_eq(session.spatial.get_position(rock.id), rock.position, "the spatial index follows")


func test_a_boulder_is_slower_and_hangs_lower() -> void:
	var rock := _nearest(LooseObject.Kind.ROCK)
	var boulder := _nearest(LooseObject.Kind.BOULDER)
	assert_true(HandTool.carry_speed(boulder) < HandTool.carry_speed(rock) * 0.5)
	assert_true(HandTool.hover_height(boulder) < HandTool.hover_height(rock))
	assert_true(HandTool.hover_height(boulder) >= Config.interaction.carry_hover_height * 0.5)
	var from := boulder.position
	assert_true(_grab(boulder))
	assert_eq(pulses, [Config.feedback.haptic_medium_ms], "heavy: felt more")
	_run(0.3)
	_drag_to(_ground_screen(from + Vector2(4.0, 0.0)))
	_run(0.2)
	var moved := boulder.position.distance_to(from)
	assert_near(moved, HandTool.carry_speed(boulder) * 0.2, 0.15, "it lags behind the finger (%.2f tiles in 0.2 s)" % moved)


func test_carried_objects_stay_inside_the_box() -> void:
	var rock := _nearest(LooseObject.Kind.ROCK)
	assert_true(_grab(rock))
	_drag_to(Vector2(-4000, -4000))
	_run(3.0)
	_drag_to(Vector2(9000, 400))
	_run(3.0)
	var b := Rect2(session.world.bounds)
	assert_true(b.has_point(rock.position), "inside: %s" % rock.position)
	assert_true(is_finite(rock.position.x) and is_finite(rock.height_offset))


func test_a_carried_object_clears_higher_ground() -> void:
	var rock := _nearest(LooseObject.Kind.ROCK)
	assert_true(_grab(rock))
	_run(0.3)
	var wall := rock.tile() + Vector2i(1, 0)
	session.world.set_height(wall, session.world.get_height(rock.tile()) + 4)
	_drag_to(_ground_screen(Vector2(wall) + Vector2(0.5, 0.5)))
	for i in 90:
		hand.update(1.0 / 60.0)
		var ground := session.world.get_height(rock.tile()) * session.world.height_step
		assert_true(rock.height_offset >= HandTool.MIN_CLEARANCE - 0.001, "never inside the ground (step %d: %.2f over %.2f)" % [i, rock.height_offset, ground])
	session.world.set_height(wall, session.world.get_height(wall) - 4)


func test_carrying_to_the_screen_edge_pans_the_view() -> void:
	var rock := _nearest(LooseObject.Kind.ROCK)
	assert_true(_grab(rock))
	var before := rig.pivot()
	_drag_to(Vector2(VIEW.x - 10.0, VIEW.y * 0.5)) # right edge
	_run(0.5)
	assert_true(rig.pivot().x > before.x + 0.5, "the view moved toward the edge (%.2f -> %.2f)" % [before.x, rig.pivot().x])
	assert_near(rig.pivot().z, before.z, 0.3, "and only that way")
	assert_true(rock.position.x > session.start.settlement_tile.x - 20.0)


func test_edge_push() -> void:
	var m := 0.14
	assert_eq(HandTool.edge_push(VIEW * 0.5, VIEW, m), Vector2.ZERO, "nothing in the middle")
	assert_eq(HandTool.edge_push(Vector2(VIEW.x * 0.5, VIEW.y * 0.3), VIEW, m), Vector2.ZERO)
	var right := HandTool.edge_push(Vector2(VIEW.x, VIEW.y * 0.5), VIEW, m)
	assert_near(right.x, 1.0, 0.001)
	assert_near(right.y, 0.0, 0.001)
	var top := HandTool.edge_push(Vector2(VIEW.x * 0.5, 0.0), VIEW, m)
	assert_near(top.y, -1.0, 0.001)
	var half := HandTool.edge_push(Vector2(VIEW.x * m * 0.5, VIEW.y * 0.5), VIEW, m)
	assert_near(half.x, -0.5, 0.001, "gentler further in")
	assert_true(HandTool.edge_push(Vector2(0, 0), VIEW, m).length() <= 1.0001, "corners are not faster")
	assert_eq(HandTool.edge_push(Vector2(0, 0), VIEW, 0.0), Vector2.ZERO, "can be switched off")


# --- letting go -----------------------------------------------------------------------------

func test_letting_go_drops_the_rock_where_it_is() -> void:
	var rock := _nearest(LooseObject.Kind.ROCK)
	var from := rock.position
	assert_true(_grab(rock))
	_run(0.3)
	var target := from + Vector2(1.0, -0.6)
	_drag_to(_ground_screen(target))
	_run(1.0)
	assert_true(tools.handle_gesture(_gesture(Gesture.Type.DRAG_END, _ground_screen(target))))
	assert_false(hand.is_busy())
	assert_eq(rock.state, LooseObject.State.FALLING)
	_run(1.0)
	assert_eq(rock.state, LooseObject.State.RESTING)
	assert_near(rock.height_offset, 0.0, 0.0)
	assert_true(rock.position.distance_to(target) < 0.6)
	assert_eq(landings.size(), 1)
	assert_true(landings[0][1] > 2.0, "it hits the ground with some speed (%.1f)" % landings[0][1])
	assert_eq(view.loose_view().drop_shadow_id(), 0, "the drop shadow is gone")
	# The world remembers that the player moved it.
	assert_eq(session.history.count(Intervention.MOVE_OBJECT, &"rock"), 1, "in the player's history")
	assert_eq(session.history.entries()[-1]["tool"], "hand")
	assert_true(rock.discoverable, "and it lies where the settlement may find it")
	assert_eq(rock.moved_count, 1)
	assert_true(rock.placed_by_player)
	assert_eq(session.loose.saved_count(), 1, "a moved rock is saved")
	var record: Dictionary = session.to_dict()["world_state"]["loose"]["objects"][0]
	assert_eq(record["position"], rock.position)


func test_letting_go_while_moving_throws() -> void:
	var boulder := _nearest(LooseObject.Kind.BOULDER)
	var from := boulder.position
	assert_true(_grab(boulder))
	_run(0.3)
	# A boulder lags behind the finger, so it is still moving when let go.
	var target := from + Vector2(1.2, 0.5)
	_drag_to(_ground_screen(target))
	_run(0.12)
	var released_at := boulder.position
	var heading := (target - from).normalized()
	tools.handle_gesture(_gesture(Gesture.Type.DRAG_END, _ground_screen(target)))
	var thrown := Vector2(boulder.velocity.x, boulder.velocity.z)
	assert_true(thrown.length() > HandTool.THROW_MIN_SPEED, "it leaves the hand moving (%.2f tiles/s)" % thrown.length())
	assert_true(thrown.length() <= Config.interaction.throw_max_speed + 0.001)
	assert_true(thrown.normalized().dot(heading) > 0.9, "the way it was being carried")
	for i in 600:
		session.loose_system.step(1.0 / 60.0)
		if not session.loose_system.is_moving(boulder.id):
			break
	assert_eq(boulder.state, LooseObject.State.RESTING)
	assert_true((boulder.position - released_at).dot(heading) > 0.15, "and rolls on a little after landing (%.2f)" % (boulder.position - released_at).dot(heading))


func test_letting_go_after_stopping_just_sets_it_down() -> void:
	var rock := _nearest(LooseObject.Kind.ROCK)
	assert_true(_grab(rock))
	_run(0.3)
	var target := rock.position + Vector2(1.0, -0.6)
	_drag_to(_ground_screen(target))
	_run(1.5) # arrived, and the finger rests
	var at := rock.position
	tools.handle_gesture(_gesture(Gesture.Type.DRAG_END, _ground_screen(target)))
	assert_eq(rock.velocity, Vector3.ZERO, "no throw")
	_run(1.0)
	assert_eq(rock.position, at, "it lands right where it was held")


func test_putting_it_back_is_not_a_move() -> void:
	var rock := _nearest(LooseObject.Kind.ROCK)
	assert_true(_grab(rock))
	_run(0.3)
	# The finger lifts without having moved: the recognizer reports a tap.
	assert_true(tools.handle_gesture(_gesture(Gesture.Type.TAP, _screen_of(rock))), "that tap only lets go")
	_run(1.0)
	assert_eq(rock.state, LooseObject.State.RESTING)
	assert_eq(rock.moved_count, 0)
	assert_false(rock.placed_by_player)
	assert_eq(session.interactions.interaction_count, 0, "and is not a touch of the rock")
	assert_eq(session.history.total(), 0, "nothing for the history")


func test_holding_still_opens_the_menu_with_the_rock_still_in_hand() -> void:
	var rock := _nearest(LooseObject.Kind.ROCK)
	assert_true(_grab(rock))
	_run(0.2)
	assert_false(tools.handle_gesture(_gesture(Gesture.Type.LONG_PRESS, _screen_of(rock))), "the long press goes on to open the menu")
	assert_true(hand.is_busy(), "and the rock stays in hand")
	assert_eq(rock.state, LooseObject.State.HELD)
	# Lifting the finger now produces no gesture; the release itself lets go.
	tools.touch_ended()
	assert_false(hand.is_busy())
	_run(1.0)
	assert_eq(rock.state, LooseObject.State.RESTING, "the rock settles back")
	assert_eq(rock.moved_count, 0)


func test_dragging_after_a_long_hold_still_carries() -> void:
	var rock := _nearest(LooseObject.Kind.ROCK)
	var from := rock.position
	assert_true(_grab(rock))
	_run(0.3)
	tools.handle_gesture(_gesture(Gesture.Type.LONG_PRESS, _screen_of(rock)))
	_run(0.4) # the player takes their time
	var target := from + Vector2(1.2, 0.5)
	assert_true(tools.handle_gesture(_gesture(Gesture.Type.DRAG_START, _ground_screen(target))), "still a carry, not a pan")
	tools.handle_gesture(_gesture(Gesture.Type.DRAG, _ground_screen(target)))
	_run(1.0)
	assert_true(rock.position.distance_to(target) < 0.6)
	tools.handle_gesture(_gesture(Gesture.Type.DRAG_END, _ground_screen(target)))
	tools.touch_ended() # the router reports the lift after the gesture
	_run(1.0)
	assert_eq(rock.state, LooseObject.State.RESTING)
	assert_eq(rock.moved_count, 1)
	assert_eq(landings.size(), 1, "dropped once")


func test_a_second_finger_makes_the_hand_let_go() -> void:
	var rock := _nearest(LooseObject.Kind.ROCK)
	assert_true(_grab(rock))
	_drag_to(_ground_screen(rock.position + Vector2(1.5, 0)))
	_run(0.5)
	# The recognizer ends the drag as cancelled, then starts the two-finger gesture.
	var end := _gesture(Gesture.Type.DRAG_END)
	end.cancelled = true
	assert_true(tools.handle_gesture(end))
	assert_false(tools.handle_gesture(_gesture(Gesture.Type.MULTI_START)), "pinching works as usual")
	assert_false(hand.is_busy())
	_run(1.0)
	assert_eq(rock.state, LooseObject.State.RESTING)


func test_saving_while_carrying_saves_the_rock_on_the_ground() -> void:
	var rock := _nearest(LooseObject.Kind.ROCK)
	assert_true(_grab(rock))
	_drag_to(_ground_screen(rock.position + Vector2(2.0, 0)))
	_run(0.6)
	assert_true(rock.height_offset > 0.2)
	var records: Array = session.to_dict()["world_state"]["loose"]["objects"]
	assert_eq(records.size(), 1)
	assert_near(records[0]["height_offset"], 0.0, 0.0, "not hanging in the air after a reload")
	assert_eq(records[0]["position"], rock.position)


func test_a_removed_rock_is_simply_let_go() -> void:
	var rock := _nearest(LooseObject.Kind.ROCK)
	assert_true(_grab(rock))
	session.loose.remove(rock.id)
	_run(0.1)
	assert_false(hand.is_busy())
	tools.handle_gesture(_gesture(Gesture.Type.DRAG_END)) # nothing breaks


# --- tools ----------------------------------------------------------------------------------

func test_tool_manager_keeps_the_tools() -> void:
	# (the water and call tools are prototypes that only exist in debug builds, like this one)
	assert_eq(tools.tool_ids(), [HandTool.ID, ObserveTool.ID, WaterTool.ID, CallTool.ID] as Array[StringName])
	assert_eq(tools.current_id(), HandTool.ID, "the hand is the default")
	var changes := []
	var bus := []
	var on_bus := func(id: StringName) -> void: bus.append(id)
	tools.tool_changed.connect(func(id: StringName) -> void: changes.append(id))
	EventBus.tool_changed.connect(on_bus)
	assert_true(tools.select(ObserveTool.ID))
	assert_true(tools.select(ObserveTool.ID), "selecting it again is fine")
	assert_false(tools.select(&"hammer"))
	assert_eq(tools.current_id(), ObserveTool.ID)
	assert_true(tools.get_tool(ObserveTool.ID) is ObserveTool)
	EventBus.tool_changed.disconnect(on_bus)
	assert_eq(changes, [ObserveTool.ID], "announced once")
	assert_eq(bus, [ObserveTool.ID])


func test_switching_tools_lets_go() -> void:
	var rock := _nearest(LooseObject.Kind.ROCK)
	assert_true(_grab(rock))
	tools.select(ObserveTool.ID)
	assert_false(hand.is_busy())
	assert_eq(rock.state, LooseObject.State.FALLING)
	# The observing eye picks nothing up.
	_run(1.0)
	assert_false(tools.handle_gesture(_gesture(Gesture.Type.HOLD, _screen_of(rock))))
	assert_eq(rock.state, LooseObject.State.RESTING)
	# cancel() (app going to the background) lets go as well.
	tools.select(HandTool.ID)
	assert_true(_grab(rock))
	tools.cancel()
	assert_false(tools.is_busy())
	assert_eq(tools.current_id(), HandTool.ID)


func test_hand_tap_touches_and_observe_tap_does_not() -> void:
	var rock := _nearest(LooseObject.Kind.ROCK)
	_look_at(rock.position)
	var target := view.pick(_screen_of(rock), 60.0)
	var response := tools.tap(target)
	assert_eq(response.effect, InteractionResponse.ROCK_WOBBLE)
	assert_eq(session.interactions.interaction_count, 1)
	assert_eq(session.history.total(), 1)
	tools.select(ObserveTool.ID)
	assert_null(tools.tap(target), "observing leaves the world alone")
	assert_eq(session.interactions.interaction_count, 1)
	assert_eq(session.history.total(), 1, "and leaves no trace in the history")
