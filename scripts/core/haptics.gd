extends Node
## Autoload "Haptics": short vibration pulses that make touches feel physical
## (bible §29, track T7).
##
## Three strengths — light (a tick), medium (a knock), strong (a jolt). Pulses
## are rate limited so rapid tapping never becomes a buzz, and the player's
## "haptics/enabled" setting switches everything off.

enum Strength { LIGHT, MEDIUM, STRONG }

## What actually vibrates: Callable(duration_ms: int, amplitude: float).
## Tests replace it; on desktop the engine call simply does nothing.
var vibrate_action: Callable = func(duration_ms: int, amplitude: float) -> void:
	Input.vibrate_handheld(duration_ms, amplitude)

var enabled := true
## Counters for the debug overlay and tests.
var pulses_played := 0
var pulses_skipped := 0

var _last_ms := -1000000
var _last_strength: Strength = Strength.LIGHT


func _ready() -> void:
	enabled = bool(Settings.get_value(&"haptics/enabled"))
	Settings.setting_changed.connect(_on_setting_changed)


func light() -> bool:
	return pulse(Strength.LIGHT)


func medium() -> bool:
	return pulse(Strength.MEDIUM)


func strong() -> bool:
	return pulse(Strength.STRONG)


## Vibrates once. Returns false if the pulse was dropped (haptics off, or too
## soon after the last one). `now_ms` is for tests; by default the real clock.
func pulse(strength: Strength, now_ms: int = -1) -> bool:
	if not enabled:
		return false
	var now := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	if now - _last_ms < Config.feedback.haptic_min_gap_ms and strength <= _last_strength:
		pulses_skipped += 1
		return false
	_last_ms = now
	_last_strength = strength
	pulses_played += 1
	vibrate_action.call(duration_ms(strength), amplitude(strength))
	return true


static func duration_ms(strength: Strength) -> int:
	match strength:
		Strength.MEDIUM:
			return Config.feedback.haptic_medium_ms
		Strength.STRONG:
			return Config.feedback.haptic_strong_ms
	return Config.feedback.haptic_light_ms


static func amplitude(strength: Strength) -> float:
	match strength:
		Strength.MEDIUM:
			return Config.feedback.haptic_medium_amplitude
		Strength.STRONG:
			return Config.feedback.haptic_strong_amplitude
	return Config.feedback.haptic_light_amplitude


## Forgets the last pulse (tests).
func reset() -> void:
	_last_ms = -1000000
	_last_strength = Strength.LIGHT
	pulses_played = 0
	pulses_skipped = 0


func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key == &"haptics/enabled":
		enabled = bool(value)
