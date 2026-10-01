class_name SaveConfig
extends ConfigBase
## Save cadence and safety (bible §31.9).

@export var save_root: String = "user://saves"
@export_range(10.0, 3600.0) var autosave_interval_s: float = 120.0
## After the player changed the world, it is saved once they have left it
## alone for this long...
@export_range(0.5, 120.0, 0.5) var save_quiet_s: float = 6.0
## ...or this long after the first unsaved change, if they never stop.
@export_range(1.0, 600.0, 1.0) var save_max_wait_s: float = 40.0
@export_range(1, 10) var backup_count: int = 2
## Lifecycle/auto saves of the same world closer together than this are skipped.
## Android fires focus-loss and pause back to back (and quit is followed by the
## world closing); saving twice would rotate a duplicate into the backups.
@export_range(0, 10000) var min_save_gap_ms: int = 500


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, save_root.begins_with("user://"), "save_root must be under user://")
	_check(p, backup_count >= 1, "backup_count must be >= 1 (never keep only one valid save)")
	_check(p, save_quiet_s <= save_max_wait_s, "save_quiet_s must be <= save_max_wait_s")
	return p
