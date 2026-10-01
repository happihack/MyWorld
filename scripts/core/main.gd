extends Node
## Main scene root: wires WorldSession, WorldView and UIRoot together.
## On launch it continues the most recently saved world; if there is none, or it
## cannot be loaded, it starts a new world (broken saves are left untouched).

@onready var session: WorldSession = $WorldSession
@onready var world_view: WorldView = $WorldView
@onready var ui_root: UIRoot = $UIRoot
@onready var input_router: InputRouter = $InputRouter
@onready var debug_overlay: DebugOverlay = $DebugOverlay

var _world_fingerprint := ""
var _last_pick := "-"


func _ready() -> void:
	_open_world()
	world_view.show_world(session.world, session.props, session.start)
	SaveManager.attach(session)
	ui_root.bind_session(session)
	input_router.gesture_recognized.connect(debug_overlay.on_gesture)
	input_router.gesture_recognized.connect(world_view.camera_rig().handle_gesture)
	input_router.touch_began.connect(func(_pos: Vector2) -> void: world_view.camera_rig().stop_motion())
	input_router.gesture_recognized.connect(_on_gesture)
	ui_root.home_pressed.connect(go_home)
	debug_overlay.register_section(&"pick", func() -> String: return "pick %s" % _last_pick)
	debug_overlay.register_section(&"camera", _camera_debug_section)
	debug_overlay.register_section(&"world", _world_debug_section)
	debug_overlay.register_section(&"save", _save_debug_section)


func _exit_tree() -> void:
	SaveManager.attach(null)


## TEMPORARY until the InteractionManager (M2.3): taps are picked and reported
## in the debug overlay, with a highlight while the overlay is shown.
func _on_gesture(gesture: Gesture) -> void:
	if gesture.type != Gesture.Type.TAP:
		return
	var radius := Config.interaction.touch_radius_dp * input_router.recognizer.units_per_dp
	var result := world_view.pick(gesture.position, radius)
	_last_pick = describe_pick(result)
	if debug_overlay.is_shown():
		world_view.show_pick(result)
	else:
		world_view.pick_highlight().clear()


## One-line description of a pick result (debug overlay).
func describe_pick(result: Picker.Result) -> String:
	match result.kind:
		Picker.Kind.ENTITY:
			var prop := session.props.get_prop(result.entity_id)
			var label: String = PropData.Kind.keys()[prop.kind] if prop != null else "entity"
			return "%s at %s%s" % [label, result.tile, "" if result.direct else " (near)"]
		Picker.Kind.WATER:
			return "WATER at %s  depth %.2f" % [result.tile, session.world.get_water(result.tile)]
		Picker.Kind.TILE:
			var terrain: String = ChunkData.Terrain.keys()[session.world.get_terrain(result.tile)]
			return "%s at %s  height %d" % [terrain, result.tile, session.world.get_height(result.tile)]
	return "nothing"


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
	var world_line := "%dx%d tiles  %d chunks  %d props  settlement %s" % [
		session.world.bounds.size.x, session.world.bounds.size.y,
		session.world.loaded_chunks().size(),
		session.props.size(),
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

