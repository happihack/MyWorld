class_name BoatsView
extends Node3D
## Draws the boats (FB2): each its own mesh, moved when its boat moves; a
## drifting or beached boat sits a little askew. There are few boats — a
## handful a landing — so one MeshInstance3D apiece is cheap. Views are
## disposable: all state lives in the BoatSystem.

## A boat bobs this much on the water (world units) and this fast.
const BOB := 0.012
const BOB_SPEED := 1.7
## Boats are drawn this much larger than the landing's picture of one was:
## big enough to hold a person (0.5 tall) — on the phone the kneeling fisher
## hid the canoe entirely (2026-10-07).
const SIZE := 1.7
## Gliding after the boat as the simulation moves it: catching up within
## about this long; further off than SNAP_DISTANCE, straight there.
const FOLLOW_SECONDS := 0.55
const SNAP_DISTANCE := 3.0
const TURN_RATE := 4.0
## Where the crew sit: this far apart along the boat, this high above the
## water line (their folded legs in the hull: PersonData.Pose.SEATED).
const CREW_SPACING := 0.3
const SEAT_Y := 0.01
## Gliding faster than this (units a second), the paddle is going.
const PADDLING_SPEED := 0.05
## A boat aground leans this much (radians).
const AGROUND_LEAN := 0.22

var _world: WorldData
var _boats: BoatSystem
var _material: Material
var _meshes: Dictionary = {} # kind -> ArrayMesh
var _shown: Dictionary = {} # boat id -> MeshInstance3D
var _time := 0.0
var _glide: Dictionary = {} # boat id -> [shown position (XZ in x, z), velocity, shown heading]


func setup(material: Material) -> void:
	_material = material


func show_boats(world: WorldData, boats: BoatSystem) -> void:
	clear()
	_world = world
	_boats = boats
	if boats == null:
		return
	boats.boat_added.connect(_on_added)
	boats.boat_removed.connect(_on_removed)
	boats.boat_moved.connect(_on_moved)
	for boat in boats.all_boats():
		_on_added(boat)


func clear() -> void:
	if _boats != null:
		_boats.boat_added.disconnect(_on_added)
		_boats.boat_removed.disconnect(_on_removed)
		_boats.boat_moved.disconnect(_on_moved)
	for instance: MeshInstance3D in _shown.values():
		instance.queue_free()
	_shown.clear()
	_glide.clear()
	_boats = null
	_world = null


func boat_count() -> int:
	return _shown.size()


func is_shown(id: int) -> bool:
	return _shown.has(id)


func boat_transform(id: int) -> Transform3D:
	var instance: MeshInstance3D = _shown.get(id)
	return instance.transform if instance != null else Transform3D.IDENTITY


## The ground moved (or the water rose): seat every boat again.
func reseat() -> void:
	for id: int in _shown:
		_place(id, 0.0) # (where it is drawn: only the height anew)


func _process(delta: float) -> void:
	if _boats == null or _shown.is_empty():
		return
	_time += delta
	for id: int in _shown:
		_place(id, delta) # (gliding; bobbing; rising and falling with the river)


## Where someone aboard sits, as the boat is drawn now: [feet (Vector3),
## facing (radians, as PersonData.facing), paddling (bool)] — null if their
## boat is not drawn.
func seat_for(person: PersonData) -> Variant:
	var instance: MeshInstance3D = _shown.get(person.aboard)
	var boat := _boats.get_boat(person.aboard) if _boats != null else null
	var glide: Array = _glide.get(person.aboard, [])
	if instance == null or boat == null or glide.is_empty():
		return null
	var heading: float = glide[2]
	var along := Vector3(sin(heading), 0.0, cos(heading))
	var seat := maxi(boat.crew.find(person.id), 0)
	var offset := (float(seat) - (boat.crew.size() - 1) * 0.5) * CREW_SPACING
	var at := instance.transform.origin + along * offset + Vector3(0.0, SEAT_Y, 0.0)
	return [at, atan2(along.z, along.x), (glide[1] as Vector3).length() > PADDLING_SPEED]


static func transform_for(boat: BoatData, world: WorldData, time: float) -> Transform3D:
	var tile := boat.tile()
	var ground := world.get_height(tile) * world.height_step if world.is_in_bounds(tile) else 0.0
	var basis := Basis(Vector3.UP, boat.heading).scaled(Vector3.ONE * SIZE)
	# (On the water as it is now: a moored boat rises with the river and comes
	# to rest on the mud when it falls — not at the height it was tied up at.)
	var water := maxf(world.get_water(tile), 0.0) if world.is_in_bounds(tile) else 0.0
	var y := ground + (boat.height if boat.state == BoatData.State.AGROUND else water)
	if boat.state == BoatData.State.AGROUND:
		basis = basis * Basis(Vector3.FORWARD, AGROUND_LEAN)
	elif water > 0.0:
		y += sin(time * BOB_SPEED + boat.id * 1.3) * BOB
	return Transform3D(basis, Vector3(boat.position.x, y, boat.position.y))


func _on_added(boat: BoatData) -> void:
	if _shown.has(boat.id):
		_place(boat.id)
		return
	var instance := MeshInstance3D.new()
	instance.name = "Boat_%d" % boat.id
	instance.mesh = _mesh_for(boat.kind)
	instance.material_override = _material
	add_child(instance)
	_shown[boat.id] = instance
	_place(boat.id)


func _on_removed(id: int) -> void:
	var instance: MeshInstance3D = _shown.get(id)
	if instance != null:
		instance.queue_free()
	_shown.erase(id)
	_glide.erase(id)


func _on_moved(_id: int) -> void:
	pass # (followed each frame: see _place)


## Draws a boat where it is — gliding there from where it was drawn: the
## simulation moves a boat a game minute at a time (half a second at Normal
## speed), and seen like that it lurches (the owner, 2026-10-07). `delta` < 0:
## straight there (just shown, the ground moved).
func _place(id: int, delta: float = -1.0) -> void:
	var instance: MeshInstance3D = _shown.get(id)
	var boat := _boats.get_boat(id) if _boats != null else null
	if instance == null or boat == null or _world == null:
		return
	var target := transform_for(boat, _world, _time)
	var glide: Array = _glide.get(id, [])
	var goal := Vector3(boat.position.x, 0.0, boat.position.y)
	if glide.is_empty() or delta < 0.0 or (glide[0] as Vector3).distance_to(goal) > SNAP_DISTANCE:
		glide = [goal, Vector3.ZERO, boat.heading]
	elif delta > 0.0:
		var moved := _smooth_damp(glide[0], goal, glide[1], delta)
		glide[0] = moved[0]
		glide[1] = moved[1]
		glide[2] = lerp_angle(glide[2], boat.heading, 1.0 - exp(-TURN_RATE * delta))
	_glide[id] = glide
	var at: Vector3 = glide[0]
	var basis := Basis(Vector3.UP, glide[2]).scaled(Vector3.ONE * SIZE)
	if boat.state == BoatData.State.AGROUND:
		basis = basis * Basis(Vector3.FORWARD, AGROUND_LEAN)
	instance.transform = Transform3D(basis, Vector3(at.x, target.origin.y, at.z))


## Critically damped approach (no overshoot): [position, velocity].
static func _smooth_damp(from: Vector3, to: Vector3, velocity: Vector3, delta: float) -> Array:
	var omega := 2.0 / FOLLOW_SECONDS
	var x := omega * delta
	var decay := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := from - to
	var temp := (velocity + change * omega) * delta
	return [to + (change + temp) * decay, (velocity - temp * omega) * decay]


func _mesh_for(kind: int) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var template := PropMeshLibrary.boat_template(kind)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = template.vertices
	arrays[Mesh.ARRAY_NORMAL] = template.normals
	arrays[Mesh.ARRAY_COLOR] = template.colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes[kind] = mesh
	return mesh
