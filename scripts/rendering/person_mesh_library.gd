class_name PersonMeshLibrary
extends RefCounted
## The shapes and colours people are drawn with (bible §28.4): one body mesh
## for everyone (told apart by colour, size and bearing in person.gdshader),
## and the few things they carry.
##
## Everything is built 1 unit tall, standing on the origin, facing +X; a view
## scales it to the person's height.

## Height of a grown person in world units. People are drawn larger than
## their huts would have them (a doorway is 0.30 high), like figures on a game
## board: they are what the player looks for.
const ADULT_HEIGHT := 0.5
## How stocky the figures are (1 = as modelled).
const BUILD := 1.12

## Colours a person's appearance indexes (sizes fixed by PersonData).
const SKIN: Array[Color] = [
	Color(0.96, 0.80, 0.66), Color(0.89, 0.69, 0.52), Color(0.78, 0.57, 0.40),
	Color(0.64, 0.44, 0.29), Color(0.48, 0.32, 0.21), Color(0.35, 0.23, 0.16),
]
const HAIR: Array[Color] = [
	Color(0.10, 0.08, 0.07), Color(0.24, 0.15, 0.09), Color(0.42, 0.26, 0.13),
	Color(0.62, 0.42, 0.18), Color(0.50, 0.20, 0.10),
]
## Saturated, against the muted land (bible §28.3).
const CLOTH: Array[Color] = [
	Color(0.80, 0.25, 0.20), Color(0.93, 0.66, 0.16), Color(0.22, 0.45, 0.78),
	Color(0.58, 0.28, 0.66), Color(0.90, 0.44, 0.16), Color(0.92, 0.90, 0.82),
]
## Woven and dyed (M16.3, weaving): madder, indigo, saffron, woad, a purple
## from berries, a green from bark — deeper than undyed cloth.
const CLOTH_DYED: Array[Color] = [
	Color(0.62, 0.10, 0.16), Color(0.16, 0.20, 0.55), Color(0.86, 0.62, 0.06),
	Color(0.10, 0.44, 0.44), Color(0.46, 0.16, 0.44), Color(0.22, 0.46, 0.20),
]
const ELDER_HAIR := Color(0.78, 0.78, 0.76)

const WOOD := Color(0.42, 0.29, 0.18)
const WICKER := Color(0.74, 0.58, 0.28)
const WICKER_DARK := Color(0.55, 0.42, 0.20)
const STONE := Color(0.56, 0.56, 0.58)
const PARCHMENT := Color(0.90, 0.84, 0.66)

const ACCESSORIES: Array[StringName] = [&"staff", &"basket", &"axe", &"hoe", &"spear", &"scroll", &"rod", &"bow"]

# Mask colours for the body mesh: COLOR.rgb = cloth / skin / hair, COLOR.a = shade.
const _TUNIC := Color(1, 0, 0, 1.0)
const _TUNIC_HEM := Color(1, 0, 0, 0.82)
const _TROUSERS := Color(1, 0, 0, 0.55)
const _SKIN := Color(0, 1, 0, 1.0)
const _HAIR := Color(0, 0, 1, 1.0)
const _EYE := Color(0, 0, 0, 1.0)

static var _body: ArrayMesh
static var _accessories: Dictionary = {} # StringName -> ArrayMesh
static var _loads: Dictionary = {} # resource id -> ArrayMesh


## The body everyone shares.
static func body() -> ArrayMesh:
	if _body == null:
		_body = _build_body()
	return _body


## What someone is drawn carrying: what they took up to hunt or fight with
## (PR6), else their trade's own thing.
static func accessory_for(person: PersonData, def: OccupationDef) -> StringName:
	if person.armed != &"":
		return person.armed
	return def.accessory if def != null else &""


## The mesh of something carried ("staff", "basket", "axe"); null for
## anything else, including &"".
static func accessory(kind: StringName) -> ArrayMesh:
	if not ACCESSORIES.has(kind):
		return null
	if not _accessories.has(kind):
		_accessories[kind] = _build_accessory(kind)
	return _accessories[kind]


## What someone carrying `resource` has in their arms: logs on the
## shoulder, a stone held low, or an armful in a carrying cloth. Null for &"".
static func load_mesh(resource: StringName) -> ArrayMesh:
	if resource == &"":
		return null
	if not _loads.has(resource):
		_loads[resource] = _build_load(resource)
	return _loads[resource]


static func skin(index: int) -> Color:
	return SKIN[posmod(index, SKIN.size())]


static func hair(index: int, stage: PersonData.LifeStage) -> Color:
	return ELDER_HAIR if stage == PersonData.LifeStage.ELDER else HAIR[posmod(index, HAIR.size())]


static func cloth(index: int, dyed: bool = false) -> Color:
	if dyed:
		return CLOTH_DYED[posmod(index, CLOTH_DYED.size())]
	return CLOTH[posmod(index, CLOTH.size())]


## How tall someone of `age_years` stands, as a fraction of a grown person:
## children grow, elders shrink a little.
static func height_factor(age_years: int, config: PeopleConfig) -> float:
	if age_years >= config.elder_from_years:
		return 0.94
	if age_years >= config.adult_from_years:
		return 1.0
	if age_years <= 0:
		return 0.32 # (a baby, in its first year)
	return lerpf(0.42, 1.0, clampf(float(age_years) / float(config.adult_from_years), 0.0, 1.0))


## How far someone bends forward (see person.gdshader).
static func stoop_for(stage: PersonData.LifeStage) -> float:
	return 0.16 if stage == PersonData.LifeStage.ELDER else 0.0


# --- building -----------------------------------------------------------------------------

class Build:
	extends RefCounted
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()

	## Adds a part. `side` = which way a limb swings (0: not a limb); the
	## swing grows from `top` (hip, shoulder) to `bottom` (foot, hand).
	func add(part: PropMeshLibrary.Template, side: float = 0.0, top: float = 0.0, bottom: float = 0.0) -> void:
		for i in part.vertices.size():
			var v := part.vertices[i]
			vertices.append(v)
			normals.append(part.normals[i])
			colors.append(part.colors[i])
			uvs.append(Vector2(side, clampf(inverse_lerp(top, bottom, v.y), 0.0, 1.0) if side != 0.0 else 0.0))


static func _build_body() -> ArrayMesh:
	var build := Build.new()

	# Legs.
	for side: float in [-1.0, 1.0]:
		var leg := PropMeshLibrary.Template.new()
		PropMeshLibrary._box(leg, Vector3(0.0, 0.15, 0.075 * side), Vector3(0.055, 0.15, 0.058), _TROUSERS)
		build.add(leg, side, 0.30, 0.0)
	# Tunic: wider at the hem, flatter front to back than side to side.
	var torso := PropMeshLibrary.Template.new()
	var hem := _oval(0.27, 0.125, 0.165, 6)
	var chest := _oval(0.50, 0.115, 0.170, 6)
	var shoulders := _oval(0.64, 0.085, 0.150, 6)
	PropMeshLibrary._band(torso, hem, chest, _TUNIC_HEM, _TUNIC)
	PropMeshLibrary._band(torso, chest, shoulders, _TUNIC, _TUNIC)
	PropMeshLibrary._fan(torso, shoulders, Vector3(0, 0.67, 0), _TUNIC, _TUNIC)
	PropMeshLibrary._fan(torso, hem, Vector3(0, 0.27, 0), _TROUSERS, _TROUSERS, true)
	build.add(torso)
	# Arms swing against the leg of the same side; hands show skin.
	for side: float in [-1.0, 1.0]:
		var arm := PropMeshLibrary.Template.new()
		PropMeshLibrary._box(arm, Vector3(0.0, 0.50, 0.195 * side), Vector3(0.04, 0.12, 0.04), _TUNIC_HEM)
		PropMeshLibrary._box(arm, Vector3(0.0, 0.35, 0.195 * side), Vector3(0.035, 0.035, 0.035), _SKIN)
		build.add(arm, -side, 0.62, 0.32)
	# Head: skin, with hair over the top and down the back; the face looks along +X.
	var head := PropMeshLibrary.Template.new()
	var chin := _oval(0.66, 0.075, 0.08, 6)
	var cheeks := _oval(0.77, 0.125, 0.13, 6)
	var brow := _oval(0.89, 0.115, 0.12, 6)
	PropMeshLibrary._band(head, chin, cheeks, _SKIN, _SKIN)
	_band_faced(head, cheeks, brow)
	PropMeshLibrary._fan(head, brow, Vector3(-0.01, 0.99, 0), _HAIR, _HAIR)
	for side: float in [-1.0, 1.0]:
		PropMeshLibrary._box(head, Vector3(0.105, 0.815, 0.05 * side), Vector3(0.012, 0.016, 0.016), _EYE)
	build.add(head)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = build.vertices
	arrays[Mesh.ARRAY_NORMAL] = build.normals
	arrays[Mesh.ARRAY_COLOR] = build.colors
	arrays[Mesh.ARRAY_TEX_UV] = build.uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# The shader moves vertices: leave room so the body is not culled mid-step.
	mesh.custom_aabb = AABB(Vector3(-0.45, -0.05, -0.4), Vector3(0.9, 1.2, 0.8))
	return mesh


## A ring that is `rx` deep (front to back) and `rz` wide.
static func _oval(y: float, rx: float, rz: float, sides: int) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i in sides:
		var angle := TAU * (i + 0.5) / sides
		points.append(Vector3(cos(angle) * rx, y, sin(angle) * rz))
	return points


## The upper half of the head: skin where it faces forward, hair elsewhere.
static func _band_faced(t: PropMeshLibrary.Template, lower: Array[Vector3], upper: Array[Vector3]) -> void:
	var n := lower.size()
	for i in n:
		var j := (i + 1) % n
		var forward := (lower[i].x + lower[j].x) * 0.5 > 0.03
		var color := _SKIN if forward else _HAIR
		PropMeshLibrary._quad(t, lower[i], lower[j], upper[j], upper[i], color, color, color, color)


## Carried things are drawn with the prop material: plain vertex colours
## (COLOR.a = 0: they do not sway in the wind).
static func _build_accessory(kind: StringName) -> ArrayMesh:
	var t := PropMeshLibrary.Template.new()
	match kind:
		&"staff": # a walking stick, planted beside the right foot
			PropMeshLibrary._box(t, Vector3(0.13, 0.44, 0.27), Vector3(0.016, 0.44, 0.016), _plain(WOOD))
		&"basket": # worn on the back
			var bottom := _oval(0.38, 0.07, 0.09, 6)
			var rim := _oval(0.60, 0.10, 0.13, 6)
			for i in 6:
				bottom[i].x -= 0.21
				rim[i].x -= 0.21
			var middle := Vector3(-0.21, 0.5, 0.0)
			for i in 6:
				var j := (i + 1) % 6
				PropMeshLibrary._quad_outward(t, bottom[i], bottom[j], rim[j], rim[i], _plain(WICKER if i % 2 == 0 else WICKER_DARK), middle)
				PropMeshLibrary._tri_outward(t, rim[i], rim[j], Vector3(-0.21, 0.57, 0.0),
					_plain(WICKER_DARK.darkened(0.25)), _plain(WICKER_DARK.darkened(0.25)), _plain(WICKER_DARK.darkened(0.45)), Vector3(-0.21, -10.0, 0.0))
				PropMeshLibrary._tri_outward(t, bottom[i], bottom[j], Vector3(-0.21, 0.38, 0.0),
					_plain(WICKER_DARK), _plain(WICKER_DARK), _plain(WICKER_DARK), Vector3(-0.21, 10.0, 0.0))
		&"hoe": # carried over the right shoulder: a long handle, a flat blade at the end
			PropMeshLibrary._box(t, Vector3(-0.04, 0.68, 0.20), Vector3(0.26, 0.012, 0.012), _plain(WOOD))
			PropMeshLibrary._box(t, Vector3(-0.29, 0.645, 0.20), Vector3(0.012, 0.045, 0.045), _plain(STONE))
		&"spear": # held upright in the right hand, taller than its bearer
			PropMeshLibrary._box(t, Vector3(0.12, 0.56, 0.27), Vector3(0.012, 0.56, 0.012), _plain(WOOD))
			PropMeshLibrary._box(t, Vector3(0.12, 1.15, 0.27), Vector3(0.02, 0.05, 0.02), _plain(STONE))
		&"scroll": # a scholar's roll of written leaves, held in the right hand (M18)
			PropMeshLibrary._box(t, Vector3(0.14, 0.42, 0.24), Vector3(0.022, 0.09, 0.022), _plain(PARCHMENT))
			PropMeshLibrary._box(t, Vector3(0.14, 0.42, 0.24), Vector3(0.026, 0.012, 0.026), _plain(WOOD))
		&"rod": # a fishing rod (M19.5): a long, thin pole held out ahead, its line hanging
			PropMeshLibrary._box(t, Vector3(0.12, 0.62, 0.42), Vector3(0.008, 0.008, 0.32), _plain(WOOD), 0.0)
			PropMeshLibrary._box(t, Vector3(0.12, 0.40, 0.73), Vector3(0.003, 0.22, 0.003), _plain(PARCHMENT), 0.0)
		&"bow": # held upright in the left hand (PR6): a bent stave and its string
			PropMeshLibrary._box(t, Vector3(0.17, 0.50, -0.27), Vector3(0.014, 0.11, 0.014), _plain(WOOD))
			PropMeshLibrary._box(t, Vector3(0.14, 0.68, -0.27), Vector3(0.012, 0.08, 0.012), _plain(WOOD))
			PropMeshLibrary._box(t, Vector3(0.14, 0.32, -0.27), Vector3(0.012, 0.08, 0.012), _plain(WOOD))
			PropMeshLibrary._box(t, Vector3(0.10, 0.50, -0.27), Vector3(0.003, 0.25, 0.003), _plain(PARCHMENT), 0.0)
		&"axe": # carried over the right shoulder
			PropMeshLibrary._box(t, Vector3(-0.02, 0.675, 0.20), Vector3(0.20, 0.014, 0.014), _plain(WOOD))
			PropMeshLibrary._box(t, Vector3(-0.19, 0.695, 0.20), Vector3(0.03, 0.06, 0.02), _plain(STONE))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = t.vertices
	arrays[Mesh.ARRAY_NORMAL] = t.normals
	arrays[Mesh.ARRAY_COLOR] = t.colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _build_load(resource: StringName) -> ArrayMesh:
	var t := PropMeshLibrary.Template.new()
	match resource:
		&"wood": # two short logs over the left shoulder
			PropMeshLibrary._box(t, Vector3(0.0, 0.705, -0.19), Vector3(0.23, 0.032, 0.032), _plain(WOOD))
			PropMeshLibrary._box(t, Vector3(0.03, 0.755, -0.17), Vector3(0.2, 0.028, 0.028), _plain(WOOD.darkened(0.18)), 0.12)
		&"stone": # held low in both hands
			PropMeshLibrary._box(t, Vector3(0.16, 0.4, 0.0), Vector3(0.06, 0.05, 0.075), _plain(STONE), 0.3)
		_: # an armful in a cloth, held to the chest
			var color: Color = PropMeshLibrary.PILE_COLORS.get(resource, STONE)
			PropMeshLibrary._box(t, Vector3(0.155, 0.5, 0.0), Vector3(0.05, 0.035, 0.085), _plain(WICKER_DARK))
			PropMeshLibrary._box(t, Vector3(0.155, 0.545, 0.0), Vector3(0.038, 0.022, 0.07), _plain(color))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = t.vertices
	arrays[Mesh.ARRAY_NORMAL] = t.normals
	arrays[Mesh.ARRAY_COLOR] = t.colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _plain(color: Color) -> Color:
	return Color(color.r, color.g, color.b, 0.0)
