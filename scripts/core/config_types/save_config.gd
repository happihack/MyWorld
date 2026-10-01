class_name SaveConfig
extends ConfigBase
## Save cadence and safety (bible §31.9).

@export var save_root: String = "user://saves"
@export_range(10.0, 3600.0) var autosave_interval_s: float = 120.0
@export_range(1, 10) var backup_count: int = 2


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, save_root.begins_with("user://"), "save_root must be under user://")
	_check(p, backup_count >= 1, "backup_count must be >= 1 (never keep only one valid save)")
	return p
