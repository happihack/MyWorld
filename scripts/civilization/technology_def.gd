class_name TechnologyDef
extends Resource
## A technology (bible §18.2, M16.2): what must come together before anyone
## can work it out — what is already known, what the land offers, how much
## is known of its domain, how many people, which trade — how likely it is
## then, each day, and what it brings. Defined in res://data/technologies/.

@export var id: StringName = &""
## The domain its knowing is counted in (Knowledge.Domain).
@export var domain: int = Knowledge.Domain.CRAFT
## The technologies that must be known first.
@export var prerequisites: PackedStringArray = PackedStringArray()
## What must be at hand (see TechnologySystem.resource_known): "clay", "fibre",
## "herbs", "fat", "stone", or a resource id the settlement has had.
@export var required_resources: PackedStringArray = PackedStringArray()
## What the settlement must know of its domain (Knowledge points).
@export_range(0.0, 1000.0, 0.5) var knowledge_threshold: float = 30.0
@export_range(0, 10000) var min_population: int = 1
## A trade someone must follow (&"" = none).
@export var specialist_occupation: StringName = &""
## Buildings that must stand (BuildingDef ids).
@export var required_buildings: PackedStringArray = PackedStringArray()
## The chance a day, once everything has come together.
@export_range(0.0, 1.0, 0.0001) var base_daily_chance: float = 0.01
## What it brings: {"buildings": [...], "occupations": [...], "actions": [...],
## "interpretations": [...], "vocabulary": [...], "visuals": [...]}.
@export var unlocks: Dictionary = {}
## How much it counts towards an era (B§22.1).
@export_range(0.0, 10.0, 0.1) var era_weight: float = 1.0
## Every settlement knows it from the beginning (fire, foraging, planting).
@export var known_from_start: bool = false
## Worked out by its own rule elsewhere, not rolled here (toolmaking: Settlement).
@export var own_rule: bool = false
## False: defined, but nothing in the world can bring it about yet (later content).
@export var implemented: bool = true
## Where it stands in the chain (for listing).
@export_range(0, 1000) var order: int = 0


func unlocked(kind: String) -> PackedStringArray:
	var listed: Variant = unlocks.get(kind)
	return PackedStringArray(listed) if typeof(listed) == TYPE_ARRAY or typeof(listed) == TYPE_PACKED_STRING_ARRAY \
		else PackedStringArray()


func validate() -> PackedStringArray:
	var out := PackedStringArray()
	if id == &"":
		out.append("a technology without an id")
	if domain < 0 or domain >= Knowledge.COUNT:
		out.append("%s: no such domain %d" % [id, domain])
	if prerequisites.has(String(id)):
		out.append("%s: requires itself" % id)
	if base_daily_chance < 0.0 or base_daily_chance > 1.0:
		out.append("%s: a chance must be 0 … 1" % id)
	return out
