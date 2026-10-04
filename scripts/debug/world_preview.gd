class_name WorldPreview
extends RefCounted
## Top-down image of a WorldData (debug tool; the minimap builds on this in M13).
## Colour = terrain type, brightness = height, blue = water (darker when deeper).

const TERRAIN_COLORS := {
	ChunkData.Terrain.GRASS: Color(0.36, 0.62, 0.30),
	ChunkData.Terrain.DIRT: Color(0.52, 0.42, 0.28),
	ChunkData.Terrain.SAND: Color(0.82, 0.76, 0.55),
	ChunkData.Terrain.ROCK: Color(0.52, 0.52, 0.54),
	ChunkData.Terrain.SNOW: Color(0.93, 0.95, 0.97),
	ChunkData.Terrain.FARMLAND: Color(0.60, 0.50, 0.25),
	ChunkData.Terrain.ROAD: Color(0.60, 0.56, 0.48),
	ChunkData.Terrain.RIVERBED: Color(0.45, 0.42, 0.36),
	ChunkData.Terrain.MUD: Color(0.38, 0.30, 0.22),
	ChunkData.Terrain.ASH: Color(0.30, 0.30, 0.30),
	ChunkData.Terrain.PAVED: Color(0.66, 0.64, 0.60),
}
const WATER_SHALLOW := Color(0.36, 0.66, 0.86)
const WATER_DEEP := Color(0.13, 0.36, 0.66)
const DEEP_WATER_UNITS := 0.4


static func tile_color(world: WorldData, tile: Vector2i, max_level: int = 15) -> Color:
	var base: Color = TERRAIN_COLORS.get(world.get_terrain(tile), Color.MAGENTA)
	var shade := 0.62 + 0.38 * float(world.get_height(tile)) / float(max_level)
	var color := Color(base.r * shade, base.g * shade, base.b * shade)
	var depth := world.get_water(tile)
	if depth > 0.0:
		color = WATER_SHALLOW.lerp(WATER_DEEP, clampf(depth / DEEP_WATER_UNITS, 0.0, 1.0))
	return color


## Renders the whole box, `pixels_per_tile` pixels per tile. `markers` maps
## tile -> Color for overlays (props, settlement sites, ...).
static func render(world: WorldData, pixels_per_tile: int = 4, markers: Dictionary = {}) -> Image:
	var b := world.bounds
	var image := Image.create(b.size.x * pixels_per_tile, b.size.y * pixels_per_tile, false, Image.FORMAT_RGB8)
	for y in b.size.y:
		for x in b.size.x:
			var tile := b.position + Vector2i(x, y)
			var color := tile_color(world, tile)
			image.fill_rect(Rect2i(x * pixels_per_tile, y * pixels_per_tile, pixels_per_tile, pixels_per_tile), color)
			if markers.has(tile):
				var inset := maxi(pixels_per_tile / 4, 1)
				image.fill_rect(Rect2i(x * pixels_per_tile + inset, y * pixels_per_tile + inset,
					pixels_per_tile - inset * 2, pixels_per_tile - inset * 2), markers[tile])
	return image
