class_name MapImage
extends RefCounted
## The world seen from above (M13.3; built on the debug WorldPreview): one
## pixel per tile — the ground's colour by its kind and height, the water's
## by its depth — with what nobody of the world has explored dimmed (bible
## §8.7: unknown land is dimmed, never black; the world's knowledge, M13.4:
## FogOfKnowledge). Drawn chunk by chunk: a chunk whose ground, water or
## knowledge changed is drawn again, a few each frame.

## Chunks drawn again per refresh() call (the first drawing is spread out so).
const CHUNKS_PER_REFRESH := 12
## What nobody has explored keeps this much of its colour, greyed.
const UNKNOWN_KEEP := 0.45
const UNKNOWN_GREY := 0.6

## Layers: the ground's colour, the water over it, the dimming of the unknown.
var show_terrain := true
var show_water := true
var show_fog := true

var image: Image
var texture: ImageTexture

var _world: WorldData
var _session: WorldSession
var _dirty: Dictionary = {} # chunk coord -> true
var _max_level := 15


func bind(session: WorldSession) -> void:
	_session = session
	_world = session.world if session != null else null
	if _world == null:
		return
	_max_level = maxi(Config.world.height_levels - 1, 1)
	var size := _world.bounds.size
	image = Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	image.fill(Color(0.1, 0.1, 0.1))
	texture = ImageTexture.create_from_image(image)
	if session.knowledge != null:
		session.knowledge.changed.connect(func(coords: Array[Vector2i]) -> void:
			for coord in coords:
				_dirty[coord] = true)
	mark_all()


## Everything is drawn again (a layer was switched).
func mark_all() -> void:
	if _world == null:
		return
	for coord in _world.chunk_coords():
		_dirty[coord] = true


func mark_tile(tile: Vector2i) -> void:
	if _world != null and _world.is_in_bounds(tile):
		_dirty[WorldCoords.tile_to_chunk(tile, _world.chunk_size)] = true


func pending() -> int:
	return _dirty.size()


## Draws again up to `most` chunks that changed (and those newly explored);
## returns how many. The texture is updated if anything was drawn.
func refresh(most: int = CHUNKS_PER_REFRESH) -> int:
	if _world == null:
		return 0
	var done := 0
	for coord: Vector2i in _dirty.keys():
		if done >= most:
			break
		_draw_chunk(coord)
		_dirty.erase(coord)
		done += 1
	if done > 0:
		texture.update(image)
	return done


## Draws everything now (tests, the full map's first look).
func refresh_all() -> void:
	while refresh(1_000_000) > 0:
		pass


## The colour of one tile as the map shows it.
func tile_color(tile: Vector2i) -> Color:
	var color: Color
	if show_terrain:
		var base: Color = WorldPreview.TERRAIN_COLORS.get(_world.get_terrain(tile), Color.MAGENTA)
		var shade := 0.62 + 0.38 * float(_world.get_height(tile)) / float(_max_level)
		color = Color(base.r * shade, base.g * shade, base.b * shade)
	else:
		var level := 0.25 + 0.6 * float(_world.get_height(tile)) / float(_max_level)
		color = Color(level, level, level)
	var depth := _world.get_water(tile)
	if show_water and depth > Pathfinder.WET_DEPTH:
		color = WorldPreview.WATER_SHALLOW.lerp(WorldPreview.WATER_DEEP, clampf(depth / WorldPreview.DEEP_WATER_UNITS, 0.0, 1.0))
	if show_fog and not is_explored(tile):
		var grey := (color.r + color.g + color.b) / 3.0 * UNKNOWN_GREY
		var kept := Color(grey, grey, grey).lerp(color, UNKNOWN_KEEP)
		color = Color(kept.r * 0.7, kept.g * 0.7, kept.b * 0.7)
	return color


## Has anyone of the world been here (or seen it from where they were)?
func is_explored(tile: Vector2i) -> bool:
	return _session == null or _session.knowledge == null or _session.knowledge.is_explored(tile)


## The pixel of a tile (image coordinates).
func pixel_of(tile: Vector2i) -> Vector2i:
	return tile - _world.bounds.position


## The tile under a point of the image (fractions of a pixel kept: a world position).
func world_at(pixel: Vector2) -> Vector2:
	return Vector2(_world.bounds.position) + pixel


func _draw_chunk(coord: Vector2i) -> void:
	var rect := WorldCoords.chunk_rect(coord, _world.chunk_size).intersection(_world.bounds)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var tile := Vector2i(x, y)
			image.set_pixelv(pixel_of(tile), tile_color(tile))
