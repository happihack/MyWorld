class_name FeedbackConfig
extends ConfigBase
## How the game answers through the speaker and the vibration motor
## (bible §29, §33, track T7).

@export_group("Haptics")
@export_range(1, 200) var haptic_light_ms: int = 14
@export_range(1, 200) var haptic_medium_ms: int = 24
@export_range(1, 400) var haptic_strong_ms: int = 48
## Vibration strength 0..1 per level (devices without amplitude control ignore it).
@export_range(0.0, 1.0, 0.01) var haptic_light_amplitude: float = 0.35
@export_range(0.0, 1.0, 0.01) var haptic_medium_amplitude: float = 0.6
@export_range(0.0, 1.0, 0.01) var haptic_strong_amplitude: float = 1.0
## Pulses closer together than this are dropped, unless the new one is stronger.
@export_range(0, 1000) var haptic_min_gap_ms: int = 60

@export_group("Sound")
## How many world sounds / UI sounds can play at once.
@export_range(1, 32) var world_voices: int = 8
@export_range(1, 16) var ui_voices: int = 4
## Camera distance (tiles) at which a world sound plays at full volume; further
## away it gets quieter, so a zoomed-out world is a quiet world.
@export_range(1.0, 200.0, 0.5) var full_volume_distance: float = 20.0
## Each world sound is played slightly higher or lower by up to this fraction.
@export_range(0.0, 0.5, 0.01) var pitch_variation: float = 0.07
@export_range(-40.0, 6.0, 0.5) var ui_volume_db: float = -12.0

@export_group("Ambience")
@export_range(-60.0, 0.0, 0.5) var wind_volume_db: float = -22.0
## The crickets of the night, at their loudest.
@export_range(-60.0, 0.0, 0.5) var crickets_volume_db: float = -26.0
## The fire crackles this often once it is dark (seconds between crackles), this loud.
@export_range(0.2, 60.0, 0.1) var crackle_min_seconds: float = 1.6
@export_range(0.2, 60.0, 0.1) var crackle_max_seconds: float = 5.0
@export_range(-60.0, 6.0, 0.5) var crackle_volume_db: float = -14.0
## At dawn the birds call this many times as often as during the day.
@export_range(1.0, 10.0, 0.1) var dawn_chorus: float = 3.5
## Seconds of quiet between bird calls (a random time in this range).
@export_range(0.5, 300.0, 0.5) var chirp_min_seconds: float = 14.0
@export_range(0.5, 300.0, 0.5) var chirp_max_seconds: float = 55.0
## Chance that another bird answers a call a moment later.
@export_range(0.0, 1.0, 0.01) var chirp_answer_chance: float = 0.3
@export_range(-40.0, 6.0, 0.5) var chirp_volume_db: float = -8.0
## Each call is quieter than chirp_volume_db by a random amount up to this.
@export_range(0.0, 24.0, 0.5) var chirp_volume_spread_db: float = 7.0
## Each call is played this much lower or higher (a random pitch in this range).
@export_range(0.5, 1.0, 0.01) var chirp_pitch_low: float = 0.78
@export_range(1.0, 2.0, 0.01) var chirp_pitch_high: float = 1.3


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, haptic_light_ms <= haptic_medium_ms and haptic_medium_ms <= haptic_strong_ms,
		"haptic durations should grow from light to strong")
	_check(p, chirp_min_seconds <= chirp_max_seconds, "chirp_min_seconds should be <= chirp_max_seconds")
	return p
