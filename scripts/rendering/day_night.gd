class_name DayNight
extends Node3D
## The light of the day (bible §28.2, M6.2): the sun rises, climbs and sets,
## the moon takes over, the air turns from rose to sky to amber to deep blue,
## windows light up at dusk and the campfire throws its glow on the night.
##
## It reads the hour from the world's clock and tells the lighting, the
## props' material (windows, flames) and the campfire's light what to be.
## What the light is at an hour is a pure function (state_at), so it can be
## tested without anything on screen.
##
## The view always looks down into the box, so there is no sky to hang a
## moon and stars in: the moon is the night's light, and the night is told by
## that light, the glow of the fire and the windows.


## What the light is at one moment.
class State:
	extends RefCounted
	var hour := 12.0
	## 0 in full day … 1 in full night.
	var night := 0.0
	## The light in the sky is the moon (else the sun).
	var is_moon := false
	## Rotation of the directional light (degrees), its colour, strength and
	## how dark its shadows are.
	var light_rotation := Vector3(-50.0, 40.0, 0.0)
	var light_color := Color.WHITE
	var light_energy := 1.2
	var shadow_opacity := 0.72
	var ambient_color := Color(0.62, 0.69, 0.82)
	var ambient_energy := 0.55
	var background := Color(0.11, 0.14, 0.19)
	## How brightly windows glow (0 … 1) and how strong the fire's light is.
	var window_light := 0.0
	var fire_energy := 0.0
	## What is left of the table's and the clouds' daytime strength (0 … 1).
	var table_light := 1.0
	var cloud_shadows := 1.0


## The hours of game time between two updates of the light at most (a
## fortieth of an hour is under a second at normal speed: nothing is seen to step).
const UPDATE_HOURS := 0.025
## How many houses can have their lights out apart from the others, and how
## far around a house's base its windows are looked for (tiles).
const DARK_HOUSES := 8
const HOUSE_RADIUS := 0.95

var _clock: GameClock
var _lighting: WorldLighting
var _prop_material: ShaderMaterial
var _cloud_materials: Array[ShaderMaterial] = []
var _cloud_strength := 0.2
var _fire: OmniLight3D
var _state := State.new()
var _dark_houses: Array[Vector3] = []
var _shown_hour := -100.0
var _flicker := 0.0
## Tests set this to hold the light at an hour whatever the clock says (< 0: follow the clock).
var forced_hour := -1.0


func _ready() -> void:
	_fire = OmniLight3D.new()
	_fire.name = "FireLight"
	_fire.shadow_enabled = false
	_fire.omni_attenuation = 1.4
	_fire.visible = false
	add_child(_fire)


## Wires the cycle to what it drives. `prop_material`: the props' shared
## material (windows and flames); `cloud_materials`: everything that carries
## cloud shadows.
func setup(lighting: WorldLighting, prop_material: ShaderMaterial, cloud_materials: Array[ShaderMaterial], cloud_strength: float) -> void:
	_lighting = lighting
	_prop_material = prop_material
	_cloud_materials = cloud_materials
	_cloud_strength = cloud_strength
	_shown_hour = -100.0


func bind(clock: GameClock) -> void:
	_clock = clock
	_shown_hour = -100.0
	refresh()


## Puts the fire's light on the campfire (or takes it away).
func set_fire(at: Vector3, lit: bool) -> void:
	_fire.position = at + Vector3(0.0, 0.45, 0.0)
	_fire.visible = lit
	_shown_hour = -100.0


## The houses whose lights are out (their base positions): everyone in them
## is asleep, or nobody lives there. At most DARK_HOUSES are told apart.
func set_dark_houses(houses: Array[Vector3]) -> void:
	if houses == _dark_houses:
		return
	_dark_houses = houses.duplicate()
	var slots: Array[Vector4] = []
	for i in DARK_HOUSES:
		slots.append(Vector4(houses[i].x, houses[i].y, houses[i].z, HOUSE_RADIUS) if i < houses.size() else Vector4.ZERO)
	if _prop_material != null:
		_prop_material.set_shader_parameter(&"lights_out", slots)


func dark_houses() -> Array[Vector3]:
	return _dark_houses


func state() -> State:
	return _state


## 0 in full day … 1 in full night, as shown now.
func night() -> float:
	return _state.night


func hour() -> float:
	if forced_hour >= 0.0:
		return forced_hour
	return _clock.hour() if _clock != null else 12.0


func fire_light() -> OmniLight3D:
	return _fire


func _process(delta: float) -> void:
	refresh()
	# The fire never burns evenly.
	if _fire.visible:
		_flicker += delta
		var config := Config.day_night
		var wobble := sin(_flicker * 11.0) * 0.5 + sin(_flicker * 17.3 + 1.7) * 0.3 + sin(_flicker * 5.1) * 0.2
		_fire.light_energy = _state.fire_energy * (1.0 + wobble * config.fire_flicker)


## Brings the light in line with the clock (cheap when the hour has hardly moved).
func refresh() -> void:
	var now := hour()
	if absf(now - _shown_hour) < UPDATE_HOURS:
		return
	_shown_hour = now
	_state = state_at(now, Config.day_night)
	if _lighting != null:
		_lighting.set_sun(_state.light_rotation, _state.light_color, _state.light_energy)
		_lighting.set_atmosphere(_state.ambient_color, _state.ambient_energy, _state.background, _state.table_light, _state.shadow_opacity)
	if _prop_material != null:
		_prop_material.set_shader_parameter(&"night_glow", _state.window_light)
		_prop_material.set_shader_parameter(&"glow_color", Config.day_night.glow_color)
		_prop_material.set_shader_parameter(&"flame_glow", lerpf(0.6, 2.2, _state.night))
	for material in _cloud_materials:
		material.set_shader_parameter(&"cloud_strength", _cloud_strength * _state.cloud_shadows)
	_fire.light_color = Config.day_night.fire_color
	_fire.omni_range = Config.day_night.fire_range
	_fire.light_energy = _state.fire_energy


# --- what the light is at an hour ---------------------------------------------------------------

## The light at `hour` (0 … 24).
static func state_at(hour: float, config: DayNightConfig) -> State:
	var s := State.new()
	var h := fposmod(hour, 24.0)
	s.hour = h
	s.night = night_at(h, config)
	var day_length := config.sunset_hour - config.sunrise_hour
	if h >= config.sunrise_hour and h <= config.sunset_hour:
		# The sun: up in the east, over the top, down in the west.
		var t := (h - config.sunrise_hour) / day_length
		var height := sin(t * PI)
		s.is_moon = false
		s.light_rotation = Vector3(-lerpf(config.lowest_elevation_degrees, config.noon_elevation_degrees, height),
			lerpf(config.sunrise_yaw_degrees, config.sunset_yaw_degrees, t), 0.0)
		s.light_color = config.sun_gradient().sample(t)
		# Strong all day; fading to nothing as it meets the horizon.
		s.light_energy = config.sun_energy * smoothstep(0.0, 0.12, height) * lerpf(0.78, 1.0, height)
		s.shadow_opacity = config.sun_shadow_opacity
	else:
		# The moon: the same journey through the night, lower and paler.
		var night_length := 24.0 - day_length
		var since := h - config.sunset_hour if h > config.sunset_hour else h + 24.0 - config.sunset_hour
		var t := since / night_length
		var height := sin(t * PI)
		s.is_moon = true
		s.light_rotation = Vector3(-lerpf(config.lowest_elevation_degrees, config.moon_elevation_degrees, height),
			lerpf(config.sunrise_yaw_degrees, config.sunset_yaw_degrees, t) + 180.0, 0.0)
		s.light_color = config.moon_color
		s.light_energy = config.moon_energy * smoothstep(0.0, 0.14, height)
		s.shadow_opacity = config.moon_shadow_opacity
	s.ambient_color = config.ambient_gradient().sample(h / 24.0)
	s.ambient_energy = lerpf(config.ambient_energy_day, config.ambient_energy_night, s.night)
	s.background = config.background_gradient().sample(h / 24.0)
	s.table_light = lerpf(1.0, config.table_night_light, s.night)
	s.cloud_shadows = lerpf(1.0, config.cloud_shadows_at_night, s.night)
	s.fire_energy = lerpf(config.fire_energy_day, config.fire_energy_night, s.night)
	# Windows are lit as it gets dark (which houses still have a light on is
	# the houses' business: see set_dark_houses).
	s.window_light = s.night
	return s


## How much it is night at `hour`: 0 in full day, 1 in full night, turning
## over the twilight around sunrise and sunset.
static func night_at(hour: float, config: DayNightConfig) -> float:
	var h := fposmod(hour, 24.0)
	var half := config.twilight_hours * 0.5
	var dawn := smoothstep(config.sunrise_hour - half, config.sunrise_hour + half, h)
	var dusk := smoothstep(config.sunset_hour - half, config.sunset_hour + half, h)
	return clampf(1.0 - dawn + dusk, 0.0, 1.0)
