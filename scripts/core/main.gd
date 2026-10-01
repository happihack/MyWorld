extends Node
## Main scene root: wires WorldSession, WorldView and UIRoot together.
## On launch it continues the most recently saved world; if there is none, or it
## cannot be loaded, it starts a new world (broken saves are left untouched).

@onready var session: WorldSession = $WorldSession
@onready var ui_root: UIRoot = $UIRoot
@onready var input_router: InputRouter = $InputRouter
@onready var debug_overlay: DebugOverlay = $DebugOverlay


func _ready() -> void:
	_open_world()
	SaveManager.attach(session)
	ui_root.bind_session(session)
	input_router.gesture_recognized.connect(debug_overlay.on_gesture)
	debug_overlay.register_section(&"world", _world_debug_section)
	debug_overlay.register_section(&"save", _save_debug_section)


func _exit_tree() -> void:
	SaveManager.attach(null)


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
	return "world tick %d  speed %s  seed %d" % [
		session.clock.tick,
		session.clock.speed_multiplier(),
		session.world_seed,
	]


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

