class_name BuildingDef
extends Resource
## A kind of building (bible §17.2, M12.1): what it is made of and how much
## work it takes, how many it holds, what it is for, and what it needs to be
## known before anyone builds it. Defined in res://data/buildings/.

@export var id: StringName = &""
## What stands there once it is built (PropData.Kind).
@export var prop_kind: int = PropData.Kind.HUT
## Tiles it takes, across and along (1 × 1 for now).
@export var footprint := Vector2i(1, 1)
## What it is made of: resource id -> units.
@export var materials: Dictionary = {}
## How much work it takes, in strokes (a stroke a game minute for a builder
## of middling skill).
@export_range(1, 100000) var labor: int = 120
## How many live in it (homes), or how much more the stores hold (storage, units).
@export_range(0, 1000) var capacity: int = 0
## What it is for: "home", "storage", "water", "workshop".
@export var tags: PackedStringArray = PackedStringArray()
## What must be known first (a technology, M18; &"" = nothing).
@export var tech: StringName = &""
## How it may look in later eras (M18+; unused yet).
@export var era_variants: PackedStringArray = PackedStringArray()

@export_group("Buildings & villagers (F1)")
## What kind of building it is: one or more of CATEGORIES (the planner's needs
## keep going by `tags`).
@export var category: PackedStringArray = PackedStringArray()
## Who works here: occupation id -> how many (0: as many as there are).
@export var workers: Dictionary = {}
## What is made here: [{"in": {resource: units}, "out": {resource: units},
## "minutes": game minutes}], the first wanted first.
@export var recipe: Array = []
## What it does to the land about it: {"effect": StringName, "radius": tiles,
## "strength": 0 …}; {} for nothing.
@export var influence: Dictionary = {}
## The least a settlement must be to build it: a tier (Settlements.Tier) and
## people.
@export_range(0, 4) var min_tier: int = 0
@export_range(0, 10000) var min_population: int = 0
## Where it goes: one of SITES.
@export var site: StringName = &"level"
## Built in place of this building (an upgrade: the old one works until it
## is done); &"" for none.
@export var upgrade_of: StringName = &""
## How many a settlement keeps: at most `limit_per_settlement` (0: no limit),
## and one for every `per_people` (0: not by its people).
@export_range(0, 100) var limit_per_settlement: int = 0
@export_range(0, 1000) var per_people: int = 0
## What keeps it standing a year: resource id -> units ({}: only repair).
@export var maintenance: Dictionary = {}
## How it looks to a culture: look id -> template variant.
@export var variants: Dictionary = {}
## Always remembered by name and story (a BuildingRecord, F5).
@export var historic: bool = false

const CATEGORIES: Array[String] = ["home", "food", "storage", "water", "craft", "knowledge", "faith",
	"social", "health", "transport", "defence"]
const SITES: Array[StringName] = [&"level", &"bank", &"crossing", &"sacred", &"rock", &"forest_edge",
	&"field_edge", &"high"]


func has_tag(tag: String) -> bool:
	return tags.has(tag)


func validate() -> PackedStringArray:
	var out := PackedStringArray()
	if id == &"":
		out.append("a building without an id")
	if prop_kind < 0 or prop_kind >= PropData.Kind.size():
		out.append("%s: no such prop kind %d" % [id, prop_kind])
	for resource: Variant in materials:
		if typeof(materials[resource]) != TYPE_INT or int(materials[resource]) < 0:
			out.append("%s: %s must be a whole number of units" % [id, resource])
	if footprint.x < 1 or footprint.y < 1:
		out.append("%s: footprint must be at least 1 × 1" % id)
	for kind in category:
		if not CATEGORIES.has(kind):
			out.append("%s: no such category '%s'" % [id, kind])
	if not SITES.has(site):
		out.append("%s: no such site rule '%s'" % [id, site])
	for trade: Variant in workers:
		if typeof(workers[trade]) != TYPE_INT or int(workers[trade]) < 0:
			out.append("%s: workers of %s must be a whole number" % [id, trade])
	for step: Variant in recipe:
		if typeof(step) != TYPE_DICTIONARY or typeof(step.get("out")) != TYPE_DICTIONARY or (step["out"] as Dictionary).is_empty():
			out.append("%s: a recipe step must say what comes out" % id)
		elif float(step.get("minutes", 0)) <= 0.0:
			out.append("%s: a recipe step must take some time" % id)
	if upgrade_of == id and id != &"":
		out.append("%s: cannot be an upgrade of itself" % id)
	return out


## Every resource its materials, recipe and upkeep name.
func resources_named() -> Array[StringName]:
	var out: Array[StringName] = []
	var add := func(by: Variant) -> void:
		if typeof(by) == TYPE_DICTIONARY:
			for resource: Variant in by:
				if not out.has(StringName(str(resource))):
					out.append(StringName(str(resource)))
	add.call(materials)
	add.call(maintenance)
	for step: Variant in recipe:
		if typeof(step) == TYPE_DICTIONARY:
			add.call(step.get("in", {}))
			add.call(step.get("out", {}))
	return out
