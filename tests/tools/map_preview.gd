extends SceneTree
## A tool (not a test): draws the lands from above — each template for a few
## seeds, shaded by height, coloured by ground — into one picture, to judge
## the terrain without opening the game.
## Run: --headless -s res://tests/tools/map_preview.gd -- --out=C:/tmp/maps.png --size=64 [--templates=a,b]

const COLORS := {
	0: Color(0.42, 0.68, 0.30), # grass (ChunkData.Terrain)
	1: Color(0.58, 0.45, 0.30), # dirt
	2: Color(0.86, 0.80, 0.55), # sand
	3: Color(0.55, 0.55, 0.57), # rock
	4: Color(0.93, 0.94, 0.96), # snow
	7: Color(0.25, 0.45, 0.80), # riverbed
}


func _init() -> void:
	var out := "C:/tmp/maps.png"
	var size := 64
	var templates := ["river_valley", "broad_valley", "lake_country", "open_plains", "highlands", "forest_vale", "river_bluffs"]
	var seeds := [1, 7, 42]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.get_slice("=", 1)
		elif arg.begins_with("--size="):
			size = int(arg.get_slice("=", 1))
		elif arg.begins_with("--templates="):
			templates = Array(arg.get_slice("=", 1).split(","))
	await process_frame
	var scale := 4 if size <= 64 else 2
	var cell := size * scale + 8
	var image := Image.create(cell * seeds.size(), cell * templates.size(), false, Image.FORMAT_RGB8)
	image.fill(Color(0.1, 0.1, 0.12))
	var config: Variant = load("res://scripts/core/config_types/world_config.gd").new()
	for row in templates.size():
		var template: Variant = load("res://data/worldgen/%s.tres" % templates[row])
		var problems: PackedStringArray = template.validate()
		if not problems.is_empty():
			print("PREVIEW %s: %s" % [templates[row], problems])
		for column in seeds.size():
			var generator: Variant = load("res://scripts/world/world_generator.gd").new(seeds[column], template, config)
			var counts := {}
			for y in size:
				for x in size:
					var tile := Vector2i(x - size / 2, y - size / 2)
					var s: Dictionary = generator.sample_tile(tile)
					var color: Color = COLORS.get(int(s["terrain"]), Color.MAGENTA)
					var shade := 0.55 + 0.45 * float(s["height"]) / 15.0
					if float(s["water"]) > 0.0:
						color = Color(0.25, 0.45, 0.80)
					else:
						color = color * shade
					counts[int(s["terrain"])] = int(counts.get(int(s["terrain"]), 0)) + 1
					# (A darker line where the land steps up.)
					var east: Dictionary = generator.sample_tile(tile + Vector2i(1, 0))
					var south: Dictionary = generator.sample_tile(tile + Vector2i(0, 1))
					var stepped := int(east["height"]) != int(s["height"]) or int(south["height"]) != int(s["height"])
					for py in scale:
						for px in scale:
							var c := color
							if stepped and (px == scale - 1 or py == scale - 1):
								c = color.darkened(0.35)
							image.set_pixel(column * cell + 4 + x * scale + px, row * cell + 4 + y * scale + py, c)
			var total := size * size
			print("PREVIEW %-13s seed %-3d grass %2d%% dirt %2d%% rock %2d%% snow %2d%% water-ish %2d%%" % [templates[row], seeds[column],
				int(counts.get(0, 0)) * 100 / total, int(counts.get(1, 0)) * 100 / total, int(counts.get(3, 0)) * 100 / total,
				int(counts.get(4, 0)) * 100 / total, (int(counts.get(2, 0)) + int(counts.get(7, 0))) * 100 / total])
	image.save_png(out)
	print("PREVIEW saved ", out)
	quit()
