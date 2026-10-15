extends SceneTree
## Writes the Palette as a GIMP palette for Blender (Preferences → Add-ons →
## "Import Palettes", then Image Paint / Vertex Paint → Color Palette → import):
##   godot --headless --path . -s res://tests/tools/palette_gpl.gd
## writes docs/wiab_palette.gpl. test_palette fails when that file is stale.

const OUT := "res://docs/wiab_palette.gpl"


static func text() -> String:
	var lines := PackedStringArray()
	lines.append("GIMP Palette")
	lines.append("Name: World in a Box")
	lines.append("Columns: 8")
	lines.append("# From scripts/rendering/palette.gd; written by tests/tools/palette_gpl.gd. Do not edit.")
	var named := Palette.named()
	for key: String in named:
		var c: Color = named[key]
		lines.append("%3d %3d %3d\t%s" % [c.r8, c.g8, c.b8, key])
	return "\n".join(lines) + "\n"


func _init() -> void:
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	if file == null:
		push_error("palette_gpl: cannot write %s (%s)" % [OUT, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	file.store_string(text())
	file.close()
	print("wrote ", OUT, " (", Palette.named().size(), " colours)")
	quit()
