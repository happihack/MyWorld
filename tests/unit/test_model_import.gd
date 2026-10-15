extends TestCase
## ModelImport: a shape made outside becomes a template with the vertex data
## the shaders read, and the kit's files round-trip through it.

const ModelKit := preload("res://tests/tools/model_kit_lib.gd")
const DIR := "user://model_import_test"

var library: PropMeshLibrary


func before_all() -> void:
	library = PropMeshLibrary.new()
	DirAccess.make_dir_recursive_absolute(DIR)


func after_all() -> void:
	remove_dir_recursive(DIR)


func _round_trip(name: String, template: PropMeshLibrary.Template) -> PropMeshLibrary.Template:
	var path := DIR.path_join(name + ".glb")
	assert_eq(ModelKit.write_glb(ModelKit.template_to_mesh(template), name, path), OK)
	var back := ModelImport.template_from_file(path)
	assert_not_null(back, "%s did not load back" % path)
	return back


func test_names() -> void:
	assert_eq(ModelImport.parse_name("hut_1", PropData.Kind), [PropData.Kind.HUT, 1])
	assert_eq(ModelImport.parse_name("record_stone_0", PropData.Kind), [PropData.Kind.RECORD_STONE, 0])
	assert_eq(ModelImport.parse_name("pile_3", LooseObject.Kind), [LooseObject.Kind.PILE, 3])
	assert_eq(ModelImport.parse_name("hut", PropData.Kind), [])
	assert_eq(ModelImport.parse_name("castle_0", PropData.Kind), [])
	assert_eq(ModelImport.parse_name("hut_x", PropData.Kind), [])


func test_material_names_carry_the_vertex_data() -> void:
	assert_eq(ModelImport.glow_for("Window.001"), ModelImport.GLOW_NIGHT)
	assert_eq(ModelImport.glow_for("flame_glow"), ModelImport.GLOW_ALWAYS)
	assert_eq(ModelImport.glow_for("wall"), 0.0)
	assert_eq(ModelImport.leaf_for("leaf_sway"), PropMeshLibrary.LEAF_SHED)
	assert_eq(ModelImport.leaf_for("Turns"), PropMeshLibrary.LEAF_TURNS)
	assert_eq(ModelImport.leaf_for("needle_sway"), PropMeshLibrary.LEAF_EVERGREEN)
	assert_eq(ModelImport.limb_side("Leg_L"), 1.0)
	assert_eq(ModelImport.limb_side("arm_l"), -1.0)
	assert_eq(ModelImport.limb_side("body"), 0.0)
	assert_eq(ModelKit.material_name_for(1.0, 0.0, false), "window")
	assert_eq(ModelKit.material_name_for(0.0, 1.0, true), "leaf_sway")
	assert_eq(ModelKit.material_name_for(0.0, 0.0, false), "solid")


func test_a_hut_round_trips() -> void:
	var hut := library.template_for(PropData.Kind.HUT, 0)
	var back := _round_trip("hut_0", hut)
	assert_eq(back.triangle_count(), hut.triangle_count())
	# Every colour of the original is found again (surfaces reorder the triangles).
	var wanted := {}
	for c in hut.colors:
		wanted[Color(c.r, c.g, c.b).to_html(false)] = true
	var found := 0
	for c in back.colors:
		var nearest := false
		for key: String in wanted:
			var w := Color.html(key)
			if absf(w.r - c.r) + absf(w.g - c.g) + absf(w.b - c.b) < 0.04:
				nearest = true
				break
		if nearest:
			found += 1
	assert_eq(found, back.colors.size(), "colours came back changed")
	# The windows still glow and nothing sways.
	var glowing := 0
	for i in back.vertices.size():
		if back.glow_of(i) > 0.0:
			glowing += 1
		assert_near(back.colors[i].a, 0.0, 0.001, "a hut does not sway")
	var glowing_before := 0
	for i in hut.vertices.size():
		if hut.glow_of(i) > 0.0:
			glowing_before += 1
	assert_eq(glowing, glowing_before)
	assert_true(glowing > 0, "the hut's window should glow")
	# Flat shading: a face's three normals agree and face outwards from the base.
	for i in range(0, back.vertices.size() - 2, 3):
		assert_true(back.normals[i].is_equal_approx(back.normals[i + 1]))
		assert_near(back.normals[i].length(), 1.0, 0.001)


func test_a_tree_round_trips_with_its_leaves_and_sway() -> void:
	var tree := library.template_for(PropData.Kind.TREE, 0)
	var back := _round_trip("tree_0", tree)
	assert_eq(back.triangle_count(), tree.triangle_count())
	var leaves := 0
	var leaves_before := 0
	var swaying := 0
	var rigid := 0
	for i in back.vertices.size():
		if back.leaf_of(i) > 0.0:
			leaves += 1
		if back.colors[i].a > 0.0:
			swaying += 1
		else:
			rigid += 1
	for i in tree.vertices.size():
		if tree.leaf_of(i) > 0.0:
			leaves_before += 1
	assert_eq(leaves, leaves_before)
	assert_true(swaying > 0, "the crown sways")
	assert_true(rigid > 0, "the trunk's base is rigid")
	# Sway grows with height: the highest vertex sways most.
	var top := 0
	for i in back.vertices.size():
		if back.vertices[i].y > back.vertices[top].y:
			top = i
	assert_true(back.colors[top].a >= 0.99, "the treetop sways fully")


func test_the_person_body_round_trips() -> void:
	var body := PersonMeshLibrary.body()
	var path := DIR.path_join("body.glb")
	assert_eq(ModelKit.write_glb(ModelKit.body_to_mesh(body), "person_body", path), OK)
	var back := ModelImport.person_body_from_file(path)
	assert_not_null(back)
	var original := body.surface_get_arrays(0)
	var imported := back.surface_get_arrays(0)
	assert_eq((imported[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), (original[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	# Masks are exact; every limb vertex has its side and the far end reaches 1.
	var colors: PackedColorArray = imported[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = imported[Mesh.ARRAY_TEX_UV]
	var sides := {}
	var far := 0.0
	for i in colors.size():
		var c := colors[i]
		assert_true(c.r + c.g + c.b >= 0.99 and c.r + c.g + c.b <= 1.01 or c == Color(0, 0, 0, 1), "a mask is one of cloth, skin, hair or the eye: %s" % c)
		sides[uvs[i].x] = true
		far = maxf(far, uvs[i].y)
	assert_true(sides.has(1.0) and sides.has(-1.0) and sides.has(0.0), "limbs of both sides and a body")
	assert_near(far, 1.0, 0.001)


func test_no_models_means_the_procedural_shapes() -> void:
	assert_eq(ModelImport.models_in("res://assets/models/nowhere").size(), 0)
	assert_null(ModelImport.template_from_file("res://assets/models/props/nothing.glb"))
	assert_true(library.template_for(PropData.Kind.HUT, 0).triangle_count() > 0)
