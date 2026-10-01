class_name CameraRig
extends Node3D
## The player's view into the box (bible §26.4, spec §6–7).
##
## The camera orbits a ground point (`pivot`) at a `distance`; its pitch eases
## from a high overview to a lower, closer angle as you zoom in. Panning,
## zooming and rotating are *anchored*: the ground point under the finger(s)
## stays under the finger(s).
##
## Feel: a flick keeps the world gliding (fling) until friction or a touch
## stops it; dragging past the edge meets growing resistance and springs back
## (rubber band); a double tap zooms a step toward the tapped point.
##
## The camera can never get lost: the furthest zoom is "the whole box fits",
## the pivot cannot stay outside the world, and an invalid state reframes the box.
##
## Direct manipulation applies instantly; programmatic moves (frame_box,
## focus_on, double tap) animate. All projection math is done here rather than
## with Camera3D.project_*, so it is testable without a renderer.

var config: CameraConfig
## Optional: Callable(world_xz: Vector2) -> float, the ground height there.
## Lets the camera look at the surface (not below it) when zoomed in on hills.
var ground_height: Callable
## Rotation of the view around the vertical axis (twist gesture).
var yaw := 0.0
## Whether the two-finger twist rotates the view (player setting).
var twist_enabled := false
## Whether a double tap zooms by itself. Off when someone else decides what a
## double tap means (on an entity it focuses that entity instead).
var handles_double_tap := true
## Flings are skipped when the player asked for reduced motion.
var reduced_motion := false

var _camera: Camera3D
var _view_size := Vector2(1080, 1920)
var _bounds := Rect2(-32, -32, 64, 64) # world area the pivot may roam
var _frame_rect := Rect2(-34, -34, 68, 68) # whole box footprint (frame included)
var _box_bottom := -2.0
var _box_top := 9.0
var _fit_distance := 100.0

var _pivot := Vector3.ZERO
var _distance := 100.0
var _goal_pivot := Vector3.ZERO
var _goal_distance := 100.0

## True while fingers are on the world (no spring-back, no animation).
var _touching := false
## Where the pivot would be without the rubber band (accumulates drag motion).
var _raw_pivot := Vector3.ZERO
var _fling_velocity := Vector2.ZERO # viewport units per second
var _fling_position := Vector2.ZERO
var _yaw_changed := false


func _init(camera_config: CameraConfig = null) -> void:
	config = camera_config if camera_config != null else CameraConfig.new()
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.near = 0.3
	add_child(_camera)


# --- setup -----------------------------------------------------------------------

## `world_bounds`: the tile area (XZ). `frame_rect`: the whole box footprint.
## `box_bottom` / `box_top`: vertical extent of the box (for framing).
func setup(world_bounds: Rect2, frame_rect: Rect2, box_bottom: float, box_top: float) -> void:
	_bounds = world_bounds
	_frame_rect = frame_rect
	_box_bottom = box_bottom
	_box_top = box_top
	_camera.fov = config.fov_degrees
	_recompute_fit()
	frame_box(false)


## Call when the viewport changes size (rotation, window resize).
func set_view_size(size: Vector2) -> void:
	if size.x <= 0.0 or size.y <= 0.0 or size == _view_size:
		return
	var was_framed := is_framed()
	_view_size = size
	_recompute_fit()
	stop_motion()
	if was_framed:
		frame_box(false) # keep showing the whole box after a rotation
	else:
		_goal_distance = minf(_goal_distance, _fit_distance)
		_distance = minf(_distance, _fit_distance)
		_goal_pivot = _clamp_pivot(_goal_pivot, _goal_distance)
		_pivot = _clamp_pivot(_pivot, _distance)
		_apply()


# --- moves -------------------------------------------------------------------------

## Shows the whole box.
func frame_box(animate: bool = true) -> void:
	_fling_velocity = Vector2.ZERO
	_goal_distance = _fit_distance
	_goal_pivot = _clamp_pivot(_box_center(), _fit_distance)
	if not animate:
		_snap()


## Looks at a world point, optionally from a new distance.
func focus_on(point: Vector3, distance: float = -1.0, animate: bool = true) -> void:
	_fling_velocity = Vector2.ZERO
	if distance > 0.0:
		_goal_distance = clampf(distance, config.min_distance, _fit_distance)
	_goal_pivot = _clamp_pivot(Vector3(point.x, 0.0, point.z), _goal_distance)
	if not animate:
		_snap()


## Drags the world: the ground point that was under `from` ends up under `to`
## (screen positions in viewport units). Past the edge the view gives a little
## with growing resistance; call settle() (or release the finger) to spring back.
func pan_screen(from: Vector2, to: Vector2) -> void:
	var a: Variant = screen_to_ground(from)
	var b: Variant = screen_to_ground(to)
	if a == null or b == null:
		return
	var moved: Vector3 = (a as Vector3) - (b as Vector3)
	_raw_pivot += Vector3(moved.x, 0.0, moved.z)
	_raw_pivot.y = _pivot.y
	_pivot = _rubber(_raw_pivot, _distance)
	_goal_pivot = _pivot
	_goal_distance = _distance
	_apply()


## Zooms by `factor` (> 1 = closer) keeping the ground point under `focal` fixed.
func zoom_at(factor: float, focal: Vector2) -> void:
	if factor <= 0.0:
		return
	var anchor: Variant = screen_to_ground(focal)
	_distance = clampf(_distance / factor, config.min_distance, _fit_distance)
	if anchor != null:
		_pivot = _anchored_pivot(focal, anchor, _pivot, _distance)
	_pivot = _clamp_pivot(_pivot, _distance)
	_raw_pivot = _pivot
	_goal_pivot = _pivot
	_goal_distance = _distance
	_apply()


## Animated zoom to `target_distance`, ending with the ground point under
## `focal` still under `focal` (as far as the world's edge allows).
func zoom_to(target_distance: float, focal: Vector2) -> void:
	_fling_velocity = Vector2.ZERO
	var anchor: Variant = screen_to_ground(focal)
	_goal_distance = clampf(target_distance, config.min_distance, _fit_distance)
	var target_pivot := _pivot
	if anchor != null:
		target_pivot = _anchored_pivot(focal, anchor, _pivot, _goal_distance)
	_goal_pivot = _clamp_pivot(target_pivot, _goal_distance)


## Rotates the view by `angle` radians (positive = the world turns clockwise on
## screen) around the ground point under `focal`.
func rotate_at(angle: float, focal: Vector2) -> void:
	var anchor: Variant = screen_to_ground(focal)
	yaw = wrapf(yaw + angle, -PI, PI)
	_yaw_changed = true
	if anchor != null:
		_pivot = _anchored_pivot(focal, anchor, _pivot, _distance)
	_pivot = _clamp_pivot(_pivot, _distance)
	_raw_pivot = _pivot
	_goal_pivot = _pivot
	_goal_distance = _distance
	_apply()


## One double-tap step: closer toward `focal`; from the closest zoom, back out
## to the whole box.
func double_tap_zoom(focal: Vector2) -> void:
	if zoom_fraction() > 0.85:
		frame_box()
	else:
		zoom_to(_goal_distance / config.double_tap_zoom, focal)


## Stops any fling. Call the moment a finger touches the world.
func stop_motion() -> void:
	_fling_velocity = Vector2.ZERO


## Ends direct manipulation: springs back inside the world if needed.
func settle() -> void:
	_touching = false
	if _yaw_changed:
		# The box fits differently from a new angle.
		_yaw_changed = false
		_recompute_fit()
		_distance = minf(_distance, _fit_distance)
	_goal_distance = _distance
	_goal_pivot = _clamp_pivot(_pivot, _distance)
	_raw_pivot = _goal_pivot


## Feeds a recognized gesture to the camera. Returns true if it was used.
func handle_gesture(gesture: Gesture) -> bool:
	match gesture.type:
		Gesture.Type.DRAG_START, Gesture.Type.MULTI_START:
			_begin_touch()
			return true
		Gesture.Type.DRAG, Gesture.Type.TWO_FINGER_DRAG:
			if not _touching:
				_begin_touch() # e.g. a desktop wheel/right-drag without a start
			pan_screen(gesture.position - gesture.delta, gesture.position)
			return true
		Gesture.Type.PINCH:
			zoom_at(gesture.scale, gesture.position)
			return true
		Gesture.Type.TWIST:
			if twist_enabled:
				rotate_at(gesture.angle, gesture.position)
			return twist_enabled
		Gesture.Type.DRAG_END:
			settle()
			if not gesture.cancelled and not gesture.after_multi and not reduced_motion \
					and gesture.velocity.length() >= config.fling_min_speed:
				_fling_velocity = gesture.velocity
				_fling_position = gesture.position
				_raw_pivot = _pivot
			return true
		Gesture.Type.MULTI_END:
			settle()
			return true
		Gesture.Type.DOUBLE_TAP:
			if handles_double_tap:
				double_tap_zoom(gesture.position)
			return handles_double_tap
	return false


## Advances flings and animated moves. Called every frame; tests call it directly.
func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	_guard() # before anything uses the state, so a bad value never reaches the camera
	if _fling_velocity != Vector2.ZERO:
		_advance_fling(delta)
	elif not _touching:
		_advance_animation(delta)
	_follow_ground(delta)
	_guard()


func _process(delta: float) -> void:
	advance(delta)


# --- queries -----------------------------------------------------------------------

func pivot() -> Vector3:
	return _pivot


func distance() -> float:
	return _distance


func fit_distance() -> float:
	return _fit_distance


func pitch_degrees() -> float:
	return rad_to_deg(_pitch_for(_distance))


## True when the whole box is in view (furthest zoom).
func is_framed() -> bool:
	return is_equal_approx(_goal_distance, _fit_distance)


func is_flinging() -> bool:
	return _fling_velocity != Vector2.ZERO


## True while the view is moving on its own (fling or animation).
func is_moving() -> bool:
	return is_flinging() or not _pivot.is_equal_approx(_goal_pivot) or not is_equal_approx(_distance, _goal_distance)


## 0 = whole box in view, 1 = closest zoom.
func zoom_fraction() -> float:
	if _fit_distance <= config.min_distance:
		return 0.0
	return clampf(inverse_lerp(_fit_distance, config.min_distance, _goal_distance), 0.0, 1.0)


func camera() -> Camera3D:
	return _camera


func camera_transform() -> Transform3D:
	return _transform_for(_pivot, _distance)


## Ground point under a screen position, on the horizontal plane at `plane_y`
## (default: the height the camera is looking at). Null if the ray misses.
func screen_to_ground(screen: Vector2, plane_y: float = NAN) -> Variant:
	return _ground_under(screen, _pivot, _distance, _pivot.y if is_nan(plane_y) else plane_y)


## Ray from the camera through a screen position: [origin, direction].
func screen_ray(screen: Vector2) -> Array[Vector3]:
	return _ray(screen, camera_transform())


## Screen position (viewport units) of a world point. Returns Vector2.INF for
## points behind the camera.
func world_to_screen(point: Vector3) -> Vector2:
	return _project(point, camera_transform())


## How many world units one viewport unit covers at `point` (perspective makes
## nearer things bigger). Converts touch radii and body sizes between spaces.
func world_units_per_screen_unit(point: Vector3) -> float:
	var depth := -(camera_transform().affine_inverse() * point).z
	return maxf(depth, 0.01) * 2.0 * tan(deg_to_rad(config.fov_degrees) * 0.5) / _view_size.y


## The pivot position with no overscroll for the current zoom.
func clamped_pivot() -> Vector3:
	return _clamp_pivot(_pivot, _distance)


# --- internals: motion --------------------------------------------------------------

func _begin_touch() -> void:
	_touching = true
	_fling_velocity = Vector2.ZERO
	_raw_pivot = _pivot
	_goal_pivot = _pivot
	_goal_distance = _distance


func _advance_fling(delta: float) -> void:
	var step := _fling_velocity * delta
	pan_screen(_fling_position, _fling_position + step)
	# Friction; much stronger once the view is being pushed past the edge.
	var overscrolled := not _pivot.is_equal_approx(_clamp_pivot(_pivot, _distance))
	var friction := config.fling_friction * (6.0 if overscrolled else 1.0)
	_fling_velocity *= exp(-friction * delta)
	if _fling_velocity.length() < config.fling_min_speed * 0.15:
		_fling_velocity = Vector2.ZERO
		settle()


func _advance_animation(delta: float) -> void:
	# Never rest outside the world.
	_goal_pivot = _clamp_pivot(_goal_pivot, _goal_distance)
	if _pivot.is_equal_approx(_goal_pivot) and is_equal_approx(_distance, _goal_distance):
		return
	var w := 1.0 - exp(-config.smoothing * delta)
	_distance = lerpf(_distance, _goal_distance, w)
	_pivot = _pivot.lerp(Vector3(_goal_pivot.x, _pivot.y, _goal_pivot.z), w)
	if absf(_distance - _goal_distance) < 0.01 \
			and Vector2(_pivot.x - _goal_pivot.x, _pivot.z - _goal_pivot.z).length() < 0.01:
		_distance = _goal_distance
		_pivot = Vector3(_goal_pivot.x, _pivot.y, _goal_pivot.z)
	_goal_pivot.y = _pivot.y
	_raw_pivot = _pivot
	_apply()


func _snap() -> void:
	_distance = _goal_distance
	_pivot = _goal_pivot
	_pivot.y = _look_height(_pivot, _distance)
	_goal_pivot = _pivot
	_raw_pivot = _pivot
	_apply()


func _apply() -> void:
	_camera.transform = camera_transform()
	_camera.far = maxf(_fit_distance * 3.0, 200.0)


func _follow_ground(delta: float) -> void:
	var target := _look_height(_pivot, _distance)
	_pivot.y = lerpf(_pivot.y, target, 1.0 - exp(-config.smoothing * 0.5 * delta))
	_goal_pivot.y = _pivot.y
	_raw_pivot.y = _pivot.y
	_apply()


## Last resort: an invalid or out-of-range state reframes the box.
func _guard() -> void:
	var limit := _overscroll_limit(_distance) + config.edge_margin_tiles + 1.0
	var ok := is_finite(_pivot.x) and is_finite(_pivot.y) and is_finite(_pivot.z) and is_finite(_distance) \
		and _distance >= config.min_distance - 0.01 and _distance <= _fit_distance + 0.01 \
		and _pivot.x >= _bounds.position.x - limit and _pivot.x <= _bounds.end.x + limit \
		and _pivot.z >= _bounds.position.y - limit and _pivot.z <= _bounds.end.y + limit
	if not ok:
		_touching = false
		_fling_velocity = Vector2.ZERO
		_pivot = _box_center()
		_distance = _fit_distance
		frame_box(false)


# --- internals: geometry -------------------------------------------------------------

## Pivot that puts ground point `anchor` back under screen position `focal`
## for a view from `at_distance` (and the current yaw).
func _anchored_pivot(focal: Vector2, anchor: Variant, from_pivot: Vector3, at_distance: float) -> Vector3:
	var target: Vector3 = anchor
	var probe := from_pivot
	probe.y = _look_height(probe, at_distance)
	var now: Variant = _ground_under(focal, probe, at_distance, target.y)
	if now == null:
		return probe
	var shift: Vector3 = target - (now as Vector3)
	return probe + Vector3(shift.x, 0.0, shift.z)


## Height the camera looks at: the base height when framed, easing to the
## actual ground height under the pivot as the view zooms in.
func _look_height(pivot_point: Vector3, at_distance: float) -> float:
	var ground := config.base_look_height
	if ground_height.is_valid():
		ground = float(ground_height.call(Vector2(pivot_point.x, pivot_point.z)))
	var t := _zoom_t(at_distance) # 1 framed .. 0 closest
	return lerpf(ground, config.base_look_height, t)


## 1 when framed, 0 at the closest zoom.
func _zoom_t(at_distance: float) -> float:
	if _fit_distance <= config.min_distance:
		return 1.0
	return clampf(inverse_lerp(config.min_distance, _fit_distance, at_distance), 0.0, 1.0)


func _pitch_for(at_distance: float) -> float:
	var t := smoothstep(0.0, 1.0, _zoom_t(at_distance))
	return deg_to_rad(lerpf(config.pitch_near_degrees, config.pitch_far_degrees, t))


func _transform_for(pivot_point: Vector3, at_distance: float, pitch_override: float = NAN) -> Transform3D:
	var pitch := _pitch_for(at_distance) if is_nan(pitch_override) else pitch_override
	var offset := Vector3(0.0, sin(pitch), cos(pitch)) * at_distance
	offset = offset.rotated(Vector3.UP, yaw)
	return Transform3D(Basis.IDENTITY, pivot_point + offset).looking_at(pivot_point, Vector3.UP)


func _ray(screen: Vector2, xform: Transform3D) -> Array[Vector3]:
	var tan_v := tan(deg_to_rad(config.fov_degrees) * 0.5)
	var aspect := _view_size.x / _view_size.y
	var ndc := Vector2(screen.x / _view_size.x * 2.0 - 1.0, 1.0 - screen.y / _view_size.y * 2.0)
	var local := Vector3(ndc.x * tan_v * aspect, ndc.y * tan_v, -1.0).normalized()
	return [xform.origin, (xform.basis * local).normalized()]


func _ground_under(screen: Vector2, pivot_point: Vector3, at_distance: float, plane_y: float) -> Variant:
	var ray := _ray(screen, _transform_for(pivot_point, at_distance))
	var origin := ray[0]
	var dir := ray[1]
	if dir.y >= -0.0001:
		return null # looking at or above the horizon
	var t := (plane_y - origin.y) / dir.y
	return origin + dir * t


func _project(point: Vector3, xform: Transform3D) -> Vector2:
	var p := xform.affine_inverse() * point
	if p.z >= -0.0001:
		return Vector2.INF
	var tan_v := tan(deg_to_rad(config.fov_degrees) * 0.5)
	var aspect := _view_size.x / _view_size.y
	var ndc := Vector2(p.x / (-p.z * tan_v * aspect), p.y / (-p.z * tan_v))
	return Vector2((ndc.x + 1.0) * 0.5 * _view_size.x, (1.0 - ndc.y) * 0.5 * _view_size.y)


func _box_center() -> Vector3:
	var c := _frame_rect.get_center()
	return Vector3(c.x, config.base_look_height, c.y)


## Furthest zoom: the smallest distance from which the whole box volume (frame
## footprint x height) is on screen with the configured margin, for the
## current rotation.
func _recompute_fit() -> void:
	var center := _box_center()
	var pitch := deg_to_rad(config.pitch_far_degrees)
	var corners: Array[Vector3] = []
	for y in [_box_bottom, _box_top]:
		for corner in [_frame_rect.position, Vector2(_frame_rect.end.x, _frame_rect.position.y),
				_frame_rect.end, Vector2(_frame_rect.position.x, _frame_rect.end.y)]:
			corners.append(Vector3(corner.x, y, corner.y))
	var lo := config.min_distance
	var hi := maxf(_frame_rect.size.x, _frame_rect.size.y) * 12.0 + 50.0
	for i in 28:
		var mid := (lo + hi) * 0.5
		if _all_visible(corners, _transform_for(center, mid, pitch)):
			hi = mid
		else:
			lo = mid
	_fit_distance = maxf(hi, config.min_distance)


func _all_visible(points: Array[Vector3], xform: Transform3D) -> bool:
	var inset := (_view_size - _view_size / config.fit_margin) * 0.5
	for p in points:
		var s := _project(p, xform)
		if s == Vector2.INF or s.x < inset.x or s.x > _view_size.x - inset.x \
				or s.y < inset.y or s.y > _view_size.y - inset.y:
			return false
	return true


## Half-size of the ground area in view, along the world X and Z axes.
func _seen_half_extents(at_distance: float) -> Vector2:
	var half_v := deg_to_rad(config.fov_degrees) * 0.5
	var aspect := _view_size.x / _view_size.y
	var across := at_distance * tan(half_v) * aspect
	var along := at_distance * tan(half_v) / maxf(sin(_pitch_for(at_distance)), 0.2)
	# A rotated view covers the world axes with a mix of both.
	var c := absf(cos(yaw))
	var s := absf(sin(yaw))
	return Vector2(c * across + s * along, s * across + c * along)


## Keeps the view over the world: the closer the zoom, the further the pivot
## may roam; at the furthest zoom it is pinned to the centre of the box.
func _clamp_pivot(point: Vector3, at_distance: float) -> Vector3:
	var seen := _seen_half_extents(at_distance)
	var center := _bounds.get_center()
	var range_x := maxf(_bounds.size.x * 0.5 + config.edge_margin_tiles - seen.x, 0.0)
	var range_z := maxf(_bounds.size.y * 0.5 + config.edge_margin_tiles - seen.y, 0.0)
	if is_equal_approx(at_distance, _fit_distance):
		range_x = 0.0
		range_z = 0.0
	return Vector3(
		clampf(point.x, center.x - range_x, center.x + range_x),
		point.y,
		clampf(point.z, center.y - range_z, center.y + range_z))


## How far (tiles) the view may be dragged past its limit at this zoom.
func _overscroll_limit(at_distance: float) -> float:
	var seen := _seen_half_extents(at_distance)
	return maxf(minf(seen.x, seen.y) * config.rubber_band, 0.0)


## The rubber band: inside the limits the pivot is where the drag put it;
## beyond them it follows with growing resistance and never exceeds the
## overscroll limit.
func _rubber(raw: Vector3, at_distance: float) -> Vector3:
	var inside := _clamp_pivot(raw, at_distance)
	var limit := _overscroll_limit(at_distance)
	if limit <= 0.0:
		return inside
	return Vector3(
		inside.x + _soften(raw.x - inside.x, limit),
		raw.y,
		inside.z + _soften(raw.z - inside.z, limit))


## Maps any overshoot onto (-limit, limit): 1:1 at first, flattening out.
static func _soften(overshoot: float, limit: float) -> float:
	if overshoot == 0.0:
		return 0.0
	return signf(overshoot) * limit * (1.0 - exp(-absf(overshoot) / limit))
