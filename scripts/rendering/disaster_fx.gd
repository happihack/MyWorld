class_name DisasterFx
extends Node3D
## What the disasters look and sound like (DisasterSystem): the ground
## jolting under a quake, the day going dark, a whirlwind crossing the land,
## the waters turned red, stars streaking down and striking.

## How long before a star strikes it is seen falling (real seconds).
const FALL_SECONDS := 0.6
## How high above the ground it is first seen, and how far to the side.
const FALL_HEIGHT := 22.0
const FALL_SIDE := 9.0
const STAR_COLOR := Color(1.0, 0.62, 0.22)
const DUST := Color(0.58, 0.50, 0.40)
const FUNNEL_COLOR := Color(0.30, 0.27, 0.24, 0.78)
const FUNNEL_HEIGHT := 6.0
## How often the quake jolts the view, and the dust it raises (real seconds).
const JOLT_EVERY := 0.28
const DUST_EVERY := 0.18

var reduced_motion := false

var _rig: CameraRig
var _day_night: DayNight
var _water: ShaderMaterial
var _effects: WorldEffects
var _disasters: DisasterSystem
var _clock: GameClock
var _world: WorldData
var _funnel: Node3D
var _jolt := 0.0
var _dust := 0.0
var _rng := RandomNumberGenerator.new()
## Stars already shown falling: their tick and place ("tick:x:y" -> true).
var _falling: Dictionary = {}


func setup(rig: CameraRig, day_night: DayNight, water: ShaderMaterial, effects: WorldEffects) -> void:
	name = "DisasterFx"
	_rig = rig
	_day_night = day_night
	_water = water
	_effects = effects
	_funnel = _make_funnel()
	_funnel.visible = false
	add_child(_funnel)


func bind(disasters: DisasterSystem, clock: GameClock, world: WorldData) -> void:
	if _disasters != null and _disasters.struck.is_connected(_on_struck):
		_disasters.struck.disconnect(_on_struck)
		_disasters.started.disconnect(_on_started)
	_disasters = disasters
	_clock = clock
	_world = world
	_falling.clear()
	if disasters != null:
		disasters.struck.connect(_on_struck)
		disasters.started.connect(_on_started)


func _process(delta: float) -> void:
	if _disasters == null or _clock == null:
		return
	var now := _clock.tick
	if _day_night != null:
		_day_night.set_eclipse(_disasters.eclipse_amount(now))
	if _water != null:
		_water.set_shader_parameter(&"blood", _disasters.blood_amount(now))
	match _disasters.kind:
		DisasterSystem.EARTHQUAKE:
			_shake(delta)
		DisasterSystem.METEORS:
			_show_falling()
	_show_funnel(delta, now)


# --- the quake ---------------------------------------------------------------------------------

func _on_started(kind: StringName, at: Vector2) -> void:
	match kind:
		DisasterSystem.EARTHQUAKE:
			AudioManager.play_at(&"thunder", _ground(at), 2.0, 0.45, false)
			Haptics.pulse(Haptics.Strength.STRONG)
		DisasterSystem.TORNADO:
			AudioManager.play_at(&"gust", _ground(at), 0.0, 0.6, false)
		DisasterSystem.ECLIPSE, DisasterSystem.BLOOD:
			AudioManager.play_at(&"hum", _ground(at), -6.0, 0.5, false)


func _shake(delta: float) -> void:
	_jolt -= delta
	if _jolt <= 0.0:
		_jolt = JOLT_EVERY
		if _rig != null and not reduced_motion:
			_rig.bump(_rng.randf_range(0.6, 1.0))
	_dust -= delta
	if _dust <= 0.0 and _effects != null:
		_dust = DUST_EVERY
		var at := _disasters.at + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * DisasterSystem.QUAKE_REACH
		_effects.burst(WorldEffects.Burst.DUST, _ground(at), DUST)


# --- the whirlwind -----------------------------------------------------------------------------

func _show_funnel(delta: float, now: int) -> void:
	var on := _disasters.kind == DisasterSystem.TORNADO
	_funnel.visible = on
	if not on:
		return
	# (Between game minutes it moves on smoothly.)
	var share := _clock.minute_fraction()
	var from := _disasters.tornado_at(now)
	var to := _disasters.tornado_at(now + 1)
	_funnel.position = _ground(from.lerp(to, share))
	_funnel.rotate_y(delta * 7.0)
	for i in _funnel.get_child_count():
		var ring := _funnel.get_child(i) as Node3D
		ring.position.x = sin(Time.get_ticks_msec() * 0.004 + i) * 0.12 * i
	_dust -= delta
	if _dust <= 0.0 and _effects != null:
		_dust = DUST_EVERY
		_effects.burst(WorldEffects.Burst.DUST, _funnel.position, DUST)
		_effects.burst(WorldEffects.Burst.LEAVES, _funnel.position + Vector3(0.0, 0.6, 0.0), Color(0.36, 0.5, 0.24))


func _make_funnel() -> Node3D:
	var funnel := Node3D.new()
	funnel.name = "Funnel"
	var material := StandardMaterial3D.new()
	material.albedo_color = FUNNEL_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rings := 6
	for i in rings:
		var piece := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		var low := float(i) / rings
		var high := float(i + 1) / rings
		mesh.bottom_radius = lerpf(0.18, 1.7, low * low)
		mesh.top_radius = lerpf(0.18, 1.7, high * high)
		mesh.height = FUNNEL_HEIGHT / rings
		mesh.radial_segments = 14
		mesh.rings = 1
		mesh.cap_top = false
		mesh.cap_bottom = false
		mesh.material = material
		piece.mesh = mesh
		piece.position.y = (i + 0.5) * FUNNEL_HEIGHT / rings
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		funnel.add_child(piece)
	return funnel


# --- the falling stars -------------------------------------------------------------------------

func _show_falling() -> void:
	var minute := maxf(Config.time.real_seconds_per_game_minute / maxf(_clock.speed_multiplier(), 0.01), 0.01)
	for star: Array in _disasters.stars_to_come():
		var key := "%d:%.2f:%.2f" % [int(star[0]), float(star[1]), float(star[2])]
		if _falling.has(key):
			continue
		# Seen falling for a moment before it strikes (at the speed the world goes).
		if float(int(star[0]) - _clock.tick) * minute > FALL_SECONDS:
			continue
		_falling[key] = true
		_fall_streak(_ground(Vector2(float(star[1]), float(star[2]))))


func _fall_streak(to: Vector3) -> void:
	var streak := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.03
	mesh.bottom_radius = 0.22
	mesh.height = 3.0
	mesh.radial_segments = 8
	var material := StandardMaterial3D.new()
	material.albedo_color = STAR_COLOR
	material.emission_enabled = true
	material.emission = STAR_COLOR
	material.emission_energy_multiplier = 3.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	streak.mesh = mesh
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var side := Vector3.FORWARD.rotated(Vector3.UP, _rng.randf() * TAU) * FALL_SIDE
	var from := to + Vector3(side.x, FALL_HEIGHT, side.z)
	add_child(streak)
	streak.position = from
	# Pointing the way it falls (its tail up behind it).
	streak.look_at_from_position(from, to, Vector3.UP if absf((to - from).normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT)
	streak.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
	var tween := streak.create_tween()
	tween.tween_property(streak, "position", to, FALL_SECONDS).set_ease(Tween.EASE_IN)
	tween.tween_callback(streak.queue_free)


func _on_struck(kind: StringName, at: Vector2, size: float) -> void:
	var ground := _ground(at)
	match kind:
		DisasterSystem.METEORS:
			if _effects != null:
				_effects.ring(ground, 3.2, 1.2, STAR_COLOR)
				_effects.burst(WorldEffects.Burst.SPARKS, ground + Vector3(0.0, 0.2, 0.0), STAR_COLOR)
				_effects.burst(WorldEffects.Burst.DUST, ground, DUST.darkened(0.4))
			AudioManager.play_at(&"thunder_2", ground, 0.0, 1.4, false)
			AudioManager.play_at(&"thud", ground, 2.0, 0.55, false)
			if _rig != null and not reduced_motion:
				_rig.bump(size)
			Haptics.pulse(Haptics.Strength.MEDIUM)
		DisasterSystem.EARTHQUAKE:
			if _effects != null:
				_effects.ring(ground, DisasterSystem.QUAKE_REACH, 2.0, DUST)


func _ground(at: Vector2) -> Vector3:
	if _world == null:
		return Vector3(at.x, 0.0, at.y)
	var tile := WorldCoords.world2d_to_tile(at)
	return Vector3(at.x, _world.get_height(tile) * _world.height_step + _world.get_water(tile), at.y)
