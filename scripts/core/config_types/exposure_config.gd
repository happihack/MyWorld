class_name ExposureConfig
extends ConfigBase
## What the weather and the river do to people's lives (bible §10.1, M9.6):
## when they go in out of it, how the cold gets into them, how heat slows
## their work, what the fire burns in the cold, and what a flood does to a
## settlement.

@export_group("Shelter")
## How strongly each kind of weather drives people indoors, 0 … 1.
@export var pull_by_weather: Dictionary = {&"rain": 0.4, &"heavy_rain": 0.7, &"storm": 1.0, &"snow": 0.4}
## The cold does too: from this temperature down (°C), fully so many degrees below it — at most this much.
@export_range(-30.0, 20.0, 0.5) var cold_pull_from: float = 0.0
@export_range(1.0, 40.0, 0.5) var cold_pull_span: float = 12.0
@export_range(0.0, 1.0, 0.05) var cold_pull_most: float = 0.8
## What a full pull adds to "go home" …
@export_range(0.0, 3.0, 0.05) var shelter_weight: float = 0.45
## … and how much of their worth it takes from work, and from what else is done out of doors.
@export_range(0.0, 1.0, 0.05) var work_cut: float = 0.5
@export_range(0.0, 1.0, 0.05) var outdoor_cut: float = 0.75
## From this much pull, going home is "taking shelter" (indoors, out of sight), for this long (game minutes).
@export_range(0.0, 1.0, 0.05) var shelter_from: float = 0.3
@export var shelter_minutes: Vector2 = Vector2(40.0, 90.0)

@export_group("Cold")
## Below this temperature (°C) someone who is not warm is getting cold.
@export_range(-30.0, 20.0, 0.5) var cold_from: float = -5.0
## Indoors is warm — unless the fire is out and it is colder than this.
@export_range(-40.0, 10.0, 0.5) var deep_cold: float = -8.0
## By the burning fire (within so many tiles) it is warm too.
@export_range(0.5, 12.0, 0.5) var fire_radius: float = 3.5
## So many game minutes of getting cold and they are ill with it; warmth
## takes the cold out of them this many times as fast as it got in.
@export_range(10.0, 5000.0, 10.0) var cold_sick_after_minutes: float = 420.0
@export_range(0.5, 10.0, 0.1) var warm_recover_factor: float = 2.0

@export_group("Heat")
## Work goes slower above this temperature (°C): by `heat_slow` at so many degrees more.
@export_range(10.0, 45.0, 0.5) var heat_from: float = 26.0
@export_range(1.0, 30.0, 0.5) var heat_span: float = 8.0
@export_range(0.0, 0.9, 0.05) var heat_slow: float = 0.4

@export_group("The fire in the cold")
## Below this temperature (°C) the fire burns more wood: `fire_cold_extra`
## times as much again at so many degrees less.
@export_range(-20.0, 25.0, 0.5) var fire_cold_from: float = 5.0
@export_range(1.0, 40.0, 0.5) var fire_cold_span: float = 15.0
@export_range(0.0, 4.0, 0.05) var fire_cold_extra: float = 1.0

@export_group("Flood")
## What a flood takes of the food lying in it in an hour, and of the wood (it floats away).
@export_range(0.0, 1.0, 0.01) var flood_food_share_per_hour: float = 0.04
@export_range(0.0, 1.0, 0.01) var flood_wood_share_per_hour: float = 0.03
## A hut the water has stood in is rebuilt on higher ground: it costs this
## much wood (and the fire's wood for the day must be left), is looked for
## within so many tiles of the fire, and stands this far from the next building.
@export_range(0, 100) var move_wood: int = 8
@export_range(2.0, 40.0, 0.5) var move_radius: float = 16.0
@export_range(1, 6) var move_spacing: int = 2

@export_group("What nature does, noticed")
## How far a storm, the rain coming back, or a flood is noticed (tiles).
@export_range(1.0, 200.0, 1.0) var natural_radius: float = 40.0


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, shelter_minutes.x > 0.0 and shelter_minutes.y >= shelter_minutes.x, "shelter_minutes must be a range of more than nothing")
	_check(p, deep_cold <= cold_from, "deep_cold must not be warmer than cold_from")
	_check(p, heat_slow < 1.0, "heat_slow must leave some work")
	for kind: Variant in pull_by_weather:
		_check(p, WeatherSystem.STATES.has(StringName(str(kind))), "pull_by_weather: %s is no weather" % kind)
	return p
