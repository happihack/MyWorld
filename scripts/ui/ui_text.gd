class_name UIText
extends RefCounted
## Player-facing words for things in the world (bible §26: quiet, short,
## curious). All wording lives here so it can move to data/text tables when
## localization arrives; nothing else in the game spells out names.

const TERRAIN_NAMES := {
	ChunkData.Terrain.GRASS: "Grass",
	ChunkData.Terrain.DIRT: "Bare earth",
	ChunkData.Terrain.SAND: "Sand",
	ChunkData.Terrain.ROCK: "Rock",
	ChunkData.Terrain.SNOW: "Snow",
	ChunkData.Terrain.FARMLAND: "Farmland",
	ChunkData.Terrain.ROAD: "Path",
	ChunkData.Terrain.RIVERBED: "Riverbed",
	ChunkData.Terrain.MUD: "Mud",
	ChunkData.Terrain.ASH: "Ash",
}

const PROP_NAMES := {
	PropData.Kind.TREE: "Tree",
	PropData.Kind.ROCK: "Rock",
	PropData.Kind.BUSH: "Berry bush",
	PropData.Kind.HUT: "Hut",
	PropData.Kind.CAMPFIRE: "Campfire",
	PropData.Kind.RUIN: "Old stones",
}

const LOOSE_NAMES := {
	LooseObject.Kind.PEBBLE: "Pebble",
	LooseObject.Kind.ROCK: "Rock",
	LooseObject.Kind.BOULDER: "Boulder",
	LooseObject.Kind.LOG: "Log",
	LooseObject.Kind.FRUIT: "Fruit",
	LooseObject.Kind.SEED: "Seed",
	LooseObject.Kind.STRANGE_OBJECT: "Strange object",
}

const TOOL_NAMES := {
	&"hand": "Hand",
	&"observe": "Observe",
	&"water": "Water (prototype)",
	&"call": "Call (prototype)",
}

const WATER_NAME := "Water"

## Words for what stands out in a person (ids from Traits).
const TRAIT_WORDS := {
	&"cautious": "Cautious", &"curious": "Curious",
	&"fearful": "Fearful", &"brave": "Brave",
	&"selfish": "Selfish", &"generous": "Generous",
	&"introverted": "Quiet", &"social": "Sociable",
	&"lazy": "Easygoing", &"ambitious": "Ambitious",
	&"skeptical": "Skeptical", &"spiritual": "Spiritual",
	&"peaceful": "Peaceful", &"aggressive": "Hot-tempered",
	&"trusting": "Trusting", &"suspicious": "Wary",
	&"homebound": "Homebound", &"adventurous": "Adventurous",
	&"intelligent": "Clever", &"creative": "Inventive", &"loyal": "Loyal",
}

const OCCUPATION_NAMES := {
	&"forager": "Forager",
	&"woodcutter": "Woodcutter",
	&"builder": "Builder",
	&"child": "Child",
	&"elder": "Elder",
}

## What people are doing, and why (bible 13.4: "Going home - tired").
const ACTIVITY_NAMES := {
	&"eat": "Eating",
	&"drink": "Drinking",
	&"sleep": "Sleeping",
	&"work": "Working",
	&"socialize": "Talking",
	&"explore": "Exploring",
	&"play": "Playing",
	&"tag_along": "Tagging along",
	&"go_home": "Resting at home",
	&"called": "Answering a call",
	&"idle": "Standing about",
}

## How a need feels when it is the reason for something (ids from Needs).
const NEED_WORDS := {
	&"hunger": "hungry",
	&"thirst": "thirsty",
	&"sleep": "tired",
	&"social": "lonely",
	&"purpose": "restless",
	&"safety": "uneasy",
}

## What a need is called on a person's card (ids from Needs).
const NEED_LABELS := {
	&"hunger": "Food",
	&"thirst": "Water",
	&"sleep": "Rest",
	&"social": "Company",
	&"purpose": "Purpose",
	&"safety": "Safety",
}

const LIFE_STAGE_NAMES := {
	PersonData.LifeStage.CHILD: "Child",
	PersonData.LifeStage.ADOLESCENT: "Youth",
	PersonData.LifeStage.ADULT: "Adult",
	PersonData.LifeStage.ELDER: "Elder",
}

## First-time hints (bible §26.3: quiet, short, curious).
const HINTS := {
	&"drag": "Drag to explore.",
	&"touch_person": "Try touching someone.",
	&"hold": "Hold to learn more.",
	&"follow": "Follow them to see their day.",
}


## Words for a person's most pronounced traits (see Traits.describe_top).
static func trait_words(traits: PackedFloat32Array, n: int = 3) -> PackedStringArray:
	var out := PackedStringArray()
	for word_id in Traits.describe_top(traits, n):
		out.append(TRAIT_WORDS.get(StringName(word_id), word_id.capitalize()))
	return out


static func occupation_name(id: StringName) -> String:
	return OCCUPATION_NAMES.get(id, String(id).capitalize())


## "Eating - hungry", "Working" (no reason worth a word: habit, their nature).
static func activity_phrase(activity: StringName, reason: StringName = &"") -> String:
	var what: String = ACTIVITY_NAMES.get(activity, String(activity).capitalize())
	if activity == &"":
		return ""
	return "%s — %s" % [what, NEED_WORDS[reason]] if NEED_WORDS.has(reason) else what


## What someone is doing about something they noticed (ReactionTable ids).
const REACTION_PHRASES := {
	&"look": "Looking about",
	&"investigate": "Taking a closer look",
	&"freeze": "Standing frozen",
	&"run": "Running away",
	&"yell": "Crying out",
	&"laugh": "Laughing",
	&"wave": "Waving",
	&"pray": "Praying",
	&"dismiss": "Shrugging it off",
	&"tell": "Going to tell someone",
	&"listen": "Listening",
}
## ...and what they make of it: "thinks …".
const INTERPRETATION_PHRASES := {
	&"natural": "it was nothing strange",
	&"spirit": "a spirit is near",
	&"deity": "a god reached down",
	&"ancestor": "an ancestor is near",
	&"experiment": "someone is testing them",
	&"unknown_intelligence": "someone unseen is there",
	&"multiple_entities": "many unseen things are there",
	&"hallucination": "they imagined it",
	&"physics": "an unknown force is at work",
	&"dream": "it was a dream",
}


## "Praying — thinks a spirit is near": what someone does about what they
## noticed, and why (bible §14.4: the reaction is "a line on the person card").
static func reaction_phrase(reaction: StringName, interpretation: StringName) -> String:
	var doing: String = REACTION_PHRASES.get(reaction, "Startled")
	if not INTERPRETATION_PHRASES.has(interpretation):
		return doing
	return "%s — thinks %s" % [doing, INTERPRETATION_PHRASES[interpretation]]


static func need_label(need_name: StringName) -> String:
	return NEED_LABELS.get(need_name, String(need_name).capitalize())


static func age_text(years: int) -> String:
	if years <= 0:
		return "A baby"
	return "1 year" if years == 1 else "%d years" % years


## How someone feels, in a word (mood and stress: 0 … 1, see Needs).
static func mood_word(mood: float, stress: float = 0.0) -> String:
	if stress >= 0.75:
		return "Desperate"
	if stress >= 0.4:
		return "Strained"
	if mood >= 0.8:
		return "Content"
	if mood >= 0.62:
		return "At ease"
	if mood >= 0.45:
		return "Restless"
	return "Troubled"


## What someone is to the person whose card is shown: `relation` is
## &"partner", &"parent" or &"child"; `sex` is theirs (PersonData.Sex).
static func relation_word(relation: StringName, sex: int) -> String:
	var woman := sex == PersonData.Sex.FEMALE
	match relation:
		&"parent":
			return "Mother" if woman else "Father"
		&"child":
			return "Daughter" if woman else "Son"
	return "Partner"


static func life_stage_name(stage: int) -> String:
	return LIFE_STAGE_NAMES.get(stage, "")


static func hint(id: StringName) -> String:
	return HINTS.get(id, "")


static func terrain_name(terrain: int) -> String:
	return TERRAIN_NAMES.get(terrain, "Ground")


static func prop_name(kind: int, variant: int = 0) -> String:
	if kind == PropData.Kind.TREE and variant >= PropData.TREE_CONIFER_FIRST_VARIANT:
		return "Pine"
	return PROP_NAMES.get(kind, "Something")


static func tool_name(id: StringName) -> String:
	return TOOL_NAMES.get(id, String(id).capitalize())


static func loose_name(kind: int) -> String:
	return LOOSE_NAMES.get(kind, "Something")


## How heavy something is to a hand reaching into the box.
static func weight_text(kilograms: float) -> String:
	var word := "Very heavy"
	if kilograms < 1.0:
		word = "Light"
	elif kilograms < 30.0:
		word = "Heavy"
	return "%s (%s kg)" % [word, ("%.1f" % kilograms) if kilograms < 10.0 else str(roundi(kilograms))]


## What a tree still bears: fruit on a broadleaf, cones on a conifer.
static func bears_text(left: int, of: int, conifer: bool) -> String:
	var what := "cones" if conifer else "fruit"
	if of <= 0:
		return "None"
	if left <= 0:
		return "No %s left" % what
	if conifer and left == 1:
		what = "cone"
	return "%d %s" % [left, what]


static func moved_text(times: int) -> String:
	if times <= 0:
		return "Never"
	return "Once" if times == 1 else "%d times" % times


## Name of what a touch landed on.
static func subject_name(what: InteractionResponse) -> String:
	if what == null:
		return ""
	if what.loose_kind >= 0:
		return loose_name(what.loose_kind)
	if what.person_id != 0:
		return "Someone"
	if what.is_entity():
		return prop_name(what.prop_kind, what.prop_variant)
	if what.touch_effect == InteractionResponse.RIPPLE:
		return WATER_NAME
	return terrain_name(what.terrain)


## Label of a context-menu action. `touch_effect`: what touching the target
## does (an InteractionResponse effect id), so "touch" can be worded to fit.
static func action_label(action: StringName, touch_effect: StringName = &"") -> String:
	match action:
		InteractionManager.ACTION_INSPECT:
			return "Inspect"
		InteractionManager.ACTION_FOCUS:
			return "Look closer"
		InteractionManager.ACTION_REMOVE:
			return "Uproot"
		InteractionManager.ACTION_TOUCH:
			match touch_effect:
				InteractionResponse.TREE_SHAKE, InteractionResponse.BUSH_RUSTLE:
					return "Shake"
				InteractionResponse.RIPPLE:
					return "Disturb"
				InteractionResponse.BUILDING_KNOCK:
					return "Knock"
			return "Touch"
	return String(action).capitalize()


## A 0..255 layer value as one of `words` (lowest to highest).
static func level_word(value: int, words: PackedStringArray) -> String:
	if words.is_empty():
		return ""
	return words[clampi(value * words.size() / 256, 0, words.size() - 1)]


static func percent(value: int) -> String:
	return "%d%%" % roundi(clampi(value, 0, 255) / 255.0 * 100.0)


static func moisture_text(value: int) -> String:
	return "%s (%s)" % [level_word(value, ["Dry", "Damp", "Moist", "Wet"]), percent(value)]


static func fertility_text(value: int) -> String:
	return "%s (%s)" % [level_word(value, ["Poor", "Fair", "Good", "Rich"]), percent(value)]


static func vegetation_text(value: int) -> String:
	return "%s (%s)" % [level_word(value, ["Bare", "Sparse", "Green", "Lush"]), percent(value)]


static func size_text(scale_percent: int) -> String:
	var word := "Small" if scale_percent < 90 else ("Large" if scale_percent > 115 else "Medium")
	return "%s (%d%%)" % [word, scale_percent]


static func depth_text(depth: float, height_step: float) -> String:
	var levels := depth / maxf(height_step, 0.001)
	var word := "Shallow" if levels < 0.6 else ("Deep" if levels > 1.4 else "Waist-deep")
	return "%s (%.2f)" % [word, depth]
