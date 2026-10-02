class_name EventsConfig
extends ConfigBase
## The world's event log, what the player is told of it as it happens, and
## the statistics kept (bible §21, §26.7).

@export_group("Log")
## The most events kept. When there are more, old ones that matter little
## (and that nothing kept was caused by) make room.
@export_range(100, 100000) var max_events: int = 2000
## Events that matter at least this much are never dropped for room.
@export_range(0.0, 1.0, 0.01) var keep_significance: float = 0.5
## From this significance an event is "major" (EventBus.major_event_occurred).
@export_range(0.0, 1.0, 0.01) var major_from: float = 0.5
## A shortage looks this many game days back for what brought it about.
@export_range(0.0, 60.0, 0.5) var cause_window_days: float = 3.0

@export_group("Notifications")
## The player is told of events that matter at least this much...
@export_range(0.0, 1.0, 0.01) var notify_from: float = 0.5
## ...and, while the camera follows someone, only of those that matter this much.
@export_range(0.0, 1.0, 0.01) var high_from: float = 0.75
## At most this many toasts in a (real) minute.
@export_range(1, 60) var toasts_per_minute: int = 3
## The same kind of thing again within this many seconds is one toast.
@export_range(0.0, 600.0, 0.5) var merge_seconds: float = 20.0
## What has waited longer than this for its turn is not told any more
## (unless it matters a great deal).
@export_range(1.0, 600.0, 0.5) var stale_seconds: float = 45.0
## How long a toast stays, and how many are shown at once.
@export_range(1.0, 60.0, 0.5) var toast_seconds: float = 7.0
@export_range(1, 8) var max_toasts: int = 3

@export_group("Statistics")
## How often the world's numbers are written down, in game minutes, and how
## many samples are kept (the oldest go).
@export_range(1, 14400) var sample_minutes: int = 60
@export_range(10, 100000) var max_samples: int = 960


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, notify_from <= high_from, "notify_from must not be more than high_from")
	_check(p, toasts_per_minute >= 1 and max_toasts >= 1, "there must be room for a toast")
	_check(p, sample_minutes >= 1 and max_samples >= 10, "statistics need an interval and room")
	return p
