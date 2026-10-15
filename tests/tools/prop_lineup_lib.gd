extends RefCounted
## Builds the lineup scene for prop_lineup.gd: the shapes on a green ground
## under the game's sun, each on its own patch, with its name below it.

const PROP_SHADER := preload("res://assets/shaders/prop.gdshader")
const PERSON_SHADER := preload("res://assets/shaders/person.gdshader")
const SPACING := 1.4

## The shapes shown, by set: [label, kind, variant, look].
static func lineup(set: String) -> Array:
	var nature := [
		["tree 0", PropData.Kind.TREE, 0, 0], ["tree 1", PropData.Kind.TREE, 1, 0],
		["tree 2", PropData.Kind.TREE, 2, 0], ["tree 3", PropData.Kind.TREE, 3, 0],
		["stump", PropData.Kind.TREE, 0, ResourceNodes.Look.STUMP],
		["rock 0", PropData.Kind.ROCK, 0, 0], ["rock 1", PropData.Kind.ROCK, 1, 0],
		["bush 0", PropData.Kind.BUSH, 0, 0], ["bush 1", PropData.Kind.BUSH, 1, 0],
		["mushroom", PropData.Kind.MUSHROOM, 1, 0], ["roots", PropData.Kind.ROOTS, 0, 0],
		["orchard", PropData.Kind.ORCHARD, 2, 0],
	]
	var buildings := [
		["hut thatch", PropData.Kind.HUT, 0, 0], ["hut reeds", PropData.Kind.HUT, 1, 0],
		["hut hides", PropData.Kind.HUT, 2, 0], ["campfire", PropData.Kind.CAMPFIRE, 0, 0],
		["storehouse", PropData.Kind.STOREHOUSE, 0, 0], ["root cellar", PropData.Kind.STOREHOUSE, 1, 0],
		["granary", PropData.Kind.GRANARY, 0, 0], ["smokehouse", PropData.Kind.SMOKEHOUSE, 0, 0],
		["well", PropData.Kind.WELL, 0, 0], ["workshop", PropData.Kind.WORKSHOP, 0, 0],
		["woodshed", PropData.Kind.WOODSHED, 0, 0], ["kiln", PropData.Kind.KILN, 0, 0],
		["quarry", PropData.Kind.QUARRY, 0, 0], ["shrine", PropData.Kind.SHRINE, 0, 0],
		["record stone", PropData.Kind.RECORD_STONE, 1, 0], ["ruin", PropData.Kind.RUIN, 0, 0],
	]
	match set:
		"nature":
			return nature
		"buildings":
			return buildings
		"animals", "loose":
			return [] # (meshes of their own: see extra_meshes)
	return nature + buildings


## Meshes that are not prop templates: [label, ArrayMesh, triangle count].
static func extra_meshes(set: String, library: PropMeshLibrary) -> Array:
	var out := []
	if set == "animals":
		for name in ["deer", "rabbit", "fox", "bear", "wolf", "lion", "boar"]:
			var def: SpeciesDef = load("res://data/species/%s.tres" % name)
			var mesh := AnimalMeshLibrary.mesh_for(def)
			if mesh != null:
				var count := (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
				out.append([name, mesh, count])
	elif set == "loose":
		var items := [["pebble", LooseObject.Kind.PEBBLE, 0], ["rock", LooseObject.Kind.ROCK, 0], ["boulder", LooseObject.Kind.BOULDER, 0],
			["log", LooseObject.Kind.LOG, 0], ["fruit", LooseObject.Kind.FRUIT, 0], ["seed", LooseObject.Kind.SEED, 0],
			["strange", LooseObject.Kind.STRANGE_OBJECT, 0]]
		for i in LooseObject.PILE_RESOURCES.size():
			items.append(["pile " + String(LooseObject.PILE_RESOURCES[i]), LooseObject.Kind.PILE, i])
		for item: Array in items:
			var template := library.loose_template(item[1], item[2])
			if template != null:
				out.append([item[0], _mesh(template), template.triangle_count()])
	return out


static func build(set: String, season: float, night: float) -> Node3D:
	if set == "box":
		return build_box()
	var scene := Node3D.new()
	scene.name = "Lineup"
	var items := lineup(set)
	var library := PropMeshLibrary.new()
	var extras := extra_meshes(set, library)
	var total := items.size() + extras.size()
	var columns := 6 if total > 6 else total
	var rows := ceili(float(total) / columns)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = WorldLighting.BACKGROUND
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = WorldLighting.AMBIENT_COLOR
	env.ambient_light_energy = 0.9
	environment.environment = env
	scene.add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = WorldLighting.SUN_ROTATION_DEG
	sun.light_color = WorldLighting.SUN_COLOR
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	scene.add_child(sun)

	# The ground: one quad per patch, in the grass colour, through the terrain's
	# look-alike (a plain material is enough for the shapes to stand on).
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(columns * SPACING + 1.0, rows * SPACING + 1.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Palette.GRASS
	ground_material.roughness = 1.0
	ground.material_override = ground_material
	ground.position = Vector3((columns - 1) * SPACING * 0.5, 0.0, (rows - 1) * SPACING * 0.5)
	scene.add_child(ground)

	var material := ShaderMaterial.new()
	material.shader = PROP_SHADER
	material.set_shader_parameter(&"season_strength", season)
	if season > 0.0: # (autumn: the tints the seasons give the leaves)
		material.set_shader_parameter(&"season_tint", Color(0.80, 0.46, 0.14))
		material.set_shader_parameter(&"season_tint_other", Color(0.86, 0.66, 0.18))
	material.set_shader_parameter(&"night_glow", night)
	var shown := [] # [label, mesh, triangles]
	for item: Array in items:
		var template: PropMeshLibrary.Template = library.template_for(item[1], item[2], item[3])
		if template != null:
			shown.append([item[0], _mesh(template), template.triangle_count()])
	shown.append_array(extras)
	for i in shown.size():
		var item: Array = shown[i]
		var at := Vector3((i % columns) * SPACING, 0.0, (i / columns) * SPACING)
		var instance := MeshInstance3D.new()
		instance.mesh = item[1]
		instance.material_override = material
		instance.position = at
		scene.add_child(instance)
		var label := Label3D.new()
		label.text = "%s  %d tri" % [item[0], item[2]]
		label.font_size = 32
		label.pixel_size = 0.004
		label.modulate = Color(0.95, 0.92, 0.85)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = at + Vector3(0.0, 0.01, 0.7)
		scene.add_child(label)

	var camera := Camera3D.new()
	var centre := Vector3((columns - 1) * SPACING * 0.5, 0.4, (rows - 1) * SPACING * 0.5)
	camera.rotation_degrees = Vector3(-48.0, 0.0, 0.0)
	var distance := maxf(columns * SPACING * 0.78, rows * SPACING * 1.1) + 1.0
	camera.position = centre + Vector3(0.0, sin(deg_to_rad(48.0)) * distance, cos(deg_to_rad(48.0)) * distance)
	camera.fov = 45.0
	camera.current = true
	scene.add_child(camera)
	return scene


static func _mesh(t: PropMeshLibrary.Template) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = t.vertices
	arrays[Mesh.ARRAY_NORMAL] = t.normals
	arrays[Mesh.ARRAY_COLOR] = t.colors
	arrays[Mesh.ARRAY_TEX_UV] = t.uvs()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The box itself around a small flat world, on its table, from the game's angle.
static func build_box() -> Node3D:
	var scene := Node3D.new()
	scene.name = "Box"
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = WorldLighting.BACKGROUND
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = WorldLighting.AMBIENT_COLOR
	env.ambient_light_energy = 0.9
	environment.environment = env
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = WorldLighting.SUN_ROTATION_DEG
	sun.light_color = WorldLighting.SUN_COLOR
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	scene.add_child(sun)
	var bounds := Rect2i(-16, -16, 32, 32)
	var frame := BoxFrame.new()
	scene.add_child(frame)
	frame.build(bounds, 6.0)
	frame.set_label("Ash Hollow")
	frame.set_lid_open(0.85)
	# The world inside: a slab of grass to the rim.
	var ground := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(bounds.size.x, 1.0, bounds.size.y)
	ground.mesh = slab
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Palette.GRASS
	ground_material.roughness = 1.0
	ground.material_override = ground_material
	ground.position = Vector3(0.0, -0.5 + 0.3, 0.0)
	scene.add_child(ground)
	# The table under it.
	var table := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300.0, 300.0)
	table.mesh = plane
	var table_material := ShaderMaterial.new()
	table_material.shader = preload("res://assets/shaders/table.gdshader")
	table_material.set_shader_parameter(&"box_half", Vector2(frame.outer_rect().size) * 0.5)
	table.material_override = table_material
	table.position = Vector3(0.0, frame.bottom_y() - 0.01, 0.0)
	scene.add_child(table)
	var camera := Camera3D.new()
	camera.rotation_degrees = Vector3(-34.0, 0.0, 0.0)
	camera.position = Vector3(0.0, 34.0, 52.0)
	camera.fov = 48.0
	camera.current = true
	scene.add_child(camera)
	return scene
