# My World in a Box

A tiny living civilization inside a mysterious box. Godot 4.7.2 · GDScript · Android-first.

- **Design:** [`game_bible.md`](game_bible.md) — what the game is (source of truth).
- **Plan:** [`implementation_phases.md`](implementation_phases.md) — milestones, status, per-phase reports.
- **Original specs:** `my_world.txt`, `my_world_plan.txt`.

## Run

Open the folder in Godot 4.7.2 and press **F5** (main scene: `scenes/main/boot.tscn`), or:

```sh
godot --path .
```

The game continues the most recently saved world; the first launch creates one.
Saves live in `user://saves/<world_id>/` — on Windows:
`%APPDATA%\Godot\app_userdata\My World in a Box\saves\`.

### Desktop controls (development)

| Input | Gesture |
|---|---|
| Left click / drag | Tap (the world answers: dust, ripples, a shaken tree…) / one-finger drag (mouse emulates touch) |
| Double click | Double tap: look at the thing under the cursor, or zoom toward open ground |
| Hold left button | Long press: menu for what is under the cursor (Inspect / Touch / Look closer) |
| Mouse wheel | Pinch zoom at the cursor |
| Right drag | Two-finger drag |
| F3 | Toggle debug overlay (debug builds; on device: three-finger tap) |

Release builds: tap the version label 7 times within 3 s to unlock debug tools.

## Test

```sh
godot --headless --path . -s res://tests/run_tests.gd                      # everything
godot --headless --path . -s res://tests/run_tests.gd -- --filter=save     # path/name filter
godot --headless --path . -s res://tests/run_tests.gd -- --verbose         # show game logs
godot --headless --path . -s res://tests/run_tests.gd -- --shard=1/4       # 1st of 4 slices (parallel runs)
```

Exit code `0` = all passed, `1` = failures, `2` = watchdog abort.

- Tests live in `tests/unit/` and `tests/integration/`, named `test_*.gd`, extending `TestCase`.
- Any **script error** during a test fails it (caught via a `Logger`), as do assertion failures and per-test timeouts (`--test-timeout=`, default 15 s).
- The runner isolates **saves** and **settings** in a per-process folder (`user://test_run_<pid>/`) and deletes it afterwards — your real world is never touched, and parallel runs never collide.
- Runner self-check (must report 3 passed, 4 failed):
  `godot --headless --path . -s res://tests/run_tests.gd -- --dir=res://tests/fixtures/runner_selftest --test-timeout=2`

## Android build

Requires the Android SDK path and JDK 17 set in Godot (Editor Settings → Export → Android).

```sh
godot --headless --path . --export-debug "Android Debug" build/wiab-debug.apk
adb install -r build/wiab-debug.apk
adb logcat -s godot
```

Debug package: `com.happihack.worldinabox.dev` ("WIAB Dev"). See Appendix 1 of
`implementation_phases.md` for the full device workflow.

## Project layout

See `implementation_phases.md` Part D. Key folders: `scripts/` (code by system), `scenes/`, `data/configuration/` (all tunables), `tests/`.
