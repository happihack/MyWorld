extends Node
## Autoload "AudioManager": every sound the game makes (bible §29, track T7).
##
## - Buses: Master > Ambience / SFX / UI, with volumes from the player's settings.
## - World sounds play at a place in the world from a fixed pool of 3D voices:
##   close to the camera they are loud, far away quiet. UI sounds use their own
##   small pool and are not positioned.
## - When every voice is busy, the one that has played longest is reused.
## - Sounds come from res://assets/audio/sfx/<id>.wav (or .ogg); where no file
##   exists, a generated placeholder (SoundSynth) is used. Placeholders are made
##   on a worker thread at startup; until they are ready, play calls are silent.

signal sounds_ready

const BUS_MASTER := &"Master"
const BUS_AMBIENCE := &"Ambience"
const BUS_SFX := &"SFX"
const BUS_UI := &"UI"
const SFX_DIR := "res://assets/audio/sfx/"
const SFX_EXTENSIONS: PackedStringArray = ["wav", "ogg"]
const WIND := &"wind"
const CRICKETS := &"crickets"
const RAIN := &"rain"
## Below this share of night the crickets are silent.
const NIGHT_SILENT_BELOW := 0.02

## Counters for the debug overlay and tests.
var sounds_played := 0
var sounds_dropped := 0
## Id of the most recent sound that was actually started.
var last_sound: StringName = &""

var _sounds: Dictionary = {} # id -> AudioStream
var _from_files: Dictionary = {} # id -> true for sounds loaded from assets
var _ready_to_play := false
var _synth_task := -1
var _placeholders: Dictionary = {} # handed over by the worker when it is done
var _synth_ms := 0
var _world_voices: Array[AudioStreamPlayer3D] = []
var _ui_voices: Array[AudioStreamPlayer] = []
var _busy_until: Dictionary = {} # voice -> ticks msec when its sound ends
var _started_at: Dictionary = {} # voice -> ticks msec when its sound started
var _ambience: AudioStreamPlayer
var _night_ambience: AudioStreamPlayer
var _rain_ambience: AudioStreamPlayer
var _rain := 0.0
var _wind := 0.0
## How hard the weather's rain falls, and the rain the player is making.
var _weather_rain := 0.0
var _made_rain := 0.0
var _night := 0.0
var _ambience_wanted := false
var _rng := RandomNumberGenerator.new() # pitch variation only; never the simulation's
## Over the crickets' chorus, a near cricket now and then (at random: never a
## loop going round); over the rain's loop, a slow wandering in how loud and how
## high it is.
var _cricket_voices: Array[AudioStreamPlayer] = []
var _next_cricket := 0
var _cricket_in := 1.0
var _rain_base_db := 0.0
var _rain_drift_db := 0.0
var _rain_drift_to := 0.0
var _rain_drift_in := 0.0


func _ready() -> void:
	for bus: StringName in [BUS_AMBIENCE, BUS_SFX, BUS_UI]:
		_ensure_bus(bus)
	_build_voices()
	apply_volumes()
	Settings.setting_changed.connect(_on_setting_changed)
	_synth_task = WorkerThreadPool.add_task(_make_placeholders, false, "Placeholder sounds")


func _process(delta: float) -> void:
	if _synth_task >= 0 and WorkerThreadPool.is_task_completed(_synth_task):
		ensure_sounds()
	_vary_ambience(delta)


## The near crickets, one at a time at random; the rain wandering a little.
func _vary_ambience(delta: float) -> void:
	if _night_ambience != null and _night_ambience.playing and _night > 0.2:
		_cricket_in -= delta
		if _cricket_in <= 0.0:
			# Now and then a longer quiet; mostly a second or two.
			_cricket_in = _rng.randf_range(0.5, 2.6) + (_rng.randf_range(3.0, 8.0) if _rng.randf() < 0.12 else 0.0)
			var id: StringName = SoundSynth.CRICKET_IDS[_rng.randi_range(0, SoundSynth.CRICKET_IDS.size() - 1)]
			var stream: AudioStream = _sounds.get(id)
			var voice: AudioStreamPlayer = null
			for each in _cricket_voices: # (a free one only: never one still singing)
				if not each.playing:
					voice = each
					break
			if stream != null and voice != null:
				_next_cricket += 1
				voice.stream = stream
				voice.volume_db = Config.feedback.crickets_volume_db + linear_to_db(maxf(_night, 0.001)) + _rng.randf_range(-9.0, -1.0)
				voice.pitch_scale = _rng.randf_range(0.93, 1.07)
				voice.play()
	if _rain_ambience != null and _rain_ambience.playing:
		_rain_drift_in -= delta
		if _rain_drift_in <= 0.0:
			_rain_drift_in = _rng.randf_range(1.5, 5.0)
			_rain_drift_to = _rng.randf_range(-4.0, 1.0)
		var step := clampf(delta * 0.6, 0.0, 1.0)
		_rain_drift_db = lerpf(_rain_drift_db, _rain_drift_to, step)
		# (Only its loudness wanders: a looping sound's pitch changed as it plays was
		# a suspect in the audio crashes on the owner's phone.)
		_rain_ambience.volume_db = _rain_base_db + _rain_drift_db


func _exit_tree() -> void:
	if _synth_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_synth_task)
		_synth_task = -1


# --- playing ----------------------------------------------------------------------------

## Plays a world sound at `position`. Returns false if it could not be played
## (unknown id, or sounds not ready yet).
func play_at(id: StringName, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0, vary: bool = true) -> bool:
	var stream := _stream_for(id)
	if stream == null:
		return false
	var voice := _free_voice(_world_voices) as AudioStreamPlayer3D
	if voice == null:
		sounds_dropped += 1
		return false # (every voice busy: this one goes unheard rather than cutting another off)
	voice.position = position
	_start(voice, id, stream, volume_db, _varied(pitch) if vary else pitch)
	return true


## Plays a UI sound (not positioned in the world).
func play_ui(id: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> bool:
	var stream := _stream_for(id)
	if stream == null:
		return false
	var voice := _free_voice(_ui_voices) as AudioStreamPlayer
	if voice == null:
		sounds_dropped += 1
		return false
	_start(voice, id, stream, Config.feedback.ui_volume_db + volume_db, pitch)
	return true


## Starts the background loop (soft wind). Safe to call before sounds are ready.
func start_ambience() -> void:
	_ambience_wanted = true
	if not _ready_to_play or _ambience.playing:
		return
	var stream: AudioStream = _sounds.get(WIND)
	if stream == null:
		return
	_ambience.stream = stream
	_ambience.volume_db = wind_db(_wind)
	_ambience.play()


## How loud the wind is heard at `wind` (0 … 1): not at all on a still day
## (owner: a constant hiss "like the ocean" under everything), coming in as it
## blows, as loud as ever in a real wind.
const WIND_HEARD_FROM := 0.15
const WIND_HEARD_FULL := 0.6
const SILENT_DB := -80.0


static func wind_db(wind: float) -> float:
	var heard := smoothstep(WIND_HEARD_FROM, WIND_HEARD_FULL, wind)
	if heard <= 0.0:
		return SILENT_DB
	return maxf(Config.feedback.wind_volume_db + Config.weather_fx.wind_gain_db * wind + linear_to_db(heard), SILENT_DB)


func stop_ambience() -> void:
	_ambience_wanted = false
	_ambience.stop()
	_night_ambience.stop()
	for cricket in _cricket_voices:
		cricket.stop()
	_rain_ambience.stop()
	# (The next world begins under whatever sky it has.)
	_rain = 0.0
	_wind = 0.0
	_weather_rain = 0.0
	_made_rain = 0.0


## How much it is night (0 day … 1 night): the crickets come in with the dark
## and go with the dawn.
func set_night(amount: float) -> void:
	_night = clampf(amount, 0.0, 1.0)
	if not _ready_to_play or not _ambience_wanted or _night < NIGHT_SILENT_BELOW:
		if _night_ambience.playing:
			_night_ambience.stop()
		return
	if not _night_ambience.playing:
		var stream: AudioStream = _sounds.get(CRICKETS)
		if stream == null:
			return
		_night_ambience.stream = stream
		_night_ambience.play()
	_night_ambience.volume_db = Config.feedback.crickets_volume_db + linear_to_db(maxf(_night, 0.001))


## The weather to be heard: how hard it rains (0 … 1) and how hard the wind
## blows (0 … 1). Rain is a loop of its own; the wind is the ambience, louder.
func set_weather(rain: float, wind: float) -> void:
	_weather_rain = clampf(rain, 0.0, 1.0)
	_rain = maxf(_weather_rain, _made_rain)
	_wind = clampf(wind, 0.0, 1.0)
	if _ambience.playing:
		_ambience.volume_db = wind_db(_wind)
	if not _ready_to_play or not _ambience_wanted or _rain < 0.02:
		if _rain_ambience.playing:
			_rain_ambience.stop()
		return
	if not _rain_ambience.playing:
		var stream: AudioStream = _sounds.get(RAIN)
		if stream == null:
			return
		_rain_ambience.stream = stream
		_rain_ambience.play()
	_rain_base_db = Config.weather_fx.rain_volume_db + linear_to_db(maxf(sqrt(_rain), 0.001))
	_rain_ambience.volume_db = _rain_base_db + _rain_drift_db


## The rain the player is making under a cloud (0 = none): heard like the
## weather's, whichever is the louder.
func set_made_rain(amount: float) -> void:
	_made_rain = clampf(amount, 0.0, 1.0)
	set_weather(_weather_rain, _wind)


func rain_ambience_player() -> AudioStreamPlayer:
	return _rain_ambience


func night_ambience_player() -> AudioStreamPlayer:
	return _night_ambience


func is_ambience_wanted() -> bool:
	return _ambience_wanted


func stop_all() -> void:
	for voice in _world_voices:
		voice.stop()
	for voice in _ui_voices:
		voice.stop()
	_busy_until.clear()
	_started_at.clear()


# --- sounds -----------------------------------------------------------------------------

func is_ready() -> bool:
	return _ready_to_play


## Makes sure the sounds exist, waiting for the worker if needed (tests; the
## game simply plays nothing until they are ready).
func ensure_sounds() -> void:
	if _synth_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_synth_task)
		_synth_task = -1
	if _ready_to_play:
		return
	set_process(false)
	for id: StringName in _placeholders:
		if not _sounds.has(id): # a sound registered meanwhile wins
			_sounds[id] = _placeholders[id]
	_placeholders = {}
	_load_sound_files()
	_ready_to_play = true
	Log.info(Log.Category.CORE, "Sounds ready", {"sounds": _sounds.size(), "from_files": _from_files.size(), "synth_ms": _synth_ms})
	sounds_ready.emit()
	if _ambience_wanted:
		start_ambience()


func has_sound(id: StringName) -> bool:
	return _sounds.has(id)


func sound(id: StringName) -> AudioStream:
	return _sounds.get(id)


func sound_ids() -> Array:
	return _sounds.keys()


## True if the sound comes from an audio file rather than the generator.
func is_from_file(id: StringName) -> bool:
	return _from_files.has(id)


## Registers (or replaces) a sound.
func set_sound(id: StringName, stream: AudioStream) -> void:
	_sounds[id] = stream


# --- volumes ----------------------------------------------------------------------------

## Pushes the player's volume settings to the buses.
func apply_volumes() -> void:
	_set_bus_volume(BUS_MASTER, float(Settings.get_value(&"audio/master")))
	_set_bus_volume(BUS_AMBIENCE, float(Settings.get_value(&"audio/ambience")))
	_set_bus_volume(BUS_SFX, float(Settings.get_value(&"audio/sfx")))
	_set_bus_volume(BUS_UI, float(Settings.get_value(&"audio/ui")))
	if bool(Settings.get_value(&"audio/muted")):
		AudioServer.set_bus_mute(AudioServer.get_bus_index(BUS_MASTER), true)


## A 0..1 slider value as decibels (0 = silent).
static func slider_to_db(value: float) -> float:
	return linear_to_db(clampf(value, 0.0001, 1.0))


# --- queries (debug, tests) -------------------------------------------------------------

## How many voices are sounding right now.
func active_voices() -> int:
	var now := Time.get_ticks_msec()
	var count := 0
	for voice: Node in _busy_until:
		if int(_busy_until[voice]) > now:
			count += 1
	return count


func world_voice_count() -> int:
	return _world_voices.size()


func ui_voice_count() -> int:
	return _ui_voices.size()


func world_voice(index: int) -> AudioStreamPlayer3D:
	return _world_voices[index]


func ui_voice(index: int) -> AudioStreamPlayer:
	return _ui_voices[index]


func ambience_player() -> AudioStreamPlayer:
	return _ambience


func debug_text() -> String:
	return "audio %d/%d voices  %d played  %d sounds%s" % [
		active_voices(), _world_voices.size() + _ui_voices.size(), sounds_played, _sounds.size(),
		"" if _ready_to_play else " (preparing)"]


# --- internals --------------------------------------------------------------------------

func _stream_for(id: StringName) -> AudioStream:
	if not _ready_to_play:
		sounds_dropped += 1
		return null
	var stream: AudioStream = _sounds.get(id)
	if stream == null:
		sounds_dropped += 1
		Log.warn(Log.Category.CORE, "Unknown sound", {"id": id})
	return stream


func _start(voice: Node, id: StringName, stream: AudioStream, volume_db: float, pitch: float) -> void:
	voice.set(&"stream", stream)
	voice.set(&"volume_db", volume_db)
	voice.set(&"pitch_scale", maxf(pitch, 0.05))
	voice.call(&"play")
	var now := Time.get_ticks_msec()
	_started_at[voice] = now
	_busy_until[voice] = now + int(stream.get_length() / maxf(pitch, 0.05) * 1000.0)
	sounds_played += 1
	last_sound = id


## A voice is free this long after its sound should have ended (the mixer may lag).
const FREE_AFTER_MSEC := 50


## A voice that has finished — or null: none is free. (A playing voice is not
## given another sound: changing a sound under the mixer while it plays is
## what crashed the audio thread on the owner's phone at the fastest speed.)
func _free_voice(pool: Array) -> Node:
	var now := Time.get_ticks_msec()
	for voice: Node in pool:
		if int(_busy_until.get(voice, 0)) + FREE_AFTER_MSEC <= now:
			return voice
	return null


func _varied(pitch: float) -> float:
	var spread := Config.feedback.pitch_variation
	return pitch * (1.0 + _rng.randf_range(-spread, spread))


func _build_voices() -> void:
	for i in Config.feedback.world_voices:
		var voice := AudioStreamPlayer3D.new()
		voice.name = "World%d" % i
		voice.bus = BUS_SFX
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		voice.unit_size = Config.feedback.full_volume_distance
		voice.max_db = 0.0
		voice.attenuation_filter_cutoff_hz = 20500.0 # distance makes it quieter, not duller
		voice.panning_strength = 0.6
		add_child(voice)
		_world_voices.append(voice)
	for i in Config.feedback.ui_voices:
		var voice := AudioStreamPlayer.new()
		voice.name = "UI%d" % i
		voice.bus = BUS_UI
		add_child(voice)
		_ui_voices.append(voice)
	_ambience = AudioStreamPlayer.new()
	_ambience.name = "Ambience"
	_ambience.bus = BUS_AMBIENCE
	add_child(_ambience)
	_night_ambience = AudioStreamPlayer.new()
	_night_ambience.name = "NightAmbience"
	_night_ambience.bus = BUS_AMBIENCE
	add_child(_night_ambience)
	for i in 3:
		var cricket := AudioStreamPlayer.new()
		cricket.name = "Cricket%d" % i
		cricket.bus = BUS_AMBIENCE
		add_child(cricket)
		_cricket_voices.append(cricket)
	_rain_ambience = AudioStreamPlayer.new()
	_rain_ambience.name = "RainAmbience"
	_rain_ambience.bus = BUS_AMBIENCE
	add_child(_rain_ambience)


func _ensure_bus(bus: StringName) -> void:
	if AudioServer.get_bus_index(bus) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus)
	AudioServer.set_bus_send(index, BUS_MASTER)


func _set_bus_volume(bus: StringName, slider: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, slider_to_db(slider))
	AudioServer.set_bus_mute(index, slider <= 0.0)


## Runs on a worker thread; the result is picked up by ensure_sounds().
func _make_placeholders() -> void:
	var started := Time.get_ticks_msec()
	_placeholders = SoundSynth.make_all()
	_synth_ms = Time.get_ticks_msec() - started


## Audio files replace generated sounds of the same id, and add new ones.
func _load_sound_files() -> void:
	var dir := DirAccess.open(SFX_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		# Exported builds list "name.wav.import"; the resource path has no ".import".
		var file_name := file.trim_suffix(".import").trim_suffix(".remap")
		if not SFX_EXTENSIONS.has(file_name.get_extension().to_lower()):
			continue
		var stream := load(SFX_DIR + file_name) as AudioStream
		if stream == null:
			continue
		var id := StringName(file_name.get_basename())
		_sounds[id] = stream
		_from_files[id] = true


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if String(key).begins_with("audio/"):
		apply_volumes()
