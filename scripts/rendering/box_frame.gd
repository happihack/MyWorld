class_name BoxFrame
extends Node3D
## The physical box around the world (bible §7.1, §28.2): a wooden plinth with
## a low rim, brass corner posts and top rails, and near-invisible glass panes.
## A display-case shape — the walls are real (the Edge) but never hide the
## world from the viewer; the cut edge of the terrain shows above the rim.
##
## Built in code from the world bounds, so it is rebuilt when the box unfolds.

const WOOD := Color(0.37, 0.25, 0.16)
const WOOD_DARK := Color(0.25, 0.165, 0.105)
const WOOD_LIGHT := Color(0.46, 0.32, 0.20)
const BRASS := Color(0.80, 0.63, 0.32)
## Glass tint; opacity is highest at the top of a pane and fades to nothing at
## the rim. Renderers that blend in linear light (Mobile, Forward+) make a pale
## tint over a dark background far more visible than sRGB blending
## (Compatibility) does, so each gets its own opacity to look alike.
const GLASS_TINT := Color(0.82, 0.92, 1.0)
const GLASS_OPACITY_LINEAR := 0.016
const GLASS_OPACITY_SRGB := 0.07

## Frame thickness as a fraction of the box width (clamped).
const THICKNESS_RATIO := 0.022
const MIN_THICKNESS := 1.0
const MAX_THICKNESS := 3.0
## How far the plinth extends below the terrain base (y = 0).
const PLINTH_DEPTH := 1.4
const MOLDING_HEIGHT := 0.4
## The rim rises this far above the terrain base.
const RIM_HEIGHT := 0.45

var bounds: Rect2i
var box_height := 8.0
var thickness := 1.4

var _wood: MeshInstance3D
var _brass: MeshInstance3D
var _glass: MeshInstance3D


func _init() -> void:
	_wood = _make_instance("Wood", _solid_material(0.75, 0.0))
	_brass = _make_instance("Brass", _solid_material(0.35, 0.65))
	_glass = _make_instance("Glass", _glass_material())
	_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Builds the frame around `world_bounds` (tiles); posts rise to `height`.
func build(world_bounds: Rect2i, height: float) -> void:
	bounds = world_bounds
	box_height = height
	thickness = clampf(world_bounds.size.x * THICKNESS_RATIO, MIN_THICKNESS, MAX_THICKNESS)
	var t := thickness
	var x0 := float(world_bounds.position.x)
	var z0 := float(world_bounds.position.y)
	var x1 := float(world_bounds.end.x)
	var z1 := float(world_bounds.end.y)

	# --- wood: molding at the bottom, then the rim walls around the terrain.
	var wood := _Builder.new()
	var m := t + 0.35
	wood.box(Vector3(x0 - m, -PLINTH_DEPTH - MOLDING_HEIGHT, z0 - m), Vector3(x1 + m, -PLINTH_DEPTH, z1 + m), WOOD_DARK, WOOD_DARK)
	wood.box(Vector3(x0 - t, -PLINTH_DEPTH, z0 - t), Vector3(x1 + t, RIM_HEIGHT, z0), WOOD, WOOD_LIGHT) # north
	wood.box(Vector3(x0 - t, -PLINTH_DEPTH, z1), Vector3(x1 + t, RIM_HEIGHT, z1 + t), WOOD, WOOD_LIGHT) # south
	wood.box(Vector3(x0 - t, -PLINTH_DEPTH, z0), Vector3(x0, RIM_HEIGHT, z1), WOOD, WOOD_LIGHT)         # west
	wood.box(Vector3(x1, -PLINTH_DEPTH, z0), Vector3(x1 + t, RIM_HEIGHT, z1), WOOD, WOOD_LIGHT)         # east
	_wood.mesh = wood.to_mesh()

	# --- brass: a post on each corner and rails joining their tops.
	var brass := _Builder.new()
	var p := t * 0.5 # post half-width, centred on the rim corner
	var top := height
	var rail := t * 0.32
	for corner in [Vector2(x0 - p, z0 - p), Vector2(x1 + p, z0 - p), Vector2(x0 - p, z1 + p), Vector2(x1 + p, z1 + p)]:
		brass.box(Vector3(corner.x - p, RIM_HEIGHT, corner.y - p), Vector3(corner.x + p, top, corner.y + p), BRASS, BRASS)
	brass.box(Vector3(x0, top - rail * 2.0, z0 - p - rail), Vector3(x1, top, z0 - p + rail), BRASS, BRASS)
	brass.box(Vector3(x0, top - rail * 2.0, z1 + p - rail), Vector3(x1, top, z1 + p + rail), BRASS, BRASS)
	brass.box(Vector3(x0 - p - rail, top - rail * 2.0, z0), Vector3(x0 - p + rail, top, z1), BRASS, BRASS)
	brass.box(Vector3(x1 + p - rail, top - rail * 2.0, z0), Vector3(x1 + p + rail, top, z1), BRASS, BRASS)
	_brass.mesh = brass.to_mesh()

	# --- glass: one pane per side, from the rim to the rails.
	var glass := _Builder.new()
	var opacity := glass_opacity(RenderingServer.get_current_rendering_method() == "gl_compatibility")
	var GLASS := Color(GLASS_TINT.r, GLASS_TINT.g, GLASS_TINT.b, opacity)
	var GLASS_BASE := Color(GLASS_TINT.r, GLASS_TINT.g, GLASS_TINT.b, 0.0)
	var g0 := RIM_HEIGHT
	var g1 := top - rail * 2.0
	glass.quad(Vector3(x0, g0, z0 - p), Vector3(x1, g0, z0 - p), Vector3(x1, g1, z0 - p), Vector3(x0, g1, z0 - p), GLASS_BASE, GLASS)
	glass.quad(Vector3(x0, g0, z1 + p), Vector3(x1, g0, z1 + p), Vector3(x1, g1, z1 + p), Vector3(x0, g1, z1 + p), GLASS_BASE, GLASS)
	glass.quad(Vector3(x0 - p, g0, z0), Vector3(x0 - p, g0, z1), Vector3(x0 - p, g1, z1), Vector3(x0 - p, g1, z0), GLASS_BASE, GLASS)
	glass.quad(Vector3(x1 + p, g0, z0), Vector3(x1 + p, g0, z1), Vector3(x1 + p, g1, z1), Vector3(x1 + p, g1, z0), GLASS_BASE, GLASS)
	_glass.mesh = glass.to_mesh()


static func glass_opacity(srgb_blending: bool) -> float:
	return GLASS_OPACITY_SRGB if srgb_blending else GLASS_OPACITY_LINEAR


## Footprint of the whole frame on the XZ plane (bounds grown by the molding).
func outer_rect() -> Rect2:
	var m := thickness + 0.35
	return Rect2(Vector2(bounds.position) - Vector2(m, m), Vector2(bounds.size) + Vector2(m, m) * 2.0)


func bottom_y() -> float:
	return -PLINTH_DEPTH - MOLDING_HEIGHT


func wood_mesh() -> Mesh:
	return _wood.mesh


func brass_mesh() -> Mesh:
	return _brass.mesh


func glass_mesh() -> Mesh:
	return _glass.mesh


func _make_instance(node_name: String, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.material_override = material
	add_child(instance)
	return instance


static func _solid_material(roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = roughness
	material.metallic = metallic
	return material


static func _glass_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Unshaded: a lit glossy pane adds its full sky reflection regardless of
	# alpha and turns milky, hiding the world behind it.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


## Collects flat-shaded triangles with vertex colours.
class _Builder:
	extends RefCounted
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	## Axis-aligned box from `lo` to `hi`; sides shade from bottom to top colour.
	func box(lo: Vector3, hi: Vector3, bottom_color: Color, top_color: Color) -> void:
		var c := [
			Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
			Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
		]
		var center := (lo + hi) * 0.5
		var faces := [[4, 5, 6, 7], [0, 3, 2, 1], [0, 1, 5, 4], [2, 3, 7, 6], [3, 0, 4, 7], [1, 2, 6, 5]]
		for f: Array in faces:
			var cols: Array[Color] = []
			for idx: int in f:
				cols.append(top_color if idx >= 4 else bottom_color)
			_face(c[f[0]], c[f[1]], c[f[2]], c[f[3]], cols, center)

	## Quad a-b-c-d where a, b are the bottom edge and c, d the top edge.
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, bottom_color: Color, top_color: Color) -> void:
		var normal := (c - a).cross(b - a).normalized()
		var points := [a, b, c, a, c, d]
		var cols := [bottom_color, bottom_color, top_color, bottom_color, top_color, top_color]
		for i in points.size():
			vertices.append(points[i])
			normals.append(normal)
			colors.append(cols[i])

	func to_mesh() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh

	func _face(a: Vector3, b: Vector3, c: Vector3, d: Vector3, cols: Array[Color], center: Vector3) -> void:
		# Wind so the front (Godot: clockwise) faces away from the box centre.
		var normal := (c - a).cross(b - a)
		var order := [0, 1, 2, 0, 2, 3]
		if normal.dot((a + b + c + d) * 0.25 - center) < 0.0:
			order = [0, 2, 1, 0, 3, 2]
			normal = -normal
		var points := [a, b, c, d]
		normal = normal.normalized()
		for i: int in order:
			vertices.append(points[i])
			normals.append(normal)
			colors.append(cols[i])
