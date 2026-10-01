class_name AnimalMeshLibrary
extends RefCounted
## The shapes animals are drawn with: small blocky bodies in the style of
## the people and props, facing +X, standing on y = 0, in tiles. One mesh
## per shape name (SpeciesDef.shape), coloured by the species.

static var _meshes: Dictionary = {} # "shape:color" -> ArrayMesh


## The mesh for a species (null if its shape is unknown).
static func mesh_for(def: SpeciesDef) -> ArrayMesh:
	if def == null:
		return null
	var key := "%s:%s" % [def.shape, def.color.to_html()]
	if not _meshes.has(key):
		_meshes[key] = _build(def.shape, def.color)
	return _meshes[key]


static func has_shape(shape: StringName) -> bool:
	return shape == &"deer" or shape == &"rabbit" or shape == &"fox"


static func _build(shape: StringName, color: Color) -> ArrayMesh:
	var t := PropMeshLibrary.Template.new()
	var dark := _plain(color.darkened(0.3))
	var body := _plain(color)
	var light := _plain(color.lightened(0.35))
	match shape:
		&"deer":
			# Four legs, a long body, a neck held up, small antlers.
			for leg: Vector2 in [Vector2(-0.17, -0.07), Vector2(-0.17, 0.07), Vector2(0.16, -0.07), Vector2(0.16, 0.07)]:
				PropMeshLibrary._box(t, Vector3(leg.x, 0.14, leg.y), Vector3(0.028, 0.14, 0.028), dark)
			PropMeshLibrary._box(t, Vector3(0.0, 0.36, 0.0), Vector3(0.24, 0.1, 0.1), body)
			PropMeshLibrary._box(t, Vector3(0.24, 0.47, 0.0), Vector3(0.05, 0.11, 0.05), body)
			PropMeshLibrary._box(t, Vector3(0.31, 0.57, 0.0), Vector3(0.085, 0.05, 0.055), body)
			PropMeshLibrary._box(t, Vector3(-0.25, 0.4, 0.0), Vector3(0.025, 0.04, 0.03), light)
			PropMeshLibrary._box(t, Vector3(0.28, 0.66, -0.045), Vector3(0.012, 0.05, 0.012), light)
			PropMeshLibrary._box(t, Vector3(0.28, 0.66, 0.045), Vector3(0.012, 0.05, 0.012), light)
		&"rabbit":
			# A round body, a head, two ears up, a white scut.
			PropMeshLibrary._box(t, Vector3(0.0, 0.07, 0.0), Vector3(0.09, 0.06, 0.06), body)
			PropMeshLibrary._box(t, Vector3(0.09, 0.12, 0.0), Vector3(0.045, 0.04, 0.04), body)
			PropMeshLibrary._box(t, Vector3(0.08, 0.2, -0.02), Vector3(0.012, 0.045, 0.012), dark)
			PropMeshLibrary._box(t, Vector3(0.08, 0.2, 0.02), Vector3(0.012, 0.045, 0.012), dark)
			PropMeshLibrary._box(t, Vector3(-0.1, 0.08, 0.0), Vector3(0.02, 0.02, 0.02), _plain(Color(0.95, 0.95, 0.92)))
		&"fox":
			# Low and long, pointed ears, a bushy tail with a pale tip.
			for leg: Vector2 in [Vector2(-0.11, -0.045), Vector2(-0.11, 0.045), Vector2(0.11, -0.045), Vector2(0.11, 0.045)]:
				PropMeshLibrary._box(t, Vector3(leg.x, 0.06, leg.y), Vector3(0.02, 0.06, 0.02), dark)
			PropMeshLibrary._box(t, Vector3(0.0, 0.17, 0.0), Vector3(0.16, 0.06, 0.065), body)
			PropMeshLibrary._box(t, Vector3(0.19, 0.22, 0.0), Vector3(0.06, 0.05, 0.055), body)
			PropMeshLibrary._box(t, Vector3(0.26, 0.2, 0.0), Vector3(0.03, 0.022, 0.025), light)
			PropMeshLibrary._box(t, Vector3(0.18, 0.3, -0.035), Vector3(0.015, 0.03, 0.015), dark)
			PropMeshLibrary._box(t, Vector3(0.18, 0.3, 0.035), Vector3(0.015, 0.03, 0.015), dark)
			PropMeshLibrary._box(t, Vector3(-0.23, 0.19, 0.0), Vector3(0.08, 0.04, 0.04), body)
			PropMeshLibrary._box(t, Vector3(-0.33, 0.2, 0.0), Vector3(0.03, 0.035, 0.035), light)
		_:
			return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = t.vertices
	arrays[Mesh.ARRAY_NORMAL] = t.normals
	arrays[Mesh.ARRAY_COLOR] = t.colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## (Colour alpha is the sway weight for the prop shader: animals do not sway.)
static func _plain(color: Color) -> Color:
	return Color(color.r, color.g, color.b, 0.0)
