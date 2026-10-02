class_name ObserveTool
extends ToolBase
## Looking without touching (bible §23.2): a tap shows what something is
## instead of disturbing it, and nothing can be picked up. Nothing done with
## this tool is noticed by the world's inhabitants.
##
## Hold a finger still for a moment and then draw it across the land: the
## card tells of each tile it passes (a trail of what the ground is like).
## A quick drag still moves the view.

const ID := &"observe"
const TRAIL_RING := Color(1.0, 0.95, 0.80, 0.55)
const _NOWHERE := Vector2i(-1_000_000, -1_000_000)

var _trail := false
var _moved := false
var _last := _NOWHERE
## How many tiles the trail going on (or the last one) has told of.
var trail_tiles := 0


func _init() -> void:
	id = ID


func deactivate() -> void:
	_trail = false


func touch_ended() -> void:
	_trail = false


func is_busy() -> bool:
	return _trail and _moved


func handle_gesture(gesture: Gesture) -> bool:
	match gesture.type:
		Gesture.Type.HOLD:
			_trail = true
			_moved = false
			_last = _NOWHERE
			trail_tiles = 0
			return false # (lifting the finger now is still a tap)
		Gesture.Type.DRAG_START:
			return _trail
		Gesture.Type.LONG_PRESS:
			return _trail and _moved
		Gesture.Type.DRAG:
			if not _trail:
				return false
			look_at(gesture.position)
			return true
		Gesture.Type.DRAG_END, Gesture.Type.SWIPE:
			var was := _trail
			_trail = false
			return was
		Gesture.Type.TAP, Gesture.Type.DOUBLE_TAP, Gesture.Type.MULTI_START:
			_trail = false
	return false


func tap(target: Picker.Result) -> InteractionResponse:
	var report := ctx.session.interactions.inspect(target)
	if report != null and ctx.ui != null:
		ctx.ui.open_inspect(report, ctx.session.world.height_step)
	return null


## The finger is over a screen position: if that is another tile than
## before, the card tells of it. True if it did.
func look_at(screen: Vector2) -> bool:
	if ctx == null or ctx.view == null:
		return false
	# (The ground itself, not what stands on it: a trail is about the land.)
	var target := ctx.view.pick(screen, ctx.touch_radius, 0)
	if target == null or not target.is_hit() or target.tile == _last:
		return false
	_last = target.tile
	_moved = true
	var report := ctx.session.interactions.inspect(target)
	if report == null:
		return false
	trail_tiles += 1
	if ctx.ui != null:
		ctx.ui.show_inspect(report, ctx.session.world.height_step)
	ctx.view.effects().ring(surface_at(Vector2(target.tile) + Vector2(0.5, 0.5)), 0.5, 0.7, TRAIL_RING)
	return true
