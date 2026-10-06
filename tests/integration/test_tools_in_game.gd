extends TestCase
## The tool bar and the hand tool in the main scene, driven by real touch
## events, on a world with a known seed.

var main: Node
var ui: UIRoot
var view: WorldView
var session: WorldSession
var rig: CameraRig
var router: InputRouter
var tools: ToolManager
var heard: Array[InteractionResponse] = []
var pulses: Array = []
var _real_vibrate: Callable


func before_each() -> void:
	AudioManager.ensure_sounds()
	_real_vibrate = Haptics.vibrate_action
	pulses.clear()
	Haptics.vibrate_action = func(ms: int, _amplitude: float) -> void: pulses.append(ms)
	Haptics.reset()
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
	view = main.get_node("WorldView")
	session = main.get_node("WorldSession")
	router = main.get_node("InputRouter")
	tools = main.get_node("Tools")
	rig = view.camera_rig()
	rig.set_process(false)
	ui.quit_action = func() -> void: pass
	ui.hints().set_process(false)
	heard.clear()
	session.interactions.responded.connect(func(r: InteractionResponse) -> void: heard.append(r))


func after_each() -> void:
	Haptics.vibrate_action = _real_vibrate
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
	await wait_frames(2)


func _look_at(xz: Vector2, distance: float = 12.0) -> void:
	rig.focus_on(Vector3(xz.x, 0, xz.y), distance, false)
	for i in 120:
		rig.advance(1.0 / 60.0)


func _nearest(kind: LooseObject.Kind) -> LooseObject:
	var best: LooseObject = null
	var best_distance := INF
	for o in session.loose.all_objects():
		var d := o.position.distance_to(Vector2(session.start.settlement_tile))
		if o.kind == kind and d < best_distance:
			best_distance = d
			best = o
	return best


func _screen_of(object: LooseObject) -> Vector2:
	return rig.world_to_screen(object.world_position(session.world) + Vector3(0, object.height() * 0.5, 0))


func _ground_screen(xz: Vector2) -> Vector2:
	var tile := WorldCoords.world2d_to_tile(xz)
	return rig.world_to_screen(Vector3(xz.x, session.world.get_height(tile) * session.world.height_step, xz.y))


func _touch(pos: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = pos
	t.pressed = pressed
	get_tree().root.push_input(t, true)


func _move(from: Vector2, to: Vector2, steps: int = 8) -> void:
	for i in range(1, steps + 1):
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = from.lerp(to, i / float(steps))
		d.relative = (to - from) / steps
		get_tree().root.push_input(d, true)


# --- tool bar -------------------------------------------------------------------------------

func test_tool_bar_shows_the_tools_that_exist() -> void:
	var bar := ui.tool_bar()
	assert_eq(bar.tool_ids(), [HandTool.ID, ObserveTool.ID, RainTool.ID, WindTool.ID, WaterTool.ID],
		"in a debug build: every tool, and the prototype (what a player has: test_powers_in_game)")
	assert_eq(bar.current(), HandTool.ID)
	assert_true(bar.button(HandTool.ID).selected)
	assert_false(bar.button(ObserveTool.ID).selected)
	await wait_frames(1)
	var screen := get_tree().root.get_visible_rect().size
	var rect := bar.get_global_rect()
	assert_near(rect.get_center().x, screen.x * 0.5, 1.0, "centred")
	assert_near(rect.end.y, screen.y - ToolBar.BOTTOM_MARGIN, 1.0, "in the bottom row")
	var home: Control = ui.get_node("%HomeButton")
	assert_false(rect.intersects(home.get_global_rect()), "clear of the Home button")
	for id: StringName in [HandTool.ID, ObserveTool.ID]:
		var button := bar.button(id)
		assert_true(button.size.x >= 139.0 and button.size.y >= 139.0, "a finger-sized target")
		assert_true(router.is_over_ui(button.get_global_rect().get_center()), "touches on it never reach the world")
		assert_false(button.tooltip_text.is_empty())
	var gap := (bar.button(HandTool.ID).get_global_rect().end.x + bar.button(ObserveTool.ID).get_global_rect().position.x) * 0.5
	assert_false(router.is_over_ui(Vector2(gap, rect.get_center().y)), "the gap between the buttons is still the world")


func test_choosing_a_tool() -> void:
	var bar := ui.tool_bar()
	var changes := []
	var on_change := func(id: StringName) -> void: changes.append(id)
	EventBus.tool_changed.connect(on_change)
	bar.button(ObserveTool.ID).pressed.emit()
	EventBus.tool_changed.disconnect(on_change)
	assert_eq(tools.current_id(), ObserveTool.ID)
	assert_eq(changes, [ObserveTool.ID])
	assert_true(bar.button(ObserveTool.ID).selected)
	assert_false(bar.button(HandTool.ID).selected)
	assert_eq(AudioManager.last_sound, &"ui_tap", "it ticks")
	bar.button(HandTool.ID).pressed.emit()
	assert_eq(tools.current_id(), HandTool.ID)


func test_inspect_card_sits_above_the_tool_bar() -> void:
	var hut := session.props.get_prop(session.start.hut_ids[0])
	_look_at(hut.position2d(), 16.0)
	var target := view.pick(_ground_screen(hut.position2d()), 60.0)
	var card := ui.open_inspect(session.interactions.inspect(target))
	await wait_frames(1)
	assert_false(card.get_global_rect().intersects(ui.tool_bar().get_global_rect()), "the card does not cover the tools")
	assert_true(get_tree().root.get_visible_rect().encloses(card.get_global_rect()))


# --- observe --------------------------------------------------------------------------------

func test_observing_shows_without_touching() -> void:
	tools.select(ObserveTool.ID)
	var rock := _nearest(LooseObject.Kind.ROCK)
	_look_at(rock.position)
	var at := _screen_of(rock)
	_touch(at, true)
	_touch(at, false)
	assert_eq(heard.size(), 0, "nothing in the world was touched")
	assert_false(view.effects().is_shaking(rock.id))
	assert_eq(pulses.size(), 0)
	var card := ui.top_panel() as InspectCard
	assert_not_null(card, "a tap shows what it is")
	assert_eq(card.title_text(), "Rock")
	# Resting a finger on it does not pick it up.
	await wait_real_ms(Config.interaction.double_tap_ms + 60)
	_touch(at, true)
	await wait_real_ms(Config.interaction.grab_hold_ms + 100)
	assert_eq(rock.state, LooseObject.State.RESTING)
	_touch(at, false)


# --- hand: the whole gesture with real touches ----------------------------------------------------

func test_grab_carry_and_drop_with_a_real_finger() -> void:
	var rock := _nearest(LooseObject.Kind.ROCK)
	_look_at(rock.position)
	var from := rock.position
	var start := _screen_of(rock)
	var target := from + Vector2(1.2, 0.5)
	var finish := _ground_screen(target)
	var pivot := rig.pivot()
	_touch(start, true)
	await wait_real_ms(Config.interaction.grab_hold_ms + 120)
	assert_eq(rock.state, LooseObject.State.HELD, "resting a finger on it picks it up")
	assert_true(rock.height_offset > 0.05, "it lifts off the ground")
	assert_eq(pulses.size(), 1)
	_move(start, finish)
	await wait_real_ms(500)
	assert_true(rock.position.distance_to(target) < 0.7, "it follows the finger (%s vs %s)" % [rock.position, target])
	assert_eq(rig.pivot(), pivot, "the view does not pan while carrying")
	assert_eq(ui.panel_count(), 0, "no menu: the finger moved")
	_touch(finish, false)
	await wait_real_ms(500)
	assert_eq(rock.state, LooseObject.State.RESTING)
	assert_near(rock.height_offset, 0.0, 0.0)
	assert_eq(rock.moved_count, 1)
	# It landed with dust, a thud and a pulse.
	assert_eq(view.effects().played.get(WorldEffects.LANDING, 0), 1)
	assert_eq(AudioManager.last_sound, &"thud")
	assert_eq(pulses.size(), 2)
	assert_eq(heard.size(), 0, "carrying is not tapping")
	assert_false(ui.hints().is_completed(HintDirector.DRAG), "nor is it exploring: the drag hint is still owed")
	assert_eq(session.history.count(Intervention.MOVE_OBJECT, &"rock"), 1, "the move is in the player's history")
	assert_eq(session.history.total(), 1)
	assert_false(rig.is_flinging(), "letting go never flings the view")


func test_holding_still_opens_the_menu_and_the_rock_settles() -> void:
	var rock := _nearest(LooseObject.Kind.ROCK)
	_look_at(rock.position)
	var at := _screen_of(rock)
	_touch(at, true)
	await wait_real_ms(Config.interaction.long_press_ms + 150)
	var menu := ui.top_panel() as ContextMenu
	assert_not_null(menu, "the long-press menu still opens on a rock")
	assert_eq(menu.title_text(), "Rock")
	assert_eq(rock.state, LooseObject.State.HELD, "while the rock is still in hand")
	_touch(at, false)
	await wait_real_ms(400)
	assert_eq(rock.state, LooseObject.State.RESTING, "lifting the finger puts it back")
	assert_eq(rock.moved_count, 0)
	assert_eq(ui.panel_count(), 1, "and the menu stays to be used")


func test_a_slow_player_can_still_carry() -> void:
	# Hold until the menu opens (waiting to see what happens), then drag.
	var rock := _nearest(LooseObject.Kind.ROCK)
	_look_at(rock.position)
	var start := _screen_of(rock)
	var target := rock.position + Vector2(1.2, 0.5)
	var finish := _ground_screen(target)
	var pivot := rig.pivot()
	_touch(start, true)
	await wait_real_ms(Config.interaction.long_press_ms + 200)
	assert_eq(ui.panel_count(), 1)
	_move(start, finish)
	assert_eq(ui.panel_count(), 0, "dragging puts the menu away")
	await wait_real_ms(500)
	assert_true(rock.position.distance_to(target) < 0.7, "and carries the rock (%s vs %s)" % [rock.position, target])
	assert_eq(rig.pivot(), pivot, "the view does not pan")
	_touch(finish, false)
	await wait_real_ms(500)
	assert_eq(rock.state, LooseObject.State.RESTING)
	assert_eq(rock.moved_count, 1)


func test_losing_focus_mid_hold_lets_go() -> void:
	var rock := _nearest(LooseObject.Kind.ROCK)
	_look_at(rock.position)
	_touch(_screen_of(rock), true)
	await wait_real_ms(Config.interaction.grab_hold_ms + 120)
	assert_eq(rock.state, LooseObject.State.HELD)
	EventBus.app_focus_changed.emit(false) # the router cancels its touches
	assert_false(tools.is_busy())
	await wait_real_ms(400)
	assert_eq(rock.state, LooseObject.State.RESTING)


func test_a_quick_drag_over_a_rock_still_pans() -> void:
	var rock := _nearest(LooseObject.Kind.ROCK)
	_look_at(rock.position)
	var at := _screen_of(rock)
	var pivot := rig.pivot()
	_touch(at, true)
	_move(at, at + Vector2(260, 0)) # at once: no time to grab
	_touch(at + Vector2(260, 0), false)
	assert_eq(rock.state, LooseObject.State.RESTING)
	assert_eq(rock.position, _nearest(LooseObject.Kind.ROCK).position)
	assert_true(rig.pivot().distance_to(pivot) > 0.5, "the view moved")


func test_app_going_to_the_background_lets_go() -> void:
	var rock := _nearest(LooseObject.Kind.ROCK)
	_look_at(rock.position)
	_touch(_screen_of(rock), true)
	await wait_real_ms(Config.interaction.grab_hold_ms + 120)
	assert_eq(rock.state, LooseObject.State.HELD)
	EventBus.app_paused.emit()
	assert_false(tools.is_busy())
	await wait_real_ms(400)
	assert_eq(rock.state, LooseObject.State.RESTING)


func test_dropping_into_water_splashes() -> void:
	var rock := _nearest(LooseObject.Kind.ROCK)
	# The nearest deep water.
	var water := Vector2i.ZERO
	var best := INF
	var b := session.world.bounds
	for y in range(b.position.y + 2, b.end.y - 2):
		for x in range(b.position.x + 2, b.end.x - 2):
			var t := Vector2i(x, y)
			var d := Vector2(t - session.start.settlement_tile).length()
			if d < best and session.world.get_water(t) > 0.3:
				best = d
				water = t
	session.loose.move(rock.id, Vector2(water) + Vector2(0.5, 0.5), 1.0)
	session.loose_system.drop(rock.id)
	await wait_real_ms(600)
	assert_eq(rock.state, LooseObject.State.RESTING)
	assert_near(rock.height_offset, 0.0, 0.0, "stone sinks to the bed")
	assert_eq(AudioManager.last_sound, &"plip")
	assert_true(view.effects().active_ring_count() >= 1, "ripples")


func test_quick_taps_with_the_water_tool_do_not_move_the_camera() -> void:
	tools.select(WaterTool.ID)
	var water_tool := tools.current() as WaterTool
	# The deepest water near the settlement.
	var tile := Vector2i.ZERO
	var best := INF
	var b := session.world.bounds
	for y in range(b.position.y + 2, b.end.y - 2):
		for x in range(b.position.x + 2, b.end.x - 2):
			var t := Vector2i(x, y)
			var d := Vector2(t - session.start.settlement_tile).length()
			if d < best and session.world.get_water(t) > 0.45:
				best = d
				tile = t
	_look_at(Vector2(tile) + Vector2(0.5, 0.5), 10.0)
	var surface := session.world.get_height(tile) * session.world.height_step + session.world.get_water(tile)
	var at := rig.world_to_screen(Vector3(tile.x + 0.5, surface, tile.y + 0.5))
	var pivot := rig.pivot()
	var distance := rig.distance()
	_touch(at, true)
	_touch(at, false)
	_touch(at, true) # at once: the recognizer calls this a double tap
	_touch(at, false)
	for i in 60:
		rig.advance(1.0 / 60.0)
	assert_true(water_tool.bucket > WaterTool.SCOOP, "both taps scooped (%.2f)" % water_tool.bucket)
	assert_eq(rig.pivot(), pivot, "and the view stayed where it was")
	assert_near(rig.distance(), distance, 0.0001)
	# With the hand, two quick taps on a tree shake it twice and look at it.
	tools.select(HandTool.ID)
	var tree: PropData = null
	var nearest := INF
	for p in session.props.all_props():
		var d := Vector2(p.tile - session.start.settlement_tile).length()
		if p.kind == PropData.Kind.TREE and d < nearest:
			nearest = d
			tree = p
	_look_at(tree.position2d())
	var crown := rig.world_to_screen(Vector3(tree.position2d().x,
		session.world.get_height(tree.tile) * session.world.height_step + 0.9, tree.position2d().y))
	await wait_real_ms(Config.interaction.double_tap_ms + 80)
	_touch(crown, true)
	_touch(crown, false)
	_touch(crown, true)
	_touch(crown, false)
	assert_eq(session.interactions.shakes_of(tree.id), 2)


func test_a_rock_rolled_into_a_hut_knocks_and_stops_outside() -> void:
	var hut := session.props.get_prop(session.start.hut_ids[0])
	var rock := _nearest(LooseObject.Kind.ROCK)
	var start := hut.position2d() + Vector2(0.0, 1.6)
	session.loose.move(rock.id, start, 0.0)
	session.loose_system.push(rock.id, Vector3(0.0, 0.0, -6.0)) # straight at the hut
	await wait_real_ms(1500)
	assert_eq(rock.state, LooseObject.State.RESTING)
	assert_true(rock.position.distance_to(hut.position2d()) >= hut.collision_radius() + rock.radius() - 0.001, "not inside the hut")
	assert_eq(AudioManager.last_sound, &"click", "the knock is heard")
	# The overlay reports the motion system.
	var overlay: DebugOverlay = main.get_node("DebugOverlay")
	overlay.toggle()
	overlay.refresh()
	assert_has((overlay.get_node("%OverlayLabel") as Label).text, "moving 0")
	overlay.toggle()


# --- people living by themselves ------------------------------------------------------------------

func test_in_the_running_game_people_go_about_their_day() -> void:
	session.clock.set_speed(GameClock.SPEED_VERY_FAST)
	var before := {}
	for p in session.people.all_people():
		before[p.id] = p.world2d()
	await wait_real_ms(2500) # more than an hour of game time
	var busy := 0
	var moved := 0
	for p in session.people.all_people():
		if session.activities.get_def(BehaviorSystem.activity_of(p)) != null:
			busy += 1
		if p.world2d().distance_to(before[p.id]) > 1.0:
			moved += 1
		assert_eq(p.needs.size(), Needs.COUNT)
	assert_eq(busy, session.people.size(), "everyone has found something to do")
	assert_true(moved >= session.people.size() / 2, "and most have gone somewhere (%d)" % moved)
	assert_true(session.behavior.decisions >= session.people.size())
	assert_eq(session.history.total(), 0, "none of which is the player's doing")


func test_work_is_seen_and_heard_but_not_too_often() -> void:
	var woodcutter: PersonData = null
	for p in session.people.all_people():
		if p.occupation_id == &"woodcutter":
			woodcutter = p
	var tree: PropData = null
	for p in session.props.all_props():
		if p.kind == PropData.Kind.TREE and (tree == null or (p.tile - woodcutter.position).length_squared() < (tree.tile - woodcutter.position).length_squared()):
			tree = p
	session.behavior.enabled = false
	_look_at(woodcutter.world2d(), 20.0)
	await wait_frames(3)
	var effects := view.effects()
	var shakes: int = effects.played.get(InteractionResponse.TREE_SHAKE, 0)
	session.behavior.worked.emit(woodcutter.id, &"tree", tree.id)
	assert_eq(effects.played.get(InteractionResponse.TREE_SHAKE, 0), shakes + 1, "the tree shivers under the axe")
	assert_true(effects.is_shaking(tree.id))
	assert_eq(AudioManager.last_sound, &"knock")
	session.behavior.worked.emit(woodcutter.id, &"tree", tree.id)
	session.behavior.worked.emit(woodcutter.id, &"tree", tree.id)
	assert_eq(effects.played.get(InteractionResponse.TREE_SHAKE, 0), shakes + 1, "not at every stroke when time runs fast")
	await wait_real_ms(400)
	session.behavior.worked.emit(woodcutter.id, &"fire", session.start.campfire_id)
	assert_eq(effects.played.get(InteractionResponse.FIRE_FLARE, 0), 0, "keeping the fire makes no show")
	session.behavior.worked.emit(woodcutter.id, &"tree", 999_999)
	assert_eq(effects.played.get(InteractionResponse.TREE_SHAKE, 0), shakes + 1, "a tree that is gone does not shake")
	# Out of sight, nothing is played.
	_look_at(woodcutter.world2d() + Vector2(-25.0, 20.0), 9.0)
	await wait_frames(3)
	session.behavior.worked.emit(woodcutter.id, &"tree", tree.id)
	assert_eq(effects.played.get(InteractionResponse.TREE_SHAKE, 0), shakes + 1)
	assert_eq(session.history.total(), 0, "people at work are not the player touching things")
