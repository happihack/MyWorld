class_name PeopleView
extends Node3D
## Draws the inhabitants (bible §31.7). Up close, everyone in sight gets a
## pooled PersonView that follows them smoothly; from far away, where a body
## would be a few pixels, people become small markers that keep the same size
## on screen — so they can always be found. In between, both are shown and the
## markers fade in.
##
## Views only read the PersonRegistry; they never change it.

const VIEW_SCENE := preload("res://scenes/people/person_view.tscn")
const PERSON_SHADER := preload("res://assets/shaders/person.gdshader")

## How tall a grown person is on screen (viewport units) decides what is drawn:
## bodies down to BODY_MIN, markers fading in from MARKER_START to MARKER_FULL.
## (The viewport is 1080 units wide: at the home view a person is about 70 tall.)
const BODY_MIN := 11.0
const MARKER_START := 36.0
const MARKER_FULL := 22.0
## Diameter of a marker on screen (viewport units).
const MARKER_SIZE := 18.0
## People this far outside the screen (viewport units) still have their view,
## so that nobody pops in at the edge.
const VIEW_MARGIN := 140.0
const MAX_VIEWS := 96
## A view is checked against its person's age and work every this many frames
## (a power of two; people do not change their clothes from one frame to the next).
const DRESS_CHECK_FRAMES := 16
## Only people simulated in full are drawn as bodies.
const MIN_TIER_FOR_VIEW := 3
const REDUCED_MOTION := 0.35

var reduced_motion := false:
	set(value):
		reduced_motion = value
		_body_material.set_shader_parameter(&"motion", REDUCED_MOTION if value else 1.0)

var _world: WorldData
var _people: PersonRegistry
var _clock: GameClock
var _occupations: OccupationLibrary
var _rig: CameraRig
var _pool: EntityViewPool
var _body_material: ShaderMaterial
var _accessory_material: Material
var _shadow_material: StandardMaterial3D
var _markers: MultiMeshInstance3D
var _marker_material: StandardMaterial3D
var _ids: Array[int] = []
var _marker_alpha := 0.0
var _marker_transforms: Array[Transform3D] = [] # as written to the MultiMesh (for queries)
var _bodies_shown := true
var _refreshes := 0


func _init() -> void:
	_body_material = ShaderMaterial.new()
	_body_material.shader = PERSON_SHADER
	_shadow_material = StandardMaterial3D.new()
	_shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_material.albedo_texture = AmbientLife.soft_dot()
	_shadow_material.albedo_color = Color(0, 0, 0, PersonView.SHADOW_ALPHA)
	_shadow_material.render_priority = 1 # over shallow water
	_pool = EntityViewPool.new(VIEW_SCENE, MAX_VIEWS, _prepare_view)
	_pool.name = "Views"
	add_child(_pool)
	_build_markers()


## `rig` is the camera people are seen through; `accessory_material` draws what
## they carry (the prop material: same light and cloud shadows as the world).
func setup(rig: CameraRig, accessory_material: Material) -> void:
	_rig = rig
	_accessory_material = accessory_material


## Pushes the cloud-shadow look into the body material (see WorldView.apply_palette).
func body_material() -> ShaderMaterial:
	return _body_material


## Shows the people of `registry`, replacing whoever was shown before.
func show_people(world: WorldData, registry: PersonRegistry, clock: GameClock, occupations: OccupationLibrary) -> void:
	clear()
	_world = world
	_people = registry
	_clock = clock
	_occupations = occupations
	if registry == null:
		return
	registry.person_added.connect(_on_person_added)
	registry.person_removed.connect(_on_person_removed)
	for person in registry.all_people():
		_ids.append(person.id)
	refresh(0.0)


func clear() -> void:
	if _people != null:
		_people.person_added.disconnect(_on_person_added)
		_people.person_removed.disconnect(_on_person_removed)
	_pool.release_all()
	for view in _pool.get_children():
		(view as PersonView).unbind()
	_ids.clear()
	_markers.multimesh.visible_instance_count = 0
	_markers.visible = false
	_marker_transforms.clear()
	_world = null
	_people = null
	_clock = null


func _process(delta: float) -> void:
	refresh(delta)


## Brings what is drawn in line with the registry and the camera. Runs every
## frame; call directly (tests) to step it by hand.
func refresh(delta: float) -> void:
	if _people == null or _world == null or _rig == null:
		return
	var units_per_px := _rig.world_units_per_screen_unit(_rig.pivot())
	var adult_px := PersonMeshLibrary.ADULT_HEIGHT / maxf(units_per_px, 0.000001)
	_bodies_shown = adult_px >= BODY_MIN
	_marker_alpha = 1.0 - smoothstep(MARKER_FULL, MARKER_START, adult_px)
	# Who is in sight: the camera's view pyramid, a margin wider (worked out
	# once per frame, so the test per person is a few multiplications).
	var size := _rig.view_size()
	var to_camera := _rig.camera_transform().affine_inverse()
	var slope_y := tan(deg_to_rad(_rig.config.fov_degrees) * 0.5)
	var slope_x := slope_y * size.x / maxf(size.y, 1.0) * (1.0 + VIEW_MARGIN * 2.0 / maxf(size.x, 1.0))
	slope_y *= 1.0 + VIEW_MARGIN * 2.0 / maxf(size.y, 1.0)
	_refreshes += 1
	var year := Config.time.ticks_per_year()
	var now := _clock.tick if _clock != null else 0
	var marked := 0
	var multimesh := _markers.multimesh
	if _marker_alpha > 0.0 and multimesh.instance_count < _ids.size():
		multimesh.instance_count = maxi(_ids.size(), multimesh.instance_count * 2)
	var marker_scale := MARKER_SIZE * units_per_px
	_marker_transforms.clear()
	for id in _ids:
		var person := _people.get_person(id)
		if person == null:
			continue
		var feet := ground_position(person)
		# Someone indoors (asleep at home) is there, but not to be seen.
		var indoors := person.has_flag(PersonData.FLAG_INDOORS)
		var wants_view := _bodies_shown and person.sim_tier >= MIN_TIER_FOR_VIEW and not indoors
		if wants_view:
			var seen := to_camera * feet # the camera looks along -Z
			wants_view = seen.z < 0.0 and absf(seen.x) <= -seen.z * slope_x and absf(seen.y) <= -seen.z * slope_y
		var view := _pool.view_of(id) as PersonView
		if wants_view:
			if view == null:
				view = _pool.acquire(id) as PersonView
				if view != null:
					view.bind(person, now, year, Config.people, _occupations, feet)
			elif ((_refreshes + id) & (DRESS_CHECK_FRAMES - 1)) == 0 					and (view.age_years != person.age_years(now, year) or view.accessory != _accessory_of(person)):
				view.dress(person, now, year, Config.people, _occupations)
			if view != null:
				view.advance(delta, feet, person.facing)
				view.set_pose(person.pose)
		elif view != null:
			view.unbind()
			_pool.release(id)
		if _marker_alpha > 0.0 and not indoors:
			# The marker floats above the head — of the view, if there is one, so
			# that marker and body move as one.
			var at := view.position if view != null and wants_view else feet
			var lift := PersonMeshLibrary.ADULT_HEIGHT + marker_scale * 0.6
			var placed := Transform3D(Basis.from_scale(Vector3.ONE * marker_scale), at + Vector3(0, lift, 0))
			_marker_transforms.append(placed)
			multimesh.set_instance_transform(marked, placed)
			multimesh.set_instance_color(marked, PersonMeshLibrary.cloth(int(person.appearance.get("cloth", 0))))
			marked += 1
	multimesh.visible_instance_count = marked
	_markers.visible = marked > 0
	_marker_material.albedo_color.a = _marker_alpha


## Where a person's feet are in the world.
func ground_position(person: PersonData) -> Vector3:
	var at := person.world2d()
	return Vector3(at.x, _world.get_height(person.position) * _world.height_step, at.y)


# --- queries (debug, tests) ---------------------------------------------------------------

## People drawn as bodies right now.
func shown_count() -> int:
	return _pool.active_count()


## People drawn as markers right now.
func marker_count() -> int:
	return _markers.multimesh.visible_instance_count if _markers.visible and _marker_alpha > 0.0 else 0


## 0 = no markers … 1 = markers fully shown.
func marker_alpha() -> float:
	return _marker_alpha


func bodies_shown() -> bool:
	return _bodies_shown


func view_of(id: int) -> PersonView:
	return _pool.view_of(id) as PersonView


func pool() -> EntityViewPool:
	return _pool


## World position of the marker of the `index`-th marked person.
func marker_transform(index: int) -> Transform3D:
	return _marker_transforms[index] if index >= 0 and index < _marker_transforms.size() else Transform3D.IDENTITY


func debug_text() -> String:
	return "%d bodies (%d views made)  %d markers %.0f%%" % [shown_count(), _pool.created_count(), marker_count(), _marker_alpha * 100.0]


# --- internals ----------------------------------------------------------------------------

func _prepare_view(view: Node3D) -> void:
	(view as PersonView).setup(_body_material, _accessory_material, _shadow_material)


func _accessory_of(person: PersonData) -> StringName:
	var def := _occupations.get_def(person.occupation_id) if _occupations != null else null
	return def.accessory if def != null else &""


func _on_person_added(id: int) -> void:
	if not _ids.has(id):
		_ids.append(id)


func _on_person_removed(id: int) -> void:
	_ids.erase(id)
	var view := _pool.view_of(id) as PersonView
	if view != null:
		view.unbind()
		_pool.release(id)


func _build_markers() -> void:
	_marker_material = StandardMaterial3D.new()
	_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_marker_material.billboard_keep_scale = true
	_marker_material.vertex_color_use_as_albedo = true
	_marker_material.vertex_color_is_srgb = true
	_marker_material.no_depth_test = true # found even behind a tree
	_marker_material.albedo_texture = marker_texture()
	_marker_material.render_priority = 2
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = 32
	multimesh.visible_instance_count = 0
	_markers = MultiMeshInstance3D.new()
	_markers.name = "Markers"
	_markers.multimesh = multimesh
	_markers.material_override = _marker_material
	_markers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Markers are spread over the whole world: never cull the batch.
	_markers.custom_aabb = AABB(Vector3(-4096, -64, -4096), Vector3(8192, 256, 8192))
	_markers.visible = false
	add_child(_markers)


## A disc with a dark rim (the rim keeps it readable on any ground); the disc
## takes the colour of the person's clothes.
static func marker_texture(size: int = 48) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5 - Vector2(0.5, 0.5)
	var outer := size * 0.5 - 1.0
	var inner := outer * 0.72
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(center)
			var alpha := clampf(outer - d + 0.5, 0.0, 1.0)
			var fill := clampf(inner - d + 0.5, 0.0, 1.0)
			var shade := lerpf(0.12, 1.0, fill)
			image.set_pixel(x, y, Color(shade, shade, shade, alpha))
	return ImageTexture.create_from_image(image)
