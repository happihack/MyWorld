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
## Two-finger gestures: finger distance must change this much before PINCH starts.
@export_range(0.0, 48.0) var pinch_slop_dp: float = 8.0
## Two-finger gestures: fingers must rotate this far before TWIST starts. Real
## fingers never keep a constant angle, so without this every pinch would also
## rotate the view.
@export_range(0.0, 90.0) var twist_start_deg: float = 12.0

@export_group("Hints")
## Idle seconds before the first hint ("Drag to explore.") appears.
@export_range(0.5, 60.0, 0.5) var hint_idle_seconds: float = 5.0
## Idle seconds before a follow-up hint appears once it has become relevant.
@export_range(0.5, 60.0, 0.5) var hint_follow_up_seconds: float = 2.5


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, double_tap_ms < long_press_ms, "double_tap_ms should be < long_press_ms")
	return p
