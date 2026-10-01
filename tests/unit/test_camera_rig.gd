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
