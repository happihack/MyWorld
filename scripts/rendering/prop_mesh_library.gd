class_name PropMeshLibrary
extends RefCounted
## Low-poly prop shapes, generated in code (bible §28: readable silhouettes,
## few triangles, vertex colours, no textures). Each shape is a Template:
## flat-shaded, non-indexed triangles around the origin with the base at y = 0,
## sized in tiles (1 tile = 1 unit).
##
## Colour alpha is the vertex's SWAY WEIGHT for the wind shader, not opacity:
## 0 = rigid (trunk base, rocks, walls), 1 = moves fully (tree tops).

class Template:
	extends RefCounted
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	## What glows, per vertex (see prop.gdshader): 0 nothing, 1 a window or a
	## doorway (lit at night), 2 a flame (always). Shorter than `vertices`
	## where nothing after it glows.
	var glow := PackedFloat32Array()

	func triangle_count() -> int:
		return vertices.size() / 3

	## Marks everything added since vertex `from` as glowing.
	func glow_from(from: int, value: float) -> void:
		glow.resize(vertices.size())
		for i in range(from, vertices.size()):
			glow[i] = value

	func glow_of(index: int) -> float:
		return glow[index] if index < glow.size() else 0.0


const TRUNK := Color(0.42, 0.29, 0.18)
const TRUNK_DARK := Color(0.33, 0.22, 0.14)
const LEAF := Color(0.24, 0.50, 0.22)
const LEAF_LIGHT := Color(0.36, 0.62, 0.27)
const PINE := Color(0.14, 0.38, 0.24)
const PINE_LIGHT := Color(0.22, 0.48, 0.29)
const STONE := Color(0.56, 0.56, 0.58)
const STONE_DARK := Color(0.43, 0.43, 0.46)
const BUSH := Color(0.22, 0.45, 0.20)
const BUSH_LIGHT := Color(0.31, 0.55, 0.24)
const BERRY := Color(0.80, 0.16, 0.30)
const WALL := Color(0.78, 0.66, 0.47)
const WALL_DARK := Color(0.63, 0.52, 0.36)
const THATCH := Color(0.74, 0.58, 0.28)
const THATCH_DARK := Color(0.55, 0.42, 0.20)
const DOOR := Color(0.24, 0.16, 0.10)
const WINDOW := Color(0.28, 0.20, 0.14)
const LOG := Color(0.30, 0.20, 0.12)
const FLAME := Color(1.0, 0.55, 0.10)
const FLAME_HOT := Color(1.0, 0.86, 0.35)
const RUIN := Color(0.50, 0.52, 0.50)
const RUIN_MOSS := Color(0.36, 0.47, 0.34)
const GRASS_BLADE := Color(0.33, 0.58, 0.24)
const GRASS_TIP := Color(0.52, 0.74, 0.34)

const SEED_HUSK := Color(0.62, 0.50, 0.30)
const STRANGE := Color(0.20, 0.23, 0.33)
const STRANGE_GLINT := Color(0.45, 0.80, 0.78)

## What a heap of each resource is made of (LooseObject.PILE_RESOURCES).
const PILE_COLORS := {
	&"berries": BERRY, &"meat": Color(0.62, 0.22, 0.20), &"fish": Color(0.55, 0.66, 0.74),
	&"grain": Color(0.86, 0.72, 0.32), &"water": Color(0.35, 0.58, 0.85), &"clay": Color(0.66, 0.44, 0.32),
	&"herbs": Color(0.40, 0.62, 0.36),
}
## Looks of a prop that has been worked on (ResourceNodes.Look), as an
## offset to the key of the shape.
const _LOOK_SHIFT := 1024

var _templates: Dictionary = {} # key -> Template
var _loose: Dictionary = {} # loose key -> Template
var _tuft: Template


func _init() -> void:
	_templates[_key(PropData.Kind.TREE, 0)] = _broadleaf(0.42, 1.55, 0.0)
	_templates[_key(PropData.Kind.TREE, 1)] = _broadleaf(0.36, 1.30, 0.5)
	_templates[_key(PropData.Kind.TREE, 2)] = _conifer(0.34, 1.75)
	_templates[_key(PropData.Kind.TREE, 3)] = _conifer(0.29, 1.45)
	_templates[_key(PropData.Kind.ROCK, 0)] = _rock(0.26, 0.20, 0.0)
	_templates[_key(PropData.Kind.ROCK, 1)] = _rock(0.19, 0.27, 0.7)
	_templates[_key(PropData.Kind.BUSH, 0)] = _bush(0.26, 0.26)
	_templates[_key(PropData.Kind.BUSH, 1)] = _bush(0.22, 0.31)
	_templates[_key(PropData.Kind.HUT, 0)] = _hut()
	_templates[_key(PropData.Kind.CAMPFIRE, 0)] = _campfire()
	_templates[_key(PropData.Kind.RUIN, 0)] = _ruin()
	# What is left of nodes that have given up what they had.
	for variant in 4:
		_templates[_look_key(PropData.Kind.TREE, variant, ResourceNodes.Look.STUMP)] = _stump(0.095 if variant < 2 else 0.08, 0.16)
	_templates[_look_key(PropData.Kind.BUSH, 0, ResourceNodes.Look.SPARSE)] = _bush(0.26, 0.26, 2)
	_templates[_look_key(PropData.Kind.BUSH, 1, ResourceNodes.Look.SPARSE)] = _bush(0.22, 0.31, 2)
	_templates[_look_key(PropData.Kind.BUSH, 0, ResourceNodes.Look.BARE)] = _bush(0.26, 0.26, 0)
	_templates[_look_key(PropData.Kind.BUSH, 1, ResourceNodes.Look.BARE)] = _bush(0.22, 0.31, 0)
	_tuft = _grass_tuft()
	# Loose objects (things that can be moved). Rocks look like the rock props
	# they replace; boulders are the same stone, bigger.
	_loose[loose_key(LooseObject.Kind.PEBBLE, 0)] = _rock(0.09, 0.07, 0.0)
	_loose[loose_key(LooseObject.Kind.PEBBLE, 1)] = _rock(0.075, 0.085, 0.6)
	_loose[loose_key(LooseObject.Kind.ROCK, 0)] = _rock(0.26, 0.20, 0.0)
	_loose[loose_key(LooseObject.Kind.ROCK, 1)] = _rock(0.19, 0.27, 0.7)
	_loose[loose_key(LooseObject.Kind.BOULDER, 0)] = _rock(0.42, 0.38, 0.3)
	_loose[loose_key(LooseObject.Kind.BOULDER, 1)] = _rock(0.37, 0.46, 0.9)
	_loose[loose_key(LooseObject.Kind.LOG, 0)] = _log(0.9, 0.11)
	_loose[loose_key(LooseObject.Kind.FRUIT, 0)] = _gem(0.06, 0.07, BERRY, BERRY.lightened(0.25))
	_loose[loose_key(LooseObject.Kind.SEED, 0)] = _gem(0.03, 0.03, SEED_HUSK, SEED_HUSK.lightened(0.2))
	_loose[loose_key(LooseObject.Kind.STRANGE_OBJECT, 0)] = _gem(0.11, 0.13, STRANGE, STRANGE_GLINT)
	# Piles of what has been gathered.
	for variant in LooseObject.PILE_RESOURCES.size():
		var resource := LooseObject.PILE_RESOURCES[variant]
		match resource:
			&"wood":
				_loose[loose_key(LooseObject.Kind.PILE, variant)] = _wood_pile()
			&"stone":
				_loose[loose_key(LooseObject.Kind.PILE, variant)] = _stone_pile()
			_:
				_loose[loose_key(LooseObject.Kind.PILE, variant)] = _heap(PILE_COLORS.get(resource, STONE))


## Key of a loose object's shape (kind + variant).
static func loose_key(kind: int, variant: int) -> int:
	return kind * 16 + (variant & 15)


## The shape of a loose object. Unknown variants fall back to variant 0.
func loose_template(kind: int, variant: int) -> Template:
	return loose_template_by_key(loose_key(kind, variant))


func loose_template_by_key(key: int) -> Template:
	var t: Template = _loose.get(key)
	if t == null:
		t = _loose.get(key - (key & 15))
	return t


func all_loose_templates() -> Array[Template]:
	var out: Array[Template] = []
	for t: Template in _loose.values():
		out.append(t)
	return out


## The shape for a prop — for how it looks now, if it has been worked on
## (ResourceNodes.Look; looks without a shape of their own use the whole
## one). Unknown variants fall back to variant 0 of the kind.
func template_for(kind: PropData.Kind, variant: int, look: int = 0) -> Template:
	if look != 0:
		var worked: Template = _templates.get(_look_key(kind, variant, look))
		if worked == null:
			worked = _templates.get(_look_key(kind, 0, look))
		if worked != null:
			return worked
	var t: Template = _templates.get(_key(kind, variant))
	if t == null:
		t = _templates.get(_key(kind, 0))
	return t


func grass_tuft() -> Template:
	return _tuft


func all_templates() -> Array[Template]:
	var out: Array[Template] = []
	for t: Template in _templates.values():
		out.append(t)
	out.append(_tuft)
	return out


static func _key(kind: int, variant: int) -> int:
	return kind * 16 + variant


static func _look_key(kind: int, variant: int, look: int) -> int:
	return _key(kind, variant) + look * _LOOK_SHIFT


# --- shapes ----------------------------------------------------------------------

static func _broadleaf(radius: float, height: float, twist: float) -> Template:
	var t := Template.new()
	var trunk_top := height * 0.42
	_band(t, _ring(0.0, 0.085, 5, twist), _ring(trunk_top, 0.06, 5, twist), _rgba(TRUNK_DARK, 0.0), _rgba(TRUNK, 0.25))
	# Canopy: a chunky blob — narrow bottom, wide middle, pointed top.
	var c0 := trunk_top - 0.08
	var bottom := _ring(c0, radius * 0.55, 6, twist)
	var middle := _ring(c0 + (height - c0) * 0.42, radius, 6, twist + 0.5)
	var upper := _ring(c0 + (height - c0) * 0.78, radius * 0.62, 6, twist)
	_fan(t, bottom, Vector3(0, c0 - 0.03, 0), _rgba(LEAF.darkened(0.2), 0.35), _rgba(LEAF.darkened(0.2), 0.3), true)
	_band(t, bottom, middle, _rgba(LEAF, 0.35), _rgba(LEAF, 0.6))
	_band(t, middle, upper, _rgba(LEAF, 0.6), _rgba(LEAF_LIGHT, 0.85))
	_fan(t, upper, Vector3(0, height, 0), _rgba(LEAF_LIGHT, 0.85), _rgba(LEAF_LIGHT, 1.0))
	return t


static func _conifer(radius: float, height: float) -> Template:
	var t := Template.new()
	var trunk_top := height * 0.22
	_band(t, _ring(0.0, 0.07, 5, 0.0), _ring(trunk_top, 0.055, 5, 0.0), _rgba(TRUNK_DARK, 0.0), _rgba(TRUNK, 0.15))
	# Three stacked cones, each smaller and lighter than the one below.
	var tiers := 3
	for i in tiers:
		var f0 := float(i) / tiers
		var f1 := float(i + 1) / tiers
		var y0 := lerpf(trunk_top - 0.05, height * 0.72, f0)
		var y1 := lerpf(trunk_top + (height - trunk_top) * 0.45, height, f1)
		var r := radius * lerpf(1.0, 0.5, f0)
		var sway0 := lerpf(0.25, 0.7, f0)
		var sway1 := lerpf(0.5, 1.0, f1)
		var col := PINE.lerp(PINE_LIGHT, f0)
		var skirt := _ring(y0, r, 6, i * 0.5)
		_fan(t, skirt, Vector3(0, y1, 0), _rgba(col, sway0), _rgba(col.lightened(0.08), sway1))
		_fan(t, skirt, Vector3(0, y0 + 0.02, 0), _rgba(col.darkened(0.25), sway0), _rgba(col.darkened(0.25), sway0), true)
	return t


static func _rock(radius: float, height: float, twist: float) -> Template:
	var t := Template.new()
	# A squashed, slightly lopsided lump: wide base, narrower off-centre top.
	var base := _ring(0.0, radius, 5, twist)
	var top := _ring(height, radius * 0.55, 5, twist + 0.35)
	for i in top.size():
		top[i] += Vector3(radius * 0.12, 0.0, -radius * 0.08)
	_band(t, base, top, _rgba(STONE_DARK, 0.0), _rgba(STONE, 0.0))
	_fan(t, top, Vector3(radius * 0.12, height + 0.02, -radius * 0.08), _rgba(STONE, 0.0), _rgba(STONE.lightened(0.1), 0.0))
	return t


## What is left of a felled tree: a short trunk with a pale cut top.
static func _stump(radius: float, height: float) -> Template:
	var t := Template.new()
	var base := _ring(0.0, radius * 1.15, 6, 0.0)
	var top := _ring(height, radius, 6, 0.0)
	_band(t, base, top, _rgba(TRUNK_DARK, 0.0), _rgba(TRUNK, 0.0))
	_fan(t, top, Vector3(0.0, height + 0.005, 0.0), _rgba(WALL_DARK, 0.0), _rgba(WALL, 0.0))
	return t


## A stack of cut logs: three on the ground, two on top.
static func _wood_pile() -> Template:
	var t := Template.new()
	var radius := 0.055
	var log := _log(0.5, radius)
	for i in 3:
		_merge(t, log, Transform3D(Basis(Vector3.UP, 0.04 * (i - 1)), Vector3(0.0, 0.0, (i - 1) * radius * 2.05)))
	for i in 2:
		_merge(t, log, Transform3D(Basis(Vector3.UP, -0.06 + 0.1 * i), Vector3(0.02, radius * 1.72, (i - 0.5) * radius * 2.05)))
	return t


## A heap of gathered stones.
static func _stone_pile() -> Template:
	var t := Template.new()
	var places := [Vector3(-0.12, 0.0, -0.05), Vector3(0.11, 0.0, -0.08), Vector3(0.0, 0.0, 0.12), Vector3(0.0, 0.09, 0.0)]
	for i in places.size():
		_merge(t, _rock(0.12 - 0.01 * i, 0.11, 0.3 * i), Transform3D(Basis(Vector3.UP, 0.9 * i), places[i]))
	return t


## A heap of something small (berries, grain, ...) on a mat.
static func _heap(color: Color) -> Template:
	var t := Template.new()
	var mat := _ring(0.012, 0.25, 7, 0.0)
	_fan(t, mat, Vector3(0.0, 0.02, 0.0), _rgba(THATCH_DARK, 0.0), _rgba(THATCH, 0.0))
	var skirt := _ring(0.02, 0.2, 7, 0.5)
	var shoulder := _ring(0.1, 0.11, 7, 0.0)
	_band(t, skirt, shoulder, _rgba(color.darkened(0.25), 0.0), _rgba(color, 0.0))
	_fan(t, shoulder, Vector3(0.0, 0.16, 0.0), _rgba(color, 0.0), _rgba(color.lightened(0.2), 0.0))
	return t


## Adds another shape to `t`, moved and turned.
static func _merge(t: Template, other: Template, xform: Transform3D) -> void:
	for i in other.vertices.size():
		t.vertices.append(xform * other.vertices[i])
		t.normals.append(xform.basis * other.normals[i])
		t.colors.append(other.colors[i])


static func _bush(radius: float, height: float, berries: int = 4) -> Template:
	var t := Template.new()
	var base := _ring(0.02, radius * 0.75, 6, 0.0)
	var middle := _ring(height * 0.55, radius, 6, 0.5)
	_band(t, base, middle, _rgba(BUSH, 0.1), _rgba(BUSH, 0.35))
	_fan(t, middle, Vector3(0, height, 0), _rgba(BUSH, 0.35), _rgba(BUSH_LIGHT, 0.5))
	# Berries: tiny bright diamonds sitting on the foliage.
	for i in berries:
		var angle := TAU * (i + 0.3) / 4.0
		var p := Vector3(cos(angle) * radius * 0.78, height * (0.45 + 0.12 * (i % 2)), sin(angle) * radius * 0.78)
		_diamond(t, p, 0.045, _rgba(BERRY, 0.35))
	return t


static func _hut() -> Template:
	var t := Template.new()
	var wall_h := 0.42
	var r := 0.40
	var base := _ring(0.0, r, 8, 0.5)
	var eaves := _ring(wall_h, r, 8, 0.5)
	_band(t, base, eaves, _rgba(WALL_DARK, 0.0), _rgba(WALL, 0.0))
	# Thatched cone roof with a generous overhang.
	var roof := _ring(wall_h - 0.04, r * 1.28, 8, 0.5)
	_fan(t, roof, Vector3(0, wall_h + 0.52, 0), _rgba(THATCH_DARK, 0.0), _rgba(THATCH, 0.0))
	_fan(t, roof, Vector3(0, wall_h, 0), _rgba(THATCH_DARK.darkened(0.3), 0.0), _rgba(THATCH_DARK.darkened(0.3), 0.0), true)
	# Doorway facing +X (PropData rotation turns it toward the fire), and a
	# small window to one side: dark by day, lit from within at night.
	var openings := t.vertices.size()
	_box(t, Vector3(r * 0.93, 0.15, 0.0), Vector3(0.03, 0.15, 0.10), _rgba(DOOR, 0.0))
	_box(t, Vector3(r * 0.66, 0.27, r * 0.66), Vector3(0.03, 0.055, 0.065), _rgba(WINDOW, 0.0), -PI * 0.25)
	t.glow_from(openings, 1.0)
	return t


static func _campfire() -> Template:
	var t := Template.new()
	for i in 6:
		var angle := TAU * i / 6.0
		_box(t, Vector3(cos(angle) * 0.20, 0.035, sin(angle) * 0.20), Vector3(0.055, 0.035, 0.045), _rgba(STONE_DARK, 0.0), angle)
	_box(t, Vector3(0, 0.04, 0), Vector3(0.14, 0.03, 0.03), _rgba(LOG, 0.0), 0.5)
	_box(t, Vector3(0, 0.06, 0), Vector3(0.14, 0.03, 0.03), _rgba(LOG, 0.0), 2.2)
	# Flame: sway weight above 1 makes it flicker more than leaves.
	var flame := _ring(0.07, 0.09, 5, 0.0)
	var burning := t.vertices.size()
	_fan(t, flame, Vector3(0, 0.36, 0), _rgba(FLAME, 0.6), _rgba(FLAME_HOT, 2.5))
	t.glow_from(burning, 2.0)
	return t


static func _ruin() -> Template:
	var t := Template.new()
	# Broken standing stones on a worn slab: clearly made, clearly old.
	_box(t, Vector3(0, 0.03, 0), Vector3(0.40, 0.03, 0.34), _rgba(RUIN.darkened(0.15), 0.0), 0.2)
	_box(t, Vector3(-0.24, 0.36, -0.14), Vector3(0.08, 0.33, 0.08), _rgba(RUIN, 0.0), 0.1)
	_box(t, Vector3(0.22, 0.25, -0.16), Vector3(0.08, 0.22, 0.08), _rgba(RUIN_MOSS, 0.0), -0.2)
	_box(t, Vector3(0.20, 0.14, 0.18), Vector3(0.08, 0.11, 0.08), _rgba(RUIN, 0.0), 0.4)
	_box(t, Vector3(-0.12, 0.09, 0.20), Vector3(0.19, 0.06, 0.07), _rgba(RUIN_MOSS, 0.0), 0.9) # fallen lintel
	return t


## A felled trunk lying on its side along X.
static func _log(length: float, radius: float) -> Template:
	var t := Template.new()
	var sides := 6
	var half := length * 0.5
	var axis_y := radius * 0.92 # sunk a little into the ground
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	for i in sides:
		var angle := TAU * i / sides
		var y := axis_y + cos(angle) * radius
		var z := sin(angle) * radius
		left.append(Vector3(-half, y, z))
		right.append(Vector3(half, y, z))
	var axis := Vector3(0.0, axis_y, 0.0)
	for i in sides:
		var j := (i + 1) % sides
		_quad_outward(t, left[i], right[i], right[j], left[j], _rgba(TRUNK if i % 2 == 0 else TRUNK_DARK, 0.0), axis)
		# Cut ends: paler wood.
		_tri_outward(t, left[i], left[j], Vector3(-half, axis_y, 0.0), _rgba(WALL, 0.0), _rgba(WALL, 0.0), _rgba(WALL_DARK, 0.0), axis)
		_tri_outward(t, right[i], right[j], Vector3(half, axis_y, 0.0), _rgba(WALL, 0.0), _rgba(WALL, 0.0), _rgba(WALL_DARK, 0.0), axis)
	return t


## A small faceted lump standing on the ground: fruit, seeds, strange things.
static func _gem(radius: float, half_height: float, color: Color, top_color: Color) -> Template:
	var t := Template.new()
	var center := Vector3(0.0, half_height, 0.0)
	var up := center + Vector3(0.0, half_height, 0.0)
	var down := center - Vector3(0.0, half_height, 0.0)
	var ring: Array[Vector3] = []
	for i in 5:
		var angle := TAU * i / 5.0
		ring.append(center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	for i in 5:
		var j := (i + 1) % 5
		_tri_outward(t, ring[i], ring[j], up, _rgba(color, 0.0), _rgba(color, 0.0), _rgba(top_color, 0.0), center)
		_tri_outward(t, ring[i], ring[j], down, _rgba(color, 0.0), _rgba(color, 0.0), _rgba(color.darkened(0.3), 0.0), center)
	return t


static func _grass_tuft() -> Template:
	var t := Template.new()
	for i in 3:
		var angle := TAU * i / 3.0 + 0.4
		var dir := Vector3(cos(angle), 0, sin(angle))
		var side := Vector3(-dir.z, 0, dir.x) * 0.035
		var base := dir * 0.05
		var tip := dir * 0.13 + Vector3(0, 0.20 + 0.04 * i, 0)
		# Two-sided blade (the prop shader culls back faces).
		_tri(t, base - side, base + side, tip, _rgba(GRASS_BLADE, 0.0), _rgba(GRASS_BLADE, 0.0), _rgba(GRASS_TIP, 0.9))
		_tri(t, base + side, base - side, tip, _rgba(GRASS_BLADE, 0.0), _rgba(GRASS_BLADE, 0.0), _rgba(GRASS_TIP, 0.9))
	return t


# --- building blocks ---------------------------------------------------------------

static func _rgba(color: Color, sway: float) -> Color:
	return Color(color.r, color.g, color.b, sway)


## Points of a horizontal ring, counter-clockwise seen from above.
static func _ring(y: float, radius: float, sides: int, phase: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i in sides:
		var angle := TAU * (i + phase) / sides
		points.append(Vector3(cos(angle) * radius, y, sin(angle) * radius))
	return points


## Side wall between two rings with the same point count.
static func _band(t: Template, lower: Array[Vector3], upper: Array[Vector3], lower_color: Color, upper_color: Color) -> void:
	var n := lower.size()
	for i in n:
		var j := (i + 1) % n
		_quad(t, lower[i], lower[j], upper[j], upper[i], lower_color, lower_color, upper_color, upper_color)


## Cone or cap from a ring to an apex. `underside` = the fan faces downward
## (a cap closing the bottom of a shape).
static func _fan(t: Template, ring: Array[Vector3], apex: Vector3, ring_color: Color, apex_color: Color, underside: bool = false) -> void:
	var n := ring.size()
	# For an underside, "outward" means away from a point high above it.
	var center: Variant = Vector3(0.0, apex.y + 10.0, 0.0) if underside else null
	for i in n:
		_tri_outward(t, ring[i], ring[(i + 1) % n], apex, ring_color, ring_color, apex_color, center)


static func _box(t: Template, center: Vector3, half: Vector3, color: Color, yaw: float = 0.0) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var c: Array[Vector3] = []
	for sy in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			for sx in [-1.0, 1.0]:
				c.append(center + basis * Vector3(half.x * sx, half.y * sy, half.z * sz))
	# Corner index = (y * 4) + (z * 2) + x. Faces listed by their four corners.
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	for f: Array in faces:
		_quad_outward(t, c[f[0]], c[f[1]], c[f[2]], c[f[3]], color, center)


static func _diamond(t: Template, center: Vector3, size: float, color: Color) -> void:
	var up := center + Vector3(0, size, 0)
	var down := center - Vector3(0, size, 0)
	var ring: Array[Vector3] = []
	for i in 4:
		var angle := TAU * i / 4.0
		ring.append(center + Vector3(cos(angle) * size, 0, sin(angle) * size))
	for i in 4:
		_tri_outward(t, ring[i], ring[(i + 1) % 4], up, color, color, color, center)
		_tri_outward(t, ring[i], ring[(i + 1) % 4], down, color, color, color, center)


static func _quad(t: Template, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_tri_outward(t, a, b, c, ca, cb, cc)
	_tri_outward(t, a, c, d, ca, cc, cd)


static func _quad_outward(t: Template, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, center: Vector3) -> void:
	_tri_outward(t, a, b, c, color, color, color, center)
	_tri_outward(t, a, c, d, color, color, color, center)


## Adds a triangle wound so its front faces away from `center` (default: the
## vertical axis through the origin at the triangle's own height).
static func _tri_outward(t: Template, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, center: Variant = null) -> void:
	var mid := (a + b + c) / 3.0
	var from: Vector3 = center if center != null else Vector3(0.0, mid.y, 0.0)
	var outward := mid - from
	# Godot front faces wind clockwise: front normal = (c - a) x (b - a).
	var normal := (c - a).cross(b - a)
	if outward.length_squared() < 0.0000001:
		outward = Vector3.UP
	if normal.dot(outward) < 0.0:
		_tri(t, a, c, b, ca, cc, cb)
	else:
		_tri(t, a, b, c, ca, cb, cc)


static func _tri(t: Template, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var normal := (c - a).cross(b - a).normalized()
	t.vertices.append(a); t.vertices.append(b); t.vertices.append(c)
	t.normals.append(normal); t.normals.append(normal); t.normals.append(normal)
	t.colors.append(ca); t.colors.append(cb); t.colors.append(cc)
