extends TestCase

const BOUNDS := Rect2i(-32, -32, 64, 64)
const HEIGHT := 9.0

var frame: BoxFrame


func before_each() -> void:
	frame = BoxFrame.new()
	add_child(frame)
	frame.build(BOUNDS, HEIGHT)


func after_each() -> void:
	frame.queue_free()


func test_three_meshes_one_surface_each() -> void:
	for mesh in [frame.wood_mesh(), frame.brass_mesh(), frame.glass_mesh()]:
		assert_not_null(mesh)
		assert_eq(mesh.get_surface_count(), 1)


func test_plinth_surrounds_the_world_without_covering_it() -> void:
	var aabb := frame.wood_mesh().get_aabb()
	var t := frame.thickness
	assert_true(t >= BoxFrame.MIN_THICKNESS and t <= BoxFrame.MAX_THICKNESS)
	# Outer footprint = bounds + thickness + molding, matching outer_rect().
	var outer := frame.outer_rect()
	assert_near(aabb.position.x, outer.position.x, 0.001)
	assert_near(aabb.position.z, outer.position.y, 0.001)
	assert_near(aabb.size.x, outer.size.x, 0.001)
	assert_near(aabb.size.z, outer.size.y, 0.001)
	assert_true(outer.position.x < BOUNDS.position.x - t and outer.end.x > BOUNDS.end.x + t)
	# From the bottom of the molding up to a low rim.
	assert_near(aabb.position.y, frame.bottom_y(), 0.001)
	assert_near(aabb.end.y, BoxFrame.RIM_HEIGHT, 0.001)
	assert_true(BoxFrame.RIM_HEIGHT < 1.0, "the rim stays low so it never hides the world")


func test_no_wood_inside_the_world_bounds() -> void:
	# Every wood vertex lies on or outside the bounds rectangle (the terrain
	# fills the inside), except the molding slab which sits entirely below it.
	var arrays := frame.wood_mesh().surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for v in vertices:
		if v.y <= -BoxFrame.PLINTH_DEPTH + 0.0001:
			continue # molding
		var inside := v.x > BOUNDS.position.x + 0.001 and v.x < BOUNDS.end.x - 0.001 \
			and v.z > BOUNDS.position.y + 0.001 and v.z < BOUNDS.end.y - 0.001
		if inside:
			fail("wood vertex inside the world at %s" % v)
			return


func test_posts_reach_the_box_height() -> void:
	var aabb := frame.brass_mesh().get_aabb()
	assert_near(aabb.end.y, HEIGHT, 0.001)
	assert_near(aabb.position.y, BoxFrame.RIM_HEIGHT, 0.001, "posts stand on the rim")
	assert_true(aabb.position.x < BOUNDS.position.x and aabb.end.x > BOUNDS.end.x, "posts sit outside the corners")


func test_glass_spans_rim_to_rails_and_fades_out_at_the_bottom() -> void:
	var arrays := frame.glass_mesh().surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_eq(vertices.size(), 4 * 6, "four panes")
	var top_alpha := 0.0
	for i in vertices.size():
		if is_equal_approx(vertices[i].y, BoxFrame.RIM_HEIGHT):
			assert_near(colors[i].a, 0.0, 0.005, "invisible at the rim")
		else:
			top_alpha = maxf(top_alpha, colors[i].a)
	assert_true(top_alpha > 0.0 and top_alpha < 0.1, "a faint tint at the top (%f)" % top_alpha)


func test_glass_opacity_differs_by_blending_mode() -> void:
	assert_true(BoxFrame.glass_opacity(false) < BoxFrame.glass_opacity(true),
		"linear-light blending needs far less opacity to look the same")


func test_rebuild_follows_new_bounds() -> void:
	var small := frame.wood_mesh().get_aabb().size.x
	frame.build(Rect2i(-64, -64, 128, 128), 12.0)
	assert_eq(frame.bounds, Rect2i(-64, -64, 128, 128))
	assert_true(frame.wood_mesh().get_aabb().size.x > small + 60.0, "the frame grew with the box")
	assert_near(frame.brass_mesh().get_aabb().end.y, 12.0, 0.001)
	assert_true(frame.thickness > 1.4, "a bigger box gets a thicker frame")


func test_thickness_is_clamped() -> void:
	frame.build(Rect2i(0, 0, 16, 16), 5.0)
	assert_eq(frame.thickness, BoxFrame.MIN_THICKNESS)
	frame.build(Rect2i(0, 0, 512, 512), 5.0)
	assert_eq(frame.thickness, BoxFrame.MAX_THICKNESS)


func test_frame_triangles_face_their_normals() -> void:
	for mesh in [frame.wood_mesh(), frame.brass_mesh()]:
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in range(0, vertices.size(), 3):
			var facing := (vertices[i + 2] - vertices[i]).cross(vertices[i + 1] - vertices[i])
			if facing.normalized().dot(normals[i]) < 0.99:
				fail("triangle %d faces away from its normal" % (i / 3))
				return


func test_graphics_quality_resolution() -> void:
	var L := GraphicsQuality.Level
	assert_eq(GraphicsQuality.resolve("low", true, false), L.LOW)
	assert_eq(GraphicsQuality.resolve("medium", false, true), L.MEDIUM, "an explicit choice wins")
	assert_eq(GraphicsQuality.resolve("HIGH", true, false), L.HIGH, "case-insensitive")
	assert_eq(GraphicsQuality.resolve("auto", true, false), L.MEDIUM, "phones default to medium")
	assert_eq(GraphicsQuality.resolve("auto", false, false), L.HIGH, "desktop defaults to high")
	assert_eq(GraphicsQuality.resolve("auto", true, true), L.LOW, "the OpenGL fallback defaults to low")
	assert_eq(GraphicsQuality.resolve("nonsense", false, false), L.HIGH, "unknown values behave like auto")
	assert_false(GraphicsQuality.shadows_enabled(L.LOW))
	assert_true(GraphicsQuality.shadows_enabled(L.MEDIUM))
	assert_true(GraphicsQuality.shadow_atlas_size(L.HIGH) > GraphicsQuality.shadow_atlas_size(L.MEDIUM))
	assert_false(GraphicsQuality.vignette_enabled(L.LOW))
	assert_eq(GraphicsQuality.level_name(L.MEDIUM), "medium")
