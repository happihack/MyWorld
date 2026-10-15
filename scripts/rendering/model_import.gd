class_name ModelImport
extends RefCounted
## Shapes made outside (Blender → glTF) brought into the one pipeline (the art
## decisions of 2026-10-15: the owner models hero shapes; docs/blender_kit.md
## has the conventions, docs/blender_kit/ the reference files).
##
## A model becomes a PropMeshLibrary.Template: flat-shaded, non-indexed
## triangles, 1 unit = 1 tile, the base at y = 0. What the prop shader reads
## from the vertices comes from the MATERIAL NAMES of the model, so a modeller
## never paints UVs:
##   "sway"            wind sway by height (0 at the model's base, 1 at its top)
##   "glow", "window"  lit at night (glow 1);  "flame"  always lit (glow 2)
##   "leaf"            a leaf that turns and falls (1.0);  "turns"  only turns
##                     colour (0.6);  "needle", "evergreen"  hardly changes (0.2)
## Vertex colours (COLOR_0; linear in the file, as glTF has it) are the colour;
## a surface without them takes its material's albedo. A vertex alpha below 1
## is the sway weight as painted, and wins over "sway".
##
## Files: assets/models/props/<kind>_<variant>.glb replaces that procedural
## prop (kind = PropData.Kind in lower case: hut_1.glb); assets/models/loose/
## the same for LooseObject.Kind; assets/models/person/body.glb is the body
## (materials leg_l, leg_r, arm_l, arm_r are the limbs; vertex colours are the
## masks: red cloth, green skin, blue hair, alpha the shade).

const PROPS_DIR := "res://assets/models/props"
const LOOSE_DIR := "res://assets/models/loose"
const PERSON_BODY := "res://assets/models/person/body.glb"

const GLOW_NIGHT := 1.0
const GLOW_ALWAYS := 2.0

## What a limb's material name means: which way it swings (person_motion:
## +1 / -1 swing opposite ways; an arm against the leg of its own side; the
## face looks along +X, so the left is +Z).
const LIMBS := {"leg_l": 1.0, "leg_r": -1.0, "arm_l": -1.0, "arm_r": 1.0}


# --- files ---------------------------------------------------------------------------------

## The scene of a model file: one imported by the editor (res://), or any
## .glb / .gltf read at run time (tests, files dropped into user://). Null
## when there is no such file; the caller frees it.
static func load_scene(path: String) -> Node:
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed != null:
			return packed.instantiate()
	if FileAccess.file_exists(path):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) == OK:
			return doc.generate_scene(state)
	return null


static func template_from_file(path: String) -> PropMeshLibrary.Template:
	var scene := load_scene(path)
	if scene == null:
		return null
	var template := template_from_scene(scene)
	scene.free()
	return template


static func person_body_from_file(path: String) -> ArrayMesh:
	var scene := load_scene(path)
	if scene == null:
		return null
	var mesh := person_body_from_scene(scene)
	scene.free()
	return mesh


## The model files in a folder, by name without extension (an exported game
## lists the imports, not the files): {"hut_1": "res://…/hut_1.glb"}.
static func models_in(dir: String) -> Dictionary:
	var out := {}
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for file in DirAccess.get_files_at(dir):
		var name := file
		if name.ends_with(".import"):
			name = name.trim_suffix(".import")
		if not (name.ends_with(".glb") or name.ends_with(".gltf")):
			continue
		out[name.get_basename()] = dir.path_join(name)
	return out


## "hut_1" → [PropData.Kind.HUT, 1]; [] when it names no kind. `kinds` is the
## enum (PropData.Kind, LooseObject.Kind).
static func parse_name(name: String, kinds: Dictionary) -> Array:
	var cut := name.rfind("_")
	if cut <= 0 or not name.substr(cut + 1).is_valid_int():
		return []
	var kind_name := name.substr(0, cut).to_upper()
	if not kinds.has(kind_name):
		return []
	return [kinds[kind_name], int(name.substr(cut + 1))]


# --- props -----------------------------------------------------------------------------------

## The model as one template, in the scene root's frame.
static func template_from_scene(root: Node) -> PropMeshLibrary.Template:
	var t := PropMeshLibrary.Template.new()
	var surfaces := _surfaces(root, Transform3D.IDENTITY)
	var low := INF
	var high := -INF
	for s: Dictionary in surfaces:
		for v: Vector3 in s.vertices:
			low = minf(low, v.y)
			high = maxf(high, v.y)
	var height := maxf(high - low, 0.001)
	for s: Dictionary in surfaces:
		var name: String = s.material_name
		var from := t.vertices.size()
		var painted: PackedColorArray = s.colors
		var albedo: Color = s.albedo
		var by_height := name.contains("sway")
		var vertices: PackedVector3Array = s.vertices
		for i in range(0, vertices.size() - 2, 3):
			var a := vertices[i]
			var b := vertices[i + 1]
			var c := vertices[i + 2]
			var normal := (b - a).cross(c - a).normalized()
			for j in 3:
				var p := vertices[i + j]
				var color := painted[i + j].linear_to_srgb() if painted.size() > i + j else albedo
				var sway := 0.0
				if painted.size() > i + j and painted[i + j].a < 0.999:
					sway = painted[i + j].a
				elif by_height:
					sway = clampf((p.y - low) / height, 0.0, 1.0)
				t.vertices.append(p)
				t.normals.append(normal)
				t.colors.append(Color(color.r, color.g, color.b, sway))
		var glow := glow_for(name)
		if glow > 0.0:
			t.glow_from(from, glow)
		var leaf := leaf_for(name)
		if leaf > 0.0:
			t.leaf_from(from, leaf)
	return t


static func glow_for(material_name: String) -> float:
	var n := material_name.to_lower()
	if n.contains("flame"):
		return GLOW_ALWAYS
	if n.contains("glow") or n.contains("window"):
		return GLOW_NIGHT
	return 0.0


static func leaf_for(material_name: String) -> float:
	var n := material_name.to_lower()
	if n.contains("needle") or n.contains("evergreen"):
		return PropMeshLibrary.LEAF_EVERGREEN
	if n.contains("turns"):
		return PropMeshLibrary.LEAF_TURNS
	if n.contains("leaf"):
		return PropMeshLibrary.LEAF_SHED
	return 0.0


# --- the person -----------------------------------------------------------------------------

## The body as PersonMeshLibrary.body() has it: colours are the masks as
## painted (no colour-space change: red, green, blue and the alpha shade are
## exact values), UV the limb (side from the material name; along the limb
## from the top of that surface, where it joins the body, to its far end).
static func person_body_from_scene(root: Node) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	for s: Dictionary in _surfaces(root, Transform3D.IDENTITY):
		var side := limb_side(s.material_name)
		var top := -INF
		var bottom := INF
		for v: Vector3 in s.vertices:
			top = maxf(top, v.y)
			bottom = minf(bottom, v.y)
		var painted: PackedColorArray = s.colors
		var albedo: Color = s.albedo
		var points: PackedVector3Array = s.vertices
		for i in range(0, points.size() - 2, 3):
			var normal := (points[i + 1] - points[i]).cross(points[i + 2] - points[i]).normalized()
			for j in 3:
				var p := points[i + j]
				vertices.append(p)
				normals.append(normal)
				colors.append(painted[i + j] if painted.size() > i + j else albedo)
				var along := clampf(inverse_lerp(top, bottom, p.y), 0.0, 1.0) if side != 0.0 else 0.0
				uvs.append(Vector2(side, along))
	if vertices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# The shader moves vertices: room so the body is not culled mid-step.
	var aabb := AABB(vertices[0], Vector3.ZERO)
	for v in vertices:
		aabb = aabb.expand(v)
	mesh.custom_aabb = aabb.grow(0.3)
	return mesh


static func limb_side(material_name: String) -> float:
	var n := material_name.to_lower()
	for key: String in LIMBS:
		if n.contains(key):
			return LIMBS[key]
	return 0.0


# --- reading the scene -----------------------------------------------------------------------

## Every surface of every mesh under `node`, de-indexed and transformed into
## the root's frame: {vertices, colors, material_name, albedo}.
static func _surfaces(node: Node, xform: Transform3D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var here := xform
	if node is Node3D:
		here = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(i)
				var material := mi.get_active_material(i)
				var name := material.resource_name if material != null else ""
				var albedo := Color.WHITE
				if material is BaseMaterial3D:
					albedo = (material as BaseMaterial3D).albedo_color
				var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var painted: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var vertices := PackedVector3Array()
				var colors := PackedColorArray()
				if indices.is_empty():
					vertices = here * points
					colors = painted
				else:
					vertices.resize(indices.size())
					if not painted.is_empty():
						colors.resize(indices.size())
					for k in indices.size():
						vertices[k] = here * points[indices[k]]
						if not painted.is_empty():
							colors[k] = painted[indices[k]]
				out.append({"vertices": vertices, "colors": colors, "material_name": name, "albedo": albedo})
	for child in node.get_children():
		out.append_array(_surfaces(child, here))
	return out
