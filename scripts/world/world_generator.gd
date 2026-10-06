class_name WorldGenerator
extends RefCounted
## Deterministic terrain generation (bible §8.4–8.5).
##
## Every tile is a pure function of (world seed, template, tile coordinate):
## chunks can be generated in any order, dropped and regenerated, and come out
## bit-identical on every device. All shaping math is integer fixed-point
## (FP units per tile / per height level); see HashNoise.
##
## Shapes are defined in world coordinates, not relative to the box bounds, so
## terrain never changes when the box unfolds.

## Bump when generated output changes in any way. Unmodified chunks are never
## saved — they are regenerated — so a changed algorithm would silently alter
## existing worlds. After release, old versions must stay reproducible (keep the
## old code path, or materialise all chunks in a save migration).
## tests/unit/test_world_generator.gd pins a checksum per version.
const GENERATOR_VERSION := 2 # (2: mushrooms and roots on ground left empty — 2026-10-06)

const FP := 256 # fixed-point units per tile and per height level
const _T_ONE := 1024 # smoothstep weight scale

## Fields written by _sample() into its output array.
enum { S_HEIGHT, S_TERRAIN, S_WATER_FP, S_MOISTURE, S_FERTILITY, S_VEGETATION, S_COUNT }

var world_seed: int
var template: StartTemplate
var chunk_size: int
var height_levels: int
var height_step: float

var _salt_terrain: int
var _salt_river: int
var _salt_pond: int
var _salt_dirt: int
var _salt_moisture: int
var _salt_fertility: int
var _salt_vegetation: int
var _salt_warp: int
var _salt_ridge: int
var _salt_forest: int
var _salt_tree: int
var _salt_rock: int
var _salt_bush: int
var _salt_mushroom: int
var _salt_roots: int
var _salt_prop: int

# Prop densities as chances out of HashNoise.ONE.
var _tree_chance: int
var _rock_chance: int
var _bush_chance: int

# Template values converted once to fixed-point.
var _valley_half: int
var _hill_run: int
var _river_half: int
var _bank_width: int
var _meander_amp: int
var _pond_extra: int
var _valley_rough: int
var _hill_rough: int
var _water_surface: int # in FP height-level units
var _edge_warp: int
var _hill_variation: int # 0.._T_ONE
var _pond_threshold: int # 0..HashNoise.ONE

var _scratch := PackedInt32Array()


func _init(seed_value: int, start_template: StartTemplate, world_config: WorldConfig) -> void:
	world_seed = seed_value
	template = start_template
	chunk_size = world_config.chunk_size
	height_levels = world_config.height_levels
	height_step = world_config.height_step
	_salt_terrain = _salt(&"gen.terrain")
	_salt_river = _salt(&"gen.river")
	_salt_pond = _salt(&"gen.pond")
	_salt_dirt = _salt(&"gen.dirt")
	_salt_moisture = _salt(&"gen.moisture")
	_salt_fertility = _salt(&"gen.fertility")
	_salt_vegetation = _salt(&"gen.vegetation")
	_salt_warp = _salt(&"gen.warp")
	_salt_ridge = _salt(&"gen.ridge")
	_salt_forest = _salt(&"gen.forest")
	_salt_tree = _salt(&"gen.tree")
	_salt_rock = _salt(&"gen.rock")
	_salt_bush = _salt(&"gen.bush")
	_salt_mushroom = _salt(&"gen.mushroom")
	_salt_roots = _salt(&"gen.roots")
	_salt_prop = _salt(&"gen.prop")
	_tree_chance = roundi(template.tree_density * HashNoise.ONE)
	_rock_chance = roundi(template.rock_density * HashNoise.ONE)
	_bush_chance = roundi(template.bush_density * HashNoise.ONE)
	_valley_half = _fp(template.valley_half_width_tiles)
	_hill_run = _fp(template.hill_run_tiles)
	_river_half = _fp(template.river_half_width_tiles)
	_bank_width = _fp(template.bank_width_tiles)
	_meander_amp = _fp(template.meander_amplitude_tiles)
	_pond_extra = _fp(template.pond_extra_width_tiles)
	_valley_rough = _fp(template.valley_roughness_levels)
	_hill_rough = _fp(template.hill_roughness_levels)
	_water_surface = template.floor_level * FP - _fp(template.water_below_floor_levels)
	_edge_warp = _fp(template.valley_edge_warp_tiles)
	_hill_variation = roundi(template.hill_height_variation * _T_ONE)
	_pond_threshold = roundi((1.0 - template.pond_amount) * HashNoise.ONE)
	_scratch.resize(S_COUNT)


## Use as WorldData.generator.
func generate_chunk(coord: Vector2i) -> ChunkData:
	var chunk := ChunkData.new(coord, chunk_size)
	var origin := WorldCoords.chunk_origin(coord, chunk_size)
	var out := _scratch
	for ly in chunk_size:
		var y := origin.y + ly
		var river_x := river_center_fp(y)
		var river_half := river_half_width_fp(y)
		for lx in chunk_size:
			_sample(origin.x + lx, y, river_x, river_half, out)
			var i := ly * chunk_size + lx
			chunk.height[i] = out[S_HEIGHT]
			chunk.terrain[i] = out[S_TERRAIN]
			chunk.water[i] = (out[S_WATER_FP] / float(FP)) * height_step
			chunk.moisture[i] = out[S_MOISTURE]
			chunk.fertility[i] = out[S_FERTILITY]
			chunk.vegetation[i] = out[S_VEGETATION]
			# Higher ground is cooler: -2 per level above the valley floor.
			chunk.temperature[i] = clampi(-(out[S_HEIGHT] - template.floor_level) * 2, -128, 127) + 128
	chunk.mark_pristine()
	return chunk


## Trees, rocks and bushes for a generated chunk: at most one per tile, each a
## pure function of (seed, tile, the chunk's generated terrain). Pass the
## pristine chunk from generate_chunk(); ids are PropData.generated_id(tile).
func generate_props(chunk: ChunkData) -> Array[PropData]:
	var props: Array[PropData] = []
	var origin := WorldCoords.chunk_origin(chunk.coord, chunk_size)
	var one := HashNoise.ONE
	for ly in chunk_size:
		for lx in chunk_size:
			var i := ly * chunk_size + lx
			var terrain := chunk.terrain[i]
			if chunk.water[i] > 0.0 or terrain == ChunkData.Terrain.RIVERBED \
					or terrain == ChunkData.Terrain.SAND or terrain == ChunkData.Terrain.SNOW:
				continue
			var x := origin.x + lx
			var y := origin.y + ly
			var level := chunk.height[i]
			var moisture := chunk.moisture[i]
			var forest := HashNoise.fbm2(x, y, template.forest_period_tiles, 2, _salt_forest)
			var kind := -1
			var variant := 0

			if terrain == ChunkData.Terrain.GRASS:
				# Forest cover ramps up where the forest noise is high; wetter
				# ground grows denser woods; a few lone trees stand anywhere.
				var cover := clampi((forest - one * 42 / 100) * 1024 / (one * 30 / 100), 0, 1024)
				var chance := _tree_chance * cover / 1024 * (128 + moisture / 2) / 255 + one * 5 / 1000
				if HashNoise.tile_value(x, y, _salt_tree) < chance:
					kind = PropData.Kind.TREE
					if level >= template.floor_level + 3:
						variant = PropData.TREE_CONIFER_FIRST_VARIANT

			if kind == -1:
				var rock_scale := 1
				if terrain == ChunkData.Terrain.ROCK:
					rock_scale = 3
				elif terrain == ChunkData.Terrain.DIRT:
					rock_scale = 2
				if HashNoise.tile_value(x, y, _salt_rock) < _rock_chance * rock_scale:
					kind = PropData.Kind.ROCK

			if kind == -1 and moisture > 90 \
					and (terrain == ChunkData.Terrain.GRASS or terrain == ChunkData.Terrain.DIRT):
				# Berry bushes favour the forest edge.
				var edge := maxi(1024 - absi(forest - one * 42 / 100) * 1024 / (one * 15 / 100), 0)
				if HashNoise.tile_value(x, y, _salt_bush) < _bush_chance * (1024 + 6 * edge) / 1024:
					kind = PropData.Kind.BUSH

			# Wild food on the ground (the owner, 2026-10-06; on ground left empty
			# above, so the props of worlds made before are as they were):
			# mushrooms on damp ground in and by the woods, roots in the open.
			if kind == -1 and moisture > 110 and terrain == ChunkData.Terrain.GRASS:
				var shade := clampi((forest - one * 36 / 100) * 1024 / (one * 20 / 100), 0, 1024)
				if HashNoise.tile_value(x, y, _salt_mushroom) < _bush_chance * shade / 1024 * 3:
					kind = PropData.Kind.MUSHROOM
			if kind == -1 and moisture > 70 and (terrain == ChunkData.Terrain.GRASS or terrain == ChunkData.Terrain.DIRT):
				var open := clampi((one * 45 / 100 - forest) * 1024 / (one * 20 / 100), 0, 1024)
				if HashNoise.tile_value(x, y, _salt_roots) < _bush_chance * (512 + open * 2) / 1024:
					kind = PropData.Kind.ROOTS

			if kind == -1:
				continue
			var h := HashNoise.hash2(x, y, _salt_prop)
			var prop := PropData.new()
			prop.tile = Vector2i(x, y)
			prop.id = PropData.generated_id(prop.tile)
			prop.kind = kind as PropData.Kind
			prop.variant = variant + (h & 1)
			prop.rotation_step = (h >> 1) & 0xFF
			prop.scale_percent = 80 + ((h >> 9) % 41) # 80..120 %
			prop.offset_x = ((h >> 16) & 0xFF) * 154 / 255 - 77 # about ±0.3 tile
			prop.offset_y = ((h >> 24) & 0xFF) * 154 / 255 - 77
			props.append(prop)
	return props


## The height of the river's surface as the world is made (world units).
func water_surface_height() -> float:
	return _water_surface / float(FP) * height_step


## Which way the river runs at a tile: a unit vector on the ground plane
## (x = world X, y = world Z). The river follows the Z axis; downstream is +Z.
func river_direction(tile: Vector2i) -> Vector2:
	var sideways := (river_center_fp(tile.y + 1) - river_center_fp(tile.y - 1)) / float(2 * FP)
	return Vector2(sideways, 1.0).normalized()


## World X of the middle of the river at row `z` (tile centres are at +0.5).
func river_center_x(z: int) -> float:
	return river_center_fp(z) / float(FP)


## One tile's generated values (for tests, validation and placement logic).
func sample_tile(tile: Vector2i) -> Dictionary:
	var out := PackedInt32Array()
	out.resize(S_COUNT)
	_sample(tile.x, tile.y, river_center_fp(tile.y), river_half_width_fp(tile.y), out)
	return {
		"height": out[S_HEIGHT],
		"terrain": out[S_TERRAIN],
		"water": (out[S_WATER_FP] / float(FP)) * height_step,
		"moisture": out[S_MOISTURE],
		"fertility": out[S_FERTILITY],
		"vegetation": out[S_VEGETATION],
	}


## River centre line X (fixed-point tiles) at row y. The river runs along Z.
func river_center_fp(y: int) -> int:
	var n := HashNoise.fbm2(y, 0, template.meander_period_tiles, 2, _salt_river)
	return (n * 2 - HashNoise.ONE) * _meander_amp / HashNoise.ONE


## River half-width (fixed-point tiles) at row y, swelling into ponds.
func river_half_width_fp(y: int) -> int:
	if _pond_threshold >= HashNoise.ONE:
		return _river_half
	var n := HashNoise.value2(0, y, template.pond_period_tiles, _salt_pond)
	var swell := maxi(n - _pond_threshold, 0) * _pond_extra / (HashNoise.ONE - _pond_threshold)
	return _river_half + swell


## Distance (fixed-point tiles) from a tile centre to the river centre line.
func distance_to_river_fp(tile: Vector2i) -> int:
	return absi(tile.x * FP + FP / 2 - river_center_fp(tile.y))


func _sample(x: int, y: int, river_x: int, river_half: int, out: PackedInt32Array) -> void:
	var d := absi(x * FP + FP / 2 - river_x)
	var is_river := d < river_half
	var is_bank := not is_river and d < river_half + _bank_width

	# The foot of the hills wanders in and out (the river uses the true distance).
	var warp_noise := HashNoise.value2(x, y, template.valley_edge_warp_period, _salt_warp) - HashNoise.ONE / 2
	var warp := warp_noise * _edge_warp / (HashNoise.ONE / 2)
	var s := HashNoise.smoothstep_fixed(_valley_half, _valley_half + _hill_run, d + warp) # 0 valley .. 1024 hills

	var level: int
	if is_river:
		level = template.floor_level - 2
	elif is_bank:
		level = template.floor_level - 1
	else:
		# Hills differ in height: scale = 1 - variation * ridge noise.
		var ridge := HashNoise.value2(x, y, template.hill_variation_period, _salt_ridge)
		var hill_scale := _T_ONE - _hill_variation * ridge / HashNoise.ONE
		var hill := template.hill_height_levels * FP * s / _T_ONE * hill_scale / _T_ONE
		var noise := HashNoise.fbm2(x, y, template.terrain_noise_period, 3, _salt_terrain) - HashNoise.ONE / 2
		var rough := _valley_rough + (_hill_rough - _valley_rough) * s / _T_ONE
		var h := template.floor_level * FP + hill + noise * rough / (HashNoise.ONE / 2)
		# Dry land never dips below the valley floor (no dry holes beside the water).
		h = maxi(h, template.floor_level * FP)
		level = (h + FP / 2) / FP
	level = clampi(level, 0, height_levels - 1)
	out[S_HEIGHT] = level

	var water := 0
	if is_river or is_bank:
		water = maxi(_water_surface - level * FP, 0)
	out[S_WATER_FP] = water

	var terrain: int
	if is_river:
		terrain = ChunkData.Terrain.RIVERBED
	elif is_bank:
		terrain = ChunkData.Terrain.SAND
	elif level >= template.snow_level:
		terrain = ChunkData.Terrain.SNOW
	elif level >= template.rock_level:
		terrain = ChunkData.Terrain.ROCK
	elif HashNoise.fbm2(x, y, 12, 3, _salt_dirt) > HashNoise.ONE * 66 / 100:
		terrain = ChunkData.Terrain.DIRT
	else:
		terrain = ChunkData.Terrain.GRASS
	out[S_TERRAIN] = terrain

	# Moisture: wet at the river, drier with distance, with some variation.
	var moisture := 255
	if not is_river:
		var falloff := clampi(d * 200 / (_valley_half + _hill_run), 0, 200)
		var jitter := (HashNoise.value2(x, y, 11, _salt_moisture) - HashNoise.ONE / 2) * 30 / (HashNoise.ONE / 2)
		moisture = clampi(245 - falloff + jitter, 10, 255)
	out[S_MOISTURE] = moisture

	# Fertility: rich valley floor, poor hills; bare ground stays poor.
	var fertility := 25
	if terrain == ChunkData.Terrain.GRASS or terrain == ChunkData.Terrain.DIRT:
		var jitter_f := (HashNoise.value2(x, y, 13, _salt_fertility) - HashNoise.ONE / 2) * 30 / (HashNoise.ONE / 2)
		fertility = clampi(205 - 140 * s / _T_ONE + jitter_f, 20, 255)
	out[S_FERTILITY] = fertility

	# Ground cover: grows where it is moist and fertile.
	var vegetation := 0
	if terrain == ChunkData.Terrain.GRASS:
		var patch := HashNoise.fbm2(x, y, 8, 2, _salt_vegetation) # 0..ONE
		vegetation = clampi(moisture * fertility / 255 * (HashNoise.ONE / 2 + patch) / HashNoise.ONE, 0, 255)
	elif terrain == ChunkData.Terrain.DIRT:
		vegetation = 20
	out[S_VEGETATION] = vegetation


func _salt(stream: StringName) -> int:
	return RngStreams.derive_seed(world_seed, stream) & 0xFFFFFFFF


static func _fp(value: float) -> int:
	return roundi(value * FP)
