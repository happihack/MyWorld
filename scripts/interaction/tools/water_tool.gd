class_name WaterTool
extends ToolBase
## PROTOTYPE, debug builds only (bible §23.2): scoop water up and pour it out
## again, to try the water simulation by hand. It becomes the real WATER tool
## (with its own gestures, reveal and feedback) in M9.
##
## A tap on water scoops some into the bucket; a tap on dry ground pours some
## out. Water is never created or destroyed: only what was scooped can be poured.

const ID := &"water"
## Depth moved by one tap, and the most the bucket holds.
const SCOOP := 0.3
const BUCKET := 3.0
## A tile with at least this much water is scooped from, not poured onto.
const SCOOP_FROM := 0.1

## How much water the bucket holds.
var bucket := 0.0


func _init() -> void:
	id = ID


func double_tap_touches() -> bool:
	return true


func double_tap_moves_camera() -> bool:
	return false # scooping and pouring is done by tapping quickly


func tap(target: Picker.Result) -> InteractionResponse:
	if target == null or not target.is_hit() or ctx == null:
		return null
	var water := ctx.session.water
	var world := ctx.session.world
	var tile := target.tile
	var moved := 0.0
	if world.get_water(tile) >= SCOOP_FROM and bucket < BUCKET:
		moved = water.take_water(tile, minf(SCOOP, BUCKET - bucket))
		bucket += moved
	elif bucket > 0.0:
		moved = water.add_water(tile, minf(SCOOP, bucket))
		bucket -= moved
	if moved > 0.0:
		var at := Vector3(tile.x + 0.5, world.get_height(tile) * world.height_step + world.get_water(tile), tile.y + 0.5)
		ctx.view.effects().play_landing(at, world.get_terrain(tile), true, 0.2)
		AudioManager.play_at(&"plip", at, -6.0)
		Haptics.light()
	return null
