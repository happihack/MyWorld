class_name BoxFrame
extends Node3D
## The physical box around the world (bible §7.1, §28.2; the art decisions of
## 2026-10-15, docs/art_assets.md §5: an attic artefact). A plank box, worn
## along the top where hands have been, scuffed on the rim, with wooden
## corner posts and near-invisible glass panes between them; a paper label
## taped to the front with the settlement's name on it. The walls are real
## (the Edge) but never hide the world from the viewer; the cut edge of the
## terrain shows above the rim.
##
## Built in code from the world bounds, so it is rebuilt when the box unfolds.

const WOOD := Palette.BOX_WOOD
const WOOD_DARK := Palette.BARK_DEEP
const WOOD_LIGHT := Palette.BARK_LIGHT
## The second plank, a shade off the first, so the planks read as planks.
const WOOD_OTHER := Color(0.34, 0.23, 0.14)
## Worn wood: the top edge, the scuffs.
const WORN := Color(0.58, 0.44, 0.29)
const PAPER := Color(0.945, 0.902, 0.788) # UITheme.PAPER
const PAPER_EDGE := Color(0.86, 0.80, 0.66)
const TAPE := Color(0.97, 0.89, 0.60)
const INK := Color(0.165, 0.114, 0.078) # UITheme.INK
## The lid's wood matches the painted lid of the main menu (UITheme.LID).
const LID := Color(0.369, 0.263, 0.169)
const LID_EDGE := Color(0.247, 0.169, 0.110)
## Glass tint; opacity is highest at the top of a pane and fades to nothing at
## the rim. Renderers that blend in linear light (Mobile, Forward+) make a pale
## tint over a dark background far more visible than sRGB blending
## (Compatibility) does, so each gets its own opacity to look alike.
const GLASS_TINT := Palette.GLASS
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
## The worn edge along the top of the walls, and how far a scuff stands proud.
const WORN_EDGE := 0.12
const SCUFF := 0.01
const PLANKS := 3

const LABEL_FONT := preload("res://assets/fonts/CaveatBrush-Regular.ttf")

var bounds: Rect2i
var box_height := 8.0
var thickness := 1.4

var _wood: MeshInstance3D
var _posts: MeshInstance3D
var _glass: MeshInstance3D
## The paper: the label on the front and its tape, and the lid's.
var _paper: MeshInstance3D
var _label: Label3D
## The lid (VS.4): only seen at the first opening, swinging up on its far
## hinge (set_lid_open); hidden otherwise.
var _lid: Node3D
var _lid_mesh: MeshInstance3D
var _lid_paper: MeshInstance3D
var _lid_label: Label3D
## How far the lid swings when fully open (degrees).
const LID_OPEN_DEGREES := 112.0
const LID_THICKNESS := 0.7


func _init() -> void:
	_wood = _make_instance("Wood", _solid_material(0.85, 0.0))
	_posts = _make_instance("Posts", _solid_material(0.85, 0.0))
	_glass = _make_instance("Glass", _glass_material())
	_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_paper = _make_instance("Paper", _solid_material(1.0, 0.0))
	_paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_label = _make_label("Label")
	add_child(_label)
	_lid = Node3D.new()
	_lid.name = "Lid"
	add_child(_lid)
	_lid_mesh = MeshInstance3D.new()
	_lid_mesh.name = "LidMesh"
	_lid_mesh.material_override = _solid_material(0.85, 0.0)
	_lid.add_child(_lid_mesh)
	_lid_paper = MeshInstance3D.new()
	_lid_paper.name = "LidPaper"
	_lid_paper.material_override = _solid_material(1.0, 0.0)
	_lid_paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lid.add_child(_lid_paper)
	_lid_label = _make_label("LidLabel")
	_lid_label.text = ProjectSettings.get_setting("application/config/name", "World in a Box")
	_lid.add_child(_lid_label)
	_lid.visible = false


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

	# --- wood: the plinth at the bottom, then the walls around the terrain as
	# planks, a worn edge along the top, scuffs on the rim.
	var wood := _Builder.new()
	var m := t + 0.35
	wood.box(Vector3(x0 - m, -PLINTH_DEPTH - MOLDING_HEIGHT, z0 - m), Vector3(x1 + m, -PLINTH_DEPTH, z1 + m), WOOD_DARK, WOOD_DARK)
	var wall_top := RIM_HEIGHT - WORN_EDGE
	for i in PLANKS:
		var y0 := lerpf(-PLINTH_DEPTH, wall_top, float(i) / PLANKS)
		var y1 := lerpf(-PLINTH_DEPTH, wall_top, float(i + 1) / PLANKS)
		var shade := WOOD if i % 2 == 0 else WOOD_OTHER
		wood.box(Vector3(x0 - t, y0, z0 - t), Vector3(x1 + t, y1, z0), shade, shade.lightened(0.06)) # north
		wood.box(Vector3(x0 - t, y0, z1), Vector3(x1 + t, y1, z1 + t), shade, shade.lightened(0.06)) # south
		wood.box(Vector3(x0 - t, y0, z0), Vector3(x0, y1, z1), shade, shade.lightened(0.06))         # west
		wood.box(Vector3(x1, y0, z0), Vector3(x1 + t, y1, z1), shade, shade.lightened(0.06))         # east
	var edge_top := RIM_HEIGHT - SCUFF
	wood.box(Vector3(x0 - t, wall_top, z0 - t), Vector3(x1 + t, edge_top, z0), WOOD_LIGHT, WORN)
	wood.box(Vector3(x0 - t, wall_top, z1), Vector3(x1 + t, edge_top, z1 + t), WOOD_LIGHT, WORN)
	wood.box(Vector3(x0 - t, wall_top, z0), Vector3(x0, edge_top, z1), WOOD_LIGHT, WORN)
	wood.box(Vector3(x1, wall_top, z0), Vector3(x1 + t, edge_top, z1), WOOD_LIGHT, WORN)
	# Scuffs: pale patches worn into the rim's top, settled by their place.
	var width := x1 - x0
	for i in 5:
		var along := x0 + width * (0.1 + 0.19 * i) + (i % 3) * 0.9
		var size := t * (0.7 + 0.4 * (i % 2))
		var patch := WORN.lightened(0.05 + 0.04 * (i % 3))
		if i % 2 == 0:
			wood.box(Vector3(along - size, edge_top - 0.02, z1 + t * 0.3), Vector3(along + size, RIM_HEIGHT, z1 + t * 0.7), patch, patch)
		else:
			wood.box(Vector3(along - size, edge_top - 0.02, z0 - t * 0.7), Vector3(along + size, RIM_HEIGHT, z0 - t * 0.3), patch, patch)
	for i in 2:
		var along := z0 + (z1 - z0) * (0.3 + 0.4 * i)
		var size := t * 0.9
		var side_x := x0 - t * 0.5 if i % 2 == 0 else x1 + t * 0.5
		wood.box(Vector3(side_x - t * 0.2, edge_top - 0.02, along - size), Vector3(side_x + t * 0.2, RIM_HEIGHT, along + size), WORN.lightened(0.06), WORN.lightened(0.06))
	_wood.mesh = wood.to_mesh()

	# --- posts: a wooden post on each corner and thin rails joining their tops.
	var posts := _Builder.new()
	var p := t * 0.5 # post half-width, centred on the rim corner
	var top := height
	var rail := t * 0.32
	for corner in [Vector2(x0 - p, z0 - p), Vector2(x1 + p, z0 - p), Vector2(x0 - p, z1 + p), Vector2(x1 + p, z1 + p)]:
		posts.box(Vector3(corner.x - p, RIM_HEIGHT, corner.y - p), Vector3(corner.x + p, top, corner.y + p), WOOD_DARK, WOOD)
	posts.box(Vector3(x0, top - rail * 2.0, z0 - p - rail), Vector3(x1, top, z0 - p + rail), WOOD_DARK, WOOD)
	posts.box(Vector3(x0, top - rail * 2.0, z1 + p - rail), Vector3(x1, top, z1 + p + rail), WOOD_DARK, WOOD)
	posts.box(Vector3(x0 - p - rail, top - rail * 2.0, z0), Vector3(x0 - p + rail, top, z1), WOOD_DARK, WOOD)
	posts.box(Vector3(x1 + p - rail, top - rail * 2.0, z0), Vector3(x1 + p + rail, top, z1), WOOD_DARK, WOOD)
	_posts.mesh = posts.to_mesh()

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

	# --- the label: a paper taped to the front wall, the name written on it.
	var paper := _Builder.new()
	# (As tall as the wall allows, wide to match; the name in the UI's hand.)
	var label_h := (wall_top + PLINTH_DEPTH) * 0.82
	var label_w := label_h * 3.4
	var label_c := Vector3((x0 + x1) * 0.5, (-PLINTH_DEPTH + wall_top) * 0.5, z1 + t)
	_paper_label(paper, label_c, Vector3.RIGHT, Vector3.UP, Vector3.BACK, label_w, label_h, 2.5)
	_paper.mesh = paper.to_mesh()
	_label.position = label_c + Vector3(0.0, -label_h * 0.04, 0.07)
	_label.rotation = Vector3(0.0, 0.0, deg_to_rad(2.5))
	_label.pixel_size = label_h * 0.62 / 64.0
	_label.width = label_w * 0.9 / _label.pixel_size

	# --- the lid: planks over the whole box, a wooden cleat for a handle at
	# the front, hinged along the far (north) rail; a label taped to its top.
	var reach := p + rail
	var depth := (z1 + reach) - (z0 - reach)
	var lid := _Builder.new()
	var lid_planks := 4
	for i in lid_planks:
		var d0 := depth * float(i) / lid_planks
		var d1 := depth * float(i + 1) / lid_planks
		var shade := LID if i % 2 == 0 else LID.lerp(LID_EDGE, 0.35)
		lid.box(Vector3(x0 - reach, 0.0, d0), Vector3(x1 + reach, LID_THICKNESS, d1), LID_EDGE, shade)
	var middle := (x0 + x1) * 0.5
	lid.box(Vector3(middle - t * 1.5, LID_THICKNESS, depth - t * 1.2), Vector3(middle + t * 1.5, LID_THICKNESS + 0.3, depth - t * 0.4),
		WOOD_DARK, WOOD)
	_lid_mesh.mesh = lid.to_mesh()
	var lid_paper := _Builder.new()
	var lid_label_w := maxf(width * 0.22, 4.0)
	var lid_label_h := lid_label_w * 0.4
	var lid_label_c := Vector3(middle, LID_THICKNESS, depth * 0.5)
	_paper_label(lid_paper, lid_label_c, Vector3.RIGHT, Vector3.BACK, Vector3.UP, lid_label_w, lid_label_h, -4.0)
	_lid_paper.mesh = lid_paper.to_mesh()
	_lid_label.position = lid_label_c + Vector3(0.0, 0.06, 0.0)
	_lid_label.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	_lid_label.rotate_object_local(Vector3.FORWARD, deg_to_rad(-4.0))
	_lid_label.pixel_size = lid_label_h * 0.45 / 64.0
	_lid_label.width = lid_label_w / _lid_label.pixel_size * 0.9
	_lid.position = Vector3(0.0, top, z0 - reach)
	_lid.rotation.x = 0.0 # (hidden until an opening shows it)


## A sheet of paper with two strips of tape over its top corners, on the plane
## spanned by `across` and `up`, standing `out` of a surface, turned `tilt`
## degrees in that plane.
static func _paper_label(into: _Builder, center: Vector3, across: Vector3, up: Vector3, out: Vector3,
		w: float, h: float, tilt: float) -> void:
	var turn := deg_to_rad(tilt)
	var a := across.rotated(out, turn)
	var u := up.rotated(out, turn)
	var sheet := center + out * 0.03
	_sheet(into, sheet, a, u, out, w, h, PAPER_EDGE, PAPER)
	for side: float in [-1.0, 1.0]:
		var ta := a.rotated(out, side * deg_to_rad(40.0))
		var tu := u.rotated(out, side * deg_to_rad(40.0))
		var at := sheet + a * side * w * 0.42 + u * h * 0.46 + out * 0.02
		_sheet(into, at, ta, tu, out, h * 0.55, h * 0.2, TAPE, TAPE)


## A rectangle `w` by `h` about `center`, facing `out`.
static func _sheet(into: _Builder, center: Vector3, a: Vector3, u: Vector3, out: Vector3, w: float, h: float,
		bottom_color: Color, top_color: Color) -> void:
	var p0 := center - a * w * 0.5 - u * h * 0.5
	var p1 := center + a * w * 0.5 - u * h * 0.5
	var p2 := center + a * w * 0.5 + u * h * 0.5
	var p3 := center - a * w * 0.5 + u * h * 0.5
	# (quad's front is (c - a) x (b - a): turn it to face out.)
	if (p2 - p0).cross(p1 - p0).dot(out) >= 0.0:
		into.quad(p0, p1, p2, p3, bottom_color, top_color)
	else:
		into.quad(p1, p0, p3, p2, bottom_color, top_color)


## What the label on the front says (the settlement's name).
func set_label(text: String) -> void:
	_label.text = text


## The lid shown, open by `amount` (0 closed … 1 swung up past upright,
## away from the camera's usual side); `amount` < 0 hides it.
func set_lid_open(amount: float) -> void:
	_lid.visible = amount >= 0.0
	_lid.rotation.x = -deg_to_rad(LID_OPEN_DEGREES * clampf(amount, 0.0, 1.0))


func lid() -> Node3D:
	return _lid


static func glass_opacity(srgb_blending: bool) -> float:
	return GLASS_OPACITY_SRGB if srgb_blending else GLASS_OPACITY_LINEAR


static func _make_label(node_name: String) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.font = LABEL_FONT
	label.font_size = 64
	label.modulate = INK
	label.outline_size = 0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.shaded = false
	label.double_sided = false
	label.no_depth_test = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return label


## Footprint of the whole frame on the XZ plane (bounds grown by the molding).
func outer_rect() -> Rect2:
	var m := thickness + 0.35
	return Rect2(Vector2(bounds.position) - Vector2(m, m), Vector2(bounds.size) + Vector2(m, m) * 2.0)


func bottom_y() -> float:
	return -PLINTH_DEPTH - MOLDING_HEIGHT


func wood_mesh() -> Mesh:
	return _wood.mesh


func posts_mesh() -> Mesh:
	return _posts.mesh


func paper_mesh() -> Mesh:
	return _paper.mesh


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
