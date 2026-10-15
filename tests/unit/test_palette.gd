extends TestCase
## Palette: one set of colours for the whole box, and the Blender copy of it.

const PaletteGpl := preload("res://tests/tools/palette_gpl.gd")

## Base colour, shade, factor: what the comment beside each shade promises.
const SHADES := [
	[Palette.BARK, Palette.BARK_DARK, 0.78], [Palette.BARK, Palette.BARK_LIGHT, 1.10],
	[Palette.BARK, Palette.BARK_DEEP, 0.60], [Palette.BARK, Palette.BOX_WOOD, 0.88],
	[Palette.LEAF, Palette.LEAF_DARK, 0.92], [Palette.LEAF_LIGHT, Palette.LEAF_LIGHT_DARK, 0.88],
	[Palette.STONE, Palette.STONE_DARK, 0.77], [Palette.STONE, Palette.STONE_LIGHT, 1.08],
	[Palette.STONE, Palette.STONE_WORN, 0.90],
	[Palette.EARTH, Palette.EARTH_DARK, 0.83], [Palette.EARTH, Palette.EARTH_LIGHT, 1.07],
	[Palette.EARTH, Palette.FIELD, 0.90], [Palette.LOAM, Palette.LOAM_DARK, 0.86],
	[Palette.SAND, Palette.SAND_DARK, 0.85],
	[Palette.THATCH, Palette.THATCH_DARK, 0.74], [Palette.THATCH, Palette.THATCH_DRY, 0.90],
	[Palette.THATCH, Palette.THATCH_HUSK, 0.85],
	[Palette.DAUB, Palette.DAUB_DARK, 0.80], [Palette.DAUB, Palette.DAUB_PALE, 0.95],
	[Palette.CLAY, Palette.CLAY_DARK, 0.74],
	[Palette.LEATHER, Palette.LEATHER_DARK, 0.72], [Palette.LEATHER, Palette.LEATHER_LIGHT, 1.20],
	[Palette.LEATHER, Palette.LEATHER_CURED, 0.85],
	[Palette.REEDS, Palette.REEDS_DARK, 0.71], [Palette.PARCHMENT, Palette.PARCHMENT_DARK, 0.78],
]


func test_every_colour_is_a_colour() -> void:
	var named := Palette.named()
	assert_true(named.size() >= 60, "expected the whole palette, got %d" % named.size())
	for key: String in named:
		var c: Color = named[key]
		for channel: float in [c.r, c.g, c.b]:
			assert_true(channel >= 0.0 and channel <= 1.0, "%s out of range" % key)
		assert_near(c.a, 1.0, 0.0001, "%s carries an alpha; alpha is sway in the props" % key)


func test_base_colours_are_distinct() -> void:
	# Two base colours closer than this would not read apart on a phone. (The
	# shades of the browns do crowd each other; that is what shades are.)
	var constants: Dictionary = (Palette as Script).get_script_constant_map()
	assert_true(Palette.BASES.size() >= 30, "expected the whole base palette")
	for name: StringName in Palette.BASES:
		assert_true(constants.has(name) and constants[name] is Color, "%s is not a colour of the palette" % name)
	for i in Palette.BASES.size():
		for j in range(i + 1, Palette.BASES.size()):
			var a: Color = constants[Palette.BASES[i]]
			var b: Color = constants[Palette.BASES[j]]
			var distance := absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			assert_true(distance >= 0.03, "%s and %s are the same colour" % [Palette.BASES[i], Palette.BASES[j]])


func test_shades_are_their_base_times_the_factor() -> void:
	for row: Array in SHADES:
		var base: Color = row[0]
		var shade: Color = row[1]
		var expected := Palette.shade(base, row[2])
		for pair: Array in [[shade.r, expected.r], [shade.g, expected.g], [shade.b, expected.b]]:
			assert_near(pair[0], pair[1], 0.011, "%s is not its base × %.2f" % [shade, row[2]])


func test_libraries_read_the_palette() -> void:
	assert_eq(PropMeshLibrary.TRUNK, Palette.BARK)
	assert_eq(PropMeshLibrary.PILE_COLORS[&"grain"], Palette.GOLD)
	assert_eq(PersonMeshLibrary.ELDER_HAIR, Palette.HAIR_GREY)
	assert_eq(BoxFrame.BRASS, Palette.BRASS)
	var terrain := TerrainPalette.new()
	assert_eq(terrain.top(ChunkData.Terrain.GRASS), Palette.GRASS)
	assert_eq(terrain.side(ChunkData.Terrain.ROCK), Palette.STONE_DARK)
	assert_eq(terrain.water_deep, Palette.WATER_DEEP)
	assert_eq(Palette.SKIN.size(), PersonData.SKIN_TONES)
	assert_eq(Palette.HAIR.size(), PersonData.HAIR_COLOURS)
	assert_eq(Palette.CLOTH.size(), PersonData.CLOTH_COLOURS)


func test_blender_palette_is_current() -> void:
	var on_disk := FileAccess.get_file_as_string(PaletteGpl.OUT)
	assert_eq(on_disk, PaletteGpl.text(),
		"docs/wiab_palette.gpl is stale: run `godot --headless --path . -s res://tests/tools/palette_gpl.gd`")
