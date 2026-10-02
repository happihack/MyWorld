class_name ToolBase
extends RefCounted
## What the player's finger does in the world (bible §23.2). One tool is
## active at a time; it sees every gesture first and may keep it for itself
## (a carried rock must not also pan the camera).


## What a tool can reach: the world, its picture, the UI and the input scale.
class Context:
	extends RefCounted
	var session: WorldSession
	var view: WorldView
	var ui: UIRoot
	## Touch radius in viewport units (finger-sized forgiveness when picking).
	var touch_radius := 60.0


var id: StringName = &""
var ctx: Context


func setup(context: Context) -> void:
	ctx = context


## The tool became the active one.
func activate() -> void:
	pass


## Another tool takes over (or the world closes): finish whatever is going on.
func deactivate() -> void:
	pass


## Sees every world gesture before the camera does. Return true to keep it:
## the camera and the default touch handling then never see it.
func handle_gesture(_gesture: Gesture) -> bool:
	return false


## The finger left the world. Not every release produces a gesture (lifting
## after a long press does not), so a tool that holds something ends it here.
func touch_ended() -> void:
	pass


## A tap on `target` that the tool did not keep. Returns what the world did
## in answer, or null if the tool leaves the world alone.
func tap(_target: Picker.Result) -> InteractionResponse:
	return null


## The second of two quick taps: does it also act like a tap? (Tapping a tree
## twice shakes it twice.)
func double_tap_touches() -> bool:
	return false


## ...and does it move the camera (look at the thing, zoom toward the ground)?
## Not for tools that are used by tapping quickly.
func double_tap_moves_camera() -> bool:
	return true


## Called every frame while active.
func update(_delta: float) -> void:
	pass


## True while the tool is in the middle of something (carrying an object).
func is_busy() -> bool:
	return false


# --- where the finger is in the world (for tools that work on the ground) ------------------------

## The point of the ground (world X/Z) under a screen position: where the
## finger's ray meets the terrain — or, off the terrain, the plane at height
## `plane_y`. Null if there is none.
func ground_under(screen: Vector2, plane_y: float = 0.0) -> Variant:
	if ctx == null or ctx.view == null:
		return null
	var rig := ctx.view.camera_rig()
	var ray := rig.screen_ray(screen)
	var hit := Picker.raycast_terrain(ctx.session.world, ray[0], ray[1])
	if hit != null:
		return Vector2(hit.position.x, hit.position.z)
	var plane: Variant = rig.screen_to_ground(screen, plane_y)
	return Vector2((plane as Vector3).x, (plane as Vector3).z) if plane != null else null


## The point on the surface (the ground, or the water lying on it) at a
## place of the world.
func surface_at(xz: Vector2) -> Vector3:
	var world := ctx.session.world
	var tile := WorldCoords.world2d_to_tile(xz)
	return Vector3(xz.x, world.get_height(tile) * world.height_step + maxf(world.get_water(tile), 0.0), xz.y)
