class_name Discovery
extends RefCounted
## Coming upon what the player has left lying about (bible §14.2: "below
## threshold: unnoticed, but may be noticed later as a consequence — someone
## found the rock"). A thing the player moved to where the settlement's
## people pass (LooseObject.discoverable) is found by whoever comes near it
## — once each, and not by those who saw it land.


## Lets a person look about them. If they come upon something, it is put
## before them as a perception (to be made something of like any other) and
## true is returned.
static func look_around(person: PersonData, ctx: AiContext) -> bool:
	if ctx.loose == null or ctx.people.spatial_index == null:
		return false
	var config := Config.memory
	for id in ctx.people.spatial_index.query_radius(person.world2d(), config.find_radius, SpatialIndex.KIND_LOOSE_OBJECT):
		var object := ctx.loose.get_object(id)
		if object == null or not object.discoverable or not object.placed_by_player \
				or object.state != LooseObject.State.RESTING or knows(object, person.id) \
				or ctx.now() - object.moved_tick < config.find_after_minutes:
			continue
		note(object, person.id)
		var found := Stimulus.new()
		found.id = ctx.take_stimulus_id()
		found.type = Stimulus.OBJECT_FOUND
		found.origin = Stimulus.Origin.PLAYER
		found.position = object.position
		found.tick = ctx.now()
		found.object_id = object.id
		Config.reactions.describe(found, clampf(object.mass() / 60.0, 0.0, 1.0))
		found.radius = 0.0 # it is theirs alone to find
		if not ctx.perceptions.has(person.id):
			ctx.perceptions[person.id] = []
		(ctx.perceptions[person.id] as Array).append({"stimulus": found, "direct": false, "witnesses": 1,
			"salience": PerceptionSystem.salience(found, 0.0, 1.0, Config.reactions)})
		return true
	return false


static func knows(object: LooseObject, person_id: int) -> bool:
	return object.discovered_by.has(person_id)


## Notes that a person knows of the object where it lies now.
static func note(object: LooseObject, person_id: int) -> void:
	if not object.discovered_by.has(person_id):
		object.discovered_by.append(person_id)
