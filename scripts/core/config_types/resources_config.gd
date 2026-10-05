class_name ResourcesConfig
extends ConfigBase
## Resource nodes, carrying and storing (bible §11, §17.3).

@export_group("Nodes")
## What each kind of node yields: node -> {"resource": id, "quantity": units
## at 100 % size, "strokes_per_unit": strokes of work for one unit,
## "regrow_days": game days from empty to full (0 = never)}.
## Nodes: "tree", "bush", "rock" (props), "crop" (a ripe field: what it
## holds is its harvest, see Farming) and "shoal" (fish: with the animals, M7.4).
@export var nodes: Dictionary = {
	&"tree": {"resource": &"wood", "quantity": 16, "strokes_per_unit": 12, "regrow_days": 24.0},
	&"bush": {"resource": &"berries", "quantity": 8, "strokes_per_unit": 4, "regrow_days": 2.0},
	&"rock": {"resource": &"stone", "quantity": 10, "strokes_per_unit": 16, "regrow_days": 0.0},
	&"crop": {"resource": &"grain", "quantity": 6, "strokes_per_unit": 2, "regrow_days": 0.0},
	&"shoal": {"resource": &"fish", "quantity": 20, "strokes_per_unit": 10, "regrow_days": 4.0},
}
## A felled tree is a stump until this much of it has grown back; then a
## sapling that grows with it.
@export_range(0.0, 1.0, 0.01) var sapling_from: float = 0.2
## A sapling's size when it first shows, as a share of the grown tree.
@export_range(0.05, 1.0, 0.01) var sapling_scale: float = 0.35
## A bush with less than this share of its berries looks picked over.
@export_range(0.0, 1.0, 0.01) var sparse_below: float = 0.5
## A bush with nothing left is this much smaller.
@export_range(0.1, 1.0, 0.01) var bare_scale: float = 0.82
## How often regrowth is worked out, in game minutes.
@export_range(1, 1440) var regrow_check_minutes: int = 60

@export_group("Winter")
## (Under study, 2026-10-05 — off: the game as it was.) In winter the bushes
## bear nothing and grow nothing back: what is eaten is what was laid in.
@export var winter_no_berries := false

@export_group("Carrying")
## What a grown person carries at once, in kilograms, and the most units
## whatever they weigh.
@export_range(0.5, 200.0, 0.5) var carry_weight: float = 8.0
@export_range(1, 100) var carry_units_max: int = 6
## Game minutes it takes to put a load down on a pile.
@export_range(0.0, 60.0, 0.5) var store_minutes: float = 2.0
## What bringing a load home is worth to the one who brought it, as purpose
## (the walk there and back is part of the work, and should feel like it).
@export_range(0.0, 1.0, 0.01) var load_purpose: float = 0.15
## A bush with at least this share of its berries is worth the walk; people
## go to barer ones only when there are no others.
@export_range(0.0, 1.0, 0.01) var worth_picking_from: float = 0.5

@export_group("Storing")
## Where a settlement keeps things, as an offset from its fire, by category
## (ResourceDef.Category names, lower case).
@export var storage_offsets: Dictionary = {
	&"material": Vector2i(2, 1),
	&"food": Vector2i(-2, 1),
	&"water": Vector2i(-2, 1),
	&"medicine": Vector2i(-2, 1),
}
## Piles of one resource a storage place holds; once they are full nobody
## gathers more of it.
@export_range(1, 16) var piles_per_resource: int = 3
## Piles within this many tiles of the storage place count as stored there.
@export_range(0.5, 16.0, 0.1) var storage_radius: float = 1.6
## A pile's size on the ground, from nearly empty to full (percent).
@export_range(10, 400) var pile_scale_min: int = 55
@export_range(10, 400) var pile_scale_max: int = 120


## The settings of a node ({} if there is no such node).
func node(key: StringName) -> Dictionary:
	var settings: Variant = nodes.get(key)
	return settings if typeof(settings) == TYPE_DICTIONARY else {}


## Where a category is kept, as an offset from the settlement's fire.
func storage_offset(category: ResourceDef.Category) -> Vector2i:
	var key := StringName(String(ResourceDef.Category.keys()[category]).to_lower())
	var offset: Variant = storage_offsets.get(key)
	return offset if typeof(offset) == TYPE_VECTOR2I else Vector2i(2, 1)


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	for key: Variant in nodes:
		var settings: Variant = nodes[key]
		if typeof(settings) != TYPE_DICTIONARY:
			p.append("nodes[%s] must be a dictionary" % key)
			continue
		_check(p, StringName(str((settings as Dictionary).get("resource", ""))) != &"", "nodes[%s] needs a resource" % key)
		_check(p, int((settings as Dictionary).get("quantity", 0)) >= 1, "nodes[%s].quantity must be at least 1" % key)
		_check(p, int((settings as Dictionary).get("strokes_per_unit", 0)) >= 1, "nodes[%s].strokes_per_unit must be at least 1" % key)
		_check(p, float((settings as Dictionary).get("regrow_days", 0.0)) >= 0.0, "nodes[%s].regrow_days cannot be negative" % key)
	_check(p, pile_scale_min <= pile_scale_max, "pile_scale_min must not be more than pile_scale_max")
	_check(p, carry_weight > 0.0, "carry_weight must be more than nothing")
	for key: Variant in storage_offsets:
		_check(p, typeof(storage_offsets[key]) == TYPE_VECTOR2I, "storage_offsets[%s] must be a Vector2i" % key)
	return p
