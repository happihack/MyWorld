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

const WATER_NAME := "Water"


static func terrain_name(terrain: int) -> String:
	return TERRAIN_NAMES.get(terrain, "Ground")


static func prop_name(kind: int, variant: int = 0) -> String:
	if kind == PropData.Kind.TREE and variant >= PropData.TREE_CONIFER_FIRST_VARIANT:
		return "Pine"
	return PROP_NAMES.get(kind, "Something")


## Name of what a touch landed on.
static func subject_name(what: InteractionResponse) -> String:
	if what == null:
		return ""
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
