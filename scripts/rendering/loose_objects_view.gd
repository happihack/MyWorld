class_name LooseObjectsView
extends Node3D
## Draws every loose object (bible §31.7). Objects of the same shape share one
## MultiMesh, so hundreds of rocks cost a handful of draw calls; moving one only
## rewrites its own transform. Views are disposable: all state lives in the
## LooseObjectRegistry.
##
## Uses the prop material, so loose objects get the same light, cloud shadows
## and touch wobble as everything else standing in the world.

class Batch:
	extends RefCounted
	var instance: MultiMeshInstance3D
	var ids: Array[int] = []


var _world: WorldData
var _registry: LooseObjectRegistry
var _library: PropMeshLibrary
var _material: Material
var _batches: Dictionary = {} # shape key -> Batch
var _slots: Dictionary = {} # object id -> [shape key, index in its batch]
var _meshes: Dictionary = {} # shape key -> ArrayMesh
## Objects were added or removed: batches must be rebuilt.
var _stale := false
## A soft dark spot on the ground under the object that is off the ground: it
## shows where the object will come down, also when real shadows are off.
var _blob: MeshInstance3D
var _blob_material: StandardMaterial3D
var _blob_id := 0

const BLOB_ALPHA := 0.30
## The blob is drawn this far above the surface.
const BLOB_LIFT := 0.035


func _init() -> void:
	_blob_material = StandardMaterial3D.new()
	_blob_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blob_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blob_material.albedo_texture = AmbientLife.soft_dot()
	_blob_material.albedo_color = Color(0, 0, 0, BLOB_ALPHA)
	_blob_material.render_priority = 1 # over the water it may lie on
	var quad := PlaneMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_blob = MeshInstance3D.new()
	_blob.name = "DropShadow"
	_blob.mesh = quad
	_blob.material_override = _blob_material
	_blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blob.visible = false
	add_child(_blob)


func setup(library: PropMeshLibrary, material: Material) -> void:
	_library = library
	_material = material


## Shows the objects of `registry`, replacing whatever was shown before.
func show_objects(world: WorldData, registry: LooseObjectRegistry) -> void:
	clear()
	_world = world
	_registry = registry
	if registry == null:
		return
	registry.object_added.connect(_on_membership_changed)
	registry.object_removed.connect(_on_membership_changed)
	registry.object_moved.connect(_on_object_moved)
	rebuild()


func clear() -> void:
	if _registry != null:
		_registry.object_added.disconnect(_on_membership_changed)
		_registry.object_removed.disconnect(_on_membership_changed)
		_registry.object_moved.disconnect(_on_object_moved)
	for batch: Batch in _batches.values():
		batch.instance.queue_free()
	_batches.clear()
	_slots.clear()
	_stale = false
	_blob.visible = false
	_blob_id = 0
	_world = null
	_registry = null


## Applies pending additions and removals. Runs automatically each frame;
## returns true if anything was rebuilt.
func refresh() -> bool:
	if not _stale:
		return false
	rebuild()
	return true


## The ground moved under the objects: stand them on it again.
func reseat() -> void:
	if _registry == null or _stale:
		return
	for id: int in _slots:
		_write(id)


## Rebuilds every batch from the registry.
func rebuild() -> void:
	_stale = false
	_slots.clear()
	if _registry == null or _world == null:
		return
	var groups: Dictionary = {} # shape key -> Array[int]
	var ids: Array = []
	for object in _registry.all_objects():
		ids.append(object.id)
	ids.sort() # same order every time
	for id: int in ids:
		var object := _registry.get_object(id)
		var key := PropMeshLibrary.loose_key(object.kind, object.variant)
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(id)
	for key: int in _batches.keys():
		if not groups.has(key):
			(_batches[key] as Batch).instance.queue_free()
			_batches.erase(key)
	for key: int in groups:
		var batch: Batch = _batches.get(key)
		if batch == null:
			batch = _make_batch(key)
			if batch == null:
				continue
			_batches[key] = batch
		batch.ids.assign(groups[key])
		batch.instance.multimesh.instance_count = batch.ids.size()
		for i in batch.ids.size():
			_slots[batch.ids[i]] = [key, i]
			_write(batch.ids[i])


func _process(_delta: float) -> void:
	refresh()


# --- queries (debug, tests) -------------------------------------------------------------

func object_count() -> int:
	return _slots.size()


func batch_count() -> int:
	return _batches.size()


func is_shown(id: int) -> bool:
	return _slots.has(id)


## Where an object is drawn (identity if it is not shown).
func object_transform(id: int) -> Transform3D:
	var object: LooseObject = _registry.get_object(id) if _registry != null else null
	return transform_for(object, _world) if object != null and _world != null else Transform3D.IDENTITY


static func transform_for(object: LooseObject, world: WorldData) -> Transform3D:
	return Transform3D(
		Basis(Vector3.UP, object.yaw).scaled(Vector3.ONE * object.scale()),
		object.world_position(world))


## Living rock varies a little in brightness from one to the next.
static func tint_for(id: int) -> Color:
	var n := ((id * 2654435761) >> 8) & 0xFFFF
	var t := 0.88 + n / 65535.0 * 0.24
	return Color(t, t, t, 1.0)


# --- internals --------------------------------------------------------------------------

func _write(id: int) -> void:
	var slot: Array = _slots.get(id, [])
	var object := _registry.get_object(id)
	if slot.is_empty() or object == null:
		return
	var batch: Batch = _batches[slot[0]]
	batch.instance.multimesh.set_instance_transform(slot[1], transform_for(object, _world))
	batch.instance.multimesh.set_instance_color(slot[1], tint_for(id))


func _make_batch(key: int) -> Batch:
	var mesh := _mesh_for(key)
	if mesh == null:
		return null
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	var batch := Batch.new()
	batch.instance = MultiMeshInstance3D.new()
	batch.instance.name = "Loose_%d" % key
	batch.instance.multimesh = multimesh
	batch.instance.material_override = _material
	add_child(batch.instance)
	return batch


func _mesh_for(key: int) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var template := _library.loose_template_by_key(key) if _library != null else null
	if template == null:
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = template.vertices
	arrays[Mesh.ARRAY_NORMAL] = template.normals
	arrays[Mesh.ARRAY_COLOR] = template.colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes[key] = mesh
	return mesh


func _on_membership_changed(id: int) -> void:
	_stale = true
	if id == _blob_id and not _registry.has_object(id):
		_blob.visible = false
		_blob_id = 0


func _on_object_moved(id: int) -> void:
	if not _stale:
		_write(id)
	_update_blob(id)


## Is the drop shadow showing, and under which object (0 = none)?
func drop_shadow_id() -> int:
	return _blob_id if _blob.visible else 0


func drop_shadow_position() -> Vector3:
	return _blob.position


func _update_blob(id: int) -> void:
	var object := _registry.get_object(id)
	if object == null:
		return
	var surface := maxf(_world.get_water(object.tile()), 0.0)
	var above := object.height_offset - surface
	if above <= 0.02:
		if id == _blob_id:
			_blob.visible = false
			_blob_id = 0
		return
	_blob_id = id
	var ground := _world.get_height(object.tile()) * _world.height_step
	_blob.position = Vector3(object.position.x, ground + surface + BLOB_LIFT, object.position.y)
	# Higher up: a wider, fainter shadow.
	var spread := object.radius() * (1.5 + above * 0.9)
	_blob.scale = Vector3(spread, 1.0, spread)
	_blob_material.albedo_color.a = BLOB_ALPHA * clampf(1.0 - above * 0.35, 0.35, 1.0)
	_blob.visible = true
