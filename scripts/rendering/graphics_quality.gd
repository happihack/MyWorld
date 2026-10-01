class_name GraphicsQuality
extends RefCounted
## Resolves the player's "graphics/quality" setting into a concrete level
## (bible §31.14: 60 FPS on modern phones, graceful degradation on low-end).
##
##   LOW    — no shadows, no vignette. Also what the OpenGL fallback gets on "auto".
##   MEDIUM — sun shadows (2048 atlas), vignette. "auto" on phones.
##   HIGH   — larger, softer shadows. "auto" on desktop.

enum Level { LOW, MEDIUM, HIGH }

const SETTING := &"graphics/quality"
const NAMES := {"low": Level.LOW, "medium": Level.MEDIUM, "high": Level.HIGH}


## The level for a setting value ("auto", "low", "medium", "high").
static func resolve(setting_value: String, is_mobile: bool, is_compatibility_renderer: bool) -> Level:
	var key := setting_value.to_lower()
	if NAMES.has(key):
		return NAMES[key]
	# "auto" (or anything unrecognised)
	if is_compatibility_renderer:
		return Level.LOW
	return Level.MEDIUM if is_mobile else Level.HIGH


## The level for the current settings and device.
static func current() -> Level:
	return resolve(
		str(Settings.get_value(SETTING)),
		OS.has_feature("mobile"),
		RenderingServer.get_current_rendering_method() == "gl_compatibility")


static func shadows_enabled(level: Level) -> bool:
	return level >= Level.MEDIUM


static func shadow_atlas_size(level: Level) -> int:
	return 4096 if level == Level.HIGH else 2048


static func vignette_enabled(level: Level) -> bool:
	return level >= Level.MEDIUM


static func level_name(level: Level) -> String:
	return Level.keys()[level].to_lower()
