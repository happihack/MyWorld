class_name Benchmark
extends Node
## The on-device benchmark (M21.1): the camera goes a fixed way over the world
## — the whole box, down to the fire, round it, across at middle height —
## while every frame is measured: how long it really took (the screen's own
## rhythm, not the work alone), the draw calls and objects. A line
## for each part and one for all of it go to `user://benchmark.txt` (newest
## last; `adb exec-out run-as <package> cat files/benchmark.txt`) and to the
## log; the camera goes back to where it was. Nothing in the world is changed.
## (Debug builds: Settings → Debug → Run benchmark.)

signal finished(summary: String)

## The parts of the way: [name, seconds].
const STAGES: Array = [["box", 12.0], ["fire", 12.0], ["around", 15.0], ["across", 15.0]]
const FILE := "user://benchmark.txt"

## Every part this much shorter or longer (tests run it quickly).
var time_scale := 1.0
## Where the summary is written (tests write elsewhere).
var file_path := FILE

var _session: WorldSession
var _rig: CameraRig
var _stage := -1
var _stage_time := 0.0
var _was_pivot := Vector3.ZERO
var _was_distance := 0.0
var _frames := {} # stage name -> PackedFloat32Array of frame ms
var _draws := {} # stage name -> PackedInt32Array
var _objects := {} # stage name -> PackedInt32Array
var _last_usec := 0


func start(session: WorldSession, rig: CameraRig) -> void:
	_session = session
	_rig = rig
	_was_pivot = rig.pivot()
	_was_distance = rig.distance()
	for entry: Array in STAGES:
		_frames[entry[0]] = PackedFloat32Array()
		_draws[entry[0]] = PackedInt32Array()
		_objects[entry[0]] = PackedInt32Array()
	_next_stage()
	_last_usec = Time.get_ticks_usec()


func is_running() -> bool:
	return _stage >= 0 and _stage < STAGES.size()


func _process(delta: float) -> void:
	if not is_running():
		return
	var now := Time.get_ticks_usec()
	var name: String = STAGES[_stage][0]
	# (The first frames of a part are the camera setting out: not counted.)
	if _stage_time > 0.5 * time_scale:
		_note(_frames, name, (now - _last_usec) / 1000.0)
		_note_int(_draws, name, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		_note_int(_objects, name, int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
	_last_usec = now
	_stage_time += delta
	if name == "around":
		_rig.rotate_at(delta * 0.5, _rig.view_size() * 0.5)
	elif name == "across":
		_rig.pan_world(Vector2(delta * 4.0, delta * 1.5))
	if _stage_time >= float(STAGES[_stage][1]) * time_scale:
		_next_stage()


func _next_stage() -> void:
	_stage += 1
	_stage_time = 0.0
	if _stage >= STAGES.size():
		_finish()
		return
	var name: String = STAGES[_stage][0]
	var fire := _fire_point()
	match name:
		"box":
			_rig.frame_box(true)
		"fire", "around":
			_rig.focus_on(fire, 14.0, true)
		"across":
			_rig.focus_on(fire, 40.0, true)


func _fire_point() -> Vector3:
	var own := _session.settlement if _session != null else null
	var fire := own.fire() if own != null else null
	if fire == null:
		return _rig.pivot()
	var world := _session.world
	return Vector3(fire.tile.x + 0.5, world.get_height(fire.tile) * world.height_step, fire.tile.y + 0.5)


func _finish() -> void:
	_rig.focus_on(_was_pivot, _was_distance, true)
	var lines := PackedStringArray()
	var header := "benchmark %s  %s  people %d  box %d²  speed ×%s  %s" % [Time.get_datetime_string_from_system(),
		OS.get_model_name(), _session.people.size(), _session.world.bounds.size.x,
		str(_session.clock.speed_multiplier()), RenderingServer.get_video_adapter_name()]
	lines.append(header)
	var all := PackedFloat32Array()
	for entry: Array in STAGES:
		var name: String = entry[0]
		all.append_array(_frames[name])
		lines.append("  %-7s %s  draws %d  objects %d" % [name, _describe(_frames[name]),
			roundi(_mean_int(_draws[name])), roundi(_mean_int(_objects[name]))])
	var summary := "  all     %s" % _describe(all)
	lines.append(summary)
	var text := "\n".join(lines)
	print(text)
	Log.info(Log.Category.PERFORMANCE, "Benchmark", {"result": text})
	var file := FileAccess.open(file_path, FileAccess.READ_WRITE if FileAccess.file_exists(file_path) else FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_string(text + "\n")
		file.close()
	_stage = STAGES.size()
	finished.emit(summary.strip_edges())
	queue_free()


## "52.1 FPS  frame 19.2 ms  p95 33.4  max 67.0  slow 12" (slow: over 34 ms).
static func _describe(frames: PackedFloat32Array) -> String:
	if frames.is_empty():
		return "no frames"
	var sorted := frames.duplicate()
	sorted.sort()
	var total := 0.0
	var slow := 0
	for ms in frames:
		total += ms
		if ms > 34.0:
			slow += 1
	var mean := total / frames.size()
	return "%.1f FPS  frame %.1f ms  p95 %.1f  max %.1f  slow %d" % [1000.0 / maxf(mean, 0.001), mean,
		sorted[int(sorted.size() * 0.95)], sorted[-1], slow]


static func _mean_int(values: PackedInt32Array) -> float:
	var total := 0
	for v in values:
		total += v
	return float(total) / values.size() if not values.is_empty() else 0.0


static func _note(store: Dictionary, name: String, value: float) -> void:
	var values: PackedFloat32Array = store[name]
	values.append(value)
	store[name] = values


static func _note_int(store: Dictionary, name: String, value: int) -> void:
	var values: PackedInt32Array = store[name]
	values.append(value)
	store[name] = values
