class_name PickHighlight
extends Node3D
## Debug visual for picking (bible §23.3, track T1): an outline on the picked
## tile and a ring under the picked entity. Drawn on top of everything so it is
## never hidden by terrain or props.

const TILE_COLOR := Color(1.0, 0.92, 0.25)
const ENTITY_COLOR := Color(0.25, 1.0, 0.85)
const WATER_COLOR := Color(0.45, 0.80, 1.0)
const LINE_WIDTH := 0.06
const RING_SEGMENTS := 24

var _tile: MeshInstance3D
var _ring: MeshInstance3D


func _init() -> void:
	_tile = _make("TileOutline", _outline_mesh())
	_ring = _make("EntityRing", _ring_mesh())
	clear()


## Shows the outline on a tile whose surface is at height `surface_y`.
func show_tile(tile: Vector2i, surface_y: float, is_water: bool = false) -> void:
	_tile.position = Vector3(tile.x, surface_y + 0.02, tile.y)
	_set_color(_tile, WATER_COLOR if is_water else TILE_COLOR)
	_tile.visible = true


## Shows a ring of `radius` on the ground at `base`.
func show_entity(base: Vector3, radius: float) -> void:
	_ring.position = base + Vector3(0.0, 0.03, 0.0)
	_ring.scale = Vector3(radius, 1.0, radius)
	_ring.visible = true


func clear() -> void:
	_tile.visible = false
	_ring.visible = false


func tile_visible() -> bool:
	return _tile.visible


func entity_visible() -> bool:
	return _ring.visible


func tile_position() -> Vector3:
	return _tile.position


func entity_position() -> Vector3:
	return _ring.position


func _make(node_name: String, mesh: Mesh) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 10
	material.albedo_color = ENTITY_COLOR if node_name == "EntityRing" else TILE_COLOR
	instance.material_override = material
	add_child(instance)
	return instance


static func _set_color(instance: MeshInstance3D, color: Color) -> void:
	(instance.material_override as StandardMaterial3D).albedo_color = color


## A unit-tile frame (0..1 on X and Z) made of four thin strips.
static func _outline_mesh() -> ArrayMesh:
	var w := LINE_WIDTH
	var quads := [
		[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, w), Vector3(0, 0, w)],
		[Vector3(0, 0, 1 - w), Vector3(1, 0, 1 - w), Vector3(1, 0, 1), Vector3(0, 0, 1)],
		[Vector3(0, 0, 0), Vector3(w, 0, 0), Vector3(w, 0, 1), Vector3(0, 0, 1)],
		[Vector3(1 - w, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(1 - w, 0, 1)],
	]
	return _mesh_from_quads(quads)


## A flat ring with outer radius 1 (scaled per entity).
static func _ring_mesh() -> ArrayMesh:
	var inner := 0.82
	var quads: Array = []
	for i in RING_SEGMENTS:
		var a0 := TAU * i / RING_SEGMENTS
		var a1 := TAU * (i + 1) / RING_SEGMENTS
		quads.append([
			Vector3(cos(a0) * inner, 0, sin(a0) * inner), Vector3(cos(a0), 0, sin(a0)),
			Vector3(cos(a1), 0, sin(a1)), Vector3(cos(a1) * inner, 0, sin(a1) * inner),
		])
	return _mesh_from_quads(quads)


static func _mesh_from_quads(quads: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	for q: Array in quads:
		for i: int in [0, 1, 2, 0, 2, 3]:
			vertices.append(q[i])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
