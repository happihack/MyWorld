class_name HandDraw
extends RefCounted
## Drawing by hand (the owner's direction, 2026-10-09): nothing quite
## straight, no two corners the same. Circles wobble and overshoot where the
## stroke ends, boxes have a different radius at every corner and sit a
## degree or two off level, paper is ruled and taped on. Every shape is
## settled by a seed, so the same button looks the same every frame.

## How far a chalk circle's radius wanders (a share of it).
const WOBBLE := 0.035
## The stroke runs past its start by this much (radians) where it ends.
const OVERSHOOT := 0.3


static func _rng(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + 13
	return rng


## A hand-drawn circle: the points of its outline, from a start angle round
## past it (`extra` radians more than a turn) — pass 0.0 for a closed shape.
static func circle_points(center: Vector2, radius: float, seed: int, extra: float = OVERSHOOT, segments: int = 44) -> PackedVector2Array:
	var rng := _rng(seed)
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	var p3 := rng.randf() * TAU
	var start := rng.randf() * TAU
	var a := WOBBLE * (0.8 + rng.randf() * 0.4)
	var points := PackedVector2Array()
	var sweep := TAU + extra
	var count := int(ceil(segments * sweep / TAU))
	for i in count + 1:
		var angle := start + sweep * i / count
		var r := radius * (1.0 + a * sin(3.0 * angle + p1) + a * 0.6 * sin(5.0 * angle + p2) + a * 0.5 * sin(2.0 * angle + p3))
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	return points


## A chalk circle: filled with `fill` (if it has any alpha), outlined in `color`.
static func chalk_circle(on: CanvasItem, center: Vector2, radius: float, color: Color, width: float, seed: int, fill: Color = Color(0, 0, 0, 0)) -> void:
	if fill.a > 0.0:
		on.draw_colored_polygon(circle_points(center, radius, seed, 0.0), fill)
	if color.a > 0.0 and width > 0.0:
		on.draw_polyline(circle_points(center, radius, seed), color, width, true)


## A ring filled part way round (clockwise from the top): how far something has come.
static func chalk_arc(on: CanvasItem, center: Vector2, radius: float, share: float, color: Color, width: float, seed: int) -> void:
	var points := circle_points(center, radius, seed, 0.0, 48)
	# (The ring starts at the top: turn the points so the first is there.)
	var top := 0
	for i in points.size():
		if points[i].y < points[top].y:
			top = i
	var kept := PackedVector2Array()
	var total := points.size() - 1
	var count := int(round(total * clampf(share, 0.0, 1.0)))
	for i in count + 1:
		kept.append(points[(top + i) % total])
	if kept.size() >= 2:
		on.draw_polyline(kept, color, width, true)


## A box whose corners are each rounded a little differently.
static func chalk_box(seed: int, fill: Color, border: Color, border_width: float, radius: float) -> StyleBoxFlat:
	var rng := _rng(seed)
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(int(round(border_width)))
	box.corner_radius_top_left = int(radius * (0.55 + rng.randf() * 0.45))
	box.corner_radius_top_right = int(radius * (0.55 + rng.randf() * 0.45))
	box.corner_radius_bottom_right = int(radius * (0.55 + rng.randf() * 0.45))
	box.corner_radius_bottom_left = int(radius * (0.55 + rng.randf() * 0.45))
	box.anti_aliasing = true
	box.anti_aliasing_size = 1.2
	return box


## A chip drawn in ink on paper: something to press.
static func ink_chip(seed: int, pad: float = 24.0, filled: bool = false) -> StyleBoxFlat:
	var chip := chalk_box(seed, UITheme.INK if filled else Color(0, 0, 0, 0), UITheme.INK, 4.0, UITheme.TOUCH_TARGET * 0.36)
	chip.content_margin_left = pad
	chip.content_margin_right = pad
	return chip


## A sheet of paper, with a shadow under it.
static func paper_box(seed: int, margin: float) -> StyleBoxFlat:
	var rng := _rng(seed)
	var box := StyleBoxFlat.new()
	box.bg_color = UITheme.PAPER
	box.corner_radius_top_left = int(4 + rng.randf() * 8)
	box.corner_radius_top_right = int(4 + rng.randf() * 8)
	box.corner_radius_bottom_right = int(4 + rng.randf() * 8)
	box.corner_radius_bottom_left = int(4 + rng.randf() * 8)
	box.shadow_color = Color(0, 0, 0, 0.38)
	box.shadow_size = 18
	box.shadow_offset = Vector2(0, 8)
	box.set_content_margin_all(margin)
	box.anti_aliasing = true
	return box


## How far off level (degrees) something with this seed sits.
static func tilt_for(seed: int, most: float = 1.5) -> float:
	var rng := _rng(seed)
	return (rng.randf() * 2.0 - 1.0) * most


## Sets a control a little off level, turning about its middle whatever its size.
static func tilt(control: Control, degrees: float) -> void:
	control.rotation_degrees = degrees
	control.pivot_offset = control.size * 0.5
	if not control.resized.is_connected(_center_pivot.bind(control)):
		control.resized.connect(_center_pivot.bind(control))


static func _center_pivot(control: Control) -> void:
	control.pivot_offset = control.size * 0.5


## The ruled lines of a sheet of paper, over `rect`.
static func draw_rules(on: CanvasItem, rect: Rect2, every: float = UITheme.RULE_EVERY, color: Color = UITheme.PAPER_RULE) -> void:
	var y := rect.position.y + every
	while y < rect.end.y:
		on.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), color, 2.0)
		y += every


## A line drawn by hand from `from` to `to`: it wanders a little.
static func draw_stroke(on: CanvasItem, from: Vector2, to: Vector2, color: Color, width: float, seed: int, wander: float = 3.0) -> void:
	var rng := _rng(seed)
	var points := PackedVector2Array()
	var steps := maxi(int((to - from).length() / 40.0), 3)
	var normal := (to - from).normalized().orthogonal()
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	for i in steps + 1:
		var f := i / float(steps)
		var off := sin(f * PI * 2.0 + p1) * wander + sin(f * PI * 5.0 + p2) * wander * 0.4
		points.append(from.lerp(to, f) + normal * off)
	on.draw_polyline(points, color, width, true)


## A squiggle under a title.
static func draw_squiggle(on: CanvasItem, from: Vector2, to: Vector2, color: Color, width: float, seed: int) -> void:
	draw_stroke(on, from, to, color, width, seed, 7.0)


## Pencil hatching across `rect` (a bar filled by hand).
static func draw_hatch(on: CanvasItem, rect: Rect2, color: Color, step: float = 10.0, width: float = 3.0) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var x := rect.position.x - rect.size.y
	while x < rect.end.x:
		# A stroke leaning right, clipped to the box.
		var a := Vector2(x, rect.end.y)
		var b := Vector2(x + rect.size.y, rect.position.y)
		var from := a
		var to := b
		if from.x < rect.position.x:
			from = a.lerp(b, (rect.position.x - a.x) / (b.x - a.x))
		if to.x > rect.end.x:
			to = a.lerp(b, (rect.end.x - a.x) / (b.x - a.x))
		if to.x > from.x:
			on.draw_line(from, to, color, width)
		x += step


## A strip of tape, `size` big, turned by `degrees`, its middle at `center`.
static func draw_tape(on: CanvasItem, center: Vector2, size: Vector2, degrees: float) -> void:
	var turn := deg_to_rad(degrees)
	var half := size * 0.5
	var corners := PackedVector2Array()
	for corner: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		corners.append(center + corner.rotated(turn))
	on.draw_colored_polygon(corners, UITheme.TAPE)
	var edge := Color(0, 0, 0, 0.12)
	on.draw_line(corners[0], corners[3], edge, 2.0)
	on.draw_line(corners[1], corners[2], edge, 2.0)


## A marker stroke behind a word: a yellow box, leaning.
static func draw_marker(on: CanvasItem, rect: Rect2, color: Color = UITheme.MARKER) -> void:
	var lean := rect.size.y * 0.1
	on.draw_colored_polygon(PackedVector2Array([
		rect.position + Vector2(lean, 0.0), Vector2(rect.end.x + lean, rect.position.y),
		Vector2(rect.end.x - lean, rect.end.y), Vector2(rect.position.x - lean, rect.end.y)]), color)


## A blot of ink: something new here.
static func draw_blot(on: CanvasItem, center: Vector2, radius: float, color: Color, seed: int) -> void:
	on.draw_colored_polygon(circle_points(center, radius, seed, 0.0, 16), color)
