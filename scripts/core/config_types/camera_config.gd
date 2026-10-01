class_name CameraConfig
extends ConfigBase
## Camera rig tunables (bible §26.4, spec §7).

## Vertical field of view. Narrow = a "miniature" look with little perspective.
@export_range(10.0, 75.0, 0.5) var fov_degrees: float = 32.0
## Camera pitch (degrees above the horizon) when the whole box is in view...
@export_range(20.0, 89.0, 0.5) var pitch_far_degrees: float = 54.0
## ...and when zoomed all the way in (lower = looking more across the world).
@export_range(15.0, 89.0, 0.5) var pitch_near_degrees: float = 38.0
## Closest zoom: distance from the camera to the point it looks at, in tiles.
@export_range(2.0, 40.0, 0.5) var min_distance: float = 7.0
## Extra room around the box when it is framed (1.0 = touching the screen edges).
@export_range(1.0, 1.5, 0.01) var fit_margin: float = 1.06
## How far (tiles) the view may look past the edge of the world when zoomed in.
@export_range(0.0, 16.0, 0.5) var edge_margin_tiles: float = 2.0
## Speed of animated moves (frame, focus). Higher = snappier.
@export_range(1.0, 30.0, 0.5) var smoothing: float = 9.0
## Height the camera looks at when the whole box is in view.
@export_range(0.0, 8.0, 0.1) var base_look_height: float = 1.0

@export_group("Feel")
## How quickly a fling slows down (per second). Higher = stops sooner.
@export_range(0.5, 20.0, 0.1) var fling_friction: float = 4.2
## A release slower than this (viewport units per second) does not fling.
@export_range(0.0, 2000.0, 10.0) var fling_min_speed: float = 180.0
## How far the view can be dragged past the edge, as a fraction of what is on
## screen, before it stops giving. It springs back when released.
@export_range(0.0, 0.5, 0.01) var rubber_band: float = 0.14
## Zoom factor of one double tap.
@export_range(1.1, 6.0, 0.1) var double_tap_zoom: float = 2.4
## Distance the Home button views the settlement from.
@export_range(4.0, 120.0, 0.5) var home_distance: float = 24.0


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, pitch_near_degrees <= pitch_far_degrees, "pitch_near_degrees must be <= pitch_far_degrees")
	_check(p, min_distance > 0.0, "min_distance must be > 0")
	return p
