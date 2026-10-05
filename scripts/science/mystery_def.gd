class_name MysteryDef
extends Resource
## A seeded mystery (M18, bible §25.2): placed when the world is made, dormant
## until what it needs comes about, then unfolding clue by clue — never all at
## once. Defined in res://data/mysteries/.

@export var id: StringName = &""
## Where it lies: "ruin" (old stones the world has, or new ones), "stones"
## (old standing stones, placed), "buried" (beneath the ground), "spot" (a
## place where something odd happens), "edge" (at the box's wall), "none"
## (nowhere in particular: the land itself).
@export var placement: String = "none"
## The clues, in order: each a list of what must hold (all of it) before it is
## found — "visited" (someone has stood near it), "seen:<days>" (on that many
## days), "known:<tech>" (some settlement knows it), "scholar" (some settlement
## has someone looking into the unexplained), "exposed" (the ground over it has
## been turned: tilled, flooded, washed away), "edge" (the Edge has been found),
## "building:<id>" (one stands), "dormant" (not yet: later content).
@export var steps: Array[PackedStringArray] = []
## How much a clue of it counts for history.
@export_range(0.0, 1.0, 0.01) var significance: float = 0.6


func validate() -> PackedStringArray:
	var out := PackedStringArray()
	if id == &"":
		out.append("a mystery without an id")
	if not ["ruin", "stones", "buried", "spot", "edge", "none"].has(placement):
		out.append("%s: no such placement %s" % [id, placement])
	if steps.is_empty():
		out.append("%s: no clues" % id)
	return out
