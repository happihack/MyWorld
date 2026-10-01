extends Node
## Main scene root: wires WorldSession, WorldView and UIRoot together.
## Until SaveManager exists (M0.6) every launch starts a new world.

@onready var session: WorldSession = $WorldSession
@onready var ui_root: UIRoot = $UIRoot


func _ready() -> void:
	session.create_new()
	ui_root.bind_session(session)

