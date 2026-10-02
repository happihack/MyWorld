class_name WeatherFxConfig
extends ConfigBase
## What the weather looks and sounds like (bible §10.1, §28.2): rain and
## snow, the light under clouds, fog, lightning, wind in the trees.

@export_group("Rain and snow")
## Drops in the air at once, by graphics quality (low, medium, high).
@export var drops: PackedInt32Array = PackedInt32Array([350, 750, 1200])
## Precipitation (units an hour, see ClimateConfig) at which every drop falls.
@export_range(0.1, 20.0, 0.1) var full_precipitation: float = 3.0
## How fast rain and snow fall (world units a second), and how far the
## wind at its strongest carries them sideways in a second.
@export_range(0.5, 60.0, 0.5) var rain_speed: float = 15.0
@export_range(0.1, 20.0, 0.1) var snow_speed: float = 2.2
@export_range(0.0, 30.0, 0.5) var wind_carry: float = 7.0
## The square the drops fill around what the camera looks at: so many
## times the camera's distance, between these sides (world units).
@export_range(0.2, 5.0, 0.05) var area_per_distance: float = 1.5
@export_range(4.0, 200.0, 1.0) var area_min: float = 16.0
@export_range(4.0, 400.0, 1.0) var area_max: float = 90.0
@export var rain_color: Color = Color(0.80, 0.87, 0.96, 0.50)
@export var snow_color: Color = Color(1.0, 1.0, 1.0, 0.85)

@export_group("Light")
## Under a covered sky: what is left of the sun's light and of the
## shadows' darkness, and the grey the light turns to.
@export_range(0.0, 1.0, 0.01) var overcast_light: float = 0.42
@export_range(0.0, 1.0, 0.01) var overcast_shadows: float = 0.3
@export var overcast_color: Color = Color(0.66, 0.70, 0.76)
## How much of the grey gets into the light from everywhere, and the backdrop.
@export_range(0.0, 1.0, 0.01) var overcast_ambient: float = 0.55
## Fog at its thickest hides this share of what the camera looks at.
@export_range(0.0, 0.95, 0.01) var fog_haze: float = 0.5
@export var fog_color: Color = Color(0.72, 0.76, 0.80)
## How dark rain makes the ground, and how many seconds it takes to get
## wet and to dry.
@export_range(0.0, 1.0, 0.01) var wet_ground: float = 1.0
@export_range(0.5, 600.0, 0.5) var wetting_seconds: float = 12.0
@export_range(0.5, 600.0, 0.5) var drying_seconds: float = 45.0
## The sky changes over this many (real) seconds at Normal speed.
@export_range(0.1, 120.0, 0.1) var transition_seconds: float = 6.0

@export_group("Wind")
## How much the trees sway in a calm and in the strongest wind (times as usual).
@export_range(0.0, 5.0, 0.05) var sway_calm: float = 0.6
@export_range(0.0, 10.0, 0.05) var sway_storm: float = 3.2

@export_group("Lightning")
## In a storm: seconds between two flashes (a random time in this range),
## how bright a flash is, and how long after it the thunder comes.
@export_range(0.5, 120.0, 0.5) var lightning_min_seconds: float = 5.0
@export_range(0.5, 120.0, 0.5) var lightning_max_seconds: float = 16.0
@export_range(0.0, 10.0, 0.1) var flash_light: float = 2.6
@export_range(0.0, 10.0, 0.05) var thunder_min_seconds: float = 0.4
@export_range(0.0, 10.0, 0.05) var thunder_max_seconds: float = 2.2

@export_group("Sound")
@export_range(-60.0, 6.0, 0.5) var rain_volume_db: float = -15.0
## How much louder than usual the wind is at its strongest.
@export_range(0.0, 24.0, 0.5) var wind_gain_db: float = 10.0
@export_range(-60.0, 6.0, 0.5) var thunder_volume_db: float = -3.0


## How many drops there are at a graphics quality (GraphicsQuality.Level).
func drops_for(level: int) -> int:
	return drops[clampi(level, 0, drops.size() - 1)] if not drops.is_empty() else 0


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, drops.size() == 3, "drops needs a value for low, medium and high quality")
	_check(p, area_min <= area_max, "area_min must not be more than area_max")
	_check(p, lightning_min_seconds <= lightning_max_seconds, "lightning_min_seconds must not be more than lightning_max_seconds")
	_check(p, thunder_min_seconds <= thunder_max_seconds, "thunder_min_seconds must not be more than thunder_max_seconds")
	return p
