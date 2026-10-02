class_name ToolFx
extends Node3D
## What the player's powers look like in the world (M9.5): the cloud that
## forms under a held finger and the rain falling from it, and the dust a
## gust raises. (The trees bending to a gust is the sky's business:
## `WeatherFx.gust`.)
##
## The rain is the weather's rain in small: the same shader, a few drops,
## in the column under the cloud — nothing per drop on the CPU.

const RAIN_SHADER := preload("res://assets/shaders/rain.gdshader")
const DROPS := 150
const CLOUD_LIGHT := Color(0.90, 0.92, 0.95, 0.9)
const CLOUD_HEAVY := Color(0.50, 0.53, 0.60, 0.9)
## How wide the cloud is for the ground it rains on (it is smaller than its
## rain: what is under it should still be seen).
const CLOUD_WIDTH := 0.62
const RAIN_TINT := Color(0.80, 0.87, 0.96, 0.6)
## Seconds for the cloud to form and to go.
const FORM_SECONDS := 0.35
## How many puffs of dust a gust raises along its way.
const GUST_PUFFS := 4

var _cloud: Node3D
var _cloud_material: StandardMaterial3D
var _rain: MultiMeshInstance3D
var _rain_material: ShaderMaterial
var _effects: WorldEffects
var _day_night: DayNight
var _world: WorldData
var _wanted := false
var _formed := 0.0 # 0 nothing … 1 the whole cloud
var _radius := 3.0
var _strength := 0.3
var _at := Vector3.ZERO
## How many gusts were shown (tests).
var gusts := 0


func _init() -> void:
	name = "ToolFx"
	_cloud = Node3D.new()
	_cloud.name = "Cloud"
	_cloud.visible = false
	add_child(_cloud)
	_cloud_material = StandardMaterial3D.new()
	_cloud_material.albedo_color = CLOUD_LIGHT
	_cloud_material.roughness = 1.0
	_cloud_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# A handful of flattened balls: a low-poly cloud.
	var puffs := [[Vector3(0.0, 0.0, 0.0), 0.62], [Vector3(0.55, -0.04, 0.15), 0.46], [Vector3(-0.5, -0.02, -0.2), 0.5],
		[Vector3(0.1, 0.03, -0.5), 0.42], [Vector3(-0.15, -0.03, 0.5), 0.4]]
	for puff: Array in puffs:
		var ball := SphereMesh.new()
		ball.radius = puff[1]
		ball.height = float(puff[1]) * 1.1
		ball.radial_segments = 12
		ball.rings = 6
		var node := MeshInstance3D.new()
		node.mesh = ball
		node.position = puff[0]
		node.material_override = _cloud_material
		_cloud.add_child(node)
	_rain = MultiMeshInstance3D.new()
	_rain.name = "Rain"
	_rain.visible = false
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_material = ShaderMaterial.new()
	_rain_material.shader = RAIN_SHADER
	_rain.material_override = _rain_material
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.center_offset = Vector3(0.0, 0.5, 0.0)
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_custom_data = true
	mesh.mesh = quad
	mesh.instance_count = DROPS
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261002
	for i in DROPS:
		mesh.set_instance_transform(i, Transform3D.IDENTITY)
		mesh.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), float(i) / DROPS))
	_rain.multimesh = mesh
	add_child(_rain)


func setup(effects: WorldEffects, day_night: DayNight) -> void:
	_effects = effects
	_day_night = day_night


## The world it is shown in (rain stays inside the box).
func bind(world: WorldData) -> void:
	_world = world
	hide_rain()
	_formed = 0.0
	_cloud.visible = false
	_rain.visible = false


# --- the cloud ----------------------------------------------------------------------------------------

## A cloud forms over `at` (a point on the surface), `radius` tiles wide, and it rains.
func show_rain(at: Vector3, radius: float) -> void:
	_wanted = true
	_at = at
	_radius = maxf(radius, 0.5)
	_strength = 0.3
	_apply()


## The cloud is over `at` now; `strength` 0 … 1 is how hard it rains.
func move_rain(at: Vector3, strength: float) -> void:
	_at = at
	_strength = clampf(strength, 0.0, 1.0)
	if _wanted:
		_apply()


func hide_rain() -> void:
	_wanted = false


func is_raining() -> bool:
	return _wanted


## Where the cloud hangs (its middle).
func cloud_position() -> Vector3:
	return _cloud.position


func cloud_node() -> Node3D:
	return _cloud


func rain_node() -> MultiMeshInstance3D:
	return _rain


func rain_material() -> ShaderMaterial:
	return _rain_material


## How much of the cloud is there, 0 … 1.
func formed() -> float:
	return _formed


## Lets `delta` real seconds pass (called every frame; tests call it themselves).
func advance(delta: float) -> void:
	var step := delta / FORM_SECONDS
	_formed = move_toward(_formed, 1.0 if _wanted else 0.0, step)
	if _formed <= 0.0:
		if _cloud.visible:
			_cloud.visible = false
			_rain.visible = false
		return
	_apply()


func _process(delta: float) -> void:
	if _wanted or _formed > 0.0:
		advance(delta)


func _apply() -> void:
	var height := Config.tools.rain_cloud_height
	_cloud.visible = _formed > 0.0
	_rain.visible = _formed > 0.0
	_cloud.position = _at + Vector3(0.0, height, 0.0)
	var wide := _radius * CLOUD_WIDTH * _formed
	_cloud.scale = Vector3(wide, wide * 0.6, wide)
	_cloud_material.albedo_color = CLOUD_LIGHT.lerp(CLOUD_HEAVY, _strength)
	var box := Rect2(_world.bounds) if _world != null else Rect2(-1000.0, -1000.0, 2000.0, 2000.0)
	_rain_material.set_shader_parameter(&"area_center", Vector2(_at.x, _at.z))
	_rain_material.set_shader_parameter(&"area_size", _radius * 2.0)
	_rain_material.set_shader_parameter(&"top", _at.y + height)
	_rain_material.set_shader_parameter(&"bottom", _at.y - 1.0)
	_rain_material.set_shader_parameter(&"fall_speed", 11.0)
	_rain_material.set_shader_parameter(&"wind", Vector2.ZERO)
	_rain_material.set_shader_parameter(&"amount", lerpf(0.45, 1.0, _strength) * _formed)
	_rain_material.set_shader_parameter(&"snow", 0.0)
	_rain_material.set_shader_parameter(&"tint", RAIN_TINT)
	_rain_material.set_shader_parameter(&"daylight", 1.0 - 0.75 * _day_night.night() if _day_night != null else 1.0)
	_rain_material.set_shader_parameter(&"box_min", box.position)
	_rain_material.set_shader_parameter(&"box_max", box.end)
	_rain.custom_aabb = AABB(Vector3(_at.x - _radius - 1.0, _at.y - 1.0, _at.z - _radius - 1.0),
		Vector3(_radius * 2.0 + 2.0, height + 2.0, _radius * 2.0 + 2.0))


# --- a gust -------------------------------------------------------------------------------------------

## A gust from `from` to `to` (points on the surface): dust rises along its
## way — rings where it crosses water.
func gust(from: Vector3, to: Vector3) -> void:
	gusts += 1
	if _effects == null:
		return
	for n in GUST_PUFFS:
		var at := from.lerp(to, (n + 0.5) / GUST_PUFFS)
		var tile := WorldCoords.world2d_to_tile(Vector2(at.x, at.z))
		if _world != null and _world.is_in_bounds(tile):
			at.y = _world.get_height(tile) * _world.height_step + maxf(_world.get_water(tile), 0.0)
			if _world.get_water(tile) > WaterMesher.MIN_DEPTH:
				_effects.ring(at, 0.7, 0.9, WorldEffects.WATER_RING)
				continue
			_effects.burst(WorldEffects.Burst.DUST, at + Vector3(0.0, 0.1, 0.0), WorldEffects.dust_color(_world.get_terrain(tile)))
