class_name DayNightConfig
extends ConfigBase
## How the light changes over a day (bible §28.2, M6.2): when the sun rises
## and sets, how high it climbs, what colour sun, moon, air and backdrop are
## at each hour. Colours over the day are Gradients (0 = midnight … 0.5 =
## noon … 1 = midnight again); the sun's own colour runs from sunrise (0) to
## sunset (1). A gradient left empty in the resource uses the built-in one.

@export_group("Hours")
@export_range(0.0, 12.0, 0.25) var sunrise_hour: float = 5.5
@export_range(12.0, 24.0, 0.25) var sunset_hour: float = 20.5
## How long dawn and dusk take (hours): the light turns over this long, half
## before and half after the sun crosses the horizon.
@export_range(0.25, 4.0, 0.25) var twilight_hours: float = 1.5
## Lights in windows burn from dusk until this hour, and low after it.
@export_range(18.0, 30.0, 0.25) var lights_out_hour: float = 23.0
@export_range(0.0, 1.0, 0.05) var late_window_light: float = 0.3

@export_group("Sun")
## How high the sun stands at noon, and how low a sun (or moon) still casts
## its light from (degrees above the horizon): never grazing, or shadows
## would run across the whole box.
@export_range(20.0, 89.0, 1.0) var noon_elevation_degrees: float = 62.0
@export_range(5.0, 45.0, 1.0) var lowest_elevation_degrees: float = 24.0
## Where the sun rises and sets (degrees of yaw; it swings from one to the other).
@export_range(-180.0, 180.0, 1.0) var sunrise_yaw_degrees: float = 115.0
@export_range(-180.0, 180.0, 1.0) var sunset_yaw_degrees: float = -35.0
@export_range(0.0, 4.0, 0.05) var sun_energy: float = 1.2
## The sun's colour from rise (0) to set (1).
@export var sun_color: Gradient

@export_group("Moon")
@export var moon_color: Color = Color(0.62, 0.74, 1.0)
@export_range(0.0, 2.0, 0.01) var moon_energy: float = 0.34
@export_range(20.0, 89.0, 1.0) var moon_elevation_degrees: float = 52.0
@export_range(0.0, 1.0, 0.01) var moon_shadow_opacity: float = 0.45
@export_range(0.0, 1.0, 0.01) var sun_shadow_opacity: float = 0.72

@export_group("Air and backdrop")
## The colour of the light that comes from everywhere, over the 24 hours.
@export var ambient_color: Gradient
@export_range(0.0, 2.0, 0.01) var ambient_energy_day: float = 0.55
@export_range(0.0, 2.0, 0.01) var ambient_energy_night: float = 0.5
## The backdrop behind the table, over the 24 hours.
@export var background_color: Gradient
## How much of its daytime brightness the table keeps at night.
@export_range(0.0, 1.0, 0.01) var table_night_light: float = 0.32
## Cloud shadows at night, as a share of the day's.
@export_range(0.0, 1.0, 0.01) var cloud_shadows_at_night: float = 0.35

@export_group("Fire and windows")
@export var glow_color: Color = Color(1.0, 0.74, 0.36)
@export var fire_color: Color = Color(1.0, 0.5, 0.2)
## The campfire's light: by day, by night, how far it reaches (tiles), and
## how much it flickers.
@export_range(0.0, 8.0, 0.05) var fire_energy_day: float = 0.35
@export_range(0.0, 8.0, 0.05) var fire_energy_night: float = 2.6
@export_range(1.0, 20.0, 0.5) var fire_range: float = 7.0
@export_range(0.0, 1.0, 0.01) var fire_flicker: float = 0.18


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, sunrise_hour < sunset_hour, "sunrise_hour must be before sunset_hour")
	_check(p, twilight_hours < (sunset_hour - sunrise_hour), "twilight_hours must be shorter than the day")
	_check(p, lowest_elevation_degrees <= noon_elevation_degrees, "lowest_elevation_degrees must be <= noon_elevation_degrees")
	return p


## The sun's colour from rise to set: warm at both ends, near white at noon.
func sun_gradient() -> Gradient:
	if sun_color != null:
		return sun_color
	if _sun == null:
		_sun = _gradient([0.0, 0.12, 0.3, 0.7, 0.88, 1.0], [
			Color(1.0, 0.62, 0.36), Color(1.0, 0.82, 0.62), Color(1.0, 0.96, 0.88),
			Color(1.0, 0.96, 0.88), Color(1.0, 0.80, 0.56), Color(1.0, 0.55, 0.34)])
	return _sun


## The colour of the air over 24 hours: deep blue at night, rose at dawn,
## the cool sky of day, amber and violet at dusk.
func ambient_gradient() -> Gradient:
	if ambient_color != null:
		return ambient_color
	if _ambient == null:
		var night := Color(0.30, 0.40, 0.72)
		var day := Color(0.62, 0.69, 0.82)
		var rise := sunrise_hour / 24.0
		var fall := sunset_hour / 24.0
		var half := twilight_hours * 0.5 / 24.0
		_ambient = _gradient([0.0, rise - half, rise, rise + half * 1.6, fall - half * 1.6, fall, fall + half, 1.0], [
			night, night, Color(0.74, 0.60, 0.66), day, day, Color(0.78, 0.58, 0.56), night, night])
	return _ambient


## The backdrop over 24 hours: the dim room by day, nearly black at night.
func background_gradient() -> Gradient:
	if background_color != null:
		return background_color
	if _background == null:
		var night := Color(0.035, 0.05, 0.095)
		var day := Color(0.113725, 0.141176, 0.188235)
		var rise := sunrise_hour / 24.0
		var fall := sunset_hour / 24.0
		var half := twilight_hours * 0.5 / 24.0
		_background = _gradient([0.0, rise - half, rise + half, fall - half, fall + half, 1.0], [night, night, day, day, night, night])
	return _background


var _sun: Gradient
var _ambient: Gradient
var _background: Gradient


static func _gradient(offsets: Array, colors: Array) -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(offsets)
	gradient.colors = PackedColorArray(colors)
	return gradient
