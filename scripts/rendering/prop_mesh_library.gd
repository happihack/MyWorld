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

	## How much of a leaf each vertex is (see prop.gdshader): 0 nothing that
	## changes with the seasons, up to 1 a leaf that turns in autumn and
	## falls in winter; in between what only changes colour (grass, bushes,
	## a little: needles). Shorter than `vertices` where nothing after it is.
	var leaf := PackedFloat32Array()

	## Marks everything added since vertex `from` as leaves.
	func leaf_from(from: int, value: float) -> void:
		leaf.resize(vertices.size())
		for i in range(from, vertices.size()):
			leaf[i] = value

	func leaf_of(index: int) -> float:
		return leaf[index] if index < leaf.size() else 0.0


## How much of a leaf a vertex is (Template.leaf): leaves that are shed,
## green that only turns colour, needles that hardly change.
const LEAF_SHED := 1.0
const LEAF_TURNS := 0.6
const LEAF_EVERGREEN := 0.2

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
const SOIL_DARK := Color(0.36, 0.26, 0.15)
const CROP_GREEN := Color(0.38, 0.62, 0.22)
const CROP_GOLD := Color(0.90, 0.74, 0.28)
const CROP_STRAW := Color(0.78, 0.68, 0.40)
const CROP_DRY := Color(0.66, 0.56, 0.26)
const CROP_DEAD := Color(0.42, 0.30, 0.18)
## Fired clay (M16.3: kilns and pots).
const CLAY := Color(0.70, 0.42, 0.28)
const NUT := Color(0.52, 0.36, 0.20)
const MUSHROOM_CAP := [Color(0.62, 0.42, 0.26), Color(0.80, 0.30, 0.22)]
const MUSHROOM_STEM := Color(0.90, 0.86, 0.76)
const ROOT_LEAF := Color(0.38, 0.56, 0.26)
const ROOT_TOP := Color(0.66, 0.36, 0.30)
const CLAY_DARK := Color(0.52, 0.30, 0.20)
const HERB := Color(0.42, 0.60, 0.30)
## Roofs of other cultures (M17.1): reeds, grey-green; hides, dark and low.
const REEDS := Color(0.62, 0.64, 0.46)
const REEDS_DARK := Color(0.44, 0.47, 0.32)
const HIDE := Color(0.50, 0.36, 0.26)
const HIDE_DARK := Color(0.36, 0.25, 0.18)

## What a heap of each resource is made of (LooseObject.PILE_RESOURCES).
const PILE_COLORS := {
	&"berries": BERRY, &"meat": Color(0.62, 0.22, 0.20), &"fish": Color(0.55, 0.66, 0.74),
	&"grain": Color(0.86, 0.72, 0.32), &"water": Color(0.35, 0.58, 0.85), &"clay": Color(0.66, 0.44, 0.32),
	&"herbs": Color(0.40, 0.62, 0.36),
	&"mushrooms": Color(0.74, 0.62, 0.48), &"roots": Color(0.55, 0.36, 0.24), &"nuts": Color(0.58, 0.42, 0.24),
}
## Looks of a prop that has been worked on (ResourceNodes.Look), as an
## offset to the key of the shape.
const _LOOK_SHIFT := 1024

var _templates: Dictionary = {} # key -> Template
var _loose: Dictionary = {} # loose key -> Template
var _tuft: Template
## A bridge's post below its deck, one unit tall (stretched down to the bed).
var _pile: Template


func _init() -> void:
	_templates[_key(PropData.Kind.TREE, 0)] = _broadleaf(0.42, 1.55, 0.0)
	_templates[_key(PropData.Kind.TREE, 1)] = _broadleaf(0.36, 1.30, 0.5)
	_templates[_key(PropData.Kind.TREE, 2)] = _conifer(0.34, 1.75)
	_templates[_key(PropData.Kind.TREE, 3)] = _conifer(0.29, 1.45)
	_templates[_key(PropData.Kind.ROCK, 0)] = _rock(0.26, 0.20, 0.0)
	_templates[_key(PropData.Kind.ROCK, 1)] = _rock(0.19, 0.27, 0.7)
	for variant in 2:
		_templates[_key(PropData.Kind.MUSHROOM, variant)] = _mushrooms(variant, 3)
		_templates[_look_key(PropData.Kind.MUSHROOM, variant, ResourceNodes.Look.SPARSE)] = _mushrooms(variant, 1)
		_templates[_look_key(PropData.Kind.MUSHROOM, variant, ResourceNodes.Look.BARE)] = _mushrooms(variant, 0)
		_templates[_key(PropData.Kind.ROOTS, variant)] = _roots(variant, false)
		_templates[_look_key(PropData.Kind.ROOTS, variant, ResourceNodes.Look.SPARSE)] = _roots(variant, false)
		_templates[_look_key(PropData.Kind.ROOTS, variant, ResourceNodes.Look.BARE)] = _roots(variant, true)
	_templates[_key(PropData.Kind.BUSH, 0)] = _bush(0.26, 0.26)
	_templates[_key(PropData.Kind.BUSH, 1)] = _bush(0.22, 0.31)
	_templates[_key(PropData.Kind.HUT, 0)] = _hut()
	# How other cultures roof their homes (M17.1): reeds, and hides.
	_templates[_key(PropData.Kind.HUT, 1)] = _hut(REEDS, REEDS_DARK)
	_templates[_key(PropData.Kind.HUT, 2)] = _hut(HIDE, HIDE_DARK, 0.42)
	_templates[_key(PropData.Kind.CAMPFIRE, 0)] = _campfire()
	_templates[_key(PropData.Kind.RUIN, 0)] = _ruin()
	_templates[_key(PropData.Kind.GRAVE, 0)] = _grave()
	for boat in PropData.Boat.size():
		_templates[_key(PropData.Kind.LANDING, boat)] = _landing(boat)
	for stones in Graves.MOST_STONES + 1:
		_templates[_key(PropData.Kind.CEMETERY, stones)] = _cemetery(stones)
	_templates[_key(PropData.Kind.SITE, ConstructionSystem.STAKES)] = _site_stakes()
	_templates[_key(PropData.Kind.SITE, ConstructionSystem.FRAME)] = _site_frame()
	_templates[_key(PropData.Kind.STOREHOUSE, 0)] = _storehouse()
	_templates[_key(PropData.Kind.WELL, 0)] = _well()
	_templates[_key(PropData.Kind.WORKSHOP, 0)] = _workshop()
	_templates[_key(PropData.Kind.WOODSHED, 0)] = _woodshed()
	_templates[_key(PropData.Kind.KILN, 0)] = _kiln()
	_templates[_key(PropData.Kind.HERB_RACK, 0)] = _herb_rack()
	_templates[_key(PropData.Kind.RECORD_STONE, 0)] = _record_stone(false)
	_templates[_key(PropData.Kind.RECORD_STONE, 1)] = _record_stone(true)
	_templates[_key(PropData.Kind.STONE_CIRCLE, 0)] = _stone_circle()
	_templates[_key(PropData.Kind.SHRINE, 0)] = _shrine()
	for stage in PropData.BRIDGE_DONE + 1:
		_templates[_key(PropData.Kind.BRIDGE, stage)] = _bridge(stage)
	# What is left of nodes that have given up what they had.
	for variant in 4:
		_templates[_look_key(PropData.Kind.TREE, variant, ResourceNodes.Look.STUMP)] = _stump(0.095 if variant < 2 else 0.08, 0.16)
	_templates[_look_key(PropData.Kind.BUSH, 0, ResourceNodes.Look.SPARSE)] = _bush(0.26, 0.26, 2)
	_templates[_look_key(PropData.Kind.BUSH, 1, ResourceNodes.Look.SPARSE)] = _bush(0.22, 0.31, 2)
	_templates[_look_key(PropData.Kind.BUSH, 0, ResourceNodes.Look.BARE)] = _bush(0.26, 0.26, 0)
	_templates[_look_key(PropData.Kind.BUSH, 1, ResourceNodes.Look.BARE)] = _bush(0.22, 0.31, 0)
	_templates[_look_key(PropData.Kind.CAMPFIRE, 0, ResourceNodes.Look.BARE)] = _campfire(false)
	# Crops: a plot of grain at each stage, and the dry look of those that stand.
	_templates[_key(PropData.Kind.CROP, Farming.Stage.SOWN)] = _crop(0.0, SOIL_DARK, SOIL_DARK, false)
	_templates[_key(PropData.Kind.CROP, Farming.Stage.SPROUT)] = _crop(0.10, CROP_GREEN, CROP_GREEN.lightened(0.15), false)
	_templates[_key(PropData.Kind.CROP, Farming.Stage.GROWING)] = _crop(0.26, CROP_GREEN, CROP_GREEN.lightened(0.2), false)
	_templates[_key(PropData.Kind.CROP, Farming.Stage.RIPE)] = _crop(0.36, CROP_GOLD.darkened(0.15), CROP_GOLD, true)
	_templates[_key(PropData.Kind.CROP, Farming.Stage.STUBBLE)] = _crop(0.05, CROP_STRAW.darkened(0.2), CROP_STRAW, false)
	_templates[_key(PropData.Kind.CROP, Farming.Stage.FAILED)] = _crop(0.13, CROP_DEAD.darkened(0.2), CROP_DEAD, false, 0.5)
	_templates[_key(PropData.Kind.CROP, Farming.Stage.SPROUT + Farming.DRY_VARIANT)] = _crop(0.09, CROP_DRY.darkened(0.1), CROP_DRY, false, 0.2)
	_templates[_key(PropData.Kind.CROP, Farming.Stage.GROWING + Farming.DRY_VARIANT)] = _crop(0.22, CROP_DRY.darkened(0.1), CROP_DRY, false, 0.3)
	_templates[_key(PropData.Kind.CROP, Farming.Stage.RIPE + Farming.DRY_VARIANT)] = _crop(0.3, CROP_DRY.darkened(0.15), CROP_DRY, true, 0.3)
	_tuft = _grass_tuft()
	_pile = Template.new()
	_box(_pile, Vector3(0.0, 0.5, 0.0), Vector3(0.035, 0.5, 0.035), _rgba(TRUNK_DARK, 0.0))
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
	_loose[loose_key(LooseObject.Kind.FRUIT, LooseObject.NUT_VARIANT)] = _gem(0.05, 0.06, NUT, NUT.lightened(0.25))
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
			&"tools":
				_loose[loose_key(LooseObject.Kind.PILE, variant)] = _tool_pile()
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


## A post of a bridge, from y 0 to 1 (Crossing: from the bed up to the deck).
func pile() -> Template:
	return _pile


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
	var canopy := t.vertices.size()
	var bottom := _ring(c0, radius * 0.55, 6, twist)
	var middle := _ring(c0 + (height - c0) * 0.42, radius, 6, twist + 0.5)
	var upper := _ring(c0 + (height - c0) * 0.78, radius * 0.62, 6, twist)
	_fan(t, bottom, Vector3(0, c0 - 0.03, 0), _rgba(LEAF.darkened(0.2), 0.35), _rgba(LEAF.darkened(0.2), 0.3), true)
	_band(t, bottom, middle, _rgba(LEAF, 0.35), _rgba(LEAF, 0.6))
	_band(t, middle, upper, _rgba(LEAF, 0.6), _rgba(LEAF_LIGHT, 0.85))
	_fan(t, upper, Vector3(0, height, 0), _rgba(LEAF_LIGHT, 0.85), _rgba(LEAF_LIGHT, 1.0))
	t.leaf_from(canopy, LEAF_SHED)
	return t


static func _conifer(radius: float, height: float) -> Template:
	var t := Template.new()
	var trunk_top := height * 0.22
	_band(t, _ring(0.0, 0.07, 5, 0.0), _ring(trunk_top, 0.055, 5, 0.0), _rgba(TRUNK_DARK, 0.0), _rgba(TRUNK, 0.15))
	# Three stacked cones, each smaller and lighter than the one below.
	var needles := t.vertices.size()
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
	t.leaf_from(needles, LEAF_EVERGREEN)
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


## A plot of field: three furrows across the tile with plants of `height`
## standing in them (none at 0: bare, sown earth). `heads`: ears of grain on
## top. `lean`: how far the plants hang over (wilting, withered).
static func _crop(height: float, stalk: Color, top: Color, heads: bool, lean: float = 0.0) -> Template:
	var t := Template.new()
	for row in 3:
		var z := (row - 1) * 0.3
		# The furrow: a low ridge of darker earth.
		_box(t, Vector3(0.0, 0.012, z), Vector3(0.44, 0.012, 0.07), _rgba(SOIL_DARK, 0.0))
		if height <= 0.0:
			continue
		for plant in 5:
			var x := (plant - 2) * 0.19 + (0.05 if row % 2 == 1 else -0.03)
			var tall := height * (0.85 + 0.15 * (((plant * 7 + row * 3) % 5) / 4.0))
			var foot := Vector3(x, 0.02, z)
			var tip := foot + Vector3(lean * tall * (1.0 if (plant + row) % 2 == 0 else -0.6), tall * (1.0 - lean * 0.5), lean * tall * 0.3)
			var side := Vector3(0.022, 0.0, 0.0)
			var depth := Vector3(0.0, 0.0, 0.022)
			var sway := 0.7 if lean < 0.4 else 0.15
			_quad(t, foot - side, foot + side, tip + side * 0.6, tip - side * 0.6, _rgba(stalk, 0.0), _rgba(stalk, 0.0), _rgba(top, sway), _rgba(top, sway))
			_quad(t, foot + side, foot - side, tip - side * 0.6, tip + side * 0.6, _rgba(stalk, 0.0), _rgba(stalk, 0.0), _rgba(top, sway), _rgba(top, sway))
			_quad(t, foot - depth, foot + depth, tip + depth * 0.6, tip - depth * 0.6, _rgba(stalk, 0.0), _rgba(stalk, 0.0), _rgba(top, sway), _rgba(top, sway))
			_quad(t, foot + depth, foot - depth, tip - depth * 0.6, tip + depth * 0.6, _rgba(stalk, 0.0), _rgba(stalk, 0.0), _rgba(top, sway), _rgba(top, sway))
			if heads:
				_diamond(t, tip + Vector3(0.0, 0.02, 0.0), 0.04, _rgba(top.lightened(0.1), sway))
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


## Tools laid together (M12.4): wooden handles with stone heads.
static func _tool_pile() -> Template:
	var t := Template.new()
	for i in 3:
		var yaw := -0.5 + 0.5 * i
		var at := Vector3((i - 1) * 0.07, 0.025 + 0.02 * (i % 2), (i - 1) * 0.03)
		_box(t, at, Vector3(0.2, 0.018, 0.018), _rgba(TRUNK, 0.0), yaw)
		var head := at + Vector3(cos(yaw), 0.0, -sin(yaw)) * 0.19 + Vector3(0.0, 0.02, 0.0)
		_box(t, head, Vector3(0.035, 0.04, 0.05), _rgba(STONE_DARK, 0.0), yaw)
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
	t.leaf_from(0, LEAF_TURNS)
	# Berries: tiny bright diamonds sitting on the foliage.
	for i in berries:
		var angle := TAU * (i + 0.3) / 4.0
		var p := Vector3(cos(angle) * radius * 0.78, height * (0.45 + 0.12 * (i % 2)), sin(angle) * radius * 0.78)
		_diamond(t, p, 0.045, _rgba(BERRY, 0.35))
	return t


static func _hut(roof_color: Color = THATCH, roof_dark: Color = THATCH_DARK, roof_height: float = 0.52) -> Template:
	var t := Template.new()
	var wall_h := 0.42
	var r := 0.40
	var base := _ring(0.0, r, 8, 0.5)
	var eaves := _ring(wall_h, r, 8, 0.5)
	_band(t, base, eaves, _rgba(WALL_DARK, 0.0), _rgba(WALL, 0.0))
	# Thatched cone roof with a generous overhang.
	var roof := _ring(wall_h - 0.04, r * 1.28, 8, 0.5)
	_fan(t, roof, Vector3(0, wall_h + roof_height, 0), _rgba(roof_dark, 0.0), _rgba(roof_color, 0.0))
	_fan(t, roof, Vector3(0, wall_h, 0), _rgba(roof_dark.darkened(0.3), 0.0), _rgba(roof_dark.darkened(0.3), 0.0), true)
	# Doorway facing +X (PropData rotation turns it toward the fire), and a
	# small window to one side: dark by day, lit from within at night.
	var openings := t.vertices.size()
	_box(t, Vector3(r * 0.93, 0.15, 0.0), Vector3(0.03, 0.15, 0.10), _rgba(DOOR, 0.0))
	_box(t, Vector3(r * 0.66, 0.27, r * 0.66), Vector3(0.03, 0.055, 0.065), _rgba(WINDOW, 0.0), -PI * 0.25)
	t.glow_from(openings, 1.0)
	return t


static func _campfire(burning: bool = true) -> Template:
	var t := Template.new()
	for i in 6:
		var angle := TAU * i / 6.0
		_box(t, Vector3(cos(angle) * 0.20, 0.035, sin(angle) * 0.20), Vector3(0.055, 0.035, 0.045), _rgba(STONE_DARK, 0.0), angle)
	# (A fire that has gone out: charred ends, no flame.)
	var wood := LOG if burning else LOG.darkened(0.55)
	_box(t, Vector3(0, 0.04, 0), Vector3(0.14, 0.03, 0.03), _rgba(wood, 0.0), 0.5)
	_box(t, Vector3(0, 0.06, 0), Vector3(0.14, 0.03, 0.03), _rgba(wood, 0.0), 2.2)
	if not burning:
		return t
	# Flame: sway weight above 1 makes it flicker more than leaves.
	var flame := _ring(0.07, 0.09, 5, 0.0)
	var lit_from := t.vertices.size()
	_fan(t, flame, Vector3(0, 0.36, 0), _rgba(FLAME, 0.6), _rgba(FLAME_HOT, 2.5))
	t.glow_from(lit_from, 2.0)
	return t


## A building site, staked out (M12.1): corner stakes, a line between
## them, and the first logs laid by.
static func _site_stakes() -> Template:
	var t := Template.new()
	for corner: Vector2 in [Vector2(-0.36, -0.36), Vector2(0.36, -0.36), Vector2(0.36, 0.36), Vector2(-0.36, 0.36)]:
		_box(t, Vector3(corner.x, 0.09, corner.y), Vector3(0.025, 0.09, 0.025), _rgba(TRUNK_DARK, 0.0))
	for side in 4:
		var yaw := PI * 0.5 * side
		var mid := Vector3(cos(yaw) * 0.36, 0.14, sin(yaw) * 0.36)
		_box(t, mid, Vector3(0.006, 0.006, 0.36), _rgba(CROP_STRAW, 0.0), yaw)
	_box(t, Vector3(0.0, 0.035, 0.12), Vector3(0.22, 0.035, 0.035), _rgba(LOG, 0.0), 0.2)
	_box(t, Vector3(0.02, 0.035, 0.03), Vector3(0.22, 0.035, 0.035), _rgba(LOG, 0.0), 0.15)
	_box(t, Vector3(0.0, 0.10, 0.08), Vector3(0.20, 0.035, 0.035), _rgba(LOG.lightened(0.1), 0.0), 0.18)
	return t


## A building going up: posts, beams, and walls half raised.
static func _site_frame() -> Template:
	var t := Template.new()
	var r := 0.36
	for corner: Vector2 in [Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)]:
		_box(t, Vector3(corner.x, 0.30, corner.y), Vector3(0.035, 0.30, 0.035), _rgba(TRUNK, 0.0))
	for side in 4:
		var yaw := PI * 0.5 * side
		_box(t, Vector3(cos(yaw) * r, 0.59, sin(yaw) * r), Vector3(0.03, 0.03, r + 0.03), _rgba(TRUNK_DARK, 0.0), yaw)
		_box(t, Vector3(cos(yaw) * r, 0.12, sin(yaw) * r), Vector3(0.025, 0.12, r * 0.9), _rgba(WALL_DARK, 0.0), yaw)
	_box(t, Vector3(0.0, 0.70, 0.0), Vector3(0.03, 0.12, 0.03), _rgba(TRUNK, 0.0))
	return t


## A storehouse: a log store raised off the ground, under a pitched thatch.
static func _storehouse() -> Template:
	var t := Template.new()
	for corner: Vector2 in [Vector2(-0.34, -0.26), Vector2(0.34, -0.26), Vector2(0.34, 0.26), Vector2(-0.34, 0.26)]:
		_box(t, Vector3(corner.x, 0.06, corner.y), Vector3(0.05, 0.06, 0.05), _rgba(STONE_DARK, 0.0))
	_box(t, Vector3(0.0, 0.32, 0.0), Vector3(0.40, 0.20, 0.30), _rgba(LOG, 0.0))
	for row in 4:
		_box(t, Vector3(0.0, 0.16 + row * 0.1, 0.305), Vector3(0.41, 0.012, 0.012), _rgba(TRUNK_DARK, 0.0))
	var roof := _ring(0.50, 0.66, 4, 0.5)
	_fan(t, roof, Vector3(0, 0.86, 0), _rgba(THATCH_DARK, 0.0), _rgba(THATCH, 0.0))
	_fan(t, roof, Vector3(0, 0.52, 0), _rgba(THATCH_DARK.darkened(0.3), 0.0), _rgba(THATCH_DARK.darkened(0.3), 0.0), true)
	_box(t, Vector3(0.405, 0.28, 0.0), Vector3(0.012, 0.12, 0.09), _rgba(DOOR, 0.0))
	return t


## A well: a ring of stones, two posts, a crossbar and a little roof.
static func _well() -> Template:
	var t := Template.new()
	for i in 8:
		var angle := TAU * i / 8.0
		_box(t, Vector3(cos(angle) * 0.22, 0.11, sin(angle) * 0.22), Vector3(0.07, 0.11, 0.05), _rgba(STONE if i % 2 == 0 else STONE_DARK, 0.0), angle)
	_box(t, Vector3(0.0, 0.02, 0.0), Vector3(0.16, 0.01, 0.16), _rgba(STRANGE, 0.0))
	for side: float in [-1.0, 1.0]:
		_box(t, Vector3(side * 0.26, 0.34, 0.0), Vector3(0.025, 0.34, 0.025), _rgba(TRUNK, 0.0))
	_box(t, Vector3(0.0, 0.52, 0.0), Vector3(0.26, 0.018, 0.018), _rgba(TRUNK_DARK, 0.0))
	_box(t, Vector3(0.0, 0.70, 0.08), Vector3(0.32, 0.015, 0.11), _rgba(THATCH, 0.0))
	_box(t, Vector3(0.0, 0.70, -0.08), Vector3(0.32, 0.015, 0.11), _rgba(THATCH_DARK, 0.0))
	return t


## A workshop: an open shed with a bench under it.
static func _workshop() -> Template:
	var t := Template.new()
	for corner: Vector2 in [Vector2(-0.38, -0.30), Vector2(0.38, -0.30), Vector2(0.38, 0.30), Vector2(-0.38, 0.30)]:
		_box(t, Vector3(corner.x, 0.30, corner.y), Vector3(0.03, 0.30, 0.03), _rgba(TRUNK, 0.0))
	_box(t, Vector3(0.0, 0.62, 0.0), Vector3(0.46, 0.03, 0.38), _rgba(THATCH, 0.0))
	_box(t, Vector3(0.0, 0.20, -0.12), Vector3(0.28, 0.02, 0.10), _rgba(LOG.lightened(0.15), 0.0))
	_box(t, Vector3(0.0, 0.10, -0.12), Vector3(0.025, 0.10, 0.08), _rgba(TRUNK_DARK, 0.0))
	return t


## Mushrooms (the owner, 2026-10-06): `count` of them in a clump, pale stems
## and round caps — brown (variant 0) or red (1); none: the ground they grew from.
static func _mushrooms(variant: int, count: int) -> Template:
	var t := Template.new()
	_box(t, Vector3(0.0, 0.004, 0.0), Vector3(0.12, 0.004, 0.10), _rgba(SOIL_DARK, 0.0))
	var spots := [Vector2(0.0, 0.0), Vector2(0.09, 0.05), Vector2(-0.07, 0.06)]
	var sizes := [1.0, 0.75, 0.6]
	for i in count:
		var at: Vector2 = spots[i]
		var s: float = sizes[i]
		_box(t, Vector3(at.x, 0.05 * s, at.y), Vector3(0.016 * s, 0.05 * s, 0.016 * s), _rgba(MUSHROOM_STEM, 0.0))
		var cap := _ring(0.1 * s, 0.07 * s, 7, 0.0)
		for n in cap.size():
			cap[n] += Vector3(at.x, 0.0, at.y)
		_fan(t, cap, Vector3(at.x, 0.14 * s, at.y), _rgba(MUSHROOM_CAP[variant], 0.0), _rgba(MUSHROOM_CAP[variant].lightened(0.2), 0.0))
		_fan(t, cap, Vector3(at.x, 0.09 * s, at.y), _rgba(MUSHROOM_STEM.darkened(0.2), 0.0), _rgba(MUSHROOM_STEM.darkened(0.2), 0.0), true)
	return t


## Wild roots: a tuft of leaves with a red root-top showing (dug: bare earth).
static func _roots(variant: int, dug: bool) -> Template:
	var t := Template.new()
	_box(t, Vector3(0.0, 0.006, 0.0), Vector3(0.14, 0.006, 0.12), _rgba(SOIL_DARK, 0.0))
	if dug:
		return t
	_box(t, Vector3(0.0, 0.03, 0.0), Vector3(0.045, 0.03, 0.045), _rgba(ROOT_TOP if variant == 0 else ROOT_TOP.lightened(0.2), 0.0))
	for i in 5:
		var angle := TAU * i / 5.0 + variant * 0.4
		var tip := Vector3(cos(angle) * 0.12, 0.2, sin(angle) * 0.12)
		_box(t, tip * 0.5 + Vector3(0.0, 0.02, 0.0), Vector3(0.018, 0.1, 0.018), _rgba(ROOT_LEAF, 0.3), -angle)
	return t


## A woodshed: a lean-to, a plank wall at the back and a roof sloping down
## to it, open in front — the wood and stone kept in it can be seen.
static func _woodshed() -> Template:
	var t := Template.new()
	for corner: Vector3 in [Vector3(-0.42, 0.66, 0.36), Vector3(0.42, 0.66, 0.36), Vector3(-0.42, 0.46, -0.36), Vector3(0.42, 0.46, -0.36)]:
		_box(t, Vector3(corner.x, corner.y * 0.5, corner.z), Vector3(0.03, corner.y * 0.5, 0.03), _rgba(TRUNK, 0.0))
	_box(t, Vector3(0.0, 0.23, -0.37), Vector3(0.42, 0.23, 0.02), _rgba(LOG, 0.0))
	for row in 3:
		_box(t, Vector3(0.0, 0.10 + row * 0.13, -0.345), Vector3(0.43, 0.012, 0.012), _rgba(TRUNK_DARK, 0.0))
	var front_left := Vector3(-0.50, 0.68, 0.44)
	var front_right := Vector3(0.50, 0.68, 0.44)
	var back_right := Vector3(0.50, 0.47, -0.44)
	var back_left := Vector3(-0.50, 0.47, -0.44)
	_quad_outward(t, front_left, front_right, back_right, back_left, _rgba(THATCH, 0.0), Vector3(0.0, -2.0, 0.0))
	var under := Vector3(0.0, -0.012, 0.0)
	_quad_outward(t, front_left + under, front_right + under, back_right + under, back_left + under,
		_rgba(THATCH_DARK.darkened(0.3), 0.0), Vector3(0.0, 3.0, 0.0))
	return t


## A kiln (M16.3, pottery): a clay dome with a dark mouth, its fire's
## glow inside, and pots set out to cool beside it.
static func _kiln() -> Template:
	var t := Template.new()
	var rings: Array = []
	for level in 5:
		var h := level * 0.11
		rings.append(_ring(h, 0.30 * cos(level * 0.32), 8, 0.0))
	for i in 4:
		_band(t, rings[i], rings[i + 1], _rgba(CLAY_DARK if i == 0 else CLAY, 0.0), _rgba(CLAY, 0.0))
	_fan(t, rings[4], Vector3(0, 0.50, 0), _rgba(CLAY, 0.0), _rgba(CLAY_DARK, 0.0))
	var mouth := t.vertices.size()
	_box(t, Vector3(0.27, 0.10, 0.0), Vector3(0.03, 0.08, 0.09), _rgba(FLAME, 0.0))
	t.glow_from(mouth, 0.6)
	_box(t, Vector3(0.0, 0.56, 0.0), Vector3(0.05, 0.06, 0.05), _rgba(CLAY_DARK, 0.0)) # the chimney
	for spot: Vector3 in [Vector3(-0.30, 0.0, 0.26), Vector3(-0.16, 0.0, 0.34), Vector3(0.05, 0.0, 0.36)]:
		var low := _ring(spot.y, 0.045, 6, 0.0)
		var belly := _ring(spot.y + 0.07, 0.065, 6, 0.0)
		var neck := _ring(spot.y + 0.13, 0.035, 6, 0.0)
		for ring: Array[Vector3] in [low, belly, neck]:
			for i in ring.size():
				ring[i] += Vector3(spot.x, 0.0, spot.z)
		_band(t, low, belly, _rgba(CLAY_DARK, 0.0), _rgba(CLAY, 0.0))
		_band(t, belly, neck, _rgba(CLAY, 0.0), _rgba(CLAY_DARK, 0.0))
	return t


## A rack for drying herbs (M16.3, medicine): two posts, a pole, bundles hanging.
static func _herb_rack() -> Template:
	var t := Template.new()
	for side: float in [-1.0, 1.0]:
		_box(t, Vector3(side * 0.32, 0.30, 0.0), Vector3(0.025, 0.30, 0.025), _rgba(TRUNK, 0.0))
	_box(t, Vector3(0.0, 0.58, 0.0), Vector3(0.36, 0.018, 0.018), _rgba(TRUNK_DARK, 0.0))
	for i in 5:
		var x := -0.24 + i * 0.12
		_box(t, Vector3(x, 0.47, 0.0), Vector3(0.035, 0.09, 0.035), _rgba(HERB if i % 2 == 0 else HERB.darkened(0.2), 0.3))
	_box(t, Vector3(0.0, 0.08, 0.20), Vector3(0.14, 0.08, 0.08), _rgba(LOG, 0.0)) # a basket of what was picked
	_box(t, Vector3(0.0, 0.165, 0.20), Vector3(0.12, 0.01, 0.06), _rgba(HERB, 0.0))
	return t


## A stone for keeping records (M16.3, writing): a standing slab with rows of
## marks cut into it — and, once they can count (`tallies`), rows of tallies.
static func _record_stone(tallies: bool) -> Template:
	var t := Template.new()
	_box(t, Vector3(0.0, 0.04, 0.0), Vector3(0.24, 0.04, 0.16), _rgba(STONE_DARK, 0.0))
	_box(t, Vector3(0.0, 0.42, 0.0), Vector3(0.18, 0.34, 0.06), _rgba(STONE, 0.0))
	_box(t, Vector3(0.0, 0.78, 0.0), Vector3(0.15, 0.03, 0.055), _rgba(STONE, 0.0))
	for row in 5:
		var y := 0.66 - row * 0.1
		for mark in 3 + (row % 2):
			_box(t, Vector3(-0.11 + mark * 0.07, y, 0.062), Vector3(0.022, 0.012, 0.004), _rgba(STONE_DARK.darkened(0.3), 0.0))
	if tallies:
		for row in 3:
			for mark in 5:
				_box(t, Vector3(-0.12 + mark * 0.05, 0.62 - row * 0.15, -0.062), Vector3(0.006, 0.04, 0.004), _rgba(STONE_DARK.darkened(0.4), 0.0))
	return t


## A circle of standing stones (M16.3, astronomy): to watch where the sun
## rises and the stars turn.
static func _stone_circle() -> Template:
	var t := Template.new()
	for i in 7:
		var angle := TAU * i / 7.0
		var tall := 0.26 + 0.08 * float((i * 3) % 4) / 3.0
		_box(t, Vector3(cos(angle) * 0.40, tall, sin(angle) * 0.40), Vector3(0.06, tall, 0.045),
			_rgba(STONE if i % 2 == 0 else STONE_DARK, 0.0), -angle)
	_box(t, Vector3(0.0, 0.03, 0.0), Vector3(0.12, 0.03, 0.12), _rgba(STONE_DARK, 0.0), 0.4) # the flat stone at its heart
	return t


## A shrine (M17.2): a small roofed stone at a sacred place, offerings before it.
static func _shrine() -> Template:
	var t := Template.new()
	_box(t, Vector3(0.0, 0.05, 0.0), Vector3(0.26, 0.05, 0.22), _rgba(STONE_DARK, 0.0))
	_box(t, Vector3(0.0, 0.28, -0.04), Vector3(0.10, 0.18, 0.08), _rgba(STONE, 0.0))
	for side: float in [-1.0, 1.0]:
		_box(t, Vector3(side * 0.20, 0.30, -0.04), Vector3(0.022, 0.25, 0.022), _rgba(TRUNK, 0.0))
	_box(t, Vector3(0.0, 0.58, -0.04), Vector3(0.28, 0.02, 0.16), _rgba(THATCH_DARK, 0.0))
	var glow := t.vertices.size()
	_box(t, Vector3(0.0, 0.16, 0.10), Vector3(0.025, 0.04, 0.025), _rgba(FLAME_HOT, 0.0)) # a small flame
	t.glow_from(glow, 0.7)
	for x: float in [-0.12, 0.13]:
		_box(t, Vector3(x, 0.13, 0.12), Vector3(0.03, 0.03, 0.03), _rgba(BERRY if x < 0.0 else CLAY, 0.0)) # offerings
	return t


## A footbridge over a ford (M12.2), running north–south (turned by the
## prop's rotation): posts driven into the bed (0), beams laid on them (1),
## then a deck of planks with a rail (PropData.BRIDGE_DONE). Its deck is
## PropData.BRIDGE_DECK above the bed, over the water of a ford.
static func _bridge(stage: int) -> Template:
	var t := Template.new()
	var deck := PropData.BRIDGE_DECK
	for z: float in [-0.42, 0.0, 0.42]:
		for x: float in [-0.24, 0.24]:
			_box(t, Vector3(x, deck * 0.5 + 0.01, z), Vector3(0.03, deck * 0.5 + 0.01, 0.03), _rgba(TRUNK_DARK, 0.0))
	if stage >= 1:
		for x: float in [-0.22, 0.22]:
			_box(t, Vector3(x, deck - 0.03, 0.0), Vector3(0.025, 0.025, 0.5), _rgba(TRUNK, 0.0))
	if stage >= PropData.BRIDGE_DONE:
		for i in 6:
			var z := -0.42 + i * 0.168
			var tone := LOG.lightened(0.18 if i % 2 == 0 else 0.1)
			_box(t, Vector3(0.0, deck + 0.01, z), Vector3(0.27, 0.018, 0.078), _rgba(tone, 0.0))
		for x: float in [-0.26, 0.26]:
			for z: float in [-0.42, 0.42]:
				_box(t, Vector3(x, deck + 0.13, z), Vector3(0.018, 0.12, 0.018), _rgba(TRUNK, 0.0))
			_box(t, Vector3(x, deck + 0.24, 0.0), Vector3(0.015, 0.015, 0.44), _rgba(TRUNK_DARK, 0.0))
	return t


## A grave: a low mound of earth with a standing stone at its head.
static func _grave() -> Template:
	var t := Template.new()
	_box(t, Vector3(0, 0.035, 0.03), Vector3(0.16, 0.035, 0.30), _rgba(SOIL_DARK, 0.0), 0.0)
	_box(t, Vector3(0, 0.075, 0.05), Vector3(0.11, 0.03, 0.22), _rgba(SOIL_DARK.lightened(0.12), 0.0), 0.0)
	_box(t, Vector3(0, 0.17, -0.30), Vector3(0.10, 0.17, 0.035), _rgba(STONE, 0.0), 0.0)
	_box(t, Vector3(0, 0.345, -0.30), Vector3(0.07, 0.015, 0.03), _rgba(STONE_DARK, 0.0), 0.0)
	return t


## A landing (M19.5): a short jetty of planks out over the water (towards -Z,
## turned by the prop's rotation), on two posts — and the boat moored beside
## it, as the settlement has come to build them: a raft of lashed logs, a
## dugout canoe, a boat of planks, a boat with a mast and sail.
## A landing: the jetty (its boats are things of their own now, drawn by the
## BoatsView — FB2; `boat` stays in the key for older worlds).
static func _landing(_boat: int) -> Template:
	var t := Template.new()
	for z: float in [0.25, -0.05, -0.35]:
		_box(t, Vector3(0.0, 0.10, z), Vector3(0.20, 0.025, 0.13), _rgba(TRUNK if int(z * 20.0) % 2 == 0 else TRUNK_DARK, 0.0), 0.0)
	for x: float in [-0.17, 0.17]:
		_box(t, Vector3(x, 0.07, -0.42), Vector3(0.025, 0.07, 0.025), _rgba(TRUNK_DARK, 0.0), 0.0)
	return t


## A boat of `kind` (PropData.Boat) about its middle, its keel a little under
## the water line, along Z (FB2).
static func boat_template(kind: int) -> Template:
	var t := Template.new()
	_boat_parts(t, kind)
	for i in t.vertices.size():
		t.vertices[i] += BOAT_CENTRE
	return t


## (Where a boat lay in the landing's frame, and how deep it sits.)
const BOAT_CENTRE := Vector3(-0.42, -0.035, 0.12)


static func _boat_parts(t: Template, boat: int) -> void:
	match boat:
		PropData.Boat.RAFT:
			for i in 4:
				_box(t, Vector3(0.36 + i * 0.07, 0.04, -0.15), Vector3(0.032, 0.03, 0.22), _rgba(TRUNK if i % 2 == 0 else TRUNK_DARK, 0.0), 0.0)
			_box(t, Vector3(0.46, 0.08, -0.15), Vector3(0.14, 0.012, 0.02), _rgba(WALL_DARK, 0.0), 0.0) # the lashing
		PropData.Boat.CANOE:
			_box(t, Vector3(0.40, 0.05, -0.12), Vector3(0.07, 0.045, 0.30), _rgba(TRUNK, 0.0), 0.0)
			_box(t, Vector3(0.40, 0.085, -0.12), Vector3(0.045, 0.012, 0.26), _rgba(TRUNK_DARK.darkened(0.3), 0.0), 0.0) # hollowed
			_box(t, Vector3(0.40, 0.10, 0.10), Vector3(0.01, 0.012, 0.16), _rgba(WALL, 0.0), 0.35) # a paddle laid across
		PropData.Boat.PLANK_BOAT, PropData.Boat.SAIL:
			_box(t, Vector3(0.42, 0.06, -0.12), Vector3(0.11, 0.06, 0.34), _rgba(WALL_DARK, 0.0), 0.0)
			_box(t, Vector3(0.42, 0.10, -0.12), Vector3(0.085, 0.02, 0.30), _rgba(TRUNK_DARK, 0.0), 0.0)
			for z: float in [-0.30, -0.12, 0.06]:
				_box(t, Vector3(0.42, 0.125, z), Vector3(0.10, 0.008, 0.02), _rgba(WALL, 0.0), 0.0) # the thwarts
			if boat == PropData.Boat.SAIL:
				_box(t, Vector3(0.42, 0.42, -0.14), Vector3(0.012, 0.30, 0.012), _rgba(TRUNK, 0.0), 0.0) # the mast
				_box(t, Vector3(0.42, 0.45, -0.06), Vector3(0.006, 0.20, 0.08), _rgba(WALL.lightened(0.3), 0.0), 0.0) # the sail


## A cemetery: a fenced plot (its gate to the south), a headstone and a mound
## for each of the dead laid there, up to `stones`, filling row by row.
static func _cemetery(stones: int) -> Template:
	var t := Template.new()
	var edge := 1.3
	_box(t, Vector3(0, 0.01, 0), Vector3(edge, 0.01, edge), _rgba(SOIL_DARK.lightened(0.25), 0.0), 0.0)
	# Posts at the corners and between; two rails on each side, a gap for the gate.
	for i in 5:
		var along := -edge + edge * 0.5 * i
		for post: Vector3 in [Vector3(along, 0, -edge), Vector3(along, 0, edge), Vector3(-edge, 0, along), Vector3(edge, 0, along)]:
			if post.z == edge and absf(post.x) < 0.01:
				continue
			_box(t, post + Vector3(0, 0.17, 0), Vector3(0.03, 0.17, 0.03), _rgba(TRUNK_DARK, 0.0), 0.0)
	for rail_y: float in [0.13, 0.26]:
		_box(t, Vector3(0, rail_y, -edge), Vector3(edge, 0.012, 0.015), _rgba(TRUNK, 0.0), 0.0)
		_box(t, Vector3(-edge, rail_y, 0), Vector3(0.015, 0.012, edge), _rgba(TRUNK, 0.0), 0.0)
		_box(t, Vector3(edge, rail_y, 0), Vector3(0.015, 0.012, edge), _rgba(TRUNK, 0.0), 0.0)
		for side: float in [-1.0, 1.0]:
			_box(t, Vector3(side * edge * 0.6, rail_y, edge), Vector3(edge * 0.4 - 0.08, 0.012, 0.015), _rgba(TRUNK, 0.0), 0.0)
	for n in stones:
		var at := Vector3(-0.72 + 0.72 * (n % 3), 0.0, -0.80 + 0.72 * floorf(n / 3.0))
		_box(t, at + Vector3(0, 0.03, 0.14), Vector3(0.11, 0.03, 0.18), _rgba(SOIL_DARK, 0.0), 0.0)
		_box(t, at + Vector3(0, 0.13, -0.08), Vector3(0.08, 0.13, 0.03), _rgba(STONE if n % 2 == 0 else STONE_DARK, 0.0), 0.0)
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
	t.leaf_from(0, LEAF_TURNS)
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
