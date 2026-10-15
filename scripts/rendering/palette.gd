class_name Palette
extends RefCounted
## The colours of everything inside the box, in one place (the art decisions of
## 2026-10-15, docs/art_assets.md §5: direction A, vertex colour only). The mesh
## libraries, the terrain palette's defaults and the box frame read from here;
## nothing else names a world colour. Blender gets the same colours from
## docs/wiab_palette.gpl, written by tests/tools/palette_gpl.gd and kept current
## by test_palette.
##
## Thirty-odd base colours in families, then the shades the shapes use, each a
## base colour darkened or lightened by the factor in its comment (test_palette
## holds them to it). Everything is a plain constant so the mesh libraries can
## alias them as constants of their own.

# --- wood -----------------------------------------------------------------------------
## Living bark and plain wood: trunks, staffs, handles.
const BARK := Color(0.42, 0.29, 0.18)
## Worked timber: logs, beams, window frames.
const TIMBER := Color(0.30, 0.20, 0.12)
## The dark of a doorway.
const DOORWAY := Color(0.22, 0.15, 0.10)

# --- foliage ----------------------------------------------------------------------------
const LEAF := Color(0.24, 0.50, 0.22)
const LEAF_LIGHT := Color(0.36, 0.62, 0.27)
const PINE := Color(0.14, 0.38, 0.24)
## Young growth: herbs, crops, grass blades, the leaves of a root.
const SPROUT := Color(0.40, 0.60, 0.26)
## The lit tip of a grass blade.
const SPROUT_LIGHT := Color(0.52, 0.74, 0.34)
## Turf and moss on old stone.
const MOSS := Color(0.36, 0.50, 0.30)
## The green of a grass tile at its lushest.
const GRASS := Color(0.46, 0.70, 0.33)

# --- earth ------------------------------------------------------------------------------
const EARTH := Color(0.60, 0.47, 0.32)
## Tilled, wet or dead: farmland, mud, a failed crop.
const LOAM := Color(0.38, 0.28, 0.19)
## A riverbed.
const SILT := Color(0.52, 0.47, 0.38)
const SAND := Color(0.86, 0.80, 0.58)

# --- stone --------------------------------------------------------------------------------
const STONE := Color(0.56, 0.56, 0.58)
const ASH := Color(0.30, 0.30, 0.30)
const SNOW := Color(0.95, 0.96, 0.98)

# --- pale and dry ---------------------------------------------------------------------------
## Dry grass, straw, stubble, nets.
const STRAW := Color(0.76, 0.66, 0.38)
## Scrolls, mushroom stems, bone.
const PARCHMENT := Color(0.90, 0.84, 0.66)

# --- made things -------------------------------------------------------------------------
## Thatch and wicker: roofs, baskets.
const THATCH := Color(0.74, 0.58, 0.28)
## Walls of daub.
const DAUB := Color(0.78, 0.66, 0.47)
const CLAY := Color(0.70, 0.42, 0.28)
## Hide, nuts, roots, dried fish.
const LEATHER := Color(0.52, 0.36, 0.24)
const REEDS := Color(0.62, 0.64, 0.46)

# --- bright ------------------------------------------------------------------------------------
const BERRY := Color(0.80, 0.16, 0.30)
## Fruit, red caps, a net's floats.
const EMBER := Color(0.86, 0.30, 0.20)
## Ripe grain.
const GOLD := Color(0.90, 0.74, 0.28)
const FLAME := Color(1.0, 0.55, 0.10)
const FLAME_HOT := Color(1.0, 0.86, 0.35)

# --- water and night -----------------------------------------------------------------------
const WATER_SHALLOW := Color(0.40, 0.74, 0.86)
const WATER_DEEP := Color(0.13, 0.40, 0.68)
const FOAM := Color(0.95, 0.98, 1.0)
## The strange object; near the background's blue.
const INK := Color(0.20, 0.23, 0.33)
const GLINT := Color(0.45, 0.80, 0.78)

# --- the box ------------------------------------------------------------------------------------
const BRASS := Color(0.80, 0.63, 0.32)
const GLASS := Color(0.82, 0.92, 1.0)

## The base colours above, in order: the shades below are these darkened or
## lightened, and the people's arrays are their own. test_palette keeps the
## bases apart from each other.
const BASES: Array[StringName] = [
	&"BARK", &"TIMBER", &"DOORWAY", &"LEAF", &"LEAF_LIGHT", &"PINE", &"SPROUT", &"SPROUT_LIGHT", &"MOSS", &"GRASS", &"EARTH", &"LOAM", &"SILT", &"SAND", &"STONE", &"ASH", &"SNOW", &"STRAW", &"PARCHMENT", &"THATCH", &"DAUB", &"CLAY", &"LEATHER", &"REEDS", &"BERRY", &"EMBER", &"GOLD", &"FLAME", &"FLAME_HOT", &"WATER_SHALLOW", &"WATER_DEEP", &"FOAM", &"INK", &"GLINT", &"BRASS", &"GLASS",
]

# --- shades ---------------------------------------------------------------------------------------
# Each is a base colour times the factor named, rounded to two places.
const BARK_DARK := Color(0.33, 0.23, 0.14) # BARK × 0.78
const BARK_LIGHT := Color(0.46, 0.32, 0.20) # BARK × 1.10
const BARK_DEEP := Color(0.25, 0.17, 0.11) # BARK × 0.60 (the box's shadowed wood)
const BOX_WOOD := Color(0.37, 0.26, 0.16) # BARK × 0.88
const LEAF_DARK := Color(0.22, 0.46, 0.20) # LEAF × 0.92 (bushes)
const LEAF_LIGHT_DARK := Color(0.32, 0.55, 0.24) # LEAF_LIGHT × 0.88 (bushes' light side)
const PINE_LIGHT := Color(0.22, 0.48, 0.29) # between PINE and LEAF_LIGHT
const STONE_DARK := Color(0.43, 0.43, 0.45) # STONE × 0.77
const STONE_LIGHT := Color(0.60, 0.60, 0.63) # STONE × 1.08 (a rock tile's top)
const STONE_WORN := Color(0.50, 0.50, 0.52) # STONE × 0.90 (ruins)
const PAVING := Color(0.58, 0.56, 0.53) # STONE towards SAND (laid stones)
const EARTH_DARK := Color(0.50, 0.39, 0.27) # EARTH × 0.83 (the soil under turf)
const EARTH_LIGHT := Color(0.64, 0.50, 0.34) # EARTH × 1.07 (a worn path)
const FIELD := Color(0.54, 0.42, 0.29) # EARTH × 0.90 (farmland)
const LOAM_DARK := Color(0.33, 0.24, 0.16) # LOAM × 0.86 (tilled soil)
const MUD := Color(0.40, 0.32, 0.24) # LOAM towards SILT
const SAND_DARK := Color(0.73, 0.68, 0.49) # SAND × 0.85
const SNOW_SHADE := Color(0.62, 0.62, 0.67) # SNOW × 0.66, bluer
const THATCH_DARK := Color(0.55, 0.43, 0.21) # THATCH × 0.74
const THATCH_DRY := Color(0.67, 0.52, 0.25) # THATCH × 0.90 (a dry crop)
const THATCH_HUSK := Color(0.63, 0.49, 0.24) # THATCH × 0.85 (a seed)
const DAUB_DARK := Color(0.62, 0.53, 0.38) # DAUB × 0.80
const DAUB_PALE := Color(0.74, 0.63, 0.45) # DAUB × 0.95 (a heap of mushrooms)
const CLAY_DARK := Color(0.52, 0.31, 0.21) # CLAY × 0.74
const CLAY_RED := Color(0.73, 0.34, 0.29) # CLAY towards BERRY (a root's top)
const LEATHER_DARK := Color(0.37, 0.26, 0.17) # LEATHER × 0.72
const LEATHER_LIGHT := Color(0.62, 0.43, 0.29) # LEATHER × 1.20 (dried fish, nuts)
const LEATHER_CURED := Color(0.44, 0.31, 0.20) # LEATHER × 0.85 (preserved food)
const REEDS_DARK := Color(0.44, 0.45, 0.33) # REEDS × 0.71
const PARCHMENT_DARK := Color(0.70, 0.66, 0.51) # PARCHMENT × 0.78 (nets)
const MEAT := Color(0.64, 0.22, 0.25) # BERRY towards LOAM
const FRUIT := Color(0.87, 0.43, 0.22) # EMBER towards GOLD
const FISH := Color(0.48, 0.65, 0.72) # WATER_SHALLOW towards STONE
const WATER_HELD := Color(0.29, 0.60, 0.79) # between WATER_DEEP and WATER_SHALLOW (a pot of it)

# --- people (bible §28.3: saturated clothing against muted land) ------------------------------------
## Indexed by PersonData's appearance fields; the sizes are checked by the tests.
const SKIN: Array[Color] = [
	Color(0.96, 0.80, 0.66), Color(0.89, 0.69, 0.52), Color(0.78, 0.57, 0.40),
	Color(0.64, 0.44, 0.29), Color(0.48, 0.32, 0.21), Color(0.35, 0.23, 0.16),
]
const HAIR: Array[Color] = [
	Color(0.10, 0.08, 0.07), Color(0.24, 0.15, 0.09), Color(0.42, 0.26, 0.13),
	Color(0.62, 0.42, 0.18), Color(0.50, 0.20, 0.10),
]
const HAIR_GREY := Color(0.78, 0.78, 0.76)
## Undyed cloth.
const CLOTH: Array[Color] = [
	Color(0.80, 0.25, 0.20), Color(0.93, 0.66, 0.16), Color(0.22, 0.45, 0.78),
	Color(0.58, 0.28, 0.66), Color(0.90, 0.44, 0.16), Color(0.92, 0.90, 0.82),
]
## Woven and dyed (M16.3): madder, indigo, saffron, woad, a purple from
## berries, a green from bark; deeper than undyed cloth.
const CLOTH_DYED: Array[Color] = [
	Color(0.62, 0.10, 0.16), Color(0.16, 0.20, 0.55), Color(0.86, 0.62, 0.06),
	Color(0.10, 0.44, 0.44), Color(0.46, 0.16, 0.44), Color(0.22, 0.46, 0.20),
]


## A colour darkened (k < 1) or lightened (k > 1) in place, alpha kept.
static func shade(color: Color, k: float) -> Color:
	return Color(minf(color.r * k, 1.0), minf(color.g * k, 1.0), minf(color.b * k, 1.0), color.a)


## Every named colour, in declaration order: name -> Color (arrays of colours
## are entered as NAME_1, NAME_2 …). For the Blender palette and the tests.
static func named() -> Dictionary:
	var out := {}
	var constants: Dictionary = (Palette as Script).get_script_constant_map()
	for key: String in constants:
		var value: Variant = constants[key]
		if value is Color:
			out[key] = value
		elif value is Array:
			for i in (value as Array).size():
				if value[i] is Color:
					out["%s_%d" % [key, i + 1]] = value[i]
	return out
