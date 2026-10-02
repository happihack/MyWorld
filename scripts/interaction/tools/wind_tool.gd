class_name WindTool
extends ToolBase
## WIND (bible §23.2, M9.5): swipe across the world and a gust blows that
## way from where the finger set out — the faster the swipe, the harder.
## Light things lying about are blown along, the trees bend, animals take
## fright. With this tool a one-finger drag is a gust, not a pan (two
## fingers still move the view).

const ID := &"wind"

var _swiping := false
var _from := Vector2.ZERO
## The last gust made (null if the last swipe made none); tests look at it.
var last_gust: Intervention


func _init() -> void:
	id = ID


func deactivate() -> void:
	_swiping = false


func touch_ended() -> void:
	_swiping = false


func handle_gesture(gesture: Gesture) -> bool:
	match gesture.type:
		Gesture.Type.DRAG_START:
			if gesture.after_multi:
				return false # (what is left of a pinch is not a swipe)
			_swiping = true
			_from = gesture.start_position
			if ctx.ui != null:
				ctx.ui.dismiss_transient_panels()
			return true
		Gesture.Type.DRAG:
			return _swiping
		Gesture.Type.DRAG_END:
			if not _swiping:
				return false
			_swiping = false
			if not gesture.cancelled:
				last_gust = blow(_from, gesture.position, gesture.velocity)
			return true
		Gesture.Type.SWIPE:
			return true # (its drag has ended, and made the gust)
		Gesture.Type.MULTI_START:
			_swiping = false
	return false


## A gust from the ground under one screen position towards the ground
## under another; `velocity` is how fast the finger was going (screen units
## a second). Returns what came of it, or null if it was no gust.
func blow(from_screen: Vector2, to_screen: Vector2, velocity: Vector2) -> Intervention:
	if ctx == null:
		return null
	var config := Config.tools
	var from: Variant = ground_under(from_screen)
	var to: Variant = ground_under(to_screen)
	if from == null or to == null or (from as Vector2).distance_to(to) < config.wind_min_swipe:
		return null
	var units_per_dp := ctx.touch_radius / Config.interaction.touch_radius_dp
	var slowest := Config.interaction.swipe_min_velocity_dp_s * units_per_dp
	var strength := clampf(velocity.length() / maxf(slowest * config.wind_full_speed, 1.0), config.wind_least, 1.0)
	var gust := ctx.session.interactions.gust(from, to, strength, ID)
	if not gust.applied:
		return gust
	var direction: Vector2 = gust.params["direction"]
	var middle := (from as Vector2) + direction * config.wind_reach * 0.5
	if ctx.view != null:
		ctx.view.tool_fx().gust(surface_at(from), surface_at((from as Vector2) + direction * config.wind_reach))
		ctx.view.weather_fx().gust(direction * config.wind_gust_sway * strength, config.wind_gust_seconds)
	AudioManager.play_at(&"gust", surface_at(middle), lerpf(-9.0, -2.0, strength), lerpf(1.15, 0.9, strength))
	Haptics.pulse(Haptics.Strength.MEDIUM if strength > 0.7 else Haptics.Strength.LIGHT)
	return gust
