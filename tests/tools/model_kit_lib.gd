extends RefCounted
## The Blender reference kit: the game's own shapes as .glb files at the
## game's scale, with their materials named the way ModelImport reads them, so
## a modeller sees the conventions in Blender instead of reading about them.
## model_kit.gd (`godot --headless --path . -s res://tests/tools/model_kit.gd`)
## writes docs/blender_kit/*.glb with it (see docs/blender_kit.md); test_model_import
## round-trips through it.

const OUT_DIR := "res://docs/blender_kit"


## A template as an ArrayMesh with one surface per class of vertex data
## (glow, leaf, sway), each with a material named for it; colours written
## linear, as glTF wants them, so Blender shows the palette's colours.
static func template_to_mesh(t: PropMeshLibrary.Template) -> ArrayMesh:
	var groups := {} # material name -> [vertices, normals, colors]
	for i in range(0, t.vertices.size() - 2, 3):
		var name := material_name_for(t.glow_of(i), t.leaf_of(i), t.colors[i].a > 0.01)
		if not groups.has(name):
			groups[name] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
		var g: Array = groups[name]
		for j in 3:
			g[0].append(t.vertices[i + j])
			g[1].append(t.normals[i + j])
			var c := t.colors[i + j]
			var linear := Color(c.r, c.g, c.b, 1.0).srgb_to_linear()
			g[2].append(Color(linear.r, linear.g, linear.b, c.a if c.a > 0.01 else 1.0))
	var mesh := ArrayMesh.new()
	for name: String in groups:
		var g: Array = groups[name]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g[0]
		arrays[Mesh.ARRAY_NORMAL] = g[1]
		arrays[Mesh.ARRAY_COLOR] = g[2]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(name, g[2]))
	return mesh


## The person body as a mesh whose surfaces are the limbs and the rest, named
## for ModelImport; its colours are the masks and stay as they are.
static func body_to_mesh(body: ArrayMesh) -> ArrayMesh:
	var arrays := body.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var groups := {}
	for i in range(0, vertices.size() - 2, 3):
		var side := uvs[i].x
		var name := "body"
		if side != 0.0:
			# Legs hang below the hip, arms from the shoulder (PersonMeshLibrary).
			var is_leg := vertices[i].y < 0.31
			if is_leg:
				name = "leg_l" if side > 0.0 else "leg_r"
			else:
				name = "arm_l" if side < 0.0 else "arm_r"
		if not groups.has(name):
			groups[name] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
		var g: Array = groups[name]
		for j in 3:
			g[0].append(vertices[i + j])
			g[1].append(normals[i + j])
			g[2].append(colors[i + j])
	var mesh := ArrayMesh.new()
	for name: String in groups:
		var g: Array = groups[name]
		var out: Array = []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = g[0]
		out[Mesh.ARRAY_NORMAL] = g[1]
		out[Mesh.ARRAY_COLOR] = g[2]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(name, g[2]))
	return mesh


static func material_name_for(glow: float, leaf: float, swaying: bool) -> String:
	var parts := PackedStringArray()
	if leaf >= 0.9:
		parts.append("leaf")
	elif leaf >= 0.4:
		parts.append("turns")
	elif leaf > 0.0:
		parts.append("needle")
	if glow >= 1.5:
		parts.append("flame")
	elif glow > 0.0:
		parts.append("window")
	if swaying:
		parts.append("sway")
	return "_".join(parts) if not parts.is_empty() else "solid"


## Writes `mesh` as a .glb named `name`. Returns the error.
static func write_glb(mesh: ArrayMesh, name: String, path: String) -> Error:
	var root := Node3D.new()
	root.name = name
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	root.add_child(instance)
	instance.owner = root
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	if err == OK:
		err = doc.write_to_filesystem(state, path)
	root.free()
	return err


static func _material(name: String, colors: PackedColorArray) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = name
	material.vertex_color_use_as_albedo = true
	if not colors.is_empty():
		var sum := Color(0, 0, 0, 1)
		for c in colors:
			sum += Color(c.r, c.g, c.b, 0.0)
		material.albedo_color = Color(sum.r / colors.size(), sum.g / colors.size(), sum.b / colors.size()).linear_to_srgb()
	return material


static func write_all() -> int:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var library := PropMeshLibrary.new()
	var files := {
		"hut_thatch": library.template_for(PropData.Kind.HUT, 0),
		"hut_reeds": library.template_for(PropData.Kind.HUT, 1),
		"hut_hides": library.template_for(PropData.Kind.HUT, 2),
		"tree_broadleaf": library.template_for(PropData.Kind.TREE, 0),
		"tree_conifer": library.template_for(PropData.Kind.TREE, 2),
		"campfire": library.template_for(PropData.Kind.CAMPFIRE, 0),
		"storehouse": library.template_for(PropData.Kind.STOREHOUSE, 0),
		"rock": library.template_for(PropData.Kind.ROCK, 0),
		"bush": library.template_for(PropData.Kind.BUSH, 0),
	}
	var failed := 0
	for name: String in files:
		var path := OUT_DIR.path_join(name + ".glb")
		var err := write_glb(template_to_mesh(files[name]), name, path)
		if err != OK:
			push_error("model_kit: %s: %s" % [path, error_string(err)])
			failed += 1
		else:
			print("wrote ", path, " (", files[name].triangle_count(), " triangles)")
	var body_path := OUT_DIR.path_join("person_body.glb")
	var err := write_glb(body_to_mesh(PersonMeshLibrary.body()), "person_body", body_path)
	if err != OK:
		push_error("model_kit: %s: %s" % [body_path, error_string(err)])
		failed += 1
	else:
		print("wrote ", body_path)
	return failed
