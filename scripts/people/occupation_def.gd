class_name OccupationDef
extends Resource
## What someone does with their days (bible §13.6). One file per occupation in
## res://data/occupations/; nothing in code names an occupation that the data
## does not define.

## Stable id (saved with people; never rename).
@export var id: StringName = &""
## Stages of life in which someone can have this occupation (PersonData.LifeStage).
@export var life_stages: Array[PersonData.LifeStage] = [PersonData.LifeStage.ADULT]
## How much of a starting band takes this up, relative to the others open to
## the same stage of life (0 = nobody starts with it).
@export_range(0.0, 10.0, 0.05) var starting_share: float = 1.0
## Which traits draw people to it: Traits.Axis name -> weight (negative = the
## opposite end of the axis).
@export var trait_weights: Dictionary = {}
## What someone with this occupation carries ("staff", "basket", "axe" — see
## PersonMeshLibrary), or nothing.
@export var accessory: StringName = &""
## Something that has no work to do yet (kept so saves and data can refer to it).
@export var placeholder: bool = false


func allows(stage: PersonData.LifeStage) -> bool:
	return life_stages.has(stage)


## How well a person's traits suit this occupation (0 = indifferent).
func affinity(traits: PackedFloat32Array) -> float:
	var total := 0.0
	for axis_name: Variant in trait_weights:
		var axis: int = Traits.Axis.get(str(axis_name), -1)
		if axis < 0:
			continue
		var lean := Traits.value(traits, axis)
		if Traits.is_amount(axis):
			lean = lean * 2.0 - 1.0
		total += lean * float(trait_weights[axis_name])
	return total


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("occupation has no id")
	if life_stages.is_empty():
		problems.append("%s: no life stage can have it" % id)
	for axis_name: Variant in trait_weights:
		if not Traits.Axis.has(str(axis_name)):
			problems.append("%s: unknown trait axis '%s'" % [id, axis_name])
	return problems
