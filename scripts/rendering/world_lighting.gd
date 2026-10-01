class_name WorldLighting
extends Node3D
## Light and atmosphere for the diorama (bible §28.2): a warm sun, cool sky
## ambient, the tabletop the box stands on, and a vignette. Shadows and the
## vignette follow the graphics quality level. The sun is static for now; the
## day/night cycle (M6) will drive it through set_sun().

const TABLE_SHADER := preload("res://assets/shaders/table.gdshader")
const VIGNETTE_SHADER := preload("res://assets/shaders/vignette.gdshader")

const BACKGROUND := Color(0.113725, 0.141176, 0.188235)
const SUN_COLOR := Color(1.0, 0.96, 0.88)
const AMBIENT_COLOR := Color(0.62, 0.69, 0.82)
const SUN_ROTATION_DEG := Vector3(-50.0, 40.0, 0.0)
## The tabletop extends this many box-widths around the box.
const TABLE_SPAN := 5.0

var quality: GraphicsQuality.Level = GraphicsQuality.Level.MEDIUM

var _sun: DirectionalLight3D
var _environment: Environment
var _table: MeshInstance3D
var _table_material: ShaderMaterial
var _vignette_layer: CanvasLayer
var _vignette: ColorRect


func _ready() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.rotation_degrees = SUN_ROTATION_DEG
	_sun.light_color = SUN_COLOR
	_sun.light_energy = 1.2
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.shadow_opacity = 0.72
	_sun.shadow_blur = 1.2
	add_child(_sun)

	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = BACKGROUND
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = AMBIENT_COLOR
	_environment.ambient_light_energy = 0.55
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.glow_enabled = false
	var world_env := WorldEnvironment.new()
	world_env.name = "Environment"
	world_env.environment = _environment
	add_child(world_env)

	_table_material = ShaderMaterial.new()
	_table_material.shader = TABLE_SHADER
	_table_material.set_shader_parameter(&"background_color", BACKGROUND)
	_table = MeshInstance3D.new()
	_table.name = "Table"
	_table.mesh = PlaneMesh.new()
	_table.material_override = _table_material
	_table.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_table)

	_vignette_layer = CanvasLayer.new()
	_vignette_layer.name = "VignetteLayer"
	_vignette_layer.layer = 0 # above the 3D world, below the UI (layer 1+)
	add_child(_vignette_layer)
	_vignette = ColorRect.new()
	_vignette.name = "Vignette"
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vignette_material := ShaderMaterial.new()
	vignette_material.shader = VIGNETTE_SHADER
	_vignette.material = vignette_material
	_vignette_layer.add_child(_vignette)

	apply_quality(GraphicsQuality.current())
	Settings.setting_changed.connect(_on_setting_changed)


## Sizes the tabletop and shadow range to the box.
func fit_to_box(frame_rect: Rect2, table_y: float, box_height: float) -> void:
	var center := frame_rect.get_center()
	var span := maxf(frame_rect.size.x, frame_rect.size.y)
	(_table.mesh as PlaneMesh).size = Vector2.ONE * span * (1.0 + TABLE_SPAN * 2.0)
	_table.position = Vector3(center.x, table_y, center.y)
	_table_material.set_shader_parameter(&"box_center", center)
	_table_material.set_shader_parameter(&"box_half", frame_rect.size * 0.5)
	_table_material.set_shader_parameter(&"fade_start", span * 0.75)
	_table_material.set_shader_parameter(&"fade_end", span * (0.5 + TABLE_SPAN * 0.42))
	_table_material.set_shader_parameter(&"shadow_reach", span * 0.07)
	# Shadows must cover the whole box from any camera distance used to view it.
	_sun.directional_shadow_max_distance = span * 4.0 + box_height
	_sun.directional_shadow_fade_start = 0.95


func apply_quality(level: GraphicsQuality.Level) -> void:
	quality = level
	_sun.shadow_enabled = GraphicsQuality.shadows_enabled(level)
	if _sun.shadow_enabled:
		RenderingServer.directional_shadow_atlas_set_size(GraphicsQuality.shadow_atlas_size(level), true)
		RenderingServer.directional_soft_shadow_filter_set_quality(
			RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if level == GraphicsQuality.Level.HIGH
			else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	_vignette.visible = GraphicsQuality.vignette_enabled(level)
	Log.info(Log.Category.PERFORMANCE, "Graphics quality", {"level": GraphicsQuality.level_name(level), "shadows": _sun.shadow_enabled})


## Sun direction/colour/strength (driven by the day/night cycle later).
func set_sun(rotation_deg: Vector3, color: Color, energy: float) -> void:
	_sun.rotation_degrees = rotation_deg
	_sun.light_color = color
	_sun.light_energy = energy


func shadows_enabled() -> bool:
	return _sun.shadow_enabled


func vignette_visible() -> bool:
	return _vignette.visible


func table_position() -> Vector3:
	return _table.position


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key == GraphicsQuality.SETTING:
		apply_quality(GraphicsQuality.current())
