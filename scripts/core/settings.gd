extends Node
## Autoload "Settings": player settings, persisted separately from worlds (bible §31.4).
##
## Keys are "section/name" StringNames, e.g. Settings.get_value(&"haptics/enabled").
## Writes are debounced and saved atomically to user://settings.cfg.

signal setting_changed(key: StringName, value: Variant)

const PATH := "user://settings.cfg"
const SAVE_DEBOUNCE_S := 0.5

## Every valid key and its default. The default's type is the key's type.
const DEFAULTS := {
	&"audio/master": 1.0,
	&"audio/ambience": 1.0,
	&"audio/sfx": 1.0,
	&"audio/ui": 1.0,
	&"audio/muted": false,
	&"haptics/enabled": true,
	&"motion/enabled": true,
	&"motion/tilt_sensitivity": 1.0,
	&"motion/shake_sensitivity": 1.0,
	&"motion/rotation_sensitivity": 1.0,
	&"motion/calibrated": false,
	&"motion/baseline_gravity": Vector3.ZERO,
	&"accessibility/ui_scale": 1.0,
	&"accessibility/text_scale": 1.0,
	&"accessibility/reduced_motion": false,
	&"accessibility/high_contrast": false,
	&"graphics/quality": "auto",
	&"graphics/fps_cap": 60,
	&"gameplay/gentle_hands": true,
	&"notifications/system_enabled": false,
	&"debug/enabled": false,
	&"debug/overlay_visible": false,
}

var _values: Dictionary = {}
var _dirty := false
var _save_pending := false


func _ready() -> void:
	_values = DEFAULTS.duplicate()
	load_from_disk()


func get_value(key: StringName) -> Variant:
	if not DEFAULTS.has(key):
		Log.error(Log.Category.UI, "Unknown setting", {"key": key})
		return null
	return _values.get(key, DEFAULTS[key])


## Returns false (and changes nothing) for unknown keys or wrong value types.
func set_value(key: StringName, value: Variant) -> bool:
	if not DEFAULTS.has(key):
		Log.error(Log.Category.UI, "Unknown setting", {"key": key})
		return false
	var coerced: Variant = _coerce(value, DEFAULTS[key])
	if coerced == null:
		Log.error(Log.Category.UI, "Wrong type for setting", {"key": key, "value": value})
		return false
	if _values.get(key) == coerced:
		return true
	_values[key] = coerced
	setting_changed.emit(key, coerced)
	_schedule_save()
	return true


func reset_to_defaults() -> void:
	for key: StringName in DEFAULTS:
		set_value(key, DEFAULTS[key])


func load_from_disk() -> void:
	if not FileAccess.file_exists(PATH):
		Log.info(Log.Category.CORE, "No settings file; using defaults")
		return
	var cfg := ConfigFile.new()
	var err := cfg.load(PATH)
	if err != OK:
		Log.warn(Log.Category.CORE, "Settings unreadable; using defaults", {"error": error_string(err)})
		return
	for key: StringName in DEFAULTS:
		var parts := String(key).split("/", true, 1)
		if not cfg.has_section_key(parts[0], parts[1]):
			continue
		var coerced: Variant = _coerce(cfg.get_value(parts[0], parts[1]), DEFAULTS[key])
		if coerced == null:
			Log.warn(Log.Category.CORE, "Ignoring invalid saved setting", {"key": key})
			continue
		_values[key] = coerced
	Log.info(Log.Category.CORE, "Settings loaded")


## Writes immediately if anything changed. Called on pause/quit and after the debounce.
func flush() -> void:
	_save_pending = false
	if not _dirty:
		return
	var cfg := ConfigFile.new()
	for key: StringName in _values:
		var parts := String(key).split("/", true, 1)
		cfg.set_value(parts[0], parts[1], _values[key])
	# Write to a temp file, then replace, so a crash never leaves a half-written file.
	var tmp := PATH + ".tmp"
	var err := cfg.save(tmp)
	if err == OK:
		err = DirAccess.rename_absolute(tmp, PATH)
	if err != OK:
		Log.error(Log.Category.SAVE, "Settings save failed", {"error": error_string(err)})
		return
	_dirty = false


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_PREDELETE:
			flush()


func _schedule_save() -> void:
	_dirty = true
	if _save_pending or not is_inside_tree():
		return
	_save_pending = true
	get_tree().create_timer(SAVE_DEBOUNCE_S).timeout.connect(flush)


## Converts value to the default's type; null if incompatible. Allows int <-> float.
static func _coerce(value: Variant, default: Variant) -> Variant:
	var want := typeof(default)
	var have := typeof(value)
	if have == want:
		return value
	if want == TYPE_FLOAT and have == TYPE_INT:
		return float(value)
	if want == TYPE_INT and have == TYPE_FLOAT:
		return int(value)
	if want == TYPE_STRING and have == TYPE_STRING_NAME:
		return String(value)
	return null
