extends Node
## Main scene root: wires WorldSession, WorldView and UIRoot together.
## On launch it continues the most recently saved world; if there is none, or it
## cannot be loaded, it starts a new world (broken saves are left untouched).

@onready var session: WorldSession = $WorldSession
@onready var world_view: WorldView = $WorldView
@onready var ui_root: UIRoot = $UIRoot
@onready var input_router: InputRouter = $InputRouter
@onready var debug_overlay: DebugOverlay = $DebugOverlay

## The player's tools (hand, observe, ...).
var tools: ToolManager
## Debug: what one person is doing and why (shown with the debug overlay).
var inspector: AiInspector
## Debug: stands in for tilting and shaking the device (part of the overlay).
var tilt_stick: TiltStick

## The game opens on the whole box, then the camera descends to the settlement
## after this many seconds (bible §26.1) — unless the player moves first.
const OPENING_HOLD_SECONDS := 1.6
## "Look closer" moves in to this fraction of the current distance.
const LOOK_CLOSER_FACTOR := 0.6

var _world_fingerprint := ""
var _last_pick := "-"
## The touch in progress closed the context menu; its tap does nothing else.
var _tap_closed_menu := false
## The player has touched the world: the camera is theirs, no opening glide.
var _player_has_touched := false
## The person the player has selected (0 = nobody): their card is open, they
## are ringed in the world and simulated most closely.
var _selected_id := 0
## The selected person is being observed: the way they are going is shown.
var _observing := false
## Who the camera follows, and whether it is with them (see CameraFollow).
var follow := CameraFollow.new()
## Where the followed person was seen last frame (INF: not yet).
var _follow_seen := Vector3.INF
## The camera never aims further ahead of a followed person than this (tiles).
const FOLLOW_LEAD_MAX := 1.5
## People at work are heard and seen at most this often (real time).
const WORK_EFFECT_GAP_MSEC := 350
var _last_work_effect_msec := 0
## Voices of people reacting to what they only saw are heard at most this often.
const VOICE_GAP_MSEC := 220
var _last_voice_msec := 0


func _ready() -> void:
	_open_world()
	world_view.show_world(session.world, session.props, session.start, session.loose)
	world_view.show_people(session.people, session.clock, session.occupations)
	world_view.show_animals(session.animals, session.species, session.clock)
	SaveManager.attach(session)
	ui_root.bind_session(session)
	_setup_tools()
	_setup_inspector()
	input_router.gesture_recognized.connect(debug_overlay.on_gesture)
	input_router.touch_began.connect(_on_world_touched)
	input_router.touch_ended.connect(tools.touch_ended)
	session.loose_system.landed.connect(_on_object_landed)
	session.loose_system.bumped.connect(_on_object_bumped)
	ui_root.context_action.connect(_on_context_action)
	ui_root.person_action.connect(_on_person_action)
	ui_root.person_chosen.connect(_on_person_chosen)
	ui_root.person_card_closed.connect(_on_person_card_closed)
	session.people.person_removed.connect(_on_person_removed)
	_refresh_pins()
	follow.changed.connect(_on_follow_changed)
	var banner := ui_root.follow_banner()
	banner.follow_pressed.connect(_on_follow_banner_pressed)
	banner.stop_pressed.connect(stop_following)
	banner.locate_pressed.connect(func() -> void: focus_on_person(_selected_id))
	_restore_follow()
	# The world is on screen: the motion sensors have something to move.
	SensorManager.set_world_visible(true)
	tilt_stick = TiltStick.new()
	debug_overlay.add_child(tilt_stick)
	tilt_stick.visible = debug_overlay.is_shown()
	debug_overlay.register_section(&"motion", func() -> String: return SensorManager.debug_text())
	# What happens in the world is told as it happens (and shown where).
	NotificationManager.bind(session.events, session.people)
	NotificationManager.quiet = follow.is_following()
	ui_root.locate_requested.connect(look_at_place)
	input_router.gesture_recognized.connect(_on_gesture)
	world_view.camera_rig().handles_double_tap = false # decided in _on_gesture
	session.interactions.responded.connect(world_view.effects().play)
	session.behavior.worked.connect(_on_person_worked)
	session.behavior.reacted.connect(_on_person_reacted)
	session.nodes.depleted.connect(_on_node_depleted)
	if session.settlement != null:
		session.settlement.fire_changed.connect(world_view.set_fire_lit)
		world_view.set_fire_lit(session.settlement.fire_lit())
	session.interactions.responded.connect(func(response: InteractionResponse) -> void:
		if response != null and response.person_id != 0 and response.effect == InteractionResponse.PERSON_TOUCH:
			ui_root.hints().complete(HintDirector.TOUCH))
	session.interactions.responded.connect(TouchFeedback.play)
	AudioManager.start_ambience()
	_begin_opening()
	ui_root.home_pressed.connect(go_home)
	debug_overlay.register_section(&"pick", func() -> String: return "pick %s" % _last_pick)
	debug_overlay.register_section(&"camera", _camera_debug_section)
	debug_overlay.register_section(&"world", _world_debug_section)
	debug_overlay.register_section(&"save", _save_debug_section)
	debug_overlay.register_section(&"moving", func() -> String:
		return "moving %d  step %.2f ms   water %d tiles  step %.2f ms" % [
			session.loose_system.moving_count(), session.loose_system.last_step_usec / 1000.0,
			session.water.active_count(), session.water.last_step_usec / 1000.0])
	debug_overlay.register_section(&"people", _people_debug_section)
	debug_overlay.register_section(&"doing", _doing_debug_section)
	debug_overlay.register_section(&"perception", func() -> String:
		return "%s  reactions %d
%s" % [session.perception.debug_text(), session.behavior.reactions, session.memories.debug_text()])
	debug_overlay.register_section(&"settlement", func() -> String:
		return session.settlement.debug_text() if session.settlement != null else "settlement: none")
	debug_overlay.register_section(&"animals", func() -> String:
		return session.fauna.debug_text())
	debug_overlay.register_section(&"events", func() -> String:
		return "%s\n%s\n%s" % [session.events.debug_text(3), NotificationManager.debug_text(), session.stats.debug_text()])
	debug_overlay.register_section(&"farming", func() -> String:
		return session.farming.debug_text(session.clock.tick))
	debug_overlay.register_section(&"resources", func() -> String:
		var carried := 0
		for person: PersonData in session.people.all_people():
			carried += person.carrying_amount
		var fire := session.props.get_prop(session.start.campfire_id) if session.start != null else null
		return "%s  carried %d\n%s" % [session.piles.debug_text(fire.position2d() if fire != null else Vector2.INF, 4.0),
			carried, session.nodes.debug_text()])
	debug_overlay.register_section(&"paths", func() -> String:
		var finder := session.pathfinder
		return "paths: %d walking  %d queued  %.2f/frame  %d found  %d from cache  %.2f ms last" % [
			session.movement.walking_count(), finder.queue_size(), session.simulation.average_paths,
			finder.paths_found, finder.cache_hits, finder.last_path_usec / 1000.0])
	debug_overlay.register_section(&"history", func() -> String:
		var history := session.history
		return "history %d interventions  %d remembered  %d people touched  achievements: %s" % [history.total(),
			history.entry_count(), history.people_touched(), ", ".join(history.achievements().keys())])
	debug_overlay.register_section(&"feedback", func() -> String:
		return "%s\nhaptics %d (%d dropped)%s" % [AudioManager.debug_text(), Haptics.pulses_played,
			Haptics.pulses_skipped, "" if Haptics.enabled else "  off"])


func _process(delta: float) -> void:
	# Whoever the player is looking at is simulated most closely.
	var pivot := world_view.camera_rig().pivot()
	session.simulation.tiers.look_at(Vector2(pivot.x, pivot.z))
	if _observing:
		world_view.people_view().show_trail(_way_of(_selected_id))
	_advance_follow(delta)
	session.watch_followed(follow.person_id if follow.is_following() else 0)
	_update_locate()
	ui_root.hints().set_person_in_view(world_view.people_view().shown_count() > 0)
	# The inspector is part of the debug overlay; it shows whoever is selected.
	var debugging := debug_overlay.is_shown()
	inspector.visible = debugging
	tilt_stick.visible = debugging and SensorManager.virtual_allowed
	if debugging:
		if inspector.inspected_id() != _selected_id:
			if _selected_id == 0:
				inspector.clear()
			else:
				inspector.inspect(_selected_id)
		var card := ui_root.person_card()
		inspector.set_bottom_margin(AiInspector.BOTTOM_MARGIN + (card.size.y + 20.0 if card != null else 0.0))


func _exit_tree() -> void:
	SensorManager.set_world_visible(false)
	SaveManager.attach(null)
	AudioManager.stop_ambience()


func _setup_inspector() -> void:
	inspector = AiInspector.new()
	debug_overlay.add_child(inspector)
	inspector.bind(session)
	inspector.visible = debug_overlay.is_shown()
	inspector.spawn_requested.connect(_on_spawn_requested)
	inspector.kill_requested.connect(func(person_id: int) -> void: session.kill_person(person_id))
	inspector.dismissed.connect(clear_selection)


## Debug: a newcomer appears where the player is looking.
func _on_spawn_requested() -> void:
	var pivot := world_view.camera_rig().pivot()
	var person := session.spawn_person(WorldCoords.world2d_to_tile(Vector2(pivot.x, pivot.z)))
	if person != null:
		select_person(person.id)


# --- the selected person ------------------------------------------------------------------------

## Selects a person: their card opens (at least at `card_state`), they are
## ringed in the world and come into the player's focus. False if there is
## no such person.
func select_person(person_id: int, card_state: PersonCard.State = PersonCard.State.PEEK) -> bool:
	if not session.is_active or not session.people.has_person(person_id):
		return false
	if person_id != _selected_id:
		_selected_id = person_id
		_observing = false
		world_view.people_view().show_trail(PackedVector3Array())
		world_view.people_view().set_selected(person_id)
		EventBus.person_selected.emit(person_id)
	var card := ui_root.open_person_card(session, person_id, card_state)
	card.set_observing(_observing)
	card.set_following(follow.is_following() and follow.person_id == person_id)
	return true


## Nobody is selected any more.
func clear_selection() -> void:
	if _selected_id == 0:
		return
	_selected_id = 0
	_observing = false
	world_view.people_view().set_selected(0)
	world_view.people_view().show_trail(PackedVector3Array())
	EventBus.person_selected.emit(-1)
	var card := ui_root.person_card()
	if card != null:
		card.close()


func selected_person_id() -> int:
	return _selected_id


func is_observing() -> bool:
	return _observing


## Looks at a person, no further away than the settlement is seen from.
## Looking at the person who is followed takes the following up again;
## looking at anyone else leaves it for later.
func focus_on_person(person_id: int) -> void:
	var person := session.people.get_person(person_id)
	if person == null:
		return
	if follow.person_id == person_id:
		follow.resume()
	else:
		follow.pause()
	var rig := world_view.camera_rig()
	rig.focus_on(world_view.people_view().ground_position(person), minf(rig.distance(), Config.camera.home_distance))


# --- following ----------------------------------------------------------------------------------

## The camera follows a person from now on (and comes closer if it is far
## away). Whoever was followed before is let go. False if there is no such
## person.
func follow_person(person_id: int) -> bool:
	var person := session.people.get_person(person_id) if session.is_active else null
	if person == null:
		return false
	if follow.person_id != person_id:
		_unflag_followed()
		person.set_flag(PersonData.FLAG_FOLLOWED, true)
		SaveManager.note_world_changed()
		follow.start(person_id)
		EventBus.person_followed.emit(person_id)
	else:
		follow.resume()
	ui_root.hints().complete(HintDirector.FOLLOW)
	var rig := world_view.camera_rig()
	rig.focus_on(world_view.people_view().ground_position(person), minf(rig.distance(), Config.camera.home_distance))
	return true


## Nobody is followed any more.
func stop_following() -> void:
	if not follow.is_active():
		return
	_unflag_followed()
	SaveManager.note_world_changed()
	follow.stop()
	EventBus.person_followed.emit(-1)


func _unflag_followed() -> void:
	var was := session.people.get_person(follow.person_id)
	if was != null:
		was.set_flag(PersonData.FLAG_FOLLOWED, false)


## Whoever was followed when the world was saved is offered again: not with
## the camera on them (the game opens on the settlement), but a tap away.
func _restore_follow() -> void:
	for person: PersonData in session.people.all_people():
		if not person.has_flag(PersonData.FLAG_FOLLOWED):
			continue
		if follow.is_active():
			person.set_flag(PersonData.FLAG_FOLLOWED, false) # one at a time
			continue
		follow.start(person.id)
		follow.pause()
		EventBus.person_followed.emit(person.id)


## Keeps the followed person in the part of the screen that is free.
func _advance_follow(delta: float) -> void:
	if not follow.is_following() or tools.is_busy():
		_follow_seen = Vector3.INF
		return
	var person := session.people.get_person(follow.person_id) if session.is_active else null
	if person == null:
		stop_following()
		return
	var rig := world_view.camera_rig()
	var card := ui_root.person_card()
	var free_bottom := card.get_global_rect().position.y if card != null else ui_root.tool_bar().get_global_rect().position.y
	var at := world_view.people_view().shown_position(person) + Vector3(0.0, PersonMeshLibrary.ADULT_HEIGHT * 0.5, 0.0)
	# The view glides after its goal and so trails a walker by a little: aim
	# that little ahead of them, and they stay where they are meant to be.
	var lead := Vector3.ZERO
	if _follow_seen != Vector3.INF and delta > 0.0:
		lead = ((at - _follow_seen) / delta / Config.camera.smoothing).limit_length(FOLLOW_LEAD_MAX)
		lead.y = 0.0
	_follow_seen = at
	rig.track(at + lead, CameraFollow.anchor(rig.view_size(), ui_root.follow_banner().bottom(), free_bottom))


func _on_follow_changed() -> void:
	# While the camera is with someone, only what matters a great deal is told.
	NotificationManager.quiet = follow.is_following()
	var person := session.people.get_person(follow.person_id)
	ui_root.follow_banner().set_following(person.given_name if person != null else "", follow.state == CameraFollow.State.PAUSED)
	var card := ui_root.person_card()
	if card != null:
		card.set_following(follow.is_following() and card.person_id() == follow.person_id)


## The banner's text: while following it shows who; paused, it resumes.
func _on_follow_banner_pressed() -> void:
	if follow.state == CameraFollow.State.PAUSED:
		follow_person(follow.person_id)
	else:
		select_person(follow.person_id)


## "Find …" is offered while the selected person is out of sight.
func _update_locate() -> void:
	var person := session.people.get_person(_selected_id) if _selected_id != 0 and session.is_active else null
	var lost := false
	if person != null and not (follow.is_following() and follow.person_id == _selected_id):
		var rig := world_view.camera_rig()
		var at := rig.world_to_screen(world_view.people_view().ground_position(person))
		var card := ui_root.person_card()
		var bottom := card.get_global_rect().position.y if card != null else rig.view_size().y
		lost = not Rect2(0.0, 0.0, rig.view_size().x, maxf(bottom, 0.0)).has_point(at)
	ui_root.follow_banner().set_locate(person.given_name if lost else "")


## The id of the person a pick found (0 if it found something else).
func _person_in(target: Picker.Result) -> int:
	if target != null and target.kind == Picker.Kind.ENTITY and session.people.has_person(target.entity_id):
		return target.entity_id
	return 0


## Touches a person as a finger on them would.
func _touch_person(person_id: int) -> void:
	var person := session.people.get_person(person_id)
	if person == null:
		return
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = person_id
	target.entity_kind = SpatialIndex.KIND_PERSON
	target.tile = person.position
	target.position = world_view.people_view().ground_position(person)
	target.direct = true
	_note_pick(target, session.interactions.tap(target, tools.current_id()))


## The way a walking person still has to go, as points on the ground.
func _way_of(person_id: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	if person_id == 0 or not session.is_active:
		return points
	var world := session.world
	for tile: Vector2i in session.movement.remaining_path(person_id):
		points.append(Vector3(tile.x + 0.5, world.get_height(tile) * world.height_step, tile.y + 0.5))
	return points


func _on_person_action(action: StringName, person_id: int) -> void:
	var person := session.people.get_person(person_id)
	if person == null:
		return
	match action:
		PersonCard.ACTION_OBSERVE:
			_observing = not _observing and person_id == _selected_id
			if not _observing:
				world_view.people_view().show_trail(PackedVector3Array())
			var card := ui_root.person_card()
			if card != null:
				card.set_observing(_observing)
		PersonCard.ACTION_TOUCH:
			_touch_person(person_id)
		PersonCard.ACTION_FOLLOW:
			if follow.is_following() and follow.person_id == person_id:
				stop_following()
			else:
				follow_person(person_id)
		PersonCard.ACTION_FOCUS:
			focus_on_person(person_id)
		PersonCard.ACTION_MARK:
			person.set_flag(PersonData.FLAG_MARKED_IMPORTANT, not person.has_flag(PersonData.FLAG_MARKED_IMPORTANT))
			SaveManager.note_world_changed()
			_refresh_pins()
			var card := ui_root.person_card()
			if card != null:
				card.refresh()


## A person was picked in the UI (family on a card, a marked name): go to them.
func _on_person_chosen(person_id: int) -> void:
	var card := ui_root.person_card()
	if select_person(person_id, card.state() if card != null else PersonCard.State.PEEK):
		focus_on_person(person_id)


func _on_person_card_closed(person_id: int) -> void:
	if person_id == _selected_id:
		clear_selection()


func _on_person_removed(person_id: int) -> void:
	if person_id == _selected_id:
		clear_selection()
	if person_id == follow.person_id:
		follow.stop()
		EventBus.person_followed.emit(-1)
	_refresh_pins()


## The names of the people marked as important, at the edge of the screen.
func _refresh_pins() -> void:
	var marked: Array = []
	for person: PersonData in session.people.all_people():
		if person.has_flag(PersonData.FLAG_MARKED_IMPORTANT):
			marked.append([person.id, person.given_name])
	marked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	ui_root.pins().set_people(marked)


func _setup_tools() -> void:
	var context := ToolBase.Context.new()
	context.session = session
	context.view = world_view
	context.ui = ui_root
	context.touch_radius = Config.interaction.touch_radius_dp * input_router.recognizer.units_per_dp
	tools = ToolManager.new()
	tools.name = "Tools"
	add_child(tools)
	tools.setup(context)
	var bar := ui_root.tool_bar()
	bar.set_tools(tools.tool_ids())
	bar.set_current(tools.current_id())
	bar.tool_selected.connect(tools.select)
	tools.tool_changed.connect(bar.set_current)
	EventBus.app_paused.connect(tools.cancel)


## Touches of the world. The active tool sees a gesture first and may keep it
## (a carried rock must not pan the camera); otherwise the camera gets it, and
## taps and presses are answered: the view says what is under the finger, the
## tool and the session's InteractionManager decide what that means.
func _on_gesture(gesture: Gesture) -> void:
	if tools.handle_gesture(gesture):
		ui_root.hints().note_touch() # busy, but carrying a rock is not exploring
		return
	ui_root.hints().note_gesture(gesture)
	world_view.camera_rig().handle_gesture(gesture)
	match gesture.type:
		Gesture.Type.DRAG_START, Gesture.Type.MULTI_START:
			ui_root.dismiss_transient_panels() # moving the view puts the menu away
			# Dragging the view away leaves the followed person to walk on alone
			# (two fingers zoom; the view comes back to them).
			if gesture.type == Gesture.Type.DRAG_START:
				follow.pause()
		Gesture.Type.TAP:
			if _tap_closed_menu:
				_tap_closed_menu = false
				return # that tap only put the menu away
			var target := pick_at(gesture.position)
			# A tap on a person selects them. The hand touches them as well;
			# looking (Observe) does not.
			var tapped := _person_in(target)
			if tapped != 0 and (tools.current_id() == HandTool.ID or tools.current_id() == ObserveTool.ID):
				if tools.current_id() == HandTool.ID:
					_note_pick(target, tools.tap(target))
				select_person(tapped)
				world_view.pick_highlight().clear()
				return
			var response := tools.tap(target)
			if response != null or tools.current_id() == HandTool.ID:
				_note_pick(target, response)
			if debug_overlay.is_shown():
				world_view.show_pick(target)
			else:
				world_view.pick_highlight().clear()
		Gesture.Type.LONG_PRESS:
			var target := pick_at(gesture.position)
			# A press on a person opens their card with what can be done.
			if _person_in(target) != 0:
				select_person(_person_in(target), PersonCard.State.HALF)
				return
			var what := session.interactions.long_press(target)
			_note_pick(target, what)
			if what == null:
				return
			# The pressed thing stays marked while its menu is open.
			world_view.show_pick(target)
			var menu := ui_root.open_context_menu(gesture.position, target, what,
				session.interactions.actions_for(target))
			menu.closed.connect(_on_context_menu_closed)
		Gesture.Type.DOUBLE_TAP:
			var target := pick_at(gesture.position)
			var tool := tools.current()
			# On a person: look at them (the first tap has already said hello).
			if _person_in(target) != 0 and tool.double_tap_moves_camera():
				select_person(_person_in(target))
				focus_on_person(_person_in(target))
				return
			if tool.double_tap_moves_camera():
				# On a thing: look at it. On open ground or water: zoom toward it.
				var what := session.interactions.describe(target)
				var rig := world_view.camera_rig()
				if what != null and what.is_entity():
					follow.pause()
					rig.focus_on(what.position, minf(rig.distance(), Config.camera.home_distance))
				else:
					rig.double_tap_zoom(gesture.position)
					return
			# The second tap is still a tap: two quick taps on a tree shake it twice.
			if tool.double_tap_touches():
				var response := tools.tap(target)
				if response != null:
					_note_pick(target, response)


## Opening shot: the box on its table, then down to where the people live —
## close enough that dragging explores. With reduced motion the view simply
## starts there.
func _begin_opening() -> void:
	if session.start == null or session.start.campfire_id == 0:
		return
	if bool(Settings.get_value(&"accessibility/reduced_motion")):
		var tile := session.start.settlement_tile
		world_view.camera_rig().focus_on(Vector3(tile.x + 0.5, 0.0, tile.y + 0.5), Config.camera.home_distance, false)
		return
	get_tree().create_timer(OPENING_HOLD_SECONDS).timeout.connect(_opening_glide)


func _opening_glide() -> void:
	# Not if the player (or anything else) has already taken the camera.
	if _player_has_touched or not world_view.camera_rig().is_framed():
		return
	go_home()


func _on_world_touched(_position: Vector2) -> void:
	_player_has_touched = true
	world_view.camera_rig().stop_motion()
	ui_root.hints().note_touch()
	_tap_closed_menu = ui_root.dismiss_transient_panels()


## A loose object came to rest: dust or a splash, a thud, a pulse.
func _on_object_landed(id: int, impact_speed: float) -> void:
	var object := session.loose.get_object(id)
	if object == null:
		return
	var tile := object.tile()
	var on_water := session.world.get_water(tile) > WaterMesher.MIN_DEPTH
	var at := object.world_position(session.world)
	if on_water:
		at.y = session.world.get_height(tile) * session.world.height_step + session.world.get_water(tile)
	world_view.effects().play_landing(at, session.world.get_terrain(tile), on_water, object.radius())
	TouchFeedback.landed(at, object.give(), impact_speed, on_water)


## A moving loose object ran into something: a knock.
func _on_object_bumped(id: int, speed: float) -> void:
	var object := session.loose.get_object(id)
	if object != null:
		TouchFeedback.bumped(object.world_position(session.world), object.give(), speed)


func _on_context_menu_closed() -> void:
	if not debug_overlay.is_shown():
		world_view.pick_highlight().clear()


func _on_context_action(action: StringName, target: Picker.Result) -> void:
	match action:
		InteractionManager.ACTION_INSPECT:
			ui_root.open_inspect(session.interactions.inspect(target), session.world.height_step)
		InteractionManager.ACTION_TOUCH:
			_note_pick(target, session.interactions.tap(target, tools.current_id()))
		InteractionManager.ACTION_REMOVE:
			_note_pick(target, session.interactions.uproot(target, tools.current_id()))
		InteractionManager.ACTION_FOCUS:
			var what := session.interactions.describe(target)
			if what != null:
				follow.pause()
				var rig := world_view.camera_rig()
				rig.focus_on(what.position, minf(rig.distance() * LOOK_CLOSER_FACTOR, Config.camera.home_distance))


## What is under a screen position, with the finger-sized forgiveness.
func pick_at(screen: Vector2) -> Picker.Result:
	var radius := Config.interaction.touch_radius_dp * input_router.recognizer.units_per_dp
	tools.current().ctx.touch_radius = radius # keeps the tools' reach in step with the screen
	return world_view.pick(screen, radius)


func _note_pick(target: Picker.Result, response: InteractionResponse) -> void:
	if response == null:
		_last_pick = "nothing"
		return
	var near := target.kind == Picker.Kind.ENTITY and not target.direct
	_last_pick = "%s%s -> %s" % [response.description, " (near)" if near else "", response.effect]


## Glides the camera to a place (world X/Z), no further away than the
## settlement is seen from: where a toast says something happened.
func look_at_place(place: Vector2) -> void:
	if not place.is_finite():
		return
	follow.pause()
	var rig := world_view.camera_rig()
	var tile := Vector2i(floori(place.x), floori(place.y))
	var height := session.world.get_height(tile) * session.world.height_step if session.world.is_in_bounds(tile) else 0.0
	rig.focus_on(Vector3(place.x, height, place.y), minf(rig.distance(), Config.camera.home_distance))


## Glides the camera to the settlement (or frames the box if there is none).
func go_home() -> void:
	follow.pause()
	var rig := world_view.camera_rig()
	if session.start == null or session.start.campfire_id == 0:
		rig.frame_box()
		return
	var tile := session.start.settlement_tile
	rig.focus_on(Vector3(tile.x + 0.5, 0.0, tile.y + 0.5), Config.camera.home_distance)


func _open_world() -> void:
	# Newest first; skip worlds that cannot be loaded (e.g. corrupt with a
	# misleadingly recent header) instead of abandoning continuity.
	for world_id in SaveManager.world_ids_by_recency():
		var loaded := SaveManager.load_world(world_id)
		if loaded.ok and session.load_from(loaded.world):
			return
		Log.error(Log.Category.LOAD, "Could not continue world; trying older", {"world_id": world_id})
	session.create_new()
	SaveManager.save_world(session, &"new_world") # persist immediately


func _world_debug_section() -> String:
	if not session.is_active:
		return "world: none"
	var clock_line := "world tick %d  speed %s  seed %d" % [
		session.clock.tick,
		session.clock.speed_multiplier(),
		session.world_seed,
	]
	var world_line := "%dx%d tiles  %d chunks  %d props  %d loose  settlement %s" % [
		session.world.bounds.size.x, session.world.bounds.size.y,
		session.world.loaded_chunks().size(),
		session.props.size(),
		session.loose.size(),
		session.start.settlement_tile,
	]
	if _world_fingerprint == "":
		# Same seed => same fingerprint on every device (integer generation).
		_world_fingerprint = WorldChecksum.terrain(session.world).substr(0, 8)
	var gen_line := "gen v%d  terrain %s  saved chunks %d  removed props %d" % [
		WorldGenerator.GENERATOR_VERSION, _world_fingerprint,
		session.world.modified_chunks().size(), session.props.removed_generated_count()]
	return clock_line + "\n" + world_line + "\n" + gen_line


func _camera_debug_section() -> String:
	var rig := world_view.camera_rig()
	var at := rig.pivot()
	return "camera at (%.1f, %.1f)  dist %.1f / %.1f  pitch %.0f" % [
		at.x, at.z, rig.distance(), rig.fit_distance(), rig.pitch_degrees()]


## A stroke of someone's work, made visible and audible: the tree shivers
## under the axe, the bush rustles. Quiet, and never more than a few a second
## however many are at it and however fast time runs.
## Someone reacted to something: a small voice — theirs, by how old they are
## — and, if it was the player's own touch that did it, a pulse.
func _on_person_reacted(person_id: int, reaction: StringName, _interpretation: StringName, _stimulus: StringName, direct: bool) -> void:
	var person := session.people.get_person(person_id)
	if person == null:
		return
	if direct:
		Haptics.medium()
	var now := Time.get_ticks_msec()
	if reaction == ReactionTable.DISMISS or reaction == ReactionTable.LISTEN \
			or (not direct and now - _last_voice_msec < VOICE_GAP_MSEC) \
			or world_view.people_view().view_of(person_id) == null:
		return # nothing to say, or nobody near enough to hear it
	_last_voice_msec = now
	AudioManager.play_at(&"voice", world_view.people_view().ground_position(person), -3.0 if direct else -9.0,
		voice_pitch(person, reaction))


## How high someone's voice is: children high, elders low, and higher in
## fright or laughter.
func voice_pitch(person: PersonData, reaction: StringName = &"") -> float:
	var pitch := 1.0
	match person.life_stage(session.clock.tick, Config.time.ticks_per_year(), Config.people):
		PersonData.LifeStage.CHILD:
			pitch = 1.7
		PersonData.LifeStage.ADOLESCENT:
			pitch = 1.3
		PersonData.LifeStage.ELDER:
			pitch = 0.85
	if person.sex == PersonData.Sex.FEMALE:
		pitch *= 1.18
	if reaction == ReactionTable.LAUGH or reaction == ReactionTable.RUN or reaction == ReactionTable.YELL:
		pitch *= 1.15
	elif reaction == ReactionTable.PRAY:
		pitch *= 0.9
	return pitch


## A node has given up the last of what it had: a tree comes down.
func _on_node_depleted(prop_id: int) -> void:
	var prop := session.props.get_prop(prop_id)
	if prop == null or prop.kind != PropData.Kind.TREE:
		return
	var answer := InteractionResponse.new()
	answer.effect = InteractionResponse.TREE_UPROOT
	answer.entity_id = prop.id
	answer.tile = prop.tile
	var at := prop.position2d()
	answer.position = Vector3(at.x, session.world.get_height(prop.tile) * session.world.height_step, at.y)
	answer.body = Vector2(1.5, 0.4) * prop.scale() # (the tree that was)
	answer.strength = 0.6
	world_view.effects().play(answer)
	AudioManager.play_at(&"rustle", answer.position, -6.0, 0.7)


func _on_person_worked(person_id: int, kind: StringName, target_id: int) -> void:
	var now := Time.get_ticks_msec()
	if kind == &"fire" or now - _last_work_effect_msec < WORK_EFFECT_GAP_MSEC:
		return
	var person := session.people.get_person(person_id)
	var prop := session.props.get_prop(target_id)
	if person == null or prop == null or world_view.people_view().view_of(person_id) == null:
		return # nobody is watching
	_last_work_effect_msec = now
	var answer := InteractionResponse.new()
	answer.effect = InteractionResponse.TREE_SHAKE if kind == &"tree" else InteractionResponse.BUSH_RUSTLE
	answer.entity_id = prop.id
	answer.tile = prop.tile
	var at := prop.position2d()
	answer.position = Vector3(at.x, session.world.get_height(prop.tile) * session.world.height_step, at.y)
	answer.body = prop.pick_shape()
	answer.strength = 0.35
	world_view.effects().play(answer)
	if kind == &"tree":
		AudioManager.play_at(&"knock", answer.position, -13.0, 0.85)


func _doing_debug_section() -> String:
	if not session.is_active:
		return "doing: -"
	var counts := session.behavior.counts()
	var names: Array = counts.keys()
	names.sort()
	var parts := PackedStringArray()
	for activity: StringName in names:
		parts.append("%s %d" % [activity if activity != &"" else &"nothing", counts[activity]])
	var sim := session.simulation
	var tiers := sim.tiers.counts()
	return "%s  doing: %s  (%d decisions, %d spared)\nsim %.3f ms/frame of %.1f (live %.3f paths %.3f move %.3f)  worst %.2f  deferred %d\nactive AI %d  tiers 4:%d 3:%d 2:%d%s" % [session.clock.format_date(),
		", ".join(parts), session.behavior.decisions, session.behavior.skipped, sim.average_usec / 1000.0,
		Config.perf.sim_budget_ms_per_frame, sim.average_live_usec / 1000.0, sim.average_paths_usec / 1000.0,
		sim.average_move_usec / 1000.0, sim.worst_usec / 1000.0, sim.deferred_total,
		(tiers.get(TierManager.FOCUS, 0) + tiers.get(TierManager.ACTIVE, 0) + tiers.get(TierManager.REGIONAL, 0))
			if session.behavior.enabled else 0,
		tiers.get(TierManager.FOCUS, 0), tiers.get(TierManager.ACTIVE, 0), tiers.get(TierManager.REGIONAL, 0),
		"" if session.behavior.enabled else "  FROZEN"]


func _people_debug_section() -> String:
	if not session.is_active:
		return "people: none"
	var year := Config.time.ticks_per_year()
	var stages := [0, 0, 0, 0]
	for person in session.people.all_people():
		stages[person.life_stage(session.clock.tick, year, Config.people)] += 1
	return "people %d in %d households  (%d children, %d youths, %d adults, %d elders)
  drawn: %s" % [
		session.people.size(), session.people.household_ids().size(),
		stages[PersonData.LifeStage.CHILD], stages[PersonData.LifeStage.ADOLESCENT],
		stages[PersonData.LifeStage.ADULT], stages[PersonData.LifeStage.ELDER],
		world_view.people_view().debug_text()]


func _save_debug_section() -> String:
	var info := SaveManager.last_save_info
	if info.is_empty():
		return "save: none yet"
	if info.has("error"):
		return "save FAILED: %s" % info["error"]
	return "save %s  %.1f ms  %d B  %ds ago%s" % [
		info["reason"], info["ms"], info["bytes"],
		int(Time.get_unix_time_from_system()) - int(info["unix"]),
		"  (change pending)" if SaveManager.has_unsaved_change() else "",
	]

