class_name ReactionTable
extends ConfigBase
## The numbers behind how people take what happens to them (bible §14):
## how strong each kind of stimulus is, what speaks for each interpretation,
## which feelings an interpretation brings, and which reaction a feeling
## leads to. Loaded from data/configuration/reactions.tres (Config.reactions).
##
## Traits are keyed by Traits.Axis (bipolar axes count -1 … +1, amounts are
## centred so that 0.5 counts as 0).

# --- interpretations (ids) ----------------------------------------------------------------
const NATURAL := &"natural"
const SPIRIT := &"spirit"
const DEITY := &"deity"
const ANCESTOR := &"ancestor"
const EXPERIMENT := &"experiment"
const UNKNOWN_INTELLIGENCE := &"unknown_intelligence"
const MULTIPLE_ENTITIES := &"multiple_entities"
const HALLUCINATION := &"hallucination"
const PHYSICS := &"physics"
## Only for someone asleep: it was a dream.
const DREAM := &"dream"
## The order is the order of PersonData.beliefs (part of the save format:
## append, never reorder).
const INTERPRETATIONS: Array[StringName] = [NATURAL, SPIRIT, DEITY, ANCESTOR, EXPERIMENT, UNKNOWN_INTELLIGENCE,
	MULTIPLE_ENTITIES, HALLUCINATION, PHYSICS, DREAM]

# --- emotions (indices) ---------------------------------------------------------------------
enum Emotion { FEAR, CURIOSITY, AWE, JOY, ANNOYANCE }
const EMOTION_COUNT := 5
const EMOTION_NAMES: Array[StringName] = [&"fear", &"curiosity", &"awe", &"joy", &"annoyance"]

# --- reactions (ids) ------------------------------------------------------------------------
const LOOK := &"look"
const INVESTIGATE := &"investigate"
const FREEZE := &"freeze"
const RUN := &"run"
const YELL := &"yell"
const LAUGH := &"laugh"
const WAVE := &"wave"
const PRAY := &"pray"
const DISMISS := &"dismiss"
const TELL := &"tell"
## What a listener does (not chosen for a stimulus of one's own).
const LISTEN := &"listen"
## What a sleeper does who takes it for a dream: stirs, and sleeps on.
const STIR := &"stir"
const REACTIONS: Array[StringName] = [LOOK, INVESTIGATE, FREEZE, RUN, YELL, LAUGH, WAVE, PRAY, DISMISS, TELL]

@export_group("Stimuli")
## Per stimulus type: [intensity at its least, intensity at its most, radius
## in tiles, anomalous, large, weatherlike].
@export var stimuli: Dictionary = {
	&"touch": [0.8, 0.8, 0.0, true, false, false],
	&"ground_touched": [0.16, 0.16, 3.0, true, false, false],
	&"knock": [0.3, 0.3, 5.0, true, false, false],
	&"tree_shaken": [0.38, 0.38, 6.5, true, false, true],
	&"tree_uprooted": [0.95, 0.95, 11.0, true, true, false],
	&"water_disturbed": [0.3, 0.3, 5.0, true, false, true],
	&"object_lifted": [0.45, 0.8, 8.0, true, false, false],
	&"object_moved": [0.5, 0.9, 9.0, true, false, false],
	&"water_taken": [0.4, 0.75, 7.0, true, true, false],
	&"water_poured": [0.45, 0.85, 8.0, true, true, true],
	&"rain_from_clear_sky": [0.5, 0.9, 9.0, true, true, true],
	&"rain_fell": [0.18, 0.35, 9.0, false, true, true],
	&"sourceless_wind": [0.4, 0.75, 9.0, true, false, true],
	&"ground_carved": [0.5, 0.5, 8.0, true, false, false],
	&"thunderstorm": [0.45, 0.45, 40.0, false, true, true],
	&"rain_returned": [0.3, 0.3, 40.0, false, true, true],
	&"flood": [0.8, 0.8, 40.0, false, true, false],
	&"object_found": [0.3, 0.5, 0.0, true, false, false],
	# The disasters (DisasterSystem): the eclipse and the blood are seen everywhere.
	&"earthquake": [0.9, 0.9, 40.0, false, true, false],
	&"eclipse": [0.85, 0.85, 400.0, true, true, false],
	&"tornado": [0.9, 0.9, 30.0, false, true, true],
	&"blood_water": [0.95, 0.95, 400.0, true, true, false],
	&"meteors": [0.95, 0.95, 40.0, true, true, false],
}

@export_group("Perception")
## Below this salience a stimulus goes unnoticed.
@export_range(0.0, 1.0, 0.01) var notice_threshold: float = 0.12
## At the very edge of its radius a stimulus still counts this much.
@export_range(0.0, 1.0, 0.01) var edge_proximity: float = 0.2
@export_range(0.0, 3.0, 0.05) var anomaly_factor: float = 1.5
@export_range(0.0, 3.0, 0.05) var ordinary_factor: float = 0.7
## How much of what happens around them people take in, by what they are at.
@export_range(0.0, 1.0, 0.01) var attention_asleep: float = 0.1
## A knock on the wall they sleep behind gets through this many times better.
@export_range(1.0, 10.0, 0.1) var own_wall_factor: float = 3.5
@export_range(0.0, 1.0, 0.01) var attention_working: float = 0.7
@export_range(0.0, 1.0, 0.01) var attention_walking: float = 0.85
@export_range(0.0, 1.0, 0.01) var attention_reacting: float = 0.6

@export_group("Interpretation")
## What speaks for an interpretation in a person's nature: axis -> weight.
@export var interpretation_traits: Dictionary = {
	&"natural": {Traits.Axis.SPIRITUALITY: -0.75, Traits.Axis.INTELLIGENCE: 0.2, Traits.Axis.CURIOSITY: -0.1},
	&"spirit": {Traits.Axis.SPIRITUALITY: 0.7, Traits.Axis.CREATIVITY: 0.25, Traits.Axis.BRAVERY: -0.1},
	&"deity": {Traits.Axis.SPIRITUALITY: 0.75, Traits.Axis.LOYALTY: 0.2, Traits.Axis.SUSPICION: -0.15},
	&"ancestor": {Traits.Axis.SPIRITUALITY: 0.45, Traits.Axis.LOYALTY: 0.4, Traits.Axis.ADVENTURE: -0.15},
	&"experiment": {Traits.Axis.INTELLIGENCE: 0.6, Traits.Axis.SUSPICION: 0.3, Traits.Axis.SPIRITUALITY: -0.3},
	&"unknown_intelligence": {Traits.Axis.CURIOSITY: 0.45, Traits.Axis.INTELLIGENCE: 0.5, Traits.Axis.SUSPICION: 0.2},
	&"multiple_entities": {Traits.Axis.CREATIVITY: 0.4, Traits.Axis.SUSPICION: 0.3},
	&"hallucination": {Traits.Axis.SPIRITUALITY: -0.5, Traits.Axis.SUSPICION: 0.2, Traits.Axis.BRAVERY: 0.15},
	&"physics": {Traits.Axis.INTELLIGENCE: 0.7, Traits.Axis.SPIRITUALITY: -0.4, Traits.Axis.CURIOSITY: 0.3},
	&"dream": {Traits.Axis.CREATIVITY: 0.25},
}
## What speaks for an interpretation in the circumstances: feature -> weight.
## "asleep": they were sleeping when it happened.
## Features (each 0 … 1): "ordinary" (not anomalous), "large", "local",
## "weatherlike", "intense", "faint", "direct" (it happened to me), "alone"
## (nobody else noticed), "tired", "familiar" (it has happened before), "child".
@export var interpretation_context: Dictionary = {
	&"natural": {&"ordinary": 1.2, &"weatherlike": 0.45, &"faint": 0.3, &"direct": -0.15, &"intense": -0.3},
	&"spirit": {&"local": 0.2, &"direct": 0.1, &"weatherlike": 0.1},
	&"deity": {&"large": 0.5, &"intense": 0.3, &"local": -0.1, &"direct": 0.15},
	&"ancestor": {&"direct": 0.3, &"local": 0.15},
	&"experiment": {&"familiar": 0.5},
	&"unknown_intelligence": {&"familiar": 0.5, &"direct": 0.25, &"child": -0.2},
	&"multiple_entities": {&"familiar": 0.3},
	&"hallucination": {&"alone": 0.3, &"direct": 0.1, &"faint": 0.45, &"tired": 0.5, &"intense": -0.5, &"large": -0.6, &"familiar": -0.3},
	&"physics": {&"familiar": 0.3, &"large": 0.2},
	&"dream": {&"asleep": 1.75, &"intense": -0.6, &"large": -0.6, &"familiar": -0.2},
}
## What every interpretation starts with (before culture, nature, evidence).
@export var interpretation_base: Dictionary = {
	&"natural": 0.3, &"spirit": 0.3, &"deity": 0.2, &"ancestor": 0.15, &"experiment": 0.0,
	&"unknown_intelligence": 0.15, &"multiple_entities": 0.0, &"hallucination": 0.1, &"physics": 0.1,
	&"dream": 0.3,
}
## What a person has to know for an interpretation to occur to them
## (PersonData.knowledge keys); "" = nothing. "death" = someone of theirs
## has died; "asleep" = only while sleeping; "never" = not yet in the world at all.
@export var interpretation_gates: Dictionary = {
	&"natural": "", &"spirit": "", &"deity": "", &"hallucination": "", &"unknown_intelligence": "",
	&"ancestor": "death", &"experiment": "scientific_method", &"physics": "natural_philosophy",
	&"multiple_entities": "never", &"dream": "asleep",
}
## How far a settlement's own leanings can go (they come from the world's seed).
@export_range(0.0, 2.0, 0.01) var culture_prior_spread: float = 0.35
## How much a person's own convictions (PersonData.beliefs) weigh: what they
## have made of things before, they tend to make of them again.
@export_range(0.0, 3.0, 0.05) var evidence_weight: float = 0.9
## How much the convictions of those close to them weigh.
@export_range(0.0, 3.0, 0.05) var social_weight: float = 0.35
## How much being told that it was so weighs (less for the suspicious).
@export_range(0.0, 3.0, 0.05) var told_weight: float = 1.0
## Children have weak priors: culture and conviction count this much for them.
@export_range(0.0, 1.0, 0.05) var child_prior_factor: float = 0.4
## How even-handed the draw is (higher = less predictable), before a person's own temperature.
@export_range(0.02, 2.0, 0.01) var interpretation_temperature: float = 0.35
## How much one experience moves a conviction, and how much the others fade.
@export_range(0.0, 1.0, 0.01) var belief_gain: float = 0.22
@export_range(0.0, 1.0, 0.01) var belief_fade: float = 0.06

@export_group("Emotion")
## What an interpretation makes people feel, before their nature has its say:
## [fear, curiosity, awe, joy, annoyance].
@export var interpretation_emotions: Dictionary = {
	&"natural": [0.1, 0.25, 0.0, 0.05, 0.1],
	&"spirit": [0.4, 0.4, 0.45, 0.15, 0.0],
	&"deity": [0.3, 0.2, 0.8, 0.3, 0.0],
	&"ancestor": [0.2, 0.3, 0.6, 0.35, 0.0],
	&"experiment": [0.3, 0.6, 0.1, 0.0, 0.3],
	&"unknown_intelligence": [0.4, 0.75, 0.25, 0.05, 0.1],
	&"multiple_entities": [0.5, 0.5, 0.3, 0.0, 0.1],
	&"hallucination": [0.15, 0.1, 0.0, 0.0, 0.25],
	&"physics": [0.1, 0.8, 0.15, 0.1, 0.0],
	&"dream": [0.05, 0.1, 0.15, 0.1, 0.0],
}
## What a person's nature adds to each feeling: emotion -> {axis -> weight}.
@export var emotion_traits: Dictionary = {
	&"fear": {Traits.Axis.BRAVERY: -0.45, Traits.Axis.SUSPICION: 0.12},
	&"curiosity": {Traits.Axis.CURIOSITY: 0.45, Traits.Axis.INTELLIGENCE: 0.2, Traits.Axis.ADVENTURE: 0.1},
	&"awe": {Traits.Axis.SPIRITUALITY: 0.35, Traits.Axis.CREATIVITY: 0.1},
	&"joy": {Traits.Axis.SUSPICION: -0.25, Traits.Axis.SOCIABILITY: 0.12},
	&"annoyance": {Traits.Axis.AGGRESSION: 0.35, Traits.Axis.SUSPICION: 0.12},
}
## What being a child adds: [fear, curiosity, awe, joy, annoyance].
@export var child_emotions: PackedFloat32Array = PackedFloat32Array([0.0, 0.3, -0.1, 0.45, -0.1])
## How quickly what was frightening and wondrous wears off: after n earlier
## times it counts 1 / (1 + n · this).
@export_range(0.0, 2.0, 0.01) var novelty_wear: float = 0.15
## ...and how much each earlier time adds to annoyance (the irritable) or joy
## (the trusting), up to `familiarity_cap` times.
@export_range(0.0, 1.0, 0.01) var familiarity_gain: float = 0.1
@export_range(0, 50) var familiarity_cap: int = 6
## What is only heard about is felt this much.
@export_range(0.0, 1.0, 0.01) var secondhand_factor: float = 0.5

@export_group("Reaction")
## What speaks for a reaction: "base", the five emotions by name, and axes.
@export var reactions: Dictionary = {
	&"look": {"base": 0.2, "curiosity": 0.2, "fear": -0.1},
	&"investigate": {"base": 0.0, "curiosity": 1.0, "fear": -0.7, Traits.Axis.ADVENTURE: 0.15},
	&"freeze": {"base": -0.15, "fear": 0.95, "awe": 0.2, Traits.Axis.BRAVERY: -0.1},
	&"run": {"base": -0.5, "fear": 1.45, "intense": 0.35, Traits.Axis.BRAVERY: -0.2},
	&"yell": {"base": -0.35, "fear": 0.6, "annoyance": 0.9, Traits.Axis.AGGRESSION: 0.35},
	&"laugh": {"base": -0.4, "joy": 1.2, "child": 0.6, "fear": -0.6},
	&"wave": {"base": -0.35, "joy": 0.9, "curiosity": 0.45, Traits.Axis.SUSPICION: -0.25, "child": 0.2, "fear": -0.5},
	&"pray": {"base": -0.25, "awe": 1.25, Traits.Axis.SPIRITUALITY: 0.3, "child": -0.5},
	&"dismiss": {"base": 0.0, "annoyance": 0.5, "curiosity": -0.5, "fear": -0.6, "awe": -0.8, Traits.Axis.SPIRITUALITY: -0.2},
	&"tell": {"base": -0.45, Traits.Axis.SOCIABILITY: 0.45, "strongest": 0.7},
}
## Reactions an interpretation rules out or favours: interpretation -> {reaction -> bonus}.
## Praying is for what can be prayed to; what is nothing much is shrugged off.
@export var reaction_by_interpretation: Dictionary = {
	&"natural": {&"pray": -10.0, &"dismiss": 0.55, &"run": -0.3, &"freeze": -0.2},
	&"hallucination": {&"pray": -10.0, &"dismiss": 0.6, &"investigate": -0.3, &"tell": -0.3, &"wave": -0.4, &"laugh": -0.2},
	&"spirit": {&"dismiss": -0.5},
	&"deity": {&"dismiss": -0.8, &"pray": 0.25},
	&"ancestor": {&"dismiss": -0.6, &"pray": 0.2, &"run": -0.4},
	&"unknown_intelligence": {&"pray": -10.0, &"investigate": 0.3, &"wave": 0.35},
	&"experiment": {&"pray": -10.0, &"investigate": 0.3},
	&"physics": {&"pray": -10.0, &"investigate": 0.5},
	&"multiple_entities": {},
	&"dream": {},
}
@export_range(0.02, 2.0, 0.01) var reaction_temperature: float = 0.22
## How long each reaction is held, in game minutes.
@export var reaction_minutes: Dictionary = {
	&"look": 4.0, &"investigate": 6.0, &"freeze": 5.0, &"run": 3.0, &"yell": 4.0, &"laugh": 4.0,
	&"wave": 4.0, &"pray": 9.0, &"dismiss": 2.0, &"tell": 6.0, &"listen": 5.0,
}
## The start that comes before most reactions (a turn of the head).
@export_range(0.0, 10.0, 0.5) var startle_minutes: float = 1.0
## How far (tiles) and how fast (times walking pace) people run from something.
@export_range(1.0, 30.0, 0.5) var flee_distance: float = 7.0
@export_range(1.0, 5.0, 0.1) var run_pace: float = 2.2
## How near someone has to be to be told (tiles).
@export_range(1.0, 60.0, 0.5) var tell_range: float = 12.0
## The chance that someone moved by something goes and tells of it afterwards
## (times how sociable they are and how strongly they feel).
@export_range(0.0, 1.0, 0.01) var tell_after_chance: float = 0.55


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	for interpretation in INTERPRETATIONS:
		_check(p, interpretation_emotions.has(interpretation) and (interpretation_emotions[interpretation] as Array).size() == EMOTION_COUNT,
			"interpretation_emotions needs %d values for %s" % [EMOTION_COUNT, interpretation])
		_check(p, interpretation_gates.has(interpretation), "interpretation_gates needs %s" % interpretation)
	for reaction in REACTIONS:
		_check(p, reactions.has(reaction), "reactions needs %s" % reaction)
		_check(p, reaction_minutes.has(reaction), "reaction_minutes needs %s" % reaction)
	for type: StringName in stimuli:
		_check(p, (stimuli[type] as Array).size() == 6, "stimuli.%s needs 6 values" % type)
	_check(p, child_emotions.size() == EMOTION_COUNT, "child_emotions needs %d values" % EMOTION_COUNT)
	return p


## Fills in how strong and far-reaching a stimulus of its type is
## (`strength` 0 … 1: between the least and the most of its kind).
func describe(stimulus: Stimulus, strength: float = 0.0) -> void:
	var row: Variant = stimuli.get(stimulus.type)
	if typeof(row) != TYPE_ARRAY or (row as Array).size() < 6:
		return
	stimulus.intensity = lerpf(float(row[0]), float(row[1]), clampf(strength, 0.0, 1.0))
	stimulus.radius = float(row[2])
	stimulus.anomalous = bool(row[3])
	stimulus.large = bool(row[4])
	stimulus.weatherlike = bool(row[5])


## What "people like me" lean toward: a settlement's prior for an
## interpretation, the same every time for a world (0 … culture_prior_spread).
func culture_prior(world_seed: int, settlement_id: int, interpretation: StringName) -> float:
	var mixed := hash([world_seed, settlement_id, String(interpretation)])
	return float(mixed & 0xFFFF) / 65535.0 * culture_prior_spread


## A trait as it counts in the tables: -1 … +1 (amounts centred on 0.5).
static func lean(traits: PackedFloat32Array, axis: int) -> float:
	var value := Traits.value(traits, axis)
	return (value - 0.5) * 2.0 if Traits.is_amount(axis) else value


func minutes_for(reaction: StringName) -> float:
	return float(reaction_minutes.get(reaction, 3.0))
