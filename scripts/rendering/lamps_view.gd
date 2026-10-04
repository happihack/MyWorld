class_name LampsView
extends Node3D
## Lamps (M16.3, bible §18.3: "light at night — fire → oil lamps → …"): where
## a settlement has learned to burn fat in a clay lamp, every home has one
## by its door after dark — a small flame and a warm pool of light on the
## ground before it. Purely what is shown; pooled, a few dozen at most.

## The most lamps shown at once.
const MOST := 48
## How dark it must be (DayNight.night) before the lamps are lit; fully lit at LIT.
const FROM := 0.25
const LIT := 0.6
## The flame's size, the pool's radius (world units) and the warm colour.
const FLAME := 0.07
const POOL := 0.55
const WARM := Color(1.0, 0.72, 0.35)
## Where by the door (in the hut's own turning: the doorway faces +X).
const DOOR := Vector3(0.55, 0.0, 0.18)
const FLAME_HEIGHT := 0.32
## How often where they stand is looked at again (seconds).
const LOOK_EVERY := 2.0

## Where the lamps stand now: Callable() -> Array[Vector3] (door, ground level); see Main.lamp_places.
var source := Callable()
## For tests: how dark it is (0 … 1) in place of the day's own (-1: the day's).
var night := -1.0
var _day_night: DayNight
var _flames: Array[Sprite3D] = []
var _pools: Array[MeshInstance3D] = []
var _places: Array[Vector3] = []
var _since := LOOK_EVERY
var _shown := -1.0


func _init() -> void:
	var dot := AmbientLife.soft_dot()
	var pool_material := StandardMaterial3D.new()
	pool_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pool_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pool_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pool_material.albedo_texture = dot
	pool_material.albedo_color = Color(WARM, 0.55)
	pool_material.render_priority = 1
	var quad := PlaneMesh.new()
	quad.size = Vector2(POOL * 2.0, POOL * 2.0)
	for i in MOST:
		var flame := Sprite3D.new()
		flame.texture = dot
		flame.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		flame.pixel_size = FLAME * 2.0 / 64.0
		flame.modulate = Color(1.0, 0.85, 0.5)
		flame.shaded = false
		flame.transparent = true
		flame.visible = false
		flame.name = "Flame%d" % i
		add_child(flame)
		_flames.append(flame)
		var pool := MeshInstance3D.new()
		pool.mesh = quad
		pool.material_override = pool_material
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pool.visible = false
		pool.name = "Pool%d" % i
		add_child(pool)
		_pools.append(pool)


func setup(day_night: DayNight) -> void:
	_day_night = day_night


## Looks again at once where the lamps stand.
func refresh() -> void:
	_since = LOOK_EVERY
	_shown = -1.0


func lamp_count() -> int:
	return _places.size()


## How many burn now (shown).
func lit_count() -> int:
	return _flames.filter(func(f: Sprite3D) -> bool: return f.visible).size()


## How brightly they burn now, 0 … 1 (0: day, unlit).
func brightness() -> float:
	var dark := night if night >= 0.0 else (_day_night.night() if _day_night != null else 0.0)
	return clampf((dark - FROM) / (LIT - FROM), 0.0, 1.0)


func advance(delta: float) -> void:
	_since += delta
	if _since >= LOOK_EVERY:
		_since = 0.0
		var places: Array = source.call() if source.is_valid() else []
		_places.clear()
		for at: Vector3 in places.slice(0, MOST):
			_places.append(at)
		_shown = -1.0
	var lit := brightness()
	if absf(lit - _shown) < 0.02:
		return
	_shown = lit
	for i in MOST:
		var on := i < _places.size() and lit > 0.0
		_flames[i].visible = on
		_pools[i].visible = on
		if on:
			_flames[i].position = _places[i] + Vector3(0.0, FLAME_HEIGHT, 0.0)
			_flames[i].modulate.a = lit
			_pools[i].position = _places[i] + Vector3(0.0, 0.03, 0.0)
			_pools[i].transparency = 1.0 - lit


func _process(delta: float) -> void:
	advance(delta)


## Where the lamp of a hut stands: by its door (the hut turned by `radians`,
## PropData.rotation_radians, and grown to `size`).
static func door_of(base: Vector3, radians: float, size: float = 1.0) -> Vector3:
	return base + Basis(Vector3.UP, radians) * (DOOR * size)
