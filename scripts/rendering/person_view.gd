class_name PersonView
extends Node3D
## How one person is drawn (bible §13.1, §28.4): a body, something carried and
## a soft shadow. A view is a disposable stand-in — everything true about the
## person lives in PersonData; the view only follows it, smoothly.
##
## Views are pooled (EntityViewPool) and handed from person to person.

## The view catches up with where its person is within about this long.
const FOLLOW_SECONDS := 0.22
## Further away than this (world units), it jumps instead of gliding.
const SNAP_DISTANCE := 3.0
## Moving at this speed (units per second) is a full walk.
const WALK_SPEED := 0.9
## Below this speed the person is standing (and turns the way they face).
const STILL_SPEED := 0.08
const TURN_RATE := 9.0
const SHADOW_ALPHA := 0.26
const SHADOW_LIFT := 0.03
## A touch (VS.5): the body gives under it and springs back, this long.
const POKE_SECONDS := 0.5
## How far it gives (a share of its height) at a full touch.
const POKE_SQUASH := 0.2

## Whose view this is (0 = nobody's: in the pool).
var person_id := 0
var stage: PersonData.LifeStage = PersonData.LifeStage.ADULT
var age_years := -1
var accessory: StringName = &""
## In dyed cloth (PersonData.FLAG_DYED: their settlement weaves).
var dyed := false
## The colours of their culture (CultureSystem.palette_of): set before dressing.
var palette := 0
## 0 standing … 1 walking, as shown.
var walk := 0.0

var _body: MeshInstance3D
var _accessory: MeshInstance3D
var _shadow: MeshInstance3D
## What they have in their arms (a resource id; &"" = nothing shown).
var _load: MeshInstance3D
var _load_shown: StringName = &""

var _velocity := Vector3.ZERO
var _shown_walk := -1.0
var _shown_busy := -1.0
## How much each pose moves the arms (see person.gdshader "busy").
const BUSY := {
	PersonData.Pose.IDLE: 0.0, PersonData.Pose.WORK: 1.0, PersonData.Pose.EAT: 0.45,
	PersonData.Pose.TALK: 0.22, PersonData.Pose.SLEEP: 0.0,
}
## What each pose makes the body show (see person_motion.gdshaderinc "act").
const ACT := {
	PersonData.Pose.STARTLE: 1.0, PersonData.Pose.KNEEL: 2.0, PersonData.Pose.WAVE: 3.0, PersonData.Pose.JUMP: 4.0,
	PersonData.Pose.CROUCH: 5.0, PersonData.Pose.YELL: 6.0, PersonData.Pose.SHRUG: 7.0,
}
var _shown_act := -1.0
# Standing where the person stands, turned as they are turned: nothing to do
# until either changes (most people, most of the time).
var _at_rest := false
var _rest_target := Vector3.ZERO
var _rest_facing := 0.0
## The touch being shown: seconds left of it, and how strong it was.
var _poke := 0.0
var _poke_strength := 0.0


## Gives the view its shared materials (once, when it is created).
func setup(body_material: Material, accessory_material: Material, shadow_material: Material) -> void:
	_body = $Body
	_accessory = $Accessory
	_shadow = $Shadow
	_body.mesh = PersonMeshLibrary.body()
	_body.material_override = body_material
	_accessory.material_override = accessory_material
	_shadow.material_override = shadow_material
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_load = MeshInstance3D.new()
	_load.name = "Load"
	_load.material_override = accessory_material
	_load.visible = false
	add_child(_load)


## Makes this the view of `person`, standing at `at` (world position of the feet).
func bind(person: PersonData, now_tick: int, ticks_per_year: int, config: PeopleConfig,
		occupations: OccupationLibrary, at: Vector3) -> void:
	person_id = person.id
	_poke = 0.0
	_show_poke(0.0)
	dress(person, now_tick, ticks_per_year, config, occupations)
	_velocity = Vector3.ZERO
	_at_rest = false
	position = at
	rotation.y = -person.facing
	walk = 0.0
	_show_walk()
	set_pose(person.pose)
	visible = true


## Size, colours and what is carried — again whenever the person has changed
## (grown a year older, taken up other work).
func dress(person: PersonData, now_tick: int, ticks_per_year: int, config: PeopleConfig,
		occupations: OccupationLibrary) -> void:
	age_years = person.age_years(now_tick, ticks_per_year)
	stage = config.stage_for_age(age_years)
	var height := PersonMeshLibrary.ADULT_HEIGHT * PersonMeshLibrary.height_factor(age_years, config) \
		* float(person.appearance.get("height", 1.0))
	var width := height * PersonMeshLibrary.BUILD * float(person.appearance.get("build", 1.0))
	scale = Vector3(width, height, width)
	_shadow.position.y = SHADOW_LIFT / height # the same lift off the ground for everyone
	dyed = person.has_flag(PersonData.FLAG_DYED)
	_body.set_instance_shader_parameter(&"cloth_color", PersonMeshLibrary.cloth(int(person.appearance.get("cloth", 0)) + palette, dyed))
	_body.set_instance_shader_parameter(&"skin_color", PersonMeshLibrary.skin(int(person.appearance.get("skin", 0))))
	_body.set_instance_shader_parameter(&"hair_color", PersonMeshLibrary.hair(int(person.appearance.get("hair", 0)), stage))
	_body.set_instance_shader_parameter(&"stoop", PersonMeshLibrary.stoop_for(stage))
	# People do not breathe and step in unison.
	_body.set_instance_shader_parameter(&"phase", float((person.id * 2654435761) & 0xFFFF) / 65535.0 * TAU)
	var def := occupations.get_def(person.occupation_id) if occupations != null else null
	accessory = def.accessory if def != null else &""
	_accessory.mesh = PersonMeshLibrary.accessory(accessory)
	_accessory.visible = _accessory.mesh != null


## Shows what the person carries (a resource id; &"" = empty-handed).
func set_load(resource: StringName) -> void:
	if resource == _load_shown:
		return
	_load_shown = resource
	_load.mesh = PersonMeshLibrary.load_mesh(resource)
	_load.visible = _load.mesh != null


## What is shown in their arms (&"" = nothing).
func load_shown() -> StringName:
	return _load_shown


## Marks the person as the one the player has selected: an outline around
## the body (the ring under their feet is the PeopleView's).
func set_selected(selected: bool, plain: Material, outlined: Material) -> void:
	var wanted := outlined if selected else plain
	if _body.material_override != wanted:
		_body.material_override = wanted


func is_outlined(outlined: Material) -> bool:
	return _body.material_override == outlined


## Shows what the person is busy with.
func set_pose(pose: PersonData.Pose) -> void:
	var busy: float = BUSY.get(pose, 0.0)
	if busy != _shown_busy:
		_shown_busy = busy
		_body.set_instance_shader_parameter(&"busy", busy)
	var showing: float = ACT.get(pose, 0.0)
	if showing != _shown_act:
		_shown_act = showing
		_body.set_instance_shader_parameter(&"act", showing)


func busy() -> float:
	return _shown_busy


## What the body is showing (0 = nothing in particular).
func act() -> float:
	return _shown_act


## Back into the pool.
func unbind() -> void:
	person_id = 0
	visible = false


func is_bound() -> bool:
	return person_id != 0


## The person was touched: the body gives under it and springs back
## (`strength` 0 … 1).
func poke(strength: float = 1.0) -> void:
	_poke = POKE_SECONDS
	_poke_strength = clampf(strength, 0.0, 1.0)


## How much the body is squashed right now (0: not at all; below 0: stretched).
func squash() -> float:
	if _poke <= 0.0:
		return 0.0
	var t := 1.0 - _poke / POKE_SECONDS
	return sin(t * TAU * 1.5) * exp(-t * 3.5) * POKE_SQUASH * _poke_strength


func _show_poke(delta: float) -> void:
	_poke = maxf(_poke - delta, 0.0)
	var s := squash()
	var shape := Vector3(1.0 + s * 0.5, 1.0 - s, 1.0 + s * 0.5)
	_body.scale = shape
	_accessory.scale = shape
	_load.scale = shape


## Follows the person: glides to `target` (their feet) and turns to `facing`
## — or, while moving, the way it is going.
func advance(delta: float, target: Vector3, facing: float) -> void:
	if _poke > 0.0 and delta > 0.0:
		_show_poke(delta)
	if delta <= 0.0 or (_at_rest and target == _rest_target and facing == _rest_facing):
		return
	_at_rest = false
	var before := position
	if position.distance_to(target) > SNAP_DISTANCE:
		position = target
		_velocity = Vector3.ZERO
		before = target
	else:
		position = _smooth_damp(position, target, delta)
	var speed := Vector2(position.x - before.x, position.z - before.z).length() / delta
	var heading := facing
	if speed > STILL_SPEED:
		heading = Vector2(position.x - before.x, position.z - before.z).angle()
	rotation.y = lerp_angle(rotation.y, -heading, 1.0 - exp(-TURN_RATE * delta))
	walk = move_toward(walk, clampf(speed / WALK_SPEED, 0.0, 1.0), delta * 5.0)
	_show_walk()
	if walk == 0.0 and position.distance_squared_to(target) < 0.000001 and _velocity.length_squared() < 0.000001 			and absf(angle_difference(rotation.y, -facing)) < 0.002:
		position = target
		rotation.y = -facing
		_velocity = Vector3.ZERO
		_at_rest = true
		_rest_target = target
		_rest_facing = facing


func body_color(parameter: StringName) -> Variant:
	return _body.get_instance_shader_parameter(parameter)


func accessory_mesh() -> Mesh:
	return _accessory.mesh if _accessory.visible else null


func _show_walk() -> void:
	# Instance parameters are not free to set: only when the value has moved.
	if absf(walk - _shown_walk) > 0.02 or (walk == 0.0 and _shown_walk != 0.0):
		_shown_walk = walk
		_body.set_instance_shader_parameter(&"walk", walk)


## Critically damped approach (no overshoot), so that a person moved in steps
## by the simulation is seen walking evenly.
func _smooth_damp(from: Vector3, to: Vector3, delta: float) -> Vector3:
	var omega := 2.0 / FOLLOW_SECONDS
	var x := omega * delta
	var decay := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := from - to
	var temp := (_velocity + change * omega) * delta
	_velocity = (_velocity - temp * omega) * decay
	return to + (change + temp) * decay
