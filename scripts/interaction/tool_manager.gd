class_name ToolManager
extends Node
## Keeps the player's tools and which one is active (bible §23.2). Gestures are
## offered to the active tool first; what it does not keep goes on to the
## camera and the default touch handling.
##
## Which tools there are grows with the world (`ToolReveals`): the hand and
## the eye from the first moment; rain, wind and water when they have shown
## themselves. (Debug builds have them all at once, and the prototypes.)

signal tool_changed(id: StringName)
## The set of tools has changed (one has shown itself).
signal tools_changed

## Every tool there is, whatever has shown itself: debug builds (or debug
## tools unlocked). Tests of the reveal switch it off.
var show_all := false

var _tools: Dictionary = {} # id -> ToolBase
var _order: Array[StringName] = []
var _current: ToolBase
var _context: ToolBase.Context
var _reveals: ToolReveals


## Creates the tools there are so far and selects the hand. `reveals` says
## which powers have shown themselves (none without it).
func setup(context: ToolBase.Context, reveals: ToolReveals = null) -> void:
	_context = context
	_reveals = reveals
	show_all = DebugOverlay.is_available()
	if _current != null:
		_current.deactivate()
	_current = null
	_build()
	select(HandTool.ID)


## Looks again at which tools there are (one has shown itself). The active
## tool stays the active one.
func refresh() -> void:
	var was := current_id()
	if _current != null:
		_current.deactivate()
	_current = null
	_build()
	if not select(was):
		select(HandTool.ID)
	tools_changed.emit()


func register(tool: ToolBase) -> void:
	tool.setup(_context)
	_tools[tool.id] = tool
	_order.append(tool.id)


## Tool ids in tool-bar order.
func tool_ids() -> Array[StringName]:
	return _order.duplicate()


func has_tool(id: StringName) -> bool:
	return _tools.has(id)


func current() -> ToolBase:
	return _current


func current_id() -> StringName:
	return _current.id if _current != null else &""


func get_tool(id: StringName) -> ToolBase:
	return _tools.get(id)


## Makes a tool the active one. False for an unknown id.
func select(id: StringName) -> bool:
	var tool: ToolBase = _tools.get(id)
	if tool == null:
		return false
	if tool == _current:
		return true
	if _current != null:
		_current.deactivate()
	_current = tool
	_current.activate()
	tool_changed.emit(id)
	EventBus.tool_changed.emit(id)
	return true


## True if the active tool kept the gesture.
func handle_gesture(gesture: Gesture) -> bool:
	return _current != null and _current.handle_gesture(gesture)


## The finger left the world (hook for InputRouter.touch_ended).
func touch_ended(_position: Vector2 = Vector2.ZERO) -> void:
	if _current != null:
		_current.touch_ended()


func tap(target: Picker.Result) -> InteractionResponse:
	return _current.tap(target) if _current != null else null


func is_busy() -> bool:
	return _current != null and _current.is_busy()


## Finishes whatever the active tool is doing (the world is closing, the app
## is going to the background).
func cancel() -> void:
	if _current != null:
		_current.deactivate()
		_current.activate()


func _process(delta: float) -> void:
	if _current != null:
		_current.update(delta)


func _exit_tree() -> void:
	if _current != null:
		_current.deactivate()


func _build() -> void:
	_tools.clear()
	_order.clear()
	register(HandTool.new())
	register(ObserveTool.new())
	if _shown(ToolReveals.RAIN):
		register(RainTool.new())
	if _shown(ToolReveals.WIND):
		register(WindTool.new())
	if _shown(ToolReveals.WATER):
		register(WaterTool.new())
	if DebugOverlay.is_available():
		register(CallTool.new()) # prototype: debug builds, or debug tools unlocked


func _shown(id: StringName) -> bool:
	return show_all or (_reveals != null and _reveals.is_known(id))
