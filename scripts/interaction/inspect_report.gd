class_name InspectReport
extends RefCounted
## What the player learns by inspecting a target (bible §26.6). Plain facts
## only — how they are worded is the UI's business. Produced by
## InteractionManager.inspect().

enum Subject { GROUND, WATER, PROP }

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
## True if the prop came with the world (not placed or built later).
var generated := false


func is_prop() -> bool:
	return subject == Subject.PROP
