class_name AmbientLife
extends Node3D
## Small things that move on their own so the world never looks frozen
## (bible §3 pillar 2, §28.2): a flock of birds circling the box and smoke
## rising from the campfire. Purely visual — nothing here is simulated or saved.

const BIRD_COUNT := 7
const BIRD_SHADER := preload("res://assets/shaders/bird.gdshader")
## Seconds for one lap around the box.
const FLOCK_LAP_SECONDS := 46.0
const FLOCK_HEIGHT := 7.5
const SMOKE_PARTICLES := 14

var _birds: MultiMeshInstance3D
var _smoke: CPUParticles3D
var _center := Vector3.ZERO
var _radius := Vector2(18.0, 13.0)
var _time := 0.0
var _formation: Array[Vector3] = []
var _bird_positions: Array[Vector3] = []
## Seconds until the next bird call.
var _chirp_in := 4.0


func _ready() -> void:
	_build_birds()
	_build_smoke()


## Fits the flock's path to the box and puts the smoke on the campfire.
func setup(world: WorldData, campfire_tile: Vector2i, has_campfire: bool) -> void:
	var b := world.bounds
	_center = Vector3(b.position.x + b.size.x * 0.5, 0.0, b.position.y + b.size.y * 0.5)
	_radius = Vector2(b.size.x * 0.30, b.size.y * 0.22)
	_smoke.visible = has_campfire
	_smoke.emitting = false
	if has_campfire:
		# Move first, then start: the pre-simulated puffs are born where the
		# emitter is at that moment (they are in world space).
		var ground := world.get_height(campfire_tile) * world.height_step
		_smoke.position = Vector3(campfire_tile.x + 0.5, ground + 0.35, campfire_tile.y + 0.5)
		_smoke.restart()
		_smoke.emitting = true
	_update_birds()


func bird_count() -> int:
	return _birds.multimesh.instance_count


## Current world position of bird `index` (the renderer's copy cannot be read
## back when running headless).
func bird_position(index: int) -> Vector3:
	return _bird_positions[index]


func smoke_position() -> Vector3:
	return _smoke.position


func is_smoking() -> bool:
	return _smoke.emitting


func _process(delta: float) -> void:
	_time += delta
	_update_birds()
	_chirp_in -= delta
	if _chirp_in <= 0.0:
		_chirp_in = randf_range(Config.feedback.chirp_min_seconds, Config.feedback.chirp_max_seconds)
		chirp()


## One of the birds calls (heard from where it is flying).
func chirp() -> void:
	if _bird_positions.is_empty():
		return
	var bird := randi() % _bird_positions.size()
	AudioManager.play_at(&"chirp", _bird_positions[bird], Config.feedback.chirp_volume_db, randf_range(0.9, 1.2))


func _update_birds() -> void:
	var mm := _birds.multimesh
	var angle := _time / FLOCK_LAP_SECONDS * TAU
	for i in mm.instance_count:
		# Each bird trails the leader slightly and drifts in and out of formation.
		var a := angle - i * 0.035
		var wobble := sin(_time * 0.7 + i * 1.9) * 0.6
		var pos := _center + Vector3(cos(a) * _radius.x, FLOCK_HEIGHT + sin(_time * 0.4 + i) * 0.5, sin(a) * _radius.y)
		var heading := Vector3(-sin(a) * _radius.x, 0.0, cos(a) * _radius.y).normalized()
		var right := heading.cross(Vector3.UP).normalized()
		pos += right * (_formation[i].x + wobble) + heading * _formation[i].z
		# The mesh's nose points along -Z; wings span X.
		var basis := Basis(right, Vector3.UP, -heading)
		mm.set_instance_transform(i, Transform3D(basis, pos))
		_bird_positions[i] = pos


func _build_birds() -> void:
	# Body at the origin, wing tips out to the sides and slightly back.
	var vertices := PackedVector3Array([
		Vector3(0, 0, -0.16), Vector3(-0.42, 0, 0.10), Vector3(0, 0, 0.06),
		Vector3(0, 0, -0.16), Vector3(0, 0, 0.06), Vector3(0.42, 0, 0.10),
	])
	var uvs := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(0, 0),
		Vector2(0, 0), Vector2(0, 0), Vector2(1, 0),
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = BIRD_SHADER
	mesh.surface_set_material(0, material)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = BIRD_COUNT
	_formation.clear()
	_bird_positions.resize(BIRD_COUNT)
	for i in BIRD_COUNT:
		# A loose V: alternate left/right, each pair further back.
		var rank := (i + 1) / 2
		var side := -1.0 if i % 2 == 0 else 1.0
		_formation.append(Vector3(side * rank * 0.75, 0.0, rank * 0.7) if i > 0 else Vector3.ZERO)
		mm.set_instance_custom_data(i, Color(i * 1.7, 0, 0, 0)) # flap phase
		mm.set_instance_transform(i, Transform3D.IDENTITY)
	_birds = MultiMeshInstance3D.new()
	_birds.name = "Birds"
	_birds.multimesh = mm
	_birds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The flock roams far from the node's origin; never cull it by its small AABB.
	_birds.custom_aabb = AABB(Vector3(-600, -20, -600), Vector3(1200, 80, 1200))
	add_child(_birds)


## A round, soft-edged white dot (generated, so there is no texture file).
static func soft_dot() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.add_point(0.55, Color(1, 1, 1, 0.55))
	gradient.set_color(gradient.get_point_count() - 1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	return texture


func _build_smoke() -> void:
	var puff := QuadMesh.new()
	puff.size = Vector2(0.32, 0.32)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(1, 1, 1, 1)
	material.albedo_texture = soft_dot()
	puff.material = material

	var fade := Gradient.new()
	fade.set_color(0, Color(0.85, 0.85, 0.85, 0.0))
	fade.add_point(0.15, Color(0.82, 0.82, 0.82, 0.42))
	fade.set_color(fade.get_point_count() - 1, Color(0.9, 0.9, 0.9, 0.0))
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.45))
	grow.add_point(Vector2(1.0, 1.6))

	_smoke = CPUParticles3D.new()
	_smoke.name = "CampfireSmoke"
	_smoke.mesh = puff
	_smoke.amount = SMOKE_PARTICLES
	_smoke.lifetime = 4.5
	_smoke.preprocess = 4.5 # already rising when first seen
	_smoke.direction = Vector3(0.25, 1.0, 0.08) # drifts with the wind
	_smoke.spread = 9.0
	_smoke.gravity = Vector3.ZERO
	_smoke.initial_velocity_min = 0.45
	_smoke.initial_velocity_max = 0.7
	_smoke.color_ramp = fade
	_smoke.scale_amount_curve = grow
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke.emitting = false
	add_child(_smoke)
