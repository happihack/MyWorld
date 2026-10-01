class_name PersonGlyph
extends Control
## A person's portrait as a glyph (bible §26.6): head and shoulders in their
## own colours — the same skin, hair and cloth they are drawn with in the
## world, so that the card and the figure are recognisably the same person.

const SIZE := 104.0

var skin := Color(0.80, 0.60, 0.45)
var hair := Color(0.20, 0.14, 0.10)
var cloth := Color(0.70, 0.30, 0.22)


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Takes the colours of a person at a stage of life (elders are grey).
func show_person(person: PersonData, stage: PersonData.LifeStage) -> void:
	skin = PersonMeshLibrary.skin(int(person.appearance.get("skin", 0)))
	hair = PersonMeshLibrary.hair(int(person.appearance.get("hair", 0)), stage)
	cloth = PersonMeshLibrary.cloth(int(person.appearance.get("cloth", 0)))
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	draw_circle(center, radius, Color(0.949, 0.902, 0.788, 0.12))
	draw_arc(center, radius - 1.5, 0.0, TAU, 48, UITheme.RIM, 3.0, true)
	# Shoulders: the top of a circle below the head, cut off by the frame.
	var shoulders := PackedVector2Array()
	var steps := 20
	for i in steps + 1:
		var angle := PI + PI * i / steps
		shoulders.append(center + Vector2(cos(angle) * radius * 0.72, radius * 0.86 + sin(angle) * radius * 0.52))
	draw_colored_polygon(shoulders, cloth)
	# Head, with hair over the top of it.
	var head := center + Vector2(0.0, -radius * 0.12)
	var head_radius := radius * 0.36
	draw_circle(head, head_radius, skin)
	var cap := PackedVector2Array()
	for i in steps + 1:
		var angle := PI * 1.08 + PI * 0.84 * i / steps
		cap.append(head + Vector2(cos(angle), sin(angle)) * head_radius * 1.06)
	cap.append(head + Vector2(head_radius * 0.55, -head_radius * 0.35))
	cap.append(head + Vector2(-head_radius * 0.55, -head_radius * 0.35))
	draw_colored_polygon(cap, hair)
