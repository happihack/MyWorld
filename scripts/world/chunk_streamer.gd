class_name ChunkStreamer
extends RefCounted
## Chunk streaming (M13.1, bible §31.7): only the chunks the camera sees — the
## ground under the screen, and a margin — have views. A view that goes far
## out of sight is released to a pool; a chunk that comes into sight gets one,
## its meshes built on a worker thread (WorkerThreadPool) from copies of the
## chunks it reads, and made into ArrayMeshes on the main thread, a few at a
## time (`APPLY_BUDGET_USEC` a frame).
##
## The first fill (fill) is built at once, on the main thread, as before; so
## are rebuilds of views already shown (WorldView.refresh_dirty_*). A worker's
## meshes are dropped for any layer rebuilt in the meantime (ChunkView.versions).
##
## Chunk data is not evicted here: the soil's passes touch every chunk within
## a game day (all chunks of a 256-tile world are modified by its first
## evening), a chunk's data is ~4 KB, and an evicted chunk would be generated
## again by the next pass (~6 ms each). WorldData.unload_chunk drops a pristine
## chunk, which comes back identical.

## Views are made this many tiles beyond what is seen…
const MARGIN_TILES := 6.0
## …and released only this far beyond it (no flicker as the view moves about).
const KEEP_TILES := 20.0
## Released views kept for reuse.
const POOL_MOST := 32
## Main-thread time a frame for making meshes of finished builds (at least one is made).
const APPLY_BUDGET_USEC := 4000

## One chunk built on a worker: everything it reads is its own.
class Job:
	extends RefCounted
	var coord: Vector2i
	var view: ChunkView
	var versions: PackedInt32Array
	var world: WorldData
	var placed: Array
	var taken: PackedByteArray
	var tuft: PropMeshLibrary.Template
	var palette: TerrainPalette
	var deep: float
	var task_id := -1
	var terrain: TerrainMesher.Buffers
	var water: WaterMesher.Buffers
	var props: PropMesher.Buffers

	func run() -> void:
		terrain = TerrainMesher.build_buffers(world, coord, palette, world.height_step)
		water = WaterMesher.build_buffers(world, coord, deep)
		props = PropMesher.build_from(world, coord, placed, taken, tuft)


## coord -> ChunkView (the WorldView's own dictionary).
var views: Dictionary = {}
## How many views have been made from a worker's meshes (since bind).
var streamed := 0
## How many views were released out of sight (since bind).
var released := 0

var _parent: Node3D
var _world: WorldData
var _props: PropRegistry
var _library: PropMeshLibrary
var _terrain_material: Material
var _water_material: Material
var _prop_material: Material
var _box_top := 8.0
var _pool: Array[ChunkView] = []
var _jobs: Array[Job] = []
## Chunks wanted but without a view yet, nearest first.
var _missing: Array[Vector2i] = []
var _wanted := Rect2i()
var _keep := Rect2i()
var _most_jobs := 2


func bind(parent: Node3D, chunk_views: Dictionary, world: WorldData, props: PropRegistry, library: PropMeshLibrary,
		terrain_material: Material, water_material: Material, prop_material: Material, box_top: float) -> void:
	unbind()
	_parent = parent
	views = chunk_views
	_world = world
	_props = props
	_library = library
	_terrain_material = terrain_material
	_water_material = water_material
	_prop_material = prop_material
	_box_top = box_top
	_most_jobs = clampi(OS.get_processor_count() - 1, 1, 4)
	_wanted = Rect2i()
	_keep = Rect2i()
	streamed = 0
	released = 0


## Waits for builds under way and forgets the pool (views in `views` are the
## caller's to free).
func unbind() -> void:
	stop()
	for view in _pool:
		view.queue_free()
	_pool.clear()
	_world = null
	_props = null


## Waits for the builds under way, and starts no more.
func stop() -> void:
	for job in _jobs:
		if job.task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(job.task_id)
		if is_instance_valid(job.view) and job.view.job == job:
			job.view.job = null
	_jobs.clear()
	_missing.clear()


## Builds a view for every chunk in `chunks` (chunk coordinates) at once.
func fill(chunks: Rect2i) -> void:
	for y in range(chunks.position.y, chunks.end.y):
		for x in range(chunks.position.x, chunks.end.x):
			var coord := Vector2i(x, y)
			if views.has(coord) or not _world.is_chunk_in_bounds(coord):
				continue
			var view := _take_view()
			view.setup(_world, coord, _terrain_material, _water_material)
			if _props != null:
				view.rebuild_props(_world, _props, _library, _prop_material)
			views[coord] = view
	_wanted = chunks
	_keep = chunks


## The chunks (chunk coordinates, within the world) whose ground is on the
## screen, grown by `margin` tiles. The whole world when the screen's corners
## do not all come down on the ground.
func visible_chunks(rig: CameraRig, margin: float = MARGIN_TILES) -> Rect2i:
	var all := WorldCoords.chunks_in_rect(_world.bounds, _world.chunk_size)
	var size := rig.view_size()
	var corners: Array[Vector2] = [Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y),
		Vector2(size.x * 0.5, 0.0), Vector2(size.x * 0.5, size.y)]
	var lowest := INF
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner in corners:
		var ray := rig.screen_ray(corner)
		var origin: Vector3 = ray[0]
		var dir: Vector3 = ray[1]
		lowest = minf(lowest, origin.y)
		if dir.y >= -0.0001:
			return all # (looking at the horizon: everything may be seen)
		# The ground lies between the floor of the box and its highest ground.
		for plane_y in [0.0, minf(_box_top, origin.y - 0.01)]:
			var at: Vector3 = origin + dir * ((float(plane_y) - origin.y) / dir.y)
			low = Vector2(minf(low.x, at.x), minf(low.y, at.z))
			high = Vector2(maxf(high.x, at.x), maxf(high.y, at.z))
	if not (is_finite(low.x) and is_finite(low.y) and is_finite(high.x) and is_finite(high.y)):
		return all
	var tiles := Rect2i(Vector2i(floori(low.x - margin), floori(low.y - margin)),
		Vector2i(ceili(high.x - low.x + margin * 2.0) + 1, ceili(high.y - low.y + margin * 2.0) + 1))
	return WorldCoords.chunks_in_rect(tiles, _world.chunk_size).intersection(all)


## Once a frame: views for what came into sight (built on workers), views
## released far out of sight, and the meshes of finished builds made.
func update(rig: CameraRig) -> void:
	if _world == null:
		return
	var wanted := visible_chunks(rig)
	if wanted != _wanted:
		_wanted = wanted
		_keep = visible_chunks(rig, KEEP_TILES)
		_release_outside(_keep)
		_list_missing(rig)
	_start_jobs()
	apply_finished(APPLY_BUDGET_USEC)


## Builds under way or waiting to start.
func pending() -> int:
	return _jobs.size() + _missing.size()


## Waits for every build to finish and makes all their meshes (tests, loading).
func finish_all() -> void:
	while not _missing.is_empty() or not _jobs.is_empty():
		_start_jobs()
		for job in _jobs:
			if job.task_id >= 0:
				WorkerThreadPool.wait_for_task_completion(job.task_id)
				job.task_id = -1
		apply_finished(-1)


## Makes the meshes of finished builds, for at most `budget_usec` (−1: all).
## Returns how many views got theirs.
func apply_finished(budget_usec: int) -> int:
	var started := Time.get_ticks_usec()
	var made := 0
	var i := 0
	while i < _jobs.size():
		var job := _jobs[i]
		if job.task_id >= 0:
			if not WorkerThreadPool.is_task_completed(job.task_id):
				i += 1
				continue
			WorkerThreadPool.wait_for_task_completion(job.task_id)
		_jobs.remove_at(i)
		if not is_instance_valid(job.view) or job.view.job != job:
			continue # released (or freed, the pool being full) meanwhile
		var view := job.view
		view.job = null
		# (A layer rebuilt here in the meantime is newer than the worker's.)
		if view.versions[0] == job.versions[0]:
			view.set_terrain_mesh(TerrainMesher.mesh_from(job.terrain))
		if view.versions[1] == job.versions[1]:
			view.set_water_mesh(WaterMesher.mesh_from(job.water))
		if view.versions[2] == job.versions[2]:
			view.set_props_mesh(PropMesher.mesh_from(job.props), _prop_material)
		streamed += 1
		made += 1
		if budget_usec >= 0 and Time.get_ticks_usec() - started >= budget_usec:
			break
	return made


func _release_outside(keep: Rect2i) -> void:
	var gone: Array[Vector2i] = []
	for coord: Vector2i in views:
		if not keep.has_point(coord):
			gone.append(coord)
	for coord in gone:
		var view: ChunkView = views[coord]
		views.erase(coord)
		view.release()
		released += 1
		if _pool.size() < POOL_MOST:
			_pool.append(view)
		else:
			view.queue_free()


func _list_missing(rig: CameraRig) -> void:
	_missing.clear()
	for y in range(_wanted.position.y, _wanted.end.y):
		for x in range(_wanted.position.x, _wanted.end.x):
			var coord := Vector2i(x, y)
			if not views.has(coord) and _world.is_chunk_in_bounds(coord):
				_missing.append(coord)
	# Nearest to where the camera looks first.
	var at := rig.pivot()
	var centre := Vector2(at.x, at.z) / float(_world.chunk_size)
	_missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (Vector2(a) + Vector2(0.5, 0.5)).distance_squared_to(centre) \
			< (Vector2(b) + Vector2(0.5, 0.5)).distance_squared_to(centre))


func _start_jobs() -> void:
	while _jobs.size() < _most_jobs and not _missing.is_empty():
		var coord: Vector2i = _missing.pop_front()
		if views.has(coord):
			continue
		var view := _take_view()
		view.place(_world, coord, _terrain_material, _water_material)
		views[coord] = view
		var job := Job.new()
		job.coord = coord
		job.view = view
		job.world = _world.snapshot_around(coord)
		if _props != null:
			job.placed = PropMesher.placements(_world, _props, coord, _library)
			job.taken = PropMesher.taken_tiles(_world, _props, coord)
			job.tuft = _library.grass_tuft()
		else:
			job.taken = PackedByteArray()
			job.taken.resize(_world.chunk_size * _world.chunk_size)
		job.palette = Config.terrain_palette
		job.deep = Config.terrain_palette.water_deep_levels * _world.height_step
		# What the copies hold is what will be drawn: later changes mark the chunk again.
		var chunk := _world.get_chunk(coord, false)
		if chunk != null:
			chunk.clear_dirty(ChunkData.DIRTY_MESH | ChunkData.DIRTY_WATER)
		view.job = job
		job.versions = view.versions.duplicate()
		job.task_id = WorkerThreadPool.add_task(job.run, false, "Chunk mesh")
		_jobs.append(job)


func _take_view() -> ChunkView:
	var view: ChunkView = _pool.pop_back() if not _pool.is_empty() else null
	if view == null:
		view = ChunkView.new()
		_parent.add_child(view)
	return view
