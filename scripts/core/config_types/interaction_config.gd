class_name InteractionConfig
extends ConfigBase
## Gesture thresholds (bible §23.1, §33). Distances are in dp (density-independent pixels).

@export_range(100, 2000) var long_press_ms: int = 450
@export_range(100, 1000) var double_tap_ms: int = 300
@export_range(2.0, 48.0) var drag_slop_dp: float = 10.0
@export_range(8.0, 64.0) var touch_radius_dp: float = 24.0
## Release velocity above which a drag counts as a swipe.
@export_range(100.0, 5000.0) var swipe_min_velocity_dp_s: float = 900.0
## Hold time before a loose object is grabbed with the HAND tool.
@export_range(50, 1000) var grab_hold_ms: int = 200


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, double_tap_ms < long_press_ms, "double_tap_ms should be < long_press_ms")
	return p
