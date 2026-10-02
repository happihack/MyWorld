class_name MotionConfig
extends ConfigBase
## The device's motion sensors: how tilt is read and how a shake is told
## from a bump (bible §23.5, §23.6, §31.11).

@export_group("Sampling")
## The sensors are read this many times a second (while they are read at all).
@export_range(5, 120) var sample_hz: int = 30
## This many readings of nothing but zeros in a row: the device has no such sensor.
@export_range(2, 600) var unavailable_after_samples: int = 30
## Without sensors it is looked again this often (seconds), in case they come.
@export_range(0.5, 60.0, 0.5) var probe_seconds: float = 3.0

@export_group("Tilt")
## Tilt below this many degrees is no tilt.
@export_range(0.0, 20.0, 0.5) var dead_zone_degrees: float = 4.0
## Tilt beyond this many degrees counts no more than this.
@export_range(5.0, 80.0, 0.5) var clamp_degrees: float = 25.0
## How quickly the tilt follows the device (seconds to close most of the gap).
@export_range(0.0, 2.0, 0.01) var smoothing_seconds: float = 0.12
## Gravity is about 9.8 m/s²: a reading outside these is no gravity (a
## glitch, or the device being thrown about) and is not used.
@export_range(0.0, 9.0, 0.1) var gravity_min: float = 5.0
@export_range(10.0, 40.0, 0.1) var gravity_max: float = 15.0
## A reading that turns the device by more than this many degrees at once
## is a spike — unless the next few say the same.
@export_range(5.0, 180.0, 1.0) var spike_degrees: float = 50.0
@export_range(1, 30) var spike_samples: int = 3
## Not calibrated by the player: the way the device is held in the first
## moments counts as level. Seconds of readings that go into it.
@export_range(0.05, 5.0, 0.05) var auto_baseline_seconds: float = 0.5
## Which way the axes run (to be set right on a device that reads otherwise).
@export var invert_x: bool = false
@export var invert_y: bool = false

@export_group("Calibration")
## "Hold still": so many seconds of readings, none of them further than
## this many degrees from what the others say.
@export_range(0.2, 10.0, 0.1) var calibration_hold_seconds: float = 1.5
@export_range(0.1, 20.0, 0.1) var calibration_spread_degrees: float = 2.0
## "Place your phone flat": within this many degrees of lying flat, face up.
@export_range(1.0, 45.0, 0.5) var calibration_flat_degrees: float = 10.0

@export_group("Touch tilt")
## Two fingers dragged this far (the UI's units; the screen is 1080 wide)
## tilt the box as far as it goes.
@export_range(40.0, 2000.0, 1.0) var touch_tilt_reach: float = 320.0
## How quickly a touch tilt follows the fingers, and comes back level when
## they are lifted (degrees a second).
@export_range(1.0, 2000.0, 1.0) var touch_tilt_speed: float = 240.0

@export_group("Shake")
## The window a shake is judged over, in milliseconds.
@export_range(100, 3000) var window_ms: int = 600
## What moves slower than this (seconds) is the device being turned, not shaken.
@export_range(0.02, 2.0, 0.01) var high_pass_seconds: float = 0.25
## Without a gravity sensor, gravity is the acceleration smoothed over this long.
@export_range(0.05, 5.0, 0.05) var gravity_estimate_seconds: float = 0.6
## Movement below this (m/s²) is not part of a shake; quiet for this long
## (milliseconds) and the shake is over.
@export_range(0.1, 20.0, 0.1) var quiet_below: float = 1.8
@export_range(20, 2000) var quiet_ms: int = 220
## Two changes of direction closer together than this (milliseconds) are
## one (the ringing of a knock is no shaking).
@export_range(0, 500) var reversal_min_gap_ms: int = 45
## For each class (light, medium, strong, extreme): the peak it takes
## (m/s²), the changes of direction, and how long it must go on (ms).
@export var peak_from: PackedFloat32Array = PackedFloat32Array([3.5, 9.0, 16.0, 26.0])
@export var reversals_from: PackedInt32Array = PackedInt32Array([2, 2, 3, 4])
@export var duration_from_ms: PackedInt32Array = PackedInt32Array([150, 200, 350, 500])
## After a shake of a class, none of that class for this many seconds.
@export var cooldown_seconds: PackedFloat32Array = PackedFloat32Array([1.5, 5.0, 20.0, 60.0])

@export_group("Virtual sensors")
## The tilt the keys (I J K L) and the debug stick stand for at their most, in degrees.
@export_range(1.0, 60.0, 0.5) var virtual_tilt_degrees: float = 18.0
## How quickly a virtual tilt comes and goes (degrees a second).
@export_range(1.0, 720.0, 1.0) var virtual_tilt_speed: float = 60.0
## The shaking a key press stands for: so many swings to and fro a second.
@export_range(1.0, 15.0, 0.5) var virtual_shake_hz: float = 5.0


func sample_seconds() -> float:
	return 1.0 / maxf(float(sample_hz), 1.0)


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, dead_zone_degrees < clamp_degrees, "dead_zone_degrees must be less than clamp_degrees")
	_check(p, gravity_min < 9.8 and gravity_max > 9.8, "gravity_min and gravity_max must lie around 9.8")
	_check(p, peak_from.size() == 4 and reversals_from.size() == 4 and duration_from_ms.size() == 4 and cooldown_seconds.size() == 4,
		"the shake classes need four values each")
	for i in range(1, mini(peak_from.size(), 4)):
		_check(p, peak_from[i] > peak_from[i - 1], "peak_from must rise from class to class")
	_check(p, quiet_below < (peak_from[0] if peak_from.size() > 0 else 1.0), "quiet_below must be less than the lightest shake")
	return p
