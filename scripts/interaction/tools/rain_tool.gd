class_name RainTool
extends ToolBase
## RAIN (bible §23.2, M9.5): hold a finger on the world and a cloud forms
## over it and rains for as long as the finger stays — move the finger and
## the cloud follows. How long decides how much: a little is a gentle thing
## to do, a great deal is not (the river rises with it).
##
## A quick drag still moves the view; only a finger that rests makes rain.

const ID := &"rain"
## How fast the cloud follows the finger (tiles a second).
const CLOUD_SPEED := 9.0

var _raining := false
var _finger := Vector2.ZERO
## Where the cloud is (world X/Z), how long it has rained and how much has fallen.
var _at := Vector2.ZERO
var _seconds := 0.0
var _since_pulse := 0.0
var _units := 0.0
var _rng := RandomNumberGenerator.new() # looks only (where a ripple shows)


func _init() -> void:
	id = ID


func deactivate() -> void:
	stop()


func touch_ended() -> void:
	stop()


func is_busy() -> bool:
	return _raining


func is_raining() -> bool:
	return _raining


## How much has fallen in this go (units of rain).
func fallen() -> float:
	return _units


func cloud_at() -> Vector2:
	return _at


func handle_gesture(gesture: Gesture) -> bool:
	match gesture.type:
		Gesture.Type.HOLD:
			return begin_at(gesture.position)
		Gesture.Type.DRAG_START, Gesture.Type.LONG_PRESS:
			return _raining # (no menu, no panning, while it rains)
		Gesture.Type.DRAG:
			if not _raining:
				return false
			_finger = gesture.position
			return true
		Gesture.Type.DRAG_END, Gesture.Type.TAP, Gesture.Type.DOUBLE_TAP, Gesture.Type.SWIPE:
			if not _raining:
				return false
			stop()
			return true
		Gesture.Type.MULTI_START:
			stop() # a second finger: the two fingers zoom
	return false


## A cloud forms over the ground under a screen position. False if there is
## no ground there.
func begin_at(screen: Vector2) -> bool:
	if _raining or ctx == null:
		return false
	var under: Variant = ground_under(screen)
	if under == null or not Rect2(ctx.session.world.bounds).has_point(under):
		return false
	if not ctx.session.interactions.rain(under, 0.0, Intervention.PHASE_BEGIN, ID).applied:
		return false
	_raining = true
	_finger = screen
	_at = under
	_seconds = 0.0
	_since_pulse = 0.0
	_units = 0.0
	if ctx.ui != null:
		ctx.ui.dismiss_transient_panels()
	if ctx.view != null:
		ctx.view.tool_fx().show_rain(surface_at(_at), Config.tools.rain_radius)
	AudioManager.set_made_rain(0.4)
	Haptics.light()
	return true


func update(delta: float) -> void:
	if not _raining:
		return
	var config := Config.tools
	var under: Variant = ground_under(_finger)
	if under != null:
		var inside := Rect2(ctx.session.world.bounds).grow(-0.5)
		var target := Vector2(clampf((under as Vector2).x, inside.position.x, inside.end.x),
			clampf((under as Vector2).y, inside.position.y, inside.end.y))
		_at = _at.move_toward(target, CLOUD_SPEED * delta)
	_seconds += delta
	_since_pulse += delta
	while _since_pulse >= config.rain_pulse_seconds:
		_since_pulse -= config.rain_pulse_seconds
		var units := config.rain_units_per_second * config.rain_pulse_seconds
		if ctx.session.interactions.rain(_at, units, Intervention.PHASE_MORE, ID).applied:
			_units += units
		_ripple()
	var strength := clampf(_units / config.rain_moderate_units, 0.3, 1.0)
	if ctx.view != null:
		ctx.view.tool_fx().move_rain(surface_at(_at), strength)
	AudioManager.set_made_rain(lerpf(0.4, 0.9, strength))


## The finger is gone: the cloud goes, and what fell is the player's doing.
func stop() -> void:
	if not _raining:
		return
	_raining = false
	if ctx.view != null:
		ctx.view.tool_fx().hide_rain()
	AudioManager.set_made_rain(0.0)
	ctx.session.interactions.rain(_at, _units, Intervention.PHASE_END, ID)


## Where the rain falls on water, rings spread.
func _ripple() -> void:
	if ctx.view == null:
		return
	var radius := Config.tools.rain_radius
	var spot := _at + Vector2.RIGHT.rotated(_rng.randf() * TAU) * (sqrt(_rng.randf()) * radius)
	var world := ctx.session.world
	if world.get_water(WorldCoords.world2d_to_tile(spot)) > WaterMesher.MIN_DEPTH:
		ctx.view.effects().ring(surface_at(spot), 0.45, 0.8, WorldEffects.WATER_RING)
