class_name ResourceDef
extends Resource
## A kind of resource (bible §11): what people gather, carry, store and use.
## Defined in res://data/resources/*.tres; found through ResourceLibrary.

enum Category { FOOD, WATER, MATERIAL, MEDICINE }

@export var id: StringName = &""
@export var category: Category = Category.MATERIAL
## The most units one pile holds.
@export_range(1, 1000) var stack: int = 20
## Game days until a stored unit goes bad (0 = keeps for ever). Spoilage
## itself comes with the stockpile (M7.2).
@export_range(0.0, 10000.0, 0.5) var spoil_days: float = 0.0
## Food only: how much of an empty belly one unit fills (1 = hunger from
## nothing to full).
@export_range(0.0, 10.0, 0.05) var nutrition: float = 0.0
## Kilograms per unit: how many units someone carries at once.
@export_range(0.01, 1000.0, 0.01) var weight: float = 1.0
## Its colour where it is drawn as a heap, and in lists.
@export var color: Color = Color(0.6, 0.6, 0.6)
## Shown in lists once there are any (optional).
@export var icon: Texture2D
## Defined for later: nothing in the world yields it yet.
@export var defined_only: bool = false


func is_food() -> bool:
	return category == Category.FOOD


func spoils() -> bool:
	return spoil_days > 0.0


## How many units someone who can carry `kilograms` takes at once (at least
## one, at most `most`).
func units_carried(kilograms: float, most: int) -> int:
	return clampi(floori(kilograms / maxf(weight, 0.01)), 1, maxi(most, 1))


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("a resource without an id")
	if stack < 1:
		problems.append("%s: stack must be at least 1" % id)
	if weight <= 0.0 or not is_finite(weight):
		problems.append("%s: weight must be more than nothing" % id)
	if category == Category.FOOD and nutrition <= 0.0:
		problems.append("%s: food must feed (nutrition)" % id)
	if spoil_days < 0.0 or not is_finite(spoil_days):
		problems.append("%s: spoil_days cannot be negative" % id)
	return problems
