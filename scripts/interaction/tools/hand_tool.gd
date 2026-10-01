class_name HandTool
extends ToolBase
## The default tool (bible §23.2): touch things, and pick loose things up.
##
## Hold a finger on a loose object for a moment and it lifts off the ground;
## drag and it follows the finger at hover height — a boulder more slowly than
## a pebble; near the edge of the screen the view pans along; let go and it
## drops. Keep holding still instead and the long-press menu opens while the
## object stays in hand: dragging from there closes the menu and carries it,
## lifting the finger puts it back down.

const ID := &"hand"
## A carried object counts as moved if it is let go at least this far (tiles)
## from where it was picked up.
const MOVED_MIN_DISTANCE := 0.2
## How fast a held object rises to (and follows) its hover height, tiles/s.
const LIFT_SPEED := 4.5
## A held object keeps at least this far above the surface.
const MIN_CLEARANCE := 0.04

var _held_id := 0
var _finger := Vector2.ZERO
## From the ground point under the finger to the object, so it does not jump
## to the finger when grabbed.
var _grab_offset := Vector2.ZERO
var _grab_from := Vector2.ZERO
var _dragged := false
## World height of the held object's base (smoothed over terrain steps).
var _base_y := 0.0


func _init() -> void:
	id = ID


func deactivate() -> void:
	release()


func is_busy() -> bool:
	return _held_id != 0


func held_id() -> int:
	return _held_id


func handle_gesture(gesture: Gesture) -> bool:
	match gesture.type:
		Gesture.Type.HOLD:
			return grab_at(gesture.position)
		Gesture.Type.DRAG_START:
			if not is_busy():
				return false
			if ctx.ui != null:
				ctx.ui.dismiss_transient_panels() # carrying on after the menu opened
			return true
		Gesture.Type.DRAG:
			if not is_busy():
				return false
			_finger = gesture.position
			_dragged = true
			return true
		Gesture.Type.DRAG_END, Gesture.Type.TAP, Gesture.Type.DOUBLE_TAP:
			# The finger left the screen: whatever it held is let go.
			if not is_busy():
				return false
			release()
			return true
		Gesture.Type.MULTI_START:
			# A second finger came down: put it back, the two fingers zoom.
			release()
	# LONG_PRESS is not kept: the menu opens, and the object stays in hand.
	return false


func touch_ended() -> void:
	release()


func tap(target: Picker.Result) -> InteractionResponse:
	return ctx.session.interactions.tap(target)


## Picks up the loose object under a screen position. False if there is none.
func grab_at(screen: Vector2) -> bool:
	if is_busy() or ctx == null:
		return false
	var target := ctx.view.pick(screen, ctx.touch_radius, SpatialIndex.KIND_LOOSE_OBJECT)
	if target.kind != Picker.Kind.ENTITY:
		return false
	var object := ctx.session.loose.get_object(target.entity_id)
	if object == null or not ctx.session.loose_system.hold(object.id):
		return false
	_held_id = object.id
	_finger = screen
	_dragged = false
	_grab_from = object.position
	var under: Variant = _ground_under(screen)
	_grab_offset = object.position - (under as Vector2) if under != null else Vector2.ZERO
	_base_y = object.world_position(ctx.session.world).y
	# Heavy things are felt more and sound lower.
	var give := object.give()
	Haptics.pulse(Haptics.Strength.MEDIUM if give < TouchFeedback.HEAVY_BELOW else Haptics.Strength.LIGHT)
	AudioManager.play_at(&"click", object.world_position(ctx.session.world), -11.0, clampf(0.7 + 0.5 * give, 0.7, 1.5))
	return true


## Lets go of the held object: it drops where it is.
func release() -> void:
	if not is_busy():
		return
	var id_was := _held_id
	_held_id = 0
	var loose := ctx.session.loose
	var object := loose.get_object(id_was)
	if object == null:
		return
	if object.position.distance_to(_grab_from) >= MOVED_MIN_DISTANCE:
		object.moved_count += 1
		object.placed_by_player = true
		loose.touch(id_was)
	ctx.session.loose_system.drop(id_was)


func update(delta: float) -> void:
	if not is_busy():
		return
	var world := ctx.session.world
	var object := ctx.session.loose.get_object(_held_id)
	if object == null or object.state != LooseObject.State.HELD:
		_held_id = 0 # it was removed or taken over by something else
		return
	if _dragged:
		_pan_at_screen_edge(delta)
	var position := object.position
	var under: Variant = _ground_under(_finger)
	if under != null and _dragged:
		var target := _inside_world((under as Vector2) + _grab_offset, object.radius())
		position = position.move_toward(target, carry_speed(object) * delta)
	# Hover over whatever is below: the ground, or the water's surface.
	var tile := WorldCoords.world2d_to_tile(position)
	var ground := world.get_height(tile) * world.height_step
	var surface := ground + maxf(world.get_water(tile), 0.0)
	_base_y = move_toward(_base_y, surface + hover_height(object), LIFT_SPEED * delta)
	_base_y = maxf(_base_y, surface + MIN_CLEARANCE)
	ctx.session.loose.move(_held_id, position, _base_y - ground)


## How high above the surface an object is carried: heavy things hang low.
static func hover_height(object: LooseObject) -> float:
	var full := Config.interaction.carry_hover_height
	return clampf(full * (0.45 + 0.55 * object.give()), full * 0.5, full)


## How fast an object follows the finger (tiles/s): heavy things lag behind.
static func carry_speed(object: LooseObject) -> float:
	return clampf(Config.interaction.carry_speed * object.give(),
		Config.interaction.carry_speed * 0.25, Config.interaction.carry_speed * 2.0)


## Ground-plane point under a screen position: where the finger's ray meets
## the terrain, or (off the terrain) the plane the object hovers over.
func _ground_under(screen: Vector2) -> Variant:
	var rig := ctx.view.camera_rig()
	var ray := rig.screen_ray(screen)
	var hit := Picker.raycast_terrain(ctx.session.world, ray[0], ray[1])
	if hit != null:
		return Vector2(hit.position.x, hit.position.z)
	var plane: Variant = rig.screen_to_ground(screen, _base_y)
	return Vector2((plane as Vector3).x, (plane as Vector3).z) if plane != null else null


## Keeps a position inside the box (objects cannot be carried through the walls).
func _inside_world(position: Vector2, margin: float) -> Vector2:
	var b := Rect2(ctx.session.world.bounds).grow(-maxf(margin, 0.05))
	return Vector2(clampf(position.x, b.position.x, b.end.x), clampf(position.y, b.position.y, b.end.y))


## Carrying something to the edge of the screen pans the view that way.
func _pan_at_screen_edge(delta: float) -> void:
	var rig := ctx.view.camera_rig()
	var push := edge_push(_finger, rig.view_size(), Config.interaction.edge_pan_margin)
	if push == Vector2.ZERO:
		return
	var center := rig.view_size() * 0.5
	var a: Variant = rig.screen_to_ground(center)
	var b: Variant = rig.screen_to_ground(center + push.normalized() * 100.0)
	if a == null or b == null:
		return
	var along := Vector2((b as Vector3).x - (a as Vector3).x, (b as Vector3).z - (a as Vector3).z).normalized()
	rig.pan_world(along * push.length() * rig.distance() * Config.interaction.edge_pan_speed * delta)


## How hard a finger at `screen` pushes the view: zero in the middle of the
## screen, up to length 1 at an edge, pointing toward that edge.
static func edge_push(screen: Vector2, view: Vector2, margin_fraction: float) -> Vector2:
	var margin := minf(view.x, view.y) * margin_fraction
	if margin <= 0.0:
		return Vector2.ZERO
	var push := Vector2.ZERO
	if screen.x < margin:
		push.x = -(margin - screen.x) / margin
	elif screen.x > view.x - margin:
		push.x = (screen.x - (view.x - margin)) / margin
	if screen.y < margin:
		push.y = -(margin - screen.y) / margin
	elif screen.y > view.y - margin:
		push.y = (screen.y - (view.y - margin)) / margin
	return push.limit_length(1.0)
