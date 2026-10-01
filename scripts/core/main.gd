extends Node
## Main scene root: wires WorldSession, WorldView and UIRoot together.
## On launch it continues the most recently saved world; if there is none, or it
## cannot be loaded, it starts a new world (broken saves are left untouched).

@onready var session: WorldSession = $WorldSession
@onready var world_view: WorldView = $WorldView
@onready var ui_root: UIRoot = $UIRoot
@onready var input_router: InputRouter = $InputRouter
@onready var debug_overlay: DebugOverlay = $DebugOverlay

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


func _ready() -> void:
	_open_world()
	world_view.show_world(session.world, session.props, session.start, session.loose)
	SaveManager.attach(session)
	ui_root.bind_session(session)
	input_router.gesture_recognized.connect(debug_overlay.on_gesture)
	input_router.gesture_recognized.connect(world_view.camera_rig().handle_gesture)
	input_router.touch_began.connect(_on_world_touched)
	ui_root.context_action.connect(_on_context_action)
	input_router.gesture_recognized.connect(_on_gesture)
	input_router.gesture_recognized.connect(ui_root.hints().note_gesture)
	world_view.camera_rig().handles_double_tap = false # decided in _on_gesture
	session.interactions.responded.connect(world_view.effects().play)
	session.interactions.responded.connect(TouchFeedback.play)
	AudioManager.start_ambience()
	_begin_opening()
	ui_root.home_pressed.connect(go_home)
	debug_overlay.register_section(&"pick", func() -> String: return "pick %s" % _last_pick)
	debug_overlay.register_section(&"camera", _camera_debug_section)
	debug_overlay.register_section(&"world", _world_debug_section)
	debug_overlay.register_section(&"save", _save_debug_section)
	debug_overlay.register_section(&"feedback", func() -> String:
		return "%s\nhaptics %d (%d dropped)%s" % [AudioManager.debug_text(), Haptics.pulses_played,
			Haptics.pulses_skipped, "" if Haptics.enabled else "  off"])


func _exit_tree() -> void:
	SaveManager.attach(null)
	AudioManager.stop_ambience()


## Touches of the world: the view says what is under the finger, the session's
## InteractionManager decides what that means, the view shows the answer.
func _on_gesture(gesture: Gesture) -> void:
	match gesture.type:
		Gesture.Type.DRAG_START, Gesture.Type.MULTI_START:
			ui_root.dismiss_transient_panels() # moving the view puts the menu away
		Gesture.Type.TAP:
			if _tap_closed_menu:
				_tap_closed_menu = false
				return # that tap only put the menu away
			var target := pick_at(gesture.position)
			_note_pick(target, session.interactions.tap(target))
			if debug_overlay.is_shown():
				world_view.show_pick(target)
			else:
				world_view.pick_highlight().clear()
		Gesture.Type.LONG_PRESS:
			var target := pick_at(gesture.position)
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
			# On a thing: look at it. On open ground or water: zoom toward it.
			var what := session.interactions.describe(pick_at(gesture.position))
			var rig := world_view.camera_rig()
			if what != null and what.is_entity():
				rig.focus_on(what.position, minf(rig.distance(), Config.camera.home_distance))
			else:
				rig.double_tap_zoom(gesture.position)


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


func _on_context_menu_closed() -> void:
	if not debug_overlay.is_shown():
		world_view.pick_highlight().clear()


func _on_context_action(action: StringName, target: Picker.Result) -> void:
	match action:
		InteractionManager.ACTION_INSPECT:
			ui_root.open_inspect(session.interactions.inspect(target), session.world.height_step)
		InteractionManager.ACTION_TOUCH:
			_note_pick(target, session.interactions.tap(target))
		InteractionManager.ACTION_FOCUS:
			var what := session.interactions.describe(target)
			if what != null:
				var rig := world_view.camera_rig()
				rig.focus_on(what.position, minf(rig.distance() * LOOK_CLOSER_FACTOR, Config.camera.home_distance))


## What is under a screen position, with the finger-sized forgiveness.
func pick_at(screen: Vector2) -> Picker.Result:
	var radius := Config.interaction.touch_radius_dp * input_router.recognizer.units_per_dp
	return world_view.pick(screen, radius)


func _note_pick(target: Picker.Result, response: InteractionResponse) -> void:
	if response == null:
		_last_pick = "nothing"
		return
	var near := target.kind == Picker.Kind.ENTITY and not target.direct
	_last_pick = "%s%s -> %s" % [response.description, " (near)" if near else "", response.effect]


## Glides the camera to the settlement (or frames the box if there is none).
func go_home() -> void:
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


func _save_debug_section() -> String:
	var info := SaveManager.last_save_info
	if info.is_empty():
		return "save: none yet"
	if info.has("error"):
		return "save FAILED: %s" % info["error"]
	return "save %s  %.1f ms  %d B  %ds ago" % [
		info["reason"], info["ms"], info["bytes"],
		int(Time.get_unix_time_from_system()) - int(info["unix"]),
	]

