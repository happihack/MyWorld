extends Node
## Autoload "EventBus": global signals for major events (bible §31.5).
##
## Rules:
## - Only major, cross-system events live here. No per-entity or per-frame signals.
## - Payloads are ids and small values, never object references (ids survive saves).
## - Queries go through owning systems directly; the bus is for notifications.
@warning_ignore_start("unused_signal")

# --- World lifecycle ---
signal world_loaded(world_id: String)
signal world_unloaded
signal world_changed(reason: StringName)
signal chunk_loaded(coord: Vector2i)
signal chunk_unloaded(coord: Vector2i)

# --- Time ---
signal day_started(day: int)
signal season_changed(season: int, year: int)
signal year_started(year: int)
signal sim_speed_changed(speed_index: int)

# --- People & entities ---
signal person_born(person_id: int)
signal person_died(person_id: int, cause: StringName)
## person_id is -1 when the selection is cleared.
signal person_selected(person_id: int)
signal person_followed(person_id: int)
signal entity_selected(kind: StringName, entity_id: int)

# --- Player ---
signal tool_changed(tool_id: StringName)
signal intervention_applied(intervention_id: int)
signal stimulus_emitted(stimulus_id: int)

# --- World events & discovery ---
signal weather_changed(old_state: StringName, new_state: StringName)
signal discovery_found(discovery_id: int)
signal technology_discovered(tech_id: StringName, inventor_id: int)
signal major_event_occurred(event_id: int)
signal notification_created(notification_id: int)

# --- Save / load ---
signal save_started(reason: StringName)
signal save_completed(path: String, duration_ms: float)
signal save_failed(error_message: String)
signal load_failed(error_message: String)

# --- Application lifecycle (emitted by AppLifecycle) ---
signal app_paused
signal app_resumed
signal app_focus_changed(has_focus: bool)
## Emitted before the app closes; listeners must finish synchronously (e.g. save).
signal app_quit_requested
## Android back button / desktop Escape equivalent. UIRoot closes the top panel.
signal back_requested

@warning_ignore_restore("unused_signal")
