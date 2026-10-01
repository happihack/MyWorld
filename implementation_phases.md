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

## M0 — PROJECT FOUNDATION

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

### M0.8 Android export & device loop (Track T5) — ✅ DONE except hands-on multi-touch + release keystore (2026-09-30)
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
- [ ] **Hands-on multi-touch check** — pinch, twist and three-finger tap with real fingers (cannot be injected via `adb shell input`).
- [ ] **Release keystore** — create with `keytool`; supply via env vars `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD` (never committed). Needed before any release build.
- **Finding:** the project is pure GDScript but the installed Godot is the **.NET (mono) build**. Export works (Godot warns "Exporting to Android when using C#/.NET is experimental", non-blocking), but the **standard (non-.NET) Godot 4.7.2 + standard templates** is the recommended toolchain: no experimental path, smaller engine library. Decision pending (would be D-15).

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

### M1.1 World data model (chunked from day one — D-13)
- [ ] `scripts/world/world_coords.gd`: static funcs `tile_to_chunk(v: Vector2i)`, `tile_to_local`, `chunk_origin`, `tile_to_world3d(tile, height)`, `world3d_to_tile`, all floor-correct for negatives.
- [ ] `scripts/world/chunk_data.gd` (RefCounted): `coord: Vector2i`, layers per B§8.3 as packed arrays of 256; `get_/set_` accessors by local index; `dirty_flags` (mesh, water, save); `modified: bool`; `to_dict()/from_dict()` storing only if modified.
- [ ] `scripts/world/world_data.gd` (RefCounted): `bounds: Rect2i` (box interior), `chunks: Dictionary[Vector2i, ChunkData]` ⚠ typed dicts (4.4+), `get_chunk(coord, generate_if_missing := true)`, tile-level accessors that route to chunks, `is_in_bounds(tile)`, `modified_chunks()`.
- [ ] `scripts/world/spatial_index.gd` (RefCounted): chunk-bucketed `id → tile` and `chunk → PackedInt64Array ids`, `query_radius(center, r, type_mask)`, `move(id, from, to)`.
- [ ] `data/configuration/world_config.tres` (`WorldConfig`: chunk_size, initial_world_tiles, height_levels, height_step, max_world_tiles).

### M1.2 World generation
- [ ] `scripts/world/world_generator.gd`: `generate_chunk(coord, seed, template) -> ChunkData` deterministic; uses `FastNoiseLite` with seeds derived from named streams; height shaped by **start template** masks; terrain type from height/moisture; initial vegetation; river carving (template-driven path from inflow to basin); lake basin.
- [ ] `scripts/world/start_templates.gd` + `data/worldgen/*.tres`: River Valley (first world default) implemented fully; other five stubbed with parameters (implemented in M32).
- [ ] Resource/prop placement pass: trees (clusters), rocks, berry bushes — placed as **entity records** (`PropData`/resource nodes minimal: id, type, tile, variant) into registry + spatial index (full resource semantics in M7).
- [ ] Starting settlement placeholder: choose site by scoring (flat, near water, not flood-prone, near trees) → 3 hut **building records** (static for now) + a campfire.
- [ ] Mysteries seeding stub: reserve generator stage `seed_mysteries()` that places 1 ruin record at a far tile (dormant, simple mesh) — proves the pipeline early (full in M18).
- [ ] Validation function `WorldGenerator.validate(world) -> Array[String]` (water reachable from settlement, ≥ N food sources, ≥ M buildable tiles, path connectivity via flood fill).

### M1.3 Terrain rendering
- [ ] `scripts/world/terrain_mesher.gd`: build one `ArrayMesh` per chunk: top faces per tile at height, side faces where neighbour lower (stepped blocks), bevel option, vertex colours from terrain type palette, normals. Use `SurfaceTool` or raw arrays (raw arrays faster) — target < 3 ms per chunk on desktop.
- [ ] `scripts/rendering/chunk_view.gd` + `scenes/world/chunk_view.tscn`: `MeshInstance3D` terrain + water mesh child; rebuild on `dirty_flags.mesh`.
- [ ] Shared material with vertex colours; terrain palette resource.

### M1.4 Water surface (static)
- [ ] `scripts/rendering/water_view.gd`: per-chunk water mesh from `water` layer (quads at terrain+depth where depth > ε).
- [ ] `assets/shaders/water.gdshader`: scrolling normal/colour variation, depth tint, shoreline foam via vertex attribute (depth); must compile in Mobile and Compatibility.

### M1.5 Props & ambient life
- [ ] `scripts/rendering/prop_renderer.gd`: per chunk, one `MultiMeshInstance3D` per prop type (tree variants, rocks, bushes, grass tufts), transform + colour jitter.
- [ ] Low-poly placeholder meshes (`assets/models/`): 2 tree types, 2 rocks, bush, grass tuft, hut, campfire, ruin stones. (Make in Blender or generate procedurally via `SurfaceTool` for now.)
- [ ] `assets/shaders/sway.gdshader` for foliage (vertex wind sway, cheap).
- [ ] Ambient: bird flock (MultiMesh, boids-lite in a script at 10 Hz), campfire smoke (`GPUParticles3D`, low count; `CPUParticles3D` fallback on Compatibility ⚠), cloud shadows (projected scrolling noise in terrain shader or a decal-like plane).

### M1.6 The box & lighting
- [ ] `scenes/world/box_frame.tscn` + `box_frame.gd`: four walls + base built to `WorldData.bounds` (so it adapts to world size/unfolding later), wood/brass material, visible wall thickness, inner wall slightly lighter.
- [ ] `WorldEnvironment`: sky colour, ambient light, tonemap (filmic/ACES ⚠), glow off on low.
- [ ] `DirectionalLight3D` sun (static angle for now; animated in M6); shadows on medium+ only.
- [ ] Fake tilt-shift: vignette + slight top/bottom blur via a cheap screen shader — **setting-gated**, off on low.

### M1.7 Camera rig v0
- [ ] `scenes/world/camera_rig.tscn` + `scripts/rendering/camera_rig.gd`: pivot (target point on XZ) + yaw + pitch + distance; perspective FOV ~32°; `pan(delta_screen)`, `zoom(factor, focal_screen)`, bounds clamp to box (+ margin), smoothing (critically damped). Mouse/touch hooks from InputRouter (drag = pan, wheel/pinch = zoom).
- [ ] `frame_box()` fits the whole box at launch in both orientations (recompute on `get_viewport().size_changed`).

### M1.8 Wire into WorldSession
- [ ] `WorldSession.create_new(seed)` → generate world → WorldView spawns ChunkViews/props/box → camera frames the settlement.
- [ ] Save/load: seed + modified chunks (none yet) + prop/building records → reload shows identical world.

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

### M2.1 Gesture completion & camera polish
- [ ] Recognizer: double tap, swipe classification (velocity > threshold), two-finger drag/twist, gesture cancellation when a second finger lands.
- [ ] Camera: pan **inertia** (fling with decay), pinch zoom around focal point, **rubber-band** soft bounds, double-tap zoom step (animated), optional two-finger twist yaw (setting), zoom limits (min shows single person clearly; max shows whole box + margin).
- [ ] **Home button** (HUD, bottom-right): animates camera to settlement center (B§26.4). Camera can never be lost: if pivot leaves bounds (e.g., bug), snap back.

### M2.2 Picking
- [ ] `scripts/interaction/picker.gd`: screen point → ray → march against height grid (DDA over tiles comparing ray height to tile top) → tile; then spatial index query in touch radius (dp → world units at current zoom) → entity by priority (B§23.3). Returns `PickResult {kind, id, tile, world_pos}`.
- [ ] Debug: draw picked tile outline + entity highlight.

### M2.3 Tap responses (contextual micro-feedback)
- [ ] `scripts/interaction/interaction_manager.gd` (node in WorldSession) v0: `on_tap(pick)`, `on_long_press(pick)`, `on_double_tap(pick)`, `on_swipe(path, velocity)`.
- [ ] Responses per target: **terrain** — dust puff + soft thud; **water** — ripple ring (shader parameter/decal) + plip; **tree** — sway impulse + leaf particles + rustle; **rock** — small wobble + click; **building** — tiny shake + wood knock; **ruin** — faint hum (seed of curiosity).
- [ ] **Swipe** through water → series of ripples; swipe across terrain in OBSERVE → tile info tooltip trail.

### M2.4 Long-press context panel (UI framework v0)
- [ ] `scenes/ui/context_menu.tscn`: radial or compact card anchored near the finger (kept on-screen), options by target type (B§26.6; only options that work now, e.g., Observe/Inspect/Touch). Touch targets ≥ 48 dp.
- [ ] `scripts/ui/ui_root.gd`: panel stack, back button closes top panel (`NOTIFICATION_WM_GO_BACK_REQUEST`), input blocking only where panels are.
- [ ] Inspect card v0 for tile/tree/rock/building: name/type, height, terrain, moisture (debug-ish now; prettified later).

### M2.5 Feedback services (Track T7)
- [ ] `scripts/core/haptics.gd` → autoload **Haptics**: `light()`, `medium()`, `strong()`; rate limit; toggle from Settings; uses `Input.vibrate_handheld(ms, amplitude)` ⚠ verify amplitude parameter in 4.7.
- [ ] `scripts/core/audio_manager.gd` → autoload **AudioManager**: SFX pool (8 `AudioStreamPlayer3D` + 4 2D), buses Master/Ambience/SFX/UI, ambience loop (wind + birds) placeholder.
- [ ] Particles: dust, leaves, ripple, sparkle (low counts, pooled).

### M2.6 FTUE hint v0 (Track T8)
- [ ] `ftue_state` in Settings (per install) + per world; hint "Drag to explore." after 5 s idle; disappears after first pan.

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

### M3.1 Loose objects as data
- [ ] `scripts/interaction/loose_object_system.gd` (node in WorldSession): registry of `LooseObject {id, kind (pebble, rock, boulder, log, fruit, seed, strange_object), tile, offset: Vector2, height_offset, velocity: Vector3, state (RESTING, HELD, FALLING, SLIDING), mass, discovered_by: Array[int], placed_by_player: bool, moved_count}`; spatial index integration; `to_dict/from_dict`.
- [ ] Rocks from worldgen that are "small enough" become loose objects; boulders are movable but heavy (slower drag, stronger thud).
- [ ] `scenes/objects/loose_object_view.tscn` pooled views (or MultiMesh per kind for resting objects + node for moving ones).

### M3.2 HAND tool: grab / carry / drop
- [ ] `scripts/interaction/tools/tool_base.gd` + `hand_tool.gd`: press-and-hold on a loose object (200 ms) → **grab** (object lifts with shadow growing, haptic light); drag → object follows finger at hover height, camera auto-pans at screen edges; release → drop with gravity.
- [ ] Tool bar v0 (`scenes/ui/tool_bar.tscn`): HAND (default) + OBSERVE (visible), others hidden until later milestones.

### M3.3 Lightweight motion integrator
- [ ] Custom integrator (not RigidBody) at fixed 30 Hz for non-resting objects: gravity, landing on tile top, bounce damping, **slide** down steep height differences, friction, settle → RESTING snaps to tile + offset. Collision: objects vs terrain steps, simple circle-vs-circle between objects in same/adjacent tiles, objects vs building footprints (bounce).
- [ ] Rolling boulder down slope knocks small objects (impulse transfer) — predictable, pretty, cheap.

### M3.4 Tree disturbance
- [ ] Tap-hold on tree → **shake** (sway burst + leaves); repeated shakes may drop fruit (loose objects) in season (placeholder: always); strong EARTH later may fell trees.
- [ ] "Remove" (long-press option, Moderate): uproot tree → becomes a log loose object (resources in M7).

### M3.5 Water sim v0 (disturbance)
- [ ] `scripts/environment/water_sim.gd` v0: cellular heightfield flow between tiles using `terrain_height + water` (B§10.3), fixed 10 Hz, active chunks only, time budget; conserves volume (test).
- [ ] Water disturbance: tap/swipe adds a local ripple (visual) + small momentum impulse (pushes floating objects); **scoop/pour prototype** behind a debug flag (becomes WATER tool in M9).
- [ ] Objects dropped into water: splash, sink (rocks) or float (logs, fruit) and drift with flow.

### M3.6 Interventions & player history (start the choke point now)
- [ ] `scripts/interaction/intervention.gd`: `Intervention {id, type, tool, tick, position, target_id, magnitude, params}`.
- [ ] `InteractionManager.apply_intervention(iv)` → validates → dispatches effect to owning system → `EventBus.intervention_applied` → `PlayerHistory.record(iv)` (B§14.6). All M2/M3 actions refactored to go through it.
- [ ] `scripts/interaction/player_history.gd`: append-only log with significance filter (only first-of-kind and major interventions shown later), counters for player statistics (B§27.3).
- [ ] `discoverable` flag: player-moved objects near settlements are marked for M4/M5 inhabitants to discover later (hook only).

### M3.7 Persistence
- [ ] Save/load loose objects (positions, states normalized to RESTING on save), modified trees, water layer for modified chunks, player history.

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

### M4.1 PersonData & registry
- [ ] `scripts/people/person_data.gd` (RefCounted) with canonical fields (B§13.1) — only those needed now plus stubs for later fields (serialized as empty).
- [ ] `scripts/people/person_registry.gd`: `add/get/remove(id)`, iteration by settlement/tier, `to_dict/from_dict`; ids from `IdAllocator`.
- [ ] `scripts/people/traits.gd`: axis enum (B§13.2), random generation from `RngStreams.stream(&"people")`, helper `describe_top(traits, n) -> PackedStringArray`.
- [ ] `scripts/people/name_generator.gd`: **phonology** (syllable sets) seeded per culture — generates given/family names (feeds M17 lexicon later).
- [ ] Occupation defs v0 (`data/occupations/`): forager, woodcutter, builder (placeholder), child, elder.
- [ ] Starting band spawn: 6–8 people in 2–3 households assigned to the placeholder huts.

### M4.2 People rendering (no heavyweight node trees)
- [ ] `scripts/rendering/entity_view_pool.gd`: pool of `person_view` instances; binds view ↔ id for entities in Tier 3/4; releases when out of view.
- [ ] `scenes/people/person_view.tscn` + `person_view.gd`: single low-poly mesh (body+head), per-instance colours (clothing/skin/hair via instance uniforms ⚠), accessory slot mesh, blob shadow; vertex-shader walk bob; smooth interpolation between sim positions; facing.
- [ ] Far zoom: switch to MultiMesh dots/markers (LOD) — people remain findable.

### M4.3 Pathfinding
- [ ] `scripts/people/pathfinder.gd`: `AStarGrid2D` ⚠ over world bounds; per-tile weights from slope, water depth (deep = solid), vegetation, buildings (solid); rebuild weights for dirty chunks only; request queue with per-frame budget; path cache.
- [ ] Movement: people advance along path at speed(age, health, terrain) in sim ticks; views interpolate.

### M4.4 Needs & utility brain
- [ ] `scripts/people/needs.gd`: need enum (start with Hunger, Thirst, Sleep, Social, Purpose, Safety), decay per game minute from `needs_config.tres`.
- [ ] `scripts/people/ai/brain.gd`: utility scoring of activities from `data/activities/*.tres` (`ActivityDef {id, need_weights, trait_weights, time_of_day_curve, requires}`), weighted sampling with per-person temperature, hysteresis.
- [ ] `scripts/people/ai/action_step.gd` + `actions/`: `WalkTo`, `Eat` (from a placeholder food source — campfire/bushes), `Drink` (water tile adjacent), `Sleep` (home), `Work` (woodcutter "chops" tree visually; forager "picks" bushes), `Socialize` (walk to a friend/campfire, face each other), `Explore` (pick unexplored/interesting tile; curiosity-weighted), `GoHome`.
- [ ] Plans are short step lists; current step serializable (B§13.4).
- [ ] **Hungry example must work:** HOME → FOOD → EAT → WORK.

### M4.5 Simulation manager & tiers v0
- [ ] `scripts/simulation/simulation_manager.gd`: per-frame accumulator → sim ticks via `GameClock`; staggered think scheduling; per-frame **sim budget** (B§33) with deferral.
- [ ] `scripts/simulation/tier_manager.gd` v0: Tier 4 (selected), Tier 3 (everyone else for now), with interface ready for Tier 2/1/0 (M21).

### M4.6 Persistence & debug
- [ ] Save/load people fully (including current action & path target; path recomputed on load).
- [ ] Debug: **AI inspector** (tap person with debug on → scores table, current plan, needs), spawn/kill person commands, "freeze AI" toggle; overlay counts: people, active AI, paths/frame.

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

### M5.1 Person card & selection
- [ ] `scenes/ui/person_card.tscn`: bottom sheet (peek / half / full), fields per B§26.6 (name, age, occupation, activity + reason, mood, needs, family, top traits, recent memory). Updates live at 4 Hz.
- [ ] Actions: **Observe** (OBSERVE overlay on this person: needs & path), **Touch**, **Follow**, **Focus Camera**, **Inspect/Learn About** (full card), **Mark Important** (flag + pin list).
- [ ] Selection ring + outline; `EventBus.person_selected`.

### M5.2 Follow & focus
- [ ] Camera follow mode (smooth, keeps person in lower-center third so card doesn't cover); banner "Following Mara ✕"; tier 4 promotion; pan breaks follow (with "Resume" chip).
- [ ] **Locate** chip for selected/marked people (camera flies to them).

### M5.3 Stimulus → perception → interpretation → reaction
- [ ] `perception/stimulus.gd` (B§14.1), emitted by `InteractionManager` for every intervention.
- [ ] `perception/perception_system.gd`: radius query, salience (B§14.2), queue perceptions to people (processed on their think tick, or immediately for direct touch).
- [ ] `perception/interpretation.gd`: scoring (B§14.3) — for now culture_prior = flat seed-derived priors, knowledge gates (only NATURAL, SPIRIT, DEITY, HALLUCINATION, UNKNOWN_INTELLIGENCE available early; ANCESTOR once a death is remembered).
- [ ] `perception/reaction_table.gd` + `data/configuration/reactions.tres`: emotion computation + reaction selection (B§14.4).
- [ ] Reaction actions: LookAt, Freeze, Run (flee away from stimulus), Investigate (walk to the spot, crouch), Pray (kneel), Wave, Laugh (children jump), Yell, Dismiss (shrug), TellSomeone (walk to nearest friend → conversation; creates secondhand memory), Remember.
- [ ] Emote icons above heads (❗ ❓ 🙏 💬 ♪) — sprite3D billboards pooled; readable at mid zoom.

### M5.4 Memory v1
- [ ] `scripts/people/memory.gd` + `memory_store.gd` (B§15.2): personal memories with importance, fidelity, source; cap + compaction; decay daily.
- [ ] Text templates `data/text/memories.csv` keyed by `subject × interpretation` via `tr()`; e.g., *"At age 23, Mara felt the mysterious presence touch her."* / skeptic variant / child variant.
- [ ] Memories **affect behaviour** now: fear memory near a location lowers that location's utility; positive wonder raises Investigate; repeated touches shift reactions (B§14.5).
- [ ] Discovering player-placed objects (hook from M3.6): a person passing a player-moved rock may Investigate → memory "found a stone that wasn't there yesterday."

### M5.5 Player history & first stats v0
- [ ] Player history shows first-of-kind entries ("YEAR 1 · touched first inhabitant").
- [ ] Counters: total interactions, people touched, objects moved.
- [ ] Achievement hook stored (unlock UI in M25): FIRST CONTACT.

### M5.6 FTUE hints
- [ ] "Try touching someone." (after first pan, person on screen) → "Hold to learn more." → "Follow them to see their day."

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

### M6.1 Calendar & clock
- [ ] `GameClock`: minute/hour/day/season/year from `TimeConfig` (D-04); signals `day_started`, `season_changed`, `year_started` via EventBus; `format_time()`, `format_date()` ("Year 3 · Spring · Day 4 · 06:30").
- [ ] **Speed control** (Pause / Normal / Fast / Very Fast) in HUD top-right; long-press opens selector; pause freezes sim, not UI/camera.

### M6.2 Day/night
- [ ] `scripts/rendering/day_night.gd`: sun angle & colour curves (`Gradient`/`Curve` resources), ambient/sky colour, moon, stars (cheap), night tint; window lights at night (emissive toggle on houses); campfires glow.
- [ ] Night ambience audio (crickets, fire crackle), dawn birds.

### M6.3 Routines & sleep
- [ ] Routine templates per occupation × life stage in `data/occupations/*.tres` (B§13.5) as time-of-day utility biases (soft).
- [ ] Sleep behaviour: go home, lights out, sleeping people are low-salience to stimuli (touching a sleeper → startled/dream interpretation variant: "dreamt of a warm hand").
- [ ] Meals: breakfast/lunch/family dinner as social eating events at home/fire.
- [ ] Children's routines: play, follow parents, bedtime (bedtime stories hook for M11).

### M6.4 Follow-mode day log
- [ ] Per-person **"Today" timeline** (ring buffer of activity changes with timestamps) shown on the card: *06:30 wakes · 07:00 eats · 08:00 works · 12:00 talks to neighbour (Jon) · …*.
- [ ] OBSERVER achievement hook: followed continuously (≥ 90%) for 24 game hours.

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
| KI-1 | M0.8 | Low (until real UI exists) | In landscape the UI renders at ~56% scale (canvas designed for 1080-wide portrait, `canvas_items` + `expand`), so text/touch targets are too small. Needs a landscape scale policy (e.g. `content_scale_factor` by orientation) when HUD work starts (M2.4 / M14 / M24). | Open |
| KI-2 | M0.8 | Low | Debug overlay sits at the top-left edge; on devices with corner cut-outs it should respect `DisplayServer.get_display_safe_area()` (M24). | Open |
| KI-3 | M0.8 | Info | Project is built with the .NET (mono) Godot editor/templates although it is pure GDScript; standard build recommended (pending decision D-15). | Open |

## Appendix 7 — Immediate next steps

1. **Confirm D-01** (3D stepped diorama vs 2D isometric) and skim the other PROPOSED decisions in `game_bible.md` §32.
2. Verify Godot 4.7.2 + Android toolchain are installed (`godot --version`, `adb version`).
3. Start **M0.1** (project creation & settings). Each sub-phase should end with the project running and tests green.

*End of Implementation Phases v1.0.*
