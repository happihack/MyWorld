class_name ToolManager
extends Node
## Keeps the player's tools and which one is active (bible §23.2). Gestures are
## offered to the active tool first; what it does not keep goes on to the
## camera and the default touch handling.

signal tool_changed(id: StringName)

var _tools: Dictionary = {} # id -> ToolBase
var _order: Array[StringName] = []
var _current: ToolBase
var _context: ToolBase.Context


## Creates the tools that exist so far and selects the hand.
func setup(context: ToolBase.Context) -> void:
	_context = context
	_tools.clear()
	_order.clear()
	_current = null
	register(HandTool.new())
	register(ObserveTool.new())
	if DebugOverlay.is_available():
		register(WaterTool.new()) # prototype: debug builds, or debug tools unlocked
	select(HandTool.ID)


func register(tool: ToolBase) -> void:
	tool.setup(_context)
	_tools[tool.id] = tool
	_order.append(tool.id)


## Tool ids in tool-bar order.
func tool_ids() -> Array[StringName]:
	return _order.duplicate()


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
