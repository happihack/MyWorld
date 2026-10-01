extends TestCase
## The long-press context menu, the inspect card and the panel stack, end to
## end in the main scene on a world with a known seed.

var main: Node
var ui: UIRoot
var view: WorldView
var session: WorldSession
var rig: CameraRig
var router: InputRouter
var heard: Array[InteractionResponse] = []


func before_each() -> void:
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
	rig = view.camera_rig()
	rig.set_process(false)
	ui.quit_action = func() -> void: pass
	_look_at(Vector2(session.start.settlement_tile) + Vector2(0.5, 0.5))
	heard.clear()
	session.interactions.responded.connect(func(r: InteractionResponse) -> void: heard.append(r))


func after_each() -> void:
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
	await wait_frames(2)


func _look_at(xz: Vector2, distance: float = 16.0) -> void:
	rig.focus_on(Vector3(xz.x, 0, xz.y), distance, false)
	for i in 120:
		rig.advance(1.0 / 60.0)


func _settle() -> void:
	for i in 300:
		rig.advance(1.0 / 60.0)


func _prop_screen(prop: PropData, up: float) -> Vector2:
	var at := prop.position2d()
	var ground := session.world.get_height(prop.tile) * session.world.height_step
	return rig.world_to_screen(Vector3(at.x, ground + up, at.y))


func _hut() -> PropData:
	return session.props.get_prop(session.start.hut_ids[0])


func _nearest(kind: PropData.Kind) -> PropData:
	var best: PropData = null
	var best_distance := INF
	for p in session.props.all_props():
		var d := Vector2(p.tile - session.start.settlement_tile).length()
		if p.kind == kind and d < best_distance:
			best_distance = d
			best = p
	return best


## Screen position where a finger touches only ground.
func _open_ground() -> Vector2:
	var center := session.start.settlement_tile
	for radius in range(1, 15):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var tile := center + Vector2i(dx, dy)
				var ground := session.world.get_height(tile) * session.world.height_step
				var screen := rig.world_to_screen(Vector3(tile.x + 0.5, ground, tile.y + 0.5))
				var target: Picker.Result = main.pick_at(screen)
				if target.kind == Picker.Kind.TILE and target.tile == tile:
					return screen
	fail("no open ground near the settlement")
	return Vector2.ZERO


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = index
	t.position = pos
	t.pressed = pressed
	get_tree().root.push_input(t, true)


func _tap(pos: Vector2) -> void:
	_touch(0, pos, true)
	_touch(0, pos, false)


## A long press as the recognizer reports it (the real, timed one is tested in
## test_long_press_with_a_real_touch).
func _long_press(pos: Vector2) -> ContextMenu:
	var g := Gesture.new(Gesture.Type.LONG_PRESS)
	g.position = pos
	g.start_position = pos
	router.gesture_recognized.emit(g)
	return ui.top_panel() as ContextMenu


func _labels(menu: ContextMenu) -> Array:
	var out := []
	for button in menu.option_buttons():
		out.append(button.text)
	return out


func _press(menu: ContextMenu, label: String) -> void:
	for button in menu.option_buttons():
		if button.text == label:
			button.pressed.emit()
			return
	fail("no option '%s' in %s" % [label, _labels(menu)])


func _view_rect() -> Rect2:
	return Rect2(Vector2.ZERO, get_tree().root.get_visible_rect().size)


# --- context menu ---------------------------------------------------------------------

func test_long_press_opens_a_menu_for_what_was_pressed() -> void:
	var roof := _prop_screen(_hut(), 0.7)
	var menu := _long_press(roof)
	assert_not_null(menu)
	assert_eq(ui.panel_count(), 1)
	assert_eq(menu.title_text(), "Hut")
	assert_eq(_labels(menu), ["Inspect", "Knock", "Look closer"])
	assert_true(view.pick_highlight().entity_visible(), "the pressed thing is marked while the menu is open")
	assert_false(view.effects().is_shaking(_hut().id), "opening the menu does not touch the hut")
	# Reachable and readable: on screen, beside the finger, finger-sized rows.
	var rect := menu.get_global_rect()
	assert_true(_view_rect().encloses(rect), "on screen: %s in %s" % [rect, _view_rect()])
	assert_false(rect.has_point(roof), "not under the finger")
	for button in menu.option_buttons():
		assert_true(button.size.y >= UITheme.TOUCH_TARGET - 0.5, "48 dp touch target (%s)" % button.size.y)
		assert_true(button.size.x >= ContextMenu.MIN_WIDTH - 0.5)


func test_long_press_with_a_real_touch() -> void:
	var roof := _prop_screen(_hut(), 0.7)
	_touch(0, roof, true)
	await wait_real_ms(Config.interaction.long_press_ms + 150)
	var menu := ui.top_panel() as ContextMenu
	assert_not_null(menu, "the menu opens while the finger is still down")
	assert_eq(heard.size(), 1)
	assert_eq(heard[0].effect, InteractionResponse.INSPECT)
	_touch(0, roof, false)
	assert_eq(heard.size(), 1, "releasing a long press is not a tap")
	assert_eq(ui.panel_count(), 1, "and the menu stays open")


func test_menu_words_fit_the_target() -> void:
	var tree := _nearest(PropData.Kind.TREE)
	_look_at(tree.position2d())
	var menu := _long_press(_prop_screen(tree, 0.9))
	assert_has(["Tree", "Pine"], menu.title_text())
	assert_eq(_labels(menu), ["Inspect", "Shake", "Uproot", "Look closer"])
	# Open ground.
	_look_at(Vector2(session.start.settlement_tile) + Vector2(0.5, 0.5))
	menu = _long_press(_open_ground())
	assert_has(UIText.TERRAIN_NAMES.values(), menu.title_text())
	assert_eq(_labels(menu), ["Inspect", "Touch", "Look closer"])
	assert_eq(ui.panel_count(), 1, "a new menu replaces the old one")
	# Water.
	var water := _water_tile()
	_look_at(Vector2(water) + Vector2(0.5, 0.5), 10.0)
	var surface := session.world.get_height(water) * session.world.height_step + session.world.get_water(water)
	menu = _long_press(rig.world_to_screen(Vector3(water.x + 0.5, surface, water.y + 0.5)))
	assert_eq(menu.title_text(), "Water")
	assert_eq(_labels(menu), ["Inspect", "Disturb", "Look closer"])


func _water_tile() -> Vector2i:
	var best := Vector2i.ZERO
	var best_distance := INF
	var b := session.world.bounds
	for y in range(b.position.y + 2, b.end.y - 2):
		for x in range(b.position.x + 2, b.end.x - 2):
			var t := Vector2i(x, y)
			var d := Vector2(t - session.start.settlement_tile).length()
			if d < best_distance and session.world.get_water(t) > 0.3 \
					and session.world.get_water(t + Vector2i(1, 0)) > 0.3 and session.world.get_water(t - Vector2i(1, 0)) > 0.3:
				best_distance = d
				best = t
	return best


func test_long_press_on_nothing_opens_nothing() -> void:
	rig.frame_box(false)
	assert_null(_long_press(Vector2(20, 20)), "outside the box")
	assert_eq(ui.panel_count(), 0)


func test_menu_keeps_clear_of_the_screen_edges() -> void:
	var what := session.interactions.describe(main.pick_at(_prop_screen(_hut(), 0.7)))
	var actions: Array[StringName] = [&"inspect", &"touch", &"focus"]
	var screen := _view_rect()
	for corner: Vector2 in [Vector2(0, 0), Vector2(screen.end.x, 0), screen.end, Vector2(0, screen.end.y), screen.get_center()]:
		var menu := ui.open_context_menu(corner, Picker.Result.new(), what, actions)
		var rect := menu.get_global_rect()
		assert_true(screen.grow(-ContextMenu.EDGE_MARGIN + 0.5).encloses(rect), "pressed at %s: %s" % [corner, rect])
	assert_eq(ui.panel_count(), 1)


# --- actions ----------------------------------------------------------------------------

func test_inspect_shows_a_card_about_the_target() -> void:
	var hut := _hut()
	_press(_long_press(_prop_screen(hut, 0.7)), "Inspect")
	assert_eq(ui.panel_count(), 1, "the menu made way for the card")
	var card := ui.top_panel() as InspectCard
	assert_not_null(card)
	assert_eq(card.title_text(), "Hut")
	assert_has(card.subtitle_text(), "%d, %d" % [hut.tile.x, hut.tile.y])
	var rows := card.rows()
	assert_eq(rows["Stands on"], UIText.terrain_name(session.world.get_terrain(hut.tile)))
	assert_eq(rows["Ground height"], str(session.world.get_height(hut.tile)))
	assert_has(rows, "Size")
	assert_false(view.pick_highlight().entity_visible(), "the mark goes with the menu")
	assert_eq(heard.size(), 1, "looking is not touching (only the long press was announced)")
	# In the corner, on screen, clear of the Home button, with a finger-sized ✕.
	await wait_frames(1)
	var rect := card.get_global_rect()
	assert_true(_view_rect().encloses(rect), "on screen: %s" % rect)
	var home: Control = ui.get_node("%HomeButton")
	assert_false(rect.intersects(home.get_global_rect()), "does not cover the Home button")
	var close: Button = card.get_node("%Close")
	assert_true(close.size.x >= 119.0 and close.size.y >= 119.0)
	close.pressed.emit()
	assert_eq(ui.panel_count(), 0)


func test_inspecting_ground_and_water() -> void:
	_press(_long_press(_open_ground()), "Inspect")
	var card := ui.top_panel() as InspectCard
	for key in ["Height", "Moisture", "Fertility", "Plant cover"]:
		assert_has(card.rows(), key)
	var water := _water_tile()
	_look_at(Vector2(water) + Vector2(0.5, 0.5), 10.0)
	var surface := session.world.get_height(water) * session.world.height_step + session.world.get_water(water)
	_press(_long_press(rig.world_to_screen(Vector3(water.x + 0.5, surface, water.y + 0.5))), "Inspect")
	assert_eq(ui.panel_count(), 1, "a new card replaces the old one")
	card = ui.top_panel() as InspectCard
	assert_eq(card.title_text(), "Water")
	assert_has(card.rows(), "Depth")
	assert_eq(card.rows()["Bed height"], str(session.world.get_height(water)))


func test_touch_action_does_what_a_tap_does() -> void:
	var tree := _nearest(PropData.Kind.TREE)
	_look_at(tree.position2d())
	_press(_long_press(_prop_screen(tree, 0.9)), "Shake")
	assert_eq(ui.panel_count(), 0)
	assert_true(view.effects().is_shaking(tree.id))
	assert_eq(heard.size(), 2)
	assert_eq(heard[1].effect, InteractionResponse.TREE_SHAKE)


func test_look_closer_moves_the_camera_in() -> void:
	var hut := _hut()
	var before := rig.distance()
	_press(_long_press(_prop_screen(hut, 0.7)), "Look closer")
	_settle()
	assert_near(rig.pivot().x, hut.position2d().x, 0.2)
	assert_near(rig.pivot().z, hut.position2d().y, 0.2)
	# Main.LOOK_CLOSER_FACTOR
	assert_near(rig.distance(), maxf(before * 0.6, Config.camera.min_distance), 0.1)


# --- panel stack ------------------------------------------------------------------------

func test_back_closes_panels_before_leaving() -> void:
	var quits := [0]
	ui.quit_action = func() -> void: quits[0] += 1
	_press(_long_press(_prop_screen(_hut(), 0.7)), "Inspect")
	_long_press(_prop_screen(_hut(), 0.7))
	assert_eq(ui.panel_count(), 2, "card with a menu on top")
	EventBus.back_requested.emit()
	assert_eq(ui.panel_count(), 1)
	assert_true(ui.top_panel() is InspectCard, "the menu was on top")
	EventBus.back_requested.emit()
	assert_eq(ui.panel_count(), 0)
	assert_eq(quits[0], 0, "still in the game")
	EventBus.back_requested.emit()
	assert_eq(quits[0], 1, "nothing left to close: back leaves")


func test_touching_the_world_puts_the_menu_away() -> void:
	_long_press(_prop_screen(_hut(), 0.7))
	var before := heard.size()
	var fire := session.props.get_prop(session.start.campfire_id)
	_tap(_prop_screen(fire, 0.15))
	assert_eq(ui.panel_count(), 0)
	assert_eq(heard.size(), before, "that tap only closed the menu")
	assert_false(view.pick_highlight().entity_visible())
	await wait_real_ms(Config.interaction.double_tap_ms + 80) # a separate tap, not a double tap
	_tap(_prop_screen(fire, 0.15))
	assert_eq(heard.size(), before + 1, "the next tap is a normal tap again")
	assert_eq(heard[-1].effect, InteractionResponse.FIRE_FLARE)


func test_moving_the_view_puts_the_menu_away_but_not_the_card() -> void:
	_press(_long_press(_prop_screen(_hut(), 0.7)), "Inspect")
	_long_press(_prop_screen(_hut(), 0.7))
	assert_eq(ui.panel_count(), 2)
	router.gesture_recognized.emit(Gesture.new(Gesture.Type.MULTI_START))
	assert_eq(ui.panel_count(), 1)
	assert_true(ui.top_panel() is InspectCard, "cards stay while exploring")
	# Tapping the world with a card open still touches the world.
	var fire := session.props.get_prop(session.start.campfire_id)
	_tap(_prop_screen(fire, 0.15))
	assert_eq(heard[-1].effect, InteractionResponse.FIRE_FLARE)
	assert_eq(ui.panel_count(), 1)


func test_touches_on_a_panel_never_reach_the_world() -> void:
	_press(_long_press(_prop_screen(_hut(), 0.7)), "Inspect")
	await wait_frames(1)
	var card := ui.top_panel() as InspectCard
	var inside := card.get_global_rect().get_center()
	assert_true(router.is_over_ui(inside))
	var gestures := [0]
	router.gesture_recognized.connect(func(_g: Gesture) -> void: gestures[0] += 1)
	_tap(inside)
	assert_eq(gestures[0], 0)
	# Just outside the card the world is still there.
	assert_false(router.is_over_ui(card.get_global_rect().position - Vector2(40, 40)))
	card.close()
	assert_false(router.is_over_ui(inside), "a closed panel lets touches through at once")


func test_panel_stack_basics() -> void:
	assert_false(ui.close_top_panel())
	assert_null(ui.top_panel())
	assert_false(ui.dismiss_transient_panels())
	_press(_long_press(_prop_screen(_hut(), 0.7)), "Inspect")
	_long_press(_prop_screen(_hut(), 0.7))
	ui.close_all_panels()
	assert_eq(ui.panel_count(), 0)
	await wait_frames(2)
	assert_eq(ui.get_node("Panels").get_child_count(), 0, "closed panels are freed")


# --- first-time hints in the game ---------------------------------------------------------------

func _drag(from: Vector2, to: Vector2) -> void:
	_touch(0, from, true)
	for i in range(1, 9):
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = from.lerp(to, i / 8.0)
		d.relative = (to - from) / 8.0
		get_tree().root.push_input(d, true)
	_touch(0, to, false)


func test_drag_hint_shows_when_idle_and_goes_with_the_first_pan() -> void:
	var hints := ui.hints()
	hints.set_process(false)
	var hint: HintLabel = ui.get_node("Hint")
	assert_false(hint.is_showing())
	hints.advance(Config.interaction.hint_idle_seconds + 0.1)
	assert_true(hint.is_showing())
	assert_eq(hint.text(), "Drag to explore.")
	await wait_frames(1)
	assert_false(router.is_over_ui(hint.get_global_rect().get_center()), "the hint does not block the world")
	assert_true(hint.get_index() < ui.get_node("Panels").get_index(), "panels draw over the hint")
	# A real one-finger pan.
	_drag(Vector2(540, 900), Vector2(300, 1100))
	assert_false(hint.is_showing())
	assert_true(hints.is_completed(HintDirector.DRAG))


func test_hold_hint_goes_when_the_menu_opens() -> void:
	var hints := ui.hints()
	hints.set_process(false)
	hints.complete(HintDirector.DRAG)
	var fire := session.props.get_prop(session.start.campfire_id)
	_tap(_prop_screen(fire, 0.15))
	hints.advance(Config.interaction.hint_follow_up_seconds + 0.1)
	assert_eq(hints.current(), HintDirector.HOLD)
	_long_press(_prop_screen(_hut(), 0.7))
	assert_eq(hints.current(), &"")
	assert_true(hints.is_completed(HintDirector.HOLD))
	assert_eq(ui.panel_count(), 1)


func test_no_hint_while_a_panel_is_open() -> void:
	var hints := ui.hints()
	hints.set_process(false)
	Settings.set_value(HintDirector.SETTING, "hold") # only the drag hint is left
	_press(_long_press(_prop_screen(_hut(), 0.7)), "Inspect")
	hints.advance(60.0)
	assert_eq(hints.current(), &"", "the card has the player's attention")
	ui.close_all_panels()
	hints.advance(Config.interaction.hint_idle_seconds + 0.1)
	assert_eq(hints.current(), HintDirector.DRAG)


# --- trees in the game -------------------------------------------------------------------------

func test_shaking_a_tree_from_the_menu_brings_fruit_down() -> void:
	var tree := _nearest(PropData.Kind.TREE)
	_look_at(tree.position2d())
	var before := session.loose.size()
	var screen := _prop_screen(tree, 0.9)
	for i in 60:
		_press(_long_press(screen), "Shake")
		if session.loose.size() > before:
			break
	assert_eq(session.loose.size(), before + 1, "a fruit (or cone) fell")
	assert_eq(tree.taken, 1)
	await wait_real_ms(1200)
	var fallen: LooseObject = null
	for o in session.loose.all_objects():
		if o.kind == LooseObject.Kind.FRUIT or o.kind == LooseObject.Kind.SEED:
			fallen = o
	assert_not_null(fallen)
	assert_eq(fallen.state, LooseObject.State.RESTING, "it lies on the ground")
	assert_true(view.loose_view().is_shown(fallen.id), "and is drawn")
	# The card tells what is left.
	_press(_long_press(screen), "Inspect")
	var card := ui.top_panel() as InspectCard
	assert_has(card.rows(), "Bears")
	assert_eq(card.rows()["Bears"], UIText.bears_text(tree.bears_left(), tree.bears(), tree.is_conifer()))


func test_uprooting_a_tree_from_the_menu() -> void:
	var tree := _nearest(PropData.Kind.TREE)
	var tree_id := tree.id
	var at := tree.position2d()
	_look_at(at)
	var chunk := WorldCoords.tile_to_chunk(tree.tile, session.world.chunk_size)
	var mesh_before := view.get_chunk_view(chunk).props_mesh()
	var logs_before := 0
	_press(_long_press(_prop_screen(tree, 0.9)), "Uproot")
	assert_null(session.props.get_prop(tree_id), "the tree is gone")
	assert_eq(heard[-1].effect, InteractionResponse.TREE_UPROOT)
	assert_eq(AudioManager.last_sound, &"rustle")
	assert_eq(view.effects().burst_count(WorldEffects.Burst.LEAVES), 2)
	await wait_real_ms(1200)
	assert_true(view.get_chunk_view(chunk).props_mesh() != mesh_before, "and no longer drawn")
	var log: LooseObject = null
	for o in session.loose.all_objects():
		if o.kind == LooseObject.Kind.LOG:
			log = o
			logs_before += 1
	assert_eq(logs_before, 1, "one log lies where it stood")
	assert_true(log.position.distance_to(at) < 1.5)
	assert_eq(log.state, LooseObject.State.RESTING)
	# The log can be touched like anything else: wood knocks.
	var menu := _long_press(rig.world_to_screen(log.world_position(session.world) + Vector3(0, 0.1, 0)))
	assert_eq(menu.title_text(), "Log")
	_press(menu, "Touch")
	assert_eq(heard[-1].effect, InteractionResponse.LOG_KNOCK)
