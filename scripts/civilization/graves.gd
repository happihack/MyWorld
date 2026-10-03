class_name Graves
extends RefCounted
## Where the dead are laid (bible §16.3: "graves are physical, tappable
## places"). The first grave opens a burial ground a little way from the
## fire; the rest are laid beside it, a tile apart, the nearest free ground
## first. A grave is a prop (PropData.Kind.GRAVE) that people can walk past.

## The burial ground is this many tiles (at least, at most) from the fire.
const NEAREST := 6
const FURTHEST := 12
## The next grave is looked for within this many tiles of the first.
const GROUND_REACH := 8

var _props: PropRegistry
var _world: WorldData
var _pathfinder: Pathfinder
var _start: WorldSetup.StartInfo
var _ids: IdAllocator
var _archive: HistoryArchive
var _loose: LooseObjectRegistry
## A settlement's graves are those within this many tiles of its fire (M12.3).
const GRAVEYARD_REACH := 14.0


func bind(props: PropRegistry, world: WorldData, pathfinder: Pathfinder, start: WorldSetup.StartInfo, ids: IdAllocator,
		archive: HistoryArchive, loose: LooseObjectRegistry = null) -> void:
	_props = props
	_world = world
	_pathfinder = pathfinder
	_start = start
	_ids = ids
	_archive = archive
	_loose = loose


## Every grave there is (ids, in order).
func all_graves() -> Array[int]:
	var out: Array[int] = []
	if _props == null:
		return out
	for prop in _props.all_props():
		if prop.kind == PropData.Kind.GRAVE:
			out.append(prop.id)
	out.sort()
	return out


## Lays someone who has died (they are in the archive) in a grave. Returns its
## id (0: nowhere to lay them).
func bury(person_id: int, start: WorldSetup.StartInfo = null) -> int:
	if _props == null or _start == null or _archive == null or _archive.get_record(person_id) == null:
		return 0
	var site: Variant = site(start)
	if site == null:
		return 0
	var grave := PropData.new()
	grave.id = _ids.next_id()
	grave.kind = PropData.Kind.GRAVE
	grave.tile = site
	grave.variant = 0
	grave.scale_percent = 100
	if not _props.add(grave):
		return 0
	_archive.set_grave(person_id, grave.id, site)
	return grave.id


## Where the next grave goes (null: nowhere).
## (Near the fire of `start`: the settlement the dead belonged to — the first, if not given.)
func site(start: WorldSetup.StartInfo = null) -> Variant:
	var own := start if start != null else _start
	var graves: Array[int] = []
	for id in all_graves():
		var grave := _props.get_prop(id)
		if grave != null and Vector2(grave.tile - own.settlement_tile).length() <= GRAVEYARD_REACH:
			graves.append(id)
	if graves.is_empty():
		return _first_site(own)
	var first := _props.get_prop(graves[0])
	var center: Vector2i = first.tile if first != null else own.settlement_tile
	var best: Variant = null
	var best_distance := 1 << 30
	for dy in range(-GROUND_REACH, GROUND_REACH + 1):
		for dx in range(-GROUND_REACH, GROUND_REACH + 1):
			var tile := center + Vector2i(dx, dy)
			var distance := dx * dx + dy * dy
			if distance >= best_distance or not _free(tile) or _grave_beside(tile):
				continue
			best = tile
			best_distance = distance
	return best if best != null else _first_site(own)


## A quiet place a little way from the fire, with free ground around it.
func _first_site(start: WorldSetup.StartInfo) -> Variant:
	var fire := start.settlement_tile
	for reach in range(NEAREST, FURTHEST + 1):
		var ring: Array[Vector2i] = []
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				if maxi(absi(dx), absi(dy)) == reach:
					ring.append(fire + Vector2i(dx, dy))
		ring.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da := (a - fire).length_squared()
			var db := (b - fire).length_squared()
			return da < db if da != db else (a.y < b.y or (a.y == b.y and a.x < b.x)))
		for tile in ring:
			if not _free(tile):
				continue
			var room := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					room += 1 if _free(tile + Vector2i(dx, dy)) else 0
			if room == 9:
				return tile
	return null


## Ground where a grave can be: dry, standable, nothing on it.
func _free(tile: Vector2i) -> bool:
	if not _world.bounds.has_point(tile) or not WorldSetup.is_walkable(_world, tile) or _world.get_water(tile) > 0.0:
		return false
	if _props.prop_at(tile) != null:
		return false
	if _pathfinder != null and _pathfinder.is_bound() and not _pathfinder.can_stand(tile):
		return false
	if _loose != null:
		for object in _loose.all_objects():
			if object.tile() == tile:
				return false
	return true


## Another grave on a tile next to this one (graves are laid a tile apart).
func _grave_beside(tile: Vector2i) -> bool:
	for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var near := _props.prop_at(tile + step)
		if near != null and near.kind == PropData.Kind.GRAVE:
			return true
	return false
