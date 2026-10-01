extends TestCase
## People on screen (M4.2): the shared body, pooled views that follow their
## person, and markers from far away.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const ViewScript := preload("res://scripts/rendering/world_view.gd")
const PersonScene := preload("res://scenes/people/person_view.tscn")
const YEAR := 1440 * 24

var session: WorldSession
var view: WorldView
var people_view: PeopleView
var rig: CameraRig


func before_each() -> void:
	SaveManager.attach(null)
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.behavior.enabled = false # people stand where the tests put them
	view = ViewScript.new()
	add_child(view)
	view.show_world(session.world, session.props, session.start, session.loose)
	view.show_people(session.people, session.clock, session.occupations)
	people_view = view.people_view()
	people_view.set_process(false) # the tests step it by hand
	rig = view.camera_rig()
	rig.set_process(false)
	rig.set_view_size(Vector2(1080, 1920))


func after_each() -> void:
	view.queue_free()
	session.queue_free()
	await wait_frames(1)


func _home() -> Vector2:
	return Vector2(session.start.settlement_tile) + Vector2(0.5, 0.5)


func _look_at(xz: Vector2, distance: float) -> void:
	rig.focus_on(Vector3(xz.x, 0, xz.y), distance, false)
	for i in 90:
		rig.advance(1.0 / 60.0)
	people_view.refresh(0.0)


func _frames(seconds: float) -> void:
	for i in int(seconds * 60.0):
		people_view.refresh(1.0 / 60.0)


func _of(stage: PersonData.LifeStage) -> PersonData:
	for p in session.people.all_people():
		if p.life_stage(session.clock.tick, YEAR, Config.people) == stage:
			return p
	return null


func _with(occupation: StringName) -> PersonData:
	for p in session.people.all_people():
		if p.occupation_id == occupation:
			return p
	return null


# --- the shapes ---------------------------------------------------------------------------------

func test_everyone_shares_one_small_body() -> void:
	var body := PersonMeshLibrary.body()
	assert_true(body == PersonMeshLibrary.body(), "built once")
	assert_eq(body.get_surface_count(), 1)
	var arrays := body.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_true(vertices.size() / 3 <= 200, "tens of triangles, not hundreds (%d)" % (vertices.size() / 3))
	assert_eq(colors.size(), vertices.size())
	assert_eq(uvs.size(), vertices.size())
	var lowest := INF
	var highest := -INF
	var has := {"cloth": false, "skin": false, "hair": false}
	var swings := {-1.0: 0, 1.0: 0}
	for i in vertices.size():
		lowest = minf(lowest, vertices[i].y)
		highest = maxf(highest, vertices[i].y)
		has["cloth"] = has["cloth"] or colors[i].r > 0.5
		has["skin"] = has["skin"] or colors[i].g > 0.5
		has["hair"] = has["hair"] or colors[i].b > 0.5
		if uvs[i].x != 0.0:
			swings[uvs[i].x] += 1
			assert_true(uvs[i].y >= 0.0 and uvs[i].y <= 1.0)
	assert_near(lowest, 0.0, 0.001, "feet on the ground")
	assert_near(highest, 0.99, 0.02, "one unit tall")
	assert_eq(has, {"cloth": true, "skin": true, "hair": true})
	assert_true(swings[-1.0] > 0 and swings[-1.0] == swings[1.0], "limbs swing both ways")


func test_colours_and_carried_things_match_the_data() -> void:
	assert_eq(PersonMeshLibrary.SKIN.size(), PersonData.SKIN_TONES)
	assert_eq(PersonMeshLibrary.HAIR.size(), PersonData.HAIR_COLOURS)
	assert_eq(PersonMeshLibrary.CLOTH.size(), PersonData.CLOTH_COLOURS)
	assert_eq(PersonMeshLibrary.hair(1, PersonData.LifeStage.ELDER), PersonMeshLibrary.ELDER_HAIR, "the old are grey")
	assert_eq(PersonMeshLibrary.cloth(PersonData.CLOTH_COLOURS + 1), PersonMeshLibrary.CLOTH[1], "indices wrap")
	assert_eq(PersonMeshLibrary.skin(-1), PersonMeshLibrary.SKIN[PersonData.SKIN_TONES - 1])
	for kind in PersonMeshLibrary.ACCESSORIES:
		var mesh := PersonMeshLibrary.accessory(kind)
		assert_not_null(mesh, String(kind))
		assert_true(mesh.get_faces().size() / 3 <= 60)
		assert_true(mesh == PersonMeshLibrary.accessory(kind), "built once")
	assert_null(PersonMeshLibrary.accessory(&""))
	assert_null(PersonMeshLibrary.accessory(&"umbrella"))
	# Whatever the occupations in data name, the library can draw.
	for id in session.occupations.ids():
		var carried := session.occupations.get_def(id).accessory
		assert_true(carried == &"" or PersonMeshLibrary.accessory(carried) != null, "%s carries '%s'" % [id, carried])
	assert_eq(session.occupations.get_def(&"woodcutter").accessory, &"axe")
	assert_eq(session.occupations.get_def(&"forager").accessory, &"basket")
	assert_eq(session.occupations.get_def(&"elder").accessory, &"staff")


func test_children_grow_and_elders_stoop() -> void:
	var config := Config.people
	assert_near(PersonMeshLibrary.height_factor(30, config), 1.0)
	assert_true(PersonMeshLibrary.height_factor(1, config) < 0.5)
	assert_true(PersonMeshLibrary.height_factor(8, config) > PersonMeshLibrary.height_factor(3, config))
	assert_true(PersonMeshLibrary.height_factor(config.adult_from_years - 2, config) < 1.0)
	assert_true(PersonMeshLibrary.height_factor(70, config) < 1.0)
	assert_true(PersonMeshLibrary.stoop_for(PersonData.LifeStage.ELDER) > 0.0)
	assert_eq(PersonMeshLibrary.stoop_for(PersonData.LifeStage.ADULT), 0.0)


# --- the pool -----------------------------------------------------------------------------------

func test_pool_lends_views_and_takes_them_back() -> void:
	var prepared := []
	var pool := EntityViewPool.new(PersonScene, 2, func(node: Node3D) -> void: prepared.append(node))
	add_child(pool)
	var a := pool.acquire(11)
	assert_not_null(a)
	assert_true(pool.acquire(11) == a, "one view per entity")
	var b := pool.acquire(12)
	assert_true(b != a)
	assert_null(pool.acquire(13), "no more than the pool may hold")
	assert_eq(pool.active_count(), 2)
	assert_eq(pool.created_count(), 2)
	assert_eq(prepared.size(), 2, "each view is prepared once")
	assert_eq(pool.bound_ids(), [11, 12] as Array[int])
	assert_true(pool.view_of(12) == b and pool.has_view(12))
	assert_true(pool.release(11))
	assert_false(pool.release(11))
	assert_false(a.visible, "a returned view is hidden")
	assert_null(pool.view_of(11))
	assert_eq(pool.free_count(), 1)
	var c := pool.acquire(13)
	assert_true(c == a, "views are reused")
	assert_eq(pool.created_count(), 2)
	assert_eq(prepared.size(), 2)
	pool.release_all()
	assert_eq(pool.active_count(), 0)
	assert_eq(pool.free_count(), 2)
	assert_eq(pool.capacity(), 2)
	pool.queue_free()


# --- one view -----------------------------------------------------------------------------------

func test_a_view_looks_like_its_person() -> void:
	_look_at(_home(), 24.0)
	var adult := _with(&"woodcutter")
	var child := _of(PersonData.LifeStage.CHILD)
	var elder := _of(PersonData.LifeStage.ELDER)
	var adult_view := people_view.view_of(adult.id)
	var child_view := people_view.view_of(child.id)
	var elder_view := people_view.view_of(elder.id)
	assert_not_null(adult_view)
	assert_not_null(child_view)
	assert_not_null(elder_view)
	assert_true(adult_view.visible)
	assert_eq(adult_view.person_id, adult.id)
	assert_eq(adult_view.body_color(&"cloth_color"), PersonMeshLibrary.cloth(adult.appearance["cloth"]))
	assert_eq(adult_view.body_color(&"skin_color"), PersonMeshLibrary.skin(adult.appearance["skin"]))
	assert_eq(adult_view.body_color(&"hair_color"), PersonMeshLibrary.hair(adult.appearance["hair"], PersonData.LifeStage.ADULT))
	assert_eq(elder_view.body_color(&"hair_color"), PersonMeshLibrary.ELDER_HAIR)
	assert_true(float(elder_view.body_color(&"stoop")) > 0.0, "the old stoop")
	assert_eq(float(adult_view.body_color(&"stoop")), 0.0)
	assert_true(adult_view.body_color(&"phase") != elder_view.body_color(&"phase"), "nobody moves in unison")
	# Size.
	assert_near(adult_view.scale.y, PersonMeshLibrary.ADULT_HEIGHT * float(adult.appearance["height"]), 0.0001)
	assert_true(child_view.scale.y < adult_view.scale.y * 0.8, "children are smaller")
	assert_near(adult_view.scale.x / adult_view.scale.y, PersonMeshLibrary.BUILD * float(adult.appearance["build"]), 0.0001)
	# What they carry.
	assert_eq(adult_view.accessory, &"axe")
	assert_true(adult_view.accessory_mesh() == PersonMeshLibrary.accessory(&"axe"))
	assert_true(elder_view.accessory_mesh() == PersonMeshLibrary.accessory(&"staff"))
	assert_null(child_view.accessory_mesh(), "children carry nothing")
	# Where they stand and where they look.
	assert_eq(adult_view.position, people_view.ground_position(adult))
	assert_near(adult_view.position.y, session.world.get_height(adult.position) * session.world.height_step, 0.0001)
	var looks := adult_view.global_transform.basis.x.normalized() # the body faces +X
	var to_fire := Vector3(_home().x, 0, _home().y) - adult_view.position
	to_fire.y = 0.0
	assert_true(looks.dot(to_fire.normalized()) > 0.99, "facing the fire, as the data says")


func test_a_view_follows_its_person_smoothly() -> void:
	_look_at(_home(), 24.0)
	var person := _with(&"forager")
	var shown := people_view.view_of(person.id)
	var from := shown.position
	session.people.move(person.id, person.position + Vector2i(1, 0), Vector2(0.5, 0.5), person.facing)
	var target := people_view.ground_position(person)
	people_view.refresh(1.0 / 60.0)
	var first_step := shown.position.distance_to(from)
	assert_true(first_step > 0.0 and first_step < 0.2, "no jump: it sets off (%.3f)" % first_step)
	var walked := 0.0
	var heading_ok := false
	var previous := shown.position
	for i in 20:
		people_view.refresh(1.0 / 60.0)
		assert_true(shown.position.distance_to(previous) < 0.25, "no jumps on the way")
		previous = shown.position
		walked = maxf(walked, shown.walk)
		if shown.global_transform.basis.x.normalized().dot(Vector3(target.x - from.x, 0, target.z - from.z).normalized()) > 0.9:
			heading_ok = true
	assert_true(walked > 0.3, "it is seen walking (%.2f)" % walked)
	assert_true(float(shown.body_color(&"walk")) > 0.0, "and the shader knows")
	assert_true(heading_ok, "turned the way it goes")
	_frames(2.0)
	assert_true(shown.position.distance_to(target) < 0.01, "it arrives")
	assert_near(shown.walk, 0.0, 0.0001, "and stands again")
	assert_eq(float(shown.body_color(&"walk")), 0.0)
	var looks := shown.global_transform.basis.x.normalized()
	assert_true(looks.dot(Vector3(cos(person.facing), 0, sin(person.facing))) > 0.98, "facing as the data says again")


func test_a_view_never_overshoots() -> void:
	_look_at(_home(), 24.0)
	var person := _with(&"forager")
	var shown := people_view.view_of(person.id)
	var from := shown.position
	session.people.move(person.id, person.position + Vector2i(1, 0), person.sub_tile_offset, person.facing)
	var target := people_view.ground_position(person)
	var total := from.distance_to(target)
	for i in 180:
		people_view.refresh(1.0 / 60.0)
		assert_true(shown.position.distance_to(from) <= total + 0.002, "never past where the person is")


func test_a_person_moved_far_away_is_not_dragged_across_the_world() -> void:
	_look_at(_home(), 60.0)
	var person := _with(&"forager")
	var shown := people_view.view_of(person.id)
	session.people.move(person.id, person.position + Vector2i(8, 0), Vector2(0.5, 0.5))
	people_view.refresh(1.0 / 60.0)
	assert_eq(shown.position, people_view.ground_position(person), "it is simply there")
	assert_near(shown.walk, 0.0, 0.0001)


func test_a_view_changes_with_its_person() -> void:
	_look_at(_home(), 24.0)
	var person := _with(&"forager")
	var shown := people_view.view_of(person.id)
	assert_eq(shown.accessory, &"basket")
	person.occupation_id = &"woodcutter"
	for i in PeopleView.DRESS_CHECK_FRAMES:
		people_view.refresh(0.016)
	assert_eq(shown.accessory, &"axe", "new work, new tool")
	var child := _of(PersonData.LifeStage.CHILD)
	var small := people_view.view_of(child.id).scale.y
	session.clock.tick += 3 * YEAR
	for i in PeopleView.DRESS_CHECK_FRAMES:
		people_view.refresh(0.016)
	assert_true(people_view.view_of(child.id).scale.y > small, "children grow")


# --- everyone -----------------------------------------------------------------------------------

func test_everyone_in_sight_is_drawn_up_close() -> void:
	_look_at(_home(), 24.0)
	assert_eq(people_view.shown_count(), session.people.size(), "the whole band stands around the fire")
	assert_true(people_view.bodies_shown())
	assert_eq(people_view.marker_count(), 0, "no markers this close")
	assert_eq(people_view.marker_alpha(), 0.0)
	for p in session.people.all_people():
		var shown := people_view.view_of(p.id)
		assert_not_null(shown, p.given_name)
		assert_true(shown.visible)
		assert_eq(shown.person_id, p.id)


func test_people_out_of_sight_give_their_views_back() -> void:
	_look_at(_home(), 24.0)
	var made := people_view.pool().created_count()
	assert_eq(made, session.people.size())
	_look_at(_home() + Vector2(-30.0, 25.0), 9.0)
	assert_eq(people_view.shown_count(), 0, "nobody lives over there")
	assert_eq(people_view.pool().free_count(), made)
	for node in people_view.pool().get_children():
		assert_false((node as PersonView).visible)
		assert_false((node as PersonView).is_bound())
	_look_at(_home(), 24.0)
	assert_eq(people_view.shown_count(), session.people.size(), "back in sight, back on screen")
	assert_eq(people_view.pool().created_count(), made, "with the same views")
	for p in session.people.all_people():
		assert_eq(people_view.view_of(p.id).position, people_view.ground_position(p), "standing where they are, not gliding in")


func test_from_far_away_people_are_markers() -> void:
	rig.frame_box(false)
	for i in 90:
		rig.advance(1.0 / 60.0)
	people_view.refresh(0.0)
	assert_false(people_view.bodies_shown(), "a body would be a few pixels")
	assert_eq(people_view.shown_count(), 0)
	assert_eq(people_view.marker_count(), session.people.size(), "but nobody is lost")
	assert_near(people_view.marker_alpha(), 1.0)
	# A marker floats over its person and keeps its size on screen.
	var first := session.people.all_people()[0]
	var marker := people_view.marker_transform(0)
	var feet := people_view.ground_position(first)
	assert_near(marker.origin.x, feet.x, 0.0001)
	assert_near(marker.origin.z, feet.z, 0.0001)
	assert_true(marker.origin.y > feet.y + PersonMeshLibrary.ADULT_HEIGHT)
	var on_screen := marker.basis.get_scale().x / rig.world_units_per_screen_unit(rig.pivot())
	assert_near(on_screen, PeopleView.MARKER_SIZE, 0.01)
	_look_at(_home(), 110.0)
	var nearer := people_view.marker_transform(0).basis.get_scale().x / rig.world_units_per_screen_unit(rig.pivot())
	assert_near(nearer, PeopleView.MARKER_SIZE, 0.01, "the same size on screen at another distance")


func test_markers_fade_in_while_bodies_are_still_there() -> void:
	var alphas: Array[float] = []
	var both := false
	for distance: float in [24.0, 50.0, 70.0, 90.0, 110.0, 140.0, 200.0]:
		_look_at(_home(), distance)
		alphas.append(people_view.marker_alpha())
		if people_view.shown_count() > 0 and people_view.marker_count() > 0:
			both = true
	for i in range(1, alphas.size()):
		assert_true(alphas[i] >= alphas[i - 1], "further away, never fewer markers (%s)" % [alphas])
	assert_eq(alphas[0], 0.0)
	assert_eq(alphas[-1], 1.0)
	assert_true(both, "no distance at which people are neither bodies nor markers")
	# Never a gap: wherever bodies are gone, markers are fully there.
	for distance in range(20, 260, 10):
		_look_at(_home(), float(distance))
		if not people_view.bodies_shown():
			assert_near(people_view.marker_alpha(), 1.0, 0.0001, "at distance %d" % distance)


func test_the_view_keeps_up_with_who_is_in_the_world() -> void:
	_look_at(_home(), 24.0)
	var count := session.people.size()
	var gone := _with(&"forager")
	var their_view := people_view.view_of(gone.id)
	session.people.remove(gone.id)
	assert_false(their_view.visible, "gone at once")
	people_view.refresh(0.016)
	assert_eq(people_view.shown_count(), count - 1)
	assert_null(people_view.view_of(gone.id))
	# A newcomer.
	var newcomer := PersonData.new()
	newcomer.id = session.ids.next_id()
	newcomer.given_name = "Newcomer"
	newcomer.birth_tick = -25 * YEAR
	newcomer.position = session.start.settlement_tile + Vector2i(1, 1)
	newcomer.appearance = {"cloth": 2, "skin": 1, "hair": 0}
	session.people.add(newcomer)
	people_view.refresh(0.016)
	assert_eq(people_view.shown_count(), count)
	var shown := people_view.view_of(newcomer.id)
	assert_not_null(shown)
	assert_eq(shown.body_color(&"cloth_color"), PersonMeshLibrary.cloth(2))
	assert_null(shown.accessory_mesh(), "no occupation, nothing carried")
	# From far away too.
	rig.frame_box(false)
	for i in 90:
		rig.advance(1.0 / 60.0)
	people_view.refresh(0.0)
	assert_eq(people_view.marker_count(), count)


func test_people_simulated_from_afar_have_no_body() -> void:
	_look_at(_home(), 24.0)
	var person := _with(&"forager")
	person.sim_tier = 1
	people_view.refresh(0.016)
	assert_null(people_view.view_of(person.id), "only people simulated in full are drawn as bodies")
	assert_eq(people_view.shown_count(), session.people.size() - 1)
	person.sim_tier = 3
	people_view.refresh(0.016)
	assert_not_null(people_view.view_of(person.id))


func test_a_crowd_is_cheap_to_keep_up_with() -> void:
	# 60 people in sight (the M4 target is 20; this is headroom).
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	while session.people.size() < 60:
		var p := PersonData.new()
		p.id = session.ids.next_id()
		p.birth_tick = -rng.randi_range(2, 60) * YEAR
		p.position = session.start.settlement_tile + Vector2i(rng.randi_range(-6, 6), rng.randi_range(-6, 6))
		p.appearance = {"cloth": rng.randi_range(0, 5), "skin": rng.randi_range(0, 5), "hair": rng.randi_range(0, 4)}
		session.people.add(p)
	_look_at(_home(), 40.0)
	assert_eq(people_view.shown_count(), 60)
	var started := Time.get_ticks_usec()
	for i in 200:
		people_view.refresh(1.0 / 60.0)
	var per_frame_ms := (Time.get_ticks_usec() - started) / 200.0 / 1000.0
	print("    people view: %.3f ms per frame for 60 bodies" % per_frame_ms)
	assert_true(per_frame_ms < 1.5, "%.3f ms per frame" % per_frame_ms)
	# More people than views: the rest wait their turn, nothing breaks.
	while session.people.size() < PeopleView.MAX_VIEWS + 10:
		var p := PersonData.new()
		p.id = session.ids.next_id()
		p.position = session.start.settlement_tile
		session.people.add(p)
	people_view.refresh(0.016)
	assert_eq(people_view.shown_count(), PeopleView.MAX_VIEWS)
	rig.frame_box(false)
	for i in 90:
		rig.advance(1.0 / 60.0)
	people_view.refresh(0.0)
	assert_eq(people_view.marker_count(), session.people.size(), "but every one of them has a marker")


func test_what_people_are_busy_with_shows() -> void:
	_look_at(_home(), 24.0)
	var person := _with(&"woodcutter")
	var shown := people_view.view_of(person.id)
	assert_eq(shown.busy(), 0.0, "standing about")
	person.pose = PersonData.Pose.WORK
	people_view.refresh(0.016)
	assert_eq(shown.busy(), 1.0, "hard at work")
	assert_eq(float(shown.body_color(&"busy")), 1.0, "and the shader knows")
	person.pose = PersonData.Pose.EAT
	people_view.refresh(0.016)
	assert_true(shown.busy() > 0.0 and shown.busy() < 1.0, "eating is gentler")
	person.pose = PersonData.Pose.TALK
	people_view.refresh(0.016)
	assert_true(shown.busy() > 0.0 and shown.busy() < 0.45, "talking gentler still")
	person.pose = PersonData.Pose.IDLE
	people_view.refresh(0.016)
	assert_eq(shown.busy(), 0.0)
	# A view handed to someone else shows what they are doing, not the last one.
	person.pose = PersonData.Pose.WORK
	people_view.refresh(0.016)
	_look_at(_home() + Vector2(-30.0, 25.0), 9.0)
	person.pose = PersonData.Pose.IDLE
	_look_at(_home(), 24.0)
	assert_eq(people_view.view_of(person.id).busy(), 0.0)


func test_someone_indoors_is_not_seen() -> void:
	_look_at(_home(), 24.0)
	var person := _with(&"forager")
	assert_not_null(people_view.view_of(person.id))
	person.set_flag(PersonData.FLAG_INDOORS, true) # asleep in their hut
	people_view.refresh(0.016)
	assert_null(people_view.view_of(person.id), "no body")
	assert_eq(people_view.shown_count(), session.people.size() - 1)
	rig.frame_box(false)
	for i in 90:
		rig.advance(1.0 / 60.0)
	people_view.refresh(0.0)
	assert_eq(people_view.marker_count(), session.people.size() - 1, "and no marker")
	person.set_flag(PersonData.FLAG_INDOORS, false)
	people_view.refresh(0.0)
	assert_eq(people_view.marker_count(), session.people.size(), "up again: there again")
	_look_at(_home(), 24.0)
	assert_not_null(people_view.view_of(person.id))


func test_another_world_shows_other_people() -> void:
	_look_at(_home(), 24.0)
	assert_true(people_view.shown_count() > 0)
	view.clear()
	assert_eq(people_view.shown_count(), 0)
	assert_eq(people_view.marker_count(), 0)
	people_view.refresh(0.016) # nothing to show, nothing to crash on
	session.create_new(777)
	view.show_world(session.world, session.props, session.start, session.loose)
	view.show_people(session.people, session.clock, session.occupations)
	_look_at(_home(), 24.0)
	assert_eq(people_view.shown_count(), session.people.size())
	for p in session.people.all_people():
		assert_eq(people_view.view_of(p.id).person_id, p.id)


func test_reduced_motion_calms_the_bodies() -> void:
	var material := people_view.body_material()
	people_view.reduced_motion = true
	assert_true(float(material.get_shader_parameter(&"motion")) < 0.5)
	people_view.reduced_motion = false
	assert_eq(float(material.get_shader_parameter(&"motion")), 1.0)
	# The world's cloud shadows fall on people as on everything else.
	assert_near(float(material.get_shader_parameter(&"cloud_strength")), Config.terrain_palette.cloud_shadow_strength)


func test_people_cannot_be_picked_yet() -> void:
	# Touching people is M5: until then a finger on a person touches the ground.
	_look_at(_home(), 12.0)
	var person := _with(&"woodcutter")
	var at := people_view.ground_position(person) + Vector3(0, PersonMeshLibrary.ADULT_HEIGHT * 0.5, 0)
	var result := view.pick(rig.world_to_screen(at), 24.0)
	assert_true(result.is_hit())
	assert_ne(result.entity_id, person.id)


func test_the_marker_texture_is_a_rimmed_disc() -> void:
	var image := PeopleView.marker_texture(32).get_image()
	assert_eq(image.get_pixel(0, 0).a, 0.0, "clear in the corners")
	assert_near(image.get_pixel(16, 16).r, 1.0, 0.01, "bright in the middle (takes the cloth colour)")
	assert_near(image.get_pixel(16, 16).a, 1.0, 0.01)
	var rim := image.get_pixel(16, 2)
	assert_true(rim.a > 0.9 and rim.r < 0.3, "dark at the rim")


func test_the_running_game_draws_its_people() -> void:
	view.queue_free()
	session.queue_free()
	await wait_frames(1)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults() # (with reduced motion the game opens at home, not on the box)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(6)
	var main := get_tree().current_scene
	var game_session: WorldSession = main.get_node("WorldSession")
	var game_view: WorldView = main.get_node("WorldView")
	var game_rig := game_view.camera_rig()
	# The game opens on the whole box: everyone who is up is a marker.
	game_session.behavior.enabled = false
	var up := 0
	for p in game_session.people.all_people():
		if not p.has_flag(PersonData.FLAG_INDOORS):
			up += 1
	await wait_frames(1)
	assert_true(up >= game_session.people.size() - 2, "(a late riser may still be in bed at six)")
	assert_eq(game_view.people_view().marker_count(), up)
	var home := Vector2(game_session.start.settlement_tile) + Vector2(0.5, 0.5)
	game_rig.set_process(false)
	game_rig.focus_on(Vector3(home.x, 0, home.y), 24.0, false)
	for i in 90:
		game_rig.advance(1.0 / 60.0)
	await wait_frames(3)
	assert_eq(game_view.people_view().shown_count(), up, "at home, everyone is there")
	assert_eq(game_view.people_view().marker_count(), 0)
	get_tree().unload_current_scene()
	await wait_frames(2)
	# (after_each frees what is already gone)
	session = SessionScript.new()
	add_child(session)
	view = ViewScript.new()
	add_child(view)
