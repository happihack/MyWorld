class_name TouchFeedback
extends RefCounted
## What a touch of the world sounds and feels like (bible §23, §29): maps an
## InteractionResponse to a sound at the touched place and a vibration pulse.
## The visual side of the same response is WorldEffects.

## Haptic strengths (the values of Haptics.Strength).
const LIGHT := 0
const MEDIUM := 1
## Targets that give way less than this (boulders) are felt as a medium pulse.
const HEAVY_BELOW := 0.5

## effect -> [sound id, volume dB, pitch, haptic strength]
const CUES := {
	InteractionResponse.DUST: [&"thud", -5.0, 1.0, LIGHT],
	InteractionResponse.RIPPLE: [&"plip", -4.0, 1.0, LIGHT],
	InteractionResponse.TREE_SHAKE: [&"rustle", -6.0, 1.0, LIGHT],
	InteractionResponse.BUSH_RUSTLE: [&"rustle", -9.0, 1.3, LIGHT],
	InteractionResponse.ROCK_WOBBLE: [&"click", -6.0, 1.0, LIGHT],
	InteractionResponse.BUILDING_KNOCK: [&"knock", -4.0, 1.0, MEDIUM],
	InteractionResponse.FIRE_FLARE: [&"crackle", -6.0, 1.0, LIGHT],
	InteractionResponse.RUIN_HUM: [&"hum", -5.0, 1.0, MEDIUM],
}


## Hook for InteractionManager.responded.
static func play(response: InteractionResponse) -> void:
	if response == null:
		return
	if response.effect == InteractionResponse.INSPECT:
		# A long press opens a menu: a UI sound and a tick, nothing in the world.
		AudioManager.play_ui(&"ui_open")
		Haptics.light()
		return
	var cue: Array = CUES.get(response.effect, [])
	if cue.is_empty():
		return
	# Heavy things sound lower and are felt more; light things the opposite.
	var pitch: float = cue[2] * clampf(0.5 + 0.5 * response.strength, 0.6, 1.4)
	AudioManager.play_at(cue[0], response.position, cue[1], pitch)
	Haptics.pulse(MEDIUM if response.strength < HEAVY_BELOW else cue[3])


## A loose object came down at `at`. `give` says how heavy it is (see
## LooseObject.give), `impact_speed` how fast it fell (tiles/s).
static func landed(at: Vector3, give: float, impact_speed: float, on_water: bool) -> void:
	# A drop from carrying height arrives at about 5 tiles/s.
	var force := clampf(impact_speed / 5.0, 0.25, 1.3)
	var volume := -12.0 + 9.0 * force + (3.0 if give < HEAVY_BELOW else 0.0)
	var pitch := clampf(0.5 + 0.5 * give, 0.6, 1.4)
	AudioManager.play_at(&"plip" if on_water else &"thud", at, volume, pitch)
	Haptics.pulse(MEDIUM if give < HEAVY_BELOW else LIGHT)


## A moving loose object ran into a wall, a prop or another object at `speed`.
static func bumped(at: Vector3, give: float, speed: float) -> void:
	var force := clampf(speed / 5.0, 0.2, 1.2)
	AudioManager.play_at(&"click", at, -14.0 + 9.0 * force, clampf(0.5 + 0.5 * give, 0.6, 1.4))


## The sound id of an effect (&"" if it has none).
static func sound_for(effect: StringName) -> StringName:
	var cue: Array = CUES.get(effect, [])
	return cue[0] if not cue.is_empty() else &""
