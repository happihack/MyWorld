extends Node
## Main scene root: wires WorldSession, WorldView and UIRoot together.
## Until SaveManager exists (M0.6) every launch starts a new world.

@onready var session: WorldSession = $WorldSession
@onready var ui_root: UIRoot = $UIRoot
@onready var input_router: InputRouter = $InputRouter


func _ready() -> void:
	session.create_new()
	ui_root.bind_session(session)
	input_router.gesture_recognized.connect(ui_root.show_gesture)

