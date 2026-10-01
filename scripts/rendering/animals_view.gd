class_name AnimalsView
extends Node3D
## How the animals are drawn (bible §31.7): one batch per species — every
## deer in one draw call — following the data smoothly. From far away the
## bodies would be specks: then each group is one dot instead.
##
## Views are disposable: everything true about an animal is in AnimalData.

## With a tile smaller than this on screen (viewport units) — the whole box
## in view — bodies give way to one dot for each group.
const TILE_MIN := 26.0
const MARKER_SIZE := 13.0
const MARKER_LIFT := 0.35
## The drawn animal catches up with the real one within about this long:
## quickly when it runs, at its ease otherwise (calm animals are moved every
## few game minutes — see AnimalSystem.CALM_EVERY — and should be seen to
## amble, not to hop).
const FOLLOW_SECONDS := 0.35
const AMBLE_SECONDS := 1.1
const SNAP_DISTANCE := 4.0
## A young one is this share of a grown one's size when it is born.
const YOUNG_SCALE := 0.5
## Lying down asleep: this share of standing height.
const ASLEEP_SCALE := 0.6

var _world: WorldData
var _registry: AnimalRegistry
var _species: SpeciesLibrary
var _clock: GameClock
var _rig: CameraRig
var _material: Material
var _batches: Dictionary = {} # species id -> MultiMeshInstance3D
var _markers: MultiMeshInstance3D
var _shown: Dictionary = {} # animal id -> Vector3 (where it is drawn)
var _yaw: Dictionary = {} # animal id -> float
var _bodies_shown := true
var _marker_count := 0
var _time := 0.0
## How big a tile is on screen right now, in viewport units.
var tile_on_screen := 0.0


func setup(rig: CameraRig, material: Material) -> void:
	_rig = rig
	_material = material
	_build_markers()


func show_animals(world: WorldData, registry: AnimalRegistry, library: SpeciesLibrary, clock: GameClock) -> void:
	clear()
	_world = world
	_registry = registry
	_species = library
	_clock = clock
	if _registry != null:
		_registry.animal_removed.connect(_on_removed)


func clear() -> void:
	if _registry != null and _registry.animal_removed.is_connected(_on_removed):
		_registry.animal_removed.disconnect(_on_removed)
	_registry = null
	for batch: MultiMeshInstance3D in _batches.values():
		batch.queue_free()
	_batches.clear()
	_shown.clear()
	_yaw.clear()
	if _markers != null:
		_markers.multimesh.visible_instance_count = 0
		_markers.visible = false


func _process(delta: float) -> void:
	refresh(delta)


## Brings what is drawn in line with the animals and the camera. Runs every
## frame; call directly (tests) to step it by hand.
func refresh(delta: float) -> void:
	if _registry == null or _world == null or _rig == null or _species == null:
		return
	_time += delta
	var units_per_px := _rig.world_units_per_screen_unit(_rig.pivot())
	var now := _clock.tick if _clock != null else 0
	var quick := 1.0 - exp(-delta / FOLLOW_SECONDS) if delta > 0.0 else 1.0
	var easy := 1.0 - exp(-delta / AMBLE_SECONDS) if delta > 0.0 else 1.0
	var counts := {}
	var groups := {} # group -> [sum of positions, count, color]
	var tallest := 0.0
	for animal in _registry.all_animals():
		var def := _species.get_def(animal.species)
		if def == null:
			continue
		tallest = maxf(tallest, def.height)
		var target := ground_position(animal)
		var hurried := animal.state == AnimalData.State.FLEE or animal.state == AnimalData.State.HUNT
		var catch_up := quick if hurried else easy
		var at: Vector3 = _shown.get(animal.id, target)
		if at.distance_to(target) > SNAP_DISTANCE:
			at = target
		else:
			at = at.lerp(target, catch_up)
		_shown[animal.id] = at
		var yaw: float = lerp_angle(float(_yaw.get(animal.id, -animal.facing)), -animal.facing, minf(catch_up * 2.0, 1.0))
		_yaw[animal.id] = yaw
		var entry: Array = groups.get(animal.group, [Vector3.ZERO, 0, def.color])
		entry[0] += at
		entry[1] += 1
		groups[animal.group] = entry
		var batch := _batch_for(def)
		if batch == null:
			continue
		var index := int(counts.get(animal.species, 0))
		counts[animal.species] = index + 1
		var multimesh := batch.multimesh
		if multimesh.instance_count <= index:
			multimesh.instance_count = maxi(index + 1, multimesh.instance_count * 2)
		# Young ones are small; sleepers lie low; whoever moves bobs a little.
		var grown := clampf(float(animal.age_days(now)) / float(maxi(def.adult_days, 1)), 0.0, 1.0)
		var size := lerpf(YOUNG_SCALE, 1.0, grown)
		var stand := ASLEEP_SCALE if animal.state == AnimalData.State.SLEEP else 1.0
		var bob := 0.0
		if animal.is_moving() and at.distance_to(target) > 0.02:
			bob = absf(sin(_time * 9.0 + float(animal.id))) * def.height * 0.08
		multimesh.set_instance_transform(index, Transform3D(
			Basis(Vector3.UP, yaw).scaled(Vector3(size, size * stand, size)), at + Vector3(0.0, bob, 0.0)))
	tile_on_screen = 1.0 / maxf(units_per_px, 0.000001)
	_bodies_shown = tallest <= 0.0 or tile_on_screen >= TILE_MIN
	for id: StringName in _batches:
		var batch: MultiMeshInstance3D = _batches[id]
		batch.multimesh.visible_instance_count = int(counts.get(id, 0)) if _bodies_shown else 0
		batch.visible = _bodies_shown and int(counts.get(id, 0)) > 0
	# From far away: one dot for each group, where its animals are.
	_marker_count = 0
	if not _bodies_shown:
		var multimesh := _markers.multimesh
		if multimesh.instance_count < groups.size():
			multimesh.instance_count = groups.size() * 2
		var scale := MARKER_SIZE * units_per_px
		for group: int in groups:
			var entry: Array = groups[group]
			var middle: Vector3 = (entry[0] as Vector3) / float(entry[1])
			multimesh.set_instance_transform(_marker_count, Transform3D(
				Basis.from_scale(Vector3.ONE * scale * (1.0 + 0.12 * minf(float(entry[1]), 6.0))), middle + Vector3(0.0, MARKER_LIFT, 0.0)))
			multimesh.set_instance_color(_marker_count, entry[2])
			_marker_count += 1
		multimesh.visible_instance_count = _marker_count
	else:
		_markers.multimesh.visible_instance_count = 0
	_markers.visible = _marker_count > 0


## Where an animal stands in the world (the ground under it).
func ground_position(animal: AnimalData) -> Vector3:
	return Vector3(animal.position.x, _world.get_height(animal.tile()) * _world.height_step, animal.position.y)


## Where it is drawn right now.
func shown_position(animal_id: int) -> Vector3:
	return _shown.get(animal_id, Vector3.INF)


## The body a finger can hit (Vector2(height, radius), see Picker), or null
## for what is not an animal.
func pick_shape(animal_id: int) -> Variant:
	var animal := _registry.get_animal(animal_id) if _registry != null else null
	var def := _species.get_def(animal.species) if animal != null and _species != null else null
	if def == null:
		return null
	return Vector2(def.height, maxf(def.radius, 0.22))


func bodies_shown() -> bool:
	return _bodies_shown


## How many animals of a species are drawn as bodies.
func shown_count(species_id: StringName) -> int:
	var batch: MultiMeshInstance3D = _batches.get(species_id)
	return batch.multimesh.visible_instance_count if batch != null else 0


func marker_count() -> int:
	return _marker_count


func batch_count() -> int:
	return _batches.size()


func _batch_for(def: SpeciesDef) -> MultiMeshInstance3D:
	if _batches.has(def.id):
		return _batches[def.id]
	var mesh := AnimalMeshLibrary.mesh_for(def)
	if mesh == null:
		_batches[def.id] = null
		return null
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = 16
	multimesh.visible_instance_count = 0
	var batch := MultiMeshInstance3D.new()
	batch.name = "Animals_%s" % def.id
	batch.multimesh = multimesh
	batch.material_override = _material
	# Animals are spread over the whole world: never cull the batch.
	batch.custom_aabb = AABB(Vector3(-4096, -64, -4096), Vector3(8192, 256, 8192))
	add_child(batch)
	_batches[def.id] = batch
	return batch


func _build_markers() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.albedo_texture = PeopleView.marker_texture()
	material.render_priority = 1
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = 16
	multimesh.visible_instance_count = 0
	_markers = MultiMeshInstance3D.new()
	_markers.name = "GroupMarkers"
	_markers.multimesh = multimesh
	_markers.material_override = material
	_markers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_markers.custom_aabb = AABB(Vector3(-4096, -64, -4096), Vector3(8192, 256, 8192))
	_markers.visible = false
	add_child(_markers)


func _on_removed(id: int) -> void:
	_shown.erase(id)
	_yaw.erase(id)
