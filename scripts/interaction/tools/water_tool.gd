class_name WaterTool
extends ToolBase
## WATER (bible §23.2, M9.5): scoop water up and pour it out again — and
## redirect it: hold a finger on the land for a moment and drag, and a
## shallow channel is carved along the finger's way. Where a channel meets
## the river, the river follows it.
##
## A tap on water scoops some into the bucket; a tap on dry ground pours some
## out. Water is never created or destroyed: only what was scooped can be
## poured. A quick drag still moves the view; only a finger that has rested
## carves. Drawn through water, the finger leaves a trail of ripples.

const ID := &"water"
## Depth moved by one tap, and the most the bucket holds.
const SCOOP := 0.3
const BUCKET := 3.0
## A tile with at least this much water is scooped from, not poured onto.
const SCOOP_FROM := 0.1
const _NOWHERE := Vector2i(-1_000_000, -1_000_000)

## How much water the bucket holds. It is the world's "carried" water, so it
## survives saving and switching tools.
var bucket: float:
	get:
		return ctx.session.water.carried if ctx != null else 0.0

var _stroke := false
var _moved := false
var _last := _NOWHERE
var _carved := 0
var _last_carved := _NOWHERE


func _init() -> void:
	id = ID


func deactivate() -> void:
	end_stroke()


func touch_ended() -> void:
	end_stroke()


func is_busy() -> bool:
	return _stroke and _moved


## How many tiles the stroke going on has carved.
func carved() -> int:
	return _carved


func double_tap_touches() -> bool:
	return true


func double_tap_moves_camera() -> bool:
	return false # scooping and pouring is done by tapping quickly


func handle_gesture(gesture: Gesture) -> bool:
	match gesture.type:
		Gesture.Type.HOLD:
			# The finger has rested: what it now draws is a stroke (a channel on
			# land, ripples on water). Not kept: lifting it is still a tap.
			begin_stroke(gesture.position)
			return false
		Gesture.Type.DRAG_START:
			if not _stroke:
				return false
			if ctx.ui != null:
				ctx.ui.dismiss_transient_panels()
			return true
		Gesture.Type.LONG_PRESS:
			return _stroke and _moved
		Gesture.Type.DRAG:
			if not _stroke:
				return false
			stroke_to(gesture.position)
			return true
		Gesture.Type.DRAG_END, Gesture.Type.SWIPE:
			if not _stroke:
				return false
			end_stroke()
			return true
		Gesture.Type.TAP, Gesture.Type.DOUBLE_TAP:
			end_stroke() # (it never moved: a tap like any other)
		Gesture.Type.MULTI_START:
			end_stroke()
	return false


func tap(target: Picker.Result) -> InteractionResponse:
	if target == null or not target.is_hit() or ctx == null:
		return null
	var interactions := ctx.session.interactions
	var world := ctx.session.world
	var tile := target.tile
	var moved := 0.0
	if world.get_water(tile) >= SCOOP_FROM and bucket < BUCKET:
		moved = interactions.scoop(tile, minf(SCOOP, BUCKET - bucket), ID)
	elif bucket > 0.0:
		moved = interactions.pour(tile, minf(SCOOP, bucket), ID)
	if moved > 0.0:
		var at := Vector3(tile.x + 0.5, world.get_height(tile) * world.height_step + world.get_water(tile), tile.y + 0.5)
		if ctx.view != null:
			ctx.view.effects().play_landing(at, world.get_terrain(tile), true, 0.2)
		AudioManager.play_at(&"plip", at, -6.0)
		Haptics.light()
	return null


# --- a stroke: a channel on land, ripples on water ------------------------------------------------

## The finger has rested at a screen position: a stroke may begin there.
func begin_stroke(screen: Vector2) -> bool:
	if _stroke or ctx == null:
		return false
	var under: Variant = ground_under(screen)
	if under == null:
		return false
	_stroke = true
	_moved = false
	_carved = 0
	_last = _NOWHERE
	_last_carved = _NOWHERE
	return true


## The finger has moved to a screen position: every tile on its way is worked.
func stroke_to(screen: Vector2) -> void:
	if not _stroke:
		return
	var under: Variant = ground_under(screen)
	if under == null:
		return
	var tile := WorldCoords.world2d_to_tile(under)
	if tile == _last:
		return
	_moved = true
	if _last == _NOWHERE:
		_work(tile)
	else:
		# Every tile between the last one and this (the finger may skip some).
		var steps := maxi(absi(tile.x - _last.x), absi(tile.y - _last.y))
		var from := _last
		for n in range(1, steps + 1):
			var between := Vector2i(roundi(lerpf(from.x, tile.x, n / float(steps))), roundi(lerpf(from.y, tile.y, n / float(steps))))
			if between != _last:
				_work(between)
				_last = between
	_last = tile


## The stroke is over: what was carved is the player's doing, and the river
## finds what now lies open to it.
func end_stroke() -> void:
	if not _stroke:
		return
	_stroke = false
	_moved = false
	if _carved > 0:
		ctx.session.interactions.carve(_last_carved, Intervention.PHASE_END, ID, _carved)
	_carved = 0


func _work(tile: Vector2i) -> void:
	var world := ctx.session.world
	if not world.is_in_bounds(tile):
		return
	if world.get_water(tile) > WaterMesher.MIN_DEPTH:
		# Through water: a trail of ripples.
		if ctx.view != null:
			ctx.view.effects().ring(surface_at(Vector2(tile) + Vector2(0.5, 0.5)), 0.55, 0.9, WorldEffects.WATER_RING)
		return
	if _carved >= Config.tools.carve_most_tiles:
		return
	var terrain := world.get_terrain(tile)
	var phase := Intervention.PHASE_BEGIN if _carved == 0 else Intervention.PHASE_MORE
	if not ctx.session.interactions.carve(tile, phase, ID).applied:
		return
	_carved += 1
	_last_carved = tile
	var at := surface_at(Vector2(tile) + Vector2(0.5, 0.5))
	if ctx.view != null:
		ctx.view.effects().burst(WorldEffects.Burst.DUST, at + Vector3(0.0, 0.1, 0.0), WorldEffects.dust_color(terrain))
	AudioManager.play_at(&"thud", at, -14.0, 1.3)
	Haptics.light()
