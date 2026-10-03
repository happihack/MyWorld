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
	return out
