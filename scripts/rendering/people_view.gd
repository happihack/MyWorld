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
const OUTLINE_SHADER := preload("res://assets/shaders/person_outline.gdshader")
## The ring under the selected person: its radius in the world, and the
## smallest it gets on screen (viewport units) — it is how they are found.
const RING_RADIUS := 0.34
const RING_MIN_ON_SCREEN := 20.0
const RING_COLOR := Color(1.0, 0.86, 0.45, 0.95)
const RING_LIFT := 0.04
## The signs above people's heads (bible §14.4): what they feel, at a glance.
const EMOTES := {
	&"exclaim": preload("res://assets/ui/emotes/exclaim.svg"),
	&"question": preload("res://assets/ui/emotes/question.svg"),
	&"pray": preload("res://assets/ui/emotes/pray.svg"),
	&"speech": preload("res://assets/ui/emotes/speech.svg"),
	&"note": preload("res://assets/ui/emotes/note.svg"),
	&"dots": preload("res://assets/ui/emotes/dots.svg"),
}
## How large a sign is in the world, and the least it is on screen (viewport
## units): readable from the middle distance.
const EMOTE_SIZE := 0.22
const EMOTE_MIN_ON_SCREEN := 46.0
## A sign pops up in this long.
const EMOTE_POP_SECONDS := 0.18
## The dots of an observed person's way.
const TRAIL_DOT := 0.09
const TRAIL_COLOR := Color(1.0, 0.92, 0.66, 0.85)

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
## Only people who are simulated as individuals moving about are drawn as
## bodies (tier 2 and up; the abstract tiers are numbers, not walkers).
const MIN_TIER_FOR_VIEW := TierManager.REGIONAL
const REDUCED_MOTION := 0.35

var reduced_motion := false:
	set(value):
		reduced_motion = value
		_body_material.set_shader_parameter(&"motion", REDUCED_MOTION if value else 1.0)
		_selected_material.set_shader_parameter(&"motion", REDUCED_MOTION if value else 1.0)
		_outline_material.set_shader_parameter(&"motion", REDUCED_MOTION if value else 1.0)

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
## The body material with the outline pass after it: the selected person's.
var _selected_material: ShaderMaterial
var _outline_material: ShaderMaterial
var _selected_id := 0
var _ring: MeshInstance3D
var _trail: MultiMeshInstance3D
var _emote_root: Node3D
var _emote_sprites: Dictionary = {} # person id -> Sprite3D
var _emote_ages: Dictionary = {} # person id -> seconds shown
var _emote_spare: Array[Sprite3D] = []
var _marker_transforms: Array[Transform3D] = [] # as written to the MultiMesh (for queries)
var _bodies_shown := true
var _refreshes := 0


func _init() -> void:
	_body_material = ShaderMaterial.new()
	_body_material.shader = PERSON_SHADER
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	_selected_material = ShaderMaterial.new()
	_selected_material.shader = PERSON_SHADER
	_selected_material.next_pass = _outline_material
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
	_build_selection()
	_emote_root = Node3D.new()
	_emote_root.name = "Emotes"
	add_child(_emote_root)


## `rig` is the camera people are seen through; `accessory_material` draws what
## they carry (the prop material: same light and cloud shadows as the world).
func setup(rig: CameraRig, accessory_material: Material) -> void:
	_rig = rig
	_accessory_material = accessory_material


## Pushes the cloud-shadow look into the body material (see WorldView.apply_palette).
func body_material() -> ShaderMaterial:
	return _body_material


## The same material with the outline after it (the selected person's).
func selected_material() -> ShaderMaterial:
	return _selected_material


# --- signs above heads --------------------------------------------------------------------------

## The sign shown above a person right now (&"" if none).
func emote_of(person_id: int) -> StringName:
	var sprite: Sprite3D = _emote_sprites.get(person_id)
	return sprite.get_meta(&"emote", &"") if sprite != null else &""


func emote_sprite(person_id: int) -> Sprite3D:
	return _emote_sprites.get(person_id)


func emote_count() -> int:
	return _emote_sprites.size()


func _show_emote(person_id: int, emote: StringName, head: Vector3, size: float, delta: float) -> void:
	var texture: Texture2D = EMOTES.get(emote)
	if texture == null:
		if _emote_sprites.has(person_id):
			_drop_emote(person_id)
		return
	var sprite: Sprite3D = _emote_sprites.get(person_id)
	if sprite == null:
		sprite = _emote_spare.pop_back() if not _emote_spare.is_empty() else _new_emote_sprite()
		sprite.visible = true
		_emote_sprites[person_id] = sprite
		_emote_ages[person_id] = 0.0
	if sprite.get_meta(&"emote", &"") != emote:
		sprite.set_meta(&"emote", emote)
		sprite.texture = texture
		sprite.pixel_size = 1.0 / maxf(texture.get_height(), 1.0) # one unit tall, scaled below
		_emote_ages[person_id] = 0.0 # a new sign pops up anew
	var age: float = float(_emote_ages[person_id]) + delta
	_emote_ages[person_id] = age
	# Pops up: a little too large, then to size.
	var grown := 1.0
	if not reduced_motion and age < EMOTE_POP_SECONDS:
		var t := age / EMOTE_POP_SECONDS
		grown = lerpf(0.3, 1.0, t) + sin(t * PI) * 0.35
	sprite.scale = Vector3.ONE * size * grown
	sprite.position = head + Vector3(0, size * 0.62, 0)


func _drop_emote(person_id: int) -> void:
	var sprite: Sprite3D = _emote_sprites.get(person_id)
	_emote_sprites.erase(person_id)
	_emote_ages.erase(person_id)
	if sprite != null:
		sprite.visible = false
		sprite.set_meta(&"emote", &"")
		_emote_spare.append(sprite)


func _new_emote_sprite() -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.no_depth_test = true # a sign is never hidden behind a tree
	sprite.render_priority = 8
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_emote_root.add_child(sprite)
	return sprite


# --- selection ----------------------------------------------------------------------------------

## Marks a person as the one the player has selected (0 = nobody): a ring
## under their feet, an outline around their body.
func set_selected(person_id: int) -> void:
	_selected_id = person_id
	if person_id == 0:
		_ring.visible = false


func selected_id() -> int:
	return _selected_id


## Is the ring showing, and where?
func ring_shown() -> bool:
	return _ring.visible


func ring_position() -> Vector3:
	return _ring.position


## Shows a way on the ground as a row of dots (an observed person's path);
## an empty list takes it away.
func show_trail(points: PackedVector3Array) -> void:
	var multimesh := _trail.multimesh
	if multimesh.instance_count < points.size():
		multimesh.instance_count = maxi(points.size(), multimesh.instance_count * 2)
	for i in points.size():
		# The last dot — where they are going — is larger.
		var dot := TRAIL_DOT * (2.0 if i == points.size() - 1 else 1.0)
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(dot, 1.0, dot)), points[i] + Vector3(0, RING_LIFT, 0)))
	multimesh.visible_instance_count = points.size()
	_trail.visible = not points.is_empty()


func trail_size() -> int:
	return _trail.multimesh.visible_instance_count if _trail.visible else 0


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
	for id: int in _emote_sprites.keys():
		_drop_emote(id)
	_selected_id = 0
	_ring.visible = false
	show_trail(PackedVector3Array())
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
				view.set_load(person.carrying if person.carrying_amount > 0 else &"")
				view.set_selected(id == _selected_id, _body_material, _selected_material)
		elif view != null:
			view.unbind()
			_pool.release(id)
		if person.emote != &"" and not indoors:
			var head := (view.position if view != null and wants_view else feet) \
				+ Vector3(0, PersonMeshLibrary.ADULT_HEIGHT * (view.scale.y / PersonMeshLibrary.ADULT_HEIGHT if view != null and wants_view else 1.0), 0)
			_show_emote(id, person.emote, head, maxf(EMOTE_SIZE, EMOTE_MIN_ON_SCREEN * units_per_px), delta)
		elif _emote_sprites.has(id):
			_drop_emote(id)
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
	if _emote_sprites.size() > 0:
		for id: int in _emote_sprites.keys():
			if not _people.has_person(id):
				_drop_emote(id)
	_marker_material.albedo_color.a = _marker_alpha
	# The ring under whoever is selected: with their body, or where they are
	# if they have none (far away) — and never smaller than can be seen.
	var chosen := _people.get_person(_selected_id) if _selected_id != 0 else null
	if chosen == null or chosen.has_flag(PersonData.FLAG_INDOORS):
		_ring.visible = false
	else:
		var body := _pool.view_of(_selected_id) as PersonView
		_ring.position = (body.position if body != null else ground_position(chosen)) + Vector3(0, RING_LIFT, 0)
		var radius := maxf(RING_RADIUS, RING_MIN_ON_SCREEN * units_per_px)
		_ring.scale = Vector3(radius, 1.0, radius)
		_ring.visible = true


## The body a finger can hit (Vector2(height, radius), see Picker), or null
## for anyone who is not to be seen (indoors, not of this world).
func pick_shape(person_id: int) -> Variant:
	var person := _people.get_person(person_id) if _people != null else null
	if person == null or person.has_flag(PersonData.FLAG_INDOORS):
		return null
	var view := _pool.view_of(person_id) as PersonView
	var height := view.scale.y if view != null else PersonMeshLibrary.ADULT_HEIGHT
	return Vector2(height, maxf(height * 0.4, 0.16))


## Where a person's feet are in the world.
func ground_position(person: PersonData) -> Vector3:
	var at := person.world2d()
	return Vector3(at.x, _world.get_height(person.position) * _world.height_step, at.y)


## Where a person is seen right now: their body's place if they have one
## (it trails the person by a step), else where they are.
func shown_position(person: PersonData) -> Vector3:
	var body := _pool.view_of(person.id) as PersonView
	return body.position if body != null else ground_position(person)


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


## A round dot with a crisp edge (white; the material colours it).
static func trail_dot_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.82, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	return texture


func _build_selection() -> void:
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.albedo_color = RING_COLOR
	ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_material.render_priority = 2
	_ring = MeshInstance3D.new()
	_ring.name = "SelectionRing"
	_ring.mesh = PickHighlight._ring_mesh()
	_ring.material_override = ring_material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)
	var dot_material := StandardMaterial3D.new()
	dot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot_material.albedo_texture = trail_dot_texture()
	dot_material.albedo_color = TRAIL_COLOR
	dot_material.render_priority = 1
	var dot := PlaneMesh.new()
	dot.size = Vector2(2.0, 2.0)
	var dots := MultiMesh.new()
	dots.transform_format = MultiMesh.TRANSFORM_3D
	dots.mesh = dot
	dots.instance_count = 64
	dots.visible_instance_count = 0
	_trail = MultiMeshInstance3D.new()
	_trail.name = "Trail"
	_trail.multimesh = dots
	_trail.material_override = dot_material
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.custom_aabb = AABB(Vector3(-4096, -64, -4096), Vector3(8192, 256, 8192))
	_trail.visible = false
	add_child(_trail)


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
