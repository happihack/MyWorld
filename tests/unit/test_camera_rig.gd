extends TestCase

const PORTRAIT := Vector2(1080, 1920)
const LANDSCAPE := Vector2(1920, 1080)
const BOUNDS := Rect2(-32, -32, 64, 64)
const FRAME := Rect2(-33.75, -33.75, 67.5, 67.5)
const BOX_BOTTOM := -1.8
const BOX_TOP := 9.0

var rig: CameraRig


func before_each() -> void:
	rig = CameraRig.new(CameraConfig.new())
	add_child(rig)
	rig.set_process(false) # tests advance time themselves
	rig.set_view_size(PORTRAIT)
	rig.setup(BOUNDS, FRAME, BOX_BOTTOM, BOX_TOP)


func after_each() -> void:
	rig.queue_free()


func _box_corners() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for y in [BOX_BOTTOM, BOX_TOP]:
		for c in [FRAME.position, Vector2(FRAME.end.x, FRAME.position.y), FRAME.end, Vector2(FRAME.position.x, FRAME.end.y)]:
			out.append(Vector3(c.x, y, c.y))
	return out


func _on_screen(p: Vector2, size: Vector2) -> bool:
	return p != Vector2.INF and p.x >= 0.0 and p.x <= size.x and p.y >= 0.0 and p.y <= size.y


## Zooms in to roughly `target` distance around the screen centre.
func _zoom_to(target: float, view: Vector2 = PORTRAIT) -> void:
	rig.zoom_at(rig.distance() / target, view * 0.5)


func test_starts_framed_with_the_whole_box_on_screen() -> void:
	assert_true(rig.is_framed())
	assert_near(rig.pitch_degrees(), rig.config.pitch_far_degrees, 0.001)
	for corner in _box_corners():
		assert_true(_on_screen(rig.world_to_screen(corner), PORTRAIT), "corner %s visible" % corner)


func test_framing_is_tight_not_wasteful() -> void:
	# At 85% of the fit distance at least one corner must fall off screen,
	# otherwise the box is framed smaller than it needs to be.
	var probe := CameraRig.new(CameraConfig.new())
	add_child(probe)
	probe.set_process(false)
	probe.set_view_size(PORTRAIT)
	probe.setup(BOUNDS, FRAME, BOX_BOTTOM, BOX_TOP)
	probe.zoom_at(1.0 / 0.85, PORTRAIT * 0.5)
	var all_visible := true
	for corner in _box_corners():
		if not _on_screen(probe.world_to_screen(corner), PORTRAIT):
			all_visible = false
	probe.queue_free()
	assert_false(all_visible)


func test_both_orientations_frame_the_box() -> void:
	var portrait_fit := rig.fit_distance()
	rig.set_view_size(LANDSCAPE)
	assert_true(rig.is_framed(), "stays framed after rotating the device")
	for corner in _box_corners():
		assert_true(_on_screen(rig.world_to_screen(corner), LANDSCAPE), "corner %s visible in landscape" % corner)
	assert_true(rig.fit_distance() < portrait_fit, "landscape fits the box from closer than portrait")


func test_screen_centre_looks_at_the_pivot() -> void:
	var hit: Vector3 = rig.screen_to_ground(PORTRAIT * 0.5)
	assert_near(hit.x, rig.pivot().x, 0.001)
	assert_near(hit.z, rig.pivot().z, 0.001)
	var ray := rig.screen_ray(PORTRAIT * 0.5)
	assert_near(ray[1].length(), 1.0, 0.0001)


func test_projection_and_ray_are_inverse() -> void:
	_zoom_to(30.0)
	for screen in [Vector2(200, 300), Vector2(900, 1500), PORTRAIT * 0.5]:
		var ground: Vector3 = rig.screen_to_ground(screen)
		var back := rig.world_to_screen(ground)
		assert_near(back.x, screen.x, 0.01)
		assert_near(back.y, screen.y, 0.01)
	assert_eq(rig.world_to_screen(rig.camera_transform().origin + rig.camera_transform().basis.z * 5.0), Vector2.INF, "behind the camera")


func test_pan_keeps_the_grabbed_point_under_the_finger() -> void:
	_zoom_to(20.0)
	var from := Vector2(500, 900)
	var to := Vector2(620, 1010)
	var grabbed: Vector3 = rig.screen_to_ground(from)
	rig.pan_screen(from, to)
	var now := rig.world_to_screen(grabbed)
	assert_near(now.x, to.x, 0.5)
	assert_near(now.y, to.y, 0.5)


func test_zoom_keeps_the_focal_point_fixed() -> void:
	_zoom_to(20.0)
	var focal := Vector2(700, 800)
	var anchor: Vector3 = rig.screen_to_ground(focal)
	rig.zoom_at(1.3, focal)
	var now := rig.world_to_screen(anchor)
	assert_near(now.x, focal.x, 1.0)
	assert_near(now.y, focal.y, 1.0)
	rig.zoom_at(1.0 / 1.2, focal)
	now = rig.world_to_screen(anchor)
	assert_near(now.x, focal.x, 1.0, "also when zooming back out")
	assert_near(now.y, focal.y, 1.0)


func test_zoom_is_clamped_both_ways() -> void:
	rig.zoom_at(1000.0, PORTRAIT * 0.5)
	assert_near(rig.distance(), rig.config.min_distance, 0.0001)
	assert_near(rig.pitch_degrees(), rig.config.pitch_near_degrees, 0.001)
	assert_near(rig.zoom_fraction(), 1.0, 0.0001)
	rig.zoom_at(0.0001, PORTRAIT * 0.5)
	assert_near(rig.distance(), rig.fit_distance(), 0.0001)
	assert_true(rig.is_framed())
	rig.zoom_at(0.0, PORTRAIT * 0.5)
	rig.zoom_at(-3.0, PORTRAIT * 0.5)
	assert_near(rig.distance(), rig.fit_distance(), 0.0001, "nonsense factors are ignored")


func test_zooming_out_fully_returns_to_the_centre() -> void:
	_zoom_to(10.0)
	rig.pan_screen(Vector2(100, 100), Vector2(1000, 1800))
	assert_true(rig.pivot().distance_to(Vector3(0, rig.pivot().y, 0)) > 1.0, "panned away")
	rig.zoom_at(0.0001, Vector2(50, 50))
	assert_near(rig.pivot().x, 0.0, 0.0001)
	assert_near(rig.pivot().z, 0.0, 0.0001)


func test_the_camera_can_never_leave_the_world() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 400:
		match rng.randi() % 3:
			0:
				rig.pan_screen(Vector2(rng.randf() * 1080, rng.randf() * 1920), Vector2(rng.randf() * 1080, rng.randf() * 1920))
			1:
				rig.zoom_at(rng.randf_range(0.3, 3.0), Vector2(rng.randf() * 1080, rng.randf() * 1920))
			2:
				rig.set_view_size(LANDSCAPE if rng.randi() % 2 == 0 else PORTRAIT)
		var p := rig.pivot()
		var margin := rig.config.edge_margin_tiles + 0.001
		if is_nan(p.x) or is_nan(p.z) or is_nan(rig.distance()):
			fail("NaN after step %d" % i)
			return
		if p.x < BOUNDS.position.x - margin or p.x > BOUNDS.end.x + margin \
				or p.z < BOUNDS.position.y - margin or p.z > BOUNDS.end.y + margin:
			fail("pivot %s left the world at step %d" % [p, i])
			return
		if rig.distance() < rig.config.min_distance - 0.001 or rig.distance() > rig.fit_distance() + 0.001:
			fail("distance %f out of range at step %d" % [rig.distance(), i])
			return


func test_closer_zoom_lets_the_pivot_roam_further() -> void:
	_zoom_to(60.0)
	rig.pan_screen(Vector2(540, 960), Vector2(-50000, 960)) # shove hard to the +X edge
	var far_reach := rig.pivot().x
	_zoom_to(10.0)
	rig.pan_screen(Vector2(540, 960), Vector2(-50000, 960))
	assert_true(rig.pivot().x > far_reach + 5.0, "zoomed in, the view reaches further toward the edge")
	assert_true(rig.pivot().x <= BOUNDS.end.x + rig.config.edge_margin_tiles + 0.001)


func test_focus_animates_and_frame_box_returns() -> void:
	rig.focus_on(Vector3(10, 0, -5), 15.0)
	assert_true(rig.distance() > 15.5, "not there instantly")
	for i in 240:
		rig.advance(1.0 / 60.0)
	assert_near(rig.distance(), 15.0, 0.02)
	assert_near(rig.pivot().x, 10.0, 0.05)
	assert_near(rig.pivot().z, -5.0, 0.05)
	rig.frame_box()
	for i in 240:
		rig.advance(1.0 / 60.0)
	assert_true(rig.is_framed())
	assert_near(rig.distance(), rig.fit_distance(), 0.02)
	rig.focus_on(Vector3(500, 0, 500), 15.0, false)
	assert_true(rig.pivot().x <= BOUNDS.end.x + rig.config.edge_margin_tiles + 0.001, "focus targets are clamped too")


func test_gestures_drive_the_camera() -> void:
	_zoom_to(20.0)
	var before := rig.pivot()
	var drag := Gesture.new(Gesture.Type.DRAG)
	drag.position = Vector2(600, 1000)
	drag.delta = Vector2(60, 40)
	assert_true(rig.handle_gesture(drag))
	assert_true(rig.pivot().distance_to(before) > 0.1)
	var pinch := Gesture.new(Gesture.Type.PINCH)
	pinch.position = PORTRAIT * 0.5
	pinch.scale = 1.25
	var d := rig.distance()
	assert_true(rig.handle_gesture(pinch))
	assert_near(rig.distance(), d / 1.25, 0.001, "spreading fingers zooms in")
	var two := Gesture.new(Gesture.Type.TWO_FINGER_DRAG)
	two.position = Vector2(500, 900)
	two.delta = Vector2(-30, 0)
	assert_true(rig.handle_gesture(two))
	assert_false(rig.handle_gesture(Gesture.new(Gesture.Type.TAP)), "taps are for the world, not the camera")


func test_looks_at_the_ground_when_zoomed_in() -> void:
	rig.ground_height = func(_xz: Vector2) -> float: return 4.0 # a plateau everywhere
	assert_near(rig.pivot().y, rig.config.base_look_height, 0.001, "framed: fixed base height")
	rig.zoom_at(1000.0, PORTRAIT * 0.5)
	for i in 300:
		rig.advance(1.0 / 60.0)
	assert_near(rig.pivot().y, 4.0, 0.05, "closest zoom: looks at the surface")


func test_camera_node_follows_the_rig() -> void:
	_zoom_to(25.0)
	assert_true(rig.camera().transform.is_equal_approx(rig.camera_transform()))
	assert_near(rig.camera().fov, rig.config.fov_degrees, 0.001)
	assert_true(rig.camera().far > rig.fit_distance())


# --- M2.1: fling, rubber band, double tap, twist, guard -------------------------

func _gesture(type: Gesture.Type, position: Vector2 = PORTRAIT * 0.5) -> Gesture:
	var g := Gesture.new(type)
	g.position = position
	return g


## A full one-finger drag from `from` to `to`, released with `velocity`.
func _drag(from: Vector2, to: Vector2, velocity: Vector2 = Vector2.ZERO) -> void:
	rig.handle_gesture(_gesture(Gesture.Type.DRAG_START, from))
	var steps := 8
	for i in range(1, steps + 1):
		var g := _gesture(Gesture.Type.DRAG, from.lerp(to, float(i) / steps))
		g.delta = (to - from) / steps
		rig.handle_gesture(g)
	var end := _gesture(Gesture.Type.DRAG_END, to)
	end.velocity = velocity
	rig.handle_gesture(end)


func _run(seconds: float) -> void:
	for i in int(seconds * 60.0):
		rig.advance(1.0 / 60.0)


func test_fling_keeps_gliding_then_stops() -> void:
	_zoom_to(15.0)
	_drag(Vector2(540, 900), Vector2(600, 900), Vector2(1500, 0))
	assert_true(rig.is_flinging())
	var at_release := rig.pivot()
	_run(0.25)
	var early := rig.pivot().distance_to(at_release)
	assert_true(early > 0.3, "the world keeps moving after release (%f)" % early)
	_run(4.0)
	assert_false(rig.is_flinging(), "friction ends the fling")
	var total := rig.pivot().distance_to(at_release)
	assert_true(total > early, "it glided further before stopping")
	var rest := rig.pivot()
	_run(0.5)
	assert_true(rig.pivot().is_equal_approx(rest), "and then stays put")


func test_fling_direction_follows_the_finger() -> void:
	_zoom_to(15.0)
	var before := rig.pivot()
	_drag(Vector2(540, 900), Vector2(600, 900), Vector2(1500, 0)) # finger moving right
	_run(1.0)
	assert_true(rig.pivot().x < before.x, "dragging right moves the view left over the world")


func test_slow_release_does_not_fling() -> void:
	_zoom_to(15.0)
	_drag(Vector2(540, 900), Vector2(600, 900), Vector2(60, 0))
	assert_false(rig.is_flinging())


func test_touch_stops_a_fling_immediately() -> void:
	_zoom_to(15.0)
	_drag(Vector2(540, 900), Vector2(600, 900), Vector2(2500, 0))
	_run(0.1)
	rig.stop_motion()
	assert_false(rig.is_flinging())
	var at := rig.pivot()
	_run(0.5)
	assert_near(rig.pivot().x, at.x, 0.001)


func test_reduced_motion_disables_flings() -> void:
	rig.reduced_motion = true
	_zoom_to(15.0)
	_drag(Vector2(540, 900), Vector2(600, 900), Vector2(3000, 0))
	assert_false(rig.is_flinging())


func test_cancelled_or_after_multi_drags_never_fling() -> void:
	_zoom_to(15.0)
	for flag in ["cancelled", "after_multi"]:
		rig.handle_gesture(_gesture(Gesture.Type.DRAG_START))
		var end := _gesture(Gesture.Type.DRAG_END)
		end.velocity = Vector2(3000, 0)
		end.set(flag, true)
		rig.handle_gesture(end)
		assert_false(rig.is_flinging(), flag)


func test_rubber_band_gives_then_springs_back() -> void:
	# Framed: the pivot has no range at all, so any drag is overscroll.
	rig.handle_gesture(_gesture(Gesture.Type.DRAG_START, Vector2(540, 900)))
	var g := _gesture(Gesture.Type.DRAG, Vector2(740, 900))
	g.delta = Vector2(200, 0)
	rig.handle_gesture(g)
	var give := rig.pivot().distance_to(rig.clamped_pivot())
	assert_true(give > 0.5, "the view gives a little (%f tiles)" % give)
	# Dragging ten times further gives more, but far less than ten times.
	g = _gesture(Gesture.Type.DRAG, Vector2(2740, 900))
	g.delta = Vector2(2000, 0)
	rig.handle_gesture(g)
	var more := rig.pivot().distance_to(rig.clamped_pivot())
	assert_true(more > give and more < give * 6.0, "growing resistance (%f then %f)" % [give, more])
	# While the finger is down the view holds its position.
	_run(0.5)
	assert_near(rig.pivot().distance_to(rig.clamped_pivot()), more, 0.001, "no spring-back under the finger")
	# Released: it springs back to the centre.
	rig.handle_gesture(_gesture(Gesture.Type.DRAG_END, Vector2(2740, 900)))
	_run(2.0)
	assert_near(rig.pivot().x, 0.0, 0.02)
	assert_near(rig.pivot().z, 0.0, 0.02)


func test_overscroll_is_bounded() -> void:
	_zoom_to(20.0)
	rig.handle_gesture(_gesture(Gesture.Type.DRAG_START))
	for i in 50:
		var g := _gesture(Gesture.Type.DRAG, Vector2(540 - i * 400.0, 900))
		g.delta = Vector2(-400, 0)
		rig.handle_gesture(g)
	var over := rig.pivot().x - rig.clamped_pivot().x
	assert_true(over > 0.0, "pushed past the +X limit")
	assert_true(rig.pivot().x <= BOUNDS.end.x + rig.config.edge_margin_tiles + 0.001, "but never beyond the margin around the world")


func test_fling_into_the_edge_stops_and_returns() -> void:
	_zoom_to(20.0)
	_drag(Vector2(540, 900), Vector2(440, 900), Vector2(-9000, 0)) # hard flick toward +X
	_run(6.0)
	assert_false(rig.is_flinging())
	assert_true(rig.pivot().is_equal_approx(rig.clamped_pivot()), "resting inside the limits")


func test_double_tap_zooms_in_toward_the_point_then_back_out() -> void:
	var focal := Vector2(700, 1100)
	var start_distance := rig.distance()
	rig.handle_gesture(_gesture(Gesture.Type.DOUBLE_TAP, focal))
	assert_true(rig.is_moving(), "animated, not a jump")
	assert_near(rig.distance(), start_distance, 0.001)
	_run(3.0)
	assert_near(rig.distance(), start_distance / rig.config.double_tap_zoom, 0.05)
	# Keep tapping: it reaches the closest zoom, then a further tap frames the box.
	for i in 8:
		rig.handle_gesture(_gesture(Gesture.Type.DOUBLE_TAP, focal))
		_run(3.0)
		if rig.is_framed():
			break
	assert_true(rig.is_framed(), "from the closest zoom a double tap returns to the whole box")


func test_pan_world_slides_the_view_within_its_limits() -> void:
	_zoom_to(20.0)
	var before := rig.pivot()
	rig.pan_world(Vector2(2.0, -1.5))
	assert_near(rig.pivot().x, before.x + 2.0, 0.0001)
	assert_near(rig.pivot().z, before.z - 1.5, 0.0001)
	assert_false(rig.is_moving(), "at once, no animation")
	rig.pan_world(Vector2(5000.0, 0.0))
	assert_true(rig.pivot().is_equal_approx(rig.clamped_pivot()), "stops at the limit: no rubber band")
	_run(1.0)
	assert_true(rig.pivot().is_equal_approx(rig.clamped_pivot()))
	# With the whole box in view there is nowhere to go.
	rig.frame_box(false)
	var framed := rig.pivot()
	rig.pan_world(Vector2(3.0, 3.0))
	assert_true(rig.pivot().is_equal_approx(framed))
	assert_eq(rig.view_size(), Vector2(1080, 1920))


func test_double_tap_can_be_left_to_someone_else() -> void:
	rig.handles_double_tap = false
	var start_distance := rig.distance()
	assert_false(rig.handle_gesture(_gesture(Gesture.Type.DOUBLE_TAP, Vector2(700, 1100))))
	_run(1.0)
	assert_near(rig.distance(), start_distance, 0.001, "the rig did nothing")
	assert_false(rig.is_moving())


func test_zoom_to_keeps_the_focal_point_when_free() -> void:
	_zoom_to(30.0)
	var focal := Vector2(600, 1000)
	var anchor: Vector3 = rig.screen_to_ground(focal)
	rig.zoom_to(12.0, focal)
	_run(4.0)
	assert_near(rig.distance(), 12.0, 0.02)
	var now := rig.world_to_screen(anchor)
	assert_near(now.x, focal.x, 12.0, "the tapped spot ends under the finger")
	assert_near(now.y, focal.y, 12.0)


func test_twist_is_off_by_default() -> void:
	_zoom_to(20.0)
	rig.handle_gesture(_gesture(Gesture.Type.MULTI_START))
	var twist := _gesture(Gesture.Type.TWIST)
	twist.angle = 0.5
	assert_false(rig.handle_gesture(twist), "ignored unless enabled")
	assert_eq(rig.yaw, 0.0)


func test_twist_rotates_around_the_fingers() -> void:
	rig.twist_enabled = true
	_zoom_to(20.0)
	var focal := Vector2(540, 960)
	var anchor: Vector3 = rig.screen_to_ground(focal)
	# A point to the right of the focal point, on the ground.
	var right_point: Vector3 = rig.screen_to_ground(focal + Vector2(200, 0))
	rig.handle_gesture(_gesture(Gesture.Type.MULTI_START, focal))
	var twist := _gesture(Gesture.Type.TWIST, focal)
	twist.angle = deg_to_rad(30.0) # fingers turn clockwise on screen
	assert_true(rig.handle_gesture(twist))
	assert_near(absf(rig.yaw), deg_to_rad(30.0), 0.0001)
	var anchor_now := rig.world_to_screen(anchor)
	assert_near(anchor_now.x, focal.x, 1.0, "the point between the fingers stays put")
	assert_near(anchor_now.y, focal.y, 1.0)
	var right_now := rig.world_to_screen(right_point)
	assert_true(right_now.y > focal.y + 20.0, "the world turns clockwise with the fingers (right side moves down)")


func test_rotated_view_still_frames_the_whole_box() -> void:
	rig.twist_enabled = true
	rig.handle_gesture(_gesture(Gesture.Type.MULTI_START))
	var twist := _gesture(Gesture.Type.TWIST)
	twist.angle = deg_to_rad(45.0)
	rig.handle_gesture(twist)
	rig.handle_gesture(_gesture(Gesture.Type.MULTI_END))
	rig.frame_box(false)
	for corner in _box_corners():
		assert_true(_on_screen(rig.world_to_screen(corner), PORTRAIT), "corner %s visible at 45 degrees" % corner)


func test_guard_recovers_from_an_invalid_state() -> void:
	_zoom_to(20.0)
	rig._pivot = Vector3(NAN, 0, 0)
	rig.advance(1.0 / 60.0)
	assert_true(rig.is_framed(), "NaN -> reframed")
	assert_true(is_finite(rig.pivot().x))
	_zoom_to(20.0)
	rig._pivot = Vector3(5000, 0, -5000)
	rig._goal_pivot = rig._pivot
	rig._touching = true # even mid-drag
	rig.advance(1.0 / 60.0)
	assert_true(rig.is_framed(), "far outside the world -> reframed")
	assert_near(rig.pivot().x, 0.0, 0.001)
