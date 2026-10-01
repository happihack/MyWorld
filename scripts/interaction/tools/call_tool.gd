class_name CallTool
extends ToolBase
## PROTOTYPE, debug builds only: a tap calls everyone to that spot, to try
## pathfinding and walking by hand before people decide for themselves where
## to go. They come, stand about for a while, and then go back to their own
## business. Not an intervention: it leaves no trace in the history and nobody
## remembers being called.

const ID := &"call"


func _init() -> void:
	id = ID


func double_tap_touches() -> bool:
	return true


func double_tap_moves_camera() -> bool:
	return false # calling here, then there, is done by tapping quickly


func tap(target: Picker.Result) -> InteractionResponse:
	if target == null or not target.is_hit() or ctx == null:
		return null
	var session := ctx.session
	var ids: Array[int] = []
	for person in session.people.all_people():
		ids.append(person.id)
	if session.behavior.call_to(ids, target.tile) > 0:
		var world := session.world
		var at := Vector3(target.tile.x + 0.5, world.get_height(target.tile) * world.height_step + world.get_water(target.tile),
			target.tile.y + 0.5)
		ctx.view.effects().play_landing(at, world.get_terrain(target.tile), world.get_water(target.tile) > 0.02, 0.15)
		Haptics.light()
	return null
