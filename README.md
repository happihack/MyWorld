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
| Hold left button on a rock, then drag | Pick it up and carry it; release to drop |
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

## iOS build

Exports an Xcode project (needs Xcode and the iOS export templates):

```sh
godot --headless --path . --export-debug "iOS" build/ios/wiab.ipa
cd build/ios && xcodebuild -project wiab.xcodeproj -scheme wiab -sdk iphoneos \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM=N5C88K4XGC CODE_SIGN_STYLE=Automatic build
xcrun devicectl device install app --device <udid> build/Debug-iphoneos/wiab.app
```

Xcode must be signed into the team (N5C88K4XGC is HAPPIHACK STUDIOS, LLC). `xcrun devicectl list devices` gives the udid. The stock simulator slice is x86_64 only and iOS 26+
simulators will not run it: test on a device. Status and findings: "iOS PORT" in
`implementation_phases.md`.

## Sound

All sounds are currently placeholders generated in code (`scripts/audio/sound_synth.gd`).
To replace one, put a file named after its id in `assets/audio/sfx/` — e.g.
`assets/audio/sfx/thud.wav` (or `.ogg`). Ids: `thud`, `plip`, `rustle`, `click`, `knock`,
`crackle`, `hum`, `chirp`, `chirp_2`, `chirp_3`, `ui_open`, `ui_tap`, `ui_close`, `wind` (loop). Levels and
haptic strengths are in `data/configuration/feedback_config.tres`.

## The look

The UI is drawn by hand (bible §28.5): the main menu is the painted lid of the box, the HUD is
chalk over the world, menus and cards are sheets of paper. It is built in code, in three places:

- `scripts/ui/ui_theme.gd` (`UITheme`): the fonts (`assets/fonts/`: Caveat Brush, Patrick Hand,
  Kalam — SIL OFL), the inks and surfaces (`CHALK`, `INK`, `PAPER`, `LID`…), the sizes, the theme.
- `scripts/ui/hand_draw.gd` (`HandDraw`): wobbly circles and boxes, paper with tape and ruled
  lines, hatching, the tilt of a control — everything settled by a seed, so it looks the same each frame.
- `scripts/ui/hand_icons.gd` (`HandIcons`): the icons as SVG strokes, rasterised when first asked
  for at a size, coloured when drawn. To add one, add its paths to `PATHS`.

To tune the look: the chalk width is `UITheme.CHALK_WIDTH`, the font sizes are the `FONT_*`
constants, the colours are the constants at the top of `ui_theme.gd`.

The world inside the box has one palette: `scripts/rendering/palette.gd` (`Palette`), 36 base
colours in families (wood, foliage, earth, stone, made things, bright, water) plus the shades
the shapes use, and the people's skin, hair and cloth. The mesh libraries, the terrain palette's
defaults and the box frame alias it; nothing else names a world colour. Blender reads the same
colours from `docs/wiab_palette.gpl`, written by
`godot --headless --path . -s res://tests/tools/palette_gpl.gd` (a test fails when it is stale).
The art decisions behind this: `docs/art_assets.md` §5.

## Project layout

See `implementation_phases.md` Part D. Key folders: `scripts/` (code by system), `scenes/`, `data/configuration/` (all tunables), `tests/`.
