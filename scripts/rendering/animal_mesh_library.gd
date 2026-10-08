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
	return shape in [&"deer", &"rabbit", &"fox", &"bear", &"wolf", &"lion", &"boar"]


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
		&"bear":
			# Big and heavy on four thick legs, a hump at the shoulders, a broad
			# head held low, small round ears.
			for leg: Vector2 in [Vector2(-0.22, -0.11), Vector2(-0.22, 0.11), Vector2(0.2, -0.11), Vector2(0.2, 0.11)]:
				PropMeshLibrary._box(t, Vector3(leg.x, 0.11, leg.y), Vector3(0.06, 0.11, 0.06), dark)
			PropMeshLibrary._box(t, Vector3(0.0, 0.33, 0.0), Vector3(0.32, 0.14, 0.16), body)
			PropMeshLibrary._box(t, Vector3(0.12, 0.47, 0.0), Vector3(0.12, 0.05, 0.13), body) # the hump
			PropMeshLibrary._box(t, Vector3(0.38, 0.33, 0.0), Vector3(0.1, 0.09, 0.1), body)
			PropMeshLibrary._box(t, Vector3(0.49, 0.3, 0.0), Vector3(0.05, 0.045, 0.06), light) # the muzzle
			PropMeshLibrary._box(t, Vector3(0.34, 0.44, -0.07), Vector3(0.025, 0.025, 0.025), dark)
			PropMeshLibrary._box(t, Vector3(0.34, 0.44, 0.07), Vector3(0.025, 0.025, 0.025), dark)
		&"wolf":
			# Long legs, a deep chest, a long muzzle, ears up, the tail held low.
			for leg: Vector2 in [Vector2(-0.15, -0.055), Vector2(-0.15, 0.055), Vector2(0.15, -0.055), Vector2(0.15, 0.055)]:
				PropMeshLibrary._box(t, Vector3(leg.x, 0.1, leg.y), Vector3(0.025, 0.1, 0.025), dark)
			PropMeshLibrary._box(t, Vector3(0.0, 0.27, 0.0), Vector3(0.2, 0.075, 0.08), body)
			PropMeshLibrary._box(t, Vector3(0.12, 0.25, 0.0), Vector3(0.08, 0.09, 0.085), light) # the chest
			PropMeshLibrary._box(t, Vector3(0.25, 0.33, 0.0), Vector3(0.07, 0.06, 0.065), body)
			PropMeshLibrary._box(t, Vector3(0.34, 0.31, 0.0), Vector3(0.05, 0.03, 0.035), dark)
			PropMeshLibrary._box(t, Vector3(0.23, 0.42, -0.04), Vector3(0.016, 0.035, 0.016), dark)
			PropMeshLibrary._box(t, Vector3(0.23, 0.42, 0.04), Vector3(0.016, 0.035, 0.016), dark)
			PropMeshLibrary._box(t, Vector3(-0.27, 0.22, 0.0), Vector3(0.1, 0.035, 0.035), body)
		&"lion":
			# A mountain lion: long, low and lithe, a small round head, a long
			# heavy tail curving down and up at the end.
			for leg: Vector2 in [Vector2(-0.16, -0.055), Vector2(-0.16, 0.055), Vector2(0.15, -0.055), Vector2(0.15, 0.055)]:
				PropMeshLibrary._box(t, Vector3(leg.x, 0.085, leg.y), Vector3(0.028, 0.085, 0.028), dark)
			PropMeshLibrary._box(t, Vector3(0.0, 0.22, 0.0), Vector3(0.22, 0.07, 0.08), body)
			PropMeshLibrary._box(t, Vector3(0.27, 0.26, 0.0), Vector3(0.065, 0.06, 0.065), body)
			PropMeshLibrary._box(t, Vector3(0.33, 0.24, 0.0), Vector3(0.03, 0.03, 0.04), light)
			PropMeshLibrary._box(t, Vector3(0.25, 0.33, -0.04), Vector3(0.015, 0.02, 0.015), dark)
			PropMeshLibrary._box(t, Vector3(0.25, 0.33, 0.04), Vector3(0.015, 0.02, 0.015), dark)
			PropMeshLibrary._box(t, Vector3(-0.32, 0.15, 0.0), Vector3(0.12, 0.025, 0.025), body)
			PropMeshLibrary._box(t, Vector3(-0.45, 0.19, 0.0), Vector3(0.03, 0.045, 0.028), dark)
		&"boar":
			# Low and barrel-bodied on short legs, a long snout, white tusks, a
			# bristly ridge along the back.
			for leg: Vector2 in [Vector2(-0.13, -0.07), Vector2(-0.13, 0.07), Vector2(0.13, -0.07), Vector2(0.13, 0.07)]:
				PropMeshLibrary._box(t, Vector3(leg.x, 0.05, leg.y), Vector3(0.03, 0.05, 0.03), dark)
			PropMeshLibrary._box(t, Vector3(0.0, 0.19, 0.0), Vector3(0.2, 0.1, 0.11), body)
			PropMeshLibrary._box(t, Vector3(0.0, 0.3, 0.0), Vector3(0.16, 0.02, 0.025), dark) # the bristles
			PropMeshLibrary._box(t, Vector3(0.26, 0.17, 0.0), Vector3(0.08, 0.07, 0.08), body)
			PropMeshLibrary._box(t, Vector3(0.36, 0.14, 0.0), Vector3(0.04, 0.035, 0.045), dark)
			PropMeshLibrary._box(t, Vector3(0.33, 0.12, -0.05), Vector3(0.03, 0.012, 0.01), _plain(Color(0.95, 0.93, 0.85)))
			PropMeshLibrary._box(t, Vector3(0.33, 0.12, 0.05), Vector3(0.03, 0.012, 0.01), _plain(Color(0.95, 0.93, 0.85)))
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
