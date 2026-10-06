class_name WeatherFx
extends Node3D
## What the weather looks and sounds like (bible §10.1, §28.2): rain and
## snow falling inside the box, the light going grey under clouds, fog,
## lightning and thunder in a storm, the wind in the trees, the ground
## darkening in the rain — and the sound of it.
##
## It only reads the weather (WeatherSystem) and shows it: what it shows
## eases towards what the weather is, so that the sky changes and does not
## switch. Everything it drives is handed to it by the WorldView.

const RAIN_SHADER := preload("res://assets/shaders/rain.gdshader")

## Thunder's echoes: none to this many after the crash, this far apart
## (seconds, least … most), each this much quieter (dB) than the one before.
const ECHOES_MOST := 3
const ECHO_GAP := Vector2(0.6, 1.6)
const ECHO_FADE_DB := 6.0
## Echoes still to come: [seconds, volume dB, pitch]; and how many were heard.
var _echoes_in: Array = []
var echoes := 0
## Below this nothing is drawn (and nothing heard).
const NOTHING := 0.01

@onready var _rain: MultiMeshInstance3D = %Rain
@onready var _leaves: MultiMeshInstance3D = %Leaves

## What is shown right now (it eases towards what the weather is).
var cover := 0.0
var fog := 0.0
## How much falls, 0 … 1, and whether it is snow.
var falling := 0.0
var snowing := false
var wind := Vector2.ZERO
## A gust on top of it (the player's): which way and how hard, and how much
## of it is left (seconds, of how many).
var _gust := Vector2.ZERO
var _gust_left := 0.0
var _gust_seconds := 1.0
## How wet the ground is, 0 … 1.
var wetness := 0.0
## How much snow lies and how frozen the water is, 0 … 1 (as shown).
var snow := 0.0
var ice := 0.0
## Where in the year what is shown stands (0 … 4, see Seasons).
var season := -1.0
## How many leaves are in the air, 0 … 1.
var leaf_fall := 0.0
## How bright the lightning is right now, 0 … 1.
var flash := 0.0
## For tests and the overlay.
var flashes := 0
var thunders := 0
## No flashes (accessibility: reduced motion); the thunder is still heard.
var reduced_motion := false

var _weather: WeatherSystem
var _clock: GameClock
var _rig: CameraRig
var _day_night: DayNight
var _lighting: WorldLighting
var _prop_material: ShaderMaterial
var _terrain_material: ShaderMaterial
var _water_material: ShaderMaterial
var _ambient: AmbientLife
var _rain_material: ShaderMaterial
var _leaf_material: ShaderMaterial
var _config: WeatherFxConfig
var _box := Rect2(-1000.0, -1000.0, 2000.0, 2000.0)
var _top := 12.0
var _bottom := 0.0
var _drop_count := 0
var _base_sway := 0.055
var _strike_in := 0.0
var _flash_left := 0.0
var _thunder_in: Array[float] = []
var _rng := RandomNumberGenerator.new() # looks only; never the simulation's


func _ready() -> void:
	_config = Config.weather_fx
	_rain_material = ShaderMaterial.new()
	_rain_material.shader = RAIN_SHADER
	_rain.material_override = _rain_material
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.visible = false
	_leaf_material = ShaderMaterial.new()
	_leaf_material.shader = RAIN_SHADER
	_leaves.material_override = _leaf_material
	_leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_leaves.visible = false
	_build_drops(GraphicsQuality.current())
	_strike_in = _next_strike()
	reduced_motion = bool(Settings.get_value(&"accessibility/reduced_motion"))
	Settings.setting_changed.connect(_on_setting_changed)


## What it drives: the camera (where the rain falls), the light of the day,
## the atmosphere, and the materials of the props (sway) and the ground (wet).
func setup(rig: CameraRig, day_night: DayNight, lighting: WorldLighting, prop_material: ShaderMaterial,
		terrain_material: ShaderMaterial, water_material: ShaderMaterial = null, ambient: AmbientLife = null) -> void:
	_water_material = water_material
	_ambient = ambient
	_rig = rig
	_day_night = day_night
	_lighting = lighting
	_prop_material = prop_material
	_terrain_material = terrain_material
	if prop_material != null:
		var amplitude: Variant = prop_material.get_shader_parameter(&"sway_amplitude")
		_base_sway = float(amplitude) if typeof(amplitude) == TYPE_FLOAT else 0.055


## The box the weather stays in: its ground rectangle (world X/Z) and from
## where to where things fall.
func fit_to_box(box: Rect2, bottom_y: float, top_y: float) -> void:
	_box = box
	_bottom = bottom_y
	_top = top_y


## The weather to show (null: none — a clear, still sky).
func bind(weather: WeatherSystem, clock: GameClock) -> void:
	_weather = weather
	_clock = clock
	snap()


## Shows the weather as it is, at once (a world just opened).
func snap() -> void:
	var target := _targets()
	cover = target["cover"]
	fog = target["fog"]
	falling = target["falling"]
	snowing = target["snow"]
	wind = target["wind"]
	wetness = 1.0 if falling > NOTHING and not snowing else 0.0
	snow = _weather.snow_cover if _weather != null else 0.0
	ice = 1.0 if _weather != null and _weather.is_frozen() else 0.0
	season = -1.0 # (shown anew)
	_apply()


func drop_count() -> int:
	return _drop_count


func rain_node() -> MultiMeshInstance3D:
	return _rain


func rain_material() -> ShaderMaterial:
	return _rain_material


func is_storming() -> bool:
	return _weather != null and _weather.state == WeatherSystem.STORM


func _process(delta: float) -> void:
	advance(delta)


## Lets `delta` real seconds pass for what is shown. (Called every frame;
## tests call it themselves.)
func advance(delta: float) -> void:
	var target := _targets()
	# The sky changes over seconds — fewer when the world runs faster.
	var speed := maxf(_clock.speed_multiplier(), 1.0) if _clock != null and not _clock.is_paused() else 1.0
	var share := clampf(delta * speed / _config.transition_seconds, 0.0, 1.0) if _config.transition_seconds > 0.0 else 1.0
	cover = move_toward(cover, target["cover"], share)
	fog = move_toward(fog, target["fog"], share)
	wind = wind.move_toward(target["wind"], share * 1.5)
	# What falls changes kind only when little is falling (rain does not turn white in mid-air).
	if bool(target["snow"]) != snowing:
		falling = move_toward(falling, 0.0, share * 2.0)
		if falling <= NOTHING:
			snowing = target["snow"]
	else:
		falling = move_toward(falling, target["falling"], share)
	# The ground: wet soon in the rain, dry slowly after it.
	if falling > NOTHING and not snowing:
		wetness = move_toward(wetness, 1.0, delta * speed / _config.wetting_seconds)
	else:
		wetness = move_toward(wetness, 0.0, delta * speed / _config.drying_seconds)
	# Snow comes and goes with what lies; water freezes over and thaws.
	snow = move_toward(snow, _weather.snow_cover if _weather != null else 0.0, share * 0.5)
	ice = move_toward(ice, 1.0 if _weather != null and _weather.is_frozen() else 0.0, share * 0.5)
	_gust_left = maxf(_gust_left - delta, 0.0)
	_advance_lightning(delta)
	_apply()


## A gust: the trees bend `blow`'s way (its length is how hard, as the
## weather's wind: 0 … 1) for `seconds`, and what falls is carried along.
func gust(blow: Vector2, seconds: float) -> void:
	_gust = blow
	_gust_seconds = maxf(seconds, 0.05)
	_gust_left = _gust_seconds
	_apply()


## The wind as it shows: the weather's, and what is left of a gust (which
## swells quickly and dies away).
func blowing() -> Vector2:
	if _gust_left <= 0.0:
		return wind
	var t := 1.0 - _gust_left / _gust_seconds
	return wind + _gust * sin(PI * sqrt(t))


## A flash of lightning now, and its thunder a moment later. (In a storm
## they come by themselves.)
func strike() -> void:
	flashes += 1
	_thunder_in.append(_rng.randf_range(_config.thunder_min_seconds, _config.thunder_max_seconds))
	if not reduced_motion:
		_flash_left = 0.32


func debug_text() -> String:
	return "sky: cover %.2f  fog %.2f  %s %.2f (%d drops)  wind (%.2f, %.2f)  wet %.2f  flashes %d\nseason %.2f  snow %.2f  ice %.2f  leaves %.2f" % [
		cover, fog, "snow" if snowing else "rain", falling, _drop_count if _rain.visible else 0, wind.x, wind.y, wetness, flashes,
		season, snow, ice, leaf_fall]


# --- internals --------------------------------------------------------------------------------------

## What the weather is now, as what there is to show.
func _targets() -> Dictionary:
	if _weather == null:
		return {"cover": 0.0, "fog": 0.0, "falling": 0.0, "snow": false, "wind": Vector2.ZERO}
	# (Snow is light: a snowfall is a sky full of flakes all the same.)
	var share := _weather.precipitation() / _config.full_precipitation * (3.0 if _weather.is_snowing() else 1.0)
	return {"cover": _weather.cloud_cover(), "fog": _weather.fog(), "falling": clampf(share, 0.0, 1.0),
		"snow": _weather.is_snowing(), "wind": _weather.wind()}


func _advance_lightning(delta: float) -> void:
	if is_storming():
		_strike_in -= delta
		if _strike_in <= 0.0:
			_strike_in = _next_strike()
			strike()
	# Two quick flickers.
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
		flash = 1.0 if _flash_left > 0.24 or (_flash_left > 0.06 and _flash_left < 0.16) else 0.15
		if _flash_left <= 0.0:
			flash = 0.0
	for i in range(_thunder_in.size() - 1, -1, -1):
		_thunder_in[i] -= delta
		if _thunder_in[i] <= 0.0:
			_thunder_in.remove_at(i)
			thunders += 1
			var at := _rig.camera().global_position if _rig != null else Vector3.ZERO
			var thunder: StringName = SoundSynth.THUNDER_IDS[_rng.randi_range(0, SoundSynth.THUNDER_IDS.size() - 1)]
			var pitch := _rng.randf_range(0.85, 1.1)
			AudioManager.play_at(thunder, at, _config.thunder_volume_db, pitch, false)
			# Then none to three echoes off the hills, each later, quieter and
			# deeper than the last (the owner, 2026-10-06).
			var after := 0.0
			for n in _rng.randi_range(0, ECHOES_MOST):
				after += _rng.randf_range(ECHO_GAP.x, ECHO_GAP.y)
				_echoes_in.append([after, _config.thunder_volume_db - ECHO_FADE_DB * (n + 1) - _rng.randf_range(0.0, 3.0),
					pitch * (0.92 - 0.05 * n)])
	for i in range(_echoes_in.size() - 1, -1, -1):
		_echoes_in[i][0] -= delta
		if float(_echoes_in[i][0]) <= 0.0:
			var echo: Array = _echoes_in[i]
			_echoes_in.remove_at(i)
			echoes += 1
			var where := _rig.camera().global_position if _rig != null else Vector3.ZERO
			var rolling: StringName = SoundSynth.THUNDER_IDS[_rng.randi_range(0, SoundSynth.THUNDER_IDS.size() - 1)]
			AudioManager.play_at(rolling, where, float(echo[1]), float(echo[2]), false)


func _next_strike() -> float:
	return _rng.randf_range(_config.lightning_min_seconds, _config.lightning_max_seconds)


## Pushes what is shown to everything that shows it.
func _apply() -> void:
	# Rain and snow, in a square around what the camera looks at.
	var visible_now := falling > NOTHING and _drop_count > 0
	if _rain.visible != visible_now:
		_rain.visible = visible_now
	if visible_now:
		var center := Vector2(_rig.pivot().x, _rig.pivot().z) if _rig != null else _box.get_center()
		var distance := _rig.distance() if _rig != null else 30.0
		var side := clampf(distance * _config.area_per_distance, _config.area_min, _config.area_max)
		var white := 1.0 if snowing else 0.0
		_rain_material.set_shader_parameter(&"area_center", center)
		_rain_material.set_shader_parameter(&"area_size", side)
		_rain_material.set_shader_parameter(&"top", _top)
		_rain_material.set_shader_parameter(&"bottom", _bottom)
		_rain_material.set_shader_parameter(&"fall_speed", _config.snow_speed if snowing else _config.rain_speed)
		_rain_material.set_shader_parameter(&"wind", blowing() * _config.wind_carry * (0.45 if snowing else 1.0))
		_rain_material.set_shader_parameter(&"amount", falling)
		_rain_material.set_shader_parameter(&"snow", white)
		_rain_material.set_shader_parameter(&"tint", _config.snow_color if snowing else _config.rain_color)
		_rain_material.set_shader_parameter(&"daylight", 1.0 - 0.75 * _day_night.night() if _day_night != null else 1.0)
		_rain_material.set_shader_parameter(&"box_min", _box.position)
		_rain_material.set_shader_parameter(&"box_max", _box.end)
		# (Drawn wherever the camera is: its place is worked out in the shader.)
		_rain.custom_aabb = AABB(Vector3(_box.position.x, _bottom, _box.position.y), Vector3(_box.size.x, _top - _bottom, _box.size.y))
	# The light.
	if _day_night != null:
		_day_night.set_weather(cover, flash)
	if _lighting != null:
		_lighting.set_fog(fog * _config.fog_haze, _config.fog_color, _rig.distance() if _rig != null else 30.0,
			_day_night.night() if _day_night != null else 0.0)
	# The wind in the trees; the ground in the rain.
	if _prop_material != null:
		var blow := blowing()
		_prop_material.set_shader_parameter(&"sway_amplitude", _base_sway * lerpf(_config.sway_calm, _config.sway_storm, minf(blow.length(), 1.0)))
		if blow.length() > 0.02:
			_prop_material.set_shader_parameter(&"wind_direction", blow.normalized())
	if _terrain_material != null:
		_terrain_material.set_shader_parameter(&"wetness", wetness * _config.wet_ground)
	_apply_seasons()
	AudioManager.set_weather(falling if not snowing else 0.0, wind.length())


## The seasons: the colour of what grows, bare trees, leaves in the air,
## snow on the ground and ice on the water — and how warm it is for the
## birds and the crickets.
func _apply_seasons() -> void:
	var seasons := Config.seasons
	var at := Seasons.position(_clock.tick) if _clock != null else 1.5
	# (The year turns slowly: its colours are set anew only when it has moved.)
	if absf(at - season) > 0.002:
		season = at
		leaf_fall = Seasons.blend(seasons.leaf_fall, at)
		if _prop_material != null:
			_prop_material.set_shader_parameter(&"season_tint", Seasons.blend_color(seasons.foliage, at))
			_prop_material.set_shader_parameter(&"season_tint_other", Seasons.blend_color(seasons.foliage_other, at))
			_prop_material.set_shader_parameter(&"season_strength", Seasons.blend(seasons.foliage_strength, at))
			_prop_material.set_shader_parameter(&"bare", Seasons.blend(seasons.bare, at))
		if _terrain_material != null:
			_terrain_material.set_shader_parameter(&"season_ground", Seasons.blend_color(seasons.ground, at))
			_terrain_material.set_shader_parameter(&"season_strength", Seasons.blend(seasons.ground_strength, at))
	for material: ShaderMaterial in [_prop_material, _terrain_material]:
		if material != null:
			material.set_shader_parameter(&"snow", snow)
			material.set_shader_parameter(&"snow_color", seasons.snow_color)
	if _water_material != null:
		_water_material.set_shader_parameter(&"frozen", ice)
		_water_material.set_shader_parameter(&"ice_color", seasons.ice_color)
		var deep := Config.terrain_palette.water_deep_levels * Config.world.height_step
		_water_material.set_shader_parameter(&"ice_depth", clampf(seasons.ice_depth / deep, 0.0, 1.0) if deep > 0.0 else 1.0)
	if _ambient != null and _weather != null:
		_ambient.set_warmth(_weather.temperature(), _clock.season() if _clock != null else -1)
	# Leaves in the air: the rain's drops, few, slow and brown.
	var falling_leaves := leaf_fall > NOTHING and _drop_count > 0 and not reduced_motion
	if _leaves.visible != falling_leaves:
		_leaves.visible = falling_leaves
	if falling_leaves:
		var center := Vector2(_rig.pivot().x, _rig.pivot().z) if _rig != null else _box.get_center()
		var distance := _rig.distance() if _rig != null else 30.0
		_leaf_material.set_shader_parameter(&"area_center", center)
		_leaf_material.set_shader_parameter(&"area_size", clampf(distance * _config.area_per_distance, _config.area_min, _config.area_max))
		_leaf_material.set_shader_parameter(&"top", _top * 0.45)
		_leaf_material.set_shader_parameter(&"bottom", _bottom)
		_leaf_material.set_shader_parameter(&"fall_speed", 1.1)
		_leaf_material.set_shader_parameter(&"wind", blowing() * _config.wind_carry * 0.6)
		_leaf_material.set_shader_parameter(&"amount", leaf_fall * 0.35)
		_leaf_material.set_shader_parameter(&"snow", 1.0)
		_leaf_material.set_shader_parameter(&"flake_size", 0.09)
		_leaf_material.set_shader_parameter(&"tint", seasons.leaf_color)
		_leaf_material.set_shader_parameter(&"daylight", 1.0 - 0.75 * _day_night.night() if _day_night != null else 1.0)
		_leaf_material.set_shader_parameter(&"box_min", _box.position)
		_leaf_material.set_shader_parameter(&"box_max", _box.end)
		_leaves.custom_aabb = AABB(Vector3(_box.position.x, _bottom, _box.position.y), Vector3(_box.size.x, _top - _bottom, _box.size.y))


func leaves_node() -> MultiMeshInstance3D:
	return _leaves


## The drops: one quad, drawn as many times as the quality allows; where
## each is, is the shader's business.
func _build_drops(level: GraphicsQuality.Level) -> void:
	_drop_count = _config.drops_for(level)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.center_offset = Vector3(0.0, 0.5, 0.0)
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_custom_data = true
	mesh.mesh = quad
	mesh.instance_count = _drop_count
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261001
	for i in _drop_count:
		mesh.set_instance_transform(i, Transform3D.IDENTITY)
		mesh.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), float(i) / maxf(_drop_count, 1.0)))
	_rain.multimesh = mesh
	_leaves.multimesh = mesh # (the same drops, drawn as leaves)


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key == GraphicsQuality.SETTING:
		_build_drops(GraphicsQuality.current())
