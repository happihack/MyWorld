# MY WORLD IN A BOX — IMPLEMENTATION PHASES

> **Status:** v1.0 · 2026-09-30
> **Implements:** the milestone roadmap in `my_world_plan.txt` (M0–M35 + First Vertical Slice), expanded and reconciled with the full specification in `my_world.txt`.
> **Design authority:** `game_bible.md` (section references like **B§14** point there; **S§n** = spec section in `my_world.txt`; **P:Mn** = plan milestone).
> **Engine:** Godot 4.7.2 · GDScript · Android-first.

---

## PART A — HOW TO USE THIS DOCUMENT

### A.1 The rules (non-negotiable)

1. **One phase at a time.** Do not start a phase until the previous one's exit criteria are green. Sub-phases (e.g., `M4.2`) are the unit of a single working session and should each end in a runnable build.
2. **If a phase or sub-phase feels too big, split it again** (P: Critical Rule). Record the split in this file.
3. **Always runnable.** Every sub-phase ends with: project opens, no parser errors, no runtime errors in a 2-minute play, all tests pass.
4. **Error-first** (S§101): on any error, stop feature work → exact file + line + cause → smallest reliable fix → rebuild → re-run tests.
5. **Feel before features** (P: Most Important Rule): a milestone isn't done because it works; it's done when it *feels good* per its exit criteria.
6. **Verify Godot 4.7.2 APIs** before use when uncertain (S§102). APIs flagged ⚠ in this document must be checked against the 4.7 class reference on first use.
7. **Complete files** over fragments when creating scripts; exact replacements when modifying (S: Implementation Instructions).
8. **No placeholder architecture.** Placeholder art/audio is fine.

### A.2 Per-sub-phase workflow

```
1. Re-read the phase + referenced bible sections.
2. State the plan briefly (architecture, dependencies, files).
3. Implement the smallest working version.
4. Run: open editor → run main scene → exercise feature → run tests headless.
5. Fix ALL errors and warnings that indicate bugs.
6. Profile if the phase has a performance budget.
7. Android check if the phase has one (from M0 on, at least at the end of every milestone).
8. Write the Completion Report (A.3). Update "Known Issues" in this file.
```

### A.3 Milestone Completion Report (required, P: Completion Format + S§100)

```markdown
## M<n> COMPLETION REPORT
### IMPLEMENTED        — what now works (player-visible + technical)
### FILES CHANGED      — every created/modified file
### HOW TO RUN         — exact steps
### TESTED             — automated tests run (counts, pass/fail) + manual test script results
### ANDROID TEST       — device(s) tested, yes/no, results
### PERFORMANCE        — FPS (avg/1% low), frame ms, memory, active entities, world size, sim load
### EXPECTED BEHAVIOR  — what a tester should observe
### KNOWN ISSUES       — honest list, with severity
### NEXT MILESTONE     — exactly what's next
```

Never silently skip failed tests.

### A.4 Definition of Done (every milestone)

- [ ] Exit criteria in the milestone are all met.
- [ ] Automated tests for the milestone exist and pass headless.
- [ ] Full test suite passes (no regressions).
- [ ] Save/load round-trips all new state (from M3 onward).
- [ ] New tunables live in `data/configuration/`, none hard-coded.
- [ ] New systems log under a category; errors handled with guards (B§31.11).
- [ ] Debug overlay/panel exposes the new system's key state (B§31, cross-cutting track T1).
- [ ] Android build installs and runs (from M0 onward, at least at milestone end).
- [ ] Performance within budget for the milestone.
- [ ] Completion report written.

### A.5 Version control conventions (recommended)

The folder is not yet a git repository. Recommended: `git init` in Phase M0.1 with a Godot `.gitignore` (`.godot/`, `*.import` handling per Godot 4 defaults, `export_presets.cfg` credentials excluded, `*.keystore`). One branch per milestone (`m04-first-inhabitants`), one commit per sub-phase, tag milestone completions (`m04-done`).

---

## PART B — RECONCILING THE TWO SOURCES

### B.1 Mapping: spec's 15 phases (S§99) ↔ plan milestones

| Spec phase (S§99) | Plan milestones | Notes |
|---|---|---|
| 1 Project foundation | M0 | |
| 2 World rendering | M1 | |
| 3 Camera and touch | M2 (+ M13 camera/map) | |
| 4 World interaction | M2, M3 | |
| 5 Basic people | M4 | |
| 6 Simulation | M6, M7 | |
| 7 Needs and AI | M4, M5, M6 | Needs/AI begin in M4 |
| 8 Civilization | M12, M16, M17 | |
| 9 History | M11, M19 | |
| 10 Environment | M9 | |
| 11 Player interventions | M3, M8, M9 | |
| 12 Persistence | Track T3 from M0; M20, M22 | **Pulled forward** (vertical slice needs save/load) |
| 13 Mobile sensors | M8 | |
| 14 UI/statistics | VS gate (v0), M14, M15 | **v0 pulled forward** for slice |
| 15 Mystery/endgame | M18, M28–M31 | |

### B.2 Adjustments made (and why)

| Adjustment | Reason |
|---|---|
| **Save skeleton in M0**, entity persistence from M3/M4, hardening in M22 (D-12) | Vertical slice requires save/load; "persistent world" is foundational (S§104) |
| **Debug overlay in M0**, grows every milestone, completed in M23 | "Debug mode is essential for development" (S§69) and "not optional" (P:M23) |
| **Test runner in M0**, tests added per milestone | "Every phase must be testable" (S§100) |
| **Chunked world data in M1**, streaming in M13 (D-13) | "Do not hard-code a tiny fixed map"; avoids core rewrite |
| **Event log with causes in M7** (D-14), story engine M19 | Story engine needs recorded causality |
| **Animals** placed in M1 (ambient birds), M7 (grazers/hunting), M9 (population ecology) | Plan has no animal milestone; spec + vertical slice require animals |
| **Water sim v0 in M3**, tilt bias M8, full hydrology M9 | M3 needs water disturbance, M8 needs tilt → water |
| **Home button in M2**, Locate for people in M5, full Locate/minimap in M13 | "Camera must never become lost" (S§7) from the first build |
| **Speed controls in M6** | Time only becomes meaningful in M6 |
| **Vertical Slice Gate (VS)** inserted after M9 | Plan's "First Vertical Slice" needs pieces of M11/M14/M15/M22; the gate assembles v0s of those and playtests before society systems |
| **Language/vocabulary** in M17 (names phonology seeded in M4) | Spec S§31; plan omits it |
| **Governance & conflict** in M12.5 / M19.1 | Spec wars/political groups; plan's story chain needs war |
| **Achievements** in M25, **Sandbox** in M32 | Spec S§66, S§68; plan omits them |
| **Large milestones split** (M4, M9, M10, M12, M16–M19, M21, M22) into sub-phases | P: Critical Rule |

### B.3 Stage overview

| Stage | Milestones | Player promise | Gate at end |
|---|---|---|---|
| **A — The Toy** | M0–M3 | Beautiful tiny world you can touch and disturb | "The player starts experimenting naturally" |
| **B — Life** | M4–M9 | People who notice you, days, food, tilt, weather | **VS Gate: vertical slice playtest** — "Oh wow, that person remembers what I did." |
| **C — Society & History** | M10–M12 | Families, memories, history, villages | "The world generates stories naturally" |
| **D — Legibility & Scale I** | M13–M15 | Bigger world, map, menus, statistics | "Player understands the world without debug tools" |
| **E — Progression** | M16–M19 | Tech, culture, science, stories | "Simulation writes stories developers didn't" |
| **F — Persistence & Hardening** | M20–M24 | Offline progression, scale, robust saves, tooling, mobile polish | Performance + save torture tests pass |
| **G — The Real Game** | M25–M27 | Integrated build, playtests, curiosity retention | External playtest findings addressed |
| **H — The Mystery** | M28–M31 | They notice you, discover the box, try to talk | Box arc playable end-to-end in accelerated test |
| **I — Breadth & Release** | M32–M35 | Content, new boxes, content pipeline, RC | Release checklist green |

---

## PART C — CROSS-CUTTING TRACKS

These run through every milestone. Each milestone lists its track obligations under "Tracks".

| Track | Starts | Every milestone must… | Completed in |
|---|---|---|---|
| **T1 Debug** | M0 | Add inspectors/overlay fields/commands for new systems | M23 |
| **T2 Tests** | M0 | Add unit tests for new logic + keep suite green | M35 |
| **T3 Save** | M0 | Serialize all new state; add a save-roundtrip test; bump `SAVE_VERSION` + migration if schema of an already-saved structure changes (after M22 stabilization, always) | M22 |
| **T4 Performance** | M1 | Measure against budget; add counters to overlay | M21, M24 |
| **T5 Android** | M0 | Install & run on device at milestone end | M24, M35 |
| **T6 Data** | M0 | Put tunables/content in resources | M34 |
| **T7 Audio/Haptics** | M2 | Add feedback sounds/haptics for new interactions (placeholder OK) | M24, M32 |
| **T8 UX/FTUE** | M1 | Keep first launch magical; add contextual hints for new verbs | M25 |
| **T9 Docs** | M0 | Update bible (if canon changed), this file, README run instructions | M35 |

---

## PART D — CANONICAL PROJECT STRUCTURE

Created progressively; a file appears in the milestone that first needs it.

```
res://
├── project.godot
├── export_presets.cfg                 (keystore paths/passwords NOT committed)
├── README.md                          (run/test/build instructions)
├── game_bible.md · implementation_phases.md   (may move to docs/)
├── scenes/
│   ├── main/        boot.tscn · main.tscn · title.tscn
│   ├── world/       world_view.tscn · box_frame.tscn · chunk_view.tscn · camera_rig.tscn · weather_fx.tscn
│   ├── people/      person_view.tscn
│   ├── animals/     animal_view.tscn
│   ├── buildings/   building_view.tscn · construction_view.tscn
│   ├── objects/     loose_object_view.tscn
│   ├── ui/          hud.tscn · tool_bar.tscn · person_card.tscn · context_menu.tscn · hamburger_menu.tscn
│   │                toast.tscn · while_you_were_gone.tscn · calibration.tscn · panels/*.tscn · widgets/*.tscn
│   └── debug/       debug_overlay.tscn · debug_panel.tscn
├── scripts/
│   ├── core/        log.gd · config.gd · event_bus.gd · settings.gd · app_lifecycle.gd · id_allocator.gd
│   │                rng_streams.gd · game_clock.gd · haptics.gd · audio_manager.gd · notification_manager.gd
│   ├── world/       world_data.gd · chunk_data.gd · world_coords.gd · world_generator.gd · start_templates.gd
│   │                spatial_index.gd · terrain_mesher.gd · chunk_streamer.gd · fog_of_knowledge.gd · box_unfolder.gd
│   ├── simulation/  world_session.gd · simulation_manager.gd · tier_manager.gd · offline_simulator.gd
│   │                invariant_checker.gd · stats_recorder.gd · surprise_director.gd
│   ├── people/      person_data.gd · person_registry.gd · traits.gd · needs.gd · name_generator.gd
│   │                pathfinder.gd · schedule.gd · lifecycle_system.gd · relationship_store.gd
│   │                memory_store.gd · memory.gd · household.gd
│   │   ├── ai/      brain.gd · activity_defs.gd · action_step.gd · actions/*.gd
│   │   └── perception/ stimulus.gd · perception_system.gd · interpretation.gd · reaction_table.gd · belief.gd
│   ├── civilization/ settlement.gd · settlement_planner.gd · construction_system.gd · job_board.gd
│   │                economy_system.gd · stockpile.gd · trade_system.gd · migration_system.gd · governance.gd
│   │                knowledge.gd · technology_system.gd · culture_system.gd · myth_system.gd · lexicon.gd
│   │                science_system.gd · anomaly_archive.gd · box_research.gd · communication_system.gd
│   ├── environment/ weather_system.gd · climate.gd · season.gd · water_sim.gd · soil_system.gd
│   │                vegetation_system.gd · animal_system.gd · animal_data.gd · disaster_system.gd · fire_system.gd
│   ├── interaction/ gesture_recognizer.gd · input_router.gd · picker.gd · interaction_manager.gd
│   │                intervention.gd · player_history.gd · player_relationship.gd · loose_object_system.gd
│   │   └── tools/   tool_base.gd · hand_tool.gd · observe_tool.gd · water_tool.gd · rain_tool.gd
│   │                wind_tool.gd · earth_tool.gd · object_tool.gd
│   ├── history/     world_event.gd · event_log.gd · history_archive.gd · significance.gd
│   │                story_engine.gd · timeline_model.gd · discovery_log.gd
│   ├── save/        save_manager.gd · save_container.gd · save_migrations.gd · save_validator.gd
│   ├── sensors/     sensor_manager.gd · motion_filter.gd · shake_detector.gd · calibration.gd
│   ├── rendering/   camera_rig.gd · chunk_view.gd · prop_renderer.gd · entity_view_pool.gd
│   │                person_view.gd · water_view.gd · day_night.gd · weather_fx.gd · box_frame.gd
│   ├── ui/          ui_root.gd · hud.gd · tool_bar.gd · person_card.gd · context_menu.gd · hamburger_menu.gd
│   │                toast.gd · wywg_panel.gd · panels/*.gd · widgets/chart.gd · widgets/family_tree.gd
│   └── debug/       debug_overlay.gd · debug_panel.gd · debug_commands.gd · inspectors/*.gd
├── data/
│   ├── configuration/  *_config.tres (+ the Resource class scripts in scripts/core/config_types/)
│   ├── worldgen/       start templates
│   ├── resources/      resource defs (wood, stone, …)
│   ├── species/        animal defs
│   ├── occupations/    occupation defs + routines
│   ├── activities/     activity utility defs
│   ├── buildings/      building defs
│   ├── technologies/   tech defs
│   ├── events/         event type defs + significance weights
│   ├── text/           templates (memories, notifications, history) as CSV for tr()
│   └── mysteries/      mystery defs
├── assets/  textures/ · models/ · audio/ · fonts/ · shaders/
└── tests/
    ├── run_tests.gd          (headless runner, extends SceneTree)
    ├── test_case.gd          (base class with assert helpers)
    ├── unit/                 test_*.gd
    ├── integration/          test_*.gd
    ├── fixtures/             old-version saves, corrupted saves
    └── soak/                 soak_runner.gd (N game years headless)
```

Headless commands (⚠ verify flags in 4.7):
```
godot --headless --path . -s res://tests/run_tests.gd                # all tests
godot --headless --path . -s res://tests/run_tests.gd -- --filter=save
godot --headless --path . -s res://tests/soak/soak_runner.gd -- --seed=1234 --years=50
godot --headless --path . --export-debug "Android Debug" build/wiab-debug.apk
```

---

# PART E — THE MILESTONES

---

## M0 — PROJECT FOUNDATION — ✅ COMPLETE (2026-09-30)

**Goal:** A clean, stable Godot 4.7.2 project that can eventually support the entire game. (P:M0, S§80–82, S§75–77)
**Player-facing:** The app launches into a basic "World in a Box" screen on desktop and Android.
**Depends on:** nothing.

### M0.1 Project creation & settings — ✅ DONE (2026-09-30)
- [x] Create project `my_world` (Godot 4.7.2), renderer **Mobile** with OpenGL fallback enabled (D-02). Verified: `Vulkan 1.4 - Forward Mobile` on desktop.
- [x] `git init` (branch `main`), `.gitignore`, `.gitattributes` (LF normalization).
- [x] Create the folder skeleton from Part D (empty folders get a `.gdkeep`) + `docs/`.
- [x] Project settings (keys verified against 4.7.2 `ProjectSettings`):
  - `application/config/name = "My World in a Box"`, `config/version = "0.0.1"`, placeholder `icon.svg`.
  - `display/window/handheld/orientation = 6` (Sensor: portrait + landscape).
  - `display/window/stretch/mode = canvas_items`, `aspect = expand`; base size 1080×1920 (portrait design); desktop window override 432×768.
  - `input_devices/pointing/emulate_touch_from_mouse = true` (desktop dev).
  - `input_devices/pointing/emulate_mouse_from_touch = true` (**kept at default** — GUI Controls rely on emulated mouse on touch devices; the InputRouter (M0.4) ignores emulated mouse events (`device == InputEvent.DEVICE_ID_EMULATION`) for gestures instead).
  - Sensors: `input_devices/sensors/enable_accelerometer/gravity/gyroscope = true` (**they default to false in 4.7**; SensorManager controls polling at runtime in M8).
  - `application/run/low_processor_mode` off in game; toggled at runtime in paused menus.
  - `physics/common/physics_ticks_per_second = 30` (we barely use physics).
  - `application/config/quit_on_go_back = false` (we handle back button).
  - `rendering/textures/vram_compression/import_etc2_astc = true` (required for Android export).
- [x] Input map actions for desktop debug only: `debug_toggle_overlay` (F3), `debug_panel` (F4), `debug_step` (F10), virtual tilt `debug_tilt_left/right/forward/back` (J/L/I/K), `debug_shake` (Space; Shift/Ctrl modifiers checked in code in M8). Events use `device = -1` (all devices).
- [x] Placeholder `scenes/main/main.tscn` (title + "Something lives inside.") so the project runs; replaced by Boot → Main in M0.3.
- **Verified:** headless import clean; settings/actions verification script PASS (F3 matches its action); headless + windowed runs exit 0 with no errors.
- **Not yet done:** first git commit (awaiting go-ahead); Android device run (M0.8).

### M0.2 Core services (autoloads) — ✅ DONE (2026-09-30)
- [x] `scripts/core/log.gd` → autoload **Log**: `Log.info(Log.Category.X, msg, data := {})`, `warn`, `error`, `debug`, `trace`; Level + Category enums (B§31.10, plus CORE/SIM/ENV/HISTORY); thread-safe (Mutex); ring buffer (500) via `get_recent()`; file sink `user://logs/wiab_<datetime>.log` rotating (keep 5), flushed on WARN+/pause/quit; DEBUG+ in debug builds, WARN+ in release; `line_logged` signal (main thread only).
- [x] `scripts/core/config.gd` → autoload **Config**: loads `data/configuration/*_config.tres` into typed fields (`Config.time`, `.world`, `.save`, `.interaction`, `.perf`); missing/wrong-type file → class defaults + logged problem (never crashes); `problems` list; `reload()`.
- [x] `scripts/core/config_types/*.gd`: `ConfigBase` (with `validate()`), `TimeConfig`, `WorldConfig`, `SaveConfig`, `InteractionConfig`, `PerfConfig` — defaults from B§33. `.tres` files generated with `ResourceSaver` (they store only non-default values; **defaults live in the class**, edit values in the inspector).
- [x] `scripts/core/event_bus.gd` → autoload **EventBus**: full signal catalogue (B§31.5) with typed, id-only payloads, plus `app_focus_changed`, `app_quit_requested`, `back_requested`.
- [x] `scripts/core/settings.gd` → autoload **Settings**: `DEFAULTS` table defines every key + type; `get_value/set_value` with type coercion (int↔float) and rejection of unknown keys/wrong types; debounced (0.5 s) atomic save (tmp + rename) to `user://settings.cfg`; flush on pause/quit.
- [x] `scripts/core/id_allocator.gd` (`IdAllocator`): monotonic ids from 1, `reserve_above()`, serializable; 0 = invalid.
- [x] `scripts/core/rng_streams.gd` (`RngStreams`): named streams seeded with `world_seed ^ (two FNV-1a-32 hashes of the name combined into 63 bits)` — **own FNV-1a hash instead of `String.hash()`** so seeds stay stable across Godot versions; state serializable; `new_world_seed()`.
- [x] `scripts/core/app_lifecycle.gd` (`AppLifecycle`, node in Main): pause/resume/focus/close/back notifications → EventBus + logs.
- **Verified:** clean import; headless smoke test of all services 31/31 PASS (log file + ring + filtering, config load/validate, signal round trip, settings coercion/rejection/atomic overwrite/reload incl. Vector3, id roundtrip, RNG determinism + FNV reference value + state roundtrip, lifecycle → EventBus); windowed run clean. Smoke checks become real unit tests in M0.7.
- **Note:** `godot --check-only` reports "Identifier not found: Log" for scripts using autoloads — a false positive (check-only doesn't register autoloads). Use real runs/tests for validation.

### M0.3 Scene architecture — ✅ DONE (2026-09-30)
- [x] `scenes/main/boot.tscn` + `scripts/core/boot.gd`: autoloads (Log → Config → EventBus → Settings) are already ready; Boot logs environment info (version, Godot, OS, model, locale, screen, dpi), warns on config problems, then `change_scene_to_file` → Main. (SaveManager readiness check added in M0.6.) Project main scene is now `boot.tscn`.
- [x] `scenes/main/main.tscn` + `scripts/core/main.gd`: `Main` with children `AppLifecycle`, `WorldSession`, `WorldView` (Node3D, empty until M1), `UIRoot` (CanvasLayer). Every launch creates a new world until M0.6.
- [x] `scripts/simulation/world_session.gd` (`WorldSession`, Node): `create_new(seed)` (0 = random), `load_from(dict) -> bool` (rejects missing keys, stays inactive), `to_dict()`, `shutdown()` (idempotent; also runs on `_exit_tree`); owns `GameClock`, `IdAllocator`, `RngStreams`; unique `world_id` even for equal seeds; emits `world_loaded/world_unloaded/sim_speed_changed`.
- [x] `scripts/core/game_clock.gd` (`GameClock`, **RefCounted** — pure/headless-testable instead of a Node): tick = game minute, `advance(real_delta) -> ticks` with accumulator, speed index over `TimeConfig.speed_multipliers` (Pause/Normal/Fast/Very Fast), `tick_fraction()` for interpolation, clamps frame delta to new tunable `TimeConfig.max_frame_delta_s` (0.25 s), sanitizes corrupt saved data. Calendar math arrives in M6.
- [x] `scripts/ui/ui_root.gd` (`UIRoot`): title, subtitle, version label (from project settings); back button with no panels → `app_quit_requested` then quit (panel stack in M2.4).
- [x] No launch flash: boot splash image off, splash bg colour and default clear colour = UI background colour.
- **Verified:** headless smoke 21/21 PASS (clock math/clamp/pause/speeds/roundtrip/sanitizing; session create/save-dict/load/rng continuation/invalid data/unique ids/signals; real Boot → Main flow ticking in real time; back button); windowed Boot → Main → world closed on exit, no errors.

### M0.4 Input foundation — ✅ DONE (2026-09-30)
- [x] `scripts/interaction/gesture.gd` (`Gesture`): type enum (TAP, DOUBLE_TAP, LONG_PRESS, DRAG_START/DRAG/DRAG_END, SWIPE, MULTI_START, PINCH, TWO_FINGER_DRAG, TWIST, MULTI_END, THREE_FINGER_TAP) + position, start_position, delta, velocity, scale, angle, touch_count, `hold_ms`, `after_multi`, `long_pressed`, `cancelled`.
- [x] `scripts/interaction/gesture_recognizer.gd` (`GestureRecognizer`, RefCounted, pure — driven by `(index, pos, time_ms)` so tests use exact timelines). Thresholds from `InteractionConfig` in dp × `units_per_dp`. Policies:
  - TAP fires **immediately** on release; the 2nd tap of a quick nearby pair fires DOUBLE_TAP instead (no added latency).
  - Long press via `update(now)`; no TAP after a long press.
  - DRAG_START carries `hold_ms` (lets the M3 HAND tool distinguish grab vs pan).
  - Release velocity averaged over the last 100 ms of movement; a rested finger never flings. SWIPE when ≥ `swipe_min_velocity_dp_s`.
  - 2nd finger cancels a drag (DRAG_END cancelled) → MULTI_START; PINCH (incremental scale), TWO_FINGER_DRAG (centroid delta), TWIST (incremental angle).
  - Lifting one finger of a pinch: the remaining finger may continue as an `after_multi` drag after slop; never a tap/long press/swipe.
  - THREE_FINGER_TAP (for the device debug overlay toggle).
  - `cancel_all()` for focus loss/pause/rotation; missed releases closed safely.
- [x] `scripts/interaction/input_router.gd` (`InputRouter`, node in Main): ScreenTouch/ScreenDrag → recognizer; **ignores touch-emulated mouse events** (`device == DEVICE_ID_EMULATION`); touches starting on a visible Control in group **`ui_blocker`** never reach the world; desktop extras: wheel = PINCH at cursor, right-drag = TWO_FINGER_DRAG; cancels on pause/focus loss/resize; `units_per_dp` from screen dpi + stretch scale, clamped to [0.25, 8] and logged (1.5 on a 96-dpi desktop window).
- [x] Debug label (debug builds only) in UIRoot shows the last gesture with details (hold ms, velocity, pinch scale, twist angle).
- **Verified:** headless smoke 29/29 PASS — 21 recognizer timelines (tap, double/non-double taps, long press, slop, deltas, rest vs fling, swipe, hold-then-drag, pinch, drag cancel, after-multi drag, twist, 3-finger tap + moved variant, cancel, missed release, leftover finger) + router via real pushed InputEvents (tap, ui_blocker, emulated-mouse ignore, wheel, right-drag) + Main wiring; windowed run clean.
- **To try on desktop:** run the project, click (tap), double-click, hold (long press), drag, flick, mouse-wheel, right-drag — the top-left label shows each gesture. Multi-touch needs a device (M0.8).

### M0.5 Debug overlay v0 — ✅ DONE (2026-09-30)
- [x] `scenes/debug/debug_overlay.tscn` + `scripts/debug/debug_overlay.gd` (`DebugOverlay`, CanvasLayer 100, `mouse_filter` IGNORE so it never blocks touches). Generic **`register_section(name, provider: Callable)`** — every later milestone adds its lines here (track T1); invalid providers are skipped.
- [x] Built-in sections: engine (FPS, frame ms, process/physics ms, draw calls, render objects/primitives, static memory (debug builds only), VRAM, object/node counts, build type) and input (last gesture with details). Main registers the world section (tick, speed, seed).
- [x] Refreshes at 4 Hz; `set_process(false)` while hidden (zero cost).
- [x] Toggle: F3 (`debug_toggle_overlay`) or THREE_FINGER_TAP; visibility persisted in new setting `debug/overlay_visible`.
- [x] Available when `OS.is_debug_build()` or Settings `debug/enabled`; **hidden unlock: 7 taps on the version label within 3 s** toggles `debug/enabled` (label is a `ui_blocker`, enlarged hit area).
- [x] The M0.4 gesture label moved into the overlay.
- **Verified:** headless smoke 17/17 PASS (layer/input passthrough, hidden+not processing by default, toggle/persist, all sections, custom/invalid sections, F3, real 3-finger tap, last gesture, unlock: 6 taps / 7 taps / slow taps / re-toggle / 7 real clicks on the label, label clicks never reach the world); windowed screenshot reviewed.
- **Note:** `Performance.TIME_PROCESS` includes the vsync wait — it is labelled "process", not "cpu". True CPU/GPU render times (viewport render-time measurement) are part of M23.

### M0.6 Save skeleton (Track T3) — ✅ DONE (2026-09-30)
- [x] `scripts/save/save_container.gd` (`SaveContainer`): `"WIAB"` magic + container version + header (`var_to_bytes` Dictionary) **with its own SHA-256** + ZSTD payload; header stores payload size, raw size and payload SHA-256. `write()`, `read()` (full verification → `ReadResult{ok, error, header, data}`), `read_header()` (cheap, no payload). Never encodes/decodes Objects. Detects bad magic, header/payload bit flips, truncation, trailing garbage, empty/random files, non-dictionary payloads.
- [x] `scripts/save/save_manager.gd` → autoload **SaveManager** (after Settings): `SAVE_VERSION := 1`; layout `<save_root>/<world_id>/world.sav (+ .bak1/.bak2, transient .tmp)`.
  - Atomic save: write `.tmp` → full read-back verify → rotate `bak1→bak2`, `world.sav→bak1` → rename `.tmp→world.sav`. Header carries world_id, seed, created/saved unix time, game tick, game version.
  - Load order: `world.sav` → verified `.tmp` (newest copy if the app died between rotation and rename) → `bak1` → `bak2`; migrates via `SaveMigrations`; **saves from a newer game version are refused and left byte-identical**; failures emit `load_failed`, never crash, never modify files.
  - `world_ids_by_recency()` (header scan, no pointer file); `find_latest_world_id()`.
  - Saves: immediately on new world, autosave every `Config.save.autosave_interval_s`, `app_paused`, `app_quit_requested`, focus loss, and **`WorldSession.about_to_close`** (emitted by `shutdown()` while still active → every orderly exit path saves). `last_save_info` for the overlay.
- [x] `scripts/save/save_migrations.gd` (`SaveMigrations`): `STEPS{from_version: Callable}`, `migrate(data, from, to)` with refusal of newer/invalid versions, missing steps and bad step results; input never mutated.
- [x] Main: tries worlds newest-first until one loads (a corrupt world with a misleading recent header can't block continuity); otherwise creates a new world (broken saves untouched). Boot logs the save root + latest world. Overlay "save" section (reason, ms, bytes, age).
- **Verified:** headless smoke 39/39 + 4/4 PASS (container corruption matrix, migrations, rotation & backup ages, fallbacks incl. crash window, newer-version refusal, recency, lifecycle + close saves, Main continuity, corrupt-newest skipping); real windowed launches continue the same world (tick 0 → 9 → 20). Save ≈ 3–12 ms, ~600 B.
- **For M0.7 tests:** corrupt save files only when no live session holds that world — a live session re-saves its world on close (correct behaviour, but it "repairs" the corruption mid-test).

### M0.7 Test runner (Track T2, D-03) — ✅ DONE (2026-09-30)
- [x] `tests/test_case.gd` (`TestCase`, Node): hooks `before_all/after_all/before_each/after_each` (may await); `assert_true/false/eq/ne/near/null/not_null/has`, `fail`; failures carry `file:line`; int/float and String/StringName compare equal; helpers `wait_frames`, `wait_seconds`, `remove_dir_recursive`, `write_bytes`, `corrupt_byte`.
- [x] `tests/run_tests.gd` (SceneTree): discovers `tests/unit` + `tests/integration` `test_*.gd`; options `--filter=`, `--dir=`, `--test-timeout=` (15 s), `--timeout=` (300 s watchdog), `--verbose`; exit 0/1/2.
  - **Script errors fail the test**: a `Logger` (`OS.add_logger`) records `ERROR_TYPE_SCRIPT/SHADER` errors — verified that in 4.7.2 a runtime error inside a called function does *not* stop the caller (it returns a default), so without this a crashing test would "pass". `push_error`/`Log.error` in negative tests do not fail tests.
  - Per-test timeout via polling (a stuck test can't hang the run); test files `load()`ed after autoloads are ready; compile failures reported as `<load>` failures.
  - **Isolation:** saves → `user://test_run/saves`, settings → `user://test_run/settings.cfg` (new `Settings.use_path()`), console echo of game logs off (new `Log.console_output`); all deleted afterwards. New `UIRoot.quit_action` lets tests exercise the back button without quitting the runner.
- [x] Runner self-test fixture `tests/fixtures/runner_selftest/` — must report 3 passed / 4 failed (assertion, sync script error, async script error, timeout).
- [x] Smoke checks from M0.2–M0.6 converted into **14 test files / 96 tests**: unit (log, config, id allocator, rng incl. pinned FNV values, game clock, gesture recognizer ×17, save container corruption matrix, migrations incl. "every old version has a step" guard) and integration (event bus, settings, world session, save manager, input router via real InputEvents, main flow: boot, continuity, corrupt-world handling, overlay, hidden unlock, back button, lifecycle).
- [x] `README.md` with run/test instructions.
- **Verified:** full suite 96/96 PASS in ~6 s; self-test 3/4 as designed; `--filter` works; real save + settings untouched.
- **Parallel-safety fix (found during M0.8):** 12 concurrent runs sharing `user://test_run` deleted each other's files (6–17 failures each). Now each process uses **`user://test_run_<pid>/`**, log files include the pid, and **`--shard=<i>/<n>`** splits the test files across processes. Verified: 12 concurrent shards = 96 passes total; 12 concurrent full runs = 96/0 each.

### M0.8 Android export & device loop (Track T5) — ✅ DONE (2026-09-30; release keystore deferred until a release build is needed)
- [x] Toolchain found: Android SDK `%LOCALAPPDATA%\Android\Sdk` (build-tools 34–36, platforms to 37, NDK, platform-tools/adb 1.0.41), JDK 17 (`C:\Program Files\Java\jdk-17.0.2`, already in editor settings), Godot debug keystore, **4.7.2.stable.mono** export templates.
- [x] `export_presets.cfg` (committed; passwords live in git-ignored `.godot/export_credentials.cfg`):
  - **Android Debug** — `com.happihack.worldinabox.dev`, "WIAB Dev", arm64-v8a + x86_64 (emulator), editor debug keystore, `build/wiab-debug.apk`.
  - **Android Release** — `com.happihack.worldinabox`, "My World in a Box", arm64-v8a + armeabi-v7a, release keystore **not configured yet**.
  - Both: version code 1 / name 0.0.1, **VIBRATE only** (internet off), immersive, no Gradle build, `tests/*` and `docs/*` excluded.
- [x] **Debug APK builds** headless and is verified with `aapt2`/`apksigner`: package, version, label, sole VIBRATE permission, ABIs, targetSdk 36, valid signature; game data 80 KB; no .NET runtime bundled. Size 57 MB (two ABIs of the engine library).
- [x] **Android SDK path set** in `editor_settings-4.7.tres` (`export/android/android_sdk_path` = `C:/Users/dreyer/AppData/Local/Android/Sdk`; backup `editor_settings-4.7.tres.bak-before-sdk-path`). `ANDROID_HOME` is **not** used as a fallback by Godot 4.7. Export with the normal Godot install verified: `godot --headless --path . --export-debug "Android Debug" build/wiab-debug.apk` → signed APK (v2+v3 schemes verify).
- [x] **Installed & tested on a real device** — Samsung Galaxy Note20 5G (SM-N981U), Android 13 (SDK 33), arm64-v8a, 1080×2400 @ 450 dpi, Adreno 650, Vulkan 1.1 Forward Mobile:
  - Launches full-screen (immersive), no crash-buffer entries; boot log at ~0.8–1.0 s after process start; **60 FPS**, 5 draw calls; PSS ≈ 269 MB (debug build, empty scene — engine baseline).
  - Input (injected via `adb shell input`): TAP at exact coordinates, LONG_PRESS (hold 463 ms), SWIPE (v ≈ 6600 units/s); `units_per_dp` = 2.8125 (= 450/160). Overlay toggles with an F3 key event; its visibility persists across launches.
  - Lifecycle: Home → focus lost + paused → saved; return → resumed (same process); **force-stop → relaunch continues the same world at the saved tick**; Back → saved, world closed, process exits; relaunch continues. `adb install -r` (app update) keeps the world. The clock does not advance while backgrounded.
  - Rotation: landscape (2400×1080) lays out correctly and input maps correctly.
  - **Fix found on device:** Android fires focus-loss and pause back to back (and quit is followed by world close), so every lifecycle event saved twice and rotated a duplicate into the backups. New tunable `SaveConfig.min_save_gap_ms` (500): `save_current()` skips a save within that gap of the last successful save of the same world. Verified on device: one save per event, three distinct backup files.
- [x] **Hands-on multi-touch check** — real fingers (cannot be injected via `adb shell input`): three-finger tap, double tap, pinch, two-finger drag and twist all confirmed on the device after the fix below. Note: a deliberate twist also registers a little drag (the midpoint between the fingers shifts) — expected; re-evaluate feel with the real camera in M1.7.
  - **Fix found by hand on device:** every two-finger gesture read "TWIST". Cause: TWIST was emitted for *any* angle change and real fingers never hold a constant angle (the synthetic tests used perfect geometry), so each pinch also rotated; the overlay showed only the last event. Now each two-finger component activates past a threshold — PINCH (`pinch_slop_dp` 8), TWO_FINGER_DRAG (`drag_slop_dp`), TWIST (`twist_start_deg` 12, starts from zero so there is no rotation jump) — and the overlay shows one combined line: `TWO_FINGER pinch x1.23  drag (dx, dy)  twist N deg`. New tests: jitter emits nothing, a wobbly pinch never twists, twist threshold/no jump, two-finger drag slop.
- [ ] **Release keystore** — create with `keytool`; supply via env vars `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD` (never committed). Needed before any release build.
- **Finding:** the project is pure GDScript but the installed Godot is the **.NET (mono) build**. Export works (Godot warns "Exporting to Android when using C#/.NET is experimental", non-blocking), but the **standard (non-.NET) Godot 4.7.2 + standard templates** is the recommended toolchain: no experimental path, smaller engine library. Decision pending (would be D-15).

### M0 — Completion summary
- **Exit criteria met:** desktop runs · Android debug build runs on a real device (Galaxy Note20 5G, 60 FPS) · structure clean · no parser/runtime errors · touch + multi-touch verified by hand · pause/resume/kill/back handled with saves.
- **Tests:** 100 automated tests (unit + integration) passing headless in ~7 s; runner self-test; parallel-safe.
- **Open items carried forward:** release keystore (before first release build); D-15 standard vs .NET Godot build; known issues KI-1..KI-3 (Appendix 6).

### M0 — Tests & checks
**Automated:** runner executes ≥ 4 test files green headless.
**Manual:** open project (no errors), run desktop, click/drag shows gestures, F3 overlay toggles, close window → save file appears in `user://saves/…`, relaunch loads it (tick persisted).
**Android:** install via one-click deploy and via APK; touch works; background/foreground logs `app_paused/app_resumed`; save written on background.
**Exit criteria (green light):** desktop runs · Android debug build runs · structure clean · no parser/runtime errors · touch input works · pause/resume handled.
**Risks:** Android toolchain setup time (mitigate: Appendix 1 checklist); DPI detection quirks (fallback constant 160 dpi × `screen_get_scale`).

---

## M1 — THE BOX

**Goal:** Make the game visually compelling before simulation. "This is a tiny world." (P:M1, S§3–5, S§46, S§58–59, B§7–8, B§28)
**Depends on:** M0. **Decision required before start:** confirm D-01 (3D stepped diorama).

### M1.1 World data model (chunked from day one — D-13) — ✅ DONE (2026-09-30)
- [x] `scripts/world/world_coords.gd` (`WorldCoords`, static, chunk size passed in): `floor_div`, `tile_to_chunk`, `tile_to_local`, `local_to_index`/`index_to_local`, `tile_to_index`, `chunk_origin`, `chunk_local_to_tile`, `chunk_rect`, `chunks_in_rect`, `tile_to_world3d` (tile-top centre), `world3d_to_tile`, `world2d_to_tile` — all floor-correct for negatives.
- [x] `scripts/world/chunk_data.gd` (`ChunkData`): layers per B§8.3 as packed arrays (height, terrain, water, moisture, fertility, vegetation, traffic, temperature offset (signed, stored biased), flags); `Terrain` enum; `FLAG_*` tile bits; clamping setters that mark `modified` + per-tile `FLAG_MODIFIED` + dirty bits (`DIRTY_MESH/WATER/SAVE`); `mark_pristine()` for generators; `to_dict()` (independent copies) / `from_dict()` (null on missing/wrong-size/wrong-type data).
- [x] `scripts/world/world_data.gd` (`WorldData`): `bounds: Rect2i` (box interior; `create_centered()` puts the world around the origin, e.g. −32…31), chunk dictionary, **`generator: Callable(coord) -> ChunkData`** called on demand (flat fallback without one), tile accessors routed to chunks, out-of-bounds reads return defaults and writes are ignored (no chunks created outside the box), `modified_chunks()`, `unload_chunk()` (drops unmodified chunks only), `to_dict()` (**modified chunks only**) / `from_dict()` (skips bad/out-of-bounds/wrong-size chunk records and reports the count).
- [x] `scripts/world/spatial_index.gd` (`SpatialIndex`): id → exact `Vector2` position + kind bit (`KIND_PERSON/ANIMAL/LOOSE_OBJECT/RESOURCE_NODE/BUILDING/MYSTERY`), chunk buckets, `insert/move/remove`, `query_radius(center, r, kind_mask)` nearest-first with deterministic tie-break, `query_chunk`; unknown ids safe; not saved (rebuilt from registries).
- [x] `data/configuration/world_config.tres` already provides chunk_size / world sizes / height step (M0.2).
- **Verified:** 32 new unit tests (negative-coordinate roundtrip over 6,400 tiles with unique slots, chunk routing across borders, sparse save roundtrip through bytes, snapshot independence, corrupt-record handling, spatial queries checked against brute force with 2,000 entities). Suite: 132 passing.
- Wiring into `WorldSession` and the save format happens in M1.8 once the generator (M1.2) exists.

### M1.2 World generation — split into M1.2a (terrain) and M1.2b (contents)

#### M1.2a Terrain generation — ✅ DONE (2026-09-30)
- [x] `scripts/world/hash_noise.gd` (`HashNoise`): **integer-only** hash, per-tile value, smooth value noise, fBm and fixed-point smoothstep. Used instead of `FastNoiseLite` so worlds are bit-identical on every platform and Godot version (float noise can differ in the last bit between x86 and ARM, which would change rounded height levels). Reference values pinned in tests.
- [x] `scripts/world/start_template.gd` (`StartTemplate`, a `ConfigBase` resource) + `data/worldgen/river_valley.tres`: shape enum (River Valley implemented; Island, Mountain Basin, Forest Clearing, Coastal Plain, Desert Oasis reserved for M32), valley/hill/river/pond/surface/contents parameters with validation (incl. a "meander too steep → river could break" check).
- [x] `scripts/world/world_generator.gd` (`WorldGenerator`): `generate_chunk(coord)` — every tile is a **pure function of (seed, template, tile)** in fixed-point integer math: meandering river along Z with ponds, lowered shallow banks, flat fertile valley floor, hills whose foot is warped by noise and whose height varies (some stay grassy, some turn to rock), dirt patches, moisture/fertility/vegetation layers, cooler high ground. Defined in world coordinates, so terrain never changes when the box unfolds. `sample_tile()`, `river_center_fp()`, `distance_to_river_fp()` for placement logic. **`GENERATOR_VERSION := 1`** — must be bumped (and old output kept reproducible) whenever output changes, because unmodified chunks are regenerated rather than saved.
- [x] `WorldData.set_generator(obj)`: keeps the generator object alive (a bare `Callable` does not — found when all test seeds produced the same flat world) and reports an error instead of silently falling back if it ever disappears.
- [x] `scripts/debug/world_preview.gd` (`WorldPreview`): top-down image of a world (terrain colour, height shading, water depth, optional markers) — used to review generation visually; basis for the minimap (M13).
- **Verified:** preview images of 6 seeds reviewed and tuned (first pass was a straight river between two grey rock walls). 23 new tests: noise determinism/range/smoothness/uniformity/pinned values; generator determinism, seed variety, **generation-order independence**, **unload → regenerate identical**, **64×64 centre identical inside a 128×128 box**, valid values for 8 seeds, **river connected top-to-bottom by flood fill**, ≥ 35% grass, golden checksum per generator version, speed. A 64×64 world generates in ~90 ms on desktop. Suite: 155 passing.
- **To verify in M1.8:** the golden checksum on the phone (ARM) once the world is wired into the game — the reason for the integer design.

#### M1.2b World contents — ✅ DONE (2026-09-30)
- [x] `scripts/world/prop_data.gd` (`PropData`): kind (TREE, ROCK, BUSH, HUT, CAMPFIRE, RUIN), tile, variant (tree variants 2–3 = conifers), rotation/scale/offset as integers. **Generated props get a stable id that encodes their tile** (`generated_id(tile)`, bit 62 set) — no allocator ids, nothing to save.
- [x] `scripts/world/prop_registry.gd` (`PropRegistry`): one prop per tile; `populate_chunk` / `depopulate_chunk` for generated props; `add` / `remove` for created ones; removing a generated prop is remembered so it stays gone after the chunk regenerates; keeps the `SpatialIndex` in sync; **saves only the differences** (removed generated ids + added props).
- [x] `WorldGenerator.generate_props(chunk)`: trees in clumps (forest noise × moisture, a few lone trees, conifers on higher ground), rocks (denser on rocky ground), berry bushes concentrated along forest edges — each a pure function of (seed, tile, generated terrain). Never on water, sand, river bed or snow.
- [x] `scripts/world/world_setup.gd` (`WorldSetup`):
  - `create_start()` → `StartInfo` (settlement tile, campfire id, hut ids, ruin id/tile, problems).
  - `find_settlement_site()`: requires a flat dry 5×5 square on grass/dirt; scores walking distance to water (ideal 5 tiles, never on the bank → not flood-prone), trees within 9 tiles (summed-area table), fertility and closeness to the box centre; deterministic tie-break.
  - Settlement placeholder: glade cleared, campfire + 3 huts facing the fire (created props with allocator ids; become real buildings in M12).
  - Mystery stub: one dormant RUIN far from the settlement (≥ 18 tiles), preferring high ground.
  - `validate()`: flood-fills **walkable** ground from the campfire (step ≤ 1 height level, water ≤ wading depth) and requires water within 30 steps, ≥ 150 buildable tiles, ≥ 4 food bushes, ≥ 12 trees, ≥ 2 rocks.
- **Verified:** preview images with markers reviewed and tuned (first pass had ~250 bushes scattered everywhere and speckled forests). 60/60 seeds valid in the tuning run. 22 new tests: id encoding, registry rules, sparse save roundtrip, props valid/deterministic/order-independent, deterministic start, site is a flat dry cleared glade near water and away from walls, ruin distance, 16 seeds all livable, validator reports each problem, walkability rules, no-site handled, golden props checksum. Suite: 177 passing (~21 s). Start setup takes ~0.3 s for a 64×64 world.
- **Note for M1.8:** a random seed whose world fails `validate()` should be re-rolled; an explicitly entered seed is used as-is with the problems logged.

### M1.3 Terrain rendering — ✅ DONE (2026-09-30)
- [x] `scripts/world/terrain_mesher.gd` (`TerrainMesher`, pure/static): one stepped-block mesh per chunk in chunk-local coordinates — a top face per tile, side faces down to each lower neighbour (looked up across chunk borders), full-height rim at the box edge (down to y = 0). Raw packed arrays → `ArrayMesh` (one surface). Per-vertex colour only: terrain colour, ±3.5% per-tile variation, **corner ambient occlusion** (corners beside taller tiles darken; quad split along the brighter diagonal), side faces darken toward their base. Winding verified against normals.
- [x] `scripts/core/config_types/terrain_palette.gd` (`TerrainPalette`) + `data/configuration/terrain_palette.tres`, loaded as `Config.terrain_palette`: top/side colour per terrain type, variation, occlusion and side-shade strengths.
- [x] `scripts/rendering/chunk_view.gd` (`ChunkView`): `MeshInstance3D` per chunk, positioned at the chunk origin, `rebuild_terrain()` clears `DIRTY_MESH`.
- [x] `scripts/rendering/world_view.gd` (`WorldView`): `show_world()`, `clear()`, `refresh_dirty_chunks()`; one shared vertex-colour material (`vertex_color_is_srgb = true` — without it the palette renders washed out). **Temporary** fixed camera that frames the whole box in portrait and landscape, plus a basic sun/ambient environment (replaced in M1.6 / M1.7).
- [x] Part of M1.8 pulled forward: `WorldSession` now owns `world`, `generator`, `props`, `spatial`, `start`; `create_new()` builds the world (a random seed is re-rolled up to 8 times until `validate()` passes; an explicit seed is used as given), `load_from()` rebuilds it from the seed. **Save format unchanged** — nothing in the world can be modified yet; real persistence of modified chunks/props remains M1.8. Main shows the world; the title text was removed; overlay shows tiles/chunks/props/settlement.
- [x] Tuning from screenshots: `WorldConfig.height_step` 0.25 → **0.4** (0.25 looked flat; 0.4 reads as a block diorama — bible §8.1/§33 updated); wading depth is now relative to the step (`WorldSetup.WADE_DEPTH_LEVELS`, `WorldData.height_step`); dirt patches use fractal noise (single-octave value noise gave boxy rectangles). Golden checksums re-pinned (pre-release, `GENERATOR_VERSION` stays 1).
- **Verified:** 13 mesher tests (face counts, extents, every triangle faces its normal, step/pit sides, seamless chunk borders, palette colours, occlusion, side shading, speed); suite 190 passing (~33 s). Desktop: 17 draw calls, ~11.7k triangles, 60 FPS. **Phone (Note20): world built in 412 ms, meshes ~70 ms, 60 FPS, 19 draw calls**; an existing version-1 save loaded and continued.
- New test helper `wait_real_ms()`: scene timers count frame deltas and can fire early after a long frame (world generation), which made a real-time save-gap test flaky.
- Not done (deferred, optional): bevelled block edges.

### M1.4 Water surface (static) — ✅ DONE (2026-09-30)
- [x] `scripts/world/water_mesher.gd` (`WaterMesher`, pure/static): one quad per wet tile at bed height + depth; **corner heights averaged over the wet tiles sharing the corner** (smooth, crack-free surface once the M3/M9 water simulation gives tiles different levels; identical across chunk borders); vertical cross-section faces where water meets the box wall; vertex colour carries shader data (r = depth 0..1, g = shore flag at corners touching dry land — the wall is not a shore), UV = world XZ.
- [x] `assets/shaders/water.gdshader`: **fully procedural** (no textures, no screen/depth reads → identical on Mobile and Compatibility): gentle vertex bob (shoreline pinned), three ripple waves in unrelated directions, shallow→deep tint, opacity by depth, thin animated foam line at the shore.
- [x] `ChunkView` gained a `Water` mesh instance (`rebuild_water()`, clears `DIRTY_WATER`, hidden when dry, casts no shadow); `WorldView.refresh_dirty_chunks()` rebuilds terrain and/or water; `WorldView.apply_palette()` pushes water colours/opacities/wave/foam from `TerrainPalette` (new *Water* group, incl. `water_deep_levels`).
- **Tuned from screenshots:** the first ripple pattern was a regular checkerboard (axis-aligned sines) and the foam a milky band over the whole bank tile.
- **Verified:** 12 mesher tests (dry chunk, quad per wet tile, flat surface over different beds, corner averaging, shore flags on a pond rim, depth attribute, world-space UVs, wall faces, winding, seamless chunk borders, the generated river is one flat surface with a quad per wet tile, view rebuild on dirty). Suite: 202 passing. Shader compiles and renders the same on **Mobile (Vulkan)** and **Compatibility (OpenGL 3.3)** on desktop. **Phone: 60 FPS, 27 draw calls, ~13k triangles.**

### M1.5 Props & ambient life — ✅ DONE (2026-09-30)
- [x] `scripts/rendering/prop_mesh_library.gd` (`PropMeshLibrary`): low-poly shapes generated in code, flat-shaded, vertex colours, no texture files — broadleaf tree ×2, conifer ×2, rock ×2, berry bush ×2 (with berries), hut (round walls, thatched cone roof with overhang, doorway), campfire (stone ring, logs, flame), ruin (slab, broken standing stones, fallen lintel), grass tuft. **Colour alpha = wind-sway weight** (0 rigid … 1 treetop; > 1 for the flame).
- [x] `scripts/world/prop_mesher.gd` (`PropMesher`, pure): **merges everything standing on a chunk into one mesh** (one draw call per chunk instead of one `MultiMesh` per prop type per chunk — the plan's approach would have cost 100+ draw calls). Applies each prop's tile/offset/rotation/scale, seats it on the terrain, tints living things ±12%; adds grass tufts on lush, prop-free grass tiles (deterministic tile hash).
- [x] `assets/shaders/prop.gdshader`: vertex colour + wind sway in world space (same wind for every prop regardless of its rotation). sRGB→linear conversion is guarded by **`OUTPUT_IS_SRGB`** — without it the Compatibility renderer drew all props far too dark (found by comparing both renderers).
- [x] `PropRegistry.chunk_changed` signal; `ChunkView.rebuild_props()`; `WorldView.show_world(world, props, start)` builds prop meshes, rebuilds only the chunks whose props changed (batched once per frame) and re-seats props when the terrain under them changes.
- [x] `scripts/rendering/ambient_life.gd` (`AmbientLife`): a flock of 7 birds circling the box in a loose V (MultiMesh + `assets/shaders/bird.gdshader` wing flap) and campfire smoke (`CPUParticles3D`, 14 soft generated puffs, drifting with the wind). Purely visual.
- **Fixes found by looking at renders:** smoke puffs were hard squares (now a generated soft round texture); a second smoke column stood at the world origin because emission started before the emitter was moved to the campfire; Compatibility-renderer darkness (above).
- **Deferred:** cloud shadows → M1.6 (with lighting).
- **Verified:** 19 new tests (shapes exist/well-formed/sized/sway weights; merged mesh contents, seating on terrain, scale, rotation via the door position, facing after transform, sway weight preserved, tuft rules, triangle budget; WorldView chunk/prop/water meshes, per-chunk rebuild on prop removal, automatic rebuild, terrain re-seat, ambient birds/smoke, no-campfire world, signal disconnect). Suite: 221 passing (~37 s). Desktop: props identical on Mobile and Compatibility (roof colour 200,163,73 vs 198,161,75). **Phone: 61 FPS, 45 draw calls, 44k triangles; view built in 184 ms.**

### M1.6 The box & lighting — ✅ DONE (2026-09-30)
- [x] `scripts/rendering/box_frame.gd` (`BoxFrame`): built in code from `WorldData.bounds` (so it is rebuilt when the box unfolds). **Display-case design**: wooden plinth with a molding and a low rim (the terrain's cut edge shows above it), brass corner posts and top rails outlining the box volume, four glass panes. Solid tall walls were rejected because the near wall would hide the world; glass keeps the walls real (the Edge) but see-through. Frame thickness scales with the box (clamped). Three meshes / draw calls (wood, brass, glass).
- [x] `scripts/rendering/world_lighting.gd` (`WorldLighting`): warm sun (`set_sun()` hook for the M6 day/night cycle), cool ambient, filmic tonemap, glow off; the **tabletop** the box stands on (`assets/shaders/table.gdshader`: unshaded pool that fades into the background with a contact shadow around the box); **vignette** (`assets/shaders/vignette.gdshader`, CanvasLayer under the UI).
- [x] `scripts/rendering/graphics_quality.gd` (`GraphicsQuality`): setting `graphics/quality` = auto/low/medium/high → LOW (no shadows, no vignette; "auto" on the OpenGL fallback), MEDIUM (sun shadows, 2048 atlas, vignette; "auto" on phones), HIGH (4096 atlas, softer filter; "auto" on desktop). Re-applied live when the setting changes.
- [x] **Cloud shadows** (deferred from M1.5): `assets/shaders/clouds.gdshaderinc` shared by the new `terrain.gdshader` and the prop and water shaders — large soft patches drifting with the wind, evaluated per vertex (negligible cost). Strength and patch size in `TerrainPalette` (*Clouds* group).
- [x] `WorldView` owns the frame and lighting, sizes them to the world, and frames the camera on the whole box (frame included). The temporary light/environment from M1.3 is gone; the temporary camera remains until M1.7.
- **Found by comparing renderers:** the glass looked like fogged grey panels on Mobile but fine on Compatibility. Two causes, both fixed: a glossy lit transparent material adds its full sky reflection regardless of alpha (glass is now unshaded), and Mobile blends in linear light, where a pale tint over a dark background is far more visible than with sRGB blending — glass opacity is now chosen per renderer (`glass_opacity()`).
- **Deferred:** fake tilt-shift blur → M24 high preset (a full-screen blur is too expensive to enable by default on phones).
- **Verified:** 13 new tests (frame meshes/extents/no wood inside the world/posts/glass fade/per-renderer opacity/rebuild/clamping/winding, quality resolution; WorldView frame matches world and rebuilds, lighting follows quality and the live setting, table under the box). Suite: 234 passing (~37 s). Desktop: both renderers match. **Phone (medium, shadows on): 60 FPS, 68 draw calls, ~67k triangles.**

### M1.7 Camera rig v0 — ✅ DONE (2026-09-30)
- [x] `scripts/rendering/camera_rig.gd` (`CameraRig`, built in code — no `.tscn` needed): pivot on the ground + distance (+ yaw, ready for twist-rotate in M2.1); pitch eases from 54° (overview) to 38° (closest); perspective FOV 32°.
  - **Anchored panning**: the ground point under the finger stays under the finger (finger projected onto the ground plane, not scaled pixels).
  - **Anchored zoom**: the point under the pinch/cursor stays fixed; clamped between `min_distance` and the fit distance.
  - **Never lost**: the furthest zoom is "the whole box fits" — found by projecting the box's actual corners (posts included) with a binary search, so it is right in portrait and landscape; the pivot's range shrinks as the view zooms out and is pinned to the centre when framed.
  - `frame_box()`, `focus_on(point, distance, animate)` (animated moves use exponential smoothing; direct manipulation is instant), `set_view_size()` (keeps the box framed across rotations), `handle_gesture()` (DRAG / TWO_FINGER_DRAG pan, PINCH zooms; taps are left for the world).
  - Looks at the terrain surface when zoomed in (ground-height callback from `WorldView`), at a fixed base height when framed.
  - Own projection math (`screen_ray`, `screen_to_ground`, `world_to_screen`) — testable headless and reusable for picking (M2.2) and UI anchoring.
- [x] `scripts/core/config_types/camera_config.gd` (`CameraConfig`) + `data/configuration/camera_config.tres` → `Config.camera`: FOV, pitches, min distance, fit margin, edge margin, smoothing, base look height.
- [x] `WorldView` owns the rig (the temporary camera is gone), feeds it viewport size changes and ground heights; Main routes gestures to it; overlay shows camera position/distance/pitch.
- [x] **Shadow range follows the camera** (`WorldLighting.set_view_distance`): the fixed range from M1.6 cut shadows off in the portrait framed view (camera 304 units away) and would have been blurry up close.
- **Verified:** 16 unit tests (framed in both orientations, tight framing, ray/projection inverse, pan and zoom anchoring, clamping, return to centre, 400 random operations never leave the world or produce NaN, roaming range vs zoom, animated focus/frame, gesture mapping, ground following, camera node sync) + 2 integration tests. Suite: 251 passing (~37 s). Driven with real input events on desktop (wheel zoom to the settlement, drag pan, zoom out returns to framed). **Phone: 60 FPS with shadows, 84 draw calls, ~87k triangles (incl. shadow pass); a drag while framed leaves the view pinned.** Pinch/pan feel still to be judged by hand.
- **Left for M2.1 (as planned):** fling inertia, rubber-band bounds, double-tap zoom, optional twist-to-rotate, Home button.

### M1.8 Wire into WorldSession — ✅ DONE (2026-09-30)
- [x] `WorldSession` owns `template_id`, `world`, `generator`, `props`, `spatial`, `start`; `create_new()` builds the world (random seeds re-roll until livable), `WorldView` shows it and the camera frames the box. (Building was pulled forward in M1.3.)
- [x] **Sparse world persistence**: `to_dict()["world_state"]` = template id, generator version, `WorldData.to_dict()` (modified chunks only), `PropRegistry.to_dict()` (removed generated ids + added props), `StartInfo.to_dict()`. `load_from()` restores it via `_restore_world()`: generator output + saved differences; the generator uses the **world's own** chunk size / height step (not today's config); **start info is restored as saved, never recomputed**; a different saved `generator_version` is logged.
- [x] **Save format version 2** (`SaveManager.SAVE_VERSION`), migration step `SaveMigrations._v1_to_v2` (version 1 stored no world content → empty `world_state` → rebuild from the seed once, exactly what v1 did on every load), fixture `tests/fixtures/saves/v1_world.sav`.
- [x] Robustness: missing/damaged `world_state` → error logged, world rebuilt from the seed (ids kept clear of the rebuilt props); bad chunk/prop records are skipped with a warning.
- [x] `scripts/world/world_checksum.gd` (`WorldChecksum.terrain / props`): shared by the golden tests and the overlay ("gen v1 terrain 62d2928c saved chunks N removed props N").
- **Verified:** 9 persistence tests (pristine world saves only the start in < 4 KB; exact reload incl. ids; changes survive and only touched chunks are stored, across two save/load cycles; saved start wins; world keeps its geometry when config changes; five kinds of damaged state fall back to the seed; bad records skipped; v1 fixture migrates, loads, and is re-saved as v2 with the v1 file kept as backup; Main keeps a felled tree gone across launches). Suite: 260 passing (~44 s).
- **Cross-platform determinism confirmed:** seed 6503499157575757534 gives terrain fingerprint `62d2928c`, 717 props and settlement (7, 0) on both the PC (x86) and the phone (ARM).
- **On device:** the phone's genuine version-1 save migrated and loaded; the next save was written as v2 (1,038 B, v1 files kept as `.bak1/.bak2`); relaunch restores the world in 160 ms (vs ~410 ms to build one).

### M1 — Completion summary
- **Built:** chunked world data, deterministic integer generation (River Valley), props/settlement/ruin with a livability validator, stepped-block terrain with ambient occlusion, animated water, merged low-poly props with wind sway, bird flock and campfire smoke, a display-case box with sun shadows, tabletop, vignette and cloud shadows, graphics quality presets, an anchored pan/zoom camera that cannot get lost, and sparse world persistence with a save migration.
- **Budgets (64×64 world):** phone (Galaxy Note20 5G, medium preset, shadows on) **60 FPS**, 84 draw calls (budget < 150), view meshes built in ~160–185 ms (budget < 300 ms), world generated in ~0.4–0.9 s or restored in 0.16 s. Desktop 60 FPS.
- **Tests:** 260 automated tests, ~44 s headless.
- **Exit criterion — "a player can stare at the world and enjoy watching it even though almost nothing is happening":** the motion is there (water, swaying trees and grass, flickering fire, smoke, birds, cloud shadows); the judgement is the owner's. *Pending the owner's verdict on the device.*
- **Carried forward:** bevelled block edges (optional), tilt-shift blur (M24), camera inertia/rubber-band/double-tap/Home (M2.1), world generation off the main thread if it grows (M13/M21), other start templates (M32).

### M1 — Tests & checks
**Automated:** `test_world_coords` (negative floor), `test_worldgen_determinism` (same seed ⇒ identical layer arrays & entity lists; different seeds differ), `test_worldgen_valid_terrain` (heights in range, water only where basin/river, no NaN), `test_worldgen_resources` (counts within ranges, not on water, reachable), `test_worldgen_validate` passes for 50 random seeds, `test_chunk_serialization`.
**Manual:** launch → box framed; zoom/pan works; water animates; trees sway; birds fly; smoke rises; world looks the same after relaunch; 5 different seeds look different but all have a sensible start.
**Android:** runs; measure FPS; portrait & landscape framing correct.
**Performance budget:** 64×64 world: ≥ 60 FPS mid-range, ≥ 30 FPS low-end; draw calls < 150; terrain build all chunks < 300 ms on device.
**Exit criteria:** *A player can stare at the world and enjoy watching it even though almost nothing is happening.* (Get 2–3 people to look at it for 30 s; do they smile / lean in?)
**Risks:** Art pipeline time → keep procedural/primitive meshes, focus on palette + lighting + motion. Shader incompatibility across renderers → test Compatibility early.

---

## M2 — TOUCH THE WORLD

**Goal:** The world is physically interactive; the player can naturally explore entirely through touch. (P:M2, S§6–7, S§10, S§44, B§23.1–23.3, B§26.4)
**Depends on:** M1.

### M2.1 Gesture completion & camera polish — ✅ DONE (2026-09-30)
- [x] Recognizer: double tap, swipe classification, two-finger drag/twist, cancellation on a second finger — already built in M0.4 (and given activation thresholds after the hands-on device test).
- [x] `CameraRig` feel:
  - **Fling**: a release faster than `fling_min_speed` keeps the world gliding, slowed by `fling_friction` (six times stronger once it pushes past the edge); stops the instant a finger touches the world (new `InputRouter.touch_began` signal); never after a cancelled or after-multi drag; **disabled by the reduced-motion setting**.
  - **Rubber band**: dragging past the limit follows with growing resistance (asymptotic to `rubber_band` × what is on screen) and springs back on release — also in the framed view, where panning used to do nothing. Implemented with a raw (unsoftened) drag position so resistance does not compound.
  - **Double tap**: animated zoom step (`double_tap_zoom`) ending with the tapped ground point under the finger; from the closest zoom it returns to the whole box. (Since M2.3 a double tap on an entity focuses it instead.)
  - **Twist to rotate** (setting `camera/twist_rotate`, **off by default**): rotates around the point between the fingers; the fit distance and pan limits account for the rotation.
  - **Guard**: runs first every frame; a non-finite or far-out-of-range state reframes the box before it can reach the camera transform.
- [x] `CameraConfig` *Feel* group: `fling_friction`, `fling_min_speed`, `rubber_band`, `double_tap_zoom`, `home_distance`.
- [x] **Home button** (`scripts/ui/widgets/home_button.gd`, bottom-right of the HUD): self-drawn house glyph (no image asset), 140-unit target (≈ 50 dp on a phone), member of `ui_blocker`; `UIRoot.home_pressed` → `Main.go_home()` glides to the settlement at `home_distance` (frames the box if there is no settlement).
- [x] `WorldView` syncs `twist_enabled` / `reduced_motion` from Settings live. Desktop right-drag is now bracketed by MULTI_START / MULTI_END like a real two-finger gesture.
- **Verified:** 15 new rig tests (fling glides/stops/direction/slow release/touch-stop/reduced motion/cancelled, rubber band give + resistance + hold + spring-back, bounded overscroll, fling into the edge, double-tap in and back out, zoom_to anchoring, twist off by default, twist anchoring and direction, rotated framing, guard) + 3 integration tests (Home button, world touch stops a fling, settings sync). Suite: 278 passing, no engine errors. **Phone:** Home tap glides to the settlement; a flick keeps gliding then rests; 60 FPS.
- **Still to judge by hand:** fling/rubber-band feel and (if enabled) twist-to-rotate.

### M2.2 Picking — ✅ DONE (2026-09-30)
- [x] `scripts/interaction/picker.gd` (`Picker`, pure/static — no physics, no colliders):
  - `raycast_terrain(world, origin, dir)`: DDA march over the height grid; hits block tops **and the sides of steps** (high ground hides what is behind it), enters through the box rim from outside, treats a water surface as the hit; returns tile, position, distance, `is_side`, `is_water`.
  - `pick(screen, rig, world, spatial, shape_for, touch_radius, kind_mask)` → `Result {kind NONE/TILE/WATER/ENTITY, tile, position, entity_id, entity_kind, direct}`. Entities are picked **in screen space**: each candidate's body (base→top segment + radius) is projected with the rig's own math and compared with the finger — a tap on a tree's canopy selects the tree although the ray lands on the ground behind it. Candidates come from the spatial index around the ray's ground track; entities hidden behind nearer terrain are skipped.
  - Selection rule: **direct hit > kind priority (person, animal, loose object, mystery, resource node, building) > screen distance > id**. Near misses count within `touch_radius` (from `InteractionConfig.touch_radius_dp`).
- [x] `PropData.pick_shape()` / `PICK_BODY` (height, radius per kind, scaled) and `PropRegistry.pick_shape(id)` as the shape provider; `CameraRig.world_units_per_screen_unit(point)`.
- [x] `scripts/rendering/pick_highlight.gd` (`PickHighlight`): tile outline + ring under the entity, drawn on top (no depth test). `WorldView.pick()` / `show_pick()`.
- [x] Temporary wiring in Main (until the InteractionManager, M2.3): a TAP is picked, described in the overlay ("pick HUT at (7, 2)", "pick WATER at … depth …", "… (near)") and highlighted while the overlay is shown.
- **Verified:** 20 picker tests (ray march: straight down, angled vs analytic plane, side of a raised block, top of a block, entry through the rim, misses, water; through the camera: visible tiles pick themselves, outside the world, water, prop base, **tree canopy**, near miss within/outside the touch radius, direct hit beats priority, priority between near misses, nearest among equals, kind mask, removed props, prop hidden behind a wall, no provider) + 2 integration tests on the generated world (campfire, hut roof, bare ground; highlight). Suite: 300 passing, no engine errors. **Phone:** taps on a hut, the campfire, a tree's canopy and grass each report the right target with the highlight in place.

### M2.3 Tap responses (contextual micro-feedback) — ✅ DONE (2026-09-30)
- [x] `scripts/interaction/interaction_manager.gd` (`InteractionManager`, child node of `WorldSession` as `session.interactions`, bound to the world in `_activate`) v0 — the seed of the single choke point for player actions (B§14.6; world changes, player history and stimuli join in M3.6). It knows the world, not the screen: the view picks, the manager decides.
  - `tap(pick)` → an `InteractionResponse`, announced through `responded`; `long_press(pick)` → effect `INSPECT` (the context panel is M2.4); `describe(pick)` → the same description without touching anything (double tap, UI). A miss returns null and is not an interaction. `interaction_count` per opened world.
  - `scripts/interaction/interaction_response.gd` (`InteractionResponse`): action, effect id (StringName: `dust`, `ripple`, `tree_shake`, `bush_rustle`, `rock_wobble`, `building_knock`, `fire_flare`, `ruin_hum`, `inspect`), position (touched point for ground/water — on the surface; **base of the prop** for entities), tile, entity id, prop kind, body (height, radius), terrain, description. Audio and haptics (M2.5) will listen to the same responses.
- [x] `scripts/rendering/world_effects.gd` (`WorldEffects`, in `WorldView`; `effects().play` is connected to `responded`) — purely visual, **fully pooled** (touching never allocates):
  - **Shake impulses.** Props are merged into one mesh per chunk, so one prop cannot be moved as a node. `prop.gdshader` now takes 4 impulses (`impulse_origin[4]`, `impulse_offset[4]`): vertices standing around a prop's base lean with it (bending like a stem: base planted, top moves most) and can be lifted. The oscillation and decay are computed on the CPU (testable), the shader only applies the offset. No mesh rebuilds; shadows follow. Same prop tapped again reuses its slot; a fifth shake replaces the one closest to rest. Per effect: lean, lift, Hz, seconds, reach (`SHAKES`).
  - **Rings** (`assets/shaders/ring.gdshader`, pool of 6): an expanding double ring that fades — ripples on water, the pulse under the ruin. Drawn after the water (render priority).
  - **Particle bursts** (4 kinds × 4 pooled one-shot `CPUParticles3D`): dust (tinted by the terrain it rises from), leaves, sparks, motes.
  - **Responses per target:** terrain — dust puff; water — double ripple ring + small splash; tree — shake + falling leaves; bush — rustle + leaves; rock — wobble and a small hop + grey dust; hut — tiny shake + thatch dust from the eaves; campfire — flame flicker + sparks; ruin — faint fast vibration + slow ring + rising motes (seed of curiosity).
  - Reduced-motion setting: shakes at 35 % strength (particles and rings stay).
- [x] **Double tap is context-aware** (`Main._on_gesture`, `CameraRig.handles_double_tap = false`): on an entity the camera glides to it (never zooming out to do so); on open ground or water it zooms toward the point as before.
- [x] **Long press** asks to inspect and marks the target for 1.2 s (`PickHighlight.clear_after`) until the context panel exists (M2.4). The debug overlay line now reads e.g. `pick TREE at (8, 6) -> tree_shake`.
- [x] Sounds (thud, plip, rustle, click, knock, hum) are **M2.5** (AudioManager); the responses they will key off exist now.
- **Moved:** *swipe through water → series of ripples* and the *tile-info trail* → **M9.5 / tool modes (M3)**. With the hand tool a one-finger drag pans the camera, and panning is anchored (the ground stays under the finger), so the finger never travels across the water. It becomes meaningful once a tool owns the drag.
- **Caught while building:** (1) particle tints were treated as linear colours on the Mobile renderer (pale, washed-out leaves) → `vertex_color_is_srgb`; green leaves were then invisible against the canopy → lighter falling-leaf colour; (2) with `explosiveness` below 1, particles still waiting to be born were drawn as **dark specks at the emitter** → all bursts emit at once; (3) tests that tapped "bare ground next to the campfire" hit the campfire instead — correct behaviour of the touch radius — and a random world sometimes had no open ground nearby → touch tests now run on a fixed-seed world and search for a spot where the finger touches only ground.
- **Verified:** 10 `InteractionManager` tests (each target kind, position at the prop base / on the water surface, vanished entity, misses, long press, describe, unbound, count) + 14 `WorldEffects` tests (shake rises, decays and frees its slot; values reach the shader; re-tap; slot replacement; rock hop vs. hut; reduced motion; ring timing and pooling; every effect's particles; leaves from the canopy; ruin; inspect/null; clear; dust colour) + 4 end-to-end tests through real touch events (tap fire → flare, tap ground → dust, double tap on a hut → camera centres on it, double tap on ground → zoom, long press → inspect + mark that fades) + 1 rig test. Suite: **329 passing**, no engine errors. Screenshots reviewed on **Mobile and Compatibility** (tree shake + leaves, dust, ripple, ruin pulse).
- **Phone (Note20):** taps on a tree, the campfire, a hut, a rock, grass and the river each reported the right target and effect (`TREE … -> tree_shake`, `WATER … depth 0.56 -> ripple`, …) with the effect visible; long press → `inspect`; 60 FPS, 44–48 draw calls; no errors in the log. Double tap could not be injected through adb (too slow) — covered by the end-to-end tests; **to try by hand**.

### M2.4 Long-press context panel (UI framework v0) — ✅ DONE (2026-09-30)
- [x] **Panel stack** in `UIRoot`: `open_panel` / `close_top_panel` / `close_all_panels` / `dismiss_transient_panels` / `top_panel` / `panel_count`. The Android back button closes the top panel and only leaves the game when none is open. Panels live on a full-screen layer that ignores input, so **a panel blocks touches only where it is** — the rest of the screen still belongs to the world.
  - `scripts/ui/panels/ui_panel.gd` (`UIPanel`, base of every panel): themed, member of `ui_blocker`, `closed` signal, `transient` flag; `close()` takes it out of the input group at once (not at the end of the frame).
- [x] **Context menu** (`scenes/ui/panels/context_menu.tscn`, `ContextMenu`): a compact card next to the finger naming what was pressed and listing what can be done. Rows are 136 units tall (48 dp on the test phone).
  - Placement (`ContextMenu.place`, pure): above the finger; below it near the top of the screen; **beside it on a low, wide screen** (landscape); never off screen and never under the finger.
  - Transient: touching the world closes it and **that tap does nothing else**; starting a drag or a two-finger gesture closes it too. A new long press replaces it. The pressed target stays marked while the menu is open.
  - Options come from `InteractionManager.actions_for(target)` — an action is listed once it works. Now: **Inspect**, **Touch** (worded to fit: *Shake* a tree or bush, *Disturb* water, *Knock* on a hut, otherwise *Touch*) and **Look closer**. The bible's other options (Observe, Follow, Remove, Move, …) join as their systems arrive.
- [x] **Inspect card** v0 (`scenes/ui/panels/inspect_card.tscn`, `InspectCard`): bottom-left card, clear of the Home button, with a self-drawn ✕ (`CloseButton`, 120 units). Stays open while exploring; replaced by the next inspect; closed by ✕ or back. Facts come from `InteractionManager.inspect(target)` → `InspectReport` (plain data; looking is not touching, nothing is announced):
  - prop: name (Tree / Pine / Rock / Berry bush / Hut / Campfire / Old stones), tile, stands on, size, ground height, moisture;
  - ground: terrain name, height, moisture, fertility, plant cover;
  - water: depth, bed, bed height.
- [x] `scripts/ui/ui_text.gd` (`UIText`): every player-facing word in one place (names, action labels, level words like Dry/Damp/Moist/Wet) — ready to move to `data/text` tables for localization.
- [x] `scripts/ui/ui_theme.gd` (`UITheme`): the look of panels, built in code — dark see-through cards with a warm rim, cream text, title/dim label styles, pressed state; `TOUCH_TARGET`.
- [x] **UI scale (fixes KI-1):** `UIRoot.ui_scale_for(window, base)` sets the window's `content_scale_factor` so a UI unit has the same physical size in portrait and landscape (1.0 upright, 1.78 in landscape on the test phone). Touch thresholds and the camera follow automatically (both read the visible rect).
- [x] `InteractionResponse` now carries `touch_effect` (what touching the target would do, kept on a long press) and `prop_variant`.
- **Caught while building:** in landscape the first placement rule put the menu **under the finger** (no room above or below on a 1080-high screen) → the "beside the finger" rule; a test tap meant to dismiss the menu landed on the menu itself and was (correctly) ignored.
- **Verified:** 4 new manager tests (actions, touch effect kept on long press, inspect of prop / ground / water) + 13 pure UI tests (wording for every terrain and prop, action labels, level words, menu placement above / below / beside / edges / offset view, UI scale upright / landscape / odd windows, theme) + 14 end-to-end tests in the main scene (menu opens for what was pressed and is on screen, real timed long press, wording per target, nothing pressed, screen corners, inspect card contents and position, ground and water cards, Touch action shakes the tree, Look closer, **back closes panels before leaving**, world touch dismisses the menu without touching the world, drag dismisses the menu but not the card, touches on a panel never reach the world, stack basics). Suite: **359 passing**, no engine errors. Screenshots reviewed in portrait (Mobile) and landscape (Compatibility).
- **Phone (Note20):** long press on a hut → menu above the finger; tapping *Inspect* with a real touch → card (Hut, tile 7, 2, Grass, Medium, height 3, Moist 74 %); back → card closed, app still running; long press on a tree → *Shake* in the menu; tap on the menu's title → nothing; tap on open ground → menu gone and the world untouched. Landscape (forced, then restored): UI at full size, menu beside the finger. 60 FPS, no errors in the log.
- **Not yet:** haptic tick on open (M2.5); safe-area insets (KI-2); the card is plain text rows, to be made friendlier as the systems behind the numbers come alive.

### M2.5 Feedback services (Track T7) — ✅ DONE (2026-09-30)
- [x] `scripts/core/haptics.gd` → autoload **Haptics**: `light()` / `medium()` / `strong()` / `pulse(strength)`. Uses `Input.vibrate_handheld(duration_ms, amplitude)` — **verified in 4.7.2**: the amplitude parameter exists (default -1). Rate limited (`haptic_min_gap_ms`, 60 ms): a pulse too soon after the last is dropped **unless it is stronger**, so rapid tapping never becomes a buzz but a jolt is never swallowed. Follows the `haptics/enabled` setting live. `vibrate_action` is replaceable (tests).
- [x] `scripts/core/audio_manager.gd` → autoload **AudioManager**:
  - Buses **Master > Ambience / SFX / UI** (created at startup if missing); volumes from the `audio/*` settings (slider → dB, 0 = muted), `audio/muted` mutes the master.
  - **Pools:** 8 `AudioStreamPlayer3D` world voices + 4 UI voices. `play_at(id, position, volume_db, pitch)` / `play_ui(id)`. A finished voice is reused first; when all are busy, the one that has played longest. World sounds get a small random pitch change per play (`pitch_variation`).
  - **Distance:** world sounds are positioned where they happen; inverse-distance attenuation with `full_volume_distance` (20 tiles) and no distance low-pass — zoomed in they are full volume, with the whole box in view they are about 24 dB quieter.
  - **Ambience:** `start_ambience()` / `stop_ambience()` — a soft looping wind (Main starts it with the world). Birds call from where they fly (`AmbientLife.chirp`): after owner feedback the calls are rare and irregular — 14–55 s of quiet, a 30 % chance that another bird answers a moment later, three different calls (`chirp`, `chirp_2`, `chirp_3`), each at a random pitch (0.78–1.3) and volume (up to 7 dB quieter).
  - **Sound sources:** a file `res://assets/audio/sfx/<id>.wav` or `.ogg` is used if present; otherwise a generated placeholder. So real audio can be dropped in one file at a time with no code change.
- [x] `scripts/audio/sound_synth.gd` (`SoundSynth`): **14 placeholder sounds generated from math** (no audio files in the project yet): `thud`, `plip`, `rustle`, `click`, `knock`, `crackle`, `hum`, three bird calls, `ui_open`, `ui_tap`, `ui_close`, and a seamless 3 s `wind` loop. Deterministic, 16-bit mono, made on a worker thread at startup (55 ms on the PC, **75 ms on the phone**); until ready, play calls are silent.
- [x] `scripts/interaction/touch_feedback.gd` (`TouchFeedback`): maps each `InteractionResponse` to a sound at the touched place and a pulse — terrain *thud*, water *plip*, tree/bush *rustle*, rock *click*, hut *knock* (medium pulse), campfire *crackle*, ruin *hum* (medium pulse); a long press gives the UI *open* tick and a light pulse. UI: choosing a menu action or pressing Home ticks; closing a card plays *close*.
- [x] `FeedbackConfig` (`data/configuration/feedback_config.tres`): pulse lengths and strengths, minimum gap, voice counts, full-volume distance, pitch variation, UI / wind / chirp volumes and chirp interval.
- [x] Particles (dust, leaves, ripple, sparkle): done in M2.3 (`WorldEffects`).
- [x] Debug overlay line: `audio 1/12 voices  5 played  12 sounds` / `haptics 4 (0 dropped)`.
- **Tuned by measurement** (the sounds were exported to WAV and their spectra analysed, since they cannot be listened to in an automated run): the first *thud* had half its energy below 150 Hz and the *wind* three quarters — a phone speaker plays almost none of that — so both were moved up (thud 185–330 Hz with an overtone, wind a 200–1650 Hz whoosh); the *hum* was raised to 262/392/523 Hz; the hiss of *rustle* and *crackle* was softened; the fade-in was shortened so clicks and knocks keep their attack.
- **Verified:** 7 synth tests (every sound sane, no click at start/end, deterministic, format, character — thud low, click bright, plip rises, two knocks — seamless wind loop) + 23 service tests (three strengths and their config, rate limit, stronger pulse passes, setting; buses, volumes, mute; placement, pool reuse, finished voice first, pitch variation, UI voices, unknown id, replacing a sound, ambience; every effect has a sound and a pulse, knock stronger than a tap, long press) + 1 end-to-end test (tap the fire: crackle from the fire's position and one light pulse; Home ticks; ambience starts and stops with the world). Suite: **390 passing**, no engine errors.
- **Phone (Note20):** the system reports an active audio track for the app, and its vibration log shows the pulses exactly as configured — 14 ms at 0.35 for taps on the fire and a tree, **24 ms at 0.6 for the knock on the hut**. 60 FPS.
- **To judge by ear and hand (cannot be automated):** whether the placeholder sounds are pleasant and the levels right (wind at −22 dB, world sounds −4…−9 dB), and whether the light tick is noticeable. All of it is in `feedback_config.tres` and the volume settings.

### M2.6 FTUE hint v0 (Track T8) — ✅ DONE (2026-09-30)
- [x] `scripts/ui/hint_director.gd` (`HintDirector`, in `UIRoot` as `hints()`): shows one quiet hint at a time, only when relevant, only until the player has done the thing once (bible §26.3).
  - **"Drag to explore."** after `hint_idle_seconds` (5 s) without a touch; gone for good after the first pan (one- or two-finger).
  - **"Hold to learn more."** (the bible's next hint; possible now that long press exists) `hint_follow_up_seconds` (2.5 s) after the first tap of the world; gone for good after the first long press.
  - In order, never two at once; a player who does the thing before its hint appears never sees it; no hints while a panel is open (the wait restarts when it closes).
- [x] State per install: Settings `ftue/completed` (comma-separated hint ids), so it survives new worlds. Resetting settings brings the hints back.
- [x] `scripts/ui/widgets/hint_label.gd` (`HintLabel`): a soft pill near the bottom centre that fades in and out; it ignores input and is not a UI blocker, so the world under it stays touchable; panels draw over it. Wording in `UIText.HINTS`.
- [x] **Opening shot** (found while testing the hint on the phone): the game opened on the whole box, where a one-finger drag only rubber-bands — so "Drag to explore." asked for something that did nothing. Now, as in bible §26.1 ("the camera descends into the open box"), the game opens on the box and after `OPENING_HOLD_SECONDS` (1.6 s) glides to the settlement, where dragging explores. Touching the world first cancels the glide; with reduced motion the view simply starts at the settlement.
- **Deferred:** the *per-world* half of `ftue_state`. No hint is per-world yet (the first will be the discovery hint, in a later milestone); storing unused state in every save would only be dead weight. Added when its first hint is.
- **Verified:** 13 director/label tests (timing, touch restarts the wait, pan completes and persists across sessions, tap does not dismiss, early pan / early long press skip the hint, order, suppression by panels, settings reset, no label, label placement and fade, hint wording style) + 3 in the main scene (real one-finger drag completes the hint; long press completes "hold"; no hint under an open card) + 3 opening tests (box → settlement and a drag then really moves the view; touch cancels; reduced motion). Suite: **409 passing**, no engine errors.
- **Phone (Note20):** launch → box → glide to the settlement → "Drag to explore." at 7 s; swipe → view moves, hint gone; tap → "Hold to learn more."; long press → gone, menu open. The hint state on the phone was reset afterwards, so the next launch shows the hints again.

### M2 — Completion summary
All six sub-phases are done (M2.1–M2.6): gestures and camera feel, picking, tap responses, the long-press menu with inspect card and panel stack, sound and haptics, first-time hints and the opening shot. **409 automated tests**, 60 FPS on the test phone throughout.
- **Exit criterion** — *"The player can naturally explore the world entirely through touch. Hand the phone to someone without instruction — do they pan/zoom/tap within 20 s?"* — is a hands-on judgement: **pending the owner's verdict**.
- **Still to judge by hand:** double tap (cannot be injected through adb), fling / rubber-band feel, whether the placeholder sounds are pleasant and the haptic tick noticeable.
- **Moved out of M2:** swipe-through-water ripples and the tile-info trail (→ M9.5 / tool modes); per-world hint state (→ with the first per-world hint).

### M2 — Tests & checks
**Automated:** `test_gestures_extended` (double tap timing, swipe vs drag, pinch focal), `test_camera_bounds` (pan clamp, zoom clamp, rubber-band returns, home), `test_picker` (tile under ray on synthetic height grid; priority ordering; touch radius scaling with zoom).
**Manual script:** explore whole box with one finger; pinch in on a hut; double-tap a tree; long-press water; swipe water; press Home from far away; rotate device mid-pinch (no crash, gesture cancels cleanly).
**Android:** gestures feel native; haptic light tick on tap; no accidental taps during pans.
**Performance:** input-to-feedback latency < 50 ms; still 60/30 FPS targets.
**Exit criteria:** *The player can naturally explore the world entirely through touch.* Hand the phone to someone without instruction — do they pan/zoom/tap within 20 s?
**Risks:** Tap vs pan ambiguity → tune slop/time on device; tiny targets → generous radius + priority.

---

## M3 — THE WORLD HAS PHYSICS

**Goal:** The first truly magical interaction — the player manipulates physical objects. (P:M3, S§20 gentle/moderate, S§21, B§23.2, B§14.6)
**Depends on:** M2.

### M3.1 Loose objects as data — ✅ DONE (2026-09-30)
- [x] `scripts/world/loose_object.gd` (`LooseObject`): `id`, `kind` (PEBBLE, ROCK, BOULDER, LOG, FRUIT, SEED, STRANGE_OBJECT), `variant`, `position` (ground plane) + `height_offset` (above what it rests on, so a resting object follows the ground if the terrain changes), `yaw`, `scale_percent`, `velocity`, `state` (RESTING, HELD, FALLING, SLIDING), `discovered_by`, `placed_by_player`, `moved_count`. Per-kind `SPECS`: body radius and height, mass, whether it floats; mass grows with the cube of the size. `give()` = how readily it yields to a finger (1 for an ordinary rock). `to_dict` / `from_dict` (validated; loaded objects are at rest).
- [x] `scripts/world/loose_object_registry.gd` (`LooseObjectRegistry`, in `WorldSession` as `session.loose`): add / remove / move, kept in step with the shared `SpatialIndex` (`KIND_LOOSE_OBJECT`); several objects may share a tile (`objects_at`); signals `object_added` / `object_removed` / `object_moved`.
  - **Sparse persistence, like props:** objects that came with the world regenerate and are not saved; the save holds only generated objects that were **moved or otherwise changed** (in full), ids of removed ones, and added objects. An untouched world stores nothing.
  - *Deviation from the plan:* the plan names one `loose_object_system.gd` node. The data is a `RefCounted` registry created fresh per world (the same pattern as `PropRegistry`, so load/restore can build it and swap it in atomically); the node that *steps* moving objects arrives with the integrator in M3.3.
- [x] **Rocks from worldgen become loose objects.** The generator is untouched (golden checksums unchanged): `WorldSetup.populate_chunk(..., loose)` routes generated rock props into the registry via `LooseObject.from_generated_rock` — same tile-encoded id, place, turn and look. Rocks generated at 110 % size or more become **boulders** (about a quarter of them: movable later, but heavy). Glade clearing, the ruin site and world validation handle loose objects. Without a registry (tests, tools) rocks stay props as before.
  - Seed 12345: 331 props + 177 loose objects (was 508 props).
  - **Older saves** (rocks were props; no `loose` entry): the removed-prop list is applied to loose objects too, so a cleared glade stays clear. Verified on the phone's existing world: 567 props + 150 loose = the 717 props it had.
- [x] `scripts/rendering/loose_objects_view.gd` (`LooseObjectsView`, in `WorldView`): one `MultiMesh` per shape (kind + variant) for all objects — hundreds of rocks in a handful of draw calls; a move rewrites one instance transform, additions/removals rebuild once per frame; objects are re-seated when the terrain under them changes. Drawn with the prop material (light, cloud shadows, touch wobble). Shapes for all seven kinds in `PropMeshLibrary` (`loose_template`): pebble, rock, boulder (two looks each), log, fruit, seed, strange object.
- [x] Touch: `WorldView.pick` knows both props and loose objects (loose objects rank above trees and buildings, per the picking priority); `InteractionManager` answers taps on them (`loose_kind`, wobble), `inspect()` reports them (`InspectReport.Subject.LOOSE`: lies on, weight, moved, ground height); menu and card wording in `UIText` (Pebble … Strange object; Light / Heavy / Very heavy).
- [x] **Weight is felt already:** `InteractionResponse.strength` (from `give()`) scales the wobble — a boulder barely stirs, a pebble jumps — lowers the pitch of the click for heavy things and makes a boulder a medium haptic pulse.
- **Verified:** 17 object/registry tests (specs, size, generated rock → rock or boulder, ground following, record round trip and rejection; add/move/remove with index and signals, refusals, shared tiles, populate once, untouched not saved, moved/removed/added survive a reload byte-for-byte, touch, bad data, older removed list, clear) + 4 world-setup tests (every generated rock becomes a loose object and nothing else changes; rocks and boulders; glade and ruin site clear for three seeds; deterministic) + 4 persistence tests (untouched costs nothing; moved/added/removed survive with the spatial index and touch system intact; pre-loose save; damaged data falls back to the seed) + 8 view tests (batching, ground placement, move without rebuild, add/remove, a shape for every kind, terrain change, picking and highlight, replacing the world) + 6 touch/wording/feedback tests. Suite: **449 passing**, no engine errors. Screenshots reviewed on Mobile and Compatibility.
- **Phone (Note20):** the existing world loaded with its rocks as loose objects; tap on a rock → `ROCK at (9, -4) -> rock_wobble`; long press → menu; 60 FPS, 49 draw calls (was 44–48).

### M3.2 HAND tool: grab / carry / drop — ✅ DONE (2026-09-30)
- [x] **Tools:** `scripts/interaction/tools/tool_base.gd` (`ToolBase` + `ToolBase.Context`: session, view, UI, touch radius), `hand_tool.gd`, `observe_tool.gd`, and `scripts/interaction/tool_manager.gd` (`ToolManager`, node `Main/Tools`): the active tool sees every gesture **first** and may keep it — a carried rock must not also pan the camera. What it does not keep goes on to the camera and the default touch handling (`Main._on_gesture`). `EventBus.tool_changed` on selection; `cancel()` on app pause.
- [x] **New gesture `HOLD`** (`GestureRecognizer`): fires once when one finger has rested for `grab_hold_ms` (200 ms), before `LONG_PRESS` (450 ms). It changes nothing else: releasing after it is still a tap, moving after it is still a drag. New `InputRouter.touch_ended` signal: lifting after a long press produces no gesture, so anything that must end when the finger lifts listens to this (also on focus loss).
- [x] **HAND tool** (default):
  - **Grab:** resting a finger on a loose object picks it up — it rises to hover height (heavy things hang lower), a soft **drop shadow** appears on the ground below (also when real shadows are off), a light pulse (medium for a boulder) and a quiet click. Only loose things can be picked up; a rock next to a tree is still reachable (picking is limited to loose objects).
  - **Carry:** the object follows the ground point under the finger (keeping its offset, so it does not jump), at `carry_speed` scaled by weight — **a boulder lags behind the finger**. It stays inside the box and always clear of the ground it passes over. The camera does not pan; near a screen edge (`edge_pan_margin`) the view **auto-pans** that way (`CameraRig.pan_world`, clamped, no rubber band).
  - **Drop:** letting go drops it where it is; a second finger or the app going to the background lets go too. A drop of 0.2 tiles or more counts as a move (`moved_count`, `placed_by_player`, saved).
  - **Holding still** opens the long-press menu **with the object still in hand**: dragging from there closes the menu and carries; lifting the finger puts it back.
- [x] `scripts/interaction/loose_object_system.gd` (`LooseObjectSystem`, node in `WorldSession` as `session.loose_system`) v0: `hold(id)` / `drop(id)`; a dropped object falls (gravity 22 tiles/s²) and comes to rest on the ground — or on the water if it floats — emitting `landed(id, impact_speed)`. Bounce, slide and collisions are M3.3. Saved objects are always at rest: one that is held or in the air is saved lying on the ground below it.
- [x] **Landing feedback:** dust (or a splash and ripples on water), a thud (or plip) whose loudness follows the impact speed and whose pitch follows the weight, and a pulse — a boulder gives the "stronger thud" and a medium pulse.
- [x] **OBSERVE tool:** a tap shows the inspect card instead of disturbing the thing; nothing can be picked up; nothing is announced to the world.
- [x] **Tool bar v0** (`scenes/ui/tool_bar.tscn`, `ToolBar` + `ToolButton`): HAND and OBSERVE, self-drawn glyphs (hand, eye), 140-unit targets, bottom centre in the Home button's row, the active tool lit. Only tools that exist are shown. The inspect card moved up to sit above the bar. *v0:* the bar stays at the bottom in landscape too (the bible's side bar comes with the HUD work).
- **Changed after the first phone test:** originally the long press made the hand let go, which left only a 250 ms window (200–450 ms) to start dragging — a player who waits to see the rock lift before moving would get the menu and a camera pan instead. Now the object stays in hand through the long press. The edge pan was also slowed (0.55 → 0.3 camera distances per second).
- **Also fixed:** a carry no longer counts as "exploring" for the first-time drag hint.
- **Verified:** gesture tests for HOLD (fires once, hold-then-tap, hold-then-drag, no hold for quick taps / early drags / after two fingers) + 8 drop-system tests (fall and rest, impact speed, higher hits harder, hold in mid-air, no jitter at rest, removed objects, stone sinks and wood floats, long frame) + 19 hand-tool tests on a generated world (grab, only loose things, pass-through when idle, follow, boulder slower and lower, stays in the box, clears higher ground, edge pan, edge push, drop and stats and save, put back, long press keeps it in hand, drag after a long hold, second finger, saving while carrying, removed while held, tool manager, switching tools, hand vs observe taps) + 11 in the main scene with real touch events (tool bar, choosing a tool, card above the bar, observing, **grab–carry–drop with a real finger**, menu while holding, slow player still carries, quick drag still pans, app pause and focus loss let go, splash in water) + rig, effects, feedback, wording and router tests. Suite: **494 passing**, no engine errors. Screenshots reviewed in portrait and landscape.
- **Phone (Note20):** the owner carried a rock by hand (from (9, -4) to (4, -8)); scripted: hold on a boulder → lifted with its shadow, menu opened with it in hand, drag → camera stayed put and the boulder followed and landed by the campfire, with pulses on grab and landing. 60 FPS, 70–73 draw calls at the settlement.
- **To judge by hand:** hover height and whether the finger hides the object, carry speed of boulders, the edge-pan speed.

### M3.3 Lightweight motion integrator — ✅ DONE (2026-09-30)
- [x] `LooseObjectSystem` is now the full integrator (custom, not RigidBody): only objects that are moving are stepped; objects at rest cost nothing and never jitter. `drop(id, velocity)`, `push(id, velocity)`, `hold(id)`; signals `landed(id, impact)`, `bumped(id, speed)`, `settled(id)`.
  - **Fixed time step**, so motion is identical at 30, 60 and 144 FPS (tested) and a hitch never teleports anything (at most 4 steps per frame). *Deviation:* the step is **60 Hz**, not the planned 30 Hz — at 30 Hz a rolling rock visibly stutters on a 60 Hz screen, and with so few moving objects the cost difference is nothing.
  - **Air:** gravity; on landing a bounce by kind (`bounce` in `LooseObject.SPECS`: a pebble skips, a boulder thuds) or rest.
  - **Ground:** friction by kind (`friction`: round stone rolls far, a log drags); a slope pulls a *moving* object downhill (`roll`), so a rock set rolling on a hillside **tumbles down the steps to the bottom** — a thud at every step — while a rock at rest stays put unless the slope is steep (more than one level per tile).
  - **Blocks:** a higher neighbouring block is a wall (bounce back, reported as a bump); a lower one is a drop (it falls off the edge and lands on the lower ground). Only lower neighbours count as slope — a wall never pushes things away before they touch it. The box's own walls keep everything inside.
  - **Things in the way:** the solid parts of props are circles (`PropData.collision_radius`: hut walls, campfire, ruin, a tree's *trunk*; bushes give way) and so are other loose objects. A moving object is pushed out and bounces; between two objects the momentum is shared by weight — **a rolling boulder sends a pebble flying and barely notices; a pebble bounces off a boulder**. Something flying over a low prop does not touch it; something dropped into a hut ends up outside it; a resting object shoved over a ledge falls.
  - **Water (until M3.5):** stone sinks slowly to the bed, wood rests on the surface, everything is slowed.
  - Objects in hand pass through everything.
- [x] **Throwing:** the hand tool remembers how the carried object is moving; letting go while it moves throws it that way (never faster than `throw_max_speed`), letting go after the finger rested just sets it down.
- [x] Bumps are heard (a click, louder when harder, lower for heavy things). Debug overlay line `moving N  step X ms`.
- [x] `SpatialIndex.FINE_CELL_TILES` (4): sessions bucket their index by 4x4 tiles instead of by chunk, so a search around one object looks at a handful of entities rather than a whole chunk's worth (picking benefits too).
- **Caught while building:** (1) an object landing on a steep slope came to rest there, because the slope was only looked at while it was already on the ground → the rest check now asks the slope where it ended up; (2) the first slope measure (the average of both neighbours) pushed a rolling rock *away* from a wall before it reached it, so it never knocked → only downhill neighbours count; (3) a resting object pushed over an edge by a neighbour hung in the air → it is woken and falls.
- **Verified:** 29 motion tests (fall and rest, bounces lower each time and by kind, impact by height, frame-rate independence, long frame, throw rolls and stops, wall, edge drop, **hillside roll to the bottom**, gentle slope holds, steep slope does not, box walls, hut bounce, bush and fly-over, pushed out of a hut, **boulder knocks pebble**, pebble off boulder, drop onto another, held passes through, shoved off a ledge, hold/push/remove, sinking and floating, rebind, a storm of 60 random throws all settle finite and inside, determinism, cost) + throw / set-down tests for the hand tool, a rock rolled into a hut in the main scene (knock heard, rests outside), feedback and prop-collision tests. Suite: **520 passing**, no engine errors.
- **Performance:** 200 resting + 10 moving at once: **0.47 ms per frame** on the PC (target < 1 ms).
- **On the generated world** (seed 12345): 46 rocks and boulders lie on slopes; nudged downhill they roll 4.3 tiles on average, the best ones 14 tiles down 8 levels in about 6 s, all come to rest, and some knock others on the way.
- **Phone (Note20):** a boulder carried toward a hut and let go mid-move rolled on, knocked against the hut and came to rest beside it; 60 FPS.
- **To judge by hand:** how far a thrown rock travels, and whether tumbling down a hillside feels right (speed, number of bounces).

### M3.4 Tree disturbance — ✅ DONE (2026-09-30)
- [x] **Shaking drops fruit.** Every tree bears a few things (`PropData.bears()`: 2–4 fruit on a broadleaf, 1–2 cones on a conifer, decided by its tile so it is the same everywhere). The first shake of a tree only rustles it; each further shake lets one go with a 60 % chance (`InteractionManager.SHAKE_DROP_CHANCE`, world RNG stream `interaction`, so the same world has the same luck) until the tree is bare. What falls is a real loose object (`FRUIT` / `SEED`): it drops from the crown, bounces, rolls, can be carried, thrown and inspected. *Placeholder as planned:* always in season, no regrowth (seasons M9, resources M7) — the limited stock keeps the world from filling up with fruit.
  - Shaking is the existing tap on a tree (and *Shake* in its menu); no separate hold gesture was added, since a resting finger already means "pick up" or "menu".
- [x] **Uproot** (the bible's *Remove*; Moderate): a new action in a tree's long-press menu — `InteractionManager.uproot(target)`. The tree is removed for good and its trunk is left lying as a `LOG` loose object (sized by the tree), toppling a little; leaves and earth fly, a low rustle and a medium pulse, then the thud of the log landing. `ACTION_REMOVE` is offered for trees only. "Gentle hands" is not involved: it guards *Major* interventions.
- [x] **Sparse per-prop state:** `PropData.taken` + `PropRegistry.touch(id)` — a generated prop that was changed is saved in full under `"changed"` (and restored in place of the generated one, also across chunk unload/reload); untouched props still cost nothing. Older saves without the list load unchanged. This is the mechanism M7's resource quantities will use.
- [x] Touch answers for the new things: a **log** knocks like wood (`log_knock`), **fruit, cones and other small things** are nudged and hop (`nudge`); the inspect card of a tree shows what it still bears ("3 fruit", "1 cone", "No fruit left").
- [x] `InteractionManager.bind(...)` now also takes the motion system, the id allocator and the world's RNG, so touches can bring new objects into the world; `InteractionResponse.dropped` lists them.
- **Verified:** 10 tree tests in the manager (first shake drops nothing, shaken bare gives exactly what it bears, fruit starts in the crown and comes to rest around the tree, conifers drop cones, same seed same drops, no spawning without the services, uproot leaves a log of the tree's size, only trees, inspect, nudge) + 5 prop-registry tests (what a tree bears, changed prop saved and restored byte-for-byte, changes survive chunk unload, removed is not also changed, bad records) + 2 persistence tests (fruit and the tree's loss survive a reload, with the RNG continuing; an uprooted tree stays gone and its log stays) + 2 in the main scene (Shake from the menu until a fruit lies on the ground and the card shows what is left; Uproot removes the tree from the picture and leaves a log that knocks) + effects, feedback and wording tests. Suite: **541 passing**, no engine errors. Screenshots reviewed on Mobile and Compatibility.
- **Phone (Note20):** eight taps on a tree near the settlement brought two fruit down (150 → 152 loose objects); its menu shows Inspect / Shake / Uproot / Look closer. (Uproot was not pressed on the owner's world.)

### M3.5 Water sim v0 (disturbance) — ✅ DONE (2026-09-30)
- [x] `scripts/environment/water_sim.gd` (`WaterSim`, node in `WorldSession` as `session.water`): cellular heightfield flow on `terrain_height + water` (B§10.3), fixed **10 Hz**.
  - **Only disturbed tiles are simulated** (an active set that grows where water moves and shrinks where it has settled). The generated river lies level, so it is at rest from the start: an untouched world costs nothing, and its river chunks stay unmodified and unsaved (tested on the real generated world).
  - **Conserved:** what leaves one tile arrives in another (two-phase update); nothing drains through the walls of the box. Each neighbour gets 0.2 of the level difference per step (≤ 0.25 for stability), never more than the tile has.
  - **A film clings to the ground** (`FILM` 0.02) and level differences under `MIN_DIFF` do not flow — a spill ends as puddles instead of spreading thinner for ever, and still water stays still.
  - **Soil soaks up thin water** (`soak_per_second`, the one sink: bible "soil absorption") and gets wetter; `soaked_total` keeps the books, so water + soaked is constant. River bed and rock do not soak.
  - **Budget:** at most 600 tiles per step; the rest wait for the next. The inner loop works on flat copies of the ground and water (no per-tile world lookups) — 40x faster than the first version.
  - `add_water` / `take_water` / `wake(tile)` (call after changing height or water yourself); water saved in mid-flow goes on flowing after a reload (the wet tiles of modified chunks are woken on bind).
  - `current_at(tile)`: the flow of the simulation, **plus the river's own gentle current** along its course and toward mid-channel (`WorldGenerator.river_direction` / `river_center_x`). *The river current is a placeholder*: the generated river holds still water; real inflow and springs arrive with hydrology (M9.3).
- [x] **Floating and drifting** (`LooseObjectSystem`): what floats is carried by the current, follows the river round its bends, and comes to rest once it has run aground (against a bank, the wall of the box, something in the water). Floating things rise and fall with the water level; stone sinks and stays.
- [x] **Disturbing water:** a tap on water (ripple, plip) now also pushes floating things nearby away from the finger.
- [x] **Scoop/pour prototype** — `WaterTool` (`tools/water_tool.gd`), **only in debug builds or with debug tools unlocked**: a third button in the tool bar (drop glyph). A tap on water scoops into a bucket, a tap on dry ground pours; water is never made or lost. Becomes the real WATER tool in M9.
- [x] **Drawing:** `WorldView.refresh_dirty_water` rebuilds the water mesh of changed chunks in turn, one every few frames (a rebuild costs 1.4–2 ms on the PC). Water shader: a thin film barely tints the ground, and shore foam is kept for real shores (isolated puddles used to turn into white squares).
- [x] **Double taps and tools:** a tool decides whether the second of two quick taps also acts as a tap (hand: yes — two quick taps on a tree shake it twice; water tool: yes) and whether it moves the camera (water tool: no). Found on the phone: quick pour taps were zooming the view.
- **Not done (planned wording):** "swipe adds ripples" — with the hand tool a drag pans the camera (see M2.3); it comes with the real WATER tool.
- **Caught while building:** (1) the first step function took 28 ms for 1,500 tiles → flat arrays and a smaller budget (0.73 ms per step with a whole flooded world unsettled); (2) a floating log came to rest in the very step it landed, before the current was looked at → the rest check asks where it ended up; (3) a log nosed into the first bend and stopped → the current steers toward mid-channel; (4) the chunk-redraw rotation skipped chunks; (5) an older test dug a hole next to the river and expected the water not to move.
- **Verified:** 14 simulation tests (still water left alone, spreads evenly, spill ends as puddles, runs downhill, basin fills level, **volume conserved over 1,000 steps**, stays in the box, soak accounting, take/add, digging lets water in, resumes after reload, bounded work, current follows flow, **the generated river is at rest and has its own current**) + 8 in-game tests (**log drifts downstream and runs aground**, stone sinks and stays, tap pushes floating things, floating things ride the level, water tool conserves, redraw in turns, poured water survives a reload and flows on, untouched world stays asleep) + double-tap test. Suite: **564 passing**, no engine errors. Screenshots reviewed on Mobile and Compatibility.
- **Performance:** PC: a spill of 6.0 by the settlement — 124 tiles active at most, worst step 1.0 ms, settled and soaked away in a few seconds; a whole world unsettled: 0.73 ms per step. **Phone (Note20):** scooped from the river and poured on the bank with the water tool: **1.66 ms per step at 148 active tiles** (target 1.5 ms), 55 FPS while flowing, 60 FPS again once still; the puddles soaked away in about 13 s.

### M3.6 Interventions & player history — ✅ DONE (2026-09-30)
- [x] `scripts/interaction/intervention.gd` (`Intervention`): `type` (`touch`, `grab`, `move_object`, `uproot`, `scoop_water`, `pour_water`), `tool`, `target` / `target_id`, `tile`, `position`, `magnitude`, `params`; filled in by the pipeline: `id`, `tick`, `applied`, `rejected` (reason), `severity` (GENTLE / MODERATE / MAJOR), `subject` ("tree", "water", "rock", ...), `response`, `recorded`.
- [x] **The single choke point** — `InteractionManager.apply_intervention(iv)` (B§14.6): validate → carry out through the owning system (props, loose objects, motion, water) → announce the world's answer (`responded`) → record in the history → `intervention_applied` signal and `EventBus.intervention_applied(id)`. Refusals carry a reason and change nothing (`nothing_there`, `not_a_tree`, `cannot_grab`, `not_in_hand`, `no_water`, `nothing_moved`, `unknown_type`, `gentle_hands`, `no_world`).
  - **All M2/M3 actions go through it:** `tap`, `uproot`, `grab` / `carry` / `release`, `scoop` / `pour` are conveniences that build the Intervention. The hand and water tools no longer touch the loose-object system, the registry or the water themselves.
  - Moving an object is **one** intervention, recorded when it is put down (distance carried, from/to, thrown or not); the grab goes through the pipeline but is not history on its own; putting something back where it was is no intervention. Severity per B§23.4: touch and moving small things Gentle; moving rocks, boulders and logs, uprooting, moving water Moderate. "Gentle hands" refuses Major ones (none exist yet).
  - Looking is not doing: long press, describe and inspect are not interventions.
- [x] `scripts/interaction/player_history.gd` (`PlayerHistory`, `session.history`, saved with the world under `world_state.history`): **counts** of everything by kind and by subject, running totals (distance moved, water moved, fruit shaken, objects thrown), and an append-only **log of what is worth remembering** — the first of each kind and everything Moderate or Major; fifty taps on grass are one entry and a count of fifty. Bounded (400 entries; firsts are kept). `stats()` gives the player statistics the world can already produce (B§27.3): total interactions, touches, objects moved / thrown, trees uprooted, fruit shaken, water moved, resources manipulated.
- [x] **`discoverable` flag** (hook for M4/M5): when an object the player moved comes to rest within `DISCOVER_RADIUS` (14 tiles) of the settlement it is marked (`LooseObject.discoverable`, saved); taken far away again, the mark is removed.
- [x] Stimuli for inhabitants and anomaly records (steps 3 and 5 of B§14.6) have their place in the pipeline but nothing to do until there are inhabitants (M4, M7).
- [x] Debug overlay line: `history N interventions  M remembered`.
- **Caught while building:** `scoop()` returned 0 after a successful scoop — the conditional expression read `applied` before the intervention was applied. The existing water-tool tests caught it at once.
- **Verified:** 13 pipeline tests (**every player action leaves its mark**: ground, water, tree, rock, move, scoop, pour, uproot — and looking leaves none; a touch as an intervention; refusals change and record nothing; gentle hands; move recorded on put-down with distance and severity; put back is nothing; discoverable near/far/taken away; water amounts; counted not logged; bounded log keeps firsts; statistics; history save round trip and broken data; unapplied/unrecorded) + tool tests now also assert the history (carry and drop, put back, observe leaves no trace, water tool) + 2 persistence tests (history saved with the world and numbering continues; a save without history). Suite: **579 passing**, no engine errors.
- **Phone (Note20):** three touches → `history 3 interventions  3 remembered`; after sending the app to the background (which saves), killing and relaunching it, the history was still there. (A hard kill without backgrounding loses what happened since the last save — as before; autosave cadence is M3.7 / M-save territory.)

### M3.7 Persistence — ✅ DONE (2026-09-30)
- [x] **Everything the player can do in M3 survives a relaunch, together.** Most of it was already saved by the sub-phase that introduced it (loose objects M3.1, changed trees M3.4, water in modified chunks M3.5, history M3.6); this sub-phase proves it end to end and closes the gaps:
  - loose objects: position, kind, `moved_count`, `discoverable`, `placed_by_player`; **always saved at rest** — what is held or in the air is saved lying on the ground below it;
  - trees: fruit taken, uprooted trees gone, their logs lying where they fell;
  - water: depths of modified chunks (as before) + **the water's books** under `world_state.water`: what the soil has soaked up and **the water the player is carrying**;
  - player history, id allocator and RNG streams (so that ids and dice never repeat after loading).
- [x] **Save format version 3** (`SaveManager.SAVE_VERSION`), with migration `2 → 3` (`SaveMigrations._v2_to_v3`): adds `loose`, `props.changed`, `history`, `water`; the rocks a version-2 world had removed (they were props then) are handed to the loose objects, so the glade is not littered again. Fixture `tests/fixtures/saves/v2_world.sav` is a **real** version-2 save, written by the last build from before loose objects (commit `04afa48`). The compatibility branch that `WorldSession` carried for such saves is gone — old formats are the migrations' business only.
- [x] **Carried water is part of the world** (`WaterSim.carried`): scooping adds to it, pouring takes from it and cannot pour more than is carried — through the intervention pipeline, not only in the debug tool. The water tool's bucket is now just a view of it (it used to be the tool's own number, lost on relaunch: scooped water vanished from the world).
- [x] **Saving soon after a change** (`SaveManager.note_world_changed`, driven by `intervention_applied`): the world is saved once the player has left it alone for `save_quiet_s` (6 s), or `save_max_wait_s` (40 s) after the first unsaved change if they never stop; any other save (background, close, autosave) settles the pending one. Before, a crash or a killed app lost everything since the last autosave (up to 120 s). Both values are in `SaveConfig`. Debug overlay: `(change pending)` on the save line.
- [x] A floating object that was saved adrift (and therefore at height 0) finds the surface again after loading and drifts on (`LooseObjectSystem.bind` → `on_water_changed`).
- **Caught while building — a real bug from M1.8 that M3.5 made reachable:** on loading, the trees, bushes and rocks of a *modified* chunk were generated from the chunk **as it is now**, not as it was made. The generator grows nothing on water, so **every tree and rock the player had flooded was missing after a relaunch** (and a tree on dug ground could change kind). `WorldSetup.populate_chunk` now generates the props of a modified chunk from the pristine land. Found by the end-to-end test (three rocks and the shaken tree were gone after pouring a puddle beside the huts).
- **Verified:** `test_save_loose_objects` (in the running game: carry a rock to the huts, shake fruit down, uproot a tree, scoop three times and pour once, close with a pebble still in hand → relaunch: every loose object, both trees, the log, the water, the carried water, the history, ids and dice are as they were, the pebble lies on the ground; a second relaunch changes nothing; and a change is on disk without closing the game) + version-2 fixture + 3 migration unit tests + carried water, soaked total, broken water data, floating log adrift, flooded/dug props (5 persistence tests) + 5 save-timing tests (saved after the quiet period; saved although the player never stops; any save settles it; looking and refused actions do not save; detaching forgets it). Suite: **594 passing**, no engine errors.
- **Numbers:** the M3 test world (3 modified chunks, 4 loose records, 7 history entries) saves as **5.0 KB in 9 ms** on the PC.
- **Phone (Note20):** the existing version-2 world (54 interventions by then) loaded through the migration; boulder carried to the fire → `save changed  34.0 ms  8277 B` six seconds later, by itself → app **force-stopped without going to the background** → relaunched: the boulder is by the fire. (The manual check "pick up rock → drop near huts → relaunch → still there".) 34 ms is two frames; it happens while the player is doing nothing.

### M3 — Completion summary
All seven sub-phases are done (M3.1–M3.7): loose objects as data, grab / carry / drop with the hand tool, the motion integrator (falling, bouncing, sliding, rolling, collisions), tree disturbance (shaking fruit, uprooting), the water simulation (flow, soaking, floating and drifting), the intervention pipeline with the player's history, and persistence of all of it. **594 automated tests.**
- **Automated tests named in the plan:** `test_loose_object_physics` → `test_loose_object_system.gd`; `test_water_conservation` → `test_water_sim.gd`; `test_save_loose_objects` → `test_save_loose_objects.gd`.
- **Performance:** 200 resting + 10 moving objects 0.47 ms/frame (PC; target < 1 ms); water 1.66 ms/step at 148 active tiles on the phone, 0.73 ms/step at the 600-tile budget on the PC (target < 1.5 ms on mid-range for 16 active chunks — met on the PC, borderline on the phone under a large spill, with 55 FPS while flowing).
- **Exit criterion** — *"The player starts experimenting naturally. Observe a tester: do they try throwing things into water/down hills without being asked?"* — is a hands-on judgement: **pending the owner's verdict**.
- **Still to judge by hand:** carry hover height and finger occlusion, boulder lag, edge-pan speed, throw distance and tumbling on hillsides, spill pace and river current, whether Uproot wants a confirmation.
- **Not in M3 on purpose:** the water tool is debug-only (the real tools come with M9); stimuli for inhabitants and anomaly records have their place in the pipeline but nothing to do before M4 / M7; water and motion tuning values are code constants until they need to be tuned in config.

### M3 — Tests & checks
**Automated:** `test_loose_object_physics` (drop lands on correct tile height; slide on slope ends at bottom; resting is stable for 100 steps), `test_water_conservation` (total volume constant ± ε over 1,000 steps without sources/sinks; flows downhill; no negative depth), `test_intervention_pipeline` (every tool action creates history entry), `test_save_loose_objects`.
**Manual:** pick up rock → drop near huts → relaunch → still there; roll boulder down a hill; drop log in river → drifts; shake tree → fruit falls.
**Android:** grabbing feels precise with a finger; edge auto-pan works; no jitter at rest.
**Performance:** 200 resting objects + 10 moving: < 1 ms sim/frame; water step < 1.5 ms on mid-range for 16 active chunks.
**Exit criteria:** *The player starts experimenting naturally.* Observe a tester: do they try throwing things into water/down hills without being asked?
**Risks:** Physics jitter → sleep thresholds and snapping; water instability → clamp flow per step to fraction of difference (≤ 0.25).

---

## M4 — FIRST INHABITANTS

**Goal:** The world feels inhabited: 5–20 people (start with 6–8) with goals, not random wandering. (P:M4, S§13–14, S§54–55, B§13)
**Depends on:** M3. **Split into 6 sub-phases.**

### M4.1 PersonData & registry — ✅ DONE (2026-09-30)
- [x] `scripts/people/person_data.gd` (`PersonData`, RefCounted) with **all canonical fields** of B§13.1. Alive now: id, names, `birth_tick` (age and life stage are always derived from the clock — never stored), sex, health, traits, occupation, skills, household / home / settlement, parents / children / partner, position (`position` tile + `sub_tile_offset` + `facing`), flags, appearance. Stubs for later milestones — needs, mood/stress, memories, beliefs, knowledge, goals, `current_action`, workplace, injuries, conditions, significance — exist and are **saved empty**, so the format does not change shape when they come alive. `sim_tier` is runtime only. `from_dict` refuses records without an id or a place and repairs everything else.
- [x] `scripts/people/person_registry.gd` (`PersonRegistry`, `session.people`): `add / get_person / remove / move`, kept in step with the spatial index (`KIND_PERSON`); iteration in id order, `in_settlement`, `in_household`, `living_in(building)`, `in_tier`, `household_ids`; names in use; `to_dict / from_dict`. People are saved in full (nothing about a person is regenerated).
- [x] `scripts/people/traits.gd` (`Traits`): the 12 axes of B§13.2 — nine opposites (−1…+1) and three amounts (0…1); `generate(rng)` (bell-shaped: most people middling in most things, nearly everyone standing out in something), `inherit(mother, father, rng)`, `sanitized`, `strength`, `describe_top(traits, n)` → word ids, strongest first, only what is pronounced (and never a lack: nobody is "unintelligent"). Wording in `UIText.TRAIT_WORDS` / `trait_words()`.
- [x] `scripts/people/phonology.gd` + `name_generator.gd`: a **phonology** per culture (which onsets, vowels and codas it uses, how syllables close, how women's and men's names tend to end, a family-name suffix) as a pure function of `seed ⊕ "culture:<id>"`; `NameGenerator` makes given names, family names and plain words (for the M17 lexicon) from it, avoids names in use, refuses the unpronounceable and a short list of rude syllables. Example (seed 12345): *Fubrudu, Skounil, Thahagou, Lamou Skadash · Duthou, Dounul, Akou Fash · Giskash Brudash*.
- [x] Occupation defs v0: `OccupationDef` resource + `OccupationLibrary` (`session.occupations`, loaded with `ResourceLoader.list_directory` so it also works exported); `data/occupations/` — **forager** (youths and adults), **woodcutter**, **builder** (placeholder: nobody starts with it), **child**, **elder**. Each has the life stages it is open to, a starting share and trait weights; `choose()` samples by fit × share ÷ how many already do it (never argmax).
- [x] **Starting band** (`scripts/people/starting_band.gd`, dice: the world's `people` stream): 6–8 people in 2–3 households, one hut each — a couple with children, a couple with an elder parent, and (with three households) someone on their own or a young couple. Parents are old enough for their children, children take after their parents (traits, skin), partners are linked both ways, every band has its young and its old and at least one forager and one woodcutter. Everyone stands on a free, dry tile by their own hut, turned to the fire. Sizes and ages of life are in `data/configuration/people_config.tres` (`Config.people`).
- [x] The settlement gets an id (`StartInfo.settlement_id`) when its people arrive.
- [x] **Save format version 4**: people under `world_state.people`; migration `3 → 4` marks worlds from before people, and such a world gets its band on loading (deterministically). A world whose people are all gone stays empty; an unusable people record brings a new band rather than an empty world. Fixture `tests/fixtures/saves/v3_world.sav` (written by `bc5f82b`).
- [x] Debug overlay: `people N in H households (children, youths, adults, elders)`; the band is listed in the log when it arrives.
- **Deviations:** people are saved now rather than in M4.6 (they are created from dice, so an unsaved band would be different people on every launch); M4.6 adds the current action and path. No separate household or settlement entities yet — a household is the people who share a `household_id`. `TimeConfig.ticks_per_year()` added (calendar proper is M6).
- **Not visible yet:** people are data only until M4.2 draws them. They are in the spatial index but cannot be picked (no pick shape until they have a body).
- **Caught while building:** men's names ended the women's way too often when a culture's "plain" vowels included a diphthong (*ia* ends in *a*) — endings are now chosen from single vowels only; a family name of the main test world read rudely, so the list of refused syllables grew; the band could be placed on a tile where a rock lies (one the player left by the fire) — such tiles are now taken.
- **Verified:** `test_traits` (8), `test_name_generator` (10), `test_person_data` (14, incl. the plan's `test_person_serialization` and the registry), `test_occupations` (6), `test_starting_band` (12: household plans over 400 dice states, six worlds checked person by person, families, determinism, save round trip, empty world, damaged data, stale id allocator, the version-3 fixture, relaunch of the running game) + migration and config tests. Suite: **646 passing**, no engine errors.
- **Phone (Note20):** the existing world (version 3, 65 interventions) loaded through the migration and its first band arrived — 7 people in 3 households (*Dodu, Fushak and Wuzu Flak · Ditreiwu, Futri and Flatreik Trak · Mitra Dazak*), **the same people the PC makes for that seed**; occupations load from the exported data; after backgrounding (save: +1.4 KB for the seven) and a relaunch, the same seven were loaded, no new band. 60 FPS, nothing visible yet.

### M4.2 People rendering (no heavyweight node trees) — ✅ DONE (2026-10-01)
- [x] `scripts/rendering/entity_view_pool.gd` (`EntityViewPool`): lends a view node to an entity id and takes it back; views are made on demand (up to a cap), prepared once, hidden when returned and reused. It knows nothing about people (animals will use it too).
- [x] `scenes/people/person_view.tscn` + `scripts/rendering/person_view.gd` (`PersonView`): body, carried thing, soft blob shadow. `bind` / `dress` / `advance` / `unbind`. **Follows its person smoothly** (critically damped, never overshoots, ~0.2 s behind; jumps instead of gliding when the person is suddenly more than 3 tiles away), turns the way it walks and back to the way the data faces when it stands; the walk amount comes from how fast the view is actually moving. A view at rest costs nothing until its person moves.
- [x] **One body for everyone** (`scripts/rendering/person_mesh_library.gd`, built in code like the props: 162 triangles, 1 unit tall, facing +X) + `assets/shaders/person.gdshader`: vertex colours are *masks* (cloth / skin / hair + shade), the actual colours are **per-instance uniforms** — so all people share one mesh and one material. In the vertex shader: breathing, **walking** (bob, roll, legs and arms swinging against each other — limb side and reach are in the UVs), leaning into the walk, an **elder's stoop**. Cloud shadows as on everything else. Eyes and a face side show which way someone looks.
- [x] Told apart by (B§28.4): clothing colour (6, saturated), skin (6), hair (5; elders grey), height and build from `appearance`, **age** (children grow from 0.42 of adult height; elders a little shorter and stooped), and **what they carry** — data-driven: `OccupationDef.accessory` (woodcutter: axe on the shoulder, forager: basket on the back, elder: staff).
- [x] `scripts/rendering/people_view.gd` (`PeopleView`, in `WorldView`; `world_view.show_people(...)`): every frame, whoever is in sight (camera pyramid + margin) and simulated in full (tier ≥ 3) has a view; whoever leaves gives it back. Views are re-dressed when their person grows a year older or changes work (checked every 16 frames).
- [x] **Far zoom:** markers — a MultiMesh of billboards (one draw call), a disc in the person's clothing colour with a dark rim, **the same size on screen at any distance**, drawn over everything (found even behind a tree). They fade in from the point where a person is about 36 viewport units tall and are full at 22; bodies are dropped below 11 — there is no distance at which someone is neither.
- [x] Reduced motion calms breathing and walking (`accessibility/reduced_motion`). Debug overlay: `drawn: N bodies (V views made) M markers P%`.
- **⚠ resolved:** instance uniforms work on **both** renderers (Mobile and Compatibility) in 4.7 — verified by screenshot, colours identical.
- **Deviations:** figures are **0.5 units tall**, larger than the placeholder huts would have them (doorway 0.30): at true scale they were specks at the home view. They read like figures on a game board; buildings can be sized to them when buildings are made (M10). The accessory is a separate mesh (prop material), so it does not bob or lean with the body. The blob shadow is one small draw per person (to be batched when crowds arrive, M21).
- **Not yet:** people cannot be picked — a finger on a person touches the ground under them. Selection, the person card and touching people are M5. Nobody walks by themselves until M4.3 / M4.4 (the walk is tested by moving people in data).
- **Caught while building:** MultiMesh instance transforms cannot be read back headless (the view keeps its own copy for queries); the first thresholds were in screen pixels of the capture, not viewport units, so markers appeared far too late; the per-frame cost for 60 standing people was 0.64 ms (in-sight test through `world_to_screen`, every view advanced every frame) → 0.30 ms with the view pyramid worked out once per frame and views at rest skipped.
- **Verified:** `test_people_view` (21): the body mesh (triangle budget, masks, limb UVs), palettes and carried things against the data, growth and stoop, the pool, a view looks like its person (colours, size, accessory, place, facing), follows smoothly without jumps or overshoot and is seen walking, snaps when far, changes with its person, everyone in sight drawn, views returned out of sight and reused, markers from far away (count, place, constant screen size), fade with no gap, people added and removed, tiers, another world, reduced motion, not pickable, the marker texture, a crowd of 60 (0.30 ms/frame on the PC) and more people than views, the running game. Suite: **667 passing**, no engine errors. Screenshots on Mobile and Compatibility at closest zoom, home, mid, far and whole box, and of someone walking: identical apart from real shadows.
- **Phone (Note20):** the band stands around the fire — 7 bodies at the home view, **60 FPS**, 109 draw calls (budget 250); on the opening view of the whole box, 7 markers. (One of them stands beside the boulder left by the fire: that band was placed before the rule about tiles with rocks.)

### M4.3 Pathfinding — ✅ DONE (2026-10-01)
- [x] `scripts/people/pathfinder.gd` (`Pathfinder`, `session.pathfinder`): the world as a graph of tiles — every tile a point, neighbouring tiles joined **where a person can step from one to the other**.
  - **Cannot be stood on:** deep water (deeper than a person can wade) and buildings (hut, campfire, ruin).
  - **A step** needs nearly level ground: at most one height level (`WorldSetup.MAX_STEP_LEVELS`); more is a cliff. A **diagonal** step also needs both tiles it passes between to be passable — nobody cuts the corner of a hut or the lip of a cliff.
  - **Weights** (slower, so gone around when that is quicker): wading ×4, a tree +3, a bush +1.5, a slope +0.35, **a boulder or log lying on the tile +7**, terrain (road 0.7, sand, rock, mud 1.6, snow 1.7).
  - **Follows the world tile by tile:** ground changes (`WorldData.ground_changed`, new), moving water (`WaterSim.tiles_changed`), props (`chunk_changed`, compared against what the graph was built from), boulders and logs being moved. Only tiles whose state actually changed touch the graph; a test checks that 120 random changes leave exactly the graph a fresh build gives.
  - `find_path(from, to)` → tiles, both ends included; **empty if there is no way**; to something that cannot be stood on (a hut, the middle of the river) it leads to the nearest tile beside it (within 3). Also `can_stand`, `can_step`, `weight_at`, `speed_factor`, `path_cost`, `is_reachable`, `standable_near` — always answered for the world as it is now.
  - **Queue with a budget:** `request(from, to, on_done)` / `cancel` / `serve(budget_usec)` (oldest first; at least one per call, so the queue cannot stall); `PerfConfig.path_budget_ms_per_frame` = 1 ms. **Cache** of answers (256, also of "no way"), dropped by a version number whenever the graph changes.
- [x] **Movement** — `scripts/people/movement_system.gd` (`MovementSystem`, `session.movement`): `walk_to(id, tile, offset)`, `gather(ids, tile)` (each to a tile of their own around the spot), `stop`; signals `arrived` / `blocked`. People first wait for their way, then advance along it tile centre to tile centre, at `speed_of(person, tile)` = `walk_tiles_per_minute` (0.45) × stage of life (child 0.7, youth 0.95, elder 0.65) × health (a half at worst) × the tile's `speed_factor`. They face the way they go. If the world changes ahead of them they look before stepping: a closed way is found again (up to 3 times), then given up (`blocked`).
  - Time is **game minutes in fractions**: the session steps movement every frame with `GameClock.last_advance_minutes` (new), so people move evenly at any frame rate and any game speed, and stand still when the game is paused. The result does not depend on the size of the time step (tested: steps of 0.05, 0.5 and 3 minutes end at the same place).
  - Speeds are in `people_config.tres` (`Config.people`).
- [x] Views interpolate (M4.2): at normal speed a walk is 0.9 tiles per second on screen, which is exactly the view's full stride.
- [x] **Call tool** (prototype, debug builds only, the flag in the tool bar): a tap calls everyone to that spot — the way to try pathfinding by hand until people decide for themselves where to go (M4.4). Not an intervention; leaves no trace in the history.
- [x] Debug overlay: `paths: N walking  Q queued  F found  C from cache  last / serve ms`.
- **⚠ resolved / deviation:** `AStar2D` instead of `AStarGrid2D`. The grid class can only make whole tiles solid or heavy; here whether a step is possible depends on the *pair* of tiles (the height difference), which needs a graph with its own connections. Same engine code underneath, and the graph is updated in place rather than rebuilt per chunk.
- **Deviations:** trees and bushes slow a way but do not close it (a dense wood must not wall anything in); small loose things (pebbles, rocks, fruit) are stepped over. Where someone is walking to is runtime state — after a relaunch people stand where they were (resuming is M4.6, with the action system).
- **Not yet:** walkers do not avoid each other (they pass through one another); nobody walks without being called.
- **Caught while building:** questions like `can_stand` answered from the graph as it was before pending changes — they now bring the graph up to date first; building the graph cost 83 ms per world on the PC (and 20 s more for the test suite) → 39 ms by reading the chunk arrays directly.
- **Verified:** `test_pathfinder` (25, on hand-made worlds: straight and diagonal ways, **avoids deep water, empty for unreachable, respects buildings**, corners, wading only when it saves a long walk, ends beside what cannot be stood on, trees/bushes/boulders/logs, terraces, cliffs and ramps, rough ground, tile-by-tile updates, incremental = fresh build, cache, queue and budget, withdrawing, standing places, rebinding) + `test_movement` (18, in the generated world: the graph of the real world, the river cannot be crossed, timings, walking and arriving on the very spot, duration = cost of the way, step-size independence, facing, young/old/sick, around huts, no way, stopping and changing one's mind, a way that closes and reopens, one that closes for good, gathering, leaving the world, 20 walkers, the running session incl. pause, a new world in the same session) + the call tool with a real tap in the running game. Suite: **711 passing**, no engine errors.
- **Numbers (PC):** graph of the 64×64 world built in 39 ms; a way across the box 0.26 ms on average (longest 43 tiles); 20 requests answered in one frame (0.4 ms); 20 walkers 0.20 ms per frame (target: path requests < 1 ms/frame).
- **Phone (Note20):** the flag tool, then a tap south of the huts: all seven set off, walked around the huts and trees and stood around the spot, each on their own tile; 7 ways found at 0.05 ms each, **60 FPS**, 118 draw calls.

### M4.4 Needs & utility brain — ✅ DONE (2026-10-01)
- [x] `scripts/people/needs.gd` (`Needs`): Hunger, Thirst, Sleep, Social, Purpose, Safety — each **how well it is met** (1 = fully), so urgency is `1 - value`. `decay(person, minutes, config, stage, state)`: rates per game minute from `data/configuration/needs_config.tres` (`Config.needs`); work makes hungry, thirsty and tired faster, sleep slows hunger and thirst; children and elders differ; the sociable miss company sooner, the ambitious purpose. `satisfy`, `urgency`, `most_urgent`, `mood`, `stress`, `initial(rng)` (a band does not get hungry all at once), `sanitized` (people saved before needs existed get them, the same every time).
- [x] `scripts/people/ai/activity_def.gd` + **`data/activities/*.tres`** (`ActivityLibrary`, `session.activities`): `id, base, need_weights, trait_weights, hours (24 factors, interpolated), requires, life_stages, repeat_after_minutes`. Eight activities: **eat, drink, sleep, work, socialize, explore, go_home, play**. A need says nothing while it is mostly met and then counts with the square of its urgency (`ActivityDef.voice`).
- [x] `scripts/people/ai/brain.gd` (`Brain`): `score` = hour factor × (base + needs + traits) − having just done it; `decide` draws among the **best three** with p ∝ exp(score / temperature) — temperature per person, from their creativity — and only among what is worth doing at all. **Hysteresis:** someone busy keeps at it unless something else beats what they are doing by 0.25 — measured against the score it was *begun* with, so a meal is finished although the first bites took the edge off the hunger; a sleeper needs more still. Returns a `Decision` with the reason ("hunger", "routine", "nature") and every score (for the M4.6 inspector).
- [x] `scripts/people/ai/action_step.gd` + `actions/`: steps are **plain data** (`{"type": "eat", "minutes": 25.0, "elapsed": 3.5, ...}`) in `PersonData.current_action`; the classes hold no state. `walk_to` (only the destination is saved; the way is found again after a load), `eat` (at the fire: the band's food until there are stores, M9), `drink` (at the water's edge, within reach), `sleep` (at home, **indoors: not drawn**; until rested, and once asleep at night until one's own hour to rise), `work` (woodcutter at a tree, forager at a bush, elder at the fire — and children's play; a visible, audible stroke every two game minutes), `socialize` (stand with someone, turned to each other; both gain, the visitor more), `rest`.
- [x] `scripts/people/ai/planner.gd` (`Planner`): turns a decision into steps; `can(requirement)` for "home / food / water / work / company". `scripts/people/ai/places.gd` (`Places`): where food, water, home, work, company and somewhere new are — answered from the world as it is. Work is at one of the nearest few trees or bushes, not always the same one; exploring prefers where nobody of the band has been and only goes where there is a way.
- [x] `scripts/people/ai/behavior_system.gd` (`BehaviorSystem`, `session.behavior`): needs run down; whoever has nothing to do decides and plans; steps are carried out; a finished or failed plan leads to a new decision; what failed is not tried again for 30 game minutes; someone busy looks up every 15. People live in **whole game minutes, spread over the frames of a tick** (walking stays smooth). Signals `activity_changed`, `worked`. `set_plan`, `think`, `call_to`, `enabled` (the freeze toggle for M4.6).
- [x] **Hungry example works** (`test_plan_hungry_home_food_eat_work`): at home and hungry → walks to the fire → eats until full → goes to a tree → works.
- [x] What is seen: poses (`PersonData.pose`, runtime) drive a new `busy` motion in the person shader — arms going at work, gentler when eating or talking; sleepers are indoors and not drawn (no body, no marker); a working woodcutter makes the tree shiver and knock, a forager the bush rustle (quiet, at most three a second, only when in view).
- [x] The call tool now goes through the behaviour system: people come, stand about for twelve game minutes, then go back to their own business.
- [x] `GameClock.hour()` and `TimeConfig.start_hour` (a world begins at 06:00); wording for activities and reasons in `UIText` (`activity_phrase` → "Eating — hungry"); debug overlay: `time HH:MM  doing: work 4, eat 1, ...  (decisions, ms/frame)`.
- **Deviations:** Explore and GoHome are activities built from `walk_to` + `rest`, not steps of their own. **Play** was added (children had nothing that gave them purpose, and wandered). **Ages of life now follow the bible** (§9.1): youth from 12, grown at 16, elder from 48 (was 13 / 18 / 55). Food is not consumed and work yields nothing yet (resources are M9). There is no day and night to *see* until M6 — people go to bed around seven in the evening and the huts are empty of visible people until five or six, in broad daylight.
- **Caught while building:** a lambda in the AI context that called back into the behaviour system kept both — and with them every world a test had opened — alive for ever (165,000 leaked objects at exit): work strokes are now collected as data. People dropped meals half eaten (the score of what one is doing falls as the need is met): the score a plan was begun with is kept. People ate, drank and napped because they *could* (everything scored low, so the dice chose anything): needs are silent until a quarter urgent, and what is not worth doing is not in the draw. Sleepers got up at one in the morning, rested, and went to work: sleep lasts till morning, and going home at night means going to bed. Children's purpose ran to zero. Exploring set out for places with no way to them. On the phone the first build cost 1.5 ms per frame for seven people → 0.2 ms by living in whole minutes.
- **Verified:** `test_needs` (15, incl. **`test_needs_decay`**), `test_behavior` (27, incl. **`test_brain_selects_eat_when_hungry`**, **`test_brain_variety`** (1,000 decisions: a favourite, never the only choice), **`test_plan_hungry_home_food_eat_work`**; each pressing need has its answer; the world's own dice; creative people less predictable; hysteresis; the hour bends without ruling; what is impossible is not chosen; drinking, sleeping until rested, waking only for something pressing, company good for both, exploring, everyone's own work, a tree gone under the axe, giving up for a while, standing about without spinning, broken plans, freezing, **a world saved in the middle of a meal, a walk and a sleep goes on from there**, people from before needs, **a whole day of the band** — everyone ate, drank, slept, workers worked, nobody ran out of anything or stood where nobody can stand, the band asleep at two in the morning, nobody idle, 14–20 changes of activity each — and 20 people within the AI budget) + poses and sleepers in `test_people_view` + the running game and work effects in `test_tools_in_game`. Suite: **757 passing**, no engine errors, no leaks.
- **Numbers (PC):** 20 people: AI 0.04 ms per frame on average (target < 0.5), worst frame 2.5 ms (a frame in which several people plan — budgets are M4.5); a whole day of 8 people: 0.32 ms per game minute, 837 decisions, 112 ways found.
- **Phone (Note20):** the band of the existing world (saved before needs) woke up and went about its day: working at trees and bushes with leaves falling, walking to the river, eating at the fire. **60 FPS**; AI 0.19–0.25 ms per frame on average for 7 people.

### M4.5 Simulation manager & tiers v0 — ✅ DONE (2026-10-01)
- [x] `scripts/simulation/simulation_manager.gd` (`SimulationManager`, a node of `WorldSession`: `session.simulation`). The session calls `advance(delta)` once per frame; per frame: the clock turns the frame into game time (ticks = game minutes) → people whose turn it is live the time that has built up for them → queued paths are answered → walkers are moved on.
  - **Staggered:** everyone has their own place in the tick, so a band does not take its turn in one frame (20 people at normal speed: at most a handful per frame, most frames nobody).
  - **Budgeted, with deferral:** `SimConfig.ai_budget_ms_per_frame` (1.5 ms) for people living, inside `PerfConfig.sim_budget_ms_per_frame` (4 ms) for the whole; when the time is used up, whoever has not had their turn comes first in the next frame (at least one person lives every frame, so nothing can stall). **Nobody ever loses time** — minutes build up and are lived in one larger step — so the simulation degrades to coarser steps, never to slow motion. Tested with a budget of zero.
  - **Think cadence by tier** (B§9.3): tier 4 every tick, tier 3 every 3, tier 2 every 15 (`SimConfig.think_ticks_*`). A look up is a *glance*: everything is weighed up again only if a need has grown noticeably louder, if enough time has passed (every 5th look), if the person was prompted (`BehaviorSystem.prompt` — the hook for perception, M5), and only if anything could matter more than what they are doing at all (`ActivityLibrary.ceiling`).
  - **Patient steps:** someone at something steady takes fewer, larger turns (asleep: every 10 ticks, resting: 4, working: one per stroke); someone walking, or in the player's focus, every tick. Given something new to do (called, woken, prompted), they take their turn in the next frame (`hurry`).
  - Walkers are moved every third frame, not all in the same one (`MovementSystem.step_in_turns`); their views glide in between.
- [x] `scripts/simulation/tier_manager.gd` (`TierManager`, `session.simulation.tiers`): **tier 4** = whoever the player has selected (`EventBus.person_selected`; the focus holds two, the oldest gives way), **tier 3** = everyone else up to a cap (`tier3_cap` 64 / 32 on low-end), **tier 2** = whoever is beyond the cap, furthest from where the player looks (main feeds the camera pivot) — living every 15 ticks, losing nothing. Tiers 1 and 0 (abstract, dormant) have their numbers and their place in the interface; simulating them is M21. `PersonData.sim_tier` is runtime only; tier 2 people are still drawn.
- [x] `data/configuration/sim_config.tres` (`Config.sim`): caps, cadences, the AI budget, `patient_steps`.
- [x] `BehaviorSystem` no longer schedules anything: `live(person, minutes, think_every)` is called by the manager; `step(minutes)` remains for tests and wherever there is no frame to keep.
- [x] Debug overlay: `sim A ms/frame of 4.0 (live / paths / move)  worst  deferred  tiers 4:n 3:n 2:n`, decisions and how many looks needed none.
- **Made cheaper on the way** (the phone showed what the PC hid): the scheduler keeps arrays and absolute times — a person who is not due costs one comparison per frame; a decision works out the hour, the stage of life, the voices of the needs and the requirements once instead of per activity, and activity weights are compiled to arrays; who is up and about is counted once per tick; the stage of life once per game day; the nearest places of work are remembered until a prop changes (`PropRegistry.version`); the shoreline (from the pathfinder's own arrays) is looked for when the world is opened and again only when water has moved; exploring no longer asks the pathfinder about every candidate (a place with no way to it is found out by setting off); walking works out speed and heading once per stretch.
- **Caught while building:** the offset that staggers people was counted as time lived (up to a whole interval of phantom minutes — 15 for tier 2); "every tick" became every second tick, because turns come a hair short of whole minutes (frames do not divide them evenly); a prompted person could still skip the weighing up; a sleeper given something new to do would have waited out their ten ticks.
- **Verified:** `test_simulation_manager` (17): frames become ticks at every speed and pause; everyone lives all the time that passes; turns within a tick; great speed; **a budget of zero: one person per frame, everyone in turn, no time lost**; the frame stays within the budget; focus by selection, two at most, gone with the person; in focus → a look every tick, otherwise every third; a look is a glance unless something changed; nothing weighed up when nothing could matter more (and the ceiling really is one, over 300 random people and hours); the cap and where the player looks; coarser tiers in larger steps; patient steps and hurrying; walking in turns covers the same ground; the session runs on the manager (freeze, new world). Suite: **773 passing**, no engine errors.
- **Numbers (PC):** 20 people: 0.036 ms per frame on average (target < 0.5), worst frame 0.56 ms, no frame over the 4 ms budget, nobody deferred; a whole day of 8 people: 583 decisions (2,630 before the glance), 0.35 ms per game minute; 20 walkers 0.13 ms per frame.
- **Phone (Note20, debug build):** 60 FPS throughout; sim 0.4–0.55 ms per frame for 7 people by day (live 0.2 / paths 0.03 / move 0.2–0.27), 0.2 at night with everyone asleep; one frame of ~20 ms while the world is opened (everyone's first plan). The phone's figures are 30–40 times the PC's for the same work — far more than its speed accounts for (an empty call costs 30 µs there): at this light load the CPU is evidently clocked down, so the milliseconds overstate the cost; the frame time is what counts, and it does not move.

### M4.6 Persistence & debug — ✅ DONE (2026-10-01)
- [x] **People are saved in full and resume where they were.** A person's record holds who they are, their needs, what they are doing and why (`current_action`: the plan, the step, how far along), and when they last did what (`activity_log`). The **path target** is part of the walking step; the way itself is found again after loading. What is not saved is rebuilt when a step is taken up again (pose, being indoors, the walk).
  - **Nobody is saved behind their time:** before the world is written, everyone lives the minutes that had built up for them (`SimulationManager.settle`, from `WorldSession.to_dict`), without the sights and sounds of it. A frozen world is saved as it stands.
  - **What the band knows of the world** (the places it has been) is saved under `world_state.behavior`.
- [x] **Save format version 5** with migration `4 → 5`. Fixture `tests/fixtures/saves/v4_world.sav` is a real version-4 save written by M4.3 (`2157016`): eight people in mid-walk who have no needs and no plans yet — they get needs on loading (the same every time) and start living. A test now loads **every** older version (1–4, each written by the build of its day) and checks that its people live.
- [x] **AI inspector** (`scripts/debug/inspectors/ai_inspector.gd`, part of the debug overlay): with the overlay up, **a tap on a person** shows who they are, their needs as bars, what they are doing and why, the steps of the plan with the current one marked and how far along it is, the walk, and **the scores of the last weighing up** (the chosen one starred, the impossible ones dashed), refreshed four times a second. The inspected person is ringed and is in the player's focus (tier 4). Without the overlay people still cannot be tapped (M5).
- [x] **Commands** (buttons on the inspector): **Freeze AI / Unfreeze** (nobody lives, nobody walks, the clock runs on; they go on where they were), **Spawn** (a newcomer where the player is looking — `WorldSession.spawn_person`, `PersonFactory.newcomer`: a stranger with a name in the settlement's tongue, a household of their own and the roof with the fewest under it), **Think** (weigh everything up now), **Kill** (`WorldSession.kill_person`: out of the world; who they were to others is not forgotten; `EventBus.person_died`).
- [x] **Overlay counts:** people by stage of life, bodies and markers drawn, time of day and what everyone is doing, decisions and looks that needed none, **active AI**, tiers, sim ms per frame by part, **paths per frame**, walkers, queue.
- [x] **Stranded people are rescued** (the M4 risk "stuck agents"): someone who cannot get anywhere because they stand where nobody can stand (the water rose around them) is put on the nearest firm ground, with a warning in the log. Someone who merely has no way to where they want to go is left where they are.
- **Caught while building:** catching everyone up before a save announced their work — tree shakes and sounds played into a scene that was being closed (an engine error): strokes are discarded while settling. "Frozen" people were still walked on by the movement system: frozen now means frozen. A newcomer was put on the same tile as the one before.
- **Verified:** `test_people_persistence` (9): the version-4 fixture (migrates, same eight people in mid-walk, needs the same every time, they start living, saved as version 5 with the old file kept), every older version loads and lives, what the band knows is saved, nobody saved behind their time, **the running game resumes where it was** (same people, same activity and reason, same step as far along, same place, same needs; whoever was walking walks on), spawn, kill (incl. an empty world), stranded. `test_ai_inspector` (10): the text, bars and steps, the inspector comes and goes with the overlay, **a real tap on a person inspects them** and a tap beside them is an ordinary tap, no tapping people without the overlay, sleepers cannot be tapped, freeze and thaw, spawn / think / kill, live refresh and touch blocking, the overlay counts. Suite: **792 passing**, no engine errors. Inspector checked by screenshot on the PC in a phone-shaped window.
- **Phone (Note20):** checked on 2026-10-01 with the M5.3 build — see M5.3 (inspector, Freeze / Spawn / Kill, relaunch resumes at the same tick).

### M4 — Completion summary
All six sub-phases are done (M4.1–M4.6): people as data and the starting band; people on screen; pathfinding and walking; needs and the utility brain; the simulation manager and tiers; persistence and the debug inspector. **792 automated tests.**
- **Automated tests named in the plan:** `test_person_serialization` (`test_person_data.gd`), `test_needs_decay` (`test_needs.gd`), `test_brain_selects_eat_when_hungry`, `test_brain_variety`, `test_plan_hungry_home_food_eat_work` (`test_behavior.gd`), `test_pathfinder` (`test_pathfinder.gd`: avoids deep water, empty for unreachable, respects buildings).
- **Manual check** ("watch the band for 5 minutes: people eat, drink at the river, chop, socialize at the fire, return home; no one stuck, no one oscillating; relaunch → same people, same tasks resumed"): all of it is automated — a whole simulated day in `test_behavior` (everyone ate, drank, slept, worked; nobody stuck or idle; 14–20 changes of activity each) and the relaunch in `test_people_persistence` — and it was seen on the phone up to M4.5. The relaunch was checked on the phone with the M5.3 build.
- **Android:** 7 people at 60 FPS (target: 8 at 60 FPS mid-range).
- **Performance (PC):** 20 people: simulation 0.036 ms per frame on average (target: AI < 0.5 ms), no frame over the 4 ms budget; a way across the box 0.26 ms, 20 requests in one frame of 0.4 ms (target: path requests < 1 ms per frame).
- **Exit criterion** — *"The world feels inhabited. A tester can describe what at least two people are 'doing'."* — is a hands-on judgement: **pending the owner's verdict**.
- **Still to judge by hand:** the size and look of the figures, the names, the walking pace, the rhythm of the day (work, meals, water, bed at dusk), the work sounds, the markers at mid zoom, the village empty of visible people at "night" in daylight (day and night come with M6).
- **Not in M4 on purpose:** people cannot be touched or selected without the debug overlay (M5); nobody perceives the player yet (M5); food is not consumed and work yields nothing (M9); no births, deaths or ageing consequences (later milestones); tiers 1 and 0 are numbers only (M21); walkers pass through one another.

### M4 — Tests & checks
**Automated:** `test_person_serialization`, `test_needs_decay`, `test_brain_selects_eat_when_hungry` (deterministic RNG), `test_brain_variety` (1,000 samples → distribution not degenerate), `test_pathfinder` (avoids deep water; returns null for unreachable; respects buildings), `test_plan_hungry_home_food_eat_work`.
**Manual:** watch the band for 5 minutes: people eat, drink at the river, chop, socialize at the fire, return home. No one stuck, no one oscillating. Relaunch → same people, same tasks resumed.
**Android:** 8 people at 60 FPS mid-range.
**Performance:** 20 people: AI < 0.5 ms/frame average; path requests < 1 ms/frame budget.
**Exit criteria:** *The world feels inhabited.* A tester can describe what at least two people are "doing".
**Risks:** Stuck agents → stuck detector (no progress N ticks → replan/teleport-to-nearest-walkable with log WARN); oscillation → hysteresis + commitment time.

---

## M5 — FIRST CONTACT

**Goal:** Interacting with inhabitants is emotionally interesting; the player cares about at least one individual. (P:M5, S§2, S§11, S§19, B§14, B§15.2, B§26.6)
**Depends on:** M4. **This is the signature mechanic — take the time to make it feel great.**

### M5.1 Person card & selection — ✅ DONE (2026-10-01)
- [x] **People can be touched and selected.** A finger on a person now finds them (`WorldView.pick` includes people; someone indoors is not there to be found; the hand's grip still reaches only for loose things, so nobody is picked up).
  - **Tap with the hand:** touches them *and* selects them. The touch is an intervention like any other (`InteractionManager`: subject `person`, gentle, in the player's history; `PersonData.FLAG_TOUCHED_BY_PLAYER`; a small warm ring, a light click and a light pulse — `InteractionResponse.PERSON_TOUCH`). **What the person makes of it is M5.3**; until then they do not react.
  - **Tap with Observe:** selects without touching (nothing in the history, no flag).
  - **Long press:** selects and opens the card at half height (what can be done), instead of the context menu.
  - **Double tap:** looks at them (the camera goes to them, never zooming out) and selects; the second tap does not touch again.
  - Other tools keep their own tap (the water tool pours, the debug call tool calls).
- [x] **Selection** is one person at a time and belongs to `Main` (`select_person(id, card_state)`, `clear_selection()`, `selected_person_id()`): `EventBus.person_selected(id)` (−1 when nobody) → tier 4 for them; whoever was selected before is let go (`SimulationManager`; the focus keeps its second place for someone followed, M5.2). Selection ends with the card (✕, dragged away, back button, another card in its place) or when the person leaves the world. It is not part of the save.
- [x] **Selection ring + outline** (`PeopleView.set_selected`): a ring on the ground under the selected person that follows them, never smaller on screen than 20 units (so it marks their marker from far away too), gone while they are indoors; and an **outline** around their body — a second pass (`assets/shaders/person_outline.gdshader`, back faces pushed out from the body's axis) on a material only the selected person's view uses. Body and outline share their movement (`person_motion.gdshaderinc`), so the outline walks, stoops and works with the body, also with reduced motion. Works on both renderers.
- [x] **Person card** (`scenes/ui/person_card.tscn`, `scripts/ui/panels/person_card.gd`): a sheet at the bottom of the screen, above the tools, with three heights —
  - **peek:** portrait glyph in the person's own colours (`PersonGlyph`: the skin, hair and cloth they are drawn with), full name, **what they are doing and why** ("Eating — hungry"), the star, ✕;
  - **half:** + age · occupation (or stage of life) · mood in a word; the six needs as bars (`NeedBar`: length first, colour second — B§28.3), named for what they are about (Food, Water, Rest, Company, Purpose, Safety); their nature in up to three words; the actions;
  - **full:** + family — partner, parents, children still in the world, each a button that goes to them.
  - The header is a handle: a tap folds and unfolds, a drag up or down goes a height up or down, down from the shortest closes. **Updated four times a second**; closes by itself when the person is gone.
- [x] **Actions:** **Observe** (toggles; shows the way they are going as dots on the ground, the last one larger — their needs are on the card), **Touch** (as a finger on them), **Focus** (camera to them), **More / Less** (the full card: "Inspect / Learn about"), **Mark important** (the star: `FLAG_MARKED_IMPORTANT`, saved with the person).
- [x] **Pin list** (`scripts/ui/widgets/pin_list.gd`): the given names of marked people at the left edge (six at most), there only while someone is marked; a tap on a name selects them and takes the camera there. Restored from the save when the world is opened; a marked person who dies leaves it.
- [x] **The debug inspector follows the selection** instead of having taps of its own: with the overlay up it shows whoever is selected and sits above their card; its ✕ lets go of them.
- **Deviations:**
  - **Follow** was not on the card in M5.1 — added with the camera's follow mode in M5.2.
  - **Recent memory** is not on the card: people have no memories until M5.4. Nothing is shown in its place.
  - **Observe** shows the path; the needs are on the card itself rather than drawn over the person.
  - A tap on open ground does not deselect (the hand taps the ground all the time); the card is closed with ✕, a drag or the back button.
  - Mood is shown as a word (Content, At ease, Restless, Troubled; Strained and Desperate under stress), not a number.
- **Caught while building:** the focus kept the previously selected person in tier 4 as well (it holds two) — selection now lets go of the old one itself; replacing one person's card with another's must not pass through "nobody selected" (the closing card says whose it was); the need bars' rounded ends were drawn over the track twice and showed as dots; the first trail dots were soft blobs that could not be seen on grass; a ground tap right after a person tap is a double tap (zoom) — as intended, but tests have to wait it out.
- **Verified:** `test_person_card` (17): the words; the facts shown (incl. family both ways, the dead not offered, broken needs never a broken bar); bars; **a real tap with the hand touches and selects** (intervention, flag, history, card at peek above the tools and blocking touches, ring and outline, a second tap, a tap on the ground, someone else — never "nobody" in between, tiers follow); Observe selects without touching and inspect card and person card take each other's place; long press → half card with every button finger-sized; double tap looks; other tools keep their tap; the three heights (grows upward, stays on screen, header tap and drags, dragging away deselects); live refresh and the person dying; closing and the back button; touch and focus from the card; observing shows the way and ends with the selection; marking, the pin list and going to a name; marks and touches across saves and a relaunch; family buttons lead to their cards at the same height; the pin list's limit. `test_people_view` (+2): a finger finds a person (not through the loose-object mask, not indoors); ring and outline (follows the body, minimum size from far away, indoors, change of selection, death, reduced motion); the trail. `test_ai_inspector` and `test_simulation_manager` updated for the selection. Suite: **811 passing**, no engine errors. Card (three heights), ring, outline, trail, pin list and the inspector above the card checked by screenshot on Mobile and Compatibility in a phone-shaped window (`C:\tmp\m51`).
- **Phone (Note20):** checked on 2026-10-01 with the M5.3 build — see M5.3. It found one fault: a tap on the card's header closed the card (fixed there).

### M5.2 Follow & focus — ✅ DONE (2026-10-01)
- [x] **Camera follow mode.** `CameraFollow` (`scripts/rendering/camera_follow.gd`) holds who is followed and whether the camera is with them (off / following / paused); `Main` moves the camera (`follow_person(id)`, `stop_following()`), through the new `CameraRig.track(point, screen)` — "keep this point under this place on the screen", gliding with the rig's own smoothing, never against a finger on the view and never out of the world.
  - **Where the person is kept:** in the middle of what is free of the screen — between the banner above and their card (or the tools) below — never lower than the middle and never higher than 28 % from the top (`CameraFollow.anchor`). The card growing or closing moves them accordingly.
  - **No trailing:** a gliding camera trails a walker by speed ÷ smoothing; the camera aims that much ahead of them (at most 1.5 tiles), so they stay where they are kept also at the faster game speeds.
  - Starting to follow comes closer if the view is far away (no further than the settlement is seen from), and never zooms out.
- [x] **Follow button on the card** (the fifth action; resolves the M5.1 deviation). Observe and Follow now show that they are on by a rim around the word instead of another word ("Observing" would not fit five in a row).
- [x] **Banner** at the top of the screen (`scripts/ui/widgets/follow_banner.gd`): **"Following Mara ✕"**. A tap on the name opens their card; ✕ stops.
- [x] **Pan breaks follow, with Resume:** dragging the view with one finger pauses the following — the banner becomes **"Resume following Mara ✕"** and a tap takes it up again. So do the home button, looking at someone or something else (double tap, Focus, a marked name, a family member), each of which takes the camera elsewhere. Looking at the followed person themselves resumes. **Two fingers do not break it:** the view can be zoomed while following.
- [x] **Tier 4 promotion:** `EventBus.person_followed(id)` (−1: nobody) → the followed person is in focus beside the selected one (`SimulationManager`; the focus holds two), paused or not, until the following is stopped.
- [x] **Kept across saves:** the followed person carries `FLAG_FOLLOWED`; on opening the world they are *offered* again ("Resume following …") rather than followed at once — the game opens on the settlement.
- [x] **Locate:** **"Find Mara"** appears under the banner while the selected person is out of sight (off the screen or behind their own card); a tap flies the camera to them. For marked people the names of the pin list (M5.1) do the same.
- Following is independent of selection: the card can be closed, or someone else selected, and the camera stays with the followed person. Someone followed who dies is let go.
- **Deviations:**
  - "Keeps the person in the lower-centre third": with the card at the bottom of the screen the lower third is where the card is; the person is kept in the middle of the free part instead (see above).
  - The Resume chip is the banner itself (one thing at the top instead of two).
  - Locate is a chip only when there is something to find; it is not shown for a person who is in view.
- **Caught while building:** the banner grew to the right instead of from its middle; its ✕ had no chip behind it; a walker at the faster game speeds trailed 70 units to the side of where they should be (hence the lead); a test's own signal handler kept the follow state alive (a leak in the test, not the game).
- **Verified:** `test_follow` (11): the state (off, on, paused; restarting resumes; someone else); the place on the screen; `CameraRig.track` (the point comes under the place, same distance, not against a finger, never out of the world); the banner widget (texts, centred, finger-sized, blocks touches); **follow from the card** (flag, tier, event, banner, the button shows it, five buttons fit uncut, the camera comes closer and puts them in the free part above the card, taller card, no card, pressing again stops; closing the card is not letting go); **the camera keeps up with a walker** (at most 45 units of 1920 off, on them again when they stop; pinch keeps following); **drag pauses, the banner resumes**, the banner's name opens the card, ✕ stops; home / someone else / Focus pause, the followed one resumes, Follow on another card changes people; death; **relaunch** (offered again, paused, tier 4; stopped stays stopped); Find (out of sight, behind the card, not while followed, not without a selection). `test_simulation_manager`: followed and selected share the focus. Suite: **822 passing**, no engine errors. Following (card at half, at peek, no card), the paused banner and Find checked by screenshot on Mobile and Compatibility (`C:\tmp\m52`).
- **Phone (Note20):** checked on 2026-10-01 with the M5.3 build — see M5.3 (follow, pause and resume, offered again after a relaunch).

### M5.3 Stimulus → perception → interpretation → reaction — ✅ DONE (2026-10-01)
The signature mechanic (B§14): nobody is commanded by a touch — they notice it, make something of it, feel something about it and do something about it, each in their own way.
- [x] **Stimulus** (`scripts/perception/stimulus.gd`, B§14.1): type, origin (hidden from inhabitants), anomalous, position, radius, intensity, tick, target. **`InteractionManager.apply_intervention` emits one for every intervention** (step 3 of the choke point; `stimulus_emitted`, `EventBus.stimulus_emitted`): a touched person → `touch`; a tree → `tree_shaken`; water → `water_disturbed`; something built → `knock`; the ground, a rock, a bush → `ground_touched`; and `tree_uprooted`, `object_lifted`, `object_moved`, `water_taken`, `water_poured` — a boulder through the air is more than a pebble, a flood more than a handful.
- [x] **Perception** (`scripts/perception/perception_system.gd`, B§14.2): everyone within the radius (spatial index) takes it in by **salience = intensity × proximity × attention × strangeness**; asleep, at work, walking and already reacting lower the attention. Below the threshold: unnoticed. What is noticed is queued for the person and considered **at their next turn, which comes at once** (so witnesses react a moment after one another, not in the same instant); **a direct touch is always perceived, immediately** — also while the game is paused. An unseen hand has no witnesses: only the person touched perceives a touch.
- [x] **Interpretation** (`scripts/perception/interpretation.gd`, B§14.3): every interpretation that can occur to the person is scored — base + **what people like them believe** (a prior per settlement, derived from the world's seed; flat spread for now) + **their nature** (trait weights) + **what they have made of things before** (`PersonData.beliefs`, one conviction per interpretation, moved by every experience: confirmation bias, and the pipeline's "belief update") + **what those close to them believe** (partner, parents) + **the circumstances** (large / local, weather-like, intense / faint, happened to me, nobody else noticed, tired, it has happened before, being a child) + being told — and one is drawn by weight (softmax; the creative are less predictable). **Knowledge gates:** NATURAL, SPIRIT, DEITY, HALLUCINATION and UNKNOWN_INTELLIGENCE are open to everyone; **ANCESTOR only to someone one of whose own has died**; EXPERIMENT and PHYSICS need knowledge nobody has yet; MULTIPLE_ENTITIES needs conflicting memories (M5.4+).
- [x] **Emotion and reaction** (`scripts/perception/reactions.gd`, table: `scripts/perception/reaction_table.gd` + `data/configuration/reactions.tres`, `Config.reactions`; B§14.4): interpretation, nature, intensity and how much of it was taken in give **fear, curiosity, awe, joy, annoyance**; these (and nature, and what the interpretation allows — nobody prays to what was nothing strange) score the reactions, and one is drawn. Every number is in the table.
- [x] **Reactions as plans** (steps like any other, saved with the person): **Look** (turn to it, ❓), **Freeze** (❗, stock still), **Run** (a start, then away from it at 2.2× walking pace, then a look back), **Investigate** (walk over, crouch at the spot, ❓), **Pray** (kneel, 🙏), **Wave** and **Laugh** (children jump, ♪), **Yell** (arms thrown up, ❗), **Dismiss** (a shrug, …), **Tell someone** (go to the nearest person who is up — family first, following them if they move — and tell, 💬: the listener hears of it **second hand, through the teller's interpretation**, makes something of it in turn, and listens, prays or waves it away; what is only heard is not carried further yet). Any strong reaction may end in going to tell someone. **Remember** is M5.4.
  - New step types `react` and `tell`; `walk_to` gained a pace, a sign, and "toward a person". New poses in the body shader (`act`: startled, kneeling, waving, jumping, crouching, crying out, shrugging) — they hold with reduced motion, only what swings and bounces is calmed.
  - Someone reacting is not asked what else they might do until it has run its course (hunger waits); another touch, or something more striking, starts a new reaction; something lesser is noticed but not reacted to.
- [x] **Emote icons above heads** (`assets/ui/emotes/*.svg`: ❗ ❓ 🙏 💬 ♪ …): pooled billboards in `PeopleView`, never hidden behind a tree, 0.22 units in the world and **never smaller than 46 units on screen** (readable from the middle distance, also above a far-away marker), popping up (not with reduced motion).
- [x] **The why is on the card:** "Praying — thinks a spirit is near", "Shrugging it off — thinks it was nothing strange" (two lines if need be). The debug inspector shows the whole of it: what was noticed, the scores of the interpretations, the five feelings, the reaction.
- [x] **The touch → reaction moment:** a medium pulse, the person's own voice (a small "oh!", pitched by age and sex, shriller in fright) and the sign. Witnesses are heard more quietly.
- **Repetition already counts** (B§14.5; the plan has it under M5.4, where memories take it further): every experience is counted per person and kind (`knowledge["experienced"]`); fear and awe wear off, the irritable grow annoyed, the trusting come to like it, and "it keeps happening" speaks for an unknown intelligence and against imagination.
- **Deviations:**
  - `reaction_table.gd` holds the numbers; the emotion and reaction logic is in `reactions.gd` next to it.
  - Perceptions wait for the person's next turn rather than their "think tick" — and that turn is brought forward to now, or people would react up to three game minutes late.
  - Stimulus numbers are per session (nothing refers to them across a save yet; M5.4's memories will).
  - No save-format change: convictions and experiences live in fields that were already saved empty (`beliefs`, `knowledge`).
  - LookAt is part of every reaction (people turn to what happened) as well as a reaction of its own.
- **Caught while building:** the arms moved the wrong way in the poses (the mesh marks arms by the leg they swing against, not by their side); what one is told counted as "nothing unusual" and so as natural; a listener who was merely idle wandered off before the teller arrived (the teller now follows them); a frozen world reacted, on thawing, to what was done while it stood still; the card's line was cut off (it wraps now). **On the phone:** a tap on the card's header closed the card — on a touch screen every touch arrives twice (as itself and as the mouse it stands in for), in different coordinates; the header now takes one of them and measures on the screen.
- **Verified:** `test_perception` (22): the table is complete; every intervention gives off the right stimulus; salience and attention; who notices and who does not (reach, sleep, direct touch); **`test_interpretation_variety`** (100 random people touched make at least four different things of it, none more than 70 %; the spiritual see spirits and gods > 80 %, skeptics nothing much > 45 %; great things are a god's doing, small ones the wind's); gates (an ancestor only after a death, with a real one); every term of the score on its own (nature, conviction, partner, tiredness, familiarity, being told, suspicion); culture priors from the seed, weak for children; the weighted draw is repeatable; feelings (nature, interpretation, strength, children, second hand); repetition (fear and awe wear off, annoyance and liking grow, the fearful run far less the thirteenth time); **`test_reaction_mapping`** (fearful + strong ⇒ run or freeze > 55 %, the brave < 15 %; the spiritual pray > 50 %, skeptics < 10 % and shrug or look; the curious investigate; the irritable cry out; children laugh and wave, hardly pray; small far things are looked at or shrugged off); what can be done where; every reaction is a plan that shows; a touch is taken in at once and runs its course; reacting is not dropped for a need but for another touch; frozen; witnesses react at their next turn and turn to it; running is faster than walking and ends well away; telling passes it on (second hand, sways the listener, no chain); **a reaction survives a save**; cost. `test_reactions_in_game` (6): a real tap → intervention → stimulus → reaction with sign, pose, voice, medium pulse and card line, and the sign goes when it is over; Observe disturbs nobody; signs from afar, above markers, indoors, unknown, death; the pop; voices; a shaken tree turns heads. Suite: **850 passing**, no engine errors. Poses and signs checked by screenshot on Mobile and Compatibility (`C:\tmp\m53`).
- **Numbers (PC):** 300 random people touched — grown: pray 27 %, run 27 %, look 12 %, freeze 10 %, dismiss 8 %, wave 7 %, yell 4 %, tell 3 %; children: laugh 29 %, run 20 %, wave 18 %, freeze 10 %. A stimulus noticed by 20 people, interpreted and reacted to by all of them in one frame: 1.9 ms.
- **Phone (Note20, debug build), M5.3 and the checks outstanding from M4.6, M5.1 and M5.2:** 60 FPS throughout (58–59 with the overlay up); sim 0.25–0.6 ms per frame for 7–8 people; no errors in the log.
  - **Reactions:** people touched cried out ("thinks a god reached down"), shrugged ("thinks they imagined it"), waved ("thinks a spirit is near"), a child laughed, a newcomer went to tell someone; a shaken tree made two people nearby look up with ❓. Signs are readable at the settlement distance (24). The pulse on a touched person is the medium one (24 ms at 0.6, against 14 ms at 0.35 for the ground). The inspector shows the scores, the feelings and the reaction.
  - **M5.1:** tap selects and touches; long press opens the half card; five buttons fit; the header folds and unfolds the card (after the fix above); the star marks and the name appears at the edge; a tap on the name flies to the person.
  - **M5.2:** Follow → "Following Mitra", dragging away → "Resume following Mitra" and "Find Mitra", a tap resumes; after leaving and reopening the game "Resume following Mitra" is offered and the pin is back.
  - **M4.6:** the inspector follows the selection and sits above the card; Spawn (a newcomer who ate and went to bed), Kill, Freeze and Unfreeze work; leaving with the back button and reopening resumes at the same tick with everyone where they were.
  - The world on the phone was left as found except for what touching does (history, convictions): the newcomer was removed, the mark and the following undone. A copy of the save from before is in `C:\tmp\m53\phone_before`.

### M5.4 Memory v1 — ✅ DONE (2026-10-01)
- [x] **Memories** (`scripts/people/memory.gd`, B§15.2): owner, subject (the kind of thing: `touch`, `tree_shaken`, `object_found`, …), the stimulus it came from, when (first and last), where, **what the owner made of it**, **how it felt** (the five emotions), intensity, **importance**, **source** (lived, witnessed, told — and by whom; inherited / taught / written reserved), **fidelity**, how many times, the stage of life it happened in, when it was last told, and its text template.
- [x] **`MemoryStore`** (`scripts/people/memory_store.gd`, `session.memories`; people hold the ids of theirs in `PersonData.memory_ids`, most recent last):
  - **Made from what a person makes of something** — every reaction of M5.3 leaves a memory (`from_outcome`): **importance = strength × how it felt × how much it was theirs × how new it was** (lived 1.0, witnessed 0.65, told 0.45; what was barely noticed is not kept, what happens to oneself always is).
  - **Compaction:** the same thing again, taken the same way, is *one* memory that grows — "felt the touch of a spirit (14 times)" — not fourteen; at most **32 per person** (`MemoryConfig.max_per_person`), beyond that the least important go, of equals the oldest.
  - **Daily decay:** once per game day every memory loses a little importance — the less it matters, the more (something that matters fully loses a twentieth of what a trifle does) — and below 0.05 it is **forgotten**. A middling memory lasts a week or two; a tree torn out by a god is still remembered after a year.
- [x] **Text templates** in `data/text/memories.csv`, looked up through the translation server (`tr`; registered in the project settings): keyed by **subject × interpretation** with a **child's variant** where there is one ("was tickled by a spirit"), the skeptic's reading being the hallucination / natural lines ("thought something touched, and put it down to tiredness"); less particular templates for what was seen ("saw a tree shaking with no wind — a spirit's doing"), found, and told ("heard from Kugi of a touch from an unseen hand — a god's doing"). `MemoryText` builds the clause, a card line ("Age 27 · Felt the touch of a spirit (3 times)") and a sentence ("At age 27, Mara felt the touch of a spirit."). Texts are clauses without a subject, so nobody is called "he" or "she" by a template.
- [x] **On the card** (the "recent memory" left open in M5.1): the last thing they remember on the half card; the last five under "Remembers" on the full card. The lower part of the full card now scrolls if the screen is too short for it, so the card never leaves the screen. The debug inspector shows the latest memory with importance, fidelity and source; the overlay counts memories.
- [x] **Memories affect behaviour:**
  - **Fear of a place:** a memory with fear in it makes its place one to keep away from (`fear_at`: by how frightening it was, how much it still matters, and how near — 6 tiles); people do **not go back there to work** (a woodcutter picks another tree) **or to look around**, as long as there is anywhere else. It fades with the memory.
  - **Wonder draws closer:** remembering the like of something with curiosity and awe (and little fear) speaks for **Investigate** — and a wave — the next time (31 → 102 closer looks of 200); remembering it with dread does the opposite (→ 1).
  - **Repeated touches shift reactions** (B§14.5; the mechanism came with M5.3): one person touched ten times goes from running to waving, looking and shrugging; all ten are remembered, as a few memories.
- [x] **Gossip with fidelity** (B§15.3): a little way into a conversation people tell of **the memory that matters most to them** — recent, true enough, not told lately, and not to someone who was there or has already heard it from them. The listener keeps a **second-hand memory at fidelity × 0.85**, taken *their* way. Stories die out by themselves: second-hand memories matter less, and below fidelity 0.4 they are no longer passed on. Someone who goes to tell of what just happened (M5.3) tells it as they remember it.
- [x] **Discovering what the player moved** (the M3.6 hook): someone who comes within 2.6 tiles of a thing the player put down where the settlement's people pass — at least half a game hour earlier — **comes upon it** (`scripts/perception/discovery.gd`, when they look up from what they are doing): a perception like any other, so they make something of it, react (the curious take a closer look) and remember: "found a stone that was not there the day before — a spirit's doing". Once per person and place: a stone moved again is found again; whoever saw it lifted or land does not "find" it.
- [x] **Save format version 6** with migration `5 → 6`: adds `memories` and the numbering of stimuli (`perception`), which now continues across saves. Version-5 worlds had people with convictions and counted experiences but no memories — **they are given one memory per kind of experience** (vaguer than a lived one, taken the way they are most convinced things are), so that someone touched three times before the update remembers it. Fixture `tests/fixtures/saves/v5_world.sav` is a real version-5 save written by M5.3 (`d74f19e`): three people touched, two of them running away.
- **Deviations:**
  - The "skeptic variant" is not a separate template per person: what a skeptic remembers differs because what they made of it differs (natural, hallucination).
  - Where a memory's fear lowers a place's "utility", it is the choice of place that changes (work, exploring), not the score of the activity — nobody stops working because one tree frightens them.
  - `text_params` is kept for templates that will need more than what the memory itself holds; nothing uses it yet.
  - Family, cultural and mythological memories (B§15.1, §15.4) are later milestones; the owner kinds exist.
- **Caught while building:** the full card grew taller than a short screen (hence the scrolling lower part), and wrapped text only knows its height a frame later (the card settles over a few frames after its content changes); a saved memory took 616 bytes (defaults are left out now: 372); in tests, idle people wander off between two steps of a scenario.
- **Verified:** `test_memory` (17): every subject × interpretation × source × child has words with no placeholder left; **`test_memory_created_on_touch`** (the whole record, the card line, a child's memory, none while frozen); importance; **`test_memory_compaction`** (merging, counts, what is another memory, recency, the cap, a trifle not kept); fading and forgetting (once a day, days made up, a year on, driven by the world's clock); **`test_repeated_touch_changes_reaction`**; **`test_gossip_secondhand_fidelity`** (0.85 per retelling, not twice to the same ears, not back to the teller, not too soon, worn stories stop); talk during socialising; fear keeps a woodcutter from a tree and fades; wonder and dread; finding a stone, what is not found, a stone moved again; **saved and restored word for word**, numbers continue; broken records; **the version-5 fixture migrates and its people remember**; cost. `test_person_card` (+1): memories on the card. `test_people_persistence`: every older version (1–5) still loads. Suite: **868 passing**, no engine errors. The card with memories checked by screenshot on Mobile and Compatibility (`C:\tmp\m54`).
- **Numbers (PC):** 640 memories (20 people with full heads): fear and wonder of one person 0.06 ms; a day's fading 0.25 ms; saved as 238 KB in 4 ms.
- **Phone (Note20):** checked on 2026-10-01 with the M5.6 build — see the M5 summary (the version-5 world migrated; memories on the card; stones found).

### M5.5 Player history & first stats v0 — ✅ DONE (2026-10-01) — journal card not yet seen on the phone
- [x] **The history is shown, in words** (B§27.2): a journal card "Your hand in this world" (`scenes/ui/panels/history_card.tscn`, `HistoryCard`) lists the acts worth remembering — the first of each kind and everything Moderate or Major, as the history has logged them since M3.6 — the latest first, with year stamps: **"YEAR 1 · touched first inhabitant"**, "YEAR 1 · shook a tree for the first time", "YEAR 3 · moved a boulder for the first time", "YEAR 7 · took water out of the world for the first time". The same thing done several times running in one year is one line ("moved a boulder (12 times)"). The list scrolls; the card keeps itself up to date while open and never leaves the screen.
  - Texts from `data/text/history.csv` through the translation server (`HistoryText`): the most particular template wins (`HIST_FIRST_<TYPE>_<SUBJECT>` → `HIST_FIRST_<TYPE>` → `HIST_<TYPE>_<SUBJECT>` → `HIST_<TYPE>`), with a name for every thing that can be touched or moved. Year 1 is the world's first year.
  - **Opened by a journal button** (an open book, above the Home button) until the menu it belongs in exists (VS.1 / M14); pressed again, or the back button, closes it. One card at a time: it and a person's or an inspect card take each other's place.
- [x] **Counters** on the card (B§27.3, "for reflection, not score"): **Interactions**, **People touched** — different people, each counted once, whatever becomes of them (`PlayerHistory.people_touched()`, with how often each: `touches_of`) — and **Objects moved**. `stats()` has `people_touched` too.
- [x] **Achievement hook:** `PlayerHistory.unlock(id, tick, intervention)` / `has_achievement` / `achievements()`, saved with the world; **FIRST CONTACT** is unlocked by the first touch of an inhabitant (when, and by which intervention). `EventBus.achievement_unlocked(id)` is emitted once, when it happens — never again on loading. Nothing is shown yet (M25); the debug overlay lists what is unlocked.
- [x] **Save format version 7** with migration `6 → 7`: the history gains `people` and `achievements`. Both are derived for older worlds from what they hold — people carry the mark of having been touched (and a count), and the log has the first touch — so a world in which first contact was made before the update has the achievement, dated to that touch. Fixture `tests/fixtures/saves/v6_world.sav` is a real version-6 save written by M5.4 (`0318478`).
- **Deviations:** the journal button is a stand-in for the menu entry (PLAYER → Interaction History); achievements are kept per world (the bible's "local only"), with no display until M25.
- **Caught while building:** a card full of "moved a boulder" lines (every Moderate act is logged) — hence the folding of repeats.
- **Verified:** `test_history_card` (7): people touched are counted once each, survive the person, a save, and broken data; first contact unlocks once, is announced once, is saved, is not announced again on loading, and a new world has none; the words (years, every act on every kind of thing with nothing left to fill in, unknown kinds still read); a real tap on the journal button opens the card (and does not touch the world), again closes it, back closes it; the card tells what was done latest first, counts, follows the years, folds repeats, scrolls and stays on screen; one card at a time; **the version-6 fixture migrates** (three people touched, one three times; first contact by intervention 1; nothing else lost). `test_people_persistence`: every older version (1–6) still loads. Suite: **875 passing**, no engine errors. Button and card checked by screenshot on Mobile and Compatibility (`C:\tmp\m55`).
- **Phone (Note20):** the journal button was seen on the HUD with the M5.6 build; **the card itself has not been seen on the phone** (see the M5 summary).

### M5.6 FTUE hints — ✅ DONE (2026-10-01)
- [x] Three more first-time hints in the `HintDirector` (M2.6), each shown once it makes sense and gone for good once the player has done the thing (state per install, `ftue/completed`):
  - **"Try touching someone."** — after the first pan, while someone is on screen as a figure (not a far-off dot); done with the first touch of a person.
  - **"Hold to learn more."** (from M2.6) — now third in line; done with the first long press.
  - **"Follow them to see their day."** — while a person's card is open; done with the first follow. It is the one hint that shows with a card open, and it sits **just above the card** (the label follows the card's top edge as it grows and shrinks) instead of behind it.
- [x] **Order and relevance:** drag → touch → hold → follow, one at a time — but a hint that makes no sense right now does not hold up the next (nobody in view: "hold" has its turn), and one that stops making sense goes away without counting as done (the person walked out of view, the card closed) and returns later. With a person's card open only the card's own hint shows; with any other panel open, none.
- **Deviation:** "Hold to learn more." keeps its M2.6 trigger (after the first touch of the world) rather than waiting for a person to have been touched: a long press teaches about everything, not only people.
- **Verified:** `test_hints` (+7, 20 in all): the touch hint after the first pan with someone in view, hidden when they leave, back when they return, done for good across sessions; nobody in view does not hold up "hold"; touch before hold; never shown to someone who already did it; the follow hint belongs to a person's card; with a card open only its hint; the label keeps clear of a card. `test_person_card` (+1): the whole sequence in the running game with real gestures — drag, the touch hint, a tap on a person, the follow hint above the card (also when the card grows), Follow, the hold hint back in its usual place, nothing with the journal open. Suite: **883 passing**, no engine errors.
- **Phone (Note20):** on launch "Try touching someone." came up at the settlement (the drag hint had been done long ago); the log shows "Follow them to see their day." 2.5 s after a card was opened. See the M5 summary for the rest of what was seen on the phone with this build.

### M5 — Completion summary
All six sub-phases are done (M5.1–M5.6): the person card and selection; follow and focus; stimulus → perception → interpretation → reaction; memory; the player's history and first statistics; the first-contact hints. **883 automated tests.**
- **Automated tests named in the plan:** `test_interpretation_variety`, `test_reaction_mapping` (`test_perception.gd`); `test_memory_created_on_touch`, `test_memory_compaction`, `test_gossip_secondhand_fidelity`, `test_repeated_touch_changes_reaction` (`test_memory.gd`).
- **Manual script** ("touch 5 different people and write down reactions; touch the same person 10 times over a day; move a rock next to a hut and wait until someone investigates it; check memories on cards"): each part is automated (reaction mapping by nature; ten touches through the whole pipeline; a stone found, investigated and remembered; memories on the card) and was seen on the phone: people cried out, shrugged, waved, a child laughed, one went to tell someone — each with its reason on the card; with the M5.6 build a card on the phone listed "Felt the touch of a spirit", "Saw a tree shaking with no wind — a spirit's doing", "Found a stone that was not there the day before — a spirit's doing" and "Saw something rise into the air by itself — a spirit's doing".
- **Android** ("the touch → reaction moment has haptic medium + sound + emote; card readable one-handed"): the medium pulse (24 ms at 0.6) and the sign were verified on the phone in M5.3, the voice by test; whether the card is comfortable one-handed is the owner's to judge. 60 FPS with 7–8 people throughout.
- **Phone, with the last build (M5.4–M5.6):** the version-5 world there opened as version 7 without errors (two migrations); people who had been touched have memories; people came upon stones moved in earlier sessions and reacted; the journal button is on the HUD. **Not seen on the phone:** the journal card itself and the follow hint's place above the card — the phone was in use by its owner at the time, so no further input was sent to it. (Three inputs had already been sent before that was noticed: two taps at the journal button's place and a long press that lifted a boulder and opened its menu.) A copy of the save from before the update is in `C:\tmp\m56\phone_before`.
- **Save format:** 5 → 7 over the milestone (memories and stimulus numbering; the history's people and achievements), with real fixtures and migrations for both steps.
- **Exit criterion** — *"The player cares about at least one individual. Testers can name a person and tell a small story about them."* — is a hands-on judgement: **pending the owner's verdict**.
- **Still to judge by hand:** whether a hand tap should touch *and* select; the card's size and reach; how often people look up when the ground or a tree near them is touched; reaction lengths; sign size from the settlement view; the mix of first reactions (grown people pray and run a lot); the wording of what people think and remember; the voice; how long memories last; the journal button on the HUD; where the followed person sits on screen.
- **Not in M5 on purpose:** family, cultural and mythological memories, myth formation (later milestones); the "Today" timeline on the card (M6.4); a display for achievements (M25); the menu the journal belongs in (VS.1 / M14); speed controls (M6).

### M5 — Tests & checks
**Automated:** `test_interpretation_variety` (same stimulus to 100 randomized persons → ≥ 4 distinct interpretations; spiritual-heavy population skews DEITY/SPIRIT; skeptics skew NATURAL/HALLUCINATION), `test_reaction_mapping` (fearful+high intensity ⇒ run/freeze mostly), `test_memory_created_on_touch`, `test_memory_compaction`, `test_gossip_secondhand_fidelity`, `test_repeated_touch_changes_reaction`.
**Manual script:** touch 5 different people (child, elder, curious, fearful, spiritual) and write down reactions; touch the same person 10 times over a day; move a rock next to a hut and wait until someone investigates it; check memories on cards.
**Android:** the touch → reaction moment has haptic medium + sound + emote; card readable one-handed.
**Exit criteria:** *The player cares about at least one individual.* Testers can name a person and tell a small story about them.
**Risks:** Reactions feel random → surface the *why* in text ("Mara thinks it was the river spirit"); too repetitive → template variety + memory-driven variation.

---

## M6 — TIME AND DAILY LIFE

**Goal:** The world feels continuous; a player can follow one person through an entire day and understand their life. (P:M6, S§12, S§40, B§9, B§13.5)
**Depends on:** M5.

### M6.1 Calendar & clock — ✅ DONE (2026-10-01) — phone check outstanding
- [x] **The calendar** (D-04, B§9.1), all of it from `TimeConfig`: tick 0 is the start hour (06:00) on day 1 of spring in year 1; days turn at midnight; 6 days to a season, 4 seasons to a year. `TimeConfig.day_index / year_of / season_of / day_of_season / day_of_year(tick)` for any tick (also before the world began); `GameClock.minute() / hour_of_day() / day() / day_of_season() / day_of_year() / season() / year()` for now.
  - **`format_time()`** → "06:30"; **`format_date()`** → "Year 3 · Spring · Day 4 · 06:30" (`format_date(false)` without the time). Season names and the date's wording are in `data/text/time.csv` (translation server); a calendar configured with more seasons than there are names numbers the rest.
  - **Signals:** the clock emits `day_started(day)` (at midnight; days counted from the world's first), `season_changed(season, year)` and `year_started(year)` as it advances; `WorldSession` passes them on through the `EventBus`. A new season is logged.
  - The player's history now takes its years from the same calendar (they turned at 06:00 before; now at midnight).
- [x] **Speed control in the HUD, top right** (`scripts/ui/widgets/speed_control.gd`): a round button showing the speed — ‖ ▶ ▶▶ ▶▶▶ — and under it the time of day and the date ("11:40" / "Year 1 · Spring · Day 1"; touches pass through the words).
  - **Tap:** pause, or carry on at the speed it had before. Paused, the button's rim and sign are lit and the readout says "Paused · 11:58".
  - **Long press:** the selector (`scripts/ui/panels/speed_selector.gd`) — Paused / Normal / Fast / Very fast, each with its sign, the current one ringed; choosing sets the speed and closes it; touching the world or the back button closes it without anything else happening.
- [x] **Pause freezes the simulation, not the UI or the camera:** the clock stands, nobody lives or walks, and now also **nothing falls, rolls, drifts or flows** (`LooseObjectSystem.frozen`, `WaterSim.frozen`, set by the session) — a stone let go while paused hangs where it was let go and comes down when the world goes on. Panning, zooming, selecting people, cards and the journal all work. A world saved paused opens paused, and says so.
- **Deviations:** the clock readout is part of the speed control (the plan names only the control); pause also stops loose objects and water, which ran in real time whatever the clock did; ambient loops (smoke, birds, breathing) keep playing, as B§9.2 allows.
- **Verified:** `test_game_clock` (+3, 9 in all): **`test_clock_calendar`** (minute → hour → day at midnight → season → year, the formats, a calendar with other numbers, the four season names and a fifth, and the speed multipliers 0 / 1 / 4 / 16 in ticks); days, seasons and years are announced once each, not while paused; the calendar of any tick, also before the world began. `test_speed_control` (5), in the running game: where the control sits (clear of the pin list and the follow banner), the readout following the clock; **a real tap pauses** — nobody moves or grows hungrier, a dropped stone hangs, the camera and a person's card work — and a second tap carries on at the speed it had; **a long press opens the selector** (four speeds, the current one marked, on screen), choosing Very fast makes the world race, a touch of the world closes it and does nothing else; a paused world is saved paused; the EventBus is told of the new day, season and year. `test_history_card` updated for years turning at midnight. Suite: **891 passing**, no engine errors. Checked by screenshot on Mobile and Compatibility (`C:\tmp\m61`).
- **Phone (Note20): not done.** The phone was in its owner's hands during the last check, so nothing has been installed or sent to it since. The build is ready (`build/wiab-debug.apk`). To check: the control's place and size under the thumb (top right is far from a thumb on a tall phone — the plan puts it there), tap to pause, hold for the selector, a few minutes at Very fast.

### M6.2 Day/night — ✅ DONE (2026-10-01) — phone check outstanding
- [x] **`scripts/rendering/day_night.gd`** (`DayNight`, in `WorldView` as `day_night()`): reads the hour from the world's clock and drives the light. What the light is at an hour is a pure function (`DayNight.state_at(hour, config)`), tested without a screen.
  - **Sun:** rises at 05:30 in the east, climbs to 62° at noon, sets at 20:30 (19:15 since M6.3) in the west — so shadows turn and lengthen through the day (never lower than 24°: no shadows across the whole box). Warm at both ends of the day, near white at noon; its strength fades to nothing at the horizon.
  - **Moon:** the same directional light takes the moon's place for the night (they change over while the light is at zero): cool, a quarter of the sun's strength, softer shadows.
  - **Air and backdrop:** the ambient colour runs through deep blue (night), rose (dawn), sky (day) and amber (dusk); the room behind the table goes nearly black at night and the table dims with it; cloud shadows weaken to a third under the moon. Dawn and dusk take an hour and a half.
  - **Night tint without losing the people:** at night the light is about half the day's — dark blue-green, with everyone and everything still to be made out.
  - All of it in `DayNightConfig` (`data/configuration/day_night.tres`, `Config.day_night`): hours, angles, energies, colours; the colours over the day are `Gradient` resources (built in; replaceable in the resource).
- [x] **Window lights:** huts have a small window now, and it and the doorway **glow warm from dusk** (full until 23:00, low after the village has gone to bed, out by morning — per household since M6.3). The props stay one mesh per chunk: what glows is marked per vertex (`PropMeshLibrary.Template.glow` → UV.x), and the prop shader lights it by `night_glow`.
- [x] **Campfires glow:** the flame shines by itself (emission, stronger at night), and a warm **flickering light** (`OmniLight3D`, no shadows) stands over the fire — faint by day, the light of the settlement by night.
- [x] **Night ambience:** **crickets** (a generated loop under the ambience volume) fade in with the dark and out with the dawn; the **fire crackles** every few seconds once it is dark; birds **roost at night** (the flock is gone, no calls) and sing most around sunrise (**dawn chorus**, 3.5 × as often).
- **Deviations:**
  - **No moon or stars in a sky:** the camera always looks down into the box (38–54°), so there is no sky to hang them in. The moon is the night's light; stars are left out.
  - The sun's and the air's curves are code-built `Gradient`s with numbers in the config rather than hand-authored `Curve` resource files (they can be replaced in the `.tres`).
  - Windows are lit by the hour for the whole settlement; lights out per household when its people sleep comes with M6.3.
  - A new world opens at 06:00 — now in the warm light just after sunrise.
- **Caught while building:** vertex colours are 8-bit, so "glows" could not ride in the colour's alpha as planned (hence UV); the hut's window had the door's colour and confused the test that finds the door.
- **Verified:** `test_day_night` (10): the config; night and day turn into each other smoothly, dark when people sleep and light when they are up; the sun climbs, crosses and sets, is warm at the ends, nothing at the horizon, and the moon takes over — and the sky is without a light for at most two hours a day; air, backdrop, table and clouds follow the hour, the night darker but never pitch black; windows and fire belong to the dark; **the light on screen follows the clock** (sun, environment, table, prop and people materials) and moves by itself; the campfire's light (place, strength by day and night, flicker, none without a fire); glow marks on hut, fire and tree and through the mesher into the mesh; crickets come and go with the dark and with the ambience; birds roost and sing at dawn, the fire crackles at night. `test_people_view`, `test_sound_synth` updated. Suite: **901 passing**, no engine errors. Nine hours of the day and the whole box at night checked by screenshot on Mobile and Compatibility (`C:\tmp\m62`).
- **Phone (Note20): not done** — nothing has been sent to the phone since it was found in use. The build is ready (`build/wiab-debug.apk`). To check: frame rate at night (one more light), whether the night is too dark or too bright on the phone's screen, the crickets' loudness.

### M6.3 Routines & sleep — ✅ DONE (2026-10-01) — phone check outstanding
- [x] **Routines per occupation** in `data/occupations/*.tres`: `routine`, a list of "HH:MM activity" entries ("wake" = nothing in particular); each holds until the next, the last over midnight (`OccupationDef.scheduled(hour)`, `hours_into_slot`, `slots`, checked at load: readable, in order). Occupations are per life stage already, so this is "occupation × life stage".
  - Woodcutter / forager / builder: 05:30 wake · 07:00 eat · 08:00 work · 12:00 eat · 13:00 work · 17:00 socialize · 18:00 eat · 19:00 socialize · 20:30 go home · 21:00 sleep.
  - Elder: 06:00 wake · 07:30 eat · 08:30 work · 12:00 eat · 13:00 socialize · 15:00 go home · 17:00 socialize · 18:00 eat · 19:30 go home · 20:00 sleep.
  - Child: 06:30 wake · 07:00 eat · 08:00 play · 10:30 tag along · 12:00 eat · 13:00 play · 16:00 tag along · 18:00 eat · 19:30 sleep.
- [x] **Soft, as a bias in the brain** (`Brain`): what the routine has for the hour scores up to 1.25 × as much and up to 0.25 on top (`ROUTINE_FACTOR`, `ROUTINE_PULL`) — **scaled by how calm the person is** (1 − their loudest need), so the parched still go to the water at work time and the dead tired to bed. For the length of its slot; a thing one does not do twice in a row (a meal) only until it is done. The routine's hour also counts as "the hour for it" whatever the general time-of-day curve says (a child's bedtime is early, and it is bedtime). What is newly due loosens what was begun for no pressing reason (lunch gets people off their work; someone who went to work because idleness was eating at them works on; a sleeper is not got up for breakfast). What holds someone at a task is the score without the push (`Decision.commitment_of`).
- [x] **Meals at the fire, together:** at mealtimes people go to **their own place in a ring around the fire** (`Places.meal_spot`), a meal lasts its time even for someone soon full, and eating beside others is company (`EatStep.company`, 60 % of a conversation's worth). Breakfast, lunch and dinner happen by themselves: typically 5–6 of 8 at the fire at once.
- [x] **Children:** play in the morning and afternoon, **tag along** with a parent twice a day (new activity `tag_along`: needs a parent who is up and about; walks to the nearer one, wherever they go meanwhile, and keeps them company), in bed at 19:30. **Bedtime hook:** `BehaviorSystem.bedtime(child_id)` when a child is put to bed for the night (not for a nap, not again after loading) — for M11's bedtime stories.
- [x] **Sleep:** home, indoors, until morning. **Lights out per household:** a hut's window and doorway glow from dusk while someone who lives there is up, and go dark when everyone in it is asleep (or nobody lives there) — `WorldView.refresh_house_lights` → `DayNight.set_dark_houses` → prop shader `lights_out[8]`. The settlement goes dark hut by hut.
- [x] **Sleepers and the hand:** a sleeper takes in a tenth of what happens. A new interpretation **"dream"** (only for someone asleep): touched, most take it for a dream — they stir, sleep on, show nothing, and remember **"dreamt of a warm hand"**; the rest start awake and react as anyone would (43 dreams / 17 startled in 60). A **knock on a hut** reaches those asleep behind that wall and nobody else ("dreamt of someone knocking"; 154 dreams / 6 woken in 160). A dream leaves convictions as they were. No dream for anyone awake.
- [x] **The day moved to fit the people:** sunset is **19:15** now (was 20:30) and night proper begins at 21:00, so dinner is at dusk, grown-ups sit up by the fire after dark, and windows are lit for an hour or two before they go out. New worlds open with people rested (they have just got up).
- **Deviations:**
  - **Meals are at the fire, not at home** — the band's food is there (stores and households' own food come with M7); "family dinner" is the whole band's dinner.
  - **"Follow parents" is `tag_along`**, an activity chosen like any other (twice a day by the routine), not a constant following.
  - **Bedtime stories:** only the hook (a signal); nothing listens yet.
  - **Routines are soft enough that not everyone keeps them:** people still nap, eat early when hungry, or go home before the others. By design (B§13.5), but it means a meal is "most of the band", not everyone.
  - `lights_out` has room for 8 dark houses (a starting settlement has 3); more huts than that need a different way of telling the shader (M7+).
  - The dream variant is an interpretation of its own rather than a variant of the others; the save format gains a tenth conviction per person (appended; older saves are padded on load — no version bump).
- **Caught while building:**
  - The push first kept a dead-tired person at work and killed all variety → scaled by calm. The pushed score, stored as what a plan was begun with, then kept a parched sleeper asleep → plans are held by the unpushed score.
  - **Everyone was in bed before dark**, so lit windows and lights-out were never seen: tired people drifted home after dinner and sleep, once drawn, holds. Fixed by pushing through the whole slot (the evening by the fire), letting the routine set the hour, a weaker pull home before 20:00, and the earlier sunset.
  - A push given once per slot ended the "evening together" after one ten-minute chat.
  - Dinner at 18:30 was eaten in ones and twos (people are hungry five hours after lunch) → 18:00.
  - Touched sleepers woke three times in four at first, and sleepers behind a knocked wall forgot it (too faint to be remembered) → dream weights; a dream is always remembered.
- **Verified:** `test_routines` (10): **`test_routine_bias`** (at 08:00 work dominates, at 21:00 sleep; the three meals; once for a meal, all through for work; a child's bedtime; the push in numbers, its absence for what is not due, and that pressing needs drown it out; the ceiling covers it); reading and checking routines, and every occupation's own; what is due loosens what was begun idly; meals (places around the fire, lasting, company, alone); tagging along; the bedtime signal (not for naps, not after a load); the touched sleeper; the knock on the wall; a house going dark and lit again (and the shader told); **the shape of a whole day** (meals together, everyone up at ten, grown-ups up after dark with children asleep, everyone in bed at eleven). Older tests adjusted where they assumed no routine. Suite: **911 passing**, no engine errors. A day watched by screenshot on Mobile and Compatibility (`C:\tmp\m63`): breakfast and dinner around the fire, people by the fire after dark, huts going dark one by one.
- **Phone (Note20): not done** — nothing has been sent to the phone since it was found in use. The build is ready (`build/wiab-debug.apk`). To check: an evening at Fast or Very fast (dinner, the fire after dark, lights out), touching a sleeper.

### M6.4 Follow-mode day log — ✅ DONE (2026-10-01) — phone check outstanding
- [x] **`DayLog`** (`scripts/people/day_log.gd`, `session.day_log`): for every person a ring of what they turned to and when — `[tick, kind, detail, other]`, at most 32 entries and two days back. Written by the behaviour system as plans change (`BehaviorSystem._note_change`), so it costs nothing while nothing changes.
  - What is written: every activity (with what kind of work, whether a meal, whether bed or a nap, and with whom), **waking** (slept out or woken), what they **noticed and did about it** ("feels a touch, runs away"; who told them, whom they go to tell) and a sleeper **stirring** at a dream.
  - What is not: going on with the same thing; something given up within three minutes (it "never happened", and a sip of water in the middle of work does not start the work anew); going from one person to the next in a talk (one entry: "talks to Yaisu and others"); a second waking within the hour; the debug call.
- [x] **In words** (`DayLogText`, `data/text/daylog.csv`, through the translation server): *"05:29 wakes · 05:31 drinks · 07:02 has breakfast · 07:40 chops wood · 12:17 has lunch · 13:02 chops wood · 17:05 talks to Ditkalou · 18:05 has dinner · 18:42 goes home · 20:03 goes to bed"*. Meals are named by the hour, work by the occupation's target (chops wood / gathers berries / tends the fire).
- [x] **"Today" on the card** (full card, above the family): the day so far as one wrapped paragraph, kept up to date; in the small hours, before the person has done anything, the title reads "Yesterday" and yesterday's day is shown; "Nothing yet" for a new arrival.
- [x] **OBSERVER hook:** `ObserverWatch` (`session.observer`) counts how long the camera has stayed with one person: unlocked (`PlayerHistory.OBSERVER`, announced on `EventBus.achievement_unlocked`) once that person has been the one followed for 24 game hours with the view on them for at least nine tenths of the last 24 (a sliding window: too much time away only delays it). A paused follow is time away; following someone else starts over; a whole day elsewhere forgets them. Saved with the world, so a session ending in the middle of the day does not lose it.
- [x] **Save format 8** (was 7): the world state gains `day_log` and `observer`. Migration 7 → 8 (both start empty), real fixture `tests/fixtures/saves/v7_world.sav` (written by the M6.3 code), test.
- **Deviations:**
  - **No "neighbour" or family word with the name** ("talks to Jon", not "talks to neighbour (Jon)") — the family words are on the card right below.
  - The timeline is on the **full** card only (the half card has no room for a paragraph).
  - Only "today" (or yesterday, before the day begins) is shown, though two days are kept.
  - OBSERVER is only unlocked and announced; nothing shows it yet (achievements are displayed from M25).
  - A new world's first day has no "wakes": people are up when it opens.
- **Caught while building:** waking was not logged when someone slept out (the sleep step ends before the next plan is made); getting up, lying down again for two minutes and getting up gave "wakes · wakes"; an evening of talk filled half the ring with "talks to …" lines; the timeline was set in the body font and took half the card.
- **Verified:** `test_day_log` (9): the log's rules (same thing, brief things, moments, rounds of talk, the ring), days told apart, saving and unusable data, every kind in words — and words for every activity, reaction, stimulus and kind of work there is —, what people turn to written down as it happens, what they notice, **a whole day reading like a life for everyone** (wakes first, eats, goes to bed, in order, nothing twice in a row), the watch's arithmetic (a tenth away is allowed, a minute more is not; starting over; forgetting; saved), and the achievement unlocked once and announced. `test_day_log_in_game` (5): the card's Today in the running game (keeps up, wraps, stays on screen, yesterday after midnight), people writing their own days, **following someone for a day through `Main` unlocks OBSERVER** (and three hours away delays it), following someone else starts over, the version-7 save. Suite: **925 passing**, no engine errors. The card seen on Mobile and Compatibility in portrait (`C:\tmp\m64`).
- **Phone (Note20): not done** — nothing has been sent to the phone since it was found in use. The build is ready (`build/wiab-debug.apk`); the world there (version 7) will be migrated to 8 on first launch.

### M6 — Completion summary
All four sub-phases are done (M6.1–M6.4): the calendar, clock and speed control; day and night; routines and sleep; the day log and the OBSERVER hook. **925 automated tests.**
- **Automated tests named in the plan:** `test_clock_calendar` (`test_game_clock.gd`), `test_routine_bias` (`test_routines.gd`), `test_day_log` (`test_day_log.gd`, `test_day_log_in_game.gd`).
- **Manual** ("follow one person for a full day at Normal and at Fast; verify the log reads like a life; check night visuals on device"): the first two are automated as far as a machine can judge (a day followed through `Main`; every person's second day checked for waking, meals, work, bed and order) and the logs were read — e.g. *"05:25 wakes · 05:25 goes home · 05:40 drinks · … · 08:04 plays · 11:44 eats · 13:02 plays · 17:00 tags along with Fubrudu · 18:30 goes home · 19:36 goes to bed"* for a child. **Night visuals on the device: not checked** (see below).
- **Performance** ("Very Fast (16×) with 20 people holds 60 FPS desktop / 30 FPS low-end"): measured on the desktop, a whole game day at Very fast with 20 people, one of them followed with the full card open: **60.0 FPS** on Mobile (1 frame of 2,698 over 33 ms, worst 35.5 ms) and on Compatibility (none over 33 ms); simulation 0.40–0.46 ms per frame on average, worst 2.3 ms (budget 4 ms). **Low-end / phone: not measured.**
- **Phone:** nothing of M6 has been on the phone. The phone was found in its owner's hands during the M5.6 check, and nothing has been installed or sent since. Outstanding there: the speed control's place and size (M6.1), the night's look, frame rate and the crickets (M6.2), an evening with dinner, the fire and lights out (M6.3), the Today paragraph on the card (M6.4), and the M5.5 journal card and M5.6 follow hint from before. `adb install -r build/wiab-debug.apk` puts the M6.4 build on it; the world there migrates from version 7 to 8.
- **Save format:** 7 → 8 over the milestone (day log, observer watch), with a real fixture and migration. (M6.3 added a tenth conviction per person without a version step: appended and padded on load.)
- **Exit criterion** — *"The player can follow one person through an entire day and understand their life."* — following works for a whole day and the day is written out on the card; whether it is *understood* is a hands-on judgement: **pending the owner's verdict**.
- **Still to judge by hand:** the speed control top right; how dark the night is; sunset at 19:15; how regimented the working hours are (`Brain.ROUTINE_FACTOR` / `ROUTINE_PULL`); sleepers dreaming of a touch about 70 % of the time; the wording of the day log; whether Today belongs on the half card too; the card covering the followed person when it is fully open in portrait.
- **Not in M6 on purpose:** stars and a moon in the sky (the camera always looks down); meals at home and households' own food (M7); bedtime stories (M11, hook only); showing achievements (M25); a settings screen for speeds or the clock (VS.1 / M14).

### M6 — Tests & checks
**Automated:** `test_clock_calendar` (rollover minute→year; speed multipliers), `test_routine_bias` (at 21:00 sleep dominates for adults; at 08:00 work dominates), `test_day_log`.
**Manual:** follow one person for a full day at Normal (12 min) and at Fast; verify the log reads like a life; check night visuals on device.
**Performance:** Very Fast (16×) with 20 people holds 60 FPS desktop / 30 FPS low-end (tiers auto-lower later; for now verify headroom).
**Exit criteria:** *The player can follow one person through an entire day and understand their life.*

---

## M7 — BASIC WORLD SIMULATION

**Goal:** From "animated diorama" to "simulation" — basic cause and effect without the player. (P:M7, S§24, S§32, B§11, B§17.3, B§21.1–21.2, B§12)
**Depends on:** M6. **Split into 5 sub-phases.**

### M7.1 Resources & nodes
- [ ] `data/resources/*.tres` (`ResourceDef`: id, category, stack, spoilage, weight, icon): food (berries, meat, fish, grain), water, wood, stone, clay (defined), herbs (defined).
- [ ] Resource **nodes** (trees, rocks, berry bushes, fish shoals) get quantity + regrowth (`data/configuration/resources_config.tres`); depletion visibly changes props (stump, smaller bush).
- [ ] Gathered items are **physical**: carried (visible on person) → dropped into **stockpile** (pile props in storage area) — piles are loose-object-like and **player-movable** (moving food is an intervention).

### M7.2 Settlement, stockpile & job board v0
- [ ] `scripts/civilization/settlement.gd` (one settlement now): members, households, buildings, stockpile, job board.
- [ ] `stockpile.gd`: physical storage counts per resource at storage tiles/buildings; spoilage per day.
- [ ] `job_board.gd`: posts jobs from simple rules (food stock < N days → forage/fish; wood < N → chop; hut damaged → repair); people's brains score jobs as Work activities (nobody assigned).

### M7.3 Simple agriculture
- [ ] Field tiles (`terrain = FARMLAND`) with crop stages (planted → sprout → growing → ripe → harvested), growth driven by moisture/fertility/temperature (moisture from M3 water + placeholder rain); farmer occupation; plant/tend/harvest actions; fertility depletion.
- [ ] Crop failure possible (dry soil) → **visible** (brown crops).

### M7.4 Animals v1
- [ ] `scripts/environment/animal_system.gd` + `data/species/*.tres`: deer-like grazer, rabbit, fox-like predator, fish (aggregate per water body), birds (existing ambient).
- [ ] State machines: graze, drink, sleep, flee (from people/predators/stimuli), wander within home range, mate (simple population growth), hunted (hunter occupation → meat).
- [ ] Views pooled like people; far zoom aggregates.

### M7.5 Event log with causality (D-14) + notifications v0
- [ ] `scripts/history/world_event.gd` + `event_log.gd` (B§21.1): `EventLog.record(type, params, causes := [])`, significance from `data/events/*.tres`, persistent, queryable by type/time/location/participant.
- [ ] Emit events: resource discovered, crop failure (causes: dry spell condition id), **food shortage** (causes: crop failure/depletion), person hungry-sick, first farm, first storage, animal hunted, player interventions (all).
- [ ] `scripts/core/notification_manager.gd` → autoload **NotificationManager** v0: priority threshold, rate limit, merge window; toast UI (`scenes/ui/toast.tscn`) with Locate.
- [ ] `scripts/simulation/stats_recorder.gd` v0: hourly samples of population, food, water, wood, stone, health avg (feeds VS stats panel).
- [ ] Shortage responses: rationing (eat less → mood drop), forage further, eat seed grain (next harvest suffers — a real consequence chain), gossip about hunger.

### M7 — Tests & checks
**Automated:** `test_gathering` (woodcutter reduces tree quantity & increases stockpile), `test_consumption` (eating reduces stock), `test_production_crops` (growth stages under moisture; failure when dry), `test_spoilage`, `test_event_causes_recorded` (crop_failure → food_shortage chain has cause ids), `test_event_persistence`, `test_animal_population_bounds` (no explosion/extinction in 20 game years headless with defaults).
**Manual:** starve the settlement by moving all food piles away (player intervention) → shortage events → responses; watch a harvest.
**Soak (headless):** 10 game years, 8 → population stays alive under defaults (no births yet — lifecycle in M10; verify no stuck states), invariants pass.
**Exit criteria:** *The world can experience basic cause and effect without player intervention.*

---

## M8 — THE FIRST REAL PLAYER POWER (MOTION)

**Goal:** The signature "box" interaction — tilt and shake the physical world. (P:M8, S§50–52, B§23.5–23.7)
**Depends on:** M7 (people react, water sim v0, loose objects).

### M8.1 SensorManager
- [ ] `scripts/sensors/sensor_manager.gd` → autoload **SensorManager**: reads `Input.get_gravity()` / `get_accelerometer()` / `get_gyroscope()` ⚠ at a fixed rate only while enabled + focused + world visible; detects availability (all-zero readings for N frames → unavailable); publishes `tilt_vector` (smoothed, calibrated, dead-zoned, clamped) and `shake_event(class, intensity, direction)`.
- [ ] `motion_filter.gd`: low-pass, dead zone, clamp, NaN/Inf rejection, spike rejection (B§31.11).
- [ ] `shake_detector.gd`: high-pass linear acceleration, peak + direction reversals in window, duration, classify LIGHT/MEDIUM/STRONG/EXTREME, per-class cooldowns (B§23.6).
- [ ] Desktop **virtual sensors**: IJKL tilt, Space/Shift+Space/Ctrl+Space shake classes; on-screen debug joystick for emulators.

### M8.2 Calibration & settings
- [ ] `scenes/ui/calibration.tscn`: "Place your phone flat." → "Hold still." (variance check) → "Calibration complete." + "Use current angle as level".
- [ ] Settings: motion enable, tilt/shake/rotation sensitivity, recalibrate, reduced motion (B§30).
- [ ] Touch alternative for devices without sensors: two-finger "tilt drag" gesture (hidden setting on; default on when sensors unavailable).

### M8.3 Tilt effects
- [ ] Box visual tilt: `WorldView` root rotates by smoothed tilt (≤ 6° visual, scaled), camera stays → strong physical illusion (disabled in reduced motion).
- [ ] Gravity bias → `water_sim` flow bias; → loose objects slide when tilt > object's friction threshold; animals/people stumble at high tilt.
- [ ] Stimulus `WORLD_TILT` (global, anomalous) → reactions (look up, grab onto things, pray, run to open ground); memories ("the day the world leaned").

### M8.4 Shake effects & the first disaster
- [ ] LIGHT: leaves, birds scatter, pebbles jiggle. MEDIUM: objects scatter, people stumble, fear. STRONG: **earthquake (minor)** — `disaster_system.gd` v0: building damage chance, injury chance, terrain micro-changes (rare height −1/+1 on steep tiles), major event. EXTREME: **earthquake (major)** — collapses, possible deaths (death handling minimal until M10: record event, remove person safely, obituary stub).
- [ ] "Gentle hands" setting (D-08) gates STRONG/EXTREME; default ON until player finds it in Settings or after the tutorial step "Try tilting the box." has been completed and N minutes played (designer decision — record).
- [ ] Earthquake produces events with causes (intervention id), notifications, strong haptic.

### M8 — Tests & checks
**Automated:** `test_motion_filter` (dead zone, clamp, NaN rejection, smoothing convergence), `test_shake_classifier` (synthetic traces: single spike → none; light oscillation → LIGHT; long strong → STRONG; cooldown respected), `test_tilt_water_bias` (water accumulates on low side), `test_earthquake_effects_bounded`.
**Manual (device):** calibrate; tilt slowly (nothing below dead zone); tilt 15° → water visibly flows, pebbles slide, people react; phone bumping on table → no false shakes; deliberate shakes of increasing strength produce the four classes; motion off → no effects.
**Android:** test on device **with and without gyroscope**; emulator virtual sensors.
**Battery:** sensors off when paused/backgrounded/menus open (verify with logs).
**Exit criteria:** *A player tilts the phone and immediately understands "I'm physically affecting this world."*
**Risks:** Nausea/annoyance → subtle visual tilt, reduced motion; accidental destruction → cooldowns + Gentle hands.

---

## M9 — WEATHER AND ENVIRONMENT

**Goal:** The world is ecologically reactive; environment and civilization influence each other. (P:M9, S§21–23, B§10)
**Depends on:** M8. **Split into 6 sub-phases.**

### M9.1 Weather state machine & visuals
- [ ] `scripts/environment/weather_system.gd` + `climate.gd`: Markov per season from `data/configuration/weather_<climate>.tres`; states & conditions (B§10.1); temperature (season base + daily curve + weather + microclimate); wind vector.
- [ ] `scripts/rendering/weather_fx.gd` + `scenes/world/weather_fx.tscn`: rain/snow particles confined to the box (cheap, GPU/CPU fallback), cloud cover darkening, fog (volumetric off on mobile — use depth fog), lightning flash, wind affects sway shader strength + particle drift.
- [ ] Audio layers: rain intensity, wind, thunder.

### M9.2 Seasons
- [ ] Season effects: vegetation palette shift (shader uniform), leaf fall in autumn, snow cover in winter (terrain shader snow mask by temperature), frozen shallow water (walkable ice flag), crop rules (no planting in winter; harvest in autumn), animal behaviour (mating spring, migration autumn).
- [ ] Civilization adaptation: storage/firewood jobs increase before winter (planner reads season forecast), planting in spring.

### M9.3 Hydrology v2
- [ ] Rain adds water per tile; evaporation (temperature, wind); soil absorption → `moisture`; springs & river inflow sources; lake levels; **floods** (water on settled tiles > threshold → flood event with causes); drying riverbeds in drought; frozen water in winter.
- [ ] Coarse update for inactive chunks (equilibrium approximation), fine step for active chunks.
- [ ] Erosion (very slow, rare height change on high-flow tiles) → recorded as terrain modification.

### M9.4 Soil & vegetation
- [ ] `soil_system.gd`: moisture/fertility dynamics; flood silt increases fertility.
- [ ] `vegetation_system.gd`: grass density growth/decline; tree saplings spawn near trees; drought/cold die-off; regrowth on abandoned land; forest coverage stat.
- [ ] Wildfire hooks (fire system in M12/M32) — define interfaces now.

### M9.5 Player environment tools
- [ ] **RAIN** tool: press-and-hold over area → cloud forms → rain amount by duration (Gentle → Moderate). Stimulus `RAIN_FROM_CLEAR_SKY` if sky was clear (anomalous!).
- [ ] **WIND** tool: swipe → gust (pushes particles, sways trees, blows light objects, extinguishes/spreads fire later). Stimulus `SOURCELESS_WIND`.
- [ ] **WATER** tool (from M3 prototype): scoop/pour, drag to carve shallow channel = **redirect water** (Moderate, terrain modification).
- [ ] Dragging a tool through water leaves a **trail of ripples** (`WorldEffects.ring` along the path); OBSERVE drag across terrain → tile-info trail. (Moved from M2.3: with the hand tool a drag pans the camera.)
- [ ] Tool reveal: RAIN appears after first natural rain *or* first drought-stressed crop; WIND after first storm; WATER after first water tap/swipe ×3. Tool bar gets a subtle glow on reveal.

### M9.6 Civilization reactions
- [ ] Seek shelter in rain/storm/cold; work slows in heat; drought → crop failure → food shortage chain (causes recorded); floods → damage, relocation of homes to higher ground (planner reads flood memories); cold → firewood demand, illness risk.
- [ ] People interpret *natural* weather too (spiritual cultures may start attributing all rain to the Presence).

### M9 — Tests & checks
**Automated:** `test_weather_transitions` (Markov respects probabilities over 10k steps within tolerance; seasons switch tables), `test_weather_effects` (rain raises moisture; evaporation lowers), `test_drought_detection`, `test_flood_event_causes`, `test_season_crop_rules`, `test_vegetation_bounds`.
**Manual:** make rain over a dry field during drought → crops recover → people react; flood the village with tilt + rain → damage + relocation; watch a full year at Very Fast.
**Soak:** 20 game years headless: no runaway water volume, vegetation within bounds, invariants hold.
**Performance:** rain particles + water sim + 20 people ≥ 30 FPS low-end.
**Exit criteria:** *The environment and civilization influence each other.*

---

## VS — VERTICAL SLICE GATE

**Goal:** Assemble the plan's **First Vertical Slice** and prove the core: take a player from *"What's this?"* to *"Oh wow, that person remembers what I did."* (P: First Vertical Slice, S§105–106, B§26.1–26.3)
**Depends on:** M0–M9.

### Slice content checklist (from the plan)
16–32 world tiles (use 32×32) · water · trees · rocks · one tiny settlement · 5–10 inhabitants · simple homes · food · basic needs · day/night · basic weather · touch interaction · moveable rock · water disturbance · tilt · one simple disaster (earthquake) · individual inspection · follow mode · simple memories · basic statistics · hamburger menu · save/load.

### VS.1 Hamburger menu v0 (subset of M14)
- [ ] `scenes/ui/hamburger_menu.tscn`: sliding panel; sections WORLD (Weather), PEOPLE (Individuals list → locate/select), HISTORY (Recent events list, tappable Locate), PLAYER (Interaction history, basic counters), SETTINGS (Audio, Haptics, Motion, Save). Hidden entries for future systems.

### VS.2 Statistics v0 (subset of M15)
- [ ] Panel with population, food days-of-stock, water, wood, stone, average health, mood, weather now; sparkline per stat from `StatsRecorder`.

### VS.3 Save UX v0 (subset of M22)
- [ ] Title flow: first launch → straight into world (no title); later launches → straight into world with an unobtrusive corner "☰ → Settings → Save" containing **Continue/New World/Backup/Reset (confirm)**.
- [ ] Autosave every 2 min + on pause; backup rotation working; corrupted main save → auto-restore from backup (manual test with a corrupted file).

### VS.4 First launch & FTUE
- [ ] Box-opening intro (≤ 6 s, skippable by tap), camera settles on a walking person, *"Something lives inside."*
- [ ] Hint chain (B§26.3) wired to real triggers; hints never repeat once done.

### VS.5 Polish pass (Tier 1 FUN focus)
- [ ] Juice the five key moments: first touch reaction, rock drop, tilt slosh, rain from clear sky, earthquake. Sound + haptic + particles + reaction timing.
- [ ] Tune reaction variety & memory text; make "remembers what I did" visible: when a previously-touched person sees the player's rock/rain/touch again, the card and an emote show recognition; memory line references the earlier event ("It touched me again — like at the river last spring.").

### VS.6 Slice playtest (mini M26)
- [ ] 3–5 fresh players, no instructions; observe 10 min each; follow Appendix 4 protocol; record findings.
- [ ] Android: low + mid device, portrait + landscape, background/resume, kill process → world persisted.

### VS Exit criteria (GO / NO-GO)
- [ ] **GO** if: most testers touch a person within 60 s; most discover tilt within 5 min (with hint); at least half spontaneously comment on a person's reaction/memory; no crashes; world persists across kill/relaunch; ≥ 30 FPS low-end.
- [ ] **NO-GO →** iterate on M2–M9 feel (do **not** start M10). Record what failed and why.

---

## M10 — FAMILIES AND RELATIONSHIPS

**Goal:** Turn individual NPCs into a society; the player can follow a family and care what happens to its members. (P:M10, S§15–17, B§16)
**Depends on:** VS = GO.

### M10.1 Relationships
- [ ] `scripts/people/relationship_store.gd`: sparse pair store (B§16.1), cap per person with pruning, `get(a,b)`, `modify(a,b, deltas, reason_event_id)`, kind flags, `to_dict/from_dict`, validation (drop pairs with missing ids).
- [ ] Social interaction actions: Converse (topic from memories → gossip), Help, Gift, Argue, Fight (rare, aggressive), Teach, Flirt; outcomes via trait compatibility + context; events for notable changes (became friends, rivalry began, reconciliation).
- [ ] Relationship-aware utility: socialize with friends, avoid rivals, help family.

### M10.2 Lifecycle: partnership, birth, aging, death
- [ ] `scripts/people/lifecycle_system.gd` (daily): aging & life-stage transitions (children grow visibly), partnership formation (affinity, age, availability, culture norms), pregnancy (food security, housing), **birth** (named via name generator + family naming conventions; traits inherited with mutation), elder transition, **death** rolls (age curve × health × conditions) and causes (old age, illness, injury, starvation, disaster, accident).
- [ ] `health`: injuries (earthquake/fall/fight), illness (cold, bad water, crowding — simple), recovery with rest/herbs.
- [ ] `household.gd`: household entity (members, home, shared stock), splits when adults partner, merges for care of orphans/elders.
- [ ] Inheritance: home, possessions, family memories to heirs.

### M10.3 Death creates history
- [ ] `scripts/history/history_archive.gd`: move dead persons to **HistoricalPerson** compact records (B§16.3); graves as tappable world objects (Read · View Family).
- [ ] Obituary event with significance; mourning behaviour (family mood, visits to grave).
- [ ] All references to dead ids resolve via archive (UI) or null (sim).

### M10.4 Family UI
- [ ] Person card: family section (parents, partner, children, siblings) tappable → select/locate (living) or open archive record (dead).
- [ ] `scripts/ui/widgets/family_tree.gd`: scrollable tree across generations incl. the dead (S§16 example).
- [ ] Menu: PEOPLE → Families, Relationships (per person list).

### M10 — Tests & checks
**Automated:** `test_relationship_creation`, `test_relationship_changes` (positive interactions raise affinity; conflict lowers; reconciliation possible), `test_birth` (preconditions; traits inheritance within bounds), `test_aging_stage_transitions`, `test_death_archives_person`, `test_inheritance`, `test_family_tree_reconstruction` (incl. dead), `test_malformed_relationship_repair`.
**Soak:** 100 game years headless from 8 people: population doesn't explode/extinct under defaults (target band tunable), ≥ 4 generations, invariants pass, save/load at year 50 identical continuation (same seed, deterministic).
**Manual:** follow a family across 3 generations at Very Fast; view tree; visit a grave.
**Exit criteria:** *The player can follow a family and become interested in what happens to its members.*

---

## M11 — MEMORY AND HISTORY

**Goal:** Actions persist beyond the moment; the world begins generating stories naturally. (P:M11, S§18, S§61–62, S§64, B§15, B§21)
**Depends on:** M10.

### M11.1 Memory types expansion
- [ ] Personal memories for life events ("Flood experienced." "Child born." "Parent died.") via templates.
- [ ] **Family memories:** parents → children transmission (bedtime stories at 20:00; elders tell grandchildren), fidelity decay, reinterpretation by listener's traits.
- [ ] **Cultural memory pool** per settlement: aggregated when N members share memories of a subject; decays when unheld.
- [ ] **Mythological distortion v0:** mutation on retelling (B§15.4); cluster detection of same stimulus type attributed to one agent type → **Myth** record (name placeholder until M17 lexicon: epithet only — "the Rainbringer").

### M11.2 Historical record & significance
- [ ] `scripts/history/significance.gd`: event significance weights (data), person significance accumulation, "firsts" ledger (first farm, first child born, first death, first touch, first storm…).
- [ ] Important people v0 (threshold) → PEOPLE/HISTORY → Important People.

### M11.3 Timeline UI
- [ ] `scripts/history/timeline_model.gd` + `scenes/ui/panels/timeline.tscn`: years grouped (YEAR 1 · settlement founded; YEAR 7 · first farm …), filters (major, people, disasters, player), virtualized list (large histories).
- [ ] Tapping an event **locates** its position (or participants/grave/descendants if position invalid).

### M11.4 Player history view
- [ ] PLAYER → Interaction History as a year-stamped log of significant interventions (B§27.2), linking to consequences once the story engine exists (M19).

### M11 — Tests & checks
**Automated:** `test_family_memory_transmission`, `test_cultural_pool_formation`, `test_myth_formation` (repeated rain-in-drought in a spiritual population forms a myth within N events), `test_significance_firsts`, `test_timeline_locate_fallbacks`, `test_history_persistence`.
**Manual:** make rain during 3 droughts → a myth forms; check a grandchild's memory of the grandparent's touch (REMEMBERED hook).
**Exit criteria:** *The world begins generating stories naturally* — a tester can read the timeline and retell a story that wasn't scripted.

---

## M12 — BASIC CIVILIZATION

**Goal:** Move beyond a village: recognizable communities with different characteristics. (P:M12, S§26, B§17)
**Depends on:** M11. **Split into 5 sub-phases.**

### M12.1 Settlement planner & construction
- [ ] `settlement_planner.gd` (daily): needs → projects (B§17.2 table; early set: shelter/hut/house, storage, well, farm plots, workshop) with site scoring (flatness, flood memory, proximity, sacredness).
- [ ] `construction_system.gd`: project entity (footprint, required materials, progress), builders fetch materials physically, stages visible (`construction_view.tscn`: scaffold → frame → complete), events ("Construction of the first well has begun.").
- [ ] `data/buildings/*.tres` (`BuildingDef`: footprint, materials, capacity, function tags, tech req, era variants).
- [ ] Buildings take damage (quakes, floods, storms) → repair jobs; abandonment → decay → ruin (history!).

### M12.2 Roads & traffic
- [ ] Traffic accumulation per tile from walking; decay; thresholds → path → road (tech later); pathfinder cheaper on roads; bridges as projects when crossing frequency high.

### M12.3 Migration & multiple settlements
- [ ] `migration_system.gd`: triggers (overcrowding, scarcity, conflict, disaster, adventurous individuals), group formation (households), destination scoring (explored tiles only! → exploration matters), journey, **founding** of a new settlement (founder significance, naming placeholder until M17).
- [ ] Settlement tiers derived (Camp → Hamlet → Village → Town → City).

### M12.4 Trade & specialization
- [ ] Specialization emerges from local resources/skills (farming/mining/fishing); `trade_system.gd`: traders carry surpluses between settlements along roads; abstracted when not visible; trade statistics.
- [ ] Workshops: craft tools (tools increase work output — first "tools" stat).

### M12.5 Governance v0
- [ ] `governance.gd`: leader emerges per settlement (respect/relationships/age/founder); leader influences planner priorities and cultural priors; leadership succession events.

### M12 — Tests & checks
**Automated:** `test_planner_proposes_storage_when_overflow`, `test_construction_consumes_materials`, `test_building_damage_repair`, `test_traffic_to_road`, `test_migration_founds_settlement`, `test_trade_moves_surplus`, `test_leader_emergence`.
**Soak:** 150 game years: ≥ 2 settlements typically form on River Valley seeds; no deadlocks; invariants.
**Manual:** watch a village grow; see a road form; watch a migration group found a new hamlet.
**Exit criteria:** *The world contains recognizable communities with different characteristics.*

---

## M13 — CAMERA, MAP AND EXPLORATION SYSTEM

**Goal:** Prepare for a world that grows beyond the initial screen without breaking camera or performance. (P:M13, S§4–7, S§41–42, B§8.6–8.7)
**Depends on:** M12.

### M13.1 Chunk streaming
- [ ] `scripts/world/chunk_streamer.gd`: visual load radius around camera (frustum + margin), unload distant chunk views to pool; data chunks remain in memory if modified or active, otherwise **evicted and regenerated on demand** (sparse storage); simulation activity per chunk tied to tier manager.
- [ ] Mesh building off the main thread (`WorkerThreadPool` ⚠ — build arrays in worker, create `ArrayMesh` on main thread).

### M13.2 World growth — the Box Unfolds (D-05)
- [ ] `scripts/world/box_unfolder.gd`: conditions (B§8.6), adds a chunk ring, animates walls outward, extends pathfinder grid, records **major event** "The Edge Moved", notifies; deterministic terrain beyond old walls.
- [ ] Advanced New World option: start box size 64/128/256.

### M13.3 Minimap & map
- [ ] Minimap (bottom-right, collapsible): `Image` updated incrementally from tile layers (per changed chunk) → `ImageTexture`; icons for settlements, selected person, events, important locations; unexplored dimmed; **tap to move camera**; drag to scrub.
- [ ] WORLD → Map full-screen with pan/zoom, layers toggle (terrain, water, settlements, fog, events).

### M13.4 Fog of knowledge & exploration
- [ ] `fog_of_knowledge.gd`: player-seen / civ-explored / civ-mapped layers (B§8.7); rendering desaturates unknown areas (shader uniform texture).
- [ ] Explorer behaviour: adventurous people explore frontier; discoveries of places; explorers may reach the **Edge** (event, first steps of box research).
- [ ] Regions: automatic clustering (valley, eastern mountains…) named with direction glosses now, lexicon names in M17.

### M13.5 Home & Locate complete
- [ ] Home → primary settlement (largest/capital). Locate for person, building, settlement, event, discovery (search list in menu + chips on cards/notifications).

### M13 — Tests & checks
**Automated:** `test_chunk_evict_regenerate_identical`, `test_streaming_loads_visible`, `test_unfold_extends_bounds_and_pathing`, `test_minimap_tap_to_world`, `test_fog_layers`, `test_camera_never_lost` (random pans/zooms/unfolds keep pivot valid).
**Performance:** 256×256 world with 2 settlements: memory within budget; streaming hitch < 8 ms per chunk on device.
**Exit criteria:** *The world can become significantly larger without breaking the camera or performance.*

---

## M14 — HAMBURGER MENU + INFORMATION SYSTEM

**Goal:** The player understands the state of the world without debug tools. (P:M14, S§8, B§26.5)
**Depends on:** M13.

- [ ] Full menu structure (B§26.5) with progressive reveal (hidden until system active).
- [ ] Panels: WORLD (Map, World Overview, Regions, Weather, Environment, Resources) · PEOPLE (Population, Individuals with search/sort/filter, Families, Occupations, Relationships, Important People) · CIVILIZATION (Settlements, Buildings, Economy, Agriculture; Technology/Culture/Government/Beliefs/Science stubs appear with their milestones) · HISTORY (Timeline, Events, Discoveries, Disasters, Wars (later), Eras (later)) · PLAYER (Interactions, Statistics, Discoveries, Influence, Box Knowledge (later)) · SETTINGS (Audio, Haptics, Motion, Graphics, Simulation Speed, Accessibility, Notifications, Save, Advanced/seed copy, Debug-if-flag).
- [ ] Reusable widgets: list with virtualization, detail card, section header, chip, "Locate" button, empty state text ("Nothing recorded yet.").
- [ ] Orientation-responsive layouts (side panel in landscape, full-height sheet in portrait); menu never fully covers the world in landscape.
- [ ] Seed display & **Copy seed** (`DisplayServer.clipboard_set`).
**Tests:** `test_menu_visibility_rules`, UI smoke test scene that opens every panel with a large fixture world (no errors, < 100 ms open).
**Exit criteria:** *The player can understand the state of the world without developer tools* — testers answer 5 questions ("How many people? Who's the oldest? What happened last year? Which settlement has most food? What's the weather?") in < 2 minutes.

---

## M15 — STATISTICS

**Goal:** Turn the simulation into something players enjoy studying. (P:M15, S§9, B§27.1)
**Depends on:** M14.

- [ ] `StatsRecorder` full: all categories (B§27.1) derived from sim data; multi-resolution time series (hourly for recent days, daily for years, yearly for centuries) with bounded storage; saved.
- [ ] `scripts/ui/widgets/chart.gd`: sparkline, line chart (pan/zoom time), stacked bars (age distribution), colourblind-safe palette + shape markers.
- [ ] Panels: Population · Economy · Society · Environment · Player (B§27.3 counters).
- [ ] **Progressive reveal:** stat appears after the underlying system produces data (e.g., inequality only after multiple households with differing wealth).
- [ ] Derived "insight" lines ("Food production fell 30% after the drought of Year 12.") using events + series.
**Tests:** `test_stats_derived_not_static` (changing sim data changes stats), `test_series_downsampling`, `test_stats_persistence`.
**Exit criteria:** Testers voluntarily open statistics twice in a session and find something they didn't know.

---

## M16 — TECHNOLOGY

**Goal:** Long-term progression; civilization visibly changes as knowledge increases. (P:M16, S§27, B§18)
**Depends on:** M15. **Split into 3 sub-phases.**

### M16.1 Knowledge model
- [ ] `scripts/civilization/knowledge.gd`: domain points per person and per settlement (B§18.1); accrual from work/curiosity/teaching/failure/player interventions; oral knowledge loss on death without students; teaching action.

### M16.2 Technology system
- [ ] `data/technologies/*.tres` (`TechnologyDef`, B§18.2) — Fire through Mathematics/Engineering first (Electricity/Industrialization/Computing/Advanced Science defined but gated by later content).
- [ ] `technology_system.gd` (daily): evaluate discovery opportunities from conditions → roll → pick inventor (skill/curiosity/intelligence weighted) → `technology_discovered` + event + notification ("Someone has discovered a new use for copper.") + significance to inventor.
- [ ] Unlocks: buildings, occupations, actions, interpretations (PHYSICS/EXPERIMENT later), vocabulary concepts, visuals.
- [ ] Tech diffusion between settlements via trade/migration.

### M16.3 Visible change
- [ ] Every implemented tech changes something visible (B§18.3): tools in hands, new building variants, lamps at night, pottery props, clothing colours, new sounds.
- [ ] CIVILIZATION → Technology panel: known techs as a timeline + "what they're close to" hints (vague: "Potters are experimenting with fire and clay.").
- [ ] Civilization phase evaluator (B§22.1) → era events ("The Age of Copper").
**Tests:** `test_tech_requires_conditions` (no discovery without resources even after 1,000 years), `test_tech_inventor_attribution`, `test_knowledge_loss_oral`, `test_tech_diffusion`, `test_phase_evaluator`.
**Soak:** 300 game years on 5 seeds: tech order varies with conditions; no tech appears without prerequisites.
**Exit criteria:** *Civilization visibly changes as knowledge increases.*

---

## M17 — CULTURE AND BELIEF (+ LANGUAGE)

**Goal:** Civilizations become culturally distinct; player interventions can become culturally significant. (P:M17, S§29–31, B§19)
**Depends on:** M16. **Split into 3 sub-phases.**

### M17.1 Culture profile & traditions
- [ ] `culture_system.gd`: profile per settlement (B§19.1) derived yearly; traditions from repeated emotional shared events (B§19.2–19.3); rituals as scheduled social activities; holidays in calendar; festivals as world events ("The harvest festival starts at dusk.").
- [ ] Architecture style & clothing palette variants per culture (visual parameters).

### M17.2 Belief & religion
- [ ] `belief.gd` aggregation: interpretation distribution per settlement feeds culture priors (closing the loop with M5 interpretation).
- [ ] `myth_system.gd` full: myths with attributes, sacred places (tile flag SACRED), shrines/temples via planner, religious founders (important people), schisms & spread.
- [ ] CIVILIZATION → Beliefs, Culture panels.

### M17.3 Language (structured vocabulary)
- [ ] `lexicon.gd`: concept registry (`data/text/concepts.csv`), culture phonology (from M4 name generator), word coining by concept frequency, inheritance, borrowing, drift after separation (B§19.5).
- [ ] UI shows words with glosses everywhere names appear (myths, places, eras, the Presence).
- [ ] Settlement/region names switch from placeholders to lexicon names (with history record "River Town came to be called Tiravel").
**Tests:** `test_tradition_from_repetition`, `test_culture_divergence_after_split` (two settlements separated 100 years differ in priors/lexicon), `test_lexicon_coining_threshold`, `test_word_inheritance`, `test_myth_split_merge`.
**Exit criteria:** Two settlements in one world are clearly distinguishable by beliefs, names and rituals; at least one tradition traceable to a player action.

---

## M18 — SCIENCE AND THE PLAYER MYSTERY

**Goal:** The beginning of the deeper mystery: scientists notice patterns. (P:M18, S§28, S§35, B§20, B§25.2)
**Depends on:** M17.

- [ ] `anomaly_archive.gd`: anomalies from observed stimuli (oral → written after Writing), witness counts, attributes (time of day, location, type, context).
- [ ] `science_system.gd`: scientist occupation (after Natural philosophy), investigation actions (travel, observe, record), **correlation checks** (B§20.2 table: time-of-day clustering using the player's real sessions, world-scale tilt, rain-after-drought responsiveness, watched-area correlation), hypotheses as records with confidence; publications → notifications ("Scientists noticed a strange correlation between rainfall and your interactions.").
- [ ] Seeded mysteries activated (`data/mysteries/*.tres`): artifact, ruins, ancient structure, recurring anomaly, missing civilization, impossible material, terrain pattern — each a clue chain with conditions (B§25.2).
- [ ] `box_research.gd` stages 1–4 (B§20.3): anomaly noticed → pattern → external force hypothesis → Edge expeditions.
- [ ] PHYSICS and EXPERIMENT interpretations unlocked by tech; science vs faith dynamics.
- [ ] PLAYER → Box Knowledge panel: what the civilization *thinks* (hypotheses, confidence), never the truth.
**Tests:** `test_anomaly_recorded_only_if_witnessed`, `test_time_of_day_correlation_detects_pattern` (synthetic sessions at 20:00 → hypothesis forms), `test_mystery_chain_progression`, `test_box_research_stage_gates`.
**Exit criteria:** In an accelerated test world, scientists form at least one correct-ish hypothesis about the player; the reveal is partial and intriguing.

---

## M19 — EMERGENT STORY ENGINE

**Goal:** Turn simulation events into compelling stories the developers didn't write. (P:M19, S§60, B§21.3)
**Depends on:** M18. **Split into 3 sub-phases.**

### M19.1 Conflict model (prerequisite for the canonical chain)
- [ ] Resource/territory disputes between settlements → raids → **war** (abstracted battles, casualties, heroes, survivors) → peace/borders; factions around beliefs/interests; revolution chance (B§17.5). Rare and costly.

### M19.2 Chain mining
- [ ] `story_engine.gd`: yearly + on major events, walk causal graph (`causes[]`), score chains (Σ significance, length, novelty, participants' significance), select top chains; avoid repeats.
- [ ] Event/era naming ("The Great Drought", "The River War", "The Years of the Leaning World") via templates + lexicon.

### M19.3 Summaries & presentation
- [ ] Templates `data/text/history.csv` for chain shapes (cause → consequence → outcome) producing: *"The Great Drought of Year 83 caused the northern migration and eventually contributed to the River War."* / *"…led to the founding of Northwatch."*
- [ ] HISTORY → Major Events & Eras show summaries; Player History links interventions to outcomes ("YEAR 31 · saved a settlement from drought").
- [ ] "A historian has proposed a new explanation for the Great Flood." — historians reinterpret old events (myth vs record).
**Tests:** `test_chain_detection_on_fixture_graph`, `test_summary_template_filling`, `test_no_duplicate_story`, `test_war_chain_records_causes`.
**Exit criteria:** In 3 soak worlds (300 years), each produces ≥ 3 multi-step summaries a reader finds coherent.

---

## M20 — OFFLINE PROGRESSION

**Goal:** The world is genuinely persistent: "What happened while I was gone?" (P:M20, S§40, S§87, B§9.4, B§26.8, B§31.8)
**Depends on:** M19.

- [ ] `offline_simulator.gd` (B§31.8): day-step abstract sim for all systems; produces real named births/deaths/constructions/discoveries/events **with causes**; deterministic given seed + start state + elapsed.
- [ ] Elapsed computation with caps (D-09) and clock-tamper guards.
- [ ] Runs on resume/launch **before** showing the world, with progress indicator if > 1 s; target < 2 s for 24 h on mid-range (profile!). Optionally chunk the work across frames with a "The box is settling…" animation.
- [ ] `scenes/ui/while_you_were_gone.tscn`: counts + one intriguing hook with Locate (B§26.8); items tappable.
- [ ] Surprise Director (B§25.3) makes sure long absences contain at least one notable natural event if plausible.
- [ ] Setting (open question B§35.5): "World rests while I'm away" (off by default).
**Tests:** `test_offline_determinism`, `test_offline_caps`, `test_offline_vs_realtime_statistical_parity` (1 year offline vs 1 year Tier-1 real-time: population/resources within tolerance), `test_clock_tamper_ignored`, `test_wywg_summary_contents`.
**Exit criteria:** Close app for 8 real hours → reopen → believable, specific summary; the hook makes a tester tap Locate.

---

## M21 — PERFORMANCE / SCALE PASS

**Goal:** Prove the architecture handles growth: 100 / 500 / 1,000 people, many settlements & chunks, long world age. (P:M21, S§53–55, S§97, B§31.6–31.7)
**Depends on:** M20. **Split into 4 sub-phases.**

### M21.1 Measurement harness
- [ ] Headless stress scenarios (`tests/soak/`): spawn 100/500/1000 people across settlements; 256² and 512² worlds; 500-year histories; record sim ms per game hour, memory, save size/time.
- [ ] On-device benchmark scene (fixed camera path) logging FPS/frame ms/draw calls to file.

### M21.2 Simulation tiers complete
- [ ] Tier 2 (regional coarse movement), Tier 1 (abstract per settlement hourly using offline-sim rules), Tier 0 (daily) — promotion/demotion with hysteresis; **consistency tests** when switching tiers mid-action.
- [ ] AI throttling by frame budget; staggered thinks; perception limited to Tier ≥ 3 (others use aggregate reactions).

### M21.3 Rendering scale
- [ ] Object pooling everywhere; MultiMesh for crowds and resting objects at mid/far zoom; LOD for buildings; visibility culling per chunk; material/texture atlasing to minimize draw calls.

### M21.4 Data scale
- [ ] Hierarchical pathfinding (chunk graph + local A*); memory compaction; history archive compression (old events summarized, raw kept compressed); relationship pruning; stats downsampling. Evaluate GDExtension for water/pathfinding hot loops **only if** budgets are missed (record D-decision).
**Targets:** 1,000 people, 512² world, 500 years: ≥ 30 FPS low-end / 60 FPS mid-range at typical zoom; sim ≤ 4 ms/frame; memory within budget; save < 300 ms (B§33).
**Exit criteria:** *The game remains playable as the civilization becomes significantly larger than the prototype.*

---

## M22 — ROBUST SAVE SYSTEM

**Goal:** The player trusts their world will never disappear. (P:M22, S§56–57, B§31.9)
**Depends on:** M21.

- [ ] Freeze save schema for v1 release format; `SAVE_VERSION` policy; migration chain with fixture saves from every previous version in `tests/fixtures/`.
- [ ] Save snapshot on main thread (fast dict build) → compress/hash/write on `WorkerThreadPool` thread; lifecycle saves synchronous-fast path (must finish within Android pause window — measure).
- [ ] `save_validator.gd`: schema validation & repair (dangling ids, malformed relationships, out-of-bounds coords, NaN) → quarantine section.
- [ ] Manual save, auto save, backups UI (list with dates/years/population; restore; export to shared storage via Android share intent — optional ⚠), Reset World with hold-to-confirm + second confirmation.
- [ ] Low storage handling (write failure → keep old save, warn gently, retry later).
**Torture tests:** force close during save (kill process via adb mid-write) ×20 → always loadable; background app; kill process; low storage (fill emulator storage); malformed save (random byte flips, truncation) → backup restore; old save version → migrates.
**Automated:** `test_atomic_rotation`, `test_corruption_detection_matrix`, `test_migration_chain_all_fixtures`, `test_validator_repairs`, `test_quarantine`.
**Exit criteria:** zero data-loss in torture matrix.

---

## M23 — DEBUG AND DEVELOPMENT TOOLKIT (complete)

**Goal:** Make future development dramatically easier. Not optional. (P:M23, S§69–70, B§31.10)
**Depends on:** M22 (but most tools already exist from Track T1 — this milestone completes and polishes).

- [ ] Debug panel (touch-friendly, tabs): **Sim** (pause, step one tick, speed, advance hour/day/year, force generation), **Spawn** (person, animal, resource, object, building), **Remove/kill**, **Teleport camera** (coords, entity id), **Weather** (set state/condition), **Disasters** (earthquake/flood/drought/fire/meteor/storm), **Events** (trigger any event type, test notification), **Tech** (force technology), **Inspect** (entity, AI state, chunk layers, memory, relationships, save state/size), **Box research** (force stage).
- [ ] Overlay complete: FPS, CPU frame time, sim ms, memory, active entities, visible entities, simulation entities by tier, chunks loaded, sim ticks, save size, world age, population, rendered objects/draw calls.
- [ ] Heatmap overlays (moisture, fertility, traffic, fog, temperature, water).
- [ ] Log viewer (ring buffer, filter by category), "Export bug report" (log + save + device info zip to `user://bugreports/`).
- [ ] Invariant checker on demand + periodic in debug builds.
- [ ] All debug UI stripped/disabled in release unless debug flag.
**Exit criteria:** A new bug can be reproduced from a bug report bundle on desktop.

---

## M24 — MOBILE POLISH

**Goal:** Genuinely good on Android. (P:M24, S§49–50, S§72–74, S§96–98, B§30, B§31.12)
**Depends on:** M23.

- [ ] Device matrix (Appendix 2): low/mid/high; portrait/landscape; resolutions & aspect ratios (incl. notches — safe area via `DisplayServer.get_display_safe_area()` ⚠); devices without gyroscope/accelerometer.
- [ ] Optimize: rendering (quality presets Low/Medium/High auto-detected + manual), battery (frame cap 30/60, low-processor mode in menus, sensors off when not needed), memory, sensor polling rate, UI (layout thrash), loading (cold start < 6 s low-end), saving.
- [ ] Settings complete: haptics, reduced motion, accessibility (UI scale, text size, high contrast, colourblind-safe markers), audio buses.
- [ ] Interruption tests: incoming call, notification shade, low battery mode, split screen, rotation mid-gesture, app termination by OS, save during background transition.
**Exit criteria:** Full Appendix 2 matrix passes; no ANR; battery drain per 10 min session within target (measure baseline vs idle app).

---

## M25 — FIRST "REAL GAME" BUILD

**Goal:** Stop thinking of it as a prototype; integrate everything into a coherent game. (P:M25, S§105, B§26–27)
**Depends on:** M24.

- [ ] Feature audit against P:M25 list: persistent world · exploration · touch · camera · zoom · people · personalities · needs · relationships · families · resources · buildings · weather · seasons · animals · civilization · history · statistics · technology · culture · player interactions · motion controls · saving · offline progression · Android support. Each item: works / feels good / known issues.
- [ ] FTUE complete: first 10 minutes sequence (B§26.2) verified end-to-end; all contextual hints; tool reveals; menu progressive reveal.
- [ ] **Achievements** (B§27.4): local unlocks, subtle toast, PLAYER → Achievements.
- [ ] Notification tuning (priority, merge, rate) with a 2-hour real-time session log review.
- [ ] Content minimum: 6 start templates at least 2 fully tuned; ≥ 20 techs; ≥ 15 buildings; ≥ 6 species; ≥ 40 event types with templates; ≥ 6 seeded mysteries.
- [ ] Bug bash: all P1/P2 bugs fixed; crash-free 10-hour soak on device (screen on, Normal speed).
- [ ] Versioning: `0.5.0`, version code incremented; release build signed; internal distribution (Play internal testing track or direct APK).
**Exit criteria:** Build is shippable to external playtesters.

---

## M26 — PLAYTESTING

**Goal:** Discover the game's natural behaviour with people who've never seen the spec. (P:M26)
**Depends on:** M25.

- [ ] Recruit 8–15 testers across ages/phone types; **do not explain** mechanics.
- [ ] Observe first sessions (in person or screen-recorded), then 1 week of natural use.
- [ ] Measure (Appendix 4): where they tap · dragging understood · people discovered · understand who people are · motion discovered · menu opened · time spent on what · what's ignored · what makes them smile · what confuses · what brings them back.
- [ ] **Local-only analytics** (offline-first, opt-in, no network): session log of anonymized counters (session length, features used, time to first touch/tilt) exportable by the tester via share sheet.
- [ ] Ask questions only after observing. Synthesize findings into a ranked list (Tier 1 FUN first).
**Exit criteria:** Findings report with top 10 issues and top 5 delights.

---

## M27 — RETENTION THROUGH CURIOSITY

**Goal:** "I want to check what happened." — improve based on playtests, never with artificial timers. (P:M27, S§36–38, S§86–88, B§25.3, B§26.9)
**Depends on:** M26.

- [ ] Forbidden list (enforced in review): energy systems, timers, daily chores, artificial waiting, forced rewards, login rewards, "come back" notifications.
- [ ] Improve: discoveries (clearer reward moments), emergent events (World Events B§26.9: meteor showers, migration seasons, experiments, festivals — simulation-driven), mysteries (clue pacing), interesting people (surface "people to watch" in WYWG), historical consequences (story engine links), world changes (visible diffs on return: "new since last visit" markers on map for 1 session), surprises (Surprise Director tuning).
- [ ] Optional opt-in Android system notifications for rare major world events only (default OFF) ⚠ local notifications plugin/API check for 4.7.
**Exit criteria:** In a second playtest round, ≥ 60% of testers return unprompted on ≥ 3 days of a week.

---

## M28 — THE CIVILIZATION STARTS NOTICING YOU

**Goal:** Major content milestone: player awareness as a rich, group-varied model — not a morality score. (P:M28, S§19, S§90, B§24)
**Depends on:** M27.

- [ ] `player_relationship.gd`: derived measures per person/settlement/culture (awareness, interpretation mix, trust, fear, curiosity/scientific interest, dependence, independence, divine/scientific belief, intervention frequency) (B§24).
- [ ] Group behaviours: scientists investigate, children tell stories (child-sourced myths with high distortion), religious groups worship (offerings, prayer gatherings at anomaly sites), skeptics reject (debates, social friction), fearful groups appease or flee.
- [ ] Consequence patterns implemented & tested: dependence (reduced self-reliance projects when help is frequent), fear (appeasement rituals, avoidance), independence (innovation bonus), selective help (jealousy/conflict).
- [ ] PLAYER → Influence / Reputation panels show descriptive trends per group ("In Tiravel, most believe the Rainbringer is kind. In Northwatch, scholars call it 'the Leaning Force'.").
- [ ] "NAMED" achievement when a culture coins a word for the Presence.
**Tests:** `test_dependence_reduces_wells`, `test_disasters_raise_fear_rituals`, `test_rare_intervention_innovation_bonus`, `test_group_interpretation_divergence`.
**Exit criteria:** Two playstyles (helper vs hands-off) on the same seed produce clearly different civilizations after 200 years.

---

## M29 — BOX THEORY

**Goal:** The civilization discovers evidence its world is enclosed — a new chapter, not an ending. (P:M29, S§28, S§92, B§20.3, B§7.3)
**Depends on:** M28.

- [ ] Box research stages 4–7: Edge expeditions & measurement (impossible geometry: perfectly flat, straight, unscalable), Sky's Ceiling observations (observatories/towers), The Edge Moved evidence (if unfolding happened), external-force proofs from tilts, strange material analysis, recurring player patterns.
- [ ] **THE BOX THEORY** major historical event: debate period — factions (believers, skeptics, religious reframing: "the Box is the Rainbringer's hand"), publications, possible conflict; new buildings (edge stations, observatories); new vocabulary.
- [ ] Revelation record "THE BOX"; THE BOX achievement; notification & special WYWG hook.
**Tests:** `test_box_theory_requires_evidence` (no Box Theory without edge + tilt + literacy conditions), `test_box_theory_debate_factions`.
**Exit criteria:** In an accelerated world, Box Theory emerges from evidence and is debated; normal play continues afterwards.

---

## M30 — COMMUNICATION WITH THE PLAYER

**Goal:** Inhabitants deliberately attempt to communicate. Only after the core simulation is stable. (P:M30, S§93–94, B§22.4)
**Depends on:** M29.

- [ ] `communication_system.gd`: civilization-side experiments: count patterns (stone circles), geoglyph symbols built from buildings/objects (visible from max zoom), light signals at night (fires in patterns), mathematical sequences.
- [ ] Player-side channels detected: tap patterns (count/rhythm near a signal), arranged objects, environmental responses (rain on the glyph, tilt toward it).
- [ ] Emergent protocol (B§22.4): count → response recognized → yes/no convention → sequences → symbol exchange; **Communication Log** (what they think the player said).
- [ ] "Someone has left a message." NEW DISCOVERY moment: zoom to the giant symbol.
- [ ] Voice/text (optional, late, B§35.6): design doc only unless approved; if built, microphone permission requested **only** on activation.
**Tests:** `test_pattern_detection_tap_counts`, `test_protocol_progression`, `test_false_positive_rate` (normal play doesn't accidentally "answer" too often).
**Exit criteria:** A tester who notices the symbol can intentionally "reply" and see the civilization react within the session.

---

## M31 — POST-BOX DISCOVERY

**Goal:** The civilization experiments on its own world to understand the player. (P:M31, S§92–93, B§22.2–22.3, B§25.4)
**Depends on:** M30.

- [ ] Revelations: **THE OUTSIDE** (evidence of an external environment: light through the lid, sound, the player's phone movement patterns), **THE OBSERVER** (intelligence confirmed), **THE SECOND BOX** (signals/materials from elsewhere), **THE CREATOR QUESTION** (investigation of the box's origin — never answered).
- [ ] Evidence of **previous civilizations** (ruins lineage; optional previous-world echoes B§25.4).
- [ ] Behaviours: attempts to **predict** the player (they schedule events at the player's usual play times!), experiments to influence the player (building offerings/structures for the player), disagreement about the player's existence, structures built specifically for the player, mathematical patterns.
**Exit criteria:** A long-lived test world keeps producing new, surprising player-directed behaviour after all revelations.

---

## M32 — POLISH AND CONTENT

**Goal:** Breadth, only after systems are proven. (P:M32, S§68)
- [ ] More biomes & start templates: forest, desert, island, mountain, frozen, volcanic, swamp, ocean, unusual/alien (per-biome data + palettes + species).
- [ ] More animals, resources, technologies (through Electricity/Industrialization/Computing/Advanced Science), buildings, cultural variations, events, mysteries, visual variety, sound, environmental effects (wildfire system full, meteor, volcanic).
- [ ] **Sandbox mode** (B§27.5) as a separate world type.
- [ ] Late-era visuals: industrial smoke/pollution, electric lights, labs, observatories.

## M33 — ADDITIONAL BOXES

**Goal:** Alternate worlds that feel mechanically different — only when the original box is excellent. (P:M33)
- [ ] Box types: DESERT (water scarcity), ISLAND (ocean & naval development), FROZEN (extreme climate), VOLCANIC (constant geological danger), MYSTERY (physics behaves strangely: altered gravity bias, water rules), ARTIFICIAL (the civilization realizes the terrain is constructed — accelerated mystery).
- [ ] Box shelf UI (multiple saves), per-box offline progression, cross-box evidence hooks (Second Box revelation) (B§35.9).

## M34 — CONTENT UPDATE ARCHITECTURE

**Goal:** Add technologies, buildings, animals, events, biomes, discoveries and mysteries without rewriting the simulation. (P:M34, S§79)
- [ ] Content registry scanning `data/**` with ids, versioning, and **validation tool** (editor plugin or headless script): missing references, invalid requirements, unreachable techs, missing text keys.
- [ ] Content schema versioning + save compatibility for removed/renamed content (id aliases).
- [ ] Documentation: "How to add a technology/building/species/event/mystery" guides with examples.

## M35 — RELEASE CANDIDATE

**Goal:** Verify everything before release. (P:M35)
Checklist (all must be green):
- **Gameplay:** fun · understandable · stable · surprising · replayable.
- **Android:** installation · startup · touch · sensors · audio · haptics · background/resume · saving · performance.
- **Simulation:** population · resources · AI · relationships · history · events.
- **Data:** save · load · backup · migration.
- **Performance:** memory · FPS · battery · large populations · long simulation.
- **UX:** tutorial · menus · accessibility · settings · notifications.
- Store readiness: privacy statement (no data collected unless opt-in export), permissions justification (VIBRATE), content rating, screenshots, target API level compliance ⚠ (check current Play requirements), AAB export.

---

# PART F — MILESTONE SUMMARY TABLE

| # | Milestone | Key deliverable | Gate question |
|---|---|---|---|
| M0 | Foundation | Runs on desktop + Android; services, tests, save skeleton, debug overlay | Builds clean everywhere? |
| M1 | The Box | Chunked generated diorama in a box | Enjoyable to stare at? |
| M2 | Touch the World | Gestures, camera, picking, feedback, Home | Explorable by touch alone? |
| M3 | Physics | Grab/drop objects, water v0, intervention choke point | Does the player experiment? |
| M4 | First Inhabitants | 6–8 people with needs, goals, paths | Does it feel inhabited? |
| M5 | First Contact | Person card, interpretation → reaction → memory | Do they care about someone? |
| M6 | Time & Daily Life | Calendar, day/night, routines, follow log | Can they follow a whole day? |
| M7 | Basic Simulation | Resources, stockpiles, farming, animals, causal event log | Cause & effect without player? |
| M8 | Motion | Tilt, shake, calibration, earthquake | "I'm physically affecting this world"? |
| M9 | Weather & Environment | Weather, seasons, hydrology, rain/wind/water tools | Environment ↔ civilization? |
| VS | Vertical Slice Gate | Menu v0, stats v0, save UX, FTUE, playtest | "That person remembers what I did"? |
| M10 | Families | Relationships, births, deaths, family tree | Do they follow a family? |
| M11 | Memory & History | Family/cultural memory, myths v0, timeline | Stories emerge? |
| M12 | Civilization | Planner, construction, roads, migration, trade, leaders | Distinct communities? |
| M13 | Map & Exploration | Streaming, unfolding, minimap, fog, Locate | Bigger world, still smooth? |
| M14 | Menu & Info | Full hamburger menu | Understandable without debug? |
| M15 | Statistics | Derived stats + charts | Enjoyable to study? |
| M16 | Technology | Knowledge, condition-based tech, visible change | Visible progress? |
| M17 | Culture & Belief | Traditions, religion, lexicon | Distinct cultures from player acts? |
| M18 | Science & Mystery | Anomalies, correlations, mysteries, box research 1–4 | Do they start studying you? |
| M19 | Story Engine | Conflict, chain mining, summaries, eras | Unscripted coherent stories? |
| M20 | Offline | Abstract sim + WYWG | "What happened while I was gone?" |
| M21 | Scale | Tiers, pooling, hierarchy, 1,000 people | Playable at scale? |
| M22 | Robust Save | Migrations, torture tests | Zero data loss? |
| M23 | Debug Toolkit | Complete tools & bug reports | Repro any bug? |
| M24 | Mobile Polish | Device matrix, battery, accessibility | Great on Android? |
| M25 | Real Game | Integrated, achievements, content minimum | Shippable to testers? |
| M26 | Playtesting | Observation findings | What's natural? |
| M27 | Curiosity Retention | World events, discovery tuning | Do they come back? |
| M28 | Noticing You | Player relationship model | Playstyles diverge worlds? |
| M29 | Box Theory | Evidence → Box Theory event | Debated, not the end? |
| M30 | Communication | Signals, protocol, log | Can the player reply? |
| M31 | Post-Box | Revelations, prediction, experiments | Still surprising? |
| M32 | Content | Biomes, species, techs, sandbox | Breadth? |
| M33 | More Boxes | Alternate box types | Mechanically distinct? |
| M34 | Content Pipeline | Registry, validation, guides | Add content without code? |
| M35 | Release Candidate | Checklist | Ready? |

---

# APPENDICES

## Appendix 1 — Android device debugging workflow (S§76)

> ⚠ Exact menu names vary by phone manufacturer and Android version; Godot export requirements (JDK/SDK/build-tools versions) must be checked against the Godot 4.7 "Exporting for Android" docs.

**One-time setup (PC, Windows):**
1. Install Android Studio **or** the Android SDK command-line tools; install *platform-tools*, the *build-tools* and *platform* versions Godot 4.7 requires; install the required OpenJDK version.
2. Godot → Editor Settings → Export → Android: set **Java SDK Path** and **Android SDK Path**. Godot can generate a debug keystore automatically ⚠; otherwise create one with `keytool`.
3. Godot → Project → Install Android Build Template (only if using Gradle builds/plugins).
4. Add `platform-tools` to `PATH` so `adb` works in a terminal.

**Phone setup:**
1. **Enable Developer Options:** Settings → About phone → tap **Build number** 7 times (on some phones under Software information).
2. **Enable USB debugging:** Settings → System → Developer options → **USB debugging** ON. (Optionally **Wireless debugging** on Android 11+.)
3. **Connect the phone** via a data-capable USB cable; on the phone, accept "Allow USB debugging?" (tick "Always allow from this computer").
4. **Verify the device:** `adb devices` → shows `<serial>  device` (if `unauthorized`, re-accept the prompt; if missing, check cable/driver — on Windows install the OEM USB driver or Google USB driver).

**Build, install, launch:**
5. **Export/build the APK:** Project → Export → *Android Debug* → Export Project → `build/wiab-debug.apk` (or headless: `godot --headless --path . --export-debug "Android Debug" build/wiab-debug.apk`).
   **Fast iteration:** use Godot's **Remote Deploy / One-click deploy** (Android icon in the editor toolbar) — it builds, installs and launches, and connects the remote debugger (breakpoints, remote scene tree, errors in the editor).
6. **Install the APK:** `adb install -r build/wiab-debug.apk` (`-r` keeps data; add `-d` to allow version downgrade).
7. **Launch:** tap the icon, or `adb shell monkey -p com.happihack.worldinabox.dev -c android.intent.category.LAUNCHER 1`.

**Logs, crashes, repro:**
8. **View Godot/Android logs:** `adb logcat -s godot` (Godot's tag) or `adb logcat | findstr /i "godot wiab"` on Windows; clear old logs first with `adb logcat -c`. The game's own file logs: `adb shell run-as com.happihack.worldinabox.dev ls files/logs` (debuggable builds only) and pull with `adb exec-out run-as com.happihack.worldinabox.dev cat files/logs/<file> > local.log`.
9. **Capture crashes:** `adb logcat -b crash` for native crashes; `adb bugreport bugreport.zip` for full reports; in-game "Export bug report" bundle (M23) for save + logs + device info. Note ANRs under `adb shell dumpsys activity anr` ⚠.
10. **Reproduce bugs:** use the bug report's seed + save; load on desktop with the debug panel; for sensor bugs, record sensor traces in debug mode (SensorManager can log raw samples to a file) and replay them into `shake_detector` tests.
11. **Clear save data during testing:** `adb shell pm clear com.happihack.worldinabox.dev` (wipes all app data), or selectively: `adb shell run-as com.happihack.worldinabox.dev rm -r files/saves`. In-game: Settings → Save → Reset World (confirm).

**Emulator testing:** Android Studio AVD with a recent system image; **Extended controls → Virtual sensors** to simulate device rotation/accelerometer (use for tilt tests; shake is best tested on real hardware). Enable host GPU. Treat emulator performance as meaningless — performance is measured on devices only.

**Useful extras:** `adb shell dumpsys batterystats --reset` then play 10 min then `adb shell dumpsys batterystats > batt.txt` for battery; `adb shell dumpsys meminfo com.happihack.worldinabox.dev` for memory; `scrcpy` for screen mirroring/recording during playtests.

## Appendix 2 — Mobile test matrix (S§72–73)

| Axis | Values |
|---|---|
| Device tier | Low-end (≈3–4 GB RAM, older GPU), mid-range, high-end |
| Screen | small phone, large phone, tablet; aspect 16:9, 19.5:9, 20:9, foldable if available |
| Orientation | portrait, landscape, rotation during gestures and panels |
| Sensors | with gyroscope; accelerometer only; no motion sensors (emulator/tablet) |
| Lifecycle | cold launch; background/resume; return after 10 min / 8 h / 3 days; OS kills app in background; force stop; reboot |
| Interruptions | incoming call; notification shade; alarm; split screen; screen off/on; low battery mode; battery saver |
| Storage | nearly full storage during save |
| Settings | reduced motion, large text, high contrast, haptics off, audio off, motion off |

Each cell: pass/fail + notes, recorded in the milestone report (M24 and M35 require the full matrix; other milestones test at least 1 low + 1 mid device).

## Appendix 3 — Performance measurement protocol

1. Use **release-like export** (debug symbols OK, verbose logging off) on a physical device, battery > 50%, not charging, screen brightness fixed, 2 minutes warm-up.
2. Run the **benchmark scene** (fixed camera path over the world for 60 s at Normal speed, then 30 s at Very Fast).
3. Record: average FPS, 1% low, frame time p95, sim ms/frame (overlay counter), draw calls, memory (static + video ⚠ monitors), active/visible/simulated entities by tier, chunks loaded, save size & time.
4. Compare against B§33 budgets; regressions > 10% block the milestone.
5. Keep results in `docs/perf_log.md` per milestone.

## Appendix 4 — Playtest observation protocol (P:M26)

- **Before:** device charged, fresh install (or specified save), screen recording on, observer silent. Only say: "This is a game. Play however you like. Think aloud if you want."
- **Observe (10–15 min):** time to first pan, first tap, first person tap, first card open, first follow, first tilt (with/without hint), first menu open; what they say aloud; smiles/laughs; confusion moments (hesitation > 5 s, repeated failed gestures).
- **Then ask:** "What do you think this is?" · "Who were the people you saw?" · "What happened when you touched someone?" · "What do you think happens when you close it?" · "What would you do next time?" · "What was confusing?" · "Anything you wanted to do but couldn't?"
- **Follow-up (1 week):** did they reopen? how often? what did they check first? (from opt-in local session log export).
- **Synthesis:** rank findings by Priority Stack tier (B§3.1).

## Appendix 5 — Sub-phase ticket template

```markdown
### M<n>.<k> — <title>
Goal:
Bible refs:
Files (new/modified):
Tasks:
- [ ]
Tunables added:
Save changes (SAVE_VERSION bump? migration?):
Debug additions:
Tests (automated + manual):
Android check:
Perf budget:
Done when:
```

## Appendix 6 — Known Issues register

| ID | Milestone | Severity | Description | Status |
|---|---|---|---|---|
| KI-1 | M0.8 | Low (until real UI exists) | In landscape the UI renders at ~56% scale (canvas designed for 1080-wide portrait, `canvas_items` + `expand`), so text/touch targets are too small. Needs a landscape scale policy (e.g. `content_scale_factor` by orientation) when HUD work starts (M2.4 / M14 / M24). | **Fixed in M2.4** (`UIRoot.ui_scale_for`) |
| KI-2 | M0.8 | Low | Debug overlay sits at the top-left edge; on devices with corner cut-outs it should respect `DisplayServer.get_display_safe_area()` (M24). | Open |
| KI-4 | M1.8 | Info | Godot logs `Couldn't present to Vulkan queue (VK_ERROR_SURFACE_LOST_KHR)` when the app is sent to the background on Android. Engine-level (the OS removes the surface); no data loss and the app resumes normally. Watch for it in M24 lifecycle testing. | Open |
| KI-3 | M0.8 | Info | Project is built with the .NET (mono) Godot editor/templates although it is pure GDScript; standard build recommended (pending decision D-15). | Open |
| KI-5 | M2.6 | Low (cosmetic) | With the camera at the settlement, birds passing between the camera and the ground look like large dark shards (they are two flat dark triangles each, drawn for the far-away framed view). Needs smaller/lighter birds or a fade when close to the camera (M1.5 ambient life; revisit with wildlife in M10). | Open |
| KI-6 | M3.2 | Low | On Android the log files in `user://logs` are empty when the app is killed (force-stop, reinstall): the file sink is not flushed. Flush on WARN and above and every few seconds. | Open |

## Appendix 7 — Immediate next steps

1. **Confirm D-01** (3D stepped diorama vs 2D isometric) and skim the other PROPOSED decisions in `game_bible.md` §32.
2. Verify Godot 4.7.2 + Android toolchain are installed (`godot --version`, `adb version`).
3. Start **M0.1** (project creation & settings). Each sub-phase should end with the project running and tests green.

*End of Implementation Phases v1.0.*
