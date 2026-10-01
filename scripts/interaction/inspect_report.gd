class_name InspectReport
extends RefCounted
## What the player learns by inspecting a target (bible §26.6). Plain facts
## only — how they are worded is the UI's business. Produced by
## InteractionManager.inspect().

enum Subject { GROUND, WATER, PROP, LOOSE, ANIMAL }

var subject: Subject = Subject.GROUND
var tile := Vector2i.ZERO
## The ground under the target (for water: the bed).
var terrain := 0
var height_level := 0
## Soil layers, 0..255.
var moisture := 0
var fertility := 0
var vegetation := 0
## Water depth above the ground, world units (0 on dry land).
var water_depth := 0.0

## Props only.
var entity_id := 0
var prop_kind := -1
var prop_variant := 0
var scale_percent := 100
## Trees only: fruit or cones still on it, and how many it bears untouched
## (-1 for anything that bears nothing).
var bears_left := -1
var bears := -1
## Resource nodes and piles: what it holds, how much is left and (nodes)
## how much it holds whole; how a node looks for it (ResourceNodes.Look).
var resource: StringName = &""
var resource_left := 0
var resource_capacity := 0
var look := 0
## Crops only: Farming.Stage (-1 = not a crop), growth and vigour 0 … 1000,
## and whether it stands dry.
var crop_stage := -1
var crop_growth := 0
var crop_vigor := 1000
var crop_dry := false
## Animals only: which kind, what it is doing (AnimalData.State), how old
## (game days), whether it is grown, and how many of its kind there are.
var species: StringName = &""
var animal_state := 0
var animal_age_days := 0
var animal_grown := true
var species_count := 0
## True if the prop or object came with the world (not placed or built later).
var generated := false

## Loose objects only (they also use entity_id, scale_percent and generated).
var loose_kind := -1
var mass := 0.0
var moved_count := 0
var placed_by_player := false


func is_prop() -> bool:
	return subject == Subject.PROP


func is_loose() -> bool:
	return subject == Subject.LOOSE
