extends Node
## Main scene root: wires WorldSession, WorldView and UIRoot together.
## Until SaveManager exists (M0.6) every launch starts a new world.

@onready var session: WorldSession = $WorldSession
@onready var ui_root: UIRoot = $UIRoot
@onready var input_router: InputRouter = $InputRouter
@onready var debug_overlay: DebugOverlay = $DebugOverlay


func _ready() -> void:
	session.create_new()
	ui_root.bind_session(session)
	input_router.gesture_recognized.connect(debug_overlay.on_gesture)
	debug_overlay.register_section(&"world", _world_debug_section)


func _world_debug_section() -> String:
	if not session.is_active:
		return "world: none"
	return "world tick %d  speed %s  seed %d" % [
		session.clock.tick,
		session.clock.speed_multiplier(),
		session.world_seed,
	]

