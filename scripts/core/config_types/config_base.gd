class_name ConfigBase
extends Resource
## Base class for tunable configuration resources in res://data/configuration/.
## Subclasses override validate() to report out-of-range values.


## Returns human-readable problems; empty means valid.
func validate() -> PackedStringArray:
	return PackedStringArray()


static func _check(problems: PackedStringArray, ok: bool, message: String) -> void:
	if not ok:
		problems.append(message)
