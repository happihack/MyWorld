class_name Catalog
extends RefCounted
## What the data names, checked against the data (buildings & villagers F1):
## every workplace, worker, technology, resource and upgrade a building or an
## occupation names must exist. Each library checks its own files; this
## checks them against one another.


static func check(buildings: BuildingLibrary, occupations: OccupationLibrary, resources: ResourceLibrary,
		techs: TechnologyLibrary) -> PackedStringArray:
	var out := PackedStringArray()
	if buildings == null or occupations == null:
		return out
	for id in buildings.ids():
		var def := buildings.get_def(id)
		if def.tech != &"" and techs != null and not techs.has_def(def.tech):
			out.append("building %s: no such technology %s" % [id, def.tech])
		if def.upgrade_of != &"" and not buildings.has_def(def.upgrade_of):
			out.append("building %s: an upgrade of %s, which is not a building" % [id, def.upgrade_of])
		for trade: Variant in def.workers:
			if not occupations.has_def(StringName(str(trade))):
				out.append("building %s: worked by %s, which is not an occupation" % [id, trade])
		if resources != null:
			for resource in def.resources_named():
				if not resources.has_def(resource):
					out.append("building %s: no such resource %s" % [id, resource])
	for id in occupations.ids():
		var def := occupations.get_def(id)
		for place in def.workplaces:
			if not buildings.has_def(StringName(place)):
				out.append("occupation %s: works at %s, which is not a building" % [id, place])
		var tech := StringName(str(def.requires.get("tech", "")))
		if tech != &"" and techs != null and not techs.has_def(tech):
			out.append("occupation %s: requires %s, which is not a technology" % [id, tech])
		var building := StringName(str(def.requires.get("building", "")))
		if building != &"" and not buildings.has_def(building):
			out.append("occupation %s: requires %s, which is not a building" % [id, building])
	return out
